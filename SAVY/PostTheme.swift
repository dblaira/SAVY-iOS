import Foundation

/// One prompt inside a post theme — the placeholder line the user answers in the Decide section.
struct PostThemeQuestion: Identifiable, Codable, Equatable {
    /// Stable per-theme position; answers are stored in this order.
    var id: String { prompt }
    let prompt: String
    /// SF Symbol shown next to the prompt, tinted crimson like every other form glyph.
    let symbol: String
}

/// A named question set for Post entries. Themes are data, not screens: picking a theme in the
/// Post form loads its questions into the Decide section, and the answers ride on the Reminder.
struct PostTheme: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let questions: [PostThemeQuestion]
}

/// The seed catalog. Add a theme here (or grow this into a loaded file later) and it appears in
/// the Post form's Theme picker — no new screens. Most themes ask four questions; The 5 Ws asks five.
enum PostThemeCatalog {
    static let themes: [PostTheme] = [
        PostTheme(
            id: "five-ws",
            name: "The 5 Ws",
            questions: [
                PostThemeQuestion(prompt: "What happened?", symbol: "bubble.left"),
                PostThemeQuestion(prompt: "Who was involved?", symbol: "person.2"),
                PostThemeQuestion(prompt: "When and where did it happen?", symbol: "mappin.and.ellipse"),
                PostThemeQuestion(prompt: "Why did it happen?", symbol: "questionmark.circle"),
                PostThemeQuestion(prompt: "How did it unfold?", symbol: "arrow.triangle.turn.up.right.circle"),
            ]
        ),
        PostTheme(
            id: "problem-solution",
            name: "Problem → Solution",
            questions: [
                PostThemeQuestion(prompt: "What's the problem?", symbol: "exclamationmark.triangle"),
                PostThemeQuestion(prompt: "Who feels it most?", symbol: "person.2"),
                PostThemeQuestion(prompt: "What's the fix?", symbol: "wrench.and.screwdriver"),
                PostThemeQuestion(prompt: "What changes once it's fixed?", symbol: "arrow.up.right"),
            ]
        ),
        PostTheme(
            id: "before-after",
            name: "Before / After",
            questions: [
                PostThemeQuestion(prompt: "What was it like before?", symbol: "clock.arrow.circlepath"),
                PostThemeQuestion(prompt: "What changed?", symbol: "arrow.left.arrow.right"),
                PostThemeQuestion(prompt: "What's it like now?", symbol: "sun.max"),
                PostThemeQuestion(prompt: "What made the difference?", symbol: "key"),
            ]
        ),
        PostTheme(
            id: "lesson-learned",
            name: "Lesson Learned",
            questions: [
                PostThemeQuestion(prompt: "What did I try?", symbol: "figure.walk"),
                PostThemeQuestion(prompt: "What went wrong?", symbol: "xmark.circle"),
                PostThemeQuestion(prompt: "What did I learn?", symbol: "lightbulb"),
                PostThemeQuestion(prompt: "What will I do differently?", symbol: "arrow.uturn.forward"),
            ]
        ),
        PostTheme(
            id: "how-to",
            name: "How-To",
            questions: [
                PostThemeQuestion(prompt: "What's the outcome?", symbol: "flag.checkered"),
                PostThemeQuestion(prompt: "What do you need first?", symbol: "checklist"),
                PostThemeQuestion(prompt: "What are the steps?", symbol: "list.number"),
                PostThemeQuestion(prompt: "What mistake should you avoid?", symbol: "hand.raised"),
            ]
        ),
        PostTheme(
            id: "story-arc",
            name: "Story Arc",
            questions: [
                PostThemeQuestion(prompt: "Where does it start?", symbol: "location"),
                PostThemeQuestion(prompt: "What's the tension?", symbol: "bolt"),
                PostThemeQuestion(prompt: "What's the turning point?", symbol: "arrow.triangle.branch"),
                PostThemeQuestion(prompt: "How does it end?", symbol: "flag"),
            ]
        ),
        PostTheme(
            id: "myth-fact",
            name: "Myth vs. Fact",
            questions: [
                PostThemeQuestion(prompt: "What do people believe?", symbol: "bubble.left.and.bubble.right"),
                PostThemeQuestion(prompt: "Why do they believe it?", symbol: "questionmark.circle"),
                PostThemeQuestion(prompt: "What's actually true?", symbol: "checkmark.seal"),
                PostThemeQuestion(prompt: "What's the proof?", symbol: "doc.text.magnifyingglass"),
            ]
        ),
        PostTheme(
            id: "the-decision",
            name: "The Decision",
            questions: [
                PostThemeQuestion(prompt: "What was the choice?", symbol: "signpost.right"),
                PostThemeQuestion(prompt: "What were the options?", symbol: "square.grid.2x2"),
                PostThemeQuestion(prompt: "What did I pick?", symbol: "checkmark.circle"),
                PostThemeQuestion(prompt: "Why?", symbol: "questionmark.circle"),
            ]
        ),
    ]

    /// The theme a fresh Post starts on — the mockup's default.
    static var defaultTheme: PostTheme { themes[0] }

    static func theme(id: String?) -> PostTheme? {
        guard let id else { return nil }
        return themes.first { $0.id == id }
    }
}
