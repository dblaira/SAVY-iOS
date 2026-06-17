# SAVY Editorial Shell And Metadata Capture Design

## Goal

SAVY should become the native personal workspace that carries the best patterns from Adam's existing iOS apps:

- Understood supplies the app shell: editorial hero, carousel, feed, bottom navigation, centered FAB, and haptics.
- Re_Call supplies the behavior capture system: reminders, actions, calendar entries, layered metadata, and quick composer flow.
- SAVY keeps its own identity: native-only SwiftUI, navy editorial surfaces, cream paper content, crimson accents, and leverage-oriented navigation.

This first implementation should establish the foundation without turning SAVY into a generic productivity app.

## Approved Direction

### App Shell

Use the Understood-style layout as the north star:

- Large navy hero/header section at the top of the home surface.
- Cream content zone below the hero.
- Horizontal carousel of major leverage cards near the fold.
- Scrollable feed below the carousel.
- Bottom navigation with a centered FAB.

The hero/header and FAB use deep navy instead of Understood's black. Crimson remains the accent color for divider lines, active states, and metadata emphasis.

### Navigation

Bottom navigation remains SAVY leverage-oriented. It should continue to foreground the existing conceptual pages rather than becoming Reminders / Actions / Calendar.

Primary bottom nav concept:

- Now
- Essays
- Center FAB
- Beliefs
- News

Ontology remains a SAVY page/section, but it does not need to occupy a bottom-nav slot in the first pass if the shell needs to stay balanced. It can be reached from the home carousel or a later top-left menu.

### Center FAB

The center FAB is a universal quick-entry trigger, not a page.

Interaction:

- Tap or press the navy FAB.
- Trigger haptic feedback.
- Open a bottom radial menu with three options:
  - Reminder
  - Action
  - Calendar
- Selecting an option opens the corresponding layered SwiftUI composer.

The radial animation should feel intentional and beautiful, not merely utilitarian. It should expand from the FAB with spring motion, preserve thumb reachability, and close cleanly when tapping outside or selecting an entry type.

### Metadata Forms

The first version uses layered forms:

- Fast default fields are visible immediately.
- Rich metadata fields live in an expandable "More Metadata" area.
- Forms are native SwiftUI bottom sheets, not WebViews.

Initial entry types:

- Reminder
- Action
- Calendar Event

Fast fields:

- Title
- Notes
- Date/time when relevant
- Tags or context labels

More Metadata fields:

- Cadence or recurrence intent
- Behavioral context
- Energy/priority signal
- Optional category/context association
- Notification scheduling toggle when relevant

Voice memo capture from Re_Call is valuable, but it should not block the first implementation unless the existing native capture machinery can be reused safely. It can be added as a second layer after the form/data foundation is stable.

### Page Ownership

SAVY's existing leverage pages should keep their own entry surfaces later:

- News Channel gets story/news entries.
- Field Essays gets draft/essay entries.
- Belief Library gets belief/connection entries.
- Ontology gets relationship/pattern entries.

The FAB radial menu is specifically for behavior and time metadata: reminders, actions, and calendar events.

### Future App Menu

A top-left hamburger menu is reserved for a later pass. It can eventually reveal settings, account controls, filters, sync status, diagnostics, and additional page management.

Do not include the full menu in this first implementation unless it becomes necessary for navigation.

## Data Model

Add a small native metadata entry model independent of the existing leverage content model.

Core shape:

- `id`
- `kind`: reminder, action, calendar
- `title`
- `notes`
- `createdAt`
- `updatedAt`
- `scheduledAt`
- `tags`
- `context`
- `priority`
- `cadence`
- `syncState`: localOnly, pendingSync, synced, failed

The model should be Codable and Equatable so it can be tested and locally persisted without extra infrastructure.

## Persistence

Use hybrid persistence:

1. Save locally immediately so capture never feels fragile.
2. Mark entries as pending Supabase sync.
3. Prepare a sync boundary that can later send entries to Supabase once the schema/API contract is finalized.

First implementation uses local JSON-backed storage through an explicit store boundary. Supabase sync can be added behind that boundary without rewriting the UI.

No secrets should be committed. Supabase diagnostics must not expose tokens or raw sensitive payloads.

## Components

Recommended native components:

- `SavyNavigationState`
  - Tracks active section and composer/radial menu presentation.
- `SavyBottomNavigationBar`
  - Understood-inspired bottom nav with SAVY labels and navy FAB.
- `SavyRadialFabMenu`
  - Bottom-centered radial menu with haptics and spring animation.
- `MetadataEntry`
  - Codable model for reminder/action/calendar captures.
- `MetadataEntryStore`
  - Local-first store with pending sync state.
- `MetadataComposerSheet`
  - Shared layered form shell.
- `ReminderComposerFields`
  - Reminder-specific fields.
- `ActionComposerFields`
  - Action-specific fields.
- `CalendarComposerFields`
  - Calendar-specific fields.
- `EditorialHomeView`
  - Understood-style navy hero, carousel, and scroll feed adapted to SAVY.

Keep the implementation native-only. Do not import Re_Call's WebView implementation.

## Error Handling

- Invalid form: show concise inline validation.
- Local save failure: show an error and keep the sheet open.
- Notification permission denial: save the entry locally and show that scheduling was not enabled.
- Supabase sync unavailable: keep entry as pending/local and do not block capture.
- Supabase sync failure: preserve local entry and record a diagnostic state.

## Testing

Add focused tests before production code:

- Metadata entry normalizes required fields.
- Store saves and reloads entries locally.
- Creating an entry starts as pending/local sync.
- Bottom navigation declares SAVY leverage sections, not generic productivity sections.
- FAB menu exposes Reminder, Action, Calendar.
- Native-only boundary still rejects WebView/PWA/React Native/Capacitor/Expo/TypeScript runtime.

UI animation details may be verified with simulator/device builds rather than brittle unit tests.

## Out Of Scope For First Pass

- Full Supabase schema migration for metadata entries.
- Voice memo capture unless it is a low-risk reuse of existing native capture code.
- Top-left full-screen hamburger menu.
- Replacing every existing SAVY page with final content-management surfaces.
- Exact visual copy of Re_Call or Understood.

## Acceptance Criteria

- SAVY launches into a navy editorial home surface with carousel/feed structure.
- Bottom navigation remains SAVY leverage-oriented.
- Center navy FAB opens a haptic bottom radial menu.
- Radial options are Reminder, Action, and Calendar.
- Each option opens a layered native composer.
- Saving an entry persists locally immediately.
- Entries carry sync state for future Supabase work.
- Tests pass.
- No web runtime is introduced.
