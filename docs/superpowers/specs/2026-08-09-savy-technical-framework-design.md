# SAVY Technical Framework Design

**Date:** 2026-08-09

**Approved design source:** the user request in this session. This document records that request against the current SAVY and CowboyAI codebase so implementation stays inside the stated boundaries.

## Goal

Keep the existing SAVY capture surface and Adam's exact three delegation fields, while adding the nonvisual technical foundation behind that form:

- save locally first and never wait for the network
- preserve a migration-safe entry model where `Clear Sign of Success` and `Compound` can both be true independently
- generate and store a deterministic agent-ready prompt from Adam's exact three fields plus metadata
- enqueue a candidate-only CowboyAI outbox after every save, with retries and receipts
- expose query services for recent `Clear Sign of Success` / `Compound` entries and pinned homepage entries

## Hard Constraints

- No redesign of the interface
- Do not change the three delegation fields
- Do not invent an `Unsorted` entry kind
- Do not invent a new visual capture flow
- Preserve both clean repositories and all existing data
- Candidate export must preserve Adam's exact words and must never promote authority
- Use the current Authority Hub contract where valid
- Only add the smallest CowboyAI candidate-intake contract if the current backend lacks a safe candidate intake

## Current Code Reality

### SAVY iOS

- The shared entry UI already lives in `SAVY/ReminderFormView.swift`
- Adam's three exact prompts already exist there:
  - `What do I want?`
  - `When I am...I like to`
  - `Done looks like...`
- `ReminderStore` is already local-first for reminders:
  - write to on-device JSON immediately
  - mark unsynced rows
  - retry pending sync on bootstrap
- The current model cannot represent `Clear Sign of Success` and `Compound` independently because `Reminder.context` is a single `SuccessStep`
- The current save path writes a Harness delegation file and syncs the reminder, but it does not create a durable candidate outbox, deterministic prompt artifact, or receipt trail
- The homepage feed already reads from `ReminderStore.pinnedFeed`

### CowboyAI

- SAVY already talks to the Authority Hub for reasoning through:
  - `POST /v1/hub/conversations`
  - `POST /v1/hub/decide`
- That path is reasoning-oriented, not an explicit safe candidate-intake contract for SAVY capture export
- CowboyAI already distinguishes candidate review from accepted authority and has durable receipt/ledger concepts

## Recommended Design

### 1. Separate the capture authority model from the reminder UI model

Keep `Reminder` as the UI-facing editing surface, but add a durable capture record alongside it.

The new capture record stores:

- stable capture ID
- source reminder ID
- Adam's exact three fields
- selected metadata copied from the reminder
- independent booleans for:
  - `isClearSignOfSuccess`
  - `isCompound`
- deterministic prompt text
- save timestamp / update timestamp
- outbox state
- last receipt
- retry bookkeeping

This avoids changing the current form or the visible reminder workflow while solving the migration problem cleanly.

### 2. Generate the prompt at save time and persist it with the capture

Prompt generation must be deterministic and local:

- same input words + metadata => same prompt text
- exact three authored fields remain verbatim inside the prompt
- metadata is appended in a fixed order
- the generated prompt is stored with the capture, not rebuilt ad hoc for later retries

This gives the outbox a stable payload and prevents later interpretation drift.

### 3. Add a separate local outbox with receipts and retries

Saving a reminder should perform three local actions immediately:

1. persist the reminder cache
2. persist/update the technical capture record
3. append/update the CowboyAI candidate outbox item

Network submission becomes a background concern owned by the outbox sync service.

The outbox item stores:

- the saved prompt payload
- candidate-only contract fields
- delivery attempt count
- next retry time
- last error
- last receipt / accepted response body

This keeps capture durable even when the network or Hub is unavailable.

### 4. Keep query services native and local-first

Expose query helpers from the SAVY store/service layer for:

- recent entries where `isClearSignOfSuccess == true`
- recent entries where `isCompound == true`
- recent entries where either is true
- pinned homepage entries derived from the reminder store

The homepage keeps its current visual behavior. The new query services exist so later native surfaces can consume the framework without scraping the raw store.

### 5. Keep CowboyAI intake explicitly candidate-only

If a safe intake contract is missing, add the smallest explicit endpoint on a separate CowboyAI branch that:

- accepts SAVY capture candidate payloads
- records exact words and metadata as candidate-only
- returns a receipt
- performs no promotion
- does not write to accepted authority

This endpoint should be narrower than the reasoning API and safer than reusing an authority write path.

## Data Flow

1. User saves the existing reminder form
2. `ReminderStore` persists the reminder locally
3. A technical-framework service derives a capture record from the saved reminder
4. The service generates the deterministic prompt from exact words + metadata
5. The capture record and outbox item are persisted locally
6. Background sync attempts candidate submission
7. The result is stored as a receipt on the outbox item
8. Retries continue until a terminal success receipt or a later edit supersedes the payload

## Error Handling

- Saving must succeed without network availability
- If candidate submission fails, preserve the capture and outbox row unchanged except for retry metadata
- If the reminder is edited later, supersede the older outbox payload with the newer prompt for the same capture
- If the backend contract is unavailable, keep the item pending rather than discarding it

## Testing

Focused unit coverage should prove:

- dual booleans allow both `Clear Sign of Success` and `Compound`
- prompt generation preserves exact words and fixed metadata ordering
- save path creates reminder + capture + outbox locally
- retry bookkeeping advances deterministically
- query services return the expected recent/pinned subsets
- candidate intake payload stays candidate-only and never implies authority promotion

## Out of Scope

- redesigning the form
- changing the three delegation prompts
- new entry kinds
- new tabs or visual capture destinations
- RDF authority changes for Belief Library / Pathway
- physical iPhone validation in this session
