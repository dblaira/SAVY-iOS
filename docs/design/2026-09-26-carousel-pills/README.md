# Approved carousel detail pills

Adam approved the final mockups and requested implementation: "Yes. This is the correct design. Please build this new design." He then confirmed his iPhone was available for installation and inspection.

## Design

- Retain the title-first 282 × 151 pt sand card (`#F3EAD5`) and existing navy serif title.
- Change only the carousel title divider to original form crimson (`#DC143C`), 36 × 2 pt.
- Anchor details 14 pt from the left and 12 pt from the bottom.
- Render selected Theme, Pattern, Priority, and Energy values only. Preserve every other field in the saved record and full editor.
- Use 16 pt capsules, flat muted tan `#E2D4B9`, 9 pt regular grey text `#737373`, and original crimson SF Symbols configured at 10 pt.
- Use 6 pt horizontal capsule padding, 3 pt between icon and text, and 4 pt between capsules/rows. At 3×, the nominal text size is 27 px and capsule height is 48 px.
- Theme uses the selected theme's original first-question symbol (or the form's generic `list.bullet` fallback for an unknown saved theme). Pattern uses `list.number`, Priority `exclamationmark.3`, and Energy the outlined `bolt`.
- As in the approved close-up, Theme/Pattern come first; Priority/Energy share the following row. Long Theme/Pattern values wrap whole pills, retaining the 9 pt font. VoiceOver exposes the field type and full value.
- Empty selections show no pills. Existing compact/unpinned cards retain their title-only presentation.

## Approval references

- `approved-card-detail.png`: approved close-up, with illustrative example selections.
- `approved-carousel.png`: approved desktop-context mockup.

These generated mockups demonstrate appearance; the source dimensions above govern the native implementation.

## Implementation

`SavyCarouselDetails.swift` projects the four saved fields and renders native SwiftUI capsules. `SavyBandCard.carouselDetails` opts the Home carousel into bottom-aligned metadata without changing the other card layouts. Source-backed carousel entries without these fields have no metadata fallback. No stored records, forms, or persistence schema are changed.

The small footer explicitly uses regular legibility weight to retain Adam's requested non-bold appearance.

## Verification

The physical Debug build passed from the permanent `SAVY.xcodeproj`, scheme `SAVY`. The final app was installed and launched on Adam's connected iPhone 17 Pro Max on September 26, 2026. Adam opened SAVY with Face ID for the final check.

`device-verification/installed-home.png` is the actual phone screen observed through QuickTime's wired iPhone preview, with saved native entries. It shows the two-line "Pattern recognition, value capture" title, crimson divider, Pattern pill above Priority/Energy, regular muted-grey text, and darker tan capsule fills anchored at the bottom left. The adjacent New Identity card has no pills. No synthetic records were added. This capture verifies the visible saved cards; a saved card combining all four types or three rows was not on this screen.

The preview was closed after capture. Source review confirmed the four-field projection, original theme symbols, shared-card opt-in, and preservation of all other fields. `git diff --check` passed. No automated UI tests were run for this appearance change.

Installed executable SHA-256: `faec5f832e1e4f828f32308994874a27f28501a0843ccdb435363c645ee72d47`.

## Mac verification

Adam also requested checking the macOS app. The same carousel patch was applied in `/Users/adamblair/agents/savy-mac` on its existing `main` checkout at `3fb3131`; unrelated newer iPhone entry-form work was not copied into it.

`./script/build_and_run.sh --verify` passed the Release Mac Catalyst build, signature validation, installation at `/Applications/SAVY.app`, and launch. The prior installed app was preserved by the script under ignored `artifacts/mac-build/`.

`device-verification/installed-mac-home.png` shows the live installed Mac app with saved native data. Visual inspection confirmed the first card's Pattern/Priority/Energy pills, the New Post card's How-To theme with its original checkered-flag symbol, the two cards without selected eligible details, bottom-left alignment, tan fill, regular grey text, and crimson dividers. Accessibility inspection exposes only those selected four field types and the title for each carousel card; the old Tags, Lift, repeat, answer excerpts, and source kicker are absent. The existing desktop columns and navigation remain in place. The app is left open.

Installed Mac executable SHA-256: `7aa6bc453b9a858ac1e73db287c6ce866753b2bb0c8415ac130b801eac9f05c2`.

Both checkouts pass `git diff --check`. After reviewing the live results, Adam requested saving, committing, and pushing this work. This checkpoint includes the native implementation, approved mockups, and both installed-app screenshots.
