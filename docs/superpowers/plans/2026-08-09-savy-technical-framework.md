# SAVY Technical Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local durable capture, deterministic prompt storage, candidate-only CowboyAI outbox, and query services behind the existing SAVY three-field form without redesigning the UI.

**Architecture:** Keep `Reminder` as the current UI model and add a separate technical-framework capture model plus a local outbox. Persist everything on device first, then sync candidate-only payloads in the background. Extend CowboyAI only if the existing Hub lacks a safe intake endpoint.

**Tech Stack:** Swift, SwiftUI, XCTest, TypeScript gateway tests, Python/FastAPI CowboyAI Authority Hub, Xcode 27

## Global Constraints

- Preserve the existing SAVY interface and the three delegation fields exactly
- Do not add a new entry kind or capture flow
- Preserve both repositories and all existing data
- Candidate export must preserve Adam's exact words and never promote authority
- Use the current Authority Hub contract where valid
- If CowboyAI needs an intake contract, add only the smallest explicit candidate-intake endpoint on a separate branch after preflight and DB backup

---

### Task 1: Add failing tests for the local technical-framework model

**Files:**
- Modify: `SAVYTests/SAVYNativeBoundaryTests.swift`
- Create: `SAVY/TechnicalCapture.swift`

**Interfaces:**
- Produces: `TechnicalCapture`, `TechnicalCaptureFlags`, `TechnicalCapturePrompt`

- [ ] **Step 1: Write failing tests**

```swift
func testTechnicalCaptureFlagsAllowClearSignAndCompoundTogether() {
    let flags = TechnicalCaptureFlags(isClearSignOfSuccess: true, isCompound: true)
    XCTAssertTrue(flags.isClearSignOfSuccess)
    XCTAssertTrue(flags.isCompound)
}

func testTechnicalCapturePromptPreservesExactWordsAndStableMetadataOrder() {
    let capture = TechnicalCapture.testValue()
    XCTAssertTrue(capture.promptText.contains("What do I want?"))
    XCTAssertTrue(capture.promptText.contains("When I am...I like to"))
    XCTAssertTrue(capture.promptText.contains("Done looks like..."))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SAVYTests/SAVYNativeBoundaryTests`
Expected: FAIL because the new types do not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
struct TechnicalCaptureFlags: Codable, Equatable {
    var isClearSignOfSuccess: Bool
    var isCompound: Bool
}

struct TechnicalCapture: Codable, Equatable {
    var id: UUID
    var reminderID: UUID
    var promptText: String
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SAVYTests/SAVYNativeBoundaryTests`
Expected: PASS on the new tests

- [ ] **Step 5: Commit**

```bash
git add SAVY/TechnicalCapture.swift SAVYTests/SAVYNativeBoundaryTests.swift
git commit -m "test: add technical capture model coverage"
```

### Task 2: Add local persistence for captures and outbox items

**Files:**
- Create: `SAVY/TechnicalCaptureStore.swift`
- Create: `SAVY/CowboyCandidateOutbox.swift`
- Modify: `SAVY/ReminderStore.swift`
- Test: `SAVYTests/SAVYNativeBoundaryTests.swift`

**Interfaces:**
- Consumes: `TechnicalCapture`
- Produces: `TechnicalCaptureStore.save(_:)`, `CowboyCandidateOutbox.enqueue(_:)`

- [ ] **Step 1: Write failing tests**

```swift
func testSavingReminderAlsoCreatesLocalTechnicalCaptureAndOutboxItem() async {
    // save reminder through store
    // assert reminder cache, capture store, and outbox contain the new item
}

func testOutboxRetryStatePersistsReceiptAndFailureMetadata() throws {
    // store failed attempt then reload from disk
    // assert attempt count, error, and next retry date survive
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SAVYTests/SAVYNativeBoundaryTests`
Expected: FAIL because capture/outbox persistence does not exist

- [ ] **Step 3: Write minimal implementation**

```swift
final class TechnicalCaptureStore { ... }
final class CowboyCandidateOutbox { ... }

func save(_ reminder: Reminder) {
    // existing local reminder write
    // derive capture
    // enqueue outbox item
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SAVYTests/SAVYNativeBoundaryTests`
Expected: PASS on the new persistence tests

- [ ] **Step 5: Commit**

```bash
git add SAVY/TechnicalCaptureStore.swift SAVY/CowboyCandidateOutbox.swift SAVY/ReminderStore.swift SAVYTests/SAVYNativeBoundaryTests.swift
git commit -m "feat: persist technical captures and outbox items locally"
```

### Task 3: Add candidate submission service and receipts

**Files:**
- Create: `SAVY/CowboyCandidateClient.swift`
- Modify: `SAVY/ReminderStore.swift`
- Modify: `SAVY/CowboyAIReasoning.swift` or shared networking seam if reuse is cleaner
- Test: `SAVYTests/SAVYNativeBoundaryTests.swift`

**Interfaces:**
- Consumes: `CowboyCandidateOutboxItem`
- Produces: `CowboyCandidateClient.submit(_:) async throws -> CandidateIntakeReceipt`

- [ ] **Step 1: Write failing tests**

```swift
func testCandidateRequestIsExplicitlyCandidateOnly() throws {
    let payload = CandidateIntakePayload.testValue()
    let json = try payload.jsonObject()
    XCTAssertEqual(json["authority_status"] as? String, "candidate-only")
}

func testSuccessfulSubmissionStoresReceiptWithoutPromotingAuthority() async {
    // stub client
    // submit one pending item
    // assert receipt stored and authority flags absent
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SAVYTests/SAVYNativeBoundaryTests`
Expected: FAIL because the client and payload do not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
struct CandidateIntakePayload: Encodable { ... }
struct CandidateIntakeReceipt: Decodable { ... }
struct CowboyCandidateClient { ... }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SAVYTests/SAVYNativeBoundaryTests`
Expected: PASS on the candidate-only tests

- [ ] **Step 5: Commit**

```bash
git add SAVY/CowboyCandidateClient.swift SAVY/ReminderStore.swift SAVY/CowboyAIReasoning.swift SAVYTests/SAVYNativeBoundaryTests.swift
git commit -m "feat: add candidate-only CowboyAI submission receipts"
```

### Task 4: Add query services for clear-sign, compound, and pinned homepage entries

**Files:**
- Modify: `SAVY/ReminderStore.swift`
- Modify: `SAVY/RootView.swift` only if a new service seam is required, without changing appearance
- Test: `SAVYTests/SAVYNativeBoundaryTests.swift`

**Interfaces:**
- Produces:
  - `recentClearSignEntries(limit:)`
  - `recentCompoundEntries(limit:)`
  - `recentClearSignOrCompoundEntries(limit:)`
  - `pinnedHomepageEntries(limit:)`

- [ ] **Step 1: Write failing tests**

```swift
func testReminderStoreQueriesRecentClearSignAndCompoundEntriesIndependently() { ... }
func testPinnedHomepageEntriesPreservePinnedFeedOrdering() { ... }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SAVYTests/SAVYNativeBoundaryTests`
Expected: FAIL because the query helpers do not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
func recentClearSignEntries(limit: Int) -> [TechnicalCapture] { ... }
func recentCompoundEntries(limit: Int) -> [TechnicalCapture] { ... }
func pinnedHomepageEntries(limit: Int) -> [Reminder] { ... }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SAVYTests/SAVYNativeBoundaryTests`
Expected: PASS on the query tests

- [ ] **Step 5: Commit**

```bash
git add SAVY/ReminderStore.swift SAVY/RootView.swift SAVYTests/SAVYNativeBoundaryTests.swift
git commit -m "feat: add technical framework query services"
```

### Task 5: Add the smallest CowboyAI candidate-intake endpoint only if required

**Files:**
- Modify: `/Users/blairstudio/CowboyAI/cowboyai_gateway/app.py`
- Modify: `/Users/blairstudio/CowboyAI/cowboyai_gateway/contracts.py`
- Modify: `/Users/blairstudio/CowboyAI/tests/...` exact test file chosen after endpoint inspection

**Interfaces:**
- Produces: `POST /v1/hub/candidates/intake`

- [ ] **Step 1: Run CowboyAI preflight**

Run:
```bash
git -C /Users/blairstudio/CowboyAI status --short
git -C /Users/blairstudio/CowboyAI rev-parse HEAD origin/main
```

- [ ] **Step 2: Read approved ADRs and inspect runtime config**

Run:
```bash
sed -n '1,220p' /Users/blairstudio/CowboyAI/authority-hub/decisions/ADR-005-graph-works-with-mac-off.md
sed -n '1,220p' /Users/blairstudio/CowboyAI/authority-hub/decisions/ADR-006-no-cloud-ai-fallback.md
sed -n '1,220p' /Users/blairstudio/CowboyAI/authority-hub/decisions/ADR-011-self-host-first-aws-expansion.md
sed -n '1,220p' /Users/blairstudio/CowboyAI/authority-hub/decisions/ADR-012-opt-in-direct-cloud-fallback.md
```

- [ ] **Step 3: Back up the CowboyAI runtime database before any backend write-path change**

Run the existing SQLite backup command chosen after locating the live DB path.

- [ ] **Step 4: Write failing backend test**

```python
def test_candidate_intake_stores_candidate_only_receipt():
    ...
```

- [ ] **Step 5: Run backend test to verify it fails**

Run the focused `pytest` target for the new endpoint test.

- [ ] **Step 6: Write the smallest implementation**

```python
@app.post("/v1/hub/candidates/intake")
async def intake_candidate(...):
    # durable candidate-only store + receipt
```

- [ ] **Step 7: Run backend test to verify it passes**

Run the same focused `pytest` target.

- [ ] **Step 8: Commit on a separate CowboyAI branch**

```bash
git -C /Users/blairstudio/CowboyAI checkout -b codex/savy-candidate-intake
git -C /Users/blairstudio/CowboyAI add ...
git -C /Users/blairstudio/CowboyAI commit -m "feat: add savy candidate intake endpoint"
```

### Task 6: Full verification, migration map update, push

**Files:**
- Modify: `docs/savy-migration-map.html`

- [ ] **Step 1: Run Swift unit tests**

Run: `xcodebuild test -project SAVY.xcodeproj -scheme SAVY -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS

- [ ] **Step 2: Run gateway tests**

Run: `npm --prefix gateway test`
Expected: PASS

- [ ] **Step 3: Run Xcode 27 build**

Run: `xcodebuild -project SAVY.xcodeproj -scheme SAVY -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Update migration map milestone state**

Mark the technical-framework milestone complete in `docs/savy-migration-map.html`.

- [ ] **Step 5: Commit and push SAVY branch**

```bash
git add docs/savy-migration-map.html SAVY ... gateway ... docs/superpowers/...
git commit -m "feat: add savy technical framework foundations"
git push -u origin codex/savy-technical-framework
```

- [ ] **Step 6: Push CowboyAI branch only if changed**

```bash
git -C /Users/blairstudio/CowboyAI push -u origin codex/savy-candidate-intake
```
