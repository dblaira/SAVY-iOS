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

/// The capture sheet -- SAVY skin: paper page, cream fields, crimson
/// send. Three boxes, Adam's exact labels, nothing else.
struct HarnessDelegationComposerView: View {
    var onDone: () -> Void

    @State private var want = ""
    @State private var think = ""
    @State private var done = ""
    @State private var sent = false
    @FocusState private var focusedField: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Delegate")
                    .font(SavyTypography.displaySerif(28))
                    .foregroundStyle(SavyTheme.ink)
                Spacer()
                Button {
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SavyTheme.ink.opacity(0.5))
                }
            }
            .padding(.bottom, 2)

            delegationField(label: "WHAT DO I WANT?", text: $want, tag: 0)
            delegationField(label: "WHEN I AM...I LIKE TO", text: $think, tag: 1)
            delegationField(label: "DONE LOOKS LIKE...", text: $done, tag: 2)

            Button {
                let ok = HarnessDelegationWriter.write(want: want, think: think, done: done)
                if ok {
                    sent = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onDone() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: sent ? "checkmark" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                    Text(sent ? "On its way home" : "Delegate")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(SavyTheme.crimson)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(want.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sent)
            .opacity(want.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(SavyTheme.paper.ignoresSafeArea())
        .onAppear { focusedField = 0 }
    }

    private func delegationField(label: String, text: Binding<String>, tag: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .kerning(1.5)
                .foregroundStyle(SavyTheme.crimson)
            TextField("", text: text, axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(SavyTheme.ink)
                .lineLimit(1...8)
                .focused($focusedField, equals: tag)
                .padding(12)
                .background(SavyTheme.beliefCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
