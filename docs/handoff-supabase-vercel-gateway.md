# Handoff — Wire SAVY gateway ↔ Supabase ↔ Vercel

> **Status:** Supabase project verified live. The SAVY gateway is **not** deployed to the Vercel project Adam was inspecting (`dblaira-github-io` is a Next.js web app, not the gateway). Open question: where (if anywhere) is the gateway deployed, and is that project connected to Supabase.

---

## Copy‑paste prompt for the desktop agent

```
You are picking up a SAVY task in the Cursor desktop IDE (Vercel + Supabase MCP servers are available here; they were NOT authable in the prior cloud agent).

Context: SAVY has a native iOS app (Swift, macOS/Xcode only) and a Vercel serverless backend at `gateway/` (TypeScript) that the iOS app calls via AWSGraphClient. The gateway runs in "supabase-bridge" phase, reading from Supabase with a service role key. Routes: GET /api/v1/health (open), GET /api/v1/entries, GET /api/v1/captures, GET /api/v1/correlations/latest, POST /api/v1/auth/* — all non-health routes require header `x-api-key: $SAVY_API_KEY`.

Verified facts (from prior session):
- Supabase project ref = `wqdacfrzurhpsiuvzxwo` → correct base URL is `https://wqdacfrzurhpsiuvzxwo.supabase.co`.
- The service_role key (JWT) is valid: decoded `ref` claim = wqdacfrzurhpsiuvzxwo, role = service_role. A live REST call returned real `entries` rows. Running the gateway locally with the CORRECT url returns real data (e.g. entry "Focus on What's in Your Control").
- BUG: the env var `SUPABASE_URL` was set to an `sb_secret_…` API key value instead of the URL, causing `Invalid supabaseUrl` 500s until corrected.
- The Vercel project `dblaira-github-io` is a Next.js "savy" web app (root returns 200), but `/api/v1/health` = 404 — so the SAVY gateway is NOT deployed there.

Do this:
1. Use the Vercel MCP to list projects and env vars. Find which project (if any) hosts the gateway (look for one deployed from this repo / with /api/v1/health). Confirm whether `dblaira-github-io` is meant to be the gateway or a separate site.
2. On whichever project should host the gateway, verify these env vars (all environments): SAVY_API_KEY (any long random string), SUPABASE_URL = https://wqdacfrzurhpsiuvzxwo.supabase.co (a URL, NOT a key), SUPABASE_SERVICE_ROLE_KEY = the service_role JWT for project wqdacfrzurhpsiuvzxwo. Fix any swapped/wrong values.
3. Use the Supabase MCP to confirm the project ref, the service_role key, and that the `entries` and `correlation_analyses` tables exist.
4. If the gateway is not deployed anywhere, deploy `gateway/` as its own Vercel project (`cd gateway && npm install && npx vercel link && npx vercel --prod`) with the three env vars set, then GET <deploy>/api/v1/health and confirm `phase: "supabase-bridge"`.
5. Put the final gateway base URL + SAVY_API_KEY into `SAVY-Secrets.xcconfig` (AWS_API_BASE_URL must end with `/api/`).

Deliverable: a clear statement of which Vercel project is the gateway, confirmation its env vars match Supabase project wqdacfrzurhpsiuvzxwo, and a passing /api/v1/health from the live deployment.
```

---

## What is already verified (don't redo)

- **Supabase project `wqdacfrzurhpsiuvzxwo` is live and connected to the stored service key.**
  - The service_role key is a JWT whose `ref` claim = `wqdacfrzurhpsiuvzxwo` and `role` = `service_role`.
  - Live REST call `GET https://wqdacfrzurhpsiuvzxwo.supabase.co/rest/v1/entries` → `200` with real rows.
  - Running this repo's `gateway/` locally (with the correct `SUPABASE_URL`) returns real SAVY entries through `/api/v1/entries`.
- **The gateway code (`gateway/`) builds and runs:** `npx tsc --noEmit` passes; handlers serve health, auth (401/405), CORS (204), and live data correctly.

## The two problems found

1. **Secret swap:** `SUPABASE_URL` was holding an `sb_secret_…` **key** instead of the **URL** `https://wqdacfrzurhpsiuvzxwo.supabase.co`. Supabase client throws `Invalid supabaseUrl`. Check for this same swap wherever the gateway is deployed.
2. **Wrong/unclear deployment target:** `dblaira-github-io.vercel.app` is a **Next.js web app** (references "savy" but `/api/v1/health` = 404). The SAVY iOS **gateway is not deployed there**. Either it lives in a different Vercel project, or it was never deployed.

## Correct configuration reference

| Name | Correct value | Notes |
|---|---|---|
| `SUPABASE_URL` | `https://wqdacfrzurhpsiuvzxwo.supabase.co` | A URL. NOT an `sb_secret_…` key. |
| `SUPABASE_SERVICE_ROLE_KEY` | service_role JWT (`eyJ…`) for ref `wqdacfrzurhpsiuvzxwo` | Keep secret. |
| `SAVY_API_KEY` | any long random string | Same value goes in iOS `SAVY-Secrets.xcconfig` as `AWS_API_KEY`. |

iOS side (`SAVY-Secrets.xcconfig`, gitignored):
```
AWS_API_BASE_URL = https://<gateway-project>.vercel.app/api/   # must end with /api/
AWS_API_KEY = <same value as SAVY_API_KEY on Vercel>
```

## Quick verification commands

```bash
# Is a given Vercel deployment the gateway? (expects JSON with service: savy-gateway)
curl -s https://<host>/api/v1/health | python3 -m json.tool

# Does it serve live data? (use the real key)
curl -s -H "x-api-key: <SAVY_API_KEY>" "https://<host>/api/v1/entries?limit=3"

# Run the gateway locally against live Supabase (vercel dev needs `vercel login`):
cd gateway && npm install
SAVY_API_KEY=local SUPABASE_URL=https://wqdacfrzurhpsiuvzxwo.supabase.co \
  SUPABASE_SERVICE_ROLE_KEY=<jwt> npx vercel dev
```

## Useful references in this repo

- `gateway/README.md` — routes, phases, deploy steps.
- `gateway/.env.example` — required env vars.
- `SAVY-Ops.local.example` — deploy checklist + accounts.
- `AGENTS.md` → "Cursor Cloud specific instructions" — gateway dev notes and the `vercel dev` credential caveat.
