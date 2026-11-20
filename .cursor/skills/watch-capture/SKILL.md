---
title: watch-capture
type: skill
tags: [skills, ios, watchos, build]
created: 2026-11-20
updated: 2026-11-20
summary: Adds the SAVY-style Apple Watch capture app to another of Adam's iPhone/Mac apps. Load when Adam says any of: "add the watch app to", "put the Apple Watch capture on", "same type of iPhone Apple Watch app", "save the watch workflow", "watch capture kit"
deployed_to: ["SAVY-iOS/.cursor/skills/watch-capture/SKILL.md", "SAVY-iOS/.claude/skills/watch-capture/SKILL.md (pointer)"]
related: ["[[Skills Hub]]", "SAVY-iOS docs/watch/savy-watch.md"]
---
## Say this to trigger

“Add the watch app to Understood.” “Put the Apple Watch capture on Harness.” “Same Watch app as SAVY.”

# Watch capture kit

Adam, Nov 20, 2026: “I'm gonna put the same type of iPhone Apple Watch app on for three or four of my other apps and it's gonna have almost identical functionality”. Then: “save the watch workflow so I can reuse it”.

What one run produces in an app: a Watch app with one door per entry type. Each door opens Watch dictation. A proof screen shows the exact words with a wrist tap, and one tap re-records. Captures are saved on the Watch first. The app also gets Siri phrases, an Action Button shortcut and a watch face complication. Captures travel through the app's own iCloud inbox zone, and the iPhone or Mac turns each one into a normal entry. SAVY was the first app; its build record is `docs/watch/savy-watch.md` in SAVY-iOS.

## What is in the kit

| Path | What it is |
|---|---|
| `scripts/watchkit.py` | `files` writes the code and settings; `wire` adds the targets to the Xcode project; `check` reports the project; `sync` refreshes templates from SAVY |
| `templates/shared/` | `WatchCapture.swift` (capture, day-and-hour reader, iCloud record) and `WatchCaptureImporter.swift` (iPhone/Mac import). The same in every app |
| `templates/watch/` | Watch app, local queue and sender, doors and proof screen. The same in every app |
| `templates/widgets/` | Complication. The same in every app |
| `templates/ci/` | GitHub Actions build check and the Watch scheme |
| `watch-capture.json` at the SAVY-iOS root | The worked example of an app config |

Generated per app from the config: `WatchCaptureConfig.swift` (names, iCloud zone, kinds, colors), `CaptureIntents.swift` (Siri phrases; App Shortcut phrases must be literals), the Watch entitlements, asset catalog and the CI workflow. Written by hand per app: the destination file and its tests.

## Steps

1. **Read the app first.** Find its entry model, its normal save path, and its iCloud container and sync. Captures must arrive through the same save the app's own form uses. Confirm the project lists its files in `project.pbxproj`: `wire` refuses projects that use Xcode folder sync (see Gotchas).
2. **Copy the kit.** Copy `.cursor/skills/watch-capture/` from SAVY-iOS into the same path in the app's repo.
3. **Write `watch-capture.json`** at the repo root, starting from SAVY's. Set new values for `appName`, `inboxZoneName` and `recordType` (unique per app, such as `UnderstoodWatchInboxV1`), `storageFolder`, `theme`, `kinds`, and every `xcode` field. Use Adam's own words for door labels and Siri phrases. Each phrase must contain `{app}`. An app can register at most 10 App Shortcuts, so use at most nine kinds. A kind's `case` is the raw value the iPhone/Mac side receives.
4. **Generate:** `python3 .cursor/skills/watch-capture/scripts/watchkit.py files --config watch-capture.json`
5. **Write the destination file** named in `xcode.destinationFile`, inside `xcode.sharedFolder`. Conform the app's store to `WatchCaptureDestination` (`acceptsWatchCaptures`, `hasEntry(forWatchCapture:)`, `saveEntry(fromWatchCapture:)`), and map a capture to an entry. SAVY's is `SAVY/SAVYWatchDestination.swift`. Rules carried from SAVY:
   - The words go where Adam would have typed them.
   - Add nothing he did not say: no tags, notes or generic names.
   - `capture.proposedWindow` gives the day or hour heard.
   - Use the capture's `id` as the entry's id, so two devices importing the same capture make one entry.
6. **Hook the import.** Call `await WatchCaptureImporter.shared.importPending(into: store)` on launch and on each foreground refresh, and only after the app's own iCloud sync has confirmed the signed-in owner. In SAVY, `RootView.importWatchCaptures()` gates on `CloudKitDocumentSync.status`.
7. **Write tests** for the mapping in the app's unit test target, and list them in `xcode.testFiles`. SAVY's are in `SAVYTests/SAVYWatchCaptureTests.swift`. They test values only: no store, no iCloud, no Watch.
8. **Wire the project, once:** `python3 .cursor/skills/watch-capture/scripts/watchkit.py wire --config watch-capture.json`. It must report no dangling references and no file outside a group. Every kit file must sit in the right target's Sources phase.
9. **Push and read CI.** The workflow compiles both apps unsigned, runs the tests, screenshots the Watch app in a Watch simulator using each kind's `demoWords`, and checks that the kit files still match the config. Read errors with `gh api repos/OWNER/REPO/check-runs/JOB_ID/annotations`. Screenshots are in the `watch-screenshots` artifact. Fix until green.
10. **Install, on Adam's Mac.** Open the project, choose the Watch scheme and his Watch, and Run. If signing mentions iCloud, tick the app's container under Signing & Capabilities for the Watch target. The first install asks for Developer Mode on the Watch. Install the iPhone and Mac apps from the same branch, because they do the importing.
11. **On the Watch.** Settings, Action Button, Action, Shortcut: pick the app's “Capture” or a single kind. Add the complication to a watch face. Try each Siri phrase.
12. **Record it** in the app's AGENTS.md: Adam's words, what was built, what is verified, and what is not.

## Decisions carried from SAVY, and why

- **Watch dictation gives the words; no raw audio is kept.** Apple's speech-to-text frameworks (`SFSpeechRecognizer`, `SpeechAnalyzer`) are not available on watchOS, so a Watch app cannot turn its own recording into words. Dictation shows the exact words on the wrist, which is the proof. Keeping audio would mean the iPhone writes the words after the run. That is Adam's call (open question on SAVY).
- **Each app's Watch writes only to its own inbox zone.** It never writes to the app's main sync zone. In SAVY, an unreadable record in the main zone stops entry sync until it is repaired, so a Watch bug must not be able to reach that zone.
- **The importer is idempotent.** It saves locally before removing the capture from iCloud. A per-device ledger and the capture id keep an entry from being imported twice or coming back after deletion.
- **No WatchConnectivity.** With the iPhone in a pocket, the Watch's iCloud traffic already goes through it, so one path is enough.
- **The Watch app is not embedded in the iPhone app yet.** That keeps the iPhone and Mac build settings untouched. Embedding is needed before TestFlight or the App Store.

## Gotchas

- `wire` runs once per project. Running it twice adds duplicates, so it refuses if the Watch target exists.
- Projects that use Xcode folder sync (`PBXFileSystemSynchronizedRootGroup`): in Xcode, add a watchOS App target and a Widget Extension with the bundle IDs from the config, put the kit files in those folders, and tick target membership for the shared files. Then copy the build settings `wire` would have set (see `cmd_wire` in `watchkit.py`).
- Each project object must be found by its own definition, never by its id inside a list. The first SAVY run of `wire` put files in the wrong phase until this was fixed. `check` prints each phase so this is visible.
- App Shortcut phrases and intent titles must be literals. That is why `CaptureIntents.swift` is generated rather than read from config.
- An Ultra has one Action Button, so only one app's shortcut can own it.
- CI runs on `macos-26`. Simulator builds are unsigned. Compile errors come back as check-run annotations, ten per step.

## Better next

- **One suite capture app.** Because of the single Action Button, one Watch app whose doors send each capture to the right app's inbox would serve every app at once.
- **A Swift package** for the shared files, instead of copies, so a fix reaches every app without `sync`.

## Keeping the kit current

Improve the code in SAVY first and verify it in CI. Then run `watchkit.py sync --config watch-capture.json` in SAVY-iOS to copy SAVY's files into `templates/`. SAVY's CI step “Kit files match watch-capture.json” fails whenever SAVY and the kit drift apart.
