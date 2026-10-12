import Foundation

/// The image boundary used by both the picker and CloudKit assets. Callers retain the
/// original UUID filename; every successful write confirms the same bytes on disk.
struct SavyImageCache: Sendable {
    enum Error: Swift.Error { case invalidFilename, missingFile }

    let directory: URL

    func fileURL(for name: String) throws -> URL {
        let stem = String(name.dropLast(4))
        guard name.hasSuffix(".jpg"), let id = UUID(uuidString: stem),
              id.uuidString.lowercased() == stem.lowercased() else { throw Error.invalidFilename }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw Error.invalidFilename }
        let file = directory.appendingPathComponent(name)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw Error.invalidFilename }
        return file
    }

    func existingFileURL(for name: String) throws -> URL {
        let file = try fileURL(for: name)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else { throw Error.missingFile }
        return file
    }

    @discardableResult
    func store(_ data: Data, name: String) throws -> URL {
        let file = try fileURL(for: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }
}
