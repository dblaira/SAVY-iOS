# Schedule sync between iPhone and Mac

The shared entry form keeps its existing appearance. SAVY account sync carries Schedule start/end instants, all-day, time zone, alert (including bounded Hourly), travel time, invitees, and organizer email. Location, URL, notes, and Repeat travel in the existing entry fields.

Reminder/Action/Calendar/Post records use `/api/v1/reminders`; authored Connections use `/api/v1/documents`. Each device recomputes its local notification requests after receiving a saved change. The existing foreground refresh runs every 60 seconds and on app activation. Internet access and the same SAVY account are required.

Native EventKit calendar/event identifiers stay on the device where Calendar was selected. Receiving shared settings never creates another Calendar event. Existing linked events on the receiving device are updated; Calendar edits still do not import into SAVY. Selecting the same iCloud calendar is separate from SAVY account sync.

## Upgrade and removal

- A Schedule has version 1; an explicit version-1 empty Schedule removes it everywhere.
- Older clients that omit the fields cannot erase a shared Schedule or its date mirrors.
- Previously local schedules migrate into the latest shared record, retaining newer writing.
- Schedule removal, completion, and deletion cancel local notifications. Hourly remains finite and ends at the chosen time.
- Saving or syncing invitee addresses never sends an invitation.

Apply `gateway/schema/reminder-schedule.sql` before deploying the gateway. The idempotent `node gateway/scripts/apply-reminder-schedule-schema.mjs` command applies and verifies it; `--check` is read-only.

## Verification

Tests exercise the production Swift wire types and stores with two isolated device caches, and the production SQL through temporary PostgreSQL tables. They do not create live personal entries, calendar events, invitations, or synthetic device alerts.

Run:

```sh
bash scripts/test-reminder-schedule.sh
bash scripts/test-reminder-schedule-sync.sh
bash scripts/test-connection-schedule-sync.sh
cd gateway && npm run test:gateway
```

Verified for this delivery: 64 planner/cache checks, 28 native notification delivery checks, invitation formatting checks, 32 two-store Reminder sync checks, 58 Connection/document-engine checks, 39 gateway tests, and five PostgreSQL storage scenarios. Release Mac build and iPhone build-for-testing passed.

With Adam's explicit permission, the installed Mac app created one disposable entry with a past Schedule and Hourly alert. Production sync delivered the exact Schedule and location to his physical iPhone. Adam then removed its Schedule on the phone; both devices stored version 1 with no Schedule or date mirrors and no pending upload. The Mac Calendar no longer showed the test event. Deleting the temporary entry through the Mac app removed it from both device caches, restoring their original 31-entry count; the Mac Reminders view returned to six active cards. The test created no native Calendar event, invitation, or future notification. Its local captures, outbox records, and registry entries were also cleared on both devices, along with its Mac delegation spool file. Unrelated capture/outbox records and preferences were preserved, and both installed apps were reopened. Private live-test evidence remains in ignored artifacts.

The live Calendar check also exposed its hidden swipe tray expanding to the full timeline height. Constraining the outer row to the existing 34/48-point compact/pinned height keeps cards at their actual scheduled hour.

Separate pre-existing issue found during cleanup: the gateway returns reminder creation/update/completion timestamps as PostgreSQL text, which the client's ISO parser does not accept. Creation/update timestamps therefore fall back to the refresh time and completion timestamps can become empty. Normalize those gateway timestamps in a separate repair; the Schedule JSON uses valid ISO timestamps and the verified Schedule transfer/removal is unaffected.
