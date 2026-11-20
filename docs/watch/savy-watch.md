# SAVY Watch — November 20, 2026

Adam: “Okay, we're going to build an Apple Watch app for the SAVY app. I put a lot of the details in this document and I was talking to Gemini when I did it.”

The document is “SAVY On Your Wrist Without Breaking Your Stride”. Its plan: one press of the orange Action Button, or a Siri phrase, captures a voice note into Action, Reminder, Calendar Event or Staged Social Post. The Watch saves it on the wrist first, shows the exact words as proof, and the iPhone and Mac do the processing after the run. Its rule, from Adam’s note The Shift: “The app isn't a capture tool for the moment of action. It's a PROCESSING tool for after the action is taken.”

Adam, Nov 20, while this was being built: “I'm gonna put the same type of iPhone Apple Watch app on for three or four of my other apps and it's gonna have almost identical functionality”. See [Reusing this for the other apps](#reusing-this-for-the-other-apps).

## What is built

| Plan item | Built |
|---|---|
| Watch target inside `SAVY.xcodeproj` | `SAVYWatch` (watchOS 11+, bundle `com.adamblair.savy.watchkitapp`), display name SAVY |
| Screen 1: complication and Smart Stack | `SAVYWatchWidgets`: circular, corner, rectangular and inline; a tap opens SAVY |
| Screen 2: voice capture | Four doors: Action, Reminder, Calendar, Social. A tap opens the Watch’s own dictation |
| Screen 3: proof | Success tap on the wrist, the exact words, the entry type, any day or hour heard, the iCloud status. Shows for four seconds, then returns. Any tap keeps it open. One tap re-records |
| Four Siri phrases | “Log an action in SAVY”, “Add a reminder in SAVY”, “Create a calendar event in SAVY”, “Stage a social post in SAVY”. Siri asks for the words and reads back what was saved |
| Action Button | Any of those four, or “Capture in SAVY”, which opens the four doors |
| Local queue first | Every capture is written to the Watch before anything is sent. Waiting captures send when SAVY opens and when watchOS wakes it to retry |
| Sync to iPhone and Mac | iCloud, in SAVY’s existing container `iCloud.com.adamblair.harness` |

### How each capture lands on the iPhone and Mac

When SAVY opens or refreshes, each capture becomes a normal entry through `ReminderStore.save`, the same path the entry form’s Save uses. It then syncs to the other devices like any other entry.

| Door | Entry | Where the words go | Day or hour |
|---|---|---|---|
| Action | Action | What do I want? | Not read |
| Reminder | Reminder | What do I want? | “tomorrow at 3 PM” becomes the Schedule, alert at start. A day with no hour starts at 9:00, SAVY’s existing default |
| Calendar | Event | What do I want? | Same, one hour long; a day with no hour is all-day with no alert. No Apple Calendar is chosen, so nothing is written to Calendar until Adam picks one |
| Social | Social, Generalization theme | The first question, “What shining example caught my attention?” | Not read |

The Social door follows Adam’s own words in the YouTube system doc: “Common scenario is that I am out for a run and have an idea hit me.” He answers only the first question, and the other three wait for him on the iPhone or Mac. Nothing is added that he did not say: no tags, no notes, no generic name.

## Where the build differs from the plan, and why

1. **The words come from Watch dictation, and no raw audio is saved.** The plan records audio and makes a live transcript on the Watch. Apple’s speech-to-text frameworks, `SFSpeechRecognizer` and `SpeechAnalyzer`, are not available on watchOS. Apple’s documentation lists iOS, iPadOS, Mac Catalyst, macOS and visionOS, plus tvOS for SpeechAnalyzer. A Watch app can record audio, but it cannot turn that recording into words. Watch dictation gives the exact words right away, which is the plan’s proof. Keeping raw audio means the iPhone writes the words after the run, so the proof moves off the wrist. That choice is Adam’s; see Open questions.
2. **No AWS or Supabase upload.** Adam cancelled AWS on Oct 12 (“I cancelled AWS last night”). SAVY now syncs through iCloud, so the Watch uses iCloud too.
3. **No separate WatchConnectivity path.** When the iPhone is in a pocket, the Watch’s iCloud traffic already goes through it. One path has fewer ways to fail. It can be added if a capture is ever slow to appear.
4. **The Watch writes to its own iCloud zone, `SAVYWatchInboxV1`.** SAVY’s entries live in `SAVYEntriesV1`, and an unreadable record there stops entry sync until it is repaired. The Watch never writes there, so a Watch bug cannot stall the iPhone and Mac. The iPhone and Mac import only after iCloud sync has confirmed the signed-in owner. Each import is saved locally before the capture is removed from iCloud, and a ledger keeps a deleted entry from coming back.
5. **StoreKit 2 is not built.** The plan ties it to selling SAVY. Nothing needs unlocking for Adam’s own use yet.
6. **The Watch app is not embedded in the iPhone app yet.** Install it by running the `SAVYWatch` scheme. The iPhone and Mac build settings are unchanged apart from two new source files. Embedding is needed later for TestFlight or the App Store.

## Status

- Written in a cloud session with no Xcode and no access to Adam’s Macs (no Tailscale secrets and no Remote Control folder were available).
- Compile check: `.github/workflows/watch-build.yml` builds `SAVYWatch` for the watchOS Simulator and `SAVY` for the iOS Simulator, both unsigned, on a GitHub macOS runner. It also runs `SAVYWatchCaptureTests` (values only: no store, iCloud or Watch). The result for each pushed commit is recorded under [CI results](#ci-results).
- Not yet done: signing, installing on the Watch, any on-device check, and the first real capture going from wrist to iPhone. Adam’s own use is the acceptance check.

### CI results

- `1164d75`: running when this was written.

## Install and set up (needs Adam’s Mac, Watch and iPhone)

1. On the Mac, open `SAVY.xcodeproj`, choose the `SAVYWatch` scheme and the Ultra 3 as the destination, and Run. Automatic signing registers `com.adamblair.savy.watchkitapp` and `com.adamblair.savy.watchkitapp.widgets`. If signing reports iCloud, open Signing & Capabilities for SAVYWatch and tick the `iCloud.com.adamblair.harness` container.
2. Install the iPhone and Mac apps from this branch too. They are the side that turns captures into entries.
3. Action Button: in Settings on the Watch, choose Action Button, then Action, then Shortcut, and pick a SAVY shortcut. Apple’s Ultra guide gives this path.
4. Complication: edit the watch face and add SAVY Capture.
5. First test: tap Action, say a sentence, and check the words on the proof screen. Then open SAVY on the iPhone and find the entry in Actions.

## Open questions for Adam

1. Raw audio or words on the wrist? Today the words show on the wrist and no audio is kept. The other option keeps the recording and the iPhone writes the words after the run.
2. Should the Action Button open the four doors, or go straight to one entry type with Siri asking for the words?
3. Does the Social door belong on the first Generalization question, or on another theme?
4. Do the door names and symbols read right on the wrist: Action, Reminder, Calendar and Social, with the same symbols SAVY’s lists use?

## Reusing this for the other apps

Adam plans the same iPhone and Watch capture for three or four more apps. What carries over from SAVY:

- `SAVY/WatchCapture.swift`: the capture model, the day-and-hour reader and the iCloud inbox record. These depend on nothing else in SAVY.
- `SAVYWatch/`: the queue, the doors, the proof screen and the Siri phrases. App-specific parts are the four kinds, their labels and symbols, the colors and the phrases.
- `SAVYWatchWidgets/`: the complication. Only the name and symbols change.
- `SAVY/WatchCaptureImporter.swift`: the import loop carries over. `Reminder(watchCapture:)`, which decides where the words go, is per app.
- `script/watch/add_watch_targets.py` and `script/watch/check_pbxproj.py`: wiring the two targets into a project without Xcode, and checking the result.
- `.github/workflows/watch-build.yml`: the compile and test check.

Lessons from this build:

- Check what watchOS supports before writing the design. Gemini’s plan assumed on-Watch transcription, which watchOS does not have.
- Give each app its own inbox zone in the shared container, such as `SAVYWatchInboxV1` or `UnderstoodWatchInboxV1`, so captures never cross between apps.
- Keep the Watch out of the app’s main sync zone.

Ways to improve it before the second app:

- **One Action Button.** An Ultra has one Action Button, and only one shortcut can own it. Four separate Watch apps would compete for it. A single suite capture app could own the button, with doors that send each capture to the right app’s inbox.
- **One shared Swift package** for the model, reader, inbox, queue and proof screen, with each app passing in its kinds, colors and mapping. A fix then reaches every app at once.
- **A parameterized wiring script** that takes the app name, bundle IDs and group anchors as arguments, so the second app needs no script edits.
