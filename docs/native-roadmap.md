# SAVY Native iOS Roadmap

SAVY iOS is the App Store product. The web property can remain a website/admin surface, but it is not the phone runtime.

## Phase 1: Native Core

- SwiftUI home surface that feels like SAVY, not a translated website.
- Native capture flow for leverage signals.
- Local persistence for captures.
- Supabase sync boundary through Swift `URLSession`.
- Local notifications for resurfacing.
- Photos picker for image attachment.
- Location context for entries that need place.
- App Intent for Siri/Shortcuts capture.

## Phase 2: iPhone System Depth

- Widgets through WidgetKit.
- Live Activities through ActivityKit where a time-bound capture or practice needs a lock-screen surface.
- Share extension for saving links or text into SAVY.
- Spotlight indexing for captures and principles.
- Keychain-backed auth/session storage.
- Background refresh for sync.

## Phase 3: Apple Ecosystem

- Apple Watch companion surface.
- CloudKit only if it earns its keep beside Supabase.
- On-device intelligence with Natural Language/Core ML/Foundation Models where useful.
- App Store archive, privacy nutrition labels, screenshots, and TestFlight.

## Hard Boundary

No WebView shell, PWA, React Native, Capacitor, Expo, or TypeScript runtime in the iPhone app.
