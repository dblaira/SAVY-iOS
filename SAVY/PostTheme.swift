import Foundation

/// One prompt inside a post theme, prefilled as editable text in the Decide section.
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

    /// The blank line puts the answer beneath the question in the same saved field.
    var prefilledAnswers: [String] {
        questions.map { $0.prompt + "\n\n" }
    }

    /// Older entries saved only answers. Supply their questions once while preserving every
    /// character the user wrote. Marked entries are already whole fields and reopen verbatim.
    func questionAndAnswers(from saved: [String]?, containQuestions: Bool) -> [String] {
        let saved = saved ?? []
        return (0..<max(saved.count, questions.count)).map { index in
            guard saved.indices.contains(index) else { return prefilledAnswers[index] }
            let value = saved[index]
            guard !containQuestions, questions.indices.contains(index) else { return value }
            let prompt = questions[index].prompt
            if value == prompt || value.hasPrefix(prompt + "\n") || value.hasPrefix(prompt + "\r\n") {
                return value
            }
            return prompt + "\n\n" + value
        }
    }

    /// Card previews count answers, not the prefilled question. This is a presentation helper;
    /// the complete field remains the saved and exported source, including edited questions.
    static func answerText(in field: String, originalPrompt: String?) -> String {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prompt = originalPrompt {
            if trimmed == prompt { return "" }
            if field.hasPrefix(prompt + "\n") || field.hasPrefix(prompt + "\r\n") {
                return String(field.dropFirst(prompt.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let separator = field.range(of: "\n\n") {
            return String(field[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}

/// One open form can explore several themes without erasing the words entered in any of them.
struct PostEntryDraft {
    private(set) var themeID: String
    private var answersByTheme: [String: [String]]

    init(entry: Reminder) {
        let theme = PostThemeCatalog.theme(id: entry.postThemeID) ?? PostThemeCatalog.defaultTheme
        themeID = theme.id
        answersByTheme = [theme.id: theme.questionAndAnswers(
            from: entry.postAnswers,
            containQuestions: entry.postAnswersContainQuestions == true
        )]
    }

    var theme: PostTheme {
        PostThemeCatalog.theme(id: themeID) ?? PostThemeCatalog.defaultTheme
    }

    var answers: [String] { answersByTheme[themeID] ?? theme.prefilledAnswers }

    mutating func selectTheme(_ id: String) {
        guard let selected = PostThemeCatalog.theme(id: id) else { return }
        themeID = selected.id
        if answersByTheme[id] == nil { answersByTheme[id] = selected.prefilledAnswers }
    }

    mutating func setAnswer(_ text: String, at index: Int) {
        guard index >= 0 else { return }
        var values = answers
        while values.count <= index { values.append("") }
        values[index] = text
        answersByTheme[themeID] = values
    }

    /// Explicit Save retains the untouched template as well as any entered answers.
    func apply(to entry: inout Reminder) {
        entry.postThemeID = theme.id
        entry.postThemeName = theme.name
        entry.postAnswers = answers
        entry.postAnswersContainQuestions = true
    }

    /// Opening a template or choosing another one does not create an autosaved post.
    /// A changed question is user content too; its original wording is only a starting point.
    var hasUserContent: Bool {
        answers.enumerated().contains { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return !theme.questions.indices.contains(index) || trimmed != theme.questions[index].prompt
        }
    }
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
        // Themes 11–30, Adam's questions verbatim (2026-09-15). The image skips #14; its two
        // #26 titles are both here as their own themes.
        PostTheme(
            id: "frequently-asked-questions",
            name: "Frequently Asked Questions",
            questions: [
                PostThemeQuestion(prompt: "What questions do people repeatedly ask?", symbol: "questionmark.bubble"),
                PostThemeQuestion(prompt: "What uncertainty is behind each question?", symbol: "questionmark.circle"),
                PostThemeQuestion(prompt: "What is the clearest answer to each?", symbol: "text.bubble"),
                PostThemeQuestion(prompt: "What follow-up question naturally comes after each answer?", symbol: "arrow.turn.down.right"),
            ]
        ),
        PostTheme(
            id: "customer-success-story",
            name: "Customer Success Story",
            questions: [
                PostThemeQuestion(prompt: "What did the customer want to achieve?", symbol: "target"),
                PostThemeQuestion(prompt: "What prevented them from succeeding before?", symbol: "hand.raised"),
                PostThemeQuestion(prompt: "How did the product or service change their experience?", symbol: "wand.and.stars"),
                PostThemeQuestion(prompt: "What success can they demonstrate and describe in their own words?", symbol: "quote.bubble"),
            ]
        ),
        PostTheme(
            id: "key-challenges-solutions",
            name: "Key Challenges & Solutions",
            questions: [
                PostThemeQuestion(prompt: "Which obstacles stand in the way of the desired outcome?", symbol: "exclamationmark.triangle"),
                PostThemeQuestion(prompt: "What makes each obstacle difficult to overcome?", symbol: "lock"),
                PostThemeQuestion(prompt: "Which solution addresses the cause of each obstacle?", symbol: "wrench.and.screwdriver"),
                PostThemeQuestion(prompt: "What conditions determine whether each solution will work?", symbol: "slider.horizontal.3"),
            ]
        ),
        PostTheme(
            id: "myths-vs-facts",
            name: "Myths vs. Facts",
            questions: [
                PostThemeQuestion(prompt: "Which claims are commonly repeated as facts?", symbol: "bubble.left.and.bubble.right"),
                PostThemeQuestion(prompt: "What is actually true about each claim?", symbol: "checkmark.seal"),
                PostThemeQuestion(prompt: "What evidence establishes the difference?", symbol: "doc.text.magnifyingglass"),
                PostThemeQuestion(prompt: "What changes in practice when someone understands the facts?", symbol: "arrow.up.right"),
            ]
        ),
        PostTheme(
            id: "the-ultimate-checklist",
            name: "The Ultimate Checklist",
            questions: [
                PostThemeQuestion(prompt: "What complete task or outcome does this checklist cover?", symbol: "flag.checkered"),
                PostThemeQuestion(prompt: "What must be included so nothing essential is missed?", symbol: "checklist"),
                PostThemeQuestion(prompt: "Which items must be checked before others?", symbol: "list.number"),
                PostThemeQuestion(prompt: "What qualifies each item as complete?", symbol: "checkmark.circle"),
            ]
        ),
        PostTheme(
            id: "quick-hack-or-shortcut",
            name: "Quick Hack or Shortcut",
            questions: [
                PostThemeQuestion(prompt: "What does the usual method require?", symbol: "list.bullet"),
                PostThemeQuestion(prompt: "Which steps does the shortcut remove or simplify?", symbol: "scissors"),
                PostThemeQuestion(prompt: "What makes skipping those steps possible?", symbol: "bolt"),
                PostThemeQuestion(prompt: "When does the shortcut stop producing an acceptable result?", symbol: "hand.raised"),
            ]
        ),
        PostTheme(
            id: "recommended-tools-resources",
            name: "Recommended Tools & Resources",
            questions: [
                PostThemeQuestion(prompt: "What specific jobs should these tools or resources help accomplish?", symbol: "target"),
                PostThemeQuestion(prompt: "Which option best serves each job?", symbol: "wrench.and.screwdriver"),
                PostThemeQuestion(prompt: "What makes each option worth recommending?", symbol: "star"),
                PostThemeQuestion(prompt: "When would someone choose one option over another?", symbol: "arrow.triangle.branch"),
            ]
        ),
        PostTheme(
            id: "essential-terminology",
            name: "Essential Terminology",
            questions: [
                PostThemeQuestion(prompt: "Which terms must someone understand to follow this topic?", symbol: "textformat"),
                PostThemeQuestion(prompt: "What does each term mean in plain language?", symbol: "book"),
                PostThemeQuestion(prompt: "How is each term used in a concrete example?", symbol: "text.quote"),
                PostThemeQuestion(prompt: "Which similar terms need to be distinguished from one another?", symbol: "arrow.left.arrow.right"),
            ]
        ),
        PostTheme(
            id: "before-after-scenarios",
            name: "Before & After Scenarios",
            questions: [
                PostThemeQuestion(prompt: "What starting condition will the “before” show?", symbol: "clock.arrow.circlepath"),
                PostThemeQuestion(prompt: "What changed between the two states?", symbol: "arrow.left.arrow.right"),
                PostThemeQuestion(prompt: "Which visible or measurable differences will the “after” show?", symbol: "sun.max"),
                PostThemeQuestion(prompt: "What must stay consistent to make the comparison fair?", symbol: "equal.circle"),
            ]
        ),
        PostTheme(
            id: "audience-poll-or-survey-results",
            name: "Audience Poll or Survey Results",
            questions: [
                PostThemeQuestion(prompt: "What question did the poll or survey ask?", symbol: "questionmark.circle"),
                PostThemeQuestion(prompt: "Who answered, and how many people responded?", symbol: "person.3"),
                PostThemeQuestion(prompt: "Where did the answers agree or divide?", symbol: "chart.pie"),
                PostThemeQuestion(prompt: "What do the results reveal about the respondents?", symbol: "lightbulb"),
            ]
        ),
        PostTheme(
            id: "core-principles-explained",
            name: "Core Principles Explained",
            questions: [
                PostThemeQuestion(prompt: "Which principles govern this topic?", symbol: "building.columns"),
                PostThemeQuestion(prompt: "What does each principle explain?", symbol: "doc.text"),
                PostThemeQuestion(prompt: "How do the principles work together?", symbol: "link"),
                PostThemeQuestion(prompt: "Where does each principle stop applying?", symbol: "nosign"),
            ]
        ),
        PostTheme(
            id: "debunking-popular-industry-beliefs",
            name: "Debunking Popular Industry Beliefs",
            questions: [
                PostThemeQuestion(prompt: "Which widely accepted industry belief are you challenging?", symbol: "bubble.left.and.bubble.right"),
                PostThemeQuestion(prompt: "Why has that belief become accepted?", symbol: "clock.arrow.circlepath"),
                PostThemeQuestion(prompt: "What evidence contradicts it?", symbol: "doc.text.magnifyingglass"),
                PostThemeQuestion(prompt: "What explanation better fits the evidence?", symbol: "lightbulb"),
            ]
        ),
        PostTheme(
            id: "history-of-the-topic",
            name: "History of the Topic",
            questions: [
                PostThemeQuestion(prompt: "Where and how did this topic begin?", symbol: "location"),
                PostThemeQuestion(prompt: "Which events changed its direction?", symbol: "arrow.triangle.branch"),
                PostThemeQuestion(prompt: "What caused those changes?", symbol: "questionmark.circle"),
                PostThemeQuestion(prompt: "Which parts of its past still shape it today?", symbol: "clock.arrow.circlepath"),
            ]
        ),
        PostTheme(
            id: "alternative-approaches",
            name: "Alternative Approaches",
            questions: [
                PostThemeQuestion(prompt: "What is the usual approach?", symbol: "figure.walk"),
                PostThemeQuestion(prompt: "What other approaches could achieve the same result?", symbol: "arrow.triangle.branch"),
                PostThemeQuestion(prompt: "What does each alternative change about how the work is done?", symbol: "arrow.left.arrow.right"),
                PostThemeQuestion(prompt: "Under what conditions would you choose each approach?", symbol: "slider.horizontal.3"),
            ]
        ),
        PostTheme(
            id: "step-by-step-breakdown",
            name: "Step-by-Step Breakdown",
            questions: [
                PostThemeQuestion(prompt: "What stages make up the process?", symbol: "list.number"),
                PostThemeQuestion(prompt: "What job does each stage perform?", symbol: "gearshape"),
                PostThemeQuestion(prompt: "What must be finished before each stage can begin?", symbol: "lock"),
                PostThemeQuestion(prompt: "What does each stage pass to the next?", symbol: "arrow.right.circle"),
            ]
        ),
        PostTheme(
            id: "checklist-for-breakdown",
            name: "Checklist for Breakdown",
            questions: [
                PostThemeQuestion(prompt: "Which parts of the process must be accounted for?", symbol: "square.grid.2x2"),
                PostThemeQuestion(prompt: "What information must be recorded for each part?", symbol: "pencil"),
                PostThemeQuestion(prompt: "Which connections between parts must be checked?", symbol: "link"),
                PostThemeQuestion(prompt: "What confirms that the breakdown covers the whole process?", symbol: "checkmark.seal"),
            ]
        ),
        PostTheme(
            id: "checklist-for-beginners",
            name: "Checklist for Beginners",
            questions: [
                PostThemeQuestion(prompt: "What must a beginner understand before starting?", symbol: "book"),
                PostThemeQuestion(prompt: "What needs to be gathered or set up?", symbol: "shippingbox"),
                PostThemeQuestion(prompt: "What must be checked before the first attempt?", symbol: "checklist"),
                PostThemeQuestion(prompt: "What marks a successful first attempt?", symbol: "flag.checkered"),
            ]
        ),
        PostTheme(
            id: "advanced-strategies",
            name: "Advanced Strategies",
            questions: [
                PostThemeQuestion(prompt: "What result requires going beyond the basics?", symbol: "target"),
                PostThemeQuestion(prompt: "What must already be mastered?", symbol: "checkmark.seal"),
                PostThemeQuestion(prompt: "Which advanced techniques improve that result?", symbol: "bolt"),
                PostThemeQuestion(prompt: "What additional demands or tradeoffs do those techniques introduce?", symbol: "scalemass"),
            ]
        ),
        PostTheme(
            id: "frequently-misunderstood-concepts",
            name: "Frequently Misunderstood Concepts",
            questions: [
                PostThemeQuestion(prompt: "Which concept do people commonly misunderstand?", symbol: "questionmark.circle"),
                PostThemeQuestion(prompt: "What do they think it means?", symbol: "bubble.left"),
                PostThemeQuestion(prompt: "What does it actually mean?", symbol: "checkmark.seal"),
                PostThemeQuestion(prompt: "What example makes the difference clear?", symbol: "text.quote"),
            ]
        ),
        PostTheme(
            id: "your-personal-take-lessons-learned",
            name: "Your Personal Take & Lessons Learned",
            questions: [
                PostThemeQuestion(prompt: "What did you believe before?", symbol: "clock.arrow.circlepath"),
                PostThemeQuestion(prompt: "What experience changed or confirmed your view?", symbol: "figure.walk"),
                PostThemeQuestion(prompt: "What do you believe now?", symbol: "lightbulb"),
                PostThemeQuestion(prompt: "What do you do differently because of it?", symbol: "arrow.uturn.forward"),
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
