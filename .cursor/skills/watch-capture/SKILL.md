---
title: watch-capture
type: skill
tags: [skills, ios, watchos, build]
created: 2026-11-20
updated: 2026-11-21
summary: Adds the SAVY-style Apple Watch capture app (one big record button) to another of Adam's iPhone/Mac apps. Load when Adam says any of: "add the watch app to", "put the Apple Watch capture on", "same type of iPhone Apple Watch app", "save the watch workflow", "watch capture kit"
deployed_to: ["SAVY-iOS/.cursor/skills/watch-capture/SKILL.md", "SAVY-iOS/.claude/skills/watch-capture/SKILL.md (pointer)"]
related: ["[[Skills Hub]]", "SAVY-iOS docs/watch/savy-watch.md"]
---
## Say this to trigger

“Add the watch app to Understood.” “Put the Apple Watch capture on Harness.” “Same Watch app as SAVY.”

# Watch capture kit

Adam, Nov 20, 2026: “I'm gonna put the same type of iPhone Apple Watch app on for three or four of my other apps and it's gonna have almost identical functionality”. Then: “save the watch workflow so I can reuse it”.

Adam, Nov 20, on the Watch design: “one large button that I can press. The idea here is to reduce friction, so if I'm reducing friction, I just need one button to press. I pressed the button, I record it, and then after it's recorded, then there can be some selections.” He also asked to “examine what it recorded because sometimes my diction can be often it might change CODEX to KODAK”.

What one run produces in an app:
- **One big record button** on the Watch, like Voice Memos: one press records, one press stops. The Action Button's “Capture” shortcut opens the app already recording.
- **A review screen.** Play the recording back. One tap on Save files it as the default type (`defaultKind`), or one tap on another type files it as that. Leaving the screen saves it too; only Delete throws it away. The wrist taps on save, and a proof screen shows the iCloud status.
- **The nearby iPhone writes out the words and sends them back to the wrist.** Adam: “let's just assume that I have my phone with me ... the phone should be able to intervene or show me the text.” watchOS has no speech-to-text. Right after a recording stops, it goes to the iPhone in live messages, which wake the iPhone app in the background. The iPhone writes out the words and sends them back, and the review screen shows them.
  - The iPhone uses SpeechAnalyzer on iOS 26 and later, with the older recognizer as the fallback. Adam's `vocabulary` goes in as hints, and his `corrections` (“Kodak” → “Codex”) are applied last.
  - When the iPhone is out of reach, the words are written out later, when the app opens on the iPhone or Mac.
  - The recording is kept on each device, with a play row in the entry beside the words.
- Siri phrases, one per kind, which save Siri's words directly. A watch face complication.
- Captures travel through the app's own iCloud inbox zone. The first iPhone or Mac to process a capture claims it, so only one entry is made.

SAVY was the first app; its build record is `docs/watch/savy-watch.md` in SAVY-iOS.

## What is in the kit

| Path | What it is |
|---|---|
| `scripts/watchkit.py` | `files` writes the code and settings; `wire` adds the targets to the Xcode project and ends with `embed`; `embed` puts the Watch app inside the iPhone app (safe to run again); `check` reports the project; `sync` refreshes templates from SAVY |
| `scripts/sim_link_test.py` | Tests the Watch-to-iPhone link in a paired iPhone and Watch simulator, with no one at a desk: installs both apps, sends a spoken recording from the Watch app, and passes only when the words come back to the Watch. Also runs the Watch app outside the iPhone app, which must fail with 7018 |
| `scripts/watchtrail.py` | Reads the capture trail: for each capture, whether it was recorded, got its words back on the wrist, reached iCloud and became an entry, and the first step that stopped. `pull` copies the trail files off the Watch and iPhone on Adam's Mac; `read` reads files; `selftest` needs no device |
| `scripts/ci_results.py` | Reads a CI run from its job logs: each job's result, the compiler crash and failure lines, and the Watch screenshots saved as PNG files |
| `templates/shared/` | Built by the iPhone/Mac and the Watch: `WatchCapture.swift` (capture, day-and-hour reader, iCloud record with the recording as an asset, link message keys, and the trail: one line per step of each capture, with the reason when a step fails). Built by the iPhone/Mac only: `WatchCaptureImporter.swift` (claim, keep the recording, write out the words, save), `WatchCaptureTranscriber.swift`, `WatchRecordingRow.swift` (play beside the words) and `WatchCapturePhoneLink.swift` (receive a recording from the Watch, send the words back). The same in every app |
| `templates/watch/` | Watch app, recorder and player, phone link, local queue and sender, big button, review and proof screens. The same in every app |
| `templates/widgets/` | Complication. The same in every app |
| `templates/ci/` | GitHub Actions build check and the Watch scheme |
| `watch-capture.json` at the SAVY-iOS root | The worked example of an app config |

Generated per app from the config: `WatchCaptureConfig.swift` (names, iCloud zone, kinds, default kind, vocabulary, colors), `CaptureIntents.swift` (Siri phrases; App Shortcut phrases must be literals), the Watch `Info.plist` (microphone text, audio background mode), entitlements, asset catalog and the CI workflow. Written by hand per app: the destination file, the recording row's place in the entry form, the speech recognition text in the app's Info.plist, and the tests.

## Steps

1. **Read the app first.** Find its entry model, its normal save path, and its iCloud container and sync. Captures must arrive through the same save the app's own form uses. Confirm the project lists its files in `project.pbxproj`: `wire` refuses projects that use Xcode folder sync (see Gotchas).
2. **Copy the kit.** Copy `.cursor/skills/watch-capture/` from SAVY-iOS into the same path in the app's repo.
3. **Write `watch-capture.json`** at the repo root, starting from SAVY's. Set new values for:
   - `appName`, `storageFolder`, `theme` and every `xcode` field;
   - `inboxZoneName` and `recordType`, unique per app, such as `UnderstoodWatchInboxV1`;
   - `kinds` and `defaultKind`, the type a plain Save uses;
   - `vocabulary`, Adam's names and terms for the speech recognizer;
   - `corrections`, words it keeps mishearing mapped to what he meant;
   - `microphoneUsage`.

   Use Adam's own words for type labels and Siri phrases. Each phrase must contain `{app}`. An app can register at most 10 App Shortcuts, so use at most nine kinds. A kind's `case` is the raw value the iPhone/Mac side receives.
4. **Generate:** `python3 .cursor/skills/watch-capture/scripts/watchkit.py files --config watch-capture.json`
5. **Write the destination file** named in `xcode.destinationFile`, inside `xcode.sharedFolder`. Conform the app's store to `WatchCaptureDestination` (`acceptsWatchCaptures`, `hasEntry(forWatchCapture:)`, `saveEntry(fromWatchCapture:)`), and map a capture to an entry. SAVY's is `SAVY/SAVYWatchDestination.swift`. Rules carried from SAVY:
   - The words go where Adam would have typed them. For a recording, they are the words the iPhone wrote out.
   - Add nothing he did not say: no tags or notes.
   - When no words could be written out, use the app's existing generic name, so the form replaces it once he types.
   - `capture.proposedWindow` gives the day or hour heard.
   - Use the capture's `id` as the entry's id; the recording files are named by it.
   Also:
   - Add `WatchRecordingRow(entryID:)` at the top of the app's entry form, shown only when `WatchRecordingFiles.url(for:)` finds a recording.
   - Add `NSSpeechRecognitionUsageDescription` to the app's Info.plist.
   - Call `WatchCapturePhoneLink.shared.activate()` in the app delegate's `didFinishLaunching`, but not under tests. The Watch's messages arrive there, even when iOS launches the app in the background.
6. **Hook the import.** Call `await WatchCaptureImporter.shared.importPending(into: store)` on launch and on each foreground refresh, and only after the app's own iCloud sync has confirmed the signed-in owner. Pass `expectedOwner` (the iCloud record name the app's sync verified) and a `while` check that is false the moment the account changes; the importer asks it again before each claim and each save. In SAVY, `RootView.importWatchCaptures()` uses `CloudKitDocumentSync.ownerPass()` and `holds(_:)`, which follow the sync's account epoch, together with its status.
7. **Write tests** for the mapping in the app's unit test target, and list them in `xcode.testFiles`. SAVY's are in `SAVYTests/SAVYWatchCaptureTests.swift`. They test values only: no store, no iCloud, no Watch.
8. **Wire the project, once:** `python3 .cursor/skills/watch-capture/scripts/watchkit.py wire --config watch-capture.json`. It must report no dangling references and no file outside a group. Every kit file must sit in the right target's Sources phase.
9. **Push and read CI.** The workflow:
   - checks that the kit files still match the config;
   - compiles both apps for the simulators on the `xcode-27` runner (`xcode.ciRunner`);
   - runs the tests and the trail reader's own check;
   - runs the link test in a paired iPhone and Watch simulator (`sim_link_test.py`);
   - screenshots the Watch app in an Apple Watch Ultra simulator using each kind's `demoWords`.

   Read the results with `python3 .cursor/skills/watch-capture/scripts/ci_results.py --repo OWNER/REPO --branch BRANCH --out DIR`. Fix until green, and send Adam the screenshots.
10. **Install, on Adam's Mac, only after the simulators pass.** Build and install the iPhone app; the Watch app is inside it and arrives on the Watch through it. Do not install the Watch app on its own: the two apps then never see each other as a pair (see Gotchas). If signing mentions iCloud, tick the app's container under Signing & Capabilities for the Watch target. The first install asks for Developer Mode on the Watch. Build the iPhone and Mac apps from one branch that carries everything Adam uses, because they do the importing.
11. **On the Watch.** Settings, Action Button, Action, Shortcut: pick the app's “Capture”, which opens the app already recording. Allow the microphone on the first recording. Add the complication to a watch face. Try each Siri phrase. On the iPhone, open the app once with the Watch app installed and allow Speech Recognition; the link asks then.
12. **Test in simulators first; his devices are the last look.** Adam, Nov 21: “Do 1000% of your tests on a fucking simulator. That's what you should do. It should work perfectly on a goddamn fucking simulator. Instead of sitting here holding me to this fucking desk.” Never keep him at his desk for a test.
    - A capture passes through four things: recorded on the Watch, words back on the wrist, in iCloud, entry in the app. Each app writes every step to `Application Support/<storageFolder>/trail.jsonl`, with the reason when one fails and never the words.
    - Prove a change in CI's paired simulators before anything goes on a device. A simulator cannot use his iCloud account, the real microphone or Bluetooth; say so when a result depends on them.
    - On his devices, when he chooses: three captures, saying anything real: one with the iPhone app open, one with the iPhone locked in a pocket, one with the iPhone's Bluetooth off. Then he opens the app on the iPhone.
    - On his Mac, with the iPhone connected: `python3 .cursor/skills/watch-capture/scripts/watchtrail.py pull --config watch-capture.json`. It prints each capture's four results and what to do about the first one that stopped. If a device copy fails, copy the two files by hand and use `read`.
    - No trail on the iPhone means its installed app has no Watch code (see Gotchas), or has not been opened since it was installed.
    - The same lines are in the system log under the category `WatchCaptureTrail`, for watching a capture live in Console.
13. **Record it** in the app's AGENTS.md: Adam's words, what was built, what is verified, and what is not.

## Decisions carried from SAVY, and why

- **The Watch records; the iPhone or Mac writes out the words.** Apple's speech-to-text frameworks (`SFSpeechRecognizer`, `SpeechAnalyzer`) are not available on watchOS. Watch dictation always opens Apple's own dictation screen first, so it cannot start on one press. Recording sound can. Adam chose this on Nov 20: one press records, and he checks the words on the iPhone beside the recording.
- **Recording starts on screen** (watchOS refuses to start it in the background). The `audio` background mode keeps it going when the wrist drops; verify this on a real Watch.
- **A recording is never lost.** It is kept on the Watch the moment it stops. Leaving the review screen saves it, and a draft left by a closed app is saved at the next launch.
- **The phone link only writes out words; it never makes the entry.** Entries are still made once, through the iCloud import, so the live path cannot double anything. Words that arrive after Save are shown on the wrist only. The iPhone writes them out again when it imports.
- **Live messages, not file transfers.** `transferFile` is queued and not delivered right away. `sendMessage` from an active Watch app wakes the iPhone app in the background. Recordings are 16 kHz mono AAC at 24 kbps and travel in 48 KB parts.
- **The Watch asks for the words; the iPhone answers that message.** After the recording's parts, the Watch sends one small request (`wordsRequest`) and the iPhone answers it once the words are written out. The answer travels back on the Watch's own message, so it does not depend on the iPhone having noticed that the Watch app is open. Right after an install it often has not, and an answer it queues instead does not arrive in time. The older live and queued paths remain as the fallback, and the Watch ignores a second copy of the same words.
- **Background speech is the open risk.** Older reports say `SFSpeechRecognizer` fails in the background (error 1700). SpeechAnalyzer (iOS 26+) is on-device and tried first. If neither works with the phone in a pocket, the words still arrive later; verify on Adam's phone.
- **One device makes the entry.** The first iPhone or Mac claims the capture in iCloud (`importedAt`, saved only if unchanged). Every device keeps its own copy of the recording. The claiming device deletes the capture from iCloud after two weeks.
- **Each app's Watch writes only to its own inbox zone.** It never writes to the app's main sync zone. In SAVY, an unreadable record in the main zone stops entry sync until it is repaired, so a Watch bug must not be able to reach that zone.
- **The importer is idempotent.** It saves locally before removing the capture from iCloud. A per-device ledger and the capture id keep an entry from being imported twice or coming back after deletion.
- **WatchConnectivity carries only the words for the wrist.** Captures still travel by iCloud alone, so there is one path for entries.
- **The Watch app is inside the iPhone app** (`watchkit.py embed`, iOS only, so the Mac build is unchanged). Installed on its own, each app says the other is not installed and the link fails with “WatchConnectivity 7018 companionAppNotInstalled”. That happened on Adam's devices on Nov 21.

## Gotchas

- `wire` runs once per project. Running it twice adds duplicates, so it refuses if the Watch target exists.
- Projects that use Xcode folder sync (`PBXFileSystemSynchronizedRootGroup`): in Xcode, add a watchOS App target and a Widget Extension with the bundle IDs from the config, put the kit files in those folders, and tick target membership for the shared files. Then copy the build settings `wire` would have set (see `cmd_wire` in `watchkit.py`).
- Each project object must be found by its own definition, never by its id inside a list. The first SAVY run of `wire` put files in the wrong phase until this was fixed. `check` prints each phase so this is visible.
- App Shortcut phrases and intent titles must be literals. That is why `CaptureIntents.swift` is generated rather than read from config.
- An Ultra has one Action Button, so only one app's shortcut can own it.
- **One iPhone build must carry everything Adam uses.** The words coming back and the entry both happen in the iPhone app. If the iPhone app is later rebuilt from a branch without the Watch code, the Watch still records and says “in iCloud”, and nothing ever arrives. In SAVY on Nov 20, the Watch app was installed from the Watch branch while the installed iPhone app is normally built from another branch. Before installing, merge the Watch branch into whatever branch the installed apps are built from.
- **The simulator pair needs signed apps and a moment.** An unsigned build names its apps “SAVY” and “SAVYWatch” in their signatures, not by their bundle IDs, and the system never pairs them. CI signs to run locally (`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`). After an install the two simulators need some seconds before they see each other; the link test waits for that.
- **The link test hooks are for the simulator only.** `-WatchCaptureLinkTest <file>` on the Watch app and `-WatchCaptureLinkTestWords "<words>"` on the iPhone app are compiled only for Debug simulator builds. The iPhone answers with set words because a build machine has no one to allow Speech Recognition. The test recording is discarded when the test ends, and a build machine's simulator has no iCloud account to send it to.
- **Callbacks that arrive off the main thread need `@Sendable`.** These projects build in Swift 6 mode. A closure written inside a `@MainActor` type and handed to a system API as a completion handler is tied to the main thread, and the app stops if the system calls it from another one. Mark such closures `{ @Sendable ... in }`, or use the API's `async` form. The kit does this for `WCSession.sendMessage`'s handlers, `scheduleBackgroundRefresh` and the microphone permission.
- The Watch's status line names an iCloud refusal with its code (“iCloud refused it (code 10)”). “Sends when online” is only for trouble that passes by itself.
- CI runs on the `xcode-27` runner, to match the Xcode Adam builds with. On `macos-26` (Xcode 26.6, Swift 6.3.3), SAVY's existing `ReminderScheduleView.swift` crashes the compiler in IRGen. That is a toolchain crash, not a Watch-code error.
- Artifact downloads can be unreachable from an agent's session, but job logs are readable. The workflow therefore prints failure context and screenshots (base64) into the log, and `ci_results.py` reads them back. Shell tracing (`set -x`) must be off while printing, or the trace interleaves with the image data.
- The Watch simulator build is signed to run locally. Unsigned, it has no iCloud entitlement, and the app ends when it opens iCloud. The screenshots then show only the clock face.
- Demo mode (`-WatchCaptureDemo home|recording|review|saved`, Debug only) never sends to iCloud and labels captures “Demo · not sent”. Demo words must never become entries. Its recording is a silent WAV, because CI has no microphone.

## Better next

- **One suite capture app.** Because of the single Action Button, one Watch app whose doors send each capture to the right app's inbox would serve every app at once.
- **A Swift package** for the shared files, instead of copies, so a fix reaches every app without `sync`.

## Keeping the kit current

Improve the code in SAVY first and verify it in CI. Then run `watchkit.py sync --config watch-capture.json` in SAVY-iOS to copy SAVY's files into `templates/`. SAVY's CI step “Kit files match watch-capture.json” fails whenever SAVY and the kit drift apart.
