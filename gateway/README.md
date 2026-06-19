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
| Bridge | `AURORA_HOST` unset | Supabase service role |
| Aurora | `AURORA_HOST` set | `savy.*` Postgres (beliefs + stats) |
| Aurora + Neo4j | `AURORA_HOST` + `NEO4J_URI` | Beliefs from Aurora, ontology edges from Neo4j |

Gateway picks the phase automatically via `lib/content-store.ts`. Health reports `phase: "supabase-bridge"`, `"aurora"`, or `"aurora+neo4j"`.

### Neo4j cutover

1. Create AuraDB instance in Neo4j console.
2. Add `NEO4J_URI`, `NEO4J_USER`, `NEO4J_DATABASE`, `NEO4J_PASSWORD` to `gateway/.env.local`.
3. Apply schema: `node scripts/apply-neo4j-schema.mjs`
4. Hydrate graph: `node scripts/migrate-aurora-to-neo4j.mjs`
5. Add Neo4j env vars to Vercel production and redeploy.

## Routes

| Method | Path | iOS client |
|--------|------|------------|
| GET | `/api/v1/health` | health check |
| GET | `/api/v1/entries?limit=24` | `fetchEntries` |
| GET | `/api/v1/captures?limit=20` | `fetchCaptures` |
| GET | `/api/v1/correlations/latest` | `fetchCorrelations` |

All routes except health require header `x-api-key: <SAVY_API_KEY>`.
