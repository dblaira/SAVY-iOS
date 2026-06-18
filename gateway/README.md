# SAVY API Gateway

Vercel serverless API the iOS app calls via `AWSGraphClient`.

## Deploy

```bash
cd gateway
npm install
cp .env.example .env.local   # fill values
npx vercel link              # link to Vercel project
npx vercel env pull .env.local
npx vercel --prod
```

## iOS config

After deploy, set in `SAVY-Secrets.xcconfig`:

```
AWS_API_BASE_URL = https://YOUR-PROJECT.vercel.app/api/
AWS_API_KEY = <same value as SAVY_API_KEY on Vercel>
```

Note the trailing `/api/` — paths append as `v1/entries`, `v1/correlations/latest`.

## Phases

| Phase | Trigger | Data source |
|-------|---------|-------------|
| Bridge | `DATABASE_URL` unset | Supabase service role |
| Aurora | `DATABASE_URL` set on Vercel | `savy.*` Postgres tables |

Gateway picks the phase automatically via `lib/content-store.ts`. Health reports `phase: "aurora"` or `"supabase-bridge"`.

### Aurora cutover

1. Provision Aurora Serverless v2 (PostgreSQL 15+).
2. Apply schema: `psql $DATABASE_URL -f docs/schema/aurora.sql`
3. Migrate data: `node scripts/migrate-supabase-to-aurora.mjs`
4. Add `DATABASE_URL` to Vercel production env.
5. Redeploy gateway — health flips to `aurora`.

Optional env for migration script:

- `SAVY_OWNER_USER_ID` (default `adam`)
- `SAVY_OWNER_EMAIL` (default `adam@savy.app`)

## Routes

| Method | Path | iOS client |
|--------|------|------------|
| GET | `/api/v1/health` | health check |
| GET | `/api/v1/entries?limit=24` | `fetchEntries` |
| GET | `/api/v1/captures?limit=20` | `fetchCaptures` |
| GET | `/api/v1/correlations/latest` | `fetchCorrelations` |

All routes except health require header `x-api-key: <SAVY_API_KEY>`.
