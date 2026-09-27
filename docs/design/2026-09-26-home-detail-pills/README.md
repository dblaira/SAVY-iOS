# Home destination detail pills

Adam approved the tonal mockups and requested: “Perfect. Please save this in the Mac OS and IOS versions.”

## Approved appearance

The four lower homepage destinations are Social Media Posts, Connection, Adam's Ontology, and Field Essays. Their expanded cards show the existing sentence/title reveal as plain text, followed by small count and post-reference capsules at the bottom left. Compact cards retain their title-only presentation.

Adam's correction: “Please use the same color as the card, but shade it to create a muted effect.”

| Current card color | Pill fill | Regular grey text |
| --- | --- | --- |
| White | `#EBEBEB` | `#737373` |
| Dark red | `#98011F` | `#CEC7C9` |
| Tan | `#BCA489` | `#595653` |

The palette follows the card's existing display position, including after reordering. Metadata uses 9-point regular text, 16-point capsule height, 6-point horizontal inset, and 4-point spacing. Whole pills wrap when needed. No count/reference icons are introduced. Sentence reveals keep the existing 14-point typography and three-line limit; title/divider colors, pin behavior, saved content, intrinsic card heights, and the upper carousel remain unchanged.

Social Media Posts has one saved-count pill and one pill for its existing first-three-post reference string. The other destinations each have one item-count pill. All values come from existing native data, not the sample values in the mockup.

- [Approved homepage context](approved-homepage.png)
- [Approved expanded examples](approved-expanded-cards.png)

Generated mockups record the approved appearance. Native source defines exact measurements.

## Delivery verification

- iPhone Debug build passed for Adam's connected iPhone 17 Pro Max (`00008150-000D793E0208401C`). Installed in place and launched through `devicectl`. After Adam opened SAVY with Face ID, the physical iPhone Home was observed through QuickTime's wired screen source: Social Media Posts shows regular grey count/reference pills on shaded white, and Connection shows its shaded-red count pill below the plain sentence. The small metadata stays regular with the phone's Bold Text setting enabled. The preview was closed afterward.
- Mac Catalyst Release build passed through `./script/build_and_run.sh --verify`. The script verified the signature, preserved the previous app, installed `/Applications/SAVY.app`, and launched it. Normal app authentication completed.
- Live Mac inspection confirmed the white-card grey pills, red-card shaded-red pill, regular small text, plain reveals, and unchanged compact Ontology/Field Essays cards.
- Temporarily expanded Ontology and Field Essays through their existing Pin actions to inspect all four native footers and the tan palette after reordering. Verified all four counts, the Posts reference string, and that pills track the current card color. Restored the original order and pin states: Social Media Posts and Connection pinned; Ontology and Field Essays unpinned.
- Shared Swift implementation files are byte-identical in the iOS and Mac checkouts. Independent source review and `git diff --check` passed. This visual-only change adds no model or persistence logic.

Screenshots:

- [Installed physical iPhone Home](device-verification/installed-iphone-home.png)
- [Installed Mac Home](device-verification/installed-mac-home.png)
- [All four expanded on Mac during the restored-afterward check](device-verification/installed-mac-expanded-check.png)

Built executable SHA-256:

- iPhone: `0886d36aefcaeb2d120ceb7dc587184097e3924f83754e20a4ad2554d64d0efd`
- Mac: `6febff8beb32506182dd1080c51ac71e27d0668c4e68514f18e2a402855b4ca8`
