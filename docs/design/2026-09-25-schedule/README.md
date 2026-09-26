# Schedule details and finite Hourly alerts

Adam requested the supplied event editor's scheduling controls in a separate page under the shared entry form, plus Hourly in Alert for a few hours at a time.

## Behavior

- Schedule → Date opens the native Schedule sheet. Starts, Ends, All-day, Time Zone, Repeat, Location or Video Call, Invitees, Calendar, Alert, Travel Time, URL, and Notes are available there. Existing cream groups, white form background, red controls, and Bodoni heading are reused.
- Cancel discards the Schedule draft. Done returns it to the entry; Save persists it. Remove Schedule clears its dates and alerts when the entry is saved.
- Hourly uses finite one-shot alerts at the start and each elapsed hour through the end, inclusive, up to 24 hours. It stops at the selected end, independently of Repeat. Edits cancel the previous set. A pending-notification capacity or permission failure is surfaced rather than silently dropping alerts.
- Calendar defaults to SAVY. Choosing an Apple calendar requests access and saves/updates one linked EventKit event on entry Save. Normal alerts belong to that calendar; Hourly belongs to SAVY. Switching back to SAVY or removing Schedule silences the linked event's alarms while retaining the event.
- Invitees are email addresses. Save & Send Invitations saves the entry, then opens Apple's Mail composer with an iCalendar invitation for the person to review and send. Ordinary Save sends no invitations. Calendar RSVP synchronization is not implemented.
- Travel Time advances a normal alert by the selected travel duration. Hourly follows the chosen start/end window.
- All-day end dates use an exclusive storage boundary; the editor and labels show the inclusive final day. SAVY Calendar displays every occupied day and retains floating all-day dates across time zones.
- Existing entries decode without the optional Schedule payload. Connection entries retain separate storage; explicit schedules can now request alerts. Detailed Schedule data is local and preserved when the current gateway omits it; the gateway does not yet sync those new details across devices.

## Verification

`bash scripts/test-reminder-schedule.sh` passed against the production sources: 53 model/cache/date-span checks, 28 notification trigger/delivery/lifecycle checks, and invitation generation checks for UTC dates, exclusive all-day boundaries across daylight saving, Unicode folding, escaping, email validation, recipient deduplication, recurrence, REQUEST fields, and stable event identifiers.

The shared-entry UI acceptance tests cover opening Schedule, finite Hourly presentation, cancellation, and save/reopen in isolated storage. They are built with the app; no simulator or automated physical-phone test has been run for this feature. No test invitation, live calendar fixture, or synthetic phone notification has been created.

The final `xcodebuild ... build-for-testing` succeeded. The app was installed on Adam's connected iPhone 17 Pro Max and launched normally as `com.adamblair.savy`. Adam opened the Date row, and the live Schedule page was observed through QuickTime's wired screen source. `installed-schedule-top.png` and `installed-schedule-options.png` show Starts, Ends, All-day, Time Zone, Repeat, Location, Invitees, Calendar, Alert, Travel Time, and the beginning of URL.

Adam initially looked in Repeat, then confirmed the Hourly option in Alert: "got it. I see it now. Thank you". Hourly timing is covered by the source-level tests above. Stop-time presentation, bottom Notes, and save/reopen have not yet been observed on the physical phone. No live invitation was sent or calendar event created during verification. Phone screenshots and saved-content visual proofs remain local verification artifacts.

## Mac delivery

Adam requested committing/pushing the work and the same functionality in the macOS app. iPhone source and approved card changes were committed and pushed as `f067ada` on `main`. The existing Mac Catalyst branch is integrated so both apps use the same Schedule view, notification planner, Calendar bridge, and invitation composer. The Mac Schedule sheet uses the existing page-sized presentation; the sandbox includes Calendar access.

Detailed Schedule settings remain local to each device. Connection document sync excludes Schedule and schedule-owned date/time mirrors, preserves the receiving device's existing Schedule when shared content changes, and cancels alerts after a successfully saved remote deletion. Native Calendar/event IDs are not transferred between devices. `bash scripts/test-connection-schedule-sync.sh` passed 21 isolated checks, including fresh-device behavior, local retention, passthrough records, remote deletion, and failed persistence. The Mac branch's nine gateway document-sync tests also passed.

`script/build_and_run.sh --verify` is the reproducible Mac build/install/launch command and backs up the prior app inside ignored `artifacts/mac-build/`. The Codex Run action uses the same script. The Mac release build and combined iPhone/test-target build passed. `/Applications/SAVY.app` was installed, signature-verified, and launched with the existing sign-in. The installed executable matches the release build SHA-256 `f9d6d7938da69e505f4f592e6d900261491ef034ddcbf0c572b5c2a9729fe234`, and its signature contains the Calendar entitlement.

Native Mac verification opened a new unsaved Reminder → Date → Schedule. All requested controls were visible, including URL and Notes. Alert was changed to Hourly, displaying "Every hour until 11:00 PM". Done returned the period to the entry, and reopening Schedule retained Hourly and its end time. The temporary entry was then cancelled, returning to Home. No test record was saved and no notification, calendar event, or invitation was created. Local visual evidence: `installed-mac-hourly.png`. Mac popup menus use a separate AppKit window not exposed in the sheet capture; keyboard selection through the popup was confirmed by its returned value and the visible stop-time line.
