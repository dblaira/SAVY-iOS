# SAVY iOS Agent Instructions

## Native iOS Rule

SAVY iOS is a 100% native Apple-platform app.

The shipped iPhone app must be built in Xcode using Swift, SwiftUI/UIKit, and Apple native frameworks. Do not implement the iOS product as a web app, PWA, WebView shell, React Native app, Capacitor app, Expo app, TypeScript frontend, or browser-hosted experience.

Vercel and Supabase may remain backend, API, auth, storage, deployment, or admin infrastructure. They are not the iOS runtime.

Product UI/UX source of truth may be explored in the Figma macOS app and implemented in the Xcode macOS app. Device validation should prioritize real iPhone hardware. Avoid simulator-first thinking unless Adam explicitly requests it for a narrow diagnostic.

Acceptance criteria: if it is part of the shipped iPhone app experience, it should feel, behave, and integrate like a real App Store iOS app with direct access to Apple platform capabilities.

## Plan Overview Rule

Adam keeps `docs/savy-migration-map.html` on screen as the living status board. Suite-wide progress: `docs/understood-suite-migration-map.html`.

When sharing multi-step plans or migration status: **overview first** — one sentence, horizontal progress track (all steps on one screen), "HERE" on current step, one-line next move. Details below or collapsed. Update the HTML when milestones change. See `.cursor/rules/plan-overview.mdc`.

## RDF Authority Gate

Only Protégé → Docker-validated W3C RDF triples (`source_app` `understood` or `recall` in `savy.rdf_triples`) may power Belief Library and Pathway. Postgres rows, Neo4j, statistical correlations, and `sync-entries` backfills are not product authority. See `.cursor/rules/rdf-authority.mdc`.

## Execute, Don't Delegate

If the agent can run it (git, shell, `xcodebuild`, `gh`, deploys, file edits), **the agent runs it**. Do not return long manual steps or Xcode menu tutorials for work the agent can execute. Ask Adam only for human-only actions (unlock phone, passwords, design judgment) — one sentence, no checklist. See `.cursor/rules/execute-dont-delegate.mdc`.

## Product Rule

This app is being built for Adam first. Adam's taste, language, understanding, and natural reaction are the acceptance criteria. Do not optimize for a hypothetical average user before Adam has reacted.

## Reuse Proven Product Rule

SAVY is Adam's daily work surface. When a requested artifact, review queue, approval flow, visualization, or Cowboy AI feature can live in SAVY, implement it natively inside SAVY before creating a parallel website or dashboard. Reuse SAVY's current navigation, typography, palette, graphics, data, and phone interaction patterns. A standalone artifact may be used only as a temporary design proof unless Adam explicitly chooses it as the final product.

When Adam's iPhone is connected, carry native work through Xcode build, device installation, launch, and visible verification. Report progress as a percentage and preserve Adam's exact wording and formatting hierarchy.

## Technical Boundaries

- Swift and Apple frameworks are the app runtime.
- Xcode is the build surface.
- Figma is the design exploration surface.
- Supabase is allowed as backend/storage/auth.
- Vercel is allowed as backend/admin/web infrastructure.
- No WebKit/WebView in the app target unless Adam explicitly reverses this rule.
- No JavaScript or TypeScript application runtime in the iOS app.
- No simulator-first workflow unless Adam explicitly asks for it.
- No audio in the app for now — Adam, 2026-09-02: "remove the listen with Cowboyai feature. I don't want to include an audio feature on the app for now." The voice panel and its controllers stay in the code with no entry points; do not wire them back in without Adam saying so.
- The post entry page stays as it is — Adam, 2026-09-02, 10:00 pm, with screenshots of the News Channel page and the post form: "On 2nd thought I really like the layout of these pages. The Jab and hook will be replaced with different terms I chose later. But let's keep the entry page as is." On 2026-09-03 Adam supplied his terms: "Change the words to \"News\" and \"Advertising\"" — News gives, Advertising asks. Do not add other borrowed language. Superseded for the bolt's Post door on 2026-09-13: Adam approved the Post-as-fourth-entry-type mockup ("That looks good. Let's build that.") — the bolt's Post door opens the shared entry form (Reminder | Action | Calendar | Post) with Theme + Decide above the full Reminder body. The SocialPost form (News/Advertising, 280-character box) stays reachable from the Social Media Posts +.
- The homepage card and page that held posts is Social Media Posts — Adam, 2026-09-19: "Let's call news channel social media posts." and "They should not be hidden on the homepage." Greatest Leverage is gone from the homepage — Adam, 2026-09-19: "Remove greatest leverage from the homepage and just move up, move the carousel up." The whole carousel card stays visible under the red line — Adam, 2026-09-19: "I want to see the whole card in the carousel. the top is obscured buy the red line." One of Connection, Adam's Ontology, Field Essays, or Social Media Posts can be pinned to the top of that area — Adam, 2026-09-19: "give me the option to pin one of those to the top of that area, that way as my taste change I can have different top areas to view first." Cards under the carousel are the Understood band cards — white, dark red, tan — on the white that sits behind the carousel. Adam, 2026-09-19: "whatever is pinned is much larger than the cards that are not pinned, so go back, look at the code, and see how it was actually built, and then create a very light background for these, and what I mean by that is the background that's behind the cards in the carousel, let that be the background behind the cards or the different rows of cards in the Savvy app that are below." Size is ActionsHomeView's scale (1.08 / 1.02 / 1) and BandCard detail (full / medium / minimal). The cards themselves are not the cream carousel cards. The copy he is signed into is the iPhone — Adam, 2026-09-19: "I'm billing in on my phone right now. I'm not signing in to some bullshit simulator." Nothing posts on its own; Adam presses Post in X.

## Post entry and Social Media Posts — September 21, 2026

Adam approved the expanded-question mockup and asked to update his connected iPhone through Xcode. Decide questions are normal editable prefilled text, with room for the answer underneath in the same expanding field. Save and agent retrieval preserve the full question and answer together; existing answers must survive the change.

The Social Media Posts + now opens the same shared Post entry form as the bolt, with all 28 templates and red SF Symbol icons matching the form. This replaces the older + routing to SocialPostFormView; existing older posts still open their original editor. Any number of posts may be pinned at the top of the post list, independently. The page header uses the homepage's deep navy and omits the redundant red SOCIAL MEDIA POSTS eyebrow. Its back arrow is a small crimson chevron with no circular background or outline.

Physical-device UI tests must use isolated storage and must not write synthetic entries to the live cache, cloud, Harness queue, or HarnessedRegistry.

## Page styling — September 21, 2026

Adam approved navy behind every page, including the homepage carousel and lower card rows, with the existing colored cards and navigation retained. Page headings use the same `SavyTypography.displaySerif` face as SAVY and Reminders (Bodoni 72 Oldstyle), in white on the navy canvas. Compact titles inside the existing white form navigation bars use that face in navy. Keep status-bar text readable on navy.

Adam: "There should be no subtitle underneath the main title of the page." Remove decorative page subtitles, including the Social Media Posts summary and weekly brief headline, and the Reminders/Actions/Connection taglines. Saved story subtitles, post answers, article content, account guidance, and source attribution remain content.

Face ID sign-in is the background exception: Adam requested a subtle vertical gradient from the existing light sand (`Brand.card`) above the content to the navigation brown (`SavyTheme.bottomNavTan`) at the bottom. Adam then requested the SAVY label in red (`SavyTheme.crimson`) and the user ID and password wording in darker brown (`Brand.tabActive`). Preserve the fonts, controls, and positions on that page.

## Lapis background trial — September 23, 2026

Adam requested: "Replace the navy blue background we have with this LAPIS blue color so I can work with this today and see how it feels." His supplied Lapis Lazuli swatch is `#243F86` (RGB 36, 63, 134). This supersedes navy for page canvases, page headers, navigation-bar backgrounds, and the band above the bottom navigation. Use `SavyTheme.pageBackground`; retain `deepNavy` for existing text, cards, controls, and graphics. The Face ID sand gradient remains separate. Color comes first; Connection writing and formatting are subsequent work.

## White content and yellow divider — September 23, 2026

Adam refined the Lapis trial: "Change the main background under the header to white. The navigation and header background colors should remain the same. And replace the thin red boarder underneath the header with yellow color." Main page content uses `SavyTheme.contentBackground` (white), existing headers/navigation retain Lapis `pageBackground`, and existing thin under-header dividers use `SavyTheme.headerDivider` (`#DFFF00`, tennis yellow). Text directly on white uses dark ink. Keep card colors, red action controls, and the Calendar now-line. Keep iPhone Mirroring closed while Adam tries the app on his phone.

The main `RootView` navigation hierarchy uses `savySolidTopScrollEdge()` to disable the iOS 26+ automatic top scroll-edge fade across Home, Actions, Reminders, Calendar, Connection, Social Media Posts, Ontology, Field Essays, and their detail pages. Apply this at the shared navigation root, not only to Home: Adam reported the same pale header strip on the other pages. Keep the availability guard for iOS 18 support. Adam approved reducing carousel cards from 182 to 140 points tall (546 to 420 physical pixels on his 3x iPhone). Width remains 282 points (846 pixels).

## Yellow content background trial — September 23, 2026

Adam replaced the white content background with the existing divider yellow: "Let's try the yellow that you used for the border, so let's use that yellow for the background and see how that works." `SavyTheme.contentBackground` and `headerDivider` both use `tennisYellow` (`#DFFF00`). This supersedes white for main content. Retain the Lapis headers/navigation, dark body text, existing card colors, and approved 140-point carousel height. Keep iPhone Mirroring closed.

Adam subsequently said yellow is too bright and is still choosing a main background. His next requested change is the header coverage on the other pages; no replacement background color has been selected.

## Navigation-matched content and white divider — September 23, 2026

Adam requested the exact bottom navigation panel color for the main content, replacing yellow, with a very thin white header divider. Both navigation `barBackground` and main `contentBackground` reference the existing `SavyTheme.bottomNavTan`: `Color(red: 0.80, green: 0.70, blue: 0.58)`. Reuse this shared value; do not sample or approximate it. `headerDivider` is white and `RootHomeLayout.heroDividerHeight` is 1 point across Home, Posts, Connection, Actions, Reminders, and Calendar. Keep Lapis headers/navigation upper bands, the shared top-edge fix, and the approved 140-point carousel cards.

## White content and header pull-down repair — September 23, 2026

Adam restored white main content and explicitly deferred card borders. Keep Lapis headers, the existing tan bottom navigation, 1-point white header dividers, and 140-point carousel cards.

A solid header alone does not cover the area exposed when a ScrollView is pulled down. Every page with a scrolling Lapis hero must use a Lapis viewport backdrop plus `savyHeaderPageContent(minHeight:)` on the full scrolling stack. That shared modifier paints white under the content, fills short pages, and extends white below the content for bottom bounce. Keep `savySolidTopScrollEdge()` at the navigation root too; disabling the iOS edge fade and painting the overscroll backdrop solve different defects.

Regression verification must inspect the actual screen during a downward pull, not only after it springs back. `SAVYHeaderOverscrollUITests` uses existing isolated test stores; the DEBUG-only capture hook requires both the capture flag and isolated test launch flag. Coordinate phone use with Adam before running UI tests because prior control prevented him from using the app.

Verification: the app and UI tests build successfully and the update is installed on Adam's iPhone. After the changes were saved, Adam confirmed: "On device, pull down worked". This is Adam's on-device confirmation of the reported pull-down repair; the eight-page automated UI tests have not run.

## Connection authoring and Post form background — September 23, 2026

Adam requested that Connection look like Social Media Posts: the same header/back treatment, small + button beside the count, shared colored cards, larger pinned cards, compact unpinned cards, and any number of independent pins at the top. Both existing source connections and newly authored connections can be pinned. Keep the original source bodies available. The + opens the native shared entry form in Connection mode, and authored cards reopen that form for editing.

Reuse "Your Personal Take & Lessons Learned" with these editable questions in order: "What did you believe before?", "What experience changed or confirmed your connection?", "What do you believe now? What is the new connection?", and "What do you do differently because of it?" Preserve all shared form metadata. The third answer supplies the new Connection card's preview. Keep the existing Post theme unchanged. Both the Post and Connection entry forms use white backgrounds with readable dark section labels and the existing cream field groups.

Authored Connections use a separate atomic local archive in Application Support/SAVY/connections.json, retaining the complete shared metadata payload. They do not enter the Reminder/Post feeds, notifications, Harness, or validated RDF merely by being saved. Existing source connections remain source-backed. UI tests use the isolated SAVYUITests archive and preference suite.

Implementation checkpoint: the iPhone app and acceptance tests build successfully, twelve Mac-hosted tests against the actual Connection storage/model and card-order sources passed, and the swipe-action update is installed on Adam's iPhone. Tests cover new-pin priority, unpin placement, retained ordering after relaunch, independent Post ordering, and persistent source-card deletion. The new Connection/Post form UI tests have not run; on-device interaction verification awaits phone-use coordination. Existing Post editor backgrounds are white too.

Adam then specified Understood's interaction: swipe right to reveal Pin/Unpin and Delete; no persistent pin icon on a Connection card. Reuse the existing `SavyUpNextCardRow` actions, matching the current Understood app in Re_Call. Pin moves the chosen card to the very top above existing pins; Unpin moves it immediately below the remaining pins. Preserve unlimited pins and larger pinned cards. Delete removes authored entries or persistently hides a source-backed card in Connection without modifying its source or validated RDF. Home counts and previews exclude deleted source cards.

Adam removed the red side coloring from Connection cards. Leave the shared band's optional `leadingEdge` unset for every Connection card.

Adam extended this treatment to the homepage: remove persistent pin icons from Home destination cards, keep Pin/Unpin behind a right swipe, and put each newly pinned card at the very top. Unpin moves a card directly below the remaining pins. Retain independent unlimited pins, larger pinned cards, and saved ordering. The shared swipe action tray is hidden and noninteractive while closed, so its color cannot show behind rounded card corners.

Home checkpoint: the update is built and installed on Adam's iPhone. Eleven Mac-hosted Home model checks passed, including newest-pin priority, unpin placement, independent pins, idempotency, migration, and relaunch. The UI acceptance test now checks those positions explicitly and verifies closed actions are not tappable; it has not run on the phone.

Adam approved the delivered state and requested a saved checkpoint: "Perfect. Save what we have so far. This is great". Save the Connection authoring, white forms, swipe-only pin controls, newest-pin ordering, and clean card edges together. The build and 23 Mac-hosted model checks passed; the automated iPhone UI tests remain unrun.

## Numbered Post cards — September 21, 2026

Adam approved the numbered Post layout: reuse the Reminders display, show the first authored sentence plus metadata, make pinned cards larger with more detail, and rotate white, dark red, sand, and navy across the displayed list. The inline count measures saved posts toward 50; it includes both shared-form Post entries and older SocialPost entries. This is a saved-post goal, not a publication count.

Adam refined the density after using the page: unpinned Posts show one preview line with an ellipsis and compact metadata so four or five cards fit. Only pinned Posts expand to show the full first sentence and more detail; the first card is never enlarged merely because of its position. The Reminders example remains the visual reference. Remove the Cowboy AI hat from Post cards.

Post numbers are stored references, assigned across both formats in creation order initially and retained across pinning, editing, and relaunch. The local allocator retains deleted assignments so a later post does not reuse a number. Keep full saved questions and answers intact behind the display preview. Number assignment must not invoke the Harness/candidate capture pipeline or cause an older clean cache to overwrite newer remote content.

## Card rearranging — September 21, 2026

Adam requested the existing Understood interaction from the former Notorious Recall app (`Re_Call`, `sh.notorious.app`) for SAVY's lower homepage rows, Social Media Posts, and Actions. Reuse its UIKit long press, red glow, lifted card, up/down chevrons, haptics, and short vertical drag. The shared row also serves Reminders. Preserve normal scrolling and swipe actions.

Move one position within the screen's visible pinned or unpinned group. Actions and Reminders must skip hidden entry kinds when choosing a neighbor. Home retains its existing single pinned destination. Home and Post positions are local display preferences; moving a Post never changes its stored number, full questions and answers, pin state, or capture history. Keep the two Post formats in one reorderable list, using source-qualified IDs. UI tests use isolated content and layout preferences.

## Current Lane

### Multiple Home pins — September 21, 2026

Adam: "i should able to pin as many of the four as I like on the homepage.  There will be more in the future.  Right now I can only pin one. change that to the ability to pin all."

This supersedes the earlier single-pin Home rule. Each destination pins independently, with no maximum. Keep pinned cards above unpinned cards and allow rearranging within either group. Preserve an existing single pin, an explicitly unpinned Home, and saved order when migrating preferences. Reuse the approved card component and pin gesture.

### Home card density — September 21, 2026

Adam rejected the oversized Home mockup: "too large.  you already have an example that i like. why not just use it?? Actions. Reminders. Don't outwork the problem."

Use the existing `SavyBandCard` component directly for Home, with its existing typography, spacing, and three-line detail limit. Pinned sections show relevant counts and previews; unpinned sections use its compact title-only layout. Remove repeated section eyebrows, including SOCIAL MEDIA POSTS and CONNECTION. Social Media Posts uses the saved count, stored post numbers, and first authored preview from the same ordered records as the Posts page. Do not change the carousel size as part of this work.

Update this line when the active milestone changes:

**Current lane:** Home supports independent pins with no maximum; all four destinations can remain pinned together, and both pin groups can be rearranged. Existing single-pin and explicitly unpinned preferences migrate with saved order intact. All-four pinning, independent unpinning, group boundaries, and relaunch persistence are verified on Adam's connected iPhone. Home uses the existing Actions/Reminders card component, compact unpinned titles, and no repeated eyebrows. Carousel cards are 140 points tall and 282 points wide. Preserve the September 23 Lapis headers/navigation, white main content, Lapis pull-down backdrops, and 1-point white header dividers, Bodoni headings, saved Post questions and answers, stored numbers, unlimited Post pins, shared 28-template entry, red framework icons, and the bare back chevron. Validated RDF remains limited to Belief Library and Pathway.

## How agents use Adam's Macs (required)

Adam signed up for Tailscale so agents work **on his real computers** — the ones already signed into his accounts — not on a blank rented machine that has to fight every login.

**Default rule:** Do the work on his Macs. Prefer `studio` (Mac Studio). Use `mbp` or `mbp2` when the task belongs there.

When Tailscale is joined (secrets `TAILSCALE_AUTHKEY` + `TAILSCALE_SSH_KEY`):
- `ssh studio` — Mac Studio — primary
- `ssh mbp` — MacBook Pro
- `ssh mbp2` — MacBook Pro 2

**Do not say you cannot access his files, apps, builds, or signed-in sessions** without first trying his Macs. If a website or app needs a login, do it from his Mac (already trusted), not from the cloud box.

If Tailscale is not joined yet, run: `bash .cursor/tailscale-join.sh`


## Skills to load (do not skip)

Always: requirement-is-the-test, adams-words, no-time-estimates, cognitive-fit, articulate-leadership-communication.

Stack (when editing matching files): see `.cursor/rules/stack-*.mdc` — nextjs / react-best-practices / figma-swiftui / aws-lambda / context7 / systematic-debugging.

If the same mistake happens twice: create a rule. Prefer system over apology.
