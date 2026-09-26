import Foundation
import SwiftUI

/// Local-first source of truth: every change writes to the on-device cache immediately (so a
/// reminder is never lost), then syncs to the backend. Unsynced rows are retried on launch.
@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [Reminder] = []
    @Published var lastSyncFailed = false

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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheURL = cacheURL ?? dir.appendingPathComponent("reminders.json")
        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS") {
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

    var technicalCaptures: [TechnicalCapture] {
        technicalCaptureStore.captures
    }

    var candidateOutboxItems: [CowboyCandidateOutboxItem] {
        candidateOutbox.items
    }

    var syncStatusLabel: String {
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
            let number = allocator.number(for: .reminder, id: reminders[index].id, savedNumber: reminders[index].postNumber)
            if reminders[index].postNumber != number {
                reminders[index].postNumber = number
                if syncNewAssignments { reminders[index].needsSync = true }
                changed = true
            }
        }
        if changed { saveCache() }
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
            reminders = merged
            assignPostNumbers()
            saveCache()
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

    func save(_ reminder: Reminder) {
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
        upsertLocal(r)
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
    }

    func complete(_ reminder: Reminder) {
        var r = reminder
        r.status = .completed
        r.completedAt = Date()
        NotificationScheduler.cancel(r)
        save(r)
    }

    func uncomplete(_ reminder: Reminder) {
        var r = reminder
        r.status = .active
        r.completedAt = nil
        save(r)
    }

    func togglePin(_ reminder: Reminder) {
        guard let idx = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        var r = reminders[idx]
        r.pinned.toggle()
        r.updatedAt = Date()
        r.needsSync = true
        reminders[idx] = r

        if r.pinned {
            applyBlockOrder(active.filter { !$0.pinned })
            var pinned = active.filter { $0.pinned }
            pinned.removeAll { $0.id == r.id }
            pinned.insert(reminders[idx], at: 0)
            applyBlockOrder(pinned)
        } else {
            applyBlockOrder(active.filter { $0.pinned })
            var unpinned = active.filter { !$0.pinned }
            unpinned.removeAll { $0.id == r.id }
            unpinned.insert(reminders[idx], at: 0)
            applyBlockOrder(unpinned)
        }
        // Pinning a sole item may leave every rank unchanged. Persist and sync the
        // pin itself even when neither applyBlockOrder call has anything to save.
        saveCache()
        if let updated = reminders.first(where: { $0.id == r.id }) {
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
        var touched: [Reminder] = []
        for item in ordered {
            guard let idx = reminders.firstIndex(where: { $0.id == item.id }) else { continue }
            guard reminders[idx].upNextOrder != item.rank else { continue }
            var r = reminders[idx]
            r.upNextOrder = item.rank
            r.updatedAt = Date()
            r.needsSync = true
            reminders[idx] = r
            touched.append(r)
        }
        guard !touched.isEmpty else { return }
        saveCache()
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
        upsertLocal(r)
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
        guard await repo.ensureReady() else { lastSyncFailed = true; return }
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

    private func upsertLocal(_ r: Reminder) {
        if let idx = reminders.firstIndex(where: { $0.id == r.id }) { reminders[idx] = r }
        else { reminders.append(r) }
        saveCache()
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
                reminder.createdAt = localCopy.createdAt
                reminder.whenIAm = reminder.whenIAm ?? localCopy.whenIAm
                reminder.marksClearSignOfSuccess = reminder.marksClearSignOfSuccess ?? localCopy.marksClearSignOfSuccess
                reminder.marksCompounding = reminder.marksCompounding ?? localCopy.marksCompounding
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
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder.recall.decode([Reminder].self, from: data) else { return }
        reminders = decoded
    }

    private func saveCache() {
        if let data = try? JSONEncoder.recall.encode(reminders) {
            try? data.write(to: cacheURL, options: .atomic)
        }
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
