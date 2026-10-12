import Foundation
import SwiftUI

/// Local-first source of truth: every change writes to the on-device cache immediately (so a
/// reminder is never lost), then syncs to the backend. Unsynced rows are retried on launch.
@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [Reminder] = []
    @Published var lastSyncFailed = false
    private(set) var loadFailed = false
    private(set) var lastWriteFailed = false
    private var confirmedReminders: [Reminder] = []

    private let repo: ReminderRepository
    private let cacheURL: URL
    private let technicalCaptureStore: TechnicalCaptureStore
    private let candidateOutbox: CowboyCandidateOutbox
    private let candidateClient: any CowboyCandidateSubmitting
    private var postNumberAllocator: PostNumberAllocator?

    // SAVY runs the reminder system on-device first, then syncs through GatewayReminderRepository.
    init(
        repo: ReminderRepository = LocalReminderRepository(),
        cacheURL: URL? = nil,
        technicalCaptureStore: TechnicalCaptureStore = .live(),
        candidateOutbox: CowboyCandidateOutbox = .live(),
        candidateClient: any CowboyCandidateSubmitting = CowboyCandidateClient()
    ) {
        self.repo = repo
        self.technicalCaptureStore = technicalCaptureStore
        self.candidateOutbox = candidateOutbox
        self.candidateClient = candidateClient
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.cacheURL = cacheURL ?? dir.appendingPathComponent("reminders.json")
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SAVYUITests", isDirectory: true)
        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED"),
           ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS"),
           self.cacheURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            == testDirectory.resolvingSymlinksInPath().standardizedFileURL.path {
            try? FileManager.default.removeItem(at: self.cacheURL)
        }
        loadCache()
        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_DEMO_REMINDERS"), reminders.isEmpty {
            reminders = Self.uiTestDemoReminders
            saveCache()
        }
        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_SEED_REORDER_ACTIONS") {
            seedActionsForReorderUITesting()
        }
    }

    var active: [Reminder] {
        reminders.filter { $0.status == .active }
            .sorted { compareUpNext($0, $1) }
    }

    var pinnedFeed: [Reminder] {
        active.filter(\.pinned)
    }

    var pendingSyncCount: Int {
        reminders.filter(\.needsSync).count
    }

    /// A damaged source stays intact and cannot be treated as an empty cloud collection.
    var canSync: Bool { !loadFailed }

    var technicalCaptures: [TechnicalCapture] {
        technicalCaptureStore.captures
    }

    var candidateOutboxItems: [CowboyCandidateOutboxItem] {
        candidateOutbox.items
    }

    var syncStatusLabel: String {
        if repo is LocalReminderRepository {
            return "local"
        }
        if lastSyncFailed {
            return "failed"
        }
        if pendingSyncCount > 0 {
            return "pending (\(pendingSyncCount))"
        }
        return "live"
    }

    /// Pinned block first; within each block, manual order then date fallback.
    private func compareUpNext(_ lhs: Reminder, _ rhs: Reminder) -> Bool {
        if lhs.pinned != rhs.pinned { return lhs.pinned }
        return compareWithinBlock(lhs, rhs)
    }

    private func compareWithinBlock(_ lhs: Reminder, _ rhs: Reminder) -> Bool {
        switch (lhs.upNextOrder, rhs.upNextOrder) {
        case let (l?, r?): return l < r
        case (nil, nil): return sortKey(lhs) < sortKey(rhs)
        case (_?, nil): return true
        case (nil, _?): return false
        }
    }
    var completed: [Reminder] {
        reminders.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    private func sortKey(_ r: Reminder) -> Date { r.fireDate ?? r.createdAt }

    /// Numbering is metadata: keep the user's text and original timestamps, and avoid the
    /// candidate-capture pipeline. Refresh merges current cloud content before uploading
    /// numbering metadata, so an old clean cache cannot overwrite a newer remote edit.
    func configurePostNumbering(_ allocator: PostNumberAllocator) {
        postNumberAllocator = allocator
        assignPostNumbers(syncNewAssignments: false)
    }

    private func assignPostNumbers(syncNewAssignments: Bool = true) {
        guard let allocator = postNumberAllocator else { return }
        allocator.seed(reminders: reminders, socialPosts: [])
        var changed = false
        for index in reminders.indices where reminders[index].kind == .post && reminders[index].status != .deleted {
            let number = allocator.numberPreservingSavedReference(for: .reminder, id: reminders[index].id, savedNumber: reminders[index].postNumber)
            if reminders[index].postNumber != number {
                reminders[index].postNumber = number
                if syncNewAssignments { reminders[index].needsSync = true }
                changed = true
            }
        }
        if changed { _ = saveCache() }
    }

    func bootstrap() async {
        // Pending requests survive termination; reconcile saved edits and bounded hourly
        // windows on launch even when this store is operating without a gateway.
        reminders.forEach(NotificationScheduler.schedule)
        await flushCandidateOutbox()
        guard await repo.ensureReady() else { return }
        await pushPending()
        await refresh()
    }

    func refresh() async {
        do {
            let remote = try await repo.fetchAll()
            let previous = reminders
            // A fetched record's existing number must be reserved before an unnumbered
            // record in the same response can consume the next number.
            postNumberAllocator?.seed(reminders: remote.filter { ($0.postNumber ?? 0) > 0 }, socialPosts: [])
            let merged = mergeRemote(remote, withLocal: reminders)
            guard persist(merged) else { return }
            assignPostNumbers()
            let retainedIDs = Set(reminders.map(\.id))
            for removed in previous where !retainedIDs.contains(removed.id) {
                NotificationScheduler.cancel(removed)
            }
#if canImport(UIKit)
            for old in previous where old.schedule?.calendarIdentifier != nil {
                let current = reminders.first { $0.id == old.id }
                if current != old {
                    await CalendarScheduleBridge.shared.reconcileSynced(previous: old, current: current)
                }
            }
#endif
            reminders.forEach(NotificationScheduler.schedule)
            // Migrate retained local Schedule/Post fields through normal sync after
            // merging the latest server content, so migration cannot overwrite it.
            await pushPending()
        } catch {
            // Stay on the local cache; no intrusive error.
        }
    }

    @discardableResult
    func save(_ reminder: Reminder) -> Bool {
        guard !loadFailed else { return false }
        var r = reminder
        let existing = reminders.first { $0.id == r.id }
        if r.schedule != nil || r.scheduleSyncVersion != nil
            || existing?.schedule != nil || existing?.scheduleSyncVersion != nil {
            r.scheduleSyncVersion = 1
        }
        let savedNumber = reminders.first { $0.id == r.id }?.postNumber ?? r.postNumber
        r.postNumber = r.kind == .post
            ? postNumberAllocator?.number(for: .reminder, id: r.id, savedNumber: savedNumber) ?? savedNumber
            : savedNumber
        r.updatedAt = Date()
        r.needsSync = true
        guard upsertLocal(r) else { return false }
        enqueueCandidateCapture(for: r)
        NotificationScheduler.schedule(r)
        Task {
#if canImport(UIKit)
            if r.status != .active || (existing != nil && existing?.status != r.status) {
                // Resolve the latest row when this task runs. A later completion,
                // deletion, or reopening must supersede an older queued Calendar edit.
                let current = reminders.first { $0.id == r.id }
                await CalendarScheduleBridge.shared.reconcileSynced(previous: existing ?? r, current: current)
            }
#endif
            await sync(r)
            await flushCandidateOutbox()
        }
        return true
    }

    func complete(_ reminder: Reminder) {
        var r = reminder
        r.status = .completed
        r.completedAt = Date()
        if save(r) { NotificationScheduler.cancel(r) }
    }

    func uncomplete(_ reminder: Reminder) {
        var r = reminder
        r.status = .active
        r.completedAt = nil
        save(r)
    }

    func togglePin(_ reminder: Reminder) {
        guard let idx = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        var next = reminders
        var r = reminders[idx]
        r.pinned.toggle()
        r.updatedAt = Date()
        r.needsSync = true
        next[idx] = r

        var ordered: [(id: UUID, rank: Int)] = []
        let nextActive = next.filter { $0.status == .active }.sorted { compareUpNext($0, $1) }
        if r.pinned {
            ordered += nextActive.filter { !$0.pinned }.enumerated().map { ($0.element.id, $0.offset) }
            var pinned = nextActive.filter { $0.pinned }
            pinned.removeAll { $0.id == r.id }
            pinned.insert(r, at: 0)
            ordered += pinned.enumerated().map { ($0.element.id, $0.offset) }
        } else {
            ordered += nextActive.filter { $0.pinned }.enumerated().map { ($0.element.id, $0.offset) }
            var unpinned = nextActive.filter { !$0.pinned }
            unpinned.removeAll { $0.id == r.id }
            unpinned.insert(r, at: 0)
            ordered += unpinned.enumerated().map { ($0.element.id, $0.offset) }
        }
        var touched = Set([r.id])
        for item in ordered {
            guard let index = next.firstIndex(where: { $0.id == item.id }), next[index].upNextOrder != item.rank else { continue }
            next[index].upNextOrder = item.rank
            next[index].updatedAt = Date()
            next[index].needsSync = true
            touched.insert(item.id)
        }
        guard persist(next) else { return }
        for updated in next where touched.contains(updated.id) {
            Task { await sync(updated) }
        }
    }

    enum UpNextMoveDirection { case up, down }

    /// Move to the adjacent visible card of the same kind and pin state. Other kinds
    /// keep their places in the shared feed rather than consuming an invisible move.
    func moveUpNext(_ reminder: Reminder, direction: UpNextMoveDirection) {
        guard let current = reminders.first(where: { $0.id == reminder.id }),
              current.status == .active else { return }
        var block = active.filter { $0.pinned == current.pinned }
        let visibleIndices = block.indices.filter { block[$0].kind == current.kind }
        guard let visibleIndex = visibleIndices.firstIndex(where: { block[$0].id == current.id }) else { return }

        let target: Int
        switch direction {
        case .up: target = visibleIndex - 1
        case .down: target = visibleIndex + 1
        }
        guard visibleIndices.indices.contains(target) else { return }

        let sourceIndex = visibleIndices[visibleIndex]
        let targetIndex = visibleIndices[target]
        let ranks = block.compactMap(\.upNextOrder)
        if ranks.count == block.count, Set(ranks).count == block.count {
            // Existing valid ranks can be exchanged directly. Hidden items retain
            // even non-contiguous ranks, timestamps, sync state, and saved content.
            applyOrderMetadata([
                (block[sourceIndex].id, ranks[targetIndex]),
                (block[targetIndex].id, ranks[sourceIndex]),
            ])
        } else {
            // Older caches may have no ranks or duplicate ranks. Establish ranks
            // from the current display while preserving the hidden cards' slots.
            block.swapAt(sourceIndex, targetIndex)
            applyBlockOrder(block)
        }
    }

    private func applyBlockOrder(_ ordered: [Reminder]) {
        applyOrderMetadata(ordered.enumerated().map { ($0.element.id, $0.offset) })
    }

    private func applyOrderMetadata(_ ordered: [(id: UUID, rank: Int)]) {
        var next = reminders
        var touched: [Reminder] = []
        for item in ordered {
            guard let idx = next.firstIndex(where: { $0.id == item.id }) else { continue }
            guard next[idx].upNextOrder != item.rank else { continue }
            var r = next[idx]
            r.upNextOrder = item.rank
            r.updatedAt = Date()
            r.needsSync = true
            next[idx] = r
            touched.append(r)
        }
        guard !touched.isEmpty else { return }
        guard persist(next) else { return }
        for r in touched {
            Task { await sync(r) }
        }
    }

    func delete(_ reminder: Reminder) {
        let previous = reminders.first { $0.id == reminder.id } ?? reminder
        var r = reminder
        r.postNumber = reminders.first { $0.id == r.id }?.postNumber ?? r.postNumber
        r.status = .deleted
        r.updatedAt = Date()
        r.needsSync = true
        guard upsertLocal(r) else { return }
        NotificationScheduler.cancel(reminder)
        Task {
#if canImport(UIKit)
            let current = reminders.first { $0.id == r.id }
            await CalendarScheduleBridge.shared.reconcileSynced(previous: previous, current: current)
#endif
            await sync(r)
        }
    }

    func recentClearSignEntries(limit: Int) -> [TechnicalCapture] {
        technicalCaptureStore.recentClearSignEntries(limit: limit)
    }

    func recentCompoundEntries(limit: Int) -> [TechnicalCapture] {
        technicalCaptureStore.recentCompoundEntries(limit: limit)
    }

    func recentClearSignOrCompoundEntries(limit: Int) -> [TechnicalCapture] {
        technicalCaptureStore.recentClearSignOrCompoundEntries(limit: limit)
    }

    func pinnedHomepageEntries(limit: Int) -> [Reminder] {
        Array(pinnedFeed.prefix(limit))
    }

    // MARK: - sync

    private func sync(_ r: Reminder) async {
        guard await repo.ensureReady() else {
            lastSyncFailed = !(repo is LocalReminderRepository)
            return
        }
        do {
            if r.status == .deleted {
                try await repo.delete(id: r.id)
                removeSyncedDelete(r.id, updatedAt: r.updatedAt)
            } else {
                try await repo.upsert(r)
                markSynced(r.id, updatedAt: r.updatedAt)
            }
            lastSyncFailed = false
        } catch {
            lastSyncFailed = true
        }
    }

    private func pushPending() async {
        for r in reminders where r.needsSync { await sync(r) }
    }

    private func enqueueCandidateCapture(for reminder: Reminder) {
        let existing = technicalCaptureStore.capture(forReminderID: reminder.id)
        let capture = TechnicalCapture.from(reminder: reminder, existing: existing)
        technicalCaptureStore.save(capture)
        candidateOutbox.enqueue(capture)
    }

    private func flushCandidateOutbox(now: Date = Date()) async {
        for item in candidateOutbox.dueItems(now: now) {
            do {
                let receipt = try await candidateClient.submit(item.payload)
                candidateOutbox.recordReceipt(itemID: item.id, receipt: receipt, now: now)
            } catch {
                candidateOutbox.recordFailure(
                    itemID: item.id,
                    message: error.localizedDescription,
                    now: now
                )
            }
        }
    }

    private func upsertLocal(_ r: Reminder) -> Bool {
        var next = reminders
        if let idx = next.firstIndex(where: { $0.id == r.id }) { next[idx] = r }
        else { next.append(r) }
        return persist(next)
    }

    private func markSynced(_ id: UUID, updatedAt: Date) {
        if let idx = reminders.firstIndex(where: { $0.id == id }) {
            guard reminders[idx].updatedAt == updatedAt else { return }
            reminders[idx].needsSync = false
            saveCache()
        }
    }

    private func removeSyncedDelete(_ id: UUID, updatedAt: Date) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }),
              reminders[idx].updatedAt == updatedAt,
              reminders[idx].status == .deleted else { return }
        reminders.remove(at: idx)
        saveCache()
    }

    private func mergeRemote(_ remote: [Reminder], withLocal local: [Reminder]) -> [Reminder] {
        var merged = remote.map { incoming -> Reminder in
            let localCopy = local.first(where: { $0.id == incoming.id })
            // A locally edited row still wins until its normal upload succeeds.
            // Schedule migration must not replace an offline edit with the server copy.
            if let localCopy, localCopy.needsSync { return localCopy }
            var reminder = ReminderScheduleSync.merging(remote: incoming, local: localCopy)
            guard let localCopy else { return reminder }

            if reminder.imageLocalPath == nil {
                reminder.imageLocalPath = localCopy.imageLocalPath
            }
            // Older gateways omit Post fields. Keep this device's saved context when
            // that happens; the marker must follow the answers it describes.
            if reminder.kind == .post {
                if let number = localCopy.postNumber, reminder.postNumber != number {
                    reminder.postNumber = number
                    reminder.needsSync = true
                }
            }
            // Creation is immutable identity metadata. Older gateways stamped first upload,
            // and an old parser stamped first fetch. Converge to the earliest known creation
            // through the normal gateway rather than retaining a different date on each device.
            if localCopy.createdAt < reminder.createdAt {
                reminder.createdAt = localCopy.createdAt
                reminder.needsSync = true
            }
            // Preserve omitted theme context for every kind; a kind change uses the remote payload.
            if reminder.kind == localCopy.kind {
                if reminder.whenIAm == nil, let value = localCopy.whenIAm {
                    reminder.whenIAm = value
                    reminder.needsSync = true
                }
                if reminder.marksClearSignOfSuccess == nil, let value = localCopy.marksClearSignOfSuccess {
                    reminder.marksClearSignOfSuccess = value
                    reminder.needsSync = true
                }
                if reminder.marksCompounding == nil, let value = localCopy.marksCompounding {
                    reminder.marksCompounding = value
                    reminder.needsSync = true
                }
                if reminder.postThemeID == nil { reminder.postThemeID = localCopy.postThemeID }
                if reminder.postThemeName == nil { reminder.postThemeName = localCopy.postThemeName }
                if reminder.postAnswers == nil {
                    reminder.postAnswers = localCopy.postAnswers
                    reminder.postAnswersContainQuestions = localCopy.postAnswersContainQuestions
                    if localCopy.postAnswers != nil { reminder.needsSync = true }
                }
            }
            return reminder
        }

        // Keep local rows that haven't synced yet; they win over the remote copy.
        for u in local where u.needsSync && !merged.contains(where: { $0.id == u.id }) {
            merged.append(u)
        }

        return merged
    }

    // MARK: - cache

    /// Synthetic actions stay inside the same isolated storage used by physical
    /// UI tests. No fixture is saved through the authoring/candidate pipeline.
    func seedActionsForReorderUITesting() {
        let arguments = ProcessInfo.processInfo.arguments
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SAVYUITests", isDirectory: true)
        guard arguments.contains("SAVY_UI_TEST_UNLOCKED"),
              arguments.contains("SAVY_UI_TEST_RESET_REMINDERS"),
              cacheURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
                == testDirectory.resolvingSymlinksInPath().standardizedFileURL.path else { return }
        let fixture: [(String, ReminderKind, Bool, Int)] = [
            ("Synthetic pinned action 1", .action, true, 0),
            ("Synthetic pinned action 2", .action, true, 2),
            ("Synthetic unpinned action 1", .action, false, 0),
            ("Synthetic unpinned action 2", .action, false, 2),
            ("Synthetic hidden pinned reminder", .reminder, true, 1),
            ("Synthetic hidden unpinned event", .event, false, 1),
        ]
        let fixtureIDs = fixture.indices.compactMap {
            UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", $0 + 1))
        }
        guard fixtureIDs.count == fixture.count else { return }
        reminders.removeAll { fixtureIDs.contains($0.id) }
        for (index, values) in fixture.enumerated() {
            var entry = Reminder()
            entry.id = fixtureIDs[index]
            entry.title = values.0
            entry.kind = values.1
            entry.pinned = values.2
            entry.upNextOrder = values.3
            entry.createdAt = Date(timeIntervalSince1970: 1_780_000_000 + Double(index * 60))
            entry.updatedAt = entry.createdAt
            reminders.append(entry)
        }
        saveCache()
    }

    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        do {
            let decoded = try JSONDecoder.recall.decode([Reminder].self, from: Data(contentsOf: cacheURL))
            guard Set(decoded.map(\.id)).count == decoded.count else { throw CocoaError(.fileReadCorruptFile) }
            reminders = decoded
            confirmedReminders = decoded
        } catch {
            loadFailed = true
            lastSyncFailed = true
        }
    }

    @discardableResult
    private func saveCache() -> Bool {
        let next = reminders
        guard persist(next) else {
            // Legacy metadata/isolated-fixture callers mutate an array before this boundary.
            reminders = confirmedReminders
            return false
        }
        return true
    }

    private func persist(_ next: [Reminder]) -> Bool {
        guard !loadFailed else { return false }
        do {
            guard Set(next.map(\.id)).count == next.count else { throw CocoaError(.fileWriteUnknown) }
            let data = try JSONEncoder.recall.encode(next)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: [.atomic])
            reminders = next
            confirmedReminders = next
            lastWriteFailed = false
            return true
        } catch {
            lastWriteFailed = true
            lastSyncFailed = true
            return false
        }
    }

    /// CloudKit imports are already merged by portable version. Gateway dirtiness must not
    /// override a newer received record, and receiving it must never re-enter save/capture.
    @discardableResult
    func applySynced(_ synced: [Reminder]) -> Bool {
        guard canSync else { return false }
        let previous = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
        let next = synced.map { incoming in
            var entry = ReminderScheduleSync.merging(remote: incoming, local: previous[incoming.id])
            entry.needsSync = false
            return entry
        }
        if next != reminders {
        guard persist(next) else { return false }
        let retainedIDs = Set(next.map(\.id))
        for removed in previous.values where !retainedIDs.contains(removed.id) {
            NotificationScheduler.cancel(removed)
        }
        for entry in next where previous[entry.id] != entry {
            NotificationScheduler.schedule(entry)
        }
        #if canImport(UIKit)
        let nextByID = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for local in previous.values where local.schedule?.calendarIdentifier != nil {
            let current = nextByID[local.id]
            if current != local {
                Task { @MainActor in
                    await CalendarScheduleBridge.shared.reconcileSynced(previous: local, current: current)
                }
            }
        }
        #endif
        }
        if let allocator = postNumberAllocator {
            for entry in next where entry.kind == .post {
                if let number = entry.postNumber,
                   !allocator.adopt(.reminder, id: entry.id, number: number) { return false }
            }
        }
        return true
    }

    /// Physical UI fixtures are written only into the unlocked test app's temporary cache.
    /// This never invokes save(_:), the gateway, or the Harness/candidate pipeline.
    func seedPostsForUITesting(count: Int) {
        let arguments = ProcessInfo.processInfo.arguments
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SAVYUITests", isDirectory: true)
        // Compare filesystem locations rather than URL base/directory representations.
        let cacheDirectoryPath = cacheURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        let testDirectoryPath = testDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        guard arguments.contains("SAVY_UI_TEST_UNLOCKED"),
              arguments.contains("SAVY_UI_TEST_RESET_REMINDERS"),
              cacheDirectoryPath == testDirectoryPath,
              count > 0 else { return }
        reminders.removeAll { $0.kind == .post }
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        for index in 0..<min(count, 50) {
            let theme = PostThemeCatalog.themes[index % PostThemeCatalog.themes.count]
            var entry = Reminder()
            entry.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
            entry.kind = .post
            entry.title = "New Post"
            entry.postThemeID = theme.id
            entry.postThemeName = theme.name
            entry.postAnswersContainQuestions = true
            entry.postAnswers = theme.questions.enumerated().map { questionIndex, question in
                let answer = questionIndex == 0
                    ? "Synthetic post \(index + 1) starts with a clear observation. This additional synthetic sentence gives a pinned post more detail without changing its first sentence."
                    : "Synthetic answer \(questionIndex + 1) for post \(index + 1)."
                return question.prompt + "\n\n" + answer
            }
            entry.notes = "Synthetic metadata for native UI verification."
            entry.outcome = "Synthetic outcome \(index + 1)"
            entry.tags = ["Synthetic", "Writing"]
            entry.pinned = index < 2
            entry.createdAt = start.addingTimeInterval(Double(index * 60))
            entry.updatedAt = entry.createdAt
            reminders.append(entry)
        }
        saveCache()
    }

    private static let uiTestDemoReminders: [Reminder] = {
        var active = Reminder(
            kind: .reminder,
            title: "One of the most productive days of my life.",
            listName: "Inspiration",
            context: .clearSign,
            status: .active
        )
        active.dueDate = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 25))
        active.dueTime = Calendar.current.date(from: DateComponents(hour: 20, minute: 24))

        var completedA = Reminder(
            kind: .reminder,
            title: "Check on clothes and dryer",
            status: .completed,
            completedAt: Date().addingTimeInterval(-86400 * 2)
        )
        var completedB = Reminder(
            kind: .reminder,
            title: "Review weekly priorities",
            status: .completed,
            completedAt: Date().addingTimeInterval(-86400)
        )
        return [active, completedA, completedB]
    }()
}
