# Navy page headers — September 23, 2026

Adam requested the same navy as the approved mountain homepage on every remaining lighter-blue header. He confirmed the cream-and-tan Face ID screen already matches what he wants and asked that work not interrupt his phone.

## Implementation

`SavyTheme.pageBackground` aliases the existing `deepNavy` (`#08172D`). All former Lapis header, toolbar, overscroll, root fallback, and above-navigation areas use that shared token. Other Lapis canvases (password authentication, Story form, Personal Authority) also resolve to navy. White content, colored cards, tan bottom navigation, and existing dividers are unchanged. No authentication file, behavior, credentials, or Face ID layout was edited.

## Verification and delivery

- Generic iOS Debug build succeeded; log: `/tmp/savy-navy-headers-device-build.log`.
- Native iPhone 17 Pro Max simulator, iOS 26.5, using existing isolated test stores.
- Visually inspected the eight unmodified native window captures in `simulator-verification/`. Each shows a continuous navy header and exposed upper backdrop during a held pull. Home retains its mountain body and crimson divider; the other main pages retain white bodies.
- Each adjacent JSON records a genuinely negative scroll offset while the screenshot was captured, rather than a screenshot taken only after the scroll springs back.
- The existing eight-case UI suite had five passes and three failures: Actions, Connection, and Reminders could not find the invisible accessibility capture receipt. Their fresh PNGs and offset metadata nevertheless exist and were directly inspected. The receipt lookup failures are not reported as passing tests. Parent accessibility-identifier propagation is a suspected cause; no unrelated test-harness repair is included.
- Test result bundle: `/tmp/savy-navy-headers-simulator.xcresult`; log: `/tmp/savy-navy-headers-simulator.log`.
- QuickTime preview and iPhone Mirroring are closed. No installation, launch, or UI automation on Adam's physical phone was performed after his request to keep it free. Physical installation and on-device verification remain pending phone availability.

## Captured pages

| Page | Screenshot |
| --- | --- |
| Home | [Held pull](simulator-verification/home.png) |
| Actions | [Held pull](simulator-verification/actions.png) |
| Reminders | [Held pull](simulator-verification/reminders.png) |
| Calendar | [Held pull](simulator-verification/calendar.png) |
| Connection | [Held pull](simulator-verification/connection.png) |
| Social Media Posts | [Held pull](simulator-verification/news-channel.png) |
| Adam's Ontology | [Held pull](simulator-verification/ontology.png) |
| Field Essays | [Held pull](simulator-verification/field-essays.png) |
