# add ChatGPT

Review this approach before Adam approves anything. This document is not authorization to implement, install, or deploy. Preserve SAVY's existing appearance and form interactions.

The proposed route uses the installed Codex CLI with Adam's existing ChatGPT login, alongside the current Claude bridge. It does not inherit the context, memory, or tools of this existing chat; SAVY must supply the conversation it owns.

## provide the instructions

1. 🔀 **Add Claude and ChatGPT selection to the existing Send to area and the Respond form. Allow either or both. Disable Send when neither is selected. Show the responding provider in the compact reply area and History. Never silently send a ChatGPT request to Claude.**

2. 🧾 **Freeze the actual form before dispatch: request ID, entry/draft ID, parent reply ID, selected providers, exact original writing, draft Theme/Visual, and ordered stable question IDs with their prompts/icons. Include the selected conversation's complete ancestry and all earlier user follow-ups, especially “What must stay?” answers. Both providers receive the same snapshot.**

3. 🔌 **Extend the existing Python bridge with validated JSON requests and an allowlisted provider. Keep its Claude adapter; add a ChatGPT adapter invoking `/Users/adamblair/.local/bin/codex`. Use subprocess arguments and stdin, not a shell-built command. Reuse CLI authentication without copying login tokens into SAVY. Move the current helper out of Claude's temporary scratch directory into the project.**

The installed CLI is version `0.162.0`. `codex login status` returned `Logged in using ChatGPT`. Its local help confirms the following argument specification:

```text
/Users/adamblair/.local/bin/codex exec
  --sandbox read-only
  --skip-git-repo-check
  --ephemeral
  --output-schema <absolute schema path>
  --output-last-message <absolute result path>
  -
```

Substitute real per-request paths in code and pass the entire prompt/context through stdin. Run from an isolated request directory. After process completion, check the exit code and parse the result file. Do not mistake stdout diagnostics for the answer. Handle timeout, authentication failure, and cancellation without losing the request. Use the configured account-accessible model rather than inventing a model identifier.

4. 📦 **Require schema-validated JSON shaped as `{"answers":[{"question_id":"…","text":"…"}]}`. Match every question ID exactly once against the frozen request. Retain invalid raw output for recovery and report an error instead of silently padding, truncating, or misassigning answers. Store each provider's result and status separately so whichever finishes last cannot overwrite the other.**

`--ephemeral` deliberately leaves conversation ownership in SAVY. Every request must include its full relevant ancestry. Keep the full archive; if explicit context compaction becomes necessary, retain the user's exact constraints. Do not silently drop old instructions or claim success on an oversized request. A persistent Codex App Server adapter can be considered later; it is not required for this first bridge extension.

5. 💾 **Persist requests before dispatch and replies before displaying success. Use a retained coordinator with durable job records, independent of the sheet. Restore unsent Respond fields and provider selection. Deduplicate by `(requestID, provider)` and retry only the failed provider. Save, dismissal, backgrounding, and relaunch must not lose pending work or original writing.**

6. 📱 **For the physical iPhone, extend SAVY's existing private CloudKit transport with explicit AI request/result records. The Mac SAVY app receives a queued request, hands it to the local helper, and syncs the saved reply back to the same iPhone entry. Designate one Mac worker and use atomic claims to avoid duplicate execution. Keep jobs visibly queued while the Mac, app, or helper is unavailable.**

This phone route is a proposed extension, not an existing capability. `127.0.0.1:8787` only reaches the current helper from the Mac/simulator. Mac Catalyst should call the separate helper rather than attempt to launch the CLI inside the app. Preserve private account/zone checks. Keep job sync separate from authored-entry Save, Calendar, and Harness side effects. Do not revive the disabled AWS login or create public access.

7. 📖 **Open replies on the answer, with the submitted Respond form behind one expandable context row. Reserve space for the Respond control so it does not cover text. Render old replies with their saved question snapshots; changing Theme or Visual must not relabel history. Keep one compact current-reply area and one History row on the entry.**

## review it before approving

1. 🧪 Verify Claude alone, ChatGPT alone, both together, and independent failure/retry of either provider.

2. 🧠 Verify exchange-one instructions are still supplied at exchange thirty and branches from older replies use the correct ancestry.

3. 🗂️ Verify fresh unsaved forms and later Theme/Visual changes preserve correct historical question labels and original answers.

4. 💾 Verify pending sends and unsent Respond drafts survive dismissal/relaunch, and retries do not duplicate replies.

5. 📱 Demonstrate the physical-iPhone round trip separately from simulator behavior. Verify delivery when the Mac returns after being unavailable.

## show this to ChatGPT

Source inspected November 8, 2026:

`/Users/adamblair/Developer/GitHub/SAVY-iOS/.claude/worktrees/content-schedule-planning-64ba25`

Branch at review: `claude/ai-communication-interface-b714f9`, with uncommitted changes to preserve.

| File within that worktree | Integration point |
| --- | --- |
| `SAVY/ReminderFormView.swift` | `sendToAIRow`, `sendToAI()`, `shareContent`: selections and snapshot from the actual draft. |
| `SAVY/SendToAI.swift` | `ask`, `rawReply`, `followUpMessage`, `answers`: adapters, context, schema validation. |
| `SAVY/ReminderModels.swift` | `AIExchange`, `aiAnswers`: immutable request, separate provider results, backward-compatible decoding. |
| `SAVY/AIHistoryView.swift` | `AIReplyView`, `AIRespondView`: original question labels, provider attribution, collapsed context. |
| `SAVY/EntryDraftStore.swift` | Atomic recovery for response fields and selections. |
| `SAVY/CloudKitDocumentSync.swift` | Private job transport, result delivery, account-scoped ownership. |

Local code confirms the private CloudKit database, container `iCloud.com.adamblair.harness`, and zone `SAVYEntriesV1`. This proves a transport exists to extend, not that an AI queue already works.

OpenAI documents saved-login reuse and schema-constrained final output in [Non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode). [Codex App Server](https://learn.chatgpt.com/docs/app-server) documents the optional persistent thread alternative.

No model request, app-code edit, installation, or deployment was performed to prepare this brief.
