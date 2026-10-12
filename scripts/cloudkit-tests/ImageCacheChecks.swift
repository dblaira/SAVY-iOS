import CloudKit
import Foundation

@main
struct ImageCacheChecks {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func main() {
        do { try run() }
        catch { print("FAILED image check: \(error)"); exit(1) }
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("savy-images-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SavyImageCache(directory: directory.appendingPathComponent("cache"))
        var passed = 0
        func check(_ value: Bool, _ description: String) throws {
            guard value else { throw Failure(description: description) }
            passed += 1
        }
        func rejects(_ description: String, _ operation: () throws -> Void,
                     matching: (any Error) -> Bool = { _ in true }) throws {
            do { try operation() }
            catch { try check(matching(error), "\(description): wrong error \(error)"); return }
            throw Failure(description: "\(description): operation succeeded")
        }
        func invalidFilename(_ error: any Error) -> Bool {
            if case SavyImageCache.Error.invalidFilename = error { return true }
            return false
        }
        func missingAsset(_ error: any Error) -> Bool {
            if case SavyCloudKitAssets.Error.missingAsset = error { return true }
            return false
        }
        func portable(_ document: String, _ value: SyncJSON?, deleted: Bool = false) -> SavyCloudRecord {
            SavyCloudRecord(id: SavyCloudRecordID(documentKey: document, key: "entry:fixture"),
                            entry: SyncEntry(value: value, modifiedAt: 42, deleted: deleted))
        }
        func cloudRecord(_ source: URL? = nil) -> CKRecord {
            let record = CKRecord(recordType: "SavyEntry")
            if let source { record["image"] = CKAsset(fileURL: source) }
            return record
        }
        let name = "B6421A2C-1263-49AB-82EE-82CAC02C2F31.jpg"
        // An asset is a byte-preserving transport; decoding/display remains UIKit's job.
        let bytes = Data([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x4a, 0x46, 0xff, 0xd9])
        let file = try cache.store(bytes, name: name)
        try check(file.lastPathComponent == name, "cache keeps UUID filename")
        try check(try Data(contentsOf: cache.existingFileURL(for: name)) == bytes, "cache keeps original bytes")
        let reopened = SavyImageCache(directory: cache.directory)
        try check(try Data(contentsOf: reopened.existingFileURL(for: name)) == bytes, "reopened cache keeps bytes")
        for badName in ["../outside.jpg", "/tmp/outside.jpg", "not-a-uuid.jpg", name + "/extra", name + ".png"] {
            try rejects("cache rejects \(badName)", { _ = try cache.store(bytes, name: badName) }, matching: invalidFilename)
        }
        let outside = directory.appendingPathComponent("outside.jpg")
        try bytes.write(to: outside)
        let symlinkName = "4ABBD4A3-CC1F-496A-A628-83206195A4AC.jpg"
        let symlink = cache.directory.appendingPathComponent(symlinkName)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        try rejects("cache rejects symlink reads", { _ = try cache.existingFileURL(for: symlinkName) }, matching: invalidFilename)
        try rejects("cache rejects symlink writes", { _ = try cache.store(Data([1]), name: symlinkName) }, matching: invalidFilename)
        try check(try Data(contentsOf: outside) == bytes, "symlink target remains unchanged")
        let blocked = directory.appendingPathComponent("blocked")
        try bytes.write(to: blocked)
        try rejects("failed cache write throws", { _ = try SavyImageCache(directory: blocked).store(bytes, name: name) })
        print("\(passed) existing image cache checks passed")

        let reminderValue = try SyncJSON.encode(["imageLocalPath": name, "whatWant": "Keep the original image"])
        let reminder = portable("reminders", reminderValue)
        let encodedReminder = try SyncJSON.encode(reminder)
        try check(try encodedReminder.decode(SavyCloudRecord.self) == reminder, "real portable record codec retains image reference")
        try check(SavyCloudKitAssets.imageName(in: reminder) == name, "Reminder imageLocalPath is portable")
        let outgoing = cloudRecord()
        try SavyCloudKitAssets.attach(to: outgoing, portable: reminder, cache: cache)
        guard let attached = outgoing["image"] as? CKAsset, let attachedFile = attached.fileURL else {
            throw Failure(description: "upload did not attach a real CKAsset")
        }
        try check(attachedFile == file && attachedFile.lastPathComponent == name, "outgoing asset keeps stable UUID filename")
        try check(try Data(contentsOf: attachedFile) == bytes, "outgoing asset contains exact original bytes")
        try check(reminder == portable("reminders", reminderValue), "attaching asset does not rewrite portable JSON")

        let connectionValue = try SyncJSON.encode(["metadata": ["imageLocalPath": name]])
        let connection = portable("connections", connectionValue)
        try check(SavyCloudKitAssets.imageName(in: connection) == name, "Connection metadata.imageLocalPath is portable")
        let connectionUpload = cloudRecord()
        try SavyCloudKitAssets.attach(to: connectionUpload, portable: connection, cache: cache)
        try check((connectionUpload["image"] as? CKAsset)?.fileURL == file, "Connection upload attaches original asset")

        let downloaded = directory.appendingPathComponent("temporary-cloudkit-download")
        try bytes.write(to: downloaded)
        let incoming = cloudRecord(downloaded)
        let receivingCache = SavyImageCache(directory: directory.appendingPathComponent("other-device-cache"))
        try SavyCloudKitAssets.retain(from: incoming, portable: reminder, cache: receivingCache)
        let retained = try receivingCache.existingFileURL(for: name)
        try check(retained != downloaded && retained.lastPathComponent == name, "fetched asset copied into independent managed cache")
        try check(try Data(contentsOf: retained) == bytes, "fetched asset preserves original bytes")
        try SavyCloudKitAssets.retain(from: incoming, portable: reminder, cache: receivingCache)
        try check(try Data(contentsOf: retained) == bytes, "identical incoming asset is idempotent")
        let connectionCache = SavyImageCache(directory: directory.appendingPathComponent("connection-cache"))
        try SavyCloudKitAssets.retain(from: incoming, portable: connection, cache: connectionCache)
        try check(try Data(contentsOf: connectionCache.existingFileURL(for: name)) == bytes, "Connection retains its metadata image")
        try FileManager.default.removeItem(at: downloaded)
        try check(try Data(contentsOf: SavyImageCache(directory: receivingCache.directory).existingFileURL(for: name)) == bytes,
                  "retained asset survives CloudKit temporary file removal and cache reopen")

        let absentCache = SavyImageCache(directory: directory.appendingPathComponent("absent-cache"))
        try rejects("missing outgoing original throws", {
            try SavyCloudKitAssets.attach(to: cloudRecord(), portable: reminder, cache: absentCache)
        }, matching: { if case SavyImageCache.Error.missingFile = $0 { return true }; return false })
        try rejects("missing downloaded asset throws", {
            try SavyCloudKitAssets.retain(from: cloudRecord(), portable: reminder, cache: absentCache)
        }, matching: missingAsset)
        let wrongAsset = cloudRecord()
        wrongAsset["image"] = "not-an-asset"
        try rejects("nonasset image field throws", {
            try SavyCloudKitAssets.retain(from: wrongAsset, portable: reminder, cache: absentCache)
        }, matching: missingAsset)
        let emptyAsset = directory.appendingPathComponent("empty-download")
        try Data().write(to: emptyAsset)
        try rejects("empty downloaded asset throws", {
            try SavyCloudKitAssets.retain(from: cloudRecord(emptyAsset), portable: reminder, cache: absentCache)
        }, matching: missingAsset)
        try rejects("unavailable downloaded file throws", {
            try SavyCloudKitAssets.retain(from: incoming, portable: reminder, cache: absentCache)
        })
        try check(!FileManager.default.fileExists(atPath: absentCache.directory.path), "failed asset reads cannot create an acknowledged image")
        try check(SavyCloudKitAssets.imageName(in: reminder) == name, "failed asset reads preserve the portable reference")

        try rejects("asset cache copy failure throws", {
            try SavyCloudKitAssets.retain(from: outgoing, portable: reminder, cache: SavyImageCache(directory: blocked))
        })
        try check(try Data(contentsOf: blocked) == bytes, "failed asset copy does not replace blocking file")

        let different = Data([0xff, 0xd8, 0x01, 0xff, 0xd9])
        let replacement = directory.appendingPathComponent("different-download")
        try different.write(to: replacement)
        try rejects("same filename with different bytes throws", {
            try SavyCloudKitAssets.retain(from: cloudRecord(replacement), portable: reminder, cache: receivingCache)
        }, matching: { if case SavyCloudKitAssets.Error.differentOriginal = $0 { return true }; return false })
        try check(try Data(contentsOf: retained) == bytes, "same-name conflict preserves existing original bytes")
        try check(try Data(contentsOf: replacement) == different, "same-name conflict preserves downloaded original bytes")

        for badName in ["../outside.jpg", "/tmp/outside.jpg", "not-a-uuid.jpg", name + "/extra", name + ".png", symlinkName] {
            let unsafe = portable("reminders", try SyncJSON.encode(["imageLocalPath": badName]))
            try rejects("outgoing asset rejects \(badName)", {
                try SavyCloudKitAssets.attach(to: cloudRecord(), portable: unsafe, cache: cache)
            }, matching: invalidFilename)
            try rejects("incoming asset rejects \(badName)", {
                try SavyCloudKitAssets.retain(from: outgoing, portable: unsafe, cache: cache)
            }, matching: invalidFilename)
        }
        try check(try Data(contentsOf: outside) == bytes, "unsafe asset paths leave outside bytes unchanged")

        let withoutImages = [portable("reminders", .object([:])),
                             portable("reminders", .object(["imageLocalPath": .null])),
                             portable("connections", .object(["imageLocalPath": .string(name)])),
                             portable("connections", .bool(true)),
                             portable("reminders", nil, deleted: true),
                             portable("reminders", reminderValue, deleted: true)]
            + ["social-posts", "stories", "card-preferences", "post-numbers", "personal-authority"]
                .map { portable($0, reminderValue) }
        for portable in withoutImages {
            try check(SavyCloudKitAssets.imageName(in: portable) == nil, "unreferenced document or tombstone has no image")
            let record = cloudRecord(file)
            try SavyCloudKitAssets.attach(to: record, portable: portable, cache: absentCache)
            try check(record["image"] == nil, "unreferenced document or tombstone clears prior asset")
            try SavyCloudKitAssets.retain(from: cloudRecord(), portable: portable, cache: absentCache)
        }
        try check(!FileManager.default.fileExists(atPath: absentCache.directory.path), "no-image records never create asset cache files")

        let outsideDirectory = directory.appendingPathComponent("outside-cache")
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try bytes.write(to: outsideDirectory.appendingPathComponent(name))
        let linkedDirectory = directory.appendingPathComponent("linked-cache")
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: outsideDirectory)
        let linkedCache = SavyImageCache(directory: linkedDirectory)
        try rejects("cache rejects a symlinked cache directory", {
            _ = try linkedCache.existingFileURL(for: name)
        }, matching: invalidFilename)
        try rejects("asset retain rejects a symlinked cache directory", {
            try SavyCloudKitAssets.retain(from: outgoing, portable: reminder, cache: linkedCache)
        }, matching: invalidFilename)
        try check(try Data(contentsOf: outsideDirectory.appendingPathComponent(name)) == bytes,
                  "symlinked cache directory cannot change outside bytes")
        print("\(passed) image cache and real CloudKit asset checks passed; stable references, original bytes, independent retention and failed-copy rejection verified")
    }
}
