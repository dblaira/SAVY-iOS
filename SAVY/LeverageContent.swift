import Foundation

enum LeverageContent {
    static let seed: [LeverageSection] = [
        newsChannel,
        fieldEssays,
        ontology,
        beliefs
    ]

    static let newsChannel = LeverageSection(
        id: "news-channel",
        title: "News Channel",
        eyebrow: "NEWS CHANNEL",
        headline: "This Week's AI Brief",
        summary: "AI briefings translated into systems, context, and product implications.",
        items: [
            LeverageItem(
                id: "weekly-ai-brief-2026-06-01",
                kicker: "JUN 1-6, 2026",
                title: "AI is becoming infrastructure",
                summary: "The main story is not one model. AI tools now need memory, rules, context, payments, permissions, and workflows.",
                body: """
                The website's News Channel frames this week around a single center of gravity: AI is becoming infrastructure.

                Models are the brain. Tools are the hands. Memory is the past. Graphs hold relationships. Rules become guardrails. Workflows turn intelligence into repeatable action. Payments turn the system into a business layer.

                The native takeaway is simple: do not build a chatbot. Build a relationship engine.
                """
            ),
            LeverageItem(
                id: "agent-workflows",
                kicker: "SIGNAL 1",
                title: "Agent workflows",
                summary: "AI is being turned into repeatable work loops.",
                body: "Use an agent when the path is unknown. Use a workflow when the steps are known. Rewriting an entry is a workflow; finding a hidden life pattern is closer to agent-like search."
            ),
            LeverageItem(
                id: "context-graphs",
                kicker: "SIGNAL 2",
                title: "Context graphs",
                summary: "AI needs structured memory. This is the ontology lane.",
                body: "Neo4j's enterprise message is that AI alone is not enough. AI needs connected facts. SAVY's human version is sharper: narratives hide, relationships reveal."
            ),
            LeverageItem(
                id: "guardrails",
                kicker: "SIGNAL 3",
                title: "Guardrails",
                summary: "AI tools need rules and limits. That is where trust gets built.",
                body: "OpenRouter is becoming less like a model menu and more like a control layer: models plus rules plus voice plus routing."
            ),
            LeverageItem(
                id: "coding-models",
                kicker: "SIGNAL 4",
                title: "Coding models",
                summary: "More models are built just for software work.",
                body: "Grok Build 0.1 points toward idea to code to test to fix to ship loops. That matters when the work is made of many small software pieces."
            ),
            LeverageItem(
                id: "vendor-ai-stacks",
                kicker: "SIGNAL 5",
                title: "Vendor AI stacks",
                summary: "Companies are adding AI into existing tools.",
                body: "Linear, Stripe, Figma, Replit, and Magnific point in the same direction: AI capability is being absorbed into existing work and business rails."
            )
        ]
    )

    static let fieldEssays = LeverageSection(
        id: "field-essays",
        title: "Field Essays",
        eyebrow: "FIELD ESSAYS",
        headline: "Patterns found in the world.",
        summary: "Essays about recurring forces: incentives, attention, morality, energy, and asymmetry.",
        items: [
            LeverageItem(
                id: "something-is-happening-to-americas-moral-code",
                kicker: "APR 24, 2026",
                title: "Something Is Happening to America's Moral Code",
                summary: "A field note on moral courage, hidden theft, and the cost of public principle.",
                body: """
                The useful parable is not about whether a person is left or right. It is about whether the act has a face.

                Civil disobedience is public. It accepts cost. It turns punishment into part of the argument. Petty theft framed as resistance often does the opposite: it hides inside distance, scale, and plausible deniability.

                The older pattern is simple: cost reveals belief. A person can say almost anything when the bill lands somewhere else. The real test is what they are willing to carry in public.
                """
            ),
            LeverageItem(
                id: "the-lesson-is-in-the-eye-of-the-beholder",
                kicker: "APR 23, 2026",
                title: "The lesson is in the eye of the beholder",
                summary: "What four true crime documentaries made me see.",
                body: """
                A great true crime documentary has to make no sense on one level and perfect sense on another, at the same time.

                The surface narrative is institutional: police, investigators, procedure. The deeper narrative is older. People protect their own. People avenge their own. Grief plus information plus proximity equals action, and the institution is optional.

                The useful pattern is not crime. It is the older system showing up uncloaked inside a culture that mostly pretends it is no longer there.
                """
            )
        ]
    )

    static let ontology = LeverageSection(
        id: "ontology",
        title: "Adam's Ontology",
        eyebrow: "ONTOLOGY",
        headline: "The map of leverage.",
        summary: "A structured view of categories, relationships, and recurring 80/20 patterns.",
        items: [
            LeverageItem(
                id: "ontology-summary",
                kicker: "92 WEEKS",
                title: "13 categories, 4,873 extractions",
                summary: "The website's ontology view compresses lived data into category relationships.",
                body: "The latest Aurora correlation analysis spans 92 weeks, 4,873 extractions, 13 categories, and 23 relationships."
            ),
            LeverageItem(
                id: "affect-learning",
                kicker: "0.670",
                title: "Affect moves with Learning",
                summary: "The strongest visible co-movement pairs emotional state with learning.",
                body: "Affect and Learning show the strongest current relationship in the website ontology sample. This is the kind of signal the native app should make readable before it makes it complex."
            ),
            LeverageItem(
                id: "insight-purchase",
                kicker: "0.663",
                title: "Insight moves with Purchase",
                summary: "Some buying behavior appears near insight and learning clusters.",
                body: "The useful question is not whether purchases are good or bad. It is whether they are downstream of real insight or just ambient stimulation."
            ),
            LeverageItem(
                id: "exercise-sleep",
                kicker: "0.570",
                title: "Exercise moves with Sleep",
                summary: "The obvious relationship still earns its place in the graph.",
                body: "Ontology is not only for surprising relationships. Sometimes the value is proving that a basic pattern is stable enough to become a default."
            )
        ]
    )

    static let beliefs = LeverageSection(
        id: "beliefs",
        title: "Belief Library",
        eyebrow: "BELIEFS",
        headline: "Principles worth keeping close.",
        summary: "Personal leverage rules, identity anchors, and patterns worth preserving.",
        items: [
            LeverageItem(
                id: "focus-control",
                kicker: "PINNED",
                title: "Focus on What's in Your Control",
                summary: "Work on what I can. Figure out the rest later on.",
                body: "Work on what I can. Figure out the rest later on."
            ),
            LeverageItem(
                id: "exporting-judgment",
                kicker: "VALIDATED PRINCIPLE",
                title: "The 10 minutes exporting your judgment builds a system",
                summary: "The 10 minutes just doing the task is gone forever.",
                body: "The 10 minutes exporting your judgment builds a system that compounds. The 10 minutes just doing the task is gone forever."
            ),
            LeverageItem(
                id: "writing-is-thinking",
                kicker: "VALIDATED PRINCIPLE",
                title: "Writing isn't just recording",
                summary: "Articulating something well changes your relationship to it.",
                body: "Articulating something well changes your relationship to it. Writing isn't just recording. It's thinking."
            ),
            LeverageItem(
                id: "context-conviction",
                kicker: "PROCESS ANCHOR",
                title: "Context Without Conviction Is Just Regret",
                summary: "What is context without conviction? Regret.",
                body: "What is context without conviction? Regret."
            ),
            LeverageItem(
                id: "system-or-task",
                kicker: "PATTERN INTERRUPT",
                title: "Am I building a system or doing a task?",
                summary: "The question that separates compounding from motion.",
                body: "Am I building a system or doing a task?"
            )
        ]
    )
}
