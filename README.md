# SAVY iOS

SAVY iOS is the native iPhone app for SAVY.

The Vercel site and Supabase backend can stay alive, but this repository is for the App Store-bound Swift app: native SwiftUI/UIKit, Apple frameworks, real iPhone capabilities, and no web runtime in the shipped app.

## Open

```bash
open SAVY.xcodeproj
```

## Build For iPhone Hardware

```bash
xcodebuild -project SAVY.xcodeproj -scheme SAVY -sdk iphoneos -destination 'generic/platform=iOS' build
```

## Runtime Boundary

- Allowed in app: Swift, SwiftUI, UIKit, Foundation, UserNotifications, PhotosUI, CoreLocation, AppIntents, WidgetKit, ActivityKit, Keychain, URLSession, and other Apple frameworks.
- Allowed outside app: Vercel, Supabase, Figma.
- Not allowed in app: WebView shell, PWA runtime, React Native, Expo, Capacitor, TypeScript frontend.
