import CloudKit
import UIKit
import XCTest
@testable import SAVY

final class SAVYCloudImageTests: XCTestCase {
    @MainActor
    func testImageCacheRetainsActualJPEGBytesAndRejectsPathsOutsideIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("savy-jpeg-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let name = UUID().uuidString + ".jpg"
        let cache = SavyImageCache(directory: directory)
        try cache.store(jpeg, name: name)
        let reopened = SavyImageCache(directory: directory)
        let bytes = try Data(contentsOf: reopened.existingFileURL(for: name))
        XCTAssertEqual(bytes, jpeg)
        XCTAssertNotNil(UIImage(data: bytes))
        XCTAssertThrowsError(try cache.store(jpeg, name: "../escape.jpg"))
        XCTAssertThrowsError(try cache.existingFileURL(for: "arbitrary.jpg"))
    }

    @MainActor
    func testCloudKitTransfersActualJPEGForReminderAndConnectionWithoutRewritingReferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("savy-jpeg-assets-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let name = UUID().uuidString + ".jpg"
        let outgoingCache = SavyImageCache(directory: directory.appendingPathComponent("outgoing"))
        let original = try outgoingCache.store(jpeg, name: name)
        let date = Date(timeIntervalSince1970: 42)
        let reminder = Reminder(title: "JPEG fixture", imageLocalPath: name, createdAt: date, updatedAt: date)
        let connection = ConnectionEntry(metadata: reminder)
        let values = [("reminders", try SyncJSON.encode(reminder)),
                      ("connections", try SyncJSON.encode(connection))]

        for (document, value) in values {
            let portable = SavyCloudRecord(id: SavyCloudRecordID(documentKey: document, key: reminder.id.uuidString),
                                           entry: SyncEntry(value: value, modifiedAt: 42, deleted: false))
            XCTAssertEqual(SavyCloudKitAssets.imageName(in: portable), name)
            let upload = CKRecord(recordType: "SavyEntry")
            try SavyCloudKitAssets.attach(to: upload, portable: portable, cache: outgoingCache)
            let asset = try XCTUnwrap(upload["image"] as? CKAsset)
            XCTAssertEqual(asset.fileURL, original)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(asset.fileURL)), jpeg)

            let download = directory.appendingPathComponent("cloudkit-download-\(document)")
            try jpeg.write(to: download)
            let fetched = CKRecord(recordType: "SavyEntry")
            fetched["image"] = CKAsset(fileURL: download)
            let destination = directory.appendingPathComponent("received-\(document)")
            try SavyCloudKitAssets.retain(from: fetched, portable: portable, cache: SavyImageCache(directory: destination))
            try FileManager.default.removeItem(at: download)
            let retained = try SavyImageCache(directory: destination).existingFileURL(for: name)
            XCTAssertEqual(retained.lastPathComponent, name)
            XCTAssertNotEqual(retained, original)
            let bytes = try Data(contentsOf: retained)
            XCTAssertEqual(bytes, jpeg)
            XCTAssertNotNil(UIImage(data: bytes))
            XCTAssertEqual(portable.entry.value, value)
        }
        XCTAssertEqual(try values[0].1.decode(Reminder.self), reminder)
        XCTAssertEqual(try values[1].1.decode(ConnectionEntry.self), connection)
    }
}
