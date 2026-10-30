# Delegate entry boxes match; full QA is green (Executive Conclusion)

1. ✍️ Delegate questions remain visible in the same black regular styling as Decide and Visual.

2. 🖥️ SAVY’s installed Mac form and both physical-iPhone apps were inspected. The first prompt focuses the answer directly below it.

3. ✅ Understood passed all 44 tests in the final full run. The exact code/test revision passed GitHub iOS Build.

# Styling and font sizes remain exactly as they are (Consequence)

1. 🔤 All 88 SAVY app files and all 43 Understood app files still match the installed feature source after QA.

2. ⌨️ Growing answers start directly beneath permanent questions. The existing caret editing and field navigation remain connected.

3. 💾 Saved writing and media are unchanged. SAVY’s two changed phone files contain CloudKit synchronization metadata.

# Installed and inspected; full QA and code CI passed (Recommendation)

SAVY’s signed Mac Release is installed at `/Applications/SAVY.app`. Both signed phone builds are installed on the physical iPhone. The actual SAVY Social and Understood Action forms were compared with Visual. All three Delegate questions match its dark body styling. Prompt taps focused the answers directly below. Blank live forms were canceled without writing or saving.

Final Understood full QC returned exit 0 and `QC GREEN`. All eight gates passed. Its valid xcresult records 44/44 tests passed, including 11 unit tests and 33 UI tests. There were no failures or skips. Expected failures were zero and runtime warnings were empty. SAVY’s two focused UI tests also passed with zero failures.

The tested code/test revision `36ab69c3723521ff89d715723cbf9ac50a930d66` is pushed and its exact [GitHub iOS Build succeeded](https://github.com/dblaira/Re_Call/actions/runs/41012230810). All app-source files were checked against the freeze again after QA and remain unchanged. The QA work preserved the installed styling and font sizes exactly.

The final native commit is documentation only. Exact-HEAD CI verification is required after that push; its actual outcome is recorded in social status without reopening this native report.

# Actual screens and final verification record (Supporting Evidence on Request)

Adam’s request, verbatim:

> One other request.  Match the Delegate entry boxes to the other entry forms.  They should not be muted and disappear when text is entered. They should be the same as Decide, and Visual.

Latest instruction, verbatim:

> Finish the full QA and GitHub build checks while I'm asleep. Keep the styling and font sizes exactly as they are.

| Final check | Result |
| --- | --- |
| Permanent Delegate questions | Black regular questions remain above their answers |
| Existing font sizes | Preserved in both apps |
| Answer placement | Zero stack gap; top-aligned growing answers |
| Question and icon taps | Focus the matching existing answer field |
| Existing caret editing | Active-field guard preserves editing inside an already focused answer |
| Data model and writing bindings | Unchanged |
| SAVY Mac Release installation and inspection | Passed; actual Social form matches Visual |
| SAVY physical-iPhone installation and inspection | Passed; Social questions and first-prompt caret checked |
| Understood physical-iPhone installation and inspection | Passed; Action questions and first-prompt caret checked |
| Blank live forms | Canceled without writing or saving |
| SAVY focused UI tests | 2/2 passed; zero failures |
| Understood full QC | All eight gates passed; exit 0 and QC GREEN |
| Final combined native test run | 44/44 passed |
| Unit tests | 11/11 passed |
| UI tests | 33/33 passed |
| Failures | 0 |
| Skips | 0 |
| Expected failures | 0 |
| Runtime warnings | Empty |
| VisualEntryForm cases | All six passed in the final full run |
| Smoke cases | All seven passed in the final full run |
| Tested code/test revision | `36ab69c3723521ff89d715723cbf9ac50a930d66` |
| Exact code/test revision GitHub iOS Build | [Succeeded](https://github.com/dblaira/Re_Call/actions/runs/41012230810) |
| Post-QA app-source freeze | All 88 SAVY and 43 Understood files unchanged |
| Final documentation-only HEAD | Exact-HEAD CI verification required after push; outcome recorded in social status |

The unchanged outer QC log is preserved as [full QA.log](</Users/adamblair/Developer/GitHub/Re_Call/docs/Delegate entry boxes/full QA.log>) in each evidence mirror.

Final valid xcresult: `/Users/adamblair/Library/Developer/Xcode/DerivedData/ReCall-QC/Logs/Test/Test-ReCall-2026.10.29_23-03-08--0700.xcresult`.

Final raw UI log: `/tmp/recall-delegate-final-ui.log`.

Final raw UI log SHA256: `75dbbe35e5486504931ccc34a22310d11a57f827ff8b56b5a0ebc877b45f6121`.

App-source freeze: `/tmp/delegate-app-source-freeze.json`. The post-QA check confirms the same installed feature source at SAVY `18f84a0ead426fc89a65973f81865dfaa492265a` and Understood `588e743ca018cc8a3a3f66cdcc7eca493b828b1f`. The final helper commit changed test behavior only.

### Earlier attempts and the test-helper correction

The first full UI run passed 32/33 cases while its 11 unit tests passed. The existing ProArrangement file-picker case failed at an invalid Cancel/Menu retap. Its unchanged focused retry failed again; the next clean run exposed the same Cancel-state problem. Raw logs are preserved at `/tmp/recall-delegate-first-ui.log` and `/tmp/recall-delegate-second-ui.log`. Lingering xcodebuild diagnostic processes were stopped after preserving those logs.

The correction retains all prior assertions. The Files Cancel control is resolved through its scoped navigation bar and tapped only after its frame settles. Its focused check passed one test with zero failures or skips in 74.981 seconds. The process returned exit 0 and `TEST SUCCEEDED`; its valid bundle is `/tmp/recall-delegate-picker-stable.xcresult`.

The focused result records the settled Files Cancel frame as `{{325.3, 86}, {36.7, 36}}`. The computed hit point `{343.7, 104}` is inside that frame. The failed run’s moving element had a converted hit point outside its frame. No Pro app code changed. The final full run then passed all 44 tests together.

Earlier feature revision `588e743ca018cc8a3a3f66cdcc7eca493b828b1f` passed its [GitHub iOS Build](https://github.com/dblaira/Re_Call/actions/runs/41010270631). Earlier code/test revision `11a02b7e363ba8603e3d8ba484dee7f56e55d4d3` also passed its [GitHub iOS Build](https://github.com/dblaira/Re_Call/actions/runs/41010590916). These historical checks are separate from the tested final helper revision above.

Understood source: [ReminderFormView.swift](/Users/adamblair/Developer/GitHub/Re_Call/ios/ReCall/App/ReminderFormView.swift).

SAVY source: [ReminderFormView.swift](/Users/adamblair/Developer/GitHub/SAVY-iOS/SAVY/ReminderFormView.swift).

| Verification log | Location |
| --- | --- |
| Initial Understood full QC | `/tmp/recall-delegate-full-qc.log` |
| Earlier clean Understood full QC | `/tmp/recall-delegate-clean-full-qc.log` |
| Final full QC, passed | `/tmp/recall-delegate-final-full-qc.log` |
| Focused stable-Cancel pass | `/tmp/recall-delegate-picker-stable.log` |
| Valid focused stable-Cancel xcresult | `/tmp/recall-delegate-picker-stable.xcresult` |
| Preserved second UI raw log | `/tmp/recall-delegate-second-ui.log` |
| Preserved first full UI raw log | `/tmp/recall-delegate-first-ui.log` |
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
| Understood | 14/14 files byte-identical; confirmed again after actual blank-form cancellation |
| SAVY | 22/24 files byte-identical; same relative file paths |
| SAVY writing and media | Unchanged |
| Changed SAVY files | `SAVY/CloudKit/state.json` and `SAVY/CloudKit/status.json` |

Final Understood comparison after blank-form cancellation: `/var/folders/ll/k4r0q6fj5k18c1vh9vk5t1c80000gn/T/delegate-understood-final-llczqad1`. All 14 files still match.

The changed SAVY files contain synchronization metadata. The changed keys were `generation`, `engineState`, `lastForegroundFetch` and `lastFetch`.

The previous Visual addition reports remain historical evidence of that earlier installation. The live evidence below verifies this Delegate correction separately.

**Installed SAVY Mac Release.** The actual blank Social form shows Delegate matching Visual. Tapping the first prompt focused the answer directly below, verified through accessibility state. The form was canceled without saving.

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
