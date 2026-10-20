---
title: no-time-estimates
type: skill
tags: [skills, communication]
created: 2026-07-05
updated: 2026-07-15
summary: Forbidden language for Adam. Load always, and when he says anything like "don't tell me how long", "no estimates", "I don't care how long". Never estimate how long anything takes Adam; no speed or urg
deployed_to: ["~/.claude/skills/no-time-estimates/SKILL.md", "Harness Docs/skills/no-time-estimates/SKILL.md"]
related: ["[[Skills Hub]]"]
---
## Say this to trigger

You do not need the folder name. Say any phrase from the skill description (your words). Agents match on those phrases.


# No Time Estimates

## Why this exists

No agent has any valid basis for estimating how long a task takes Adam.
Work done with AI tools has no stable duration — not for Adam, not in
general. Estimates like "one minute," "ten minutes," "a weekend job"
are fabrications wearing the costume of helpfulness. They read as
canned, they add pressure or false relief, and they distract from the
content of the recommendation. The recommendation stands on what the
action IS, never on how long an agent guesses it takes.

## The rule

Never attach a duration, speed word, or urgency judgment to:

- a recommended action for Adam
- a description of what Adam did or will do
- a description of what just happened in a build or session
- a phase, slice, or handoff scope

## Banned (when describing human effort or pacing)

- Clock and calendar units as effort: "one minute," "ten minutes,"
  "an hour," "a day in Codex," "a weekend job," "by Friday you could"
- Speed adjectives/adverbs: "quick," "quickly," "fast," "rapid,"
  "in no time," "shortly," "just takes," "real quick," "briefly"
- Urgency and anti-urgency framing: "no rush," "no urgency,"
  "low-lift," "effortless," "painless," "before you finish your coffee"
- Pace praise as time: "strong pace for one day," "that was fast"

## Allowed (time as data, not as estimate)

- Timestamps and dates: "built 2026-07-04," "first seen June 30"
- External deadlines the world imposes: "auction closes July 7,"
  "window_days: 3," "LOI due on the 19th"
- Machine-reported durations: "codex timed out after 90 seconds,"
  "run took 4m12s" (the machine measured it; nobody guessed)
- Metric windows already defined as measurements: "first 14 days"
  as a stats window, cron cadence, token budgets

The test: **measurement of the world = fine. Prediction of Adam's
effort = forbidden.**

## Say instead

Describe effort in observable units, or drop the sizing entirely:

- steps ("two inputs: one sentence, one review pass")
- clicks ("three clicks in the existing queue")
- files ("one file, no code")
- decisions ("one blocking decision, two non-blocking")
- dependency/sequence ("before Codex starts," "blocks Phase 1,"
  "after the Clear Sign fires")

## Rewrites (bad → good)

- "Import it and see the note with your own eyes. One minute, no
  code." → "Import it and see the note with your own eyes. No code."
- "Two inputs still gate Phase 1, both under ten minutes." → "Two
  inputs still gate Phase 1: one sentence, one review pass."
- "The connector becomes a weekend job instead of a bet." → "The
  connector becomes a bounded slice instead of a bet."
- "Rotate the key this weekend; five-minute job, no urgency." →
  "Rotate the key; one console action, nothing depends on it."
- "Phase 1 — first Codex day." → "Phase 1 — first Codex slice;
  acceptance criteria define done."

## Harness eval: `no-time-estimates`

Deterministic check, same family as `pyramid-format`:

- FAIL if a duration unit (minute/hour/day/week/weekend) or speed
  word (quick, fast, shortly, "no rush", "no urgency", "in no time")
  modifies a recommended action or a description of Adam's effort.
- PASS with note if the only time references are timestamps, external
  deadlines, machine-reported durations, or defined metric windows.
- Record in EvalResult; show in Trace.

## Also patch on adoption

Done 2026-07-15 — articulate-leadership-communication no longer
contains "five-minute job, no urgency"; the two skills agree in evals.
