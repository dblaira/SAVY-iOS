# Backend Contract

AWS Aurora, Neo4j, and Vercel are allowed infrastructure. They are not the iOS runtime.

## AWS Graph (Aurora + Neo4j)

Allowed responsibilities:

- Auth/session backend (Cognito via API gateway).
- Aurora Postgres as system of record.
- Neo4j for graph intelligence and ontology traversal.
- S3 for media attachments.
- Vercel API routes as the iOS-facing gateway.

Native iOS responsibilities:

- Swift `URLSession` client boundary (`AWSGraphClient`).
- Keychain session storage.
- Local-first UI state.
- Permission prompts and Apple framework integration.

## Vercel

Allowed responsibilities:

- Public SAVY website.
- Admin/editor web surfaces.
- API orchestration when useful.
- Internal tooling.

Not allowed:

- Serving the iPhone app UI.
- Acting as a hidden web runtime for the App Store app.
- PWA/WebView replacement for native iOS.

## Secrets

Do not commit private keys, service-role keys, Apple credentials, App Store Connect credentials, or personal auth tokens. Client-safe API keys can be added only once Adam confirms the target project.
