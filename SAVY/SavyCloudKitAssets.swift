import CloudKit
import Foundation

/// Assets are confirmed in the managed cache before their referencing JSON can apply.
/// The portable payload owns the filename; temporary CloudKit download URLs never do.
enum SavyCloudKitAssets {
    enum Error: Swift.Error { case missingAsset, differentOriginal }

    static func imageName(in record: SavyCloudRecord) -> String? {
        guard !record.entry.deleted, case .object(let value) = record.entry.value else { return nil }
        if record.id.documentKey == "reminders" { return value["imageLocalPath"]?.stringValue }
        if record.id.documentKey == "connections", case .object(let metadata) = value["metadata"] {
            return metadata["imageLocalPath"]?.stringValue
        }
        return nil
    }

    static func attach(to cloudRecord: CKRecord, portable: SavyCloudRecord, cache: SavyImageCache) throws {
        if let name = imageName(in: portable) {
            cloudRecord["image"] = CKAsset(fileURL: try cache.existingFileURL(for: name))
        } else {
            cloudRecord["image"] = nil
        }
    }

    static func retain(from cloudRecord: CKRecord, portable: SavyCloudRecord, cache: SavyImageCache) throws {
        guard let name = imageName(in: portable) else { return }
        _ = try cache.fileURL(for: name)
        guard let asset = cloudRecord["image"] as? CKAsset, let source = asset.fileURL else { throw Error.missingAsset }
        let bytes = try Data(contentsOf: source)
        guard !bytes.isEmpty else { throw Error.missingAsset }
        if let existing = try? cache.existingFileURL(for: name) {
            guard try Data(contentsOf: existing) == bytes else { throw Error.differentOriginal }
            return
        }
        try cache.store(bytes, name: name)
    }
}
