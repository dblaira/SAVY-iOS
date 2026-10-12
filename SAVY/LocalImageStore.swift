import UIKit

/// Picked photos remain local immediately; CloudKit transports referenced files as assets.
enum LocalImageStore {
    static var cache: SavyImageCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reminder-images", isDirectory: true)
        return SavyImageCache(directory: base)
    }

    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do { try cache.store(data, name: name); return name }
        catch { return nil }
    }

    static func load(_ name: String?) -> UIImage? {
        guard let name, let file = try? cache.existingFileURL(for: name) else { return nil }
        return UIImage(contentsOfFile: file.path)
    }

    /// Original JPEG bytes, without re-encoding the image.
    static func data(_ name: String?) -> Data? {
        guard let name, let file = try? cache.existingFileURL(for: name) else { return nil }
        return try? Data(contentsOf: file)
    }

    /// Write downloaded bytes under an explicit name (deterministic cache for cloud images).
    @discardableResult
    static func write(_ data: Data, name: String) -> String? {
        do { try cache.store(data, name: name); return name }
        catch { return nil }
    }

    static func exists(_ name: String) -> Bool {
        (try? cache.existingFileURL(for: name)) != nil
    }
}
