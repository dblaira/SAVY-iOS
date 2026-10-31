# questions under each Visual

October 31, 2026.

# Installed in SAVY on Mac and iPhone (Executive Conclusion)

1. ✅ All 48 questions are approved and installed in both SAVY apps. The twelve existing Visual names and their order are unchanged.

2. 🧭 Visual remains Adam's choice. Theme selection does not select Visual.

3. 🎨 The current native styling and font sizes are unchanged. All 87 other tracked app files match the baseline.

# Existing writing is preserved (Consequence)

1. 💾 Saved questions and answers keep their original snapshots. Only slots with an exactly empty question and an exactly empty answer receive the current prompt when displayed.

2. 📚 Unknown formats and extra future fields remain intact. Whitespace counts as existing text. Reading or sharing does not rewrite the stored draft.

3. 🔒 Both installations retain all 55 saved records. The authored archives and media match fresh backups. Only the two CloudKit metadata files changed.

# Questions under each Visual (Recommendation)

Adam approved these questions:

> These look great. Let's add these to both the Mac OS and the iOS app for SAVY. I have my phone connected

Summarize retains his four dictated questions. The other 44 are approved wording adapted from his explanations.

### Summarize

🎯 Why does this need to be summarized?

📄 What is being summarized?

💡 Why is summarization helpful compared to more visual outputs?

👥 How should this summary be fully taken advantage of by the audience?

### Tables

🎯 What am I comparing?

📄 What goes in the rows?

💡 What goes in the columns?

👥 What difference should people see?

### Matrices

🎯 What goes across the top?

📄 What goes down the side?

💡 What goes where they meet?

👥 What connection should people see?

### Node Trees

🎯 What goes first?

📄 What comes under it?

💡 How are they connected?

👥 What order should people follow?

### Graphic Imagery

🎯 What idea am I showing?

📄 What needs to be in the image?

💡 What should people notice first?

👥 What should this make clear while I talk?

### Slides

🎯 What are the steps or elements?

📄 What goes on each slide?

💡 What should be shown together?

👥 What text keeps people on topic?

### Charts

🎯 What's X?

📄 What's Y?

💡 Is there a trend or an outlier?

👥 What context do people need?

### Images

🎯 What still image do I want?

📄 What should people notice in it?

💡 What does it help people understand?

👥 Is there a feeling I want the image to create?

### Video

🎯 What do I want people to see happening?

📄 What part of the story does it show?

💡 What am I saying while it plays?

👥 Where does the clip start and end?

### Audio

🎯 What do I want people to hear?

📄 What does the sound help explain?

💡 What should be on screen while it plays?

👥 Where does it belong in the story?

### Music

🎯 Is music going to be an important part of it?

📄 What feeling should it create?

💡 Where should it come in?

👥 Where should it stop?

### Example

🎯 What am I showing an example of?

📄 What happens from beginning to end?

💡 What will people see and hear?

👥 How could they use it in their own circumstances?

# Sources and verification (Supporting Evidence on Request)

Adam's current request, verbatim:

> Now let's work on the questions under each Visual so I can explain what I want on the other half of the screen. Use my words, keep Visual my choice, and don't change the styling or font sizes.

1. 🗣️ [creating visual choices](</Users/adamblair/Documents/social-media/notes/creating visual choices.md>) contains Adam's full explanations of his Visual choices. It also contains his full description of “Half screen me, half screen presentation.”

2. 📈 Adam's original XY-axis explanation is in the original user message at `/Users/adamblair/.codex/sessions/2026/10/31/rollout-2026-10-31T09-13-59-01a192bd-4290-7b72-9bf3-a7ca47777dc7.jsonl`, line 166. Exact excerpt:

> these obvious questions about, say, the XY axis, what, what's X, what's Y

3. 🗺️ His [Visual Content Decision Map](/Users/adamblair/Documents/Visual%20Content%20Decision%20Map.md) supplies his visual labels. Those labels informed the approved questions; they do not authorize renaming the existing Visual choices or assigning them to Themes.

4. 📄 [Visual templates](</Users/adamblair/Documents/social-media/artifacts/Visual templates/Visual templates.md>) preserves the original Summarize dictation and distinguishes the previous sixteen assistant-drafted questions from Adam's words.

5. 📥 Gemini's question sets remain unselected context. The approved questions came from this review, not from selecting those Gemini sets.

### Installed app verification

1. 🖥️ The signed Mac Catalyst Release build passed and is installed at `/Applications/SAVY.app`. Its executable matches the Release build exactly. The previous app bundle is preserved.

2. 📱 The signed iOS build passed and is installed on the connected physical iPhone. SAVY launched normally after installation.

3. 👁️ The actual installed Mac form displayed all four questions for all twelve Visuals. Matrices and Example were inspected visually. The compact crimson selector and rounded cream choices retain their appearance.

4. 📱 The actual iPhone form displayed all four approved questions for Matrices, Slides and Charts. Its opened Visual menu retained the existing icons and styling. Tapping the first Slides question showed the crimson cursor immediately below the question.

5. ✍️ Both blank verification forms were canceled without typing or saving. iPhone Mirroring was quit. Before installation, one restored phone draft contained only default questions and empty metadata; its backup was preserved before the empty form was canceled. A second preinstallation backup confirmed no open recovery draft.

6. 🧪 Seven focused model tests passed against the real model source in an isolated SwiftPM harness with no SAVY app host. The tests cover the catalog and all-format answer round trips. They also cover conservative legacy backfill and unknown formats. The existing UI-test Matrices expectation was updated; the automated Xcode UI suite was not rerun for this content update.

7. 💾 Mac comparison: 18 of 20 files are byte-identical. Phone comparison: 22 of 24 files are byte-identical. The only differences are `SAVY/CloudKit/state.json` and `SAVY/CloudKit/status.json`. Both reminder archives still contain 55 records. Recovery drafts are empty. No synthetic writing was added to either live app.

8. 📂 The [verification receipt](verification.json) contains build and installation evidence. The [native patch](questions%20under%20each%20Visual.patch) contains the catalog change and conservative backfill with its tests. Repository and Mac report copies match. Cowork copies are staged; cloud project upload remains unconfirmed.

9. 🗂️ Earlier draft-review results remain in Git history and in the original part of the verification receipt. The later installation evidence is recorded separately.

10. 🔧 SAVY has no GitHub Actions workflows configured. Both signed native builds were verified locally.
