# SAVY iOS Agent Instructions

## Native iOS Rule

SAVY iOS is a 100% native Apple-platform app.

The shipped iPhone app must be built in Xcode using Swift, SwiftUI/UIKit, and Apple native frameworks. Do not implement the iOS product as a web app, PWA, WebView shell, React Native app, Capacitor app, Expo app, TypeScript frontend, or browser-hosted experience.

Vercel and Supabase may remain backend, API, auth, storage, deployment, or admin infrastructure. They are not the iOS runtime.

Product UI/UX source of truth may be explored in the Figma macOS app and implemented in the Xcode macOS app. Device validation should prioritize real iPhone hardware. Avoid simulator-first thinking unless Adam explicitly requests it for a narrow diagnostic.

Acceptance criteria: if it is part of the shipped iPhone app experience, it should feel, behave, and integrate like a real App Store iOS app with direct access to Apple platform capabilities.

## Plan Overview Rule

Adam keeps `docs/savy-migration-map.html` on screen as the living status board.

When sharing multi-step plans or migration status: **overview first** — one sentence, horizontal progress track (all steps on one screen), "HERE" on current step, one-line next move. Details below or collapsed. Update the HTML when milestones change. See `.cursor/rules/plan-overview.mdc`.

## RDF Authority Gate

Only Protégé → Docker-validated W3C RDF triples (`source_app` `understood` or `recall` in `savy.rdf_triples`) may power Belief Library and Pathway. Postgres rows, Neo4j, statistical correlations, and `sync-entries` backfills are not product authority. See `.cursor/rules/rdf-authority.mdc`.

## Execute, Don't Delegate

If the agent can run it (git, shell, `xcodebuild`, `gh`, deploys, file edits), **the agent runs it**. Do not return long manual steps or Xcode menu tutorials for work the agent can execute. Ask Adam only for human-only actions (unlock phone, passwords, design judgment) — one sentence, no checklist. See `.cursor/rules/execute-dont-delegate.mdc`.

## Product Rule

This app is being built for Adam first. Adam's taste, language, understanding, and natural reaction are the acceptance criteria. Do not optimize for a hypothetical average user before Adam has reacted.

## Technical Boundaries

- Swift and Apple frameworks are the app runtime.
- Xcode is the build surface.
- Figma is the design exploration surface.
- Supabase is allowed as backend/storage/auth.
- Vercel is allowed as backend/admin/web infrastructure.
- No WebKit/WebView in the app target unless Adam explicitly reverses this rule.
- No JavaScript or TypeScript application runtime in the iOS app.
- No simulator-first workflow unless Adam explicitly asks for it.

## Cursor Cloud specific instructions

Cloud Agent VMs are **Linux**, so the shipped iOS app (`SAVY.xcodeproj`) cannot be built or run here — that requires macOS + Xcode. On this VM only the **Node/TypeScript backend gateway** is runnable and testable: the Vercel serverless functions under `gateway/api/**` (re-exported by the root `api/**`), the helpers in `gateway/lib/**`, and the `packages/suite-graph-engine` package.

- **Runtime:** Node 22 is preinstalled; `package.json` pins `engines.node` to `20.x`, so `npm install` prints an `EBADENGINE` warning. It is only a warning — tests and the handlers run fine on Node 22.
- **Tests:** `cd gateway && npm test` runs the engine + gateway suites (commands defined in `gateway/package.json`). One gateway test (`gateway/test/rdf-import.test.ts`) reads a fixture from a sibling repo at `../../../understood-app/fixtures/ontology/suite-triples.json`. That repo is not checked out here, so that single test fails with `ENOENT`; everything else passes. This is an external-repo gap, not a code bug.
- **No lint/build gate:** there is no lint script and no build step (functions are deployed by Vercel with `noEmit`). `npx tsc --noEmit` in `gateway/` is **not** clean on a stock checkout (dynamic `[id]` route files aren't matched by the tsconfig `include` glob, plus a `ws` type mismatch), so don't treat raw `tsc` as a pass/fail gate.
- **Running the gateway:** the documented dev command is `vercel dev`, which requires Vercel credentials (`vercel login` / `VERCEL_TOKEN`) and will not start offline. Without credentials, the handlers are plain `(req, res)` functions and can be smoke-tested by importing them directly via `tsx` behind a tiny Node HTTP adapter. `GET /api/v1/health` needs no secrets and reports the active phase (`supabase-bridge` when neither `AURORA_HOST` nor `DATABASE_URL` is set). All non-health routes require an `x-api-key` header matching `SAVY_API_KEY` (put it in `gateway/.env.local`).
