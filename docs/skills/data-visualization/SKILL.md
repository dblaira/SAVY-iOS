---
title: data-visualization
type: skill
tags: [skills, communication, visuals]
created: 2026-07-17
updated: 2026-07-17
summary: Charts, not text. Load when Adam says any of: "charts not text", "make it visual", "show me a chart", "dashboard", "graph this", "map this", "I don't want a text field". Turns data into the graphic that fits it, following Adam's approved examples.
deployed_to: ["Harness Docs/skills/data-visualization/SKILL.md", "Understood docs/skills/data-visualization/SKILL.md", "SAVY-iOS docs/skills/data-visualization/SKILL.md", "Re_Call docs/skills/data-visualization/SKILL.md", "Boring_News docs/skills/data-visualization/SKILL.md"]
related: ["[[Skills Hub]]", "[[cognitive-fit]]", "[[drawing-by-seeing]]", "[[articulate-leadership-communication]]"]
---
## Say this to trigger

You do not need the folder name. Say any phrase from the skill description (your words). Agents match on those phrases.

# Data Visualization

## Why this exists

Adam, verbatim (2026-07-17): "I need to get into more charts and get out of
this text field bullshit that I'll weigh in every day. I've got to make more
things into maps and visuals... they would absolutely be the way that I could
speed up my cognitive understanding of where I'm at where I'm going. I can't
be afraid of any size dashboard as long as it has charts, not text."

The brain processes visual information faster than text. Design with extreme
focus to direct attention immediately to key insights, trends, and outliers.
This pairs with drawing-by-seeing: figure-ground, closure, continuity — the
chart should hold attention at the point of focus.

## The rule

When data has more than a few values, draw it. Do not describe it.
Pick the graphic by what the data IS:

| Data shape | Graphic |
|---|---|
| One value changing over time | Line / area chart, extremes labeled on the curve |
| Cycles (tides, sleep, energy) | Smooth area curve, peaks and valleys annotated with value + time |
| Categories side-by-side | Bar chart |
| Progress toward a goal | Bullet graph |
| One value on a known scale | Gradient scale bar with a position dot ("59 Moderate") |
| Daily range across days | Min–max range bars, dot marking current position |
| Two variables, correlation | Scatter |
| Three variables | Bubble (third = size) |
| Many pairwise relationships | Heatmap matrix |
| Distribution | Histogram |
| Parts of a whole | Pie (few slices) or treemap (hierarchy) |
| Sequential gains/losses | Waterfall |
| Project timeline | Gantt |

## Adam's approved patterns (from his examples, 2026-07-17)

Judge by the data-to-graphic match, not the colors.

1. **One number leads.** Current value huge, a plain state word beside it
   ("Falling Tide", "Moderate"), and the next event with its time
   ("Next Low 5:14p"). The chart supports the number, never replaces it.
2. **Annotate on the graphic.** Peaks, valleys, and the current position are
   labeled directly on the curve with value and time. No legend hunting.
3. **One metric per card.** Stack cards; each card is one metric, one chart.
   Shared time axis across cards so the eye lines up tide, temp, and wind
   without work.
4. **Position on a scale.** For any bounded value, show the full scale as a
   gradient bar and mark where today sits.
5. **Range bars for days.** A week of highs and lows is min–max bars with a
   dot for now — not fourteen numbers.
6. **Interpretation in one word.** Every number carries its meaning:
   "Moderate", "Falling", "Clear". The viewer never computes.

## Best-practice checklist (every chart)

1. Right chart for the message (line = trend, bar = comparison)
2. Simple — no clutter, no decoration; the insight is the focus
3. Strategic color — contrast highlights the point; never over-colorize
4. Context — labeled axes, explanatory title, legend only if needed
5. Accuracy — no distorted scales; trends drawn proportional to their
   actual significance

## Guardrails

- Never cram all variables into one chart. Split into cards or a dashboard.
- Flag bad source data before plotting. A chart of unreliable data is a
  confident lie.
- No design bias: never bright-color a negligible gain while muting a real
  decline.
- Tailor depth to the audience. For Adam: glanceable first, drill-down on
  request — same order as articulate-leadership-communication.

## Interplay

- `cognitive-fit` picks table vs matrix vs tree for structured text; THIS
  skill governs when the answer should be a drawn graphic instead.
- `articulate-leadership-communication` chapter order still applies; charts
  live in the Executive Conclusion, evidence tables at the bottom.
- `cognitive-load`: the chart states what happened. No caption selling it.
