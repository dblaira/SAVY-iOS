# Native inline completion: September 26, 2026 attempt

## Result

**Native gray completion was visibly demonstrated and accepted with Space inside SAVY's real Post DecideAnswer0 on the iOS 27 Simulator. This is not physical-iPhone acceptance or a completed release.**

Started 2026-09-26 23:42:49 UTC, bounded to 20 minutes and 500,000 tokens. The goal reached its token budget during final evidence capture. Stopped further substantive work. No physical phone operated. No commit or push.

Current starting revision was clean main at 527e4639c7e062612f38372a47df91fcf55ac79d, matching recorded origin/main. The older handoff's dirty experimental editor was absent. The current keyboard-row implementation was preserved as the starting point.

## Evidence

All images and the standalone native control live under `artifacts/native-text-entry/attempt-20260926/`.

- `savy-post-inline-visible.png`: real Post field displays black `We I was try` followed by native gray `ing to`.
- `savy-post-inline-accepted.png`: software Space accepts the continuation; full `We I was trying to` is black.
- Native trace observed proposed completion with markedTextRange present, then accepted `We I was trying to ` with markedTextRange nil. Trace was removed from source during wrap-up; no writing-content logging remains in the implementation.
- `post-original-we-no-gray.png`: original SwiftUI field, same blank-field prefix, no gray continuation.
- `control-we-prefix-gray.png`: independent plain UITextView, same prefix, gray continuation.
- `control-exact-prefix.png`: plain UITextView with `When I was try` did NOT show gray completion. Prediction depends on context; this phrase cannot serve as a deterministic feature test.
- `control-inline-visible.png` / `control-inline-accepted.png`: initial successful plain-native control experiment.
- `post-original-no-gray.png`: original field with individual software key touches for `When I was try`, no gray completion.
- `post-baseline-inline-visible.png` is an early misnamed file: it shows NO gray completion, and must not be cited as successful evidence.

The native test control is pure UIKit/SwiftUI, with no custom ghost text or prediction provider. XcodeBuildMCP semantic tap returned success without entering keys; actual touch down/up worked. This does not establish anything about XCTest suppression.

## Implementation retained, uncommitted

Only `SAVY/ReminderFormView.swift` is modified. Shared Post/Connection Decide fields use UITextView with native inline prediction, marked-text/equality guards, stable theme identity, native focus synchronization, and an input accessory row matching the existing navigation actions. No custom completion text is drawn.

Initial bridge focus regression was repaired by registering the wrapper with FocusState. SwiftUI's keyboard toolbar did not appear for this native editor; the final experimental build supplies a native accessory row. Its buttons were visible, but their navigation and Done behavior were not exercised. Final source differs from the successful installed build only by removal of temporary DEBUG trace prints. That logging-only cleanup was diff-checked, not rebuilt.

## Remaining work

1. Verify the same native completion and acceptance in Connection and in a normal question-plus-answer draft.
2. Verify keyboard row navigation/Done, long answers, copy/paste, save/reopen, theme changes, and composition behavior.
3. Coordinate Adam's physical iPhone availability and obtain visible acceptance there. Simulator evidence is not a substitute.
4. Commit/push only after review and the required verification. No release claim is made.

All SAVY launches used isolated UI-test repositories with cloud sync disabled for diagnostic writing; the initial launch without flags reached the unsigned-in gate and did not write entries. Synthetic drafts were cancelled; the final app process was stopped. No live entries were edited. The earlier experiment patch/source, including temporary trace instrumentation, remain in ignored artifacts for reproducibility.
