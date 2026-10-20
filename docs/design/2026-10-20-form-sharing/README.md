# Entry form sharing

The shared entry form has a black `square.and.arrow.up` icon at the bottom center. Its 30-point symbol sits in a 64-point circle, matching the existing FAB's size and position. The native glass treatment mirrors the circular Close and Save controls at the top. It remains available while scrolling and above the keyboard. There is no visible Share label; VoiceOver receives “Share.”

The form heading and type selector now read **Social**. Existing saved entries retain their `post` storage value.

The circle rises 22 points above a solid, full-width, 1-point divider at the footer's top edge, matching the existing FAB's overlap. A white circular backing keeps the divider behind the button. The footer extends through the bottom safe area.

On iOS 26 and later, the circle uses Apple's [native Liquid Glass effect](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views), with a material-circle fallback on earlier supported versions. Its bottom spacing uses the same layout constant as SAVY's existing FAB.

Share opens the native destination picker directly with the entire form: current Decide questions and answers, the three Delegate fields, steps and metadata. There is no scope menu. The iPhone's share sheet still lets Adam choose where to send the text.

Original writing, line breaks and edited questions are preserved. Images and image paths are excluded. Sharing reads the current draft, including pending tags, without saving an entry or clearing the editor. Sharing again after an edit includes the latest writing.

Metadata includes the selected theme, Pattern, Lift, priority, energy, effort, tags, flags, status, notes, link, location, waiting-on text, schedule and repeat information. Existing Social numbers and success/compounding markers are included when present.

The shared formatter and icon control match Understood's implementation. This change applies to SAVY's shared Reminder, Action, Calendar, Social and Connection entry form.

## Simulator verification

Functional testing ran exclusively in the simulator as Adam requested.

- iPhone 17 Pro Max simulator, iOS 27.
- Five export unit tests passed, covering exact writing, every Delegate field, steps, metadata, legacy questions, pending tags and image exclusion.
- The sharing UI test passed. It compares Share's center, width and height with the existing FAB, checks the Social selector and visibility above the keyboard, and opens native Copy directly without a scope choice.
- The test copies the entire draft, returns to the form, adds writing, and copies the entire form again. Both exports retain the exact text and metadata. Cancelling afterward creates no entry.

Final direct-sharing result: `/tmp/form-sharing-20261020/SAVY-entire-only-final.xcresult`; log: `/tmp/form-sharing-20261020/savy-entire-only-final.log`. The screenshots below come from this successful run.

An initial test inserted its added sentence at the beginning because it assumed a cursor position. The native export correctly contained that edit. The test now places the cursor explicitly and verifies the field before sharing; product code did not change for this test correction.

Earlier validation before removing the scope menu: 152 unit tests and three UI tests passed in `/tmp/form-sharing-20261020/SAVY-final-share.xcresult`; all ten existing form regression tests also passed before the placement revisions. The approved divider layout separately passed the existing keyboard cursor regression.

## Phone installation for Adam's inspection

The direct whole-form version's signed Debug build installed and launched on Adam's connected iPhone 17 Pro Max. Its receipts are `/tmp/form-sharing-20261020/entire-only-phone-install.json` and `/tmp/form-sharing-20261020/entire-only-phone-launch.json`.

Before installation, SAVY was in the background and its freshly copied recovery file contained no unfinished draft. The saved reminders file, containing 47 entries, was byte-for-byte unchanged after installation. The installed app's Home screen was observed. Sharing interactions were tested in isolated simulator storage.

## Captured app screens

- [Share crossing the divider, Social heading](share-icon.png)
- [Share stays available above the keyboard](share-keyboard.png)
- [Entire form opens directly in the native share sheet](entire-form-share-sheet.png)
- [Entire form shared again after an edit](updated-form-share-sheet.png)
- [Editor after sharing](editor-after-sharing.png)
