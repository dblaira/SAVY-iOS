#if DEBUG
import SwiftUI
import UIKit

/// Test-only evidence: with isolated UI-test data, walk the main pages and write each window
/// image to SAVY_UI_TEST_CAPTURE_DIR (or Application Support/SAVY/ScreenCaptures), then quit.
/// Needs no screen-recording permission because the app draws its own windows.
@MainActor
enum SavyScreenCapture {
    static let openHomeSection = Notification.Name("SavyScreenCaptureOpenHomeSection")

    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("SAVY_UI_TEST_CAPTURE_SCREENS") && arguments.contains("SAVY_UI_TEST_UNLOCKED")
    }

    static func run(navigation: SavyNavigationState, showPosts: @escaping (Bool) -> Void) async {
        let pause: Duration = .milliseconds(2500)
        try? await Task.sleep(for: .seconds(4))
        capture("home")
        for (section, name) in [(SavyNavigationSection.reminders, "reminders"), (.actions, "actions"), (.calendar, "calendar")] {
            navigation.activeSection = section
            try? await Task.sleep(for: pause)
            capture(name)
        }
        navigation.activeSection = .now
        try? await Task.sleep(for: pause)
        navigation.openComposer(for: .post)
        try? await Task.sleep(for: .seconds(4))
        capture("composer")
        navigation.activeComposerKind = nil
        try? await Task.sleep(for: pause)
        showPosts(true)
        try? await Task.sleep(for: pause)
        capture("posts")
        showPosts(false)
        try? await Task.sleep(for: pause)
        NotificationCenter.default.post(name: openHomeSection, object: "beliefs")
        try? await Task.sleep(for: pause)
        capture("connection")
        exit(0)
    }

    /// Writes the main window and, when a sheet is open in its own window (the Mac), that window too.
    private static func capture(_ name: String) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        write(window, as: name)
        var presented = window.rootViewController?.presentedViewController
        while let controller = presented {
            if let sheetWindow = controller.view.window, sheetWindow !== window {
                write(sheetWindow, as: "\(name)-sheet")
            }
            presented = controller.presentedViewController
        }
    }

    private static func write(_ window: UIWindow, as name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let requested = ProcessInfo.processInfo.environment["SAVY_UI_TEST_CAPTURE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard let png = image.pngData(),
              let directory = requested ?? (try? FileManager.default.url(
                  for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
              ).appendingPathComponent("SAVY/ScreenCaptures", isDirectory: true)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? png.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
#endif
