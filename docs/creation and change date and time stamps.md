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

Adam needed his phone, so further device work stopped and iPhone Mirroring was closed. The installed timestamp build remains usable. A subsequent source correction marks inline Reminder title dates for repository sync and records Connection title sync dates; that signed build is ready, but these two follow-up sync changes have not been reinstalled on the phone.
