# Readable carousel details

Adam reported: “I used the SAVY app today and couldn't read the pill-shaped details.” He approved “Keep the muted styling and regular weight, with larger text and pills.”

## Change

| Carousel measurement | Previous | Updated |
| --- | --- | --- |
| Regular text | 9 pt | 12 pt |
| Original crimson icons | 10 pt | 13 pt |
| Pill height | 16 pt | 24 pt |
| Horizontal pill inset | 6 pt | 8 pt |
| Uniform card size | 282 × 151 pt | 282 × 182 pt |

On the iPhone's 3× display, the nominal new text size is 36 pixels and pill height is 72 pixels. The card gains room for the existing two-line title, a minimum 6-point title/footer gap, and up to three pill rows without shrinking the text. Whole pills retain the existing wrapping and field order.

The tan fill, grey text, original crimson icons, regular legibility weight, red title divider, bottom-left placement, and Theme/Pattern/Priority/Energy projection are unchanged. Compact cards remain compact. This correction applies to the carousel on iPhone and Mac Catalyst; lower homepage destination pills and saved data are unchanged.

## Verification

- iPhone Debug build passed for Adam's connected iPhone 17 Pro Max (`00008150-000D793E0208401C`). After Adam confirmed availability, the update was installed in place and launched with `devicectl`.
- The physical iPhone Home was observed through QuickTime's wired screen source after authentication. The first carousel card shows the larger regular grey Pattern, Priority, and Energy pills at the bottom left, with the original crimson symbols, tan fill, red divider, and clear separation from the two-line title. The preview was closed afterward.
- Mac Catalyst Release build passed through `./script/build_and_run.sh --verify`; the script verified the signature, installed `/Applications/SAVY.app`, and launched it. Live Mac inspection confirmed the matching larger carousel details and aligned card edges, including the How-To theme pill.
- Independent native font measurements confirmed that the longest catalog theme fits the 254-point content width, Priority and Energy fit together, and a two-line title plus three 24-point pill rows needs approximately 180.14 points with the existing insets and gaps. The 182-point height accommodates that measured case. The physical first card has two pill rows; three-row fit was checked by measurement.
- Shared implementation files are byte-identical between the iOS and Mac checkouts. `git diff --check` passed. No saved entry or pin changes were made for verification.

Screenshots:

- [Installed physical iPhone Home](device-verification/installed-iphone-home.png)
- [Installed Mac Home](device-verification/installed-mac-home.png)

Built executable SHA-256:

- iPhone: `26dd42d60721b9bd46860d27f1c4bacb743cd66e794d65e7dd35cf6bccc803c3`
- Mac: `3e7850d573c682556b2f0ea79bc758b32e101ea91c543d12885f50161cbb97f9`
