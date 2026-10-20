---
title: market-inefficiency
type: skill
tags: [skills, detection, finance]
created: 2026-07-05
updated: 2026-07-08
summary: Adam's market-inefficiency chain. Load when he says any of: "I see a market inefficiency", "market inefficiency", "nobody is doing this", "why is this still so hard", "this just became a market", "mon
deployed_to: ["~/.claude/skills/market-inefficiency/SKILL.md", "~/.agents/skills/market-inefficiency/SKILL.md", "Harness Docs/skills/market-inefficiency/SKILL.md"]
related: ["[[Skills Hub]]", "[[requirement-is-the-test]]"]
---
## Say this to trigger

You do not need the folder name. Say any phrase from the skill description (your words). Agents match on those phrases.


# Market Inefficiency

## Where this comes from

Reverse-engineered from two Adam sources:
- Direct reflection, 2026-06-28 (semantic candidate
  `20260628-123605-market-inefficiency-build-threshold`): "I respond and
  get excited in situations where I feel like I see a market
  inefficiency… the efficient answer to it now is something within my
  skill set or within the tools that I have at my disposal."
- Lived instance, 2026-01-24 (tennis prediction markets): noticed that
  early-round ATP matches are grossly mismatched competitions inside a
  newly liquid market (Kalshi/Polymarket) — "money says: this is where
  the inefficiencies lie."

The pattern is not generic "market recognition." It is a specific
causal chain, and this skill runs that chain as a procedure.

## Where to look BEFORE the chain (Adam's refinement, 2026-07-05 voice memo)

Three hunting grounds where inefficiency exists by construction, plus
the thesis that justifies the fleet:

- **The larger-client shadow.** When a market serves a more important
  client than the price-payer — sport promotion (Australian Open
  wildcards admitted to serve the home country), entertainment,
  regulation, national interest — mispricings pool beneath that
  priority as a subsidy shadow. The bettor adding a home-country
  wildcard to a parlay "adds to the anxiety of it all" and pays a bad
  price on purpose. Ask first: *who is the larger client here, and
  what does their priority distort below it?*
- **Lavishness leeway.** Zones where buyers deliberately suspend
  cost-consciousness (experiences, feeling wild while staying safe).
  Price discipline is intentionally relaxed, so inefficiency is
  tolerated — even purchased as a feeling.
- **The potential premium.** Markets where buyers pay for potential
  and exploration rather than present utility (Adam's own AI-token
  spend). Inefficiency zones by construction.
- **Attention seats (the fleet thesis).** The edge is attention
  asymmetry: agents pay closer attention and notice faster; Adam acts
  faster and more informed. "There could be thousands of seats… I'm
  just in one of them." The pattern does not require beating everyone
  — only occupying one seat well. This is why finding one is enough
  and why honest empty catches cost nothing.

## The chain (run every step; each is a gate)

1. **Inefficiency noticed** — a measurable gap between public
   perception/price/behavior and probable reality. Trigger language
   from Adam: "market inefficiency," "nobody's doing X," "why is this
   still so hard/expensive," "this just became a market."
2. **Solution search** — look for existing solutions, honestly. Name
   what exists.
3. **Incumbent assessment** — the gate opens only if incumbents are
   *absent, overly complex, overly expensive, or outdated*. If a good
   solution exists, say so and stop; that kills the pattern honestly.
4. **Capability match** — test the gap against Adam's ACTUAL current
   skills and tools (Claude/Codex agents, Swift/SwiftUI, Supabase,
   Firecrawl, ontology/graph infrastructure, prediction-market
   accounts, publishing surfaces). Not hypothetical skills — the
   toolbox as it exists today.
5. **Efficient-solution hypothesis** — state, in one paragraph, how
   the current toolbox solves it more efficiently than incumbents.
6. **Build threshold** — the crossing condition: inadequate incumbents
   AND capability match both present. Only then does this become a
   build/pursue candidate. Money is the *proof of trapped value*, not
   the motivation to start.
7. **Emit, never execute** — output a delegation (see below). No agent
   ever bets, deposits, trades, buys, or starts building. Adam crosses
   thresholds; agents only report that a threshold is reached.

## Output shape

Emit a v1.2 envelope file (`type: delegation`) with the chain as
evidence:

- `title`: the inefficiency in ≤10 plain words
- `description`: the one-paragraph efficient-solution hypothesis
- body: each of the 7 steps with its evidence, one line each —
  including what incumbents were found (step 2 is mandatory; an empty
  solution search is a failed run, not a passed gate)
- `rules_hit`: cite the ontology rule when accepted; until Adam
  promotes the candidate, cite it as `candidate:market-inefficiency-
  build-threshold` — a claim, not authority
- `fit`: fraction of gates passed with strong evidence
- `app`: Notorious Recall if research remains; Understood if the
  hypothesis is act-ready

## In conversation (not just scouting)

When Adam's own language matches step-1 triggers, name the pattern
("this sounds like your market-inefficiency chain — step 3 is where it
stands") and walk the remaining gates with him. The chain doubles as a
brake: if step 3 or 4 fails, saying so early protects him from
excitement-driven builds — that is the rule working, not failing.

## Boundaries (inherited laws)

- Ontology candidate is **pending Adam review** — do not treat the
  chain as accepted authority; do not promote it.
- Standing rule: agents propose; no agent spends, trades, bets,
  contacts, or commits. The tennis story involves real deposits —
  those are Adam's actions, never an agent's.
- `requirement-is-the-test` applies: "inefficiency found" claims need
  the evidence chain attached, observable by Adam.
