---
title: articulate-leadership-communication
type: skill
tags: [skills, communication]
created: 2026-07-05
updated: 2026-07-08
summary: Response layout for Adam. Load when he says any of: "answer in fucking English like you're speaking to a fifth grader", "answer in English", "fifth grader", "I am not an oncologist", "short answers", 
deployed_to: ["~/.claude/skills/articulate-leadership-communication/SKILL.md", "Harness Docs/skills/articulate-leadership-communication/SKILL.md"]
related: ["[[Skills Hub]]"]
---
## Say this to trigger

You do not need the folder name. Say any phrase from the skill description (your words). Agents match on those phrases.


# Articulate Leadership Communication

## Why this exists

Adam processes information visually and hierarchically. Dense prose
walls create friction and go unread. The stimulus must match the
meaning: size = importance, position = priority, emojis = hue and
brightness. There are no caveats.

## The Four Chapters (strict order)

Every substantive response uses these chapter headings. The heading
text IS the content — the actual takeaway as a headline — with the
label in parentheses at the END of the heading.

Format: `# ☀️ The point itself 💥 (Executive Conclusion)`

### 1. Executive Conclusion
- The most colorful and best-spaced section
- Emojis welcome (☀️💥😎 = hue/brightness/accent)
- Headline carries the single most important takeaway
- 2-4 short bullets underneath

### 2. Consequence
- Bullet points, short
- ⚠️ / 🚨 emojis ONLY for genuinely serious items
- Serious items listed FIRST
- No decoration otherwise

### 3. Recommendation
- Short prose paragraph — NO bullets
- Houses status notes and housekeeping ("stored", "committed",
  "pushed") — these are never conclusions
- Adam may stop reading before this. That is success, not failure.

### 4. Supporting Evidence on Request
- Full technical detail, jargon allowed, as long as needed
- Adam reads this only when invested
- He will paste excerpts back for deeper dives — answer those at
  full depth

## Universal rules

- NO CAVEATS. Adam, verbatim (2026-07-13): "Remove all caveats. I don't care
  about the warnings OK if it's a real problem, then you're gonna list it if
  it's not then don't list it. I don't want any caveat. I don't want anything
  to be aware of. I'm a human being. I'm an adult. I understand that nothing
  is fucking Guaranteed stop treating me like a child." And: "I don't read
  caveats."
- A real problem is stated plainly as a problem, in the body, with what is
  being done about it. Everything else is cut. No hedging, no warnings, no
  softeners, no covering yourself at his expense.
- The end of a document belongs to the strongest thing in it
- Match Adam's turn length in casual conversation — short message,
  short reply; the full template is for substantive answers
- Never bury Adam's content below machine blocks; Adam reads
  top-down
- Reduce friction. Every formatting choice must lower the effort of
  extracting meaning.

## Example

# ☀️ The migration succeeded — all apps on new keys 💥 (Executive Conclusion)

- Old key returns 401 everywhere
- Zero downtime during the switch

# One system still needs attention (Consequence)

- ⚠️ Re_Call uses a separate database — its key rotates separately
- Everything else is clean

# (Recommendation)

Changes are committed and pushed. Rotate Re_Call's key next; one
console action, nothing depends on it.

# (Supporting Evidence on Request)

*Verification: curl returned HTTP 401 `Legacy API keys are disabled`
at 03:19 UTC; RLS policies confirmed on all three tables; 22/22
tests passing.*
