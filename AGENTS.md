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

The cloud VM is **Linux with no Xcode/Swift toolchain**, so the iOS app (the `SAVY` target / `SAVY.xcodeproj`) cannot be built or run here. iOS build + tests are macOS-only — use the `xcodebuild` command in `README.md` on real Apple hardware. On the cloud VM, development is limited to the backend (the Vercel serverless API the iOS app calls).

### Repo layout (backend is an npm monorepo)

- `gateway/` — the real Vercel serverless TypeScript API (handlers + `lib/`). This is where backend logic lives.
- `api/` (repo root) — thin shims that re-export the `gateway/` handlers; Vercel deploys from the root and maps `api/v1/**` (see root `vercel.json`, `installCommand: "npm install && npm install --prefix gateway"`).
- `packages/suite-graph-engine/` — workspace package with deterministic RDF graph-trace helpers + its own tests.
- Install deps in all three: `npm install` (root), `npm install --prefix gateway`, `npm install --prefix packages/suite-graph-engine`.

### gateway (Vercel serverless TypeScript API)

- Tests: `cd gateway && npm test` (runs `test:engine` then `test:gateway` via `node --import tsx --test`). `tsx` is a gateway devDependency now, so no `npx --yes` needed. Caveat: one `rdf-import` test reads fixtures from a **sibling `understood-app/` repo** that is not checked out here, so it fails with `ENOENT … /understood-app/fixtures/...` — that is an external-dependency gap, not a code regression.
- Typecheck: `cd gateway && npx tsc --noEmit`. No ESLint config. Note: `tsc` currently reports pre-existing errors in `gateway/api/v1/reminders/[id].ts` / `[id]/image.ts` (relative import depth) and a `ws` type mismatch in `lib/supabase-axiom-bridge.ts`; these exist on `main` and Vercel still builds/deploys.
- `npm run dev` (`vercel dev`) **requires Vercel account credentials** and fails on the cloud VM with `No existing credentials found` unless you `vercel login` / pass `--token`. To exercise handlers without Vercel auth, invoke them directly: each handler is a plain default-export `(req, res)` function, so a tiny Node `http` harness (run with `tsx`, which resolves the `.js`→`.ts` ESM imports) can serve them. Augment `res` with `status()`/`json()` and `req` with `query`/`body`.
- Env: copy `gateway/.env.example` → `gateway/.env.local` (gitignored). `SUPABASE_URL` must be the project URL `https://<ref>.supabase.co` (NOT an `sb_secret_…` key — a swapped value yields `Invalid supabaseUrl`).
- Phases: production (`savy-gateway.vercel.app`) runs the full `aurora+neo4j` phase (`/api/v1/health` reports it). Locally, without `AURORA_HOST`/`DATABASE_URL`, the gateway falls back to the `supabase-bridge` phase, which needs `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` for `/api/v1/entries` + `/api/v1/correlations/latest` (else 500).
- Auth model: `/api/v1/health` is open; every other route requires header `x-api-key: $SAVY_API_KEY`. `/api/v1/auth/*` routes need AWS Cognito creds. Full route table lives in `gateway/README.md`.
