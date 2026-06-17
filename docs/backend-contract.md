# Backend Contract

Supabase and Vercel are allowed infrastructure. They are not the iOS runtime.

## Supabase

Allowed responsibilities:

- Auth/session backend.
- Postgres data store.
- Storage for media attachments.
- Row-level security.
- Edge functions only when native code should not own the work.

Native iOS responsibilities:

- Swift `URLSession` client boundary.
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

Do not commit private keys, service-role keys, Apple credentials, App Store Connect credentials, or personal auth tokens. Client-safe Supabase anon keys can be added only once Adam confirms the target project.
