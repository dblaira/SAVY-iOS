# SAVY mountain homepage — September 23, 2026

## Reference and device evidence

- Source: `docs/design/2026-09-23-mountain-home/approved-home.png` (851 × 1848).
- Final implementation: `docs/design/2026-09-23-mountain-home/device-verification/installed-home.png` (816 × 1766), captured from Adam’s physical iPhone 17 Pro Max through QuickTime’s wired Screen input.
- Same top-of-page Now state, including seven saved posts and 23 connections. Compared both images in one tool input; normalized by viewport proportions, excluding native status-bar chrome. QuickTime displays a 9:41 status clock; this is not mock app content.
- The scrolled state was also observed live: all four destination cards and the opaque source-status card remain readable over the photograph.

## Comparison history

1. Initial installation: the photo scaled with the entire list height, making the summit too large and leaving only its tip visible. Evidence: `device-verification/before-crop.png`. Finding: P2, crop depended on content height.
2. Correction: bind photo scale to viewport height and offset the background as the header scrolls away. Rebuilt, reinstalled, launched, and observed the corrected top and scrolled states. Evidence: `device-verification/installed-home.png`.

## Required fidelity checks

- Typography: existing native Bodoni/Times headings and system metadata retained; visible text remains readable.
- Layout: native 140-point carousel height, card padding, and safe-area/navigation dimensions retained. An 80-point landscape reveal establishes the approved composition. The generated mockup has shorter carousel and lower-navigation regions; native sizes are deliberately retained from Adam’s earlier decisions rather than treating image-generation geometry as exact measurements.
- Colors: deep navy header reaching the status area and both lower bands; thin crimson header divider; tan navigation; opaque white/crimson/tan cards.
- Imagery: exact original photograph bundled, with SHA-256 matching the saved source. Summit visible between carousel and first card; photo remains behind cards while scrolling. No screenshot used as app UI.
- Content: same post count, post references, Connection count and preview text; no synthetic entries added.
- Focused checks: header/divider and white-card perimeter are readable in the full-resolution device capture, so additional crops were unnecessary.

## Validation and remaining scope

- Device-target Xcode build succeeded; installation and launch receipts saved beside the screenshots.
- Independent source review found no issue with background bounds, scrolling coverage, or interaction preservation.
- No pin/delete actions or held-pull test were performed during this visual change. Existing storage and gesture handlers were retained.
- QuickTime preview and iPhone Mirroring were closed after verification. No recording was started.
- Previous Personal Authority QA is preserved under `device-verification/previous-personal-authority-design-qa.md`.

No actionable P0/P1/P2 issue remains for the requested homepage background, navy framing, and red divider.

final result: passed
