import UIKit

/// Persists picked photos to Application Support and loads them back. v1 keeps images on-device;
/// cloud upload to S3 via the AWS graph API is the 1.0.1 follow-up (image_path stays null server-side).
enum LocalImageStore {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reminder-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do { try data.write(to: dir.appendingPathComponent(name), options: .atomic); return name }
        catch { return nil }
    }

    static func load(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    /// Raw JPEG bytes for a stored image — used to upload to S3.
    static func data(_ name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(name))
    }

    /// Write downloaded bytes under an explicit name (deterministic cache for cloud images).
    @discardableResult
    static func write(_ data: Data, name: String) -> String? {
        do { try data.write(to: dir.appendingPathComponent(name), options: .atomic); return name }
        catch { return nil }
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }
}
