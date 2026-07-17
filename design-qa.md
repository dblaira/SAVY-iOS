# Cowboy AI Personal Authority Review — Design QA

## Acceptance surface

- Reference: Adam's SAVY Actions and SAVY home screenshots.
- Implementation: the native Cowboy AI candidate-review screen installed on Adam's iPhone 17 Pro Max.
- Core task: read or listen to one candidate, understand its source and authority state, then choose Yes, Sometimes, or No.

## Visual comparison

- Preserves SAVY's deep navy field, cream reading surface, sand controls, crimson primary action, Bodoni display hierarchy, and oversized editorial typography.
- Uses the supplied retro signal graphic and the existing SAVY cowboy-hat asset instead of invented placeholder graphics.
- Candidate section labels are visible headings with crimson rules; paragraphs and bullets retain distinct hierarchy.
- Candidate, evidence explanation, read-aloud controls, approval actions, and 1-of-709 position are all visible in the native phone flow.
- Qwen3-TTS is visibly labeled as the local natural voice; Apple speech is hidden behind the phone-only fallback shown only when the Mac cannot be reached.

## Functional checks

- The exact 709-candidate JSON payload is bundled in the app.
- Decisions persist locally without promoting candidates into accepted authority.
- Local natural voice supports generation, local caching, listen, pause, continue, and stop.
- Selecting a decision stops speech and advances to the next candidate.
- Previous and Next stop speech before navigation.

## Severity review

- P0: none.
- P1: none.
- P2: none.

final result: passed
