# Delegate entry boxes (Executive Conclusion)

1. ✍️ Delegate questions remain visible in the same black regular styling as Decide and Visual.

2. 🖥️ The installed SAVY Mac Social form was inspected. The Delegate icons and spacing match Visual.

3. 📱 Both installed iPhone apps were inspected. Tapping the first Delegate prompt placed the caret directly below it.

# The question remains while writing grows (Consequence)

1. 🔤 Existing form font sizes are preserved in both apps.

2. ⌨️ Answers begin directly below the question. Existing field identifiers and focus navigation remain connected.

3. 💾 Saved writing and media are unchanged. SAVY’s two changed phone files contain CloudKit synchronization metadata.

# Installed and inspected; Understood full QC is pending (Recommendation)

SAVY’s signed Mac Release was installed through `script/build_and_run.sh --verify` and launched at `/Applications/SAVY.app`. Both signed final phone builds were installed successfully on the physical iPhone. The actual SAVY Social and Understood Action forms were compared with Visual. All three Delegate labels use the same dark body styling. The first-prompt tap was checked directly in each app. The blank forms were canceled without writing or saving.

SAVY’s two final focused UI tests passed with zero failures. They verified answer expansion and complete values, including no ellipsis and Save/reopen behavior. They also checked prompt persistence and focus.

Understood’s full QC is still running. An existing ProArrangement file-picker case failed when an immediate Menu retap used coordinates `{-1, -1}` after Photo Library Cancel. The unchanged case will be retried after the full run. The full gate is not reported as passed. Commit, push and final-revision GitHub verification are pending.

# Actual screens and verification record (Supporting Evidence on Request)

Adam’s request, verbatim:

> One other request.  Match the Delegate entry boxes to the other entry forms.  They should not be muted and disappear when text is entered. They should be the same as Decide, and Visual.

| Check | Current result |
| --- | --- |
| Permanent Delegate questions | Implemented in both shared native forms |
| Question color and weight | Black and regular, using each app’s existing question font |
| Existing font sizes | Preserved |
| Answer placement | Zero question/answer stack gap; top-aligned growing answer |
| Question and icon taps | Focus the matching existing answer field |
| Existing caret editing | Whole-row focus guard uses the active field |
| Data model and writing bindings | Unchanged |
| Understood signed phone build and installation | Succeeded on the physical iPhone |
| Understood full QC | Running; one file-picker case failed; unchanged retry pending |
| SAVY phone and Mac builds | Succeeded |
| SAVY final focused UI tests | 2/2 passed; zero failures |
| SAVY Mac Release installation | Succeeded through the verified install script |
| Installed SAVY Mac Social inspection | Delegate matches Visual; first prompt focuses answer directly below |
| Physical SAVY Social inspection | All three dark questions match Visual; first-prompt caret checked directly |
| Physical Understood Action inspection | All three dark questions match Visual; first-prompt caret checked directly |
| Blank live forms | Canceled without writing or saving |
| Isolated SAVY Mac Debug preview | All three prompts and exact sample answers visible; canceled without saving |
| Final pushed revision’s GitHub build | Pending |

Understood source: [ReminderFormView.swift](/Users/adamblair/Developer/GitHub/Re_Call/ios/ReCall/App/ReminderFormView.swift).

SAVY source: [ReminderFormView.swift](/Users/adamblair/Developer/GitHub/SAVY-iOS/SAVY/ReminderFormView.swift).

| Verification log | Location |
| --- | --- |
| Understood full QC | `/tmp/recall-delegate-full-qc.log` |
| Understood signed phone build | `/tmp/recall-delegate-device-final.log` |
| SAVY final focused UI tests | `/tmp/savy-delegate-ui-final.log` |
| SAVY Mac Release installation | `/tmp/delegate-mac-install.log` |

Fresh Mac preinstallation backup: `/var/folders/ll/k4r0q6fj5k18c1vh9vk5t1c80000gn/T/delegate-mac-preinstall-6zxt2x8u`.

| Mac saved archive check | Result |
| --- | --- |
| Compared archives | All four byte-identical after installation and after blank-form cancellation |
| Reminders | 54 |
| Recovery drafts | 0 |
| Connections | 3 |
| Legacy posts | 1 |

Fresh phone preinstallation backup: `/var/folders/ll/k4r0q6fj5k18c1vh9vk5t1c80000gn/T/delegate-phone-preinstall-kyxv88i2`.

Phone postinstallation copy and comparison: `/var/folders/ll/k4r0q6fj5k18c1vh9vk5t1c80000gn/T/delegate-phone-postinstall-02nl3eel`.

| Physical-phone saved files | Result |
| --- | --- |
| Understood | 14/14 files byte-identical |
| SAVY | 22/24 files byte-identical; same relative file paths |
| SAVY writing and media | Unchanged |
| Changed SAVY files | `SAVY/CloudKit/state.json` and `SAVY/CloudKit/status.json` |

The changed SAVY files contain synchronization metadata. The changed keys were `generation`, `engineState`, `lastForegroundFetch` and `lastFetch`.

The previous Visual addition reports remain historical evidence of that earlier installation. The live evidence below verifies this Delegate correction separately.

**Installed SAVY Mac Release.** The actual blank Social form shows Delegate matching Visual. The first prompt was tapped and the caret appears directly underneath. The form was canceled without saving.

![Mac app](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Delegate entry boxes/Mac app.jpg>)

**Installed SAVY on the physical iPhone.** The blank Social form shows all three dark Delegate questions with the matching crimson icons beneath Visual.

![phone app](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Delegate entry boxes/phone app.jpg>)

**SAVY after the first Delegate prompt tap.** The actual Social form is focused for writing beneath the question. Direct inspection confirmed the caret position. The blank form was canceled without saving.

![entry boxes](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Delegate entry boxes/entry boxes.jpg>)

**Installed Understood on the physical iPhone.** The actual Action form shows the caret immediately beneath “What do I want?” All three Delegate questions remain dark and visible. The blank form was canceled without saving.

![Understood](</Users/adamblair/Developer/GitHub/Re_Call/docs/Delegate entry boxes/Understood.jpg>)

**Isolated Mac Debug preview.** This earlier screenshot records all three questions with exact sample writing. It was canceled without saving. It remains distinct from the live captures above.

![SAVY](</Users/adamblair/Developer/GitHub/SAVY-iOS/docs/design/Delegate entry boxes/SAVY.jpg>)

All five original JPEG files are copied without changing their bytes.
