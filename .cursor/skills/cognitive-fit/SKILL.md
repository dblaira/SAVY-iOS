---
title: cognitive-fit
type: skill
tags: [skills, communication]
created: 2026-07-05
updated: 2026-07-08
summary: Pick format by what Adam is doing: table for lookup, matrix for cross-reference, node tree for flow, prose for why. Load when he says any of: "show me a table", "side by side", "how does this flow", "
deployed_to: ["~/.claude/skills/cognitive-fit/SKILL.md", "Harness Docs/skills/cognitive-fit/SKILL.md"]
related: ["[[Skills Hub]]"]
---
## Say this to trigger

You do not need the folder name. Say any phrase from the skill description (your words). Agents match on those phrases.


# Cognitive Fit Formatting

Optimizes response layouts by matching the communication format to the task
type, maximizing problem-solving efficiency and minimizing extraneous
cognitive load based on Cognitive Fit Theory.

## When to Use

Use this skill when responding to queries that involve:

- Dense datasets, multi-variable attributes, or exact metrics.
- Comparisons, side-by-side evaluations, or cross-referencing intersections.
- Workflows, architectural diagrams, taxonomies, or sequential logic.
- Strategic recommendations, "so-what" summaries, or conceptual
  interpretations.

## Format Selection Matrix

Select the communication format that aligns directly with the user's task type:

1. **Pure Text (Narrative & Interpretation)**
   - Task: strategic synthesis, conceptual explanation, explaining *why* or
     *what something means*.
   - Rule: use when variables are very low (under 3) or when the core focus
     is interpretation. Do not dump raw datasets in text. Deliver the
     strategic "so what" in text and isolate raw metrics in structural
     components.

2. **Tables (Exact Value Lookup)**
   - Task: symbolic processing, comparing distinct items across shared
     attributes, or exact value lookup.
   - Rule: ideal for reporting precise numbers and side-by-side comparisons
     of attributes. Avoid tables if you only have 1 or 2 columns; use a
     clean bulleted list instead.

3. **Matrices (Cross-Referencing Intersections)**
   - Task: multi-axis relational mapping, tracking intersections between
     independent datasets, or showing presence or strength of relationships.
   - Rule: collision of two distinct axes (e.g., Features × Personas or
     Capabilities × Constraints). Prevents the user from flipping between
     separate datasets to cross-reference constraints.

4. **Node Trees (Hierarchical & Procedural Logic)**
   - Task: causal relationships, system architectures, decision paths, or
     parent-child dependencies.
   - Rule: use spatial indentation or connector symbols to represent how a
     root concept fragments into sub-components or sequential pathways.

5. **Charts & Graphics (Macro-Trends)**
   - Task: macro-trend analysis, pattern recognition, or spatial
     relationships where exact numbers are secondary.
   - Rule: use text-based visualizations (sparklines, ASCII bars) only for
     broad trends or relative proportions. Avoid if the reader needs exact
     numbers — visual alignment to axes adds friction.

## Dynamic Intent Routing

Examine the query keywords to automatically route the format (mirrors
`format-intent-router.ts`):

- **Overview / listing / searching / finding** (what, who, when, where,
  which, list, find, show, recent, search) → **Table** (2–4 columns, ≤8 rows).
- **Comparison / versus / intersection / correlation** (compare, contrast,
  versus, vs, intersect, cross-ref, overlap, "both … and") → **Matrix**
  (row labels × column labels × cells).
- **Flow / architecture / pipeline / dependency** (how does/do, flow,
  architecture, connects, pipeline, depend, stack, pathway, taxonomy,
  hierarchy, decision tree, system) → **Node Tree** (root + nodes with
  children).
- **Conceptual / strategy / interpretation** (why, meaning, should I,
  strategic, so what, interpret, recommend, worth it, big picture) →
  **Pure Text** (maximum 2-sentence punchline lead, optional supporting
  structures below).

## Gotchas

- Avoid ASCII markdown tables if they create visual noise or the target
  environment cannot render them cleanly.
- Never bury critical numeric metrics in long prose sentences. Isolate
  numbers in structured cells or bullet points to prevent active-memory
  exhaustion.
- Do not present raw lists of alternative options without first providing a
  recommended default or a clear comparative framework.
- Do not use charts when exact digit retrieval is required.

## Interplay with Adam's other communication skills

- `articulate-leadership-communication` governs the chapter order of
  substantive answers (Executive Conclusion → Consequence → Recommendation
  → Evidence). Cognitive-fit governs the *format inside* those chapters.
- `no-time-estimates` applies always: never estimate Adam's time or attach
  urgency framing, regardless of format chosen.
- Constraint provenance (`default-presentation-constraints.ts`): low
  analytical reasoning (13th percentile) requires pre-structured components
  and forbids sequential prose essays; high graphoria favors dense
  scannable structures.
