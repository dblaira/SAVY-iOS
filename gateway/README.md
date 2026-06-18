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

| Phase | Data source | Status |
|-------|-------------|--------|
| Bridge | Supabase service role | **Now** — gets live beliefs + ontology on phone fast |
| Aurora | `DATABASE_URL` | Replace bridge queries in `lib/` |
| Neo4j | Graph enrichment | Optional layer on correlations |

## Routes

| Method | Path | iOS client |
|--------|------|------------|
| GET | `/api/v1/health` | health check |
| GET | `/api/v1/entries?limit=24` | `fetchEntries` |
| GET | `/api/v1/captures?limit=20` | `fetchCaptures` |
| GET | `/api/v1/correlations/latest` | `fetchCorrelations` |

All routes except health require header `x-api-key: <SAVY_API_KEY>`.
