import SwiftUI

/// Adam's three-sentence delegation, captured in SAVY and landed in the
/// Harness Delegation queue at home via the suite's shared iCloud
/// container. His words, verbatim: "I go into the savvy app because
/// that's the area where I want to focus on things that I'm already
/// good at ... when I enter that in I have the three step delegation
/// when I press enter ... I would like for that to transfer
/// automatically to the harness app and that way I can work on it more
/// when I get home."
enum HarnessDelegationWriter {
    static let containerIdentifier = "iCloud.com.adamblair.harness"

    /// Documents/Delegations inside the shared container; nil when
    /// iCloud is unavailable (signed out, airplane-mode first launch).
    static func delegationsDirectory() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return nil
        }
        let dir = container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Delegations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Local fallback spool -- anything written here is moved into the
    /// container on the next successful write (capture never fails
    /// because the network did).
    static func spoolDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HarnessDelegationSpool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes the delegation card in the exact frontmatter contract the
    /// Harness board parser validates (resource, rules_hit, fit, app,
    /// sources). Adam's sentences go in verbatim -- title is his first
    /// sentence, the body carries all three under his own labels.
    @discardableResult
    static func write(want: String, think: String, done: String) -> Bool {
        let stamp = Self.fileStampFormatter.string(from: Date())
        let iso = ISO8601DateFormatter().string(from: Date())
        let id = "DELEGATION-\(stamp)-SAVY"
        let title = want
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces) ?? want
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")

        let markdown = """
        ---
        type: delegation
        title: "\(escapedTitle)"
        resource: savy://delegation/\(stamp)
        timestamp: \(iso)
        opp_id: \(id)
        fit: 0.8
        rules_hit: [R-01]
        app: SAVY
        sources: 1
        scout_id: adam-savy-capture
        ---
        WHAT DO I WANT?
        \(want)

        WHEN I AM...I LIKE TO
        \(think)

        DONE LOOKS LIKE...
        \(done)
        """

        let filename = "\(id).md"
        if let dir = delegationsDirectory() {
            drainSpool(into: dir)
            do {
                try markdown.write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
                return true
            } catch {
                // fall through to spool
            }
        }
        let spooled = spoolDirectory().appendingPathComponent(filename)
        return (try? markdown.write(to: spooled, atomically: true, encoding: .utf8)) != nil
    }

    /// Move any offline captures into the container once it's reachable.
    static func drainSpool(into directory: URL) {
        let spool = spoolDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: spool, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "md" {
            try? FileManager.default.moveItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
        }
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
