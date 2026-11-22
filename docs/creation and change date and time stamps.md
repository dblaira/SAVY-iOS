# Creation And Change Date And Time Stamps

## Entry dates are available to agents (Executive Conclusion)

1. 🕒 Original creation dates survive subsequent saves. Entry changes update the change date.

2. 🤖 Whole-form sharing includes `Created` and `Changed` as ISO 8601 UTC instants with seconds. Unsaved form snapshots are identified separately.

## Date meanings stay separate (Consequence)

1. 📅 Creation and change dates are separate from due dates, event start/end dates, completion dates, publication dates, and export times.

2. 📖 Reading, reopening, and sharing do not stamp a new edit. Existing writing and known historical dates are preserved.

## Implementation and delivery (Recommendation)

Implemented on the source branch used by the installed SAVY builds, including the existing Send to AI and Mac close-button work. The stale Documents checkout's three pre-existing modified files remain untouched.

The shared Reminder model covers Reminder, Action, Calendar and Social. Connection metadata, older Social posts, Stories, MetadataEntry and CaptureEntry are covered too. Inline entry-title changes update the owning saved entry. Connection pin changes now update their metadata timestamp.

Send to AI carries dates for shared entries, older Social posts and Stories. Technical-capture metadata and prompts carry the originating entry dates separately from the outbox's creation time. Calendar invitations include `CREATED` and `LAST-MODIFIED`, separately from `DTSTAMP` and the event schedule. Nothing is sent or published by this change.

## Verification (Supporting Evidence on Request)

The signed iPhone build is installed. On the physical iPhone, an existing Reminder was opened, shared with native Copy, and closed with Cancel. The copied text included `Created: 2026-11-08T18:15:56Z` and `Changed: 2026-11-12T00:06:54Z`, matching its saved record. The original text and dates were unchanged.

Fresh before/after phone archives retain all 58 reminder IDs, the authored Connection, the older Social post, and media. One reminder's `needsSync` flag and two CloudKit transport files changed during launch/sync; authored content and entry dates did not change. Backups are at `/tmp/entry-timestamps-before/savy` and `/tmp/entry-timestamps-after/savy`.

The final unit suite passed 180/180 tests, including persistence through every authored store, title-change sync eligibility, and calendar invitation dates. The final signed iPhone build passed. The native sharing UI regression passed with two real Copy/Paste operations, exact UTC timestamp checks, updated writing on the second share, restored draft contents, and Cancel without a saved entry. Clipboard tests run serially across simulators to prevent shared-clipboard interference.

Final delivery completed after Adam returned. The signed build containing the Reminder title-sync and Connection sync-date corrections was installed on the physical iPhone. All 24 Application Support files matched the fresh preinstallation backup byte-for-byte. The final app launched normally; native Share → Copy again returned `Created: 2026-11-08T18:15:56Z` and `Changed: 2026-11-12T00:06:54Z` for the existing entry. Cancel returned to Home without saving. The final readback preserved every authored file and image; only two CloudKit transport files changed during normal launch/sync. iPhone Mirroring was closed afterward.

Final readbacks are in `/tmp/entry-timestamps-resumed-before/savy`, `/tmp/entry-timestamps-resumed-after/savy`, and `/tmp/entry-timestamps-final-phone/savy`. The actual copied output is saved in `/tmp/entry-timestamps-resumed-after/creation and change date and time stamps.rtf`. Tested implementation commit: `43a6a6e95a7b5116e707b4febb11cdf0e5997913`; the installed baseline branch and timestamp branch both contain it.
