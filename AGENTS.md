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

**Current lane:** Home supports independent pins with no maximum; all four destinations can remain pinned together, and both pin groups can be rearranged. Existing single-pin and explicitly unpinned preferences migrate with saved order intact. All-four pinning, independent unpinning, group boundaries, and relaunch persistence are verified on Adam's connected iPhone. Home uses the existing Actions/Reminders card component, compact unpinned titles, and no repeated eyebrows. Carousel dimensions are unchanged. Preserve navy canvases, Bodoni headings, saved Post questions and answers, stored numbers, unlimited Post pins, shared 28-template entry, red framework icons, and the bare back chevron. Validated RDF remains limited to Belief Library and Pathway.

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
