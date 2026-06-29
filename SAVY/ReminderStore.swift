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

    // SAVY runs the reminder system on-device first, then syncs through GatewayReminderRepository.
    init(repo: ReminderRepository = LocalReminderRepository()) {
        self.repo = repo
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("reminders.json")
        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS") {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        loadCache()
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

    func bootstrap() async {
        guard await repo.ensureReady() else { return }
        await pushPending()
        await refresh()
    }

    func refresh() async {
        do {
            let remote = try await repo.fetchAll()
            let merged = mergeRemote(remote, withLocal: reminders)
            reminders = merged
            saveCache()
            reminders.forEach(NotificationScheduler.schedule)
        } catch {
            // Stay on the local cache; no intrusive error.
        }
    }

    func save(_ reminder: Reminder) {
        var r = reminder
        r.updatedAt = Date()
        r.needsSync = true
        upsertLocal(r)
        NotificationScheduler.schedule(r)
        Task { await sync(r) }
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
    }

    enum UpNextMoveDirection { case up, down }

    /// Move one step within the reminder's pinned/unpinned block.
    func moveUpNext(_ reminder: Reminder, direction: UpNextMoveDirection) {
        let feed = active
        let blockPinned = reminder.pinned
        var block = feed.filter { $0.pinned == blockPinned }
        guard let blockIdx = block.firstIndex(where: { $0.id == reminder.id }) else { return }

        let target: Int
        switch direction {
        case .up: target = blockIdx - 1
        case .down: target = blockIdx + 1
        }
        guard block.indices.contains(target) else { return }

        block.swapAt(blockIdx, target)
        applyBlockOrder(block)
    }

    private func applyBlockOrder(_ ordered: [Reminder]) {
        var touched: [Reminder] = []
        for (i, item) in ordered.enumerated() {
            guard let idx = reminders.firstIndex(where: { $0.id == item.id }) else { continue }
            guard reminders[idx].upNextOrder != i else { continue }
            var r = reminders[idx]
            r.upNextOrder = i
            r.updatedAt = Date()
            r.needsSync = true
            reminders[idx] = r
            touched.append(r)
        }
        guard !touched.isEmpty else { return }
        saveCache()
        for r in touched {
            NotificationScheduler.schedule(r)
            Task { await sync(r) }
        }
    }

    func delete(_ reminder: Reminder) {
        var r = reminder
        r.status = .deleted
        r.updatedAt = Date()
        r.needsSync = true
        upsertLocal(r)
        NotificationScheduler.cancel(reminder)
        Task { await sync(r) }
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
            guard let localCopy = local.first(where: { $0.id == incoming.id }) else { return incoming }
            var reminder = incoming

            if localCopy.needsSync {
                reminder = localCopy
                if reminder.imageLocalPath == nil {
                    reminder.imageLocalPath = localCopy.imageLocalPath
                }
                return reminder
            }

            if reminder.imageLocalPath == nil {
                reminder.imageLocalPath = localCopy.imageLocalPath
            }
            return reminder
        }

        // Keep local rows that haven't synced yet; they win over the remote copy.
        for u in local where u.needsSync {
            if let idx = merged.firstIndex(where: { $0.id == u.id }) { merged[idx] = u }
            else { merged.append(u) }
        }

        return merged
    }

    // MARK: - cache

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
}
