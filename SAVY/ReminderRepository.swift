import Foundation

/// The seam the reminder system codes against. Re_Call backed this with Supabase over URLSession;
/// SAVY's `AWSGraphClient` will back a reminder repository here — a one-type change behind this seam.
/// `Sendable` so `ReminderStore` (a `@MainActor` type) can `await` it without sending shared
/// mutable state across the actor boundary — required by Swift 6 strict concurrency.
protocol ReminderRepository: Sendable {
    func ensureReady() async -> Bool
    func fetchAll() async throws -> [Reminder]
    func upsert(_ reminder: Reminder) async throws
    func delete(id: UUID) async throws
}

/// On-device-only repository. `ReminderStore` is local-first: it writes to its JSON cache before it
/// ever touches a backend. Reporting "not ready" here means `bootstrap()` is a no-op and each
/// `save` simply stays local — every create/edit works with no network coupling. `fetchAll` throws
/// (rather than returning `[]`) so that if `refresh()` is ever called the local cache is preserved.
struct LocalReminderRepository: ReminderRepository {
    enum LocalOnly: Error { case noBackendYet }

    func ensureReady() async -> Bool { false }
    func fetchAll() async throws -> [Reminder] { throw LocalOnly.noBackendYet }
    func upsert(_ reminder: Reminder) async throws { throw LocalOnly.noBackendYet }
    func delete(id: UUID) async throws { throw LocalOnly.noBackendYet }
}
