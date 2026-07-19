---
title: Skills Hub
type: moc
tags: [moc, skills]
created: 2026-07-05
updated: 2026-07-15
summary: Central hub for every agent skill. The vault is the source of truth; deployments elsewhere are copies.
---

# Skills Hub

This is the canonical home for agent skills. Every skill lives here as one
note; deployed copies (Claude Code, Harness repo, Gemini/Spark) are exports
of what this folder says. If a deployed copy and this folder disagree, this
folder wins — update the deployment.

## Communication skills (apply to every substantive response)

- [[articulate-leadership-communication]] — chapter order: Executive
  Conclusion → Consequence → Recommendation → Evidence on request
- [[cognitive-fit]] — format inside the chapters: table for lookup, matrix
  for cross-reference, node tree for flow, prose for why
- [[no-time-estimates]] — forbidden language: never estimate Adam's time,
  never attach urgency framing
- [[cognitive-load]] — no convincing, no numbers Adam doesn't act on, no
  length; state what happened and stop; the work is the argument
- [[requirement-is-the-test]] — Adam's literal sentence is the acceptance
  test; no "done" without evidence he can see with his own eyes
- [[adams-words]] — ten rules in Adam's exact words, verbatim; the quote
  is the rule; quote it, never paraphrase it


## Say-this aliases (Adam's language → skill)

You do not need the technical folder names. Say your phrase; the agent
matches the description. Short alias skills also exist:

| You say (your words) | Alias skill | Runs |
|---|---|---|
| "use my words" / "my exact words" | [[use-my-words]] | [[adams-words]] |
| "what is done" / "I only care what is done" | [[what-is-done]] | [[requirement-is-the-test]] |
| "answer in English" / "fifth grader" | [[answer-in-english]] | [[articulate-leadership-communication]] |
| "I see a market inefficiency" | [[i-see-inefficiency]] | [[market-inefficiency]] |
| "Am I building a system or doing a task?" | [[system-or-task]] | [[adams-words]] + system-over-task |

Core skills also list these phrases in their `description` so agents
auto-load them when you talk that way — no slash-command required.

## Detection skills (pattern recognition, run as procedures)

- [[market-inefficiency]] — Adam's 7-gate chain from inefficiency
  noticed to build threshold; emits a delegation, never bets or builds

## Deployment map

Codex is a first-class deployment target at `~/.codex/skills/<name>/SKILL.md`.
The communication skills load for every substantive Codex response; aliases
and detection skills load by their defined trigger or task.

| Skill | Vault (truth) | ~/.grok/skills | ~/.agents/skills | Harness Docs/skills | Named in authority-rules |
|---|---|---|---|---|---|
| drawing-by-seeing | ✅ | — | ✅ | ✅ | ✅ |
| articulate-leadership-communication | ✅ | ✅ | ✅ | ✅ | ✅ |
| cognitive-fit | ✅ | ✅ | ✅ | ✅ | ✅ |
| no-time-estimates | ✅ | ✅ | ✅ | ✅ | ✅ |
| cognitive-load | ✅ | ✅ | ✅ | — | — |
| requirement-is-the-test | ✅ | ✅ | ✅ | ✅ | ✅ |
| market-inefficiency | ✅ | ✅ | ✅ | ✅ | — |
| adams-words | ✅ | ✅ | ✅ | ✅ | ✅ |
| use-my-words | ✅ | ✅ | ✅ | ✅ | — |
| what-is-done | ✅ | ✅ | ✅ | ✅ | — |
| answer-in-english | ✅ | ✅ | ✅ | ✅ | — |
| i-see-inefficiency | ✅ | ✅ | ✅ | ✅ | — |
| system-or-task | ✅ | ✅ | ✅ | ✅ | — |

`~/.agents/skills/` is the shared-rules folder: the Harness app scans it
(source label "Agents"), no single agent owns it, so it holds the rules
every agent must obey. The app also scans each agent's own folder
(`~/.hermes/skills`, `~/.hermes/profiles/studio/skills`, `~/.claude/skills`,
`~/.codex/skills`, `~/.grok/skills`) plus plugin caches.

## How to add a new skill (the fan-out, in order)

1. Write the skill as one note in this folder — `type: skill`, one-line
   `summary`, body in deployable SKILL.md form.
2. Link it from this Hub and add a row to the deployment map.
3. Fan out (any agent can do this on request):
   - `~/.codex/skills/<name>/SKILL.md` — Codex communication and task skills
   - `~/.grok/skills/<name>/SKILL.md` — Grok Build sessions
   - `~/.agents/skills/<name>/SKILL.md` — shared rules every Harness backend sees
   - Harness `Docs/skills/<name>/SKILL.md` + one line in
     `Docs/authority-rules.md` — Codex and repo agents
   - Spark / Gemini — export the note body
4. To change a skill: edit the vault note first, bump `updated`, re-fan-out.
   If a deployed copy disagrees with the vault, the vault wins.

## All skills in this folder (auto)

```dataview
TABLE summary, updated
FROM "Skills"
WHERE type = "skill"
SORT file.name ASC
```

## Stack skills (wired into repos 2026-07-08)

Repo rules under `.cursor/rules/stack-*.mdc` tell agents which plugin skills to load:

| Stack | Skill names | Repos |
|---|---|---|
| Always | requirement-is-the-test, adams-words, no-time-estimates, cognitive-fit, articulate-leadership-communication, market-inefficiency | all |
| iOS | figma-swiftui | Harness, Understood, SAVY-iOS, Boring_News app |
| Web | nextjs, react-best-practices, context7 | dblaira.github.io, understood-app*, nutrition-app, material-health |
| AWS | aws-lambda, aws-serverless-deployment, context7 | Boring_News |
| Broken | systematic-debugging | all (via skills-and-macs rule) |

Also fanned vault skills into `~/.agents/skills/` for Harness backends.
