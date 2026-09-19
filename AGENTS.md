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

## Current Lane

Update this line when the active milestone changes:

**Current lane:** Device-first shell + gateway health; wire validated RDF only to Belief Library and Pathway — audit non-RDF data paths. Do not expand scope without Adam saying so.

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

