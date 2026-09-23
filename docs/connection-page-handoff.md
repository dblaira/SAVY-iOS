# Connection page — next-chat handoff

Updated September 23, 2026. This is the working handoff for the SAVY Connection work, including Adam's intent, accepted decisions, implementation, and unfinished work. It is not a verbatim transcript or a backup of Apple Notes or the phone's live entries.

## Start here

- Repository: `/Users/adamblair/Developer/GitHub/SAVY-iOS`, GitHub `dblaira/SAVY-iOS`, branch `main`, Xcode project/scheme `SAVY`. The conversation began in the social-media workspace, but this native app is the implementation repo.
- Read this handoff and `AGENTS.md` before continuing. Follow Adam's latest decisions below rather than earlier superseded palette trials in the historical sections of `AGENTS.md`.
- Adam currently needs his phone uninterrupted. Do not open iPhone Mirroring, connect a phone preview, run physical-device automation, reinstall, or restart SAVY until phone use is coordinated. The latest navy-header update is built and saved but **not installed on his phone**.
- Adam confirmed the current cream-and-tan Face ID screen is correct: "nothing. That is what I wanted. it looked different before." No Face ID repair is pending.

## Why Connection matters

Adam wants a beautiful, substantial collection of connections and beliefs in SAVY. It supports recognizing patterns across his interests and turning them into social posts, meeting interesting people, and developing an authentic way to market his apps and products.

His source material includes the Apple Notes titled `Value Capture 50 posts` and `50 Post Synthesis`. Pattern mining began with six saved SAVY social posts; that is historical context, not a current live count. The original Notes and handwritten images were not re-read as part of this handoff. Earlier pasted Claude analysis is context, not newly verified findings or an adopted implementation specification.

Adam has accounts on X, YouTube, Instagram, TikTok, LinkedIn, and Facebook. His initial volume goal was 30 posts per day total across surfaces, growing toward 300. Preserve breadth and his polymath interests. Do not reinterpret the project as specializing in a narrow content niche.

His requested Connection is already in `LeverageContent.addedConnections`, ID `polymath-specialization-kill-switch`, with this exact body:

> I am a polymath: therefore specialization is a kill switch.  Volume is the only way to sustainable interest.  Volume is beautiful because volume is where patterns can be seen.

Also already present there are `venture-capital-not-private-equity`, `volume-wonderful-outcome`, and `taste-not-new-moat`. His venture-capital statement is:

> Think about the difference between venture capital and private equity and understand that I think more like venture capital than private equity.

Adam asked for five new candidates to approve and warned that Claude was working on the same subject. Before proposing or saving new content, inspect the existing bundled, source-backed, and locally authored connections. Do not recreate these entries or assume an unapproved candidate is accepted. Preserve his wording. Nothing posts to social media on its own; Adam presses Post.

## Accepted Connection page and form

- Match the Social Media Posts page: serif heading, bare crimson back chevron, small add button beside the count, colored cards, larger pinned cards, compact unpinned cards.
- The add button opens the shared native entry form in Connection mode. Tapping a locally authored Connection reopens its editor. Tapping a source-backed card opens the original source detail.
- The fixed theme is **Your Personal Take & Lessons Learned**, with these editable prompts in order:
  1. What did you believe before?
  2. What experience changed or confirmed your connection?
  3. What do you believe now? What is the new connection?
  4. What do you do differently because of it?
- Keep complete question-and-answer fields, including edits to the question text. The third answer supplies the card's primary preview; the complete entry remains behind it.
- Keep the shared form's full metadata payload: title, notes, link, image reference, dates/times, repeat/urgency, list, flag, priority, context, outcome, effort, energy, success/compounding fields, deferred/waiting information, location, tags, subtasks, status, and timestamps. Do not reduce storage to the visible preview.
- The Connection and Post forms have white backgrounds, readable dark section labels, and existing cream field groups. Connection mode has its fixed theme and no Reminder/Action/Calendar/Post destination selector.
- Manual writing is implemented. Adam's earlier broader request for writing and formatting does not establish that a rich-text formatting toolbar was completed; the current form uses editable plain-text fields.

## Card behavior and appearance

- Use the existing Understood-style interaction: **swipe right** reveals Pin/Unpin and Delete. No always-visible pin toggle on Connection or Home cards.
- Any number of Connection cards may be pinned independently, including both source-backed and authored entries.
- Pinning moves that card to the very top, above existing pins. Unpinning moves it immediately below the remaining pins. Saved ordering survives relaunch.
- Reuse the shared long-press/rearrangement interaction within pinned or unpinned groups.
- Pinned Connection cards use the full shared card presentation with a 186-point minimum height. Unpinned cards use compact presentation. Card colors come from the Posts palette (white, dark red, tan, navy).
- No decorative left-side color strips. Closed swipe-action backgrounds must not show behind rounded corners. Keep existing horizontal title underlines and full card borders; Adam deferred broader border experimentation.
- Deleting an authored entry removes it from the local Connection archive. Deleting a source-backed card hides it persistently on this page without deleting its source or changing validated RDF. Home counts and previews exclude hidden source cards.

## Storage and authority

`ConnectionEntry` wraps the complete shared `Reminder` metadata model. `ConnectionStore` writes atomically to `Application Support/SAVY/connections.json`, storing authored entries, source pin overrides, and hidden source IDs. Connection order uses `savy.connections.cardOrder.v1` separately from Posts and Home.

Saving a Connection does not publish a social post, create a reminder/notification, enqueue Harness/candidate work, or make it validated RDF. Source-backed entries remain source-backed. Corrupt-file handling preserves the original archive instead of silently overwriting it.

The repo contains implementation and bundled connections, **not a backup of every live entry authored on Adam's phone**. Read the actual current app data when content deduplication or a live count is needed.

## Current app styling

- Deep navy `#08172D` replaces the lighter Lapis blue for shared headers, navigation bars, and the backdrops exposed during pull-down. Preserve the top-edge fade fix and overscroll background coverage together.
- Home has Adam's original mountain photo behind the cards, a navy header and above-navigation bands, and a thin 1-point crimson divider. Its native carousel remains 140 points tall and 282 points wide, with the approved 80-point landscape reveal.
- Other main pages keep white bodies and their existing thin white dividers. The tan bottom navigation remains the exact shared `Color(red: 0.80, green: 0.70, blue: 0.58)`.
- Face ID remains cream-to-tan with red SAVY lettering and dark-brown account/password wording. It is intentionally separate from page-header colors.
- Adam wants to add image backgrounds to other pages using images he supplies; different pages may have different images. This is future work, not permission to select arbitrary images.

## Delivery and verification

- `5f683b2`: Connection authoring, shared form, swipe-only Connection/Home pin controls, newest-pin ordering, white forms.
- `bf92eeb`: approved mountain homepage and app-wide clean card edges. Installed and physically observed before this handoff.
- `f15e018`: shared navy page headers. Built and pushed; **physical-phone installation remains pending** because Adam needs the phone free.
- Earlier recorded validation: 23 Mac-hosted Connection/Home model checks passed, covering metadata/storage and pin/order behavior. Full Connection author/edit/delete UI acceptance tests are present but have not been run on Adam's physical phone. Do not turn build or model-test success into a claim of physical UI verification.
- Adam previously confirmed the header repair: "On device, pull down worked". That confirmation predates the newest navy palette update.
- The newest navy update has eight visually reviewed simulator held-pull screenshots: Home, Actions, Reminders, Calendar, Connection, Posts, Ontology, Field Essays. Five automated cases passed; three capture-receipt accessibility checks failed even though their screenshots and negative-offset metadata were saved and inspected. See the linked verification notes for the exact limitation.
- Personal Authority review has a separate known testing hazard: its default store can write live approvals on initialization. Do not casually open it during automated inspection without isolating that store too.

## Code and evidence map

| Area | File |
| --- | --- |
| User decisions and project rules | [`../AGENTS.md`](../AGENTS.md) |
| Connection list, add button, cards, pin/delete/open behavior | [`../SAVY/ConnectionView.swift`](../SAVY/ConnectionView.swift) |
| Fixed four questions, metadata, archive and source overrides | [`../SAVY/ConnectionStore.swift`](../SAVY/ConnectionStore.swift) |
| Shared native form and Connection mode | [`../SAVY/ReminderFormView.swift`](../SAVY/ReminderFormView.swift) |
| Complete metadata model | [`../SAVY/ReminderModels.swift`](../SAVY/ReminderModels.swift) |
| Editable questions and answers | [`../SAVY/PostTheme.swift`](../SAVY/PostTheme.swift) |
| Persistent pin-group ordering | [`../SAVY/PostCardOrderStore.swift`](../SAVY/PostCardOrderStore.swift) |
| Existing added Connection statements | [`../SAVY/LeverageContent.swift`](../SAVY/LeverageContent.swift) |
| Shared header backgrounds and navy token | [`../SAVY/RootView.swift`](../SAVY/RootView.swift), [`../SAVY/SavyShellComponents.swift`](../SAVY/SavyShellComponents.swift) |
| Connection storage tests | [`../SAVYTests/SAVYConnectionStoreTests.swift`](../SAVYTests/SAVYConnectionStoreTests.swift) |
| Connection UI acceptance tests | [`../SAVYUITests/SAVYConnectionEntryUITests.swift`](../SAVYUITests/SAVYConnectionEntryUITests.swift) |
| Approved mountain image and physical evidence | [`design/2026-09-23-mountain-home/README.md`](design/2026-09-23-mountain-home/README.md) |
| Latest navy screenshots and verification limits | [`design/2026-09-23-navy-headers/README.md`](design/2026-09-23-navy-headers/README.md) |

Resume from Adam's next request. Keep his phone free, preserve the confirmed Face ID screen, and distinguish the installed mountain build from the newer navy-header build waiting on the Mac.
