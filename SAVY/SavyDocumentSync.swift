import Combine
import CoreFoundation
import Foundation

// MARK: - Values

/// A JSON value that compares numbers by value, so a record read back from the gateway equals
/// the record this device wrote even when the server returns a different number spelling.
enum SyncJSON: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SyncJSON])
    case object([String: SyncJSON])

    struct Unsupported: Error {}

    init(any value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(try array.map(SyncJSON.init(any:)))
        case let object as [String: Any]:
            self = .object(try object.mapValues(SyncJSON.init(any:)))
        default:
            throw Unsupported()
        }
    }

    /// Whole numbers are written as integers so `Int` fields decode after a round trip.
    var anyValue: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): NSNumber(value: value)
        case .number(let value):
            value.rounded() == value && abs(value) < 9e15 ? NSNumber(value: Int64(value)) : NSNumber(value: value)
        case .string(let value): value
        case .array(let values): values.map(\.anyValue)
        case .object(let values): values.mapValues(\.anyValue)
        }
    }

    static func encode<T: Encodable>(_ value: T) throws -> SyncJSON {
        let data = try JSONEncoder.recall.encode(value)
        return try SyncJSON(any: JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: anyValue, options: [.fragmentsAllowed])
        return try JSONDecoder.recall.decode(type, from: data)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([SyncJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: SyncJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var stringArray: [String]? {
        guard case .array(let values) = self else { return nil }
        return values.compactMap(\.stringValue)
    }
}

/// One entry of a synced document. The gateway keeps whichever copy has the later `modifiedAt`
/// and keeps its own copy on a tie.
struct SyncEntry: Codable, Equatable, Sendable {
    var value: SyncJSON?
    var modifiedAt: Double
    var deleted: Bool

    var wireValue: [String: Any] {
        ["value": value?.anyValue ?? NSNull(), "modifiedAt": modifiedAt, "deleted": deleted]
    }

    init(value: SyncJSON?, modifiedAt: Double, deleted: Bool) {
        self.value = value
        self.modifiedAt = modifiedAt
        self.deleted = deleted
    }

    init?(wire: Any) {
        guard let object = wire as? [String: Any],
              let modifiedAt = (object["modifiedAt"] as? NSNumber)?.doubleValue,
              let deleted = object["deleted"] as? Bool else { return nil }
        let value = deleted ? nil : (object["value"]).flatMap { try? SyncJSON(any: $0) }
        self.init(value: value, modifiedAt: modifiedAt, deleted: deleted)
    }
}

// MARK: - Adapters

struct SyncStamp: Equatable {
    var modifiedAt: Double
    var uploads: Bool
}

enum SyncChangeContext {
    /// The first time this device records the document, before it has ever synced it.
    case firstRun(legacyDevice: Bool)
    case change(previous: SyncEntry?, now: Double)
}

/// Connects one local store to one synced document.
@MainActor
protocol SavySyncAdapter: AnyObject {
    var documentKey: String { get }
    /// False while the local source could not be read; the document is then left untouched.
    var isReady: Bool { get }
    var localChanges: AnyPublisher<Void, Never> { get }
    func snapshot() -> [String: SyncJSON]
    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp
    /// Replaces the local records with the merged document's live entries.
    func apply(_ values: [String: SyncJSON])
    /// Stores with fallible writes can refuse acknowledgement until local persistence succeeds.
    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool
}

extension SavySyncAdapter {
    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool {
        apply(values)
        return true
    }
}

extension SyncChangeContext {
    /// A change made on this device is stamped with its time, strictly after anything it replaces.
    static func stampAfter(_ previous: SyncEntry?, now: Double) -> Double {
        max(now, (previous?.modifiedAt ?? 0) + 0.001)
    }
}

// MARK: - Document state

struct SavySyncShadow: Codable, Equatable {
    var entries: [String: SyncEntry] = [:]
    var pending: Set<String> = []
    var initialized = false

    var liveValues: [String: SyncJSON] {
        entries.reduce(into: [:]) { result, pair in
            if !pair.value.deleted, let value = pair.value.value { result[pair.key] = value }
        }
    }

    var pendingEntries: [String: SyncEntry] {
        pending.reduce(into: [:]) { result, key in
            if let entry = entries[key] { result[key] = entry }
        }
    }
}

/// Tracks what this device last knew about one document, which local differences still need
/// uploading, and folds the server's copy back into the local store.
@MainActor
final class SavySyncDocument {
    let adapter: any SavySyncAdapter
    private(set) var shadow: SavySyncShadow
    private let fileURL: URL

    /// A source that suddenly reads empty is treated as unreadable rather than as a mass deletion.
    static let emptySnapshotGuard = 4

    init(adapter: any SavySyncAdapter, directory: URL) {
        self.adapter = adapter
        fileURL = directory.appendingPathComponent("\(adapter.documentKey).json")
        shadow = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(SavySyncShadow.self, from: $0) }
            ?? SavySyncShadow()
        // After an unreadable local file, forget what was synced: the next readable launch merges
        // with the shared copy instead of recording every missing record as a deletion.
        if !adapter.isReady {
            shadow = SavySyncShadow()
            save()
        }
    }

    @discardableResult
    func recordLocalChanges(now: Double, legacyDevice: Bool) -> Bool {
        guard adapter.isReady else { return false }
        let current = adapter.snapshot()
        let firstRun = !shadow.initialized
        let liveKnown = shadow.entries.filter { !$0.value.deleted }
        if !firstRun, current.isEmpty, liveKnown.count >= Self.emptySnapshotGuard { return false }

        var next = shadow
        for (key, value) in current {
            let previous = shadow.entries[key]
            if let previous, !previous.deleted, previous.value == value { continue }
            let context: SyncChangeContext = firstRun
                ? .firstRun(legacyDevice: legacyDevice)
                : .change(previous: previous, now: now)
            let stamp = adapter.stamp(key: key, value: value, context: context)
            next.entries[key] = SyncEntry(value: value, modifiedAt: stamp.modifiedAt, deleted: false)
            if stamp.uploads { next.pending.insert(key) } else { next.pending.remove(key) }
        }
        for (key, previous) in liveKnown where current[key] == nil {
            next.entries[key] = SyncEntry(value: nil, modifiedAt: SyncChangeContext.stampAfter(previous, now: now), deleted: true)
            next.pending.insert(key)
        }
        next.initialized = true
        guard next != shadow else { return false }
        shadow = next
        save()
        return true
    }

    /// The server's entry wins when it is newer or equally new: on a tie the server kept its own.
    @discardableResult
    func absorb(_ remote: [String: SyncEntry]) -> Bool {
        guard adapter.isReady else { return false }
        var next = shadow
        for (key, incoming) in remote {
            if let current = next.entries[key], incoming.modifiedAt < current.modifiedAt { continue }
            next.entries[key] = incoming
            next.pending.remove(key)
        }
        next.initialized = true
        guard next != shadow else { return false }
        let valuesChanged = next.liveValues != shadow.liveValues
        // Keep the last confirmed shadow on a failed local write. Otherwise the next
        // snapshot would treat stale local content as a new edit and upload it again.
        if valuesChanged, !adapter.applyAndConfirm(next.liveValues) { return false }
        shadow = next
        save()
        return valuesChanged
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(shadow) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Transport

enum SavyDocumentSyncError: Error, Equatable {
    /// The gateway or database does not offer document sync yet.
    case unavailable
    case notSignedIn
    case badResponse
}

protocol SavyDocumentSyncClient: Sendable {
    func fetchDocuments() async throws -> [String: [String: SyncEntry]]
    func merge(key: String, entries: [String: SyncEntry]) async throws -> [String: SyncEntry]
}

struct GatewayDocumentSyncClient: SavyDocumentSyncClient {
    let accessToken: @Sendable () async -> String?
    let email: String?

    private func client() async throws -> (AWSGraphClient, String) {
        guard let client = AWSGraphClient.fromBundleConfiguration() else { throw SavyDocumentSyncError.unavailable }
        guard let token = await accessToken() else { throw SavyDocumentSyncError.notSignedIn }
        return (client, token)
    }

    func fetchDocuments() async throws -> [String: [String: SyncEntry]] {
        let (client, token) = try await client()
        return try await client.fetchSyncDocuments(accessToken: token)
    }

    func merge(key: String, entries: [String: SyncEntry]) async throws -> [String: SyncEntry] {
        let (client, token) = try await client()
        return try await client.mergeSyncDocument(key: key, entries: entries, email: email, accessToken: token)
    }
}

extension AWSGraphClient {
    func fetchSyncDocuments(accessToken: String) async throws -> [String: [String: SyncEntry]] {
        let object = try await sendDocumentRequest(authorizedRequest(path: "v1/documents", accessToken: accessToken))
        guard let documents = object["documents"] as? [[String: Any]] else { throw SavyDocumentSyncError.badResponse }
        return documents.reduce(into: [:]) { result, document in
            guard let key = document["key"] as? String else { return }
            result[key] = Self.syncEntries(document["entries"])
        }
    }

    func mergeSyncDocument(
        key: String,
        entries: [String: SyncEntry],
        email: String?,
        accessToken: String
    ) async throws -> [String: SyncEntry] {
        var request = authorizedRequest(path: "v1/documents", method: "POST", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["key": key, "entries": entries.mapValues(\.wireValue)]
        if let email { body["email"] = email }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let object = try await sendDocumentRequest(request)
        guard let document = object["document"] as? [String: Any] else { throw SavyDocumentSyncError.badResponse }
        return Self.syncEntries(document["entries"])
    }

    private func sendDocumentRequest(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SavyDocumentSyncError.badResponse }
        if http.statusCode == 404 || http.statusCode == 503 { throw SavyDocumentSyncError.unavailable }
        if http.statusCode == 401 { throw SavyDocumentSyncError.notSignedIn }
        guard (200..<300).contains(http.statusCode) else {
            throw AWSGraphClientError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SavyDocumentSyncError.badResponse
        }
        return object
    }

    private static func syncEntries(_ value: Any?) -> [String: SyncEntry] {
        guard let object = value as? [String: Any] else { return [:] }
        return object.reduce(into: [:]) { result, pair in
            if let entry = SyncEntry(wire: pair.value) { result[pair.key] = entry }
        }
    }
}

// MARK: - Coordinator

/// Keeps records that used to live only on this device in step with every other signed-in copy of
/// SAVY. Local changes are stamped as they settle; each pass pulls the server's documents, folds
/// them in, then uploads whatever is still pending.
@MainActor
final class SavyDocumentSync: ObservableObject {
    enum Status: Equatable {
        case idle, syncing, live(Date), unavailable, failed
    }

    @Published private(set) var status: Status = .idle

    private let documents: [SavySyncDocument]
    private let client: any SavyDocumentSyncClient
    private let legacyDevice: Bool
    private var cancellables: Set<AnyCancellable> = []
    private var isSyncing = false
    private var needsAnotherPass = false
    private var started = false

    init(
        adapters: [any SavySyncAdapter],
        client: any SavyDocumentSyncClient,
        directory: URL = SavyDocumentSync.defaultDirectory,
        legacyDevice: Bool
    ) {
        documents = adapters.map { SavySyncDocument(adapter: $0, directory: directory) }
        self.client = client
        self.legacyDevice = legacyDevice
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY/Sync", isDirectory: true)
    }

    func start() async {
        guard !started else { return }
        started = true
        recordAll()
        for document in documents {
            document.adapter.localChanges
                .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.localChangesSettled() }
                }
                .store(in: &cancellables)
        }
        await syncNow()
    }

    func syncNow() async {
        guard started else { return }
        guard !isSyncing else {
            needsAnotherPass = true
            return
        }
        isSyncing = true
        repeat {
            needsAnotherPass = false
            await performPass()
        } while needsAnotherPass
        isSyncing = false
    }

    private func localChangesSettled() {
        recordAll()
        guard documents.contains(where: { !$0.shadow.pending.isEmpty }) else { return }
        Task { await syncNow() }
    }

    private func performPass() async {
        recordAll()
        if case .live = status {} else { status = .syncing }
        do {
            let remote = try await client.fetchDocuments()
            for document in documents {
                if let entries = remote[document.adapter.documentKey] { document.absorb(entries) }
            }
            for document in documents {
                let pending = document.shadow.pendingEntries
                guard !pending.isEmpty else { continue }
                document.absorb(try await client.merge(key: document.adapter.documentKey, entries: pending))
            }
            status = .live(Date())
        } catch SavyDocumentSyncError.unavailable {
            status = .unavailable
        } catch {
            status = .failed
        }
    }

    private func recordAll() {
        let now = Date().timeIntervalSince1970
        for document in documents {
            document.recordLocalChanges(now: now, legacyDevice: legacyDevice)
        }
    }
}

/// The access token for gateway calls. Amplify refreshes the Cognito session on demand, so a
/// long-running copy (the Mac app stays open for days) keeps syncing after the first token expires.
final class SavyAccessTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var token: String

    init(initial: String) {
        token = initial
    }

    var current: String {
        lock.withLock { token }
    }

    @discardableResult
    func refresh() async -> String {
        if let fresh = await AmplifyAuthService.freshAccessToken() {
            lock.withLock { token = fresh }
            return fresh
        }
        return current
    }
}
