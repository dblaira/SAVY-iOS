# Programming Logic for Your Apps

Curated 3 October 2026

A reading guide to the reasoning inside Cowboyai, NewsCalm, SAVY, and your web apps: what counts as evidence, what the system may do next, and how it knows when something went wrong.

50 recommended readings across eight families, plus one SwiftUI transcript. The selection includes essays, tutorials, standards primers, reference chapters, and research papers; each is labeled.

## How to use this guide

Formal logic gives precise rules for statements, evidence, and inference. Engineering patterns organize decisions, state, and effects; they may use formal ideas without being separate mathematical logics.

Conceptual means start with the explanation. Intermediate expects some code or system vocabulary. Advanced means formalism or dense technical detail; the reading notes point to approachable sections where available.

## A short route through the ideas

Start with these eight, in this order. Read for the decision each piece clarifies; code and mathematical derivations can wait. This reading order is a recommendation, not a project roadmap.

1. [A Crash Course in Predicate Logic](#reading-01): Make an English requirement precise
2. [Domain services vs Application services](#reading-15): Find the actual business decision
3. [Designing with types: Making illegal states unrepresentable](#reading-16): Turn that decision into valid outcomes
4. [You don’t need a library for state machines](#reading-21): Describe the allowed next steps
5. [Natural Logic for Textual Inference](#reading-02): See what a rewrite can accidentally change
6. [Local-first software: You own your data, in spite of the cloud](#reading-24): Think through SAVY’s cross-device behavior
7. [Building effective agents](#reading-29): Decide where the model may choose
8. [The Enterprise Developer from Hell](#reading-42): Turn expectations into useful tests

## Browse by question

1. [Claims and uncertainty](#claims): What exactly follows from what you know?
2. [Rules and explanations](#rules): How did those facts produce this answer?
3. [Models and boundaries](#models): What should be impossible to represent?
4. [State and identity](#state): What can happen next, and what stays the same?
5. [Time and shared data](#time): What happens when two devices disagree?
6. [Workflows and recovery](#workflows): What happens if the job stops halfway through?
7. [Data and permissions](#data): Which records count, and who may change them?
8. [Testing and safe failure](#checks): How would you discover that your rule is wrong?

<a id="claims"></a>

## 1 Claims and uncertainty

What exactly follows from what you know?

Formal logic, causal reasoning, and uncertainty. For Cowboyai, distinguish missing evidence, conflicting evidence, and a justified conclusion; for NewsCalm, identify the words that change a claim’s meaning.

<a id="reading-01"></a>

### 01 A Crash Course in Predicate Logic

[A Crash Course in Predicate Logic](https://www.hillelwayne.com/post/predicate-logic/)

Hillel Wayne · Article / adapted book chapter · Conceptual · Starter route

Logic: Propositional and predicate logic

**What it teaches:** Turns English requirements into predicates, implications, and some/all statements, including why ‘all reviewers approved’ can be true when nobody reviewed anything.

**In your apps:** For Cowboyai, distinguish 'every retrieved source agrees' from 'at least one source supports this'; for NewsCalm, specify exactly which factual claims must survive a rewrite.

**Reading note:** Read the practical example and Quantifiers first. This is the strongest foundations starter.

<a id="reading-02"></a>

### 02 Natural Logic for Textual Inference

[Natural Logic for Textual Inference](https://aclanthology.org/W07-1431/)

Bill MacCartney and Christopher D. Manning · Research paper · Intermediate · Starter route

Logic: Natural-language entailment and monotonicity

**What it teaches:** Shows how small wording changes preserve, weaken, or break an inference, especially around negation and quantifiers, so similarity alone cannot establish a faithful rewrite.

**In your apps:** An especially direct NewsCalm fit: test edits to qualifiers, scope, amounts, negation, and attribution before calling a calmer headline fact-preserving. The paper also states limits, so this supplies test-design principles rather than a complete automatic factuality guarantee.

**Reading note:** Read the opening counterexample and section 2 first. Do not confuse this linguistic use of monotonicity with monotonic database updates.

<a id="reading-03"></a>

### 03 OWL 2 Web Ontology Language Primer (Second Edition)

[OWL 2 Web Ontology Language Primer (Second Edition)](https://www.w3.org/TR/owl-primer/)

W3C OWL Working Group · Explanatory standards primer · Intermediate

Logic: Description logic, ontologies, and open-world reasoning

**What it teaches:** Explains classes, relationships, consistency, and entailment, including why an absent fact can remain potentially true and an ontology restriction is different from an input-validation rule.

**In your apps:** For Cowboyai, keep 'not known to be true' separate from 'known to be false'; distinguish taxonomy inference from enforcing required Postgres fields. An ontology can organize answers without pretending the graph contains all reality.

**Reading note:** Start with sections 2–3, then class disjointness and property restrictions. It is a substantial primer rather than an API reference.

<a id="reading-04"></a>

### 04 Negation as Failure

[Negation as Failure](https://www.doc.ic.ac.uk/~klc/neg.html)

Keith L. Clark · Foundational paper · Advanced

Logic: Default negation and database completion

**What it teaches:** Formalizes a database-oriented meaning of ‘not’ based on failure to prove a query, whose justification depends on the database interpretation rather than establishing unrestricted falsity in the world.

**In your apps:** Before a Cowboyai rule concludes 'no conflict' or 'not connected,' ask whether the searched data is complete enough for absence to count as negation. A failed or incomplete search should not silently become a negative fact.

**Reading note:** The author page links a 29-page scanned PDF. Treat as a foundational deep dive after the OWL primer, not the starting explanation.

<a id="reading-05"></a>

### 05 Making Belnap’s “Useful Four-Valued Logic” Useful

[Making Belnap’s “Useful Four-Valued Logic” Useful](https://cdn.aaai.org/ocs/17599/17599-77711-1-PB.pdf)

Geoff Sutcliffe, Francis Jeffry Pelletier, and Allen P. Hazen · Research paper · Advanced

Logic: Four-valued and paraconsistent logic

**What it teaches:** Distinguishes true, false, both, and neither, showing why conflicting evidence differs from missing evidence and why contradiction need not justify arbitrary conclusions.

**In your apps:** A strong model for Cowboyai and NewsCalm evidence handling: retain disagreement between sources and distinguish it from no evidence. Four evidence states still need provenance and carefully chosen inference rules; they are not numerical confidence scores.

**Reading note:** Read Background and the two information/truth diagrams first; the connective design and evaluation are deeper material.

<a id="reading-06"></a>

### 06 ProbLog: A Probabilistic Prolog and its Application in Link Discovery

[ProbLog: A Probabilistic Prolog and its Application in Link Discovery](https://www.ijcai.org/Proceedings/07/Papers/396.pdf)

Luc De Raedt, Angelika Kimmig, and Hannu Toivonen · Foundational research paper · Advanced

Logic: Probabilistic logic programming

**What it teaches:** Combines logical rules with uncertainty over facts or clauses and explains why overlapping proof paths cannot simply have their probabilities added.

**In your apps:** For Cowboyai, distinguish a definite rule-based consequence from a probabilistic graph hypothesis, and avoid double-counting the same underlying evidence through multiple paths. Its independence assumptions must be modeled deliberately, not replaced with arbitrary LLM confidence numbers.

**Reading note:** Read the graph example and the first ProbLog example, then inspect why success probabilities require more than counting proofs. The ProbLog project also has a Python package, but this paper explains the underlying design.

<a id="reading-07"></a>

### 07 The Seven Tools of Causal Inference with Reflections on Machine Learning

[The Seven Tools of Causal Inference with Reflections on Machine Learning](https://ftp.cs.ucla.edu/pub/stat_ser/r481.pdf)

Judea Pearl · Research essay / author manuscript · Intermediate

Logic: Causal, interventional, and counterfactual reasoning

**What it teaches:** Separates observing associations, predicting interventions, and answering counterfactuals, making the causal assumptions needed to move beyond observed patterns explicit.

**In your apps:** For NewsCalm, prevent a rewrite from strengthening 'associated with' into 'caused'; for Cowboyai, distinguish graph entailment from recommendations claiming that taking an action will improve an outcome.

**Reading note:** Start with The Three Layer Causal Hierarchy and the inference-engine discussion. Read as a conceptual foundation, not a current survey of AI capabilities.

<a id="reading-08"></a>

### 08 Explainability + Trust

[Explainability + Trust](https://pair.withgoogle.com/guidebook-v2/chapter/explainability-trust/)

Google PAIR, People + AI Guidebook · Design guide chapter · Conceptual

Logic: Uncertainty and explanation

**What it teaches:** Explains how uncertainty, stakes, data sources and explanations should influence whether users rely on an AI output, including why displaying a confidence percentage can mislead.

**In your apps:** Use this to design Cowboyai's distinction between sourced answers, inferred connections and unverified suggestions. For NewsCalm, show what was preserved and where the evidence came from instead of implying a polished rewrite has been independently fact-checked.

<a id="rules"></a>

## 2 Rules and explanations

How did those facts produce this answer?

Formal inference systems and engineering patterns. For Cowboyai’s dictionary, RDF, ontology, and WordNet work, make the difference between an imported fact, a derived relationship, and the evidence supporting it explicit.

<a id="reading-09"></a>

### 09 Tutorial

[Tutorial](https://souffle-lang.github.io/tutorial)

Soufflé project · Substantive official tutorial · Intermediate

Logic: Datalog, Horn clauses, recursive inference, and fixed points

**What it teaches:** Uses transitive closure and same-generation examples to show how facts plus rules derive graph relationships without manually programming every traversal step.

**In your apps:** Prototype Cowboyai rules over entities and relationships, keeping supplied facts separate from derived answers. Its discussion of language extensions also exposes why adding expressive power can lose termination guarantees.

**Reading note:** Read Introduction to Datalog, Transitive closure, and Same generation; installation and profiling can wait.

<a id="reading-10"></a>

### 10 Datalog

[Datalog](https://inst.eecs.berkeley.edu/~cs294-260/sp24/2024-02-05-datalog)

UC Berkeley CS294-260 course notes · University course notes · Advanced

Logic: Deductive and recursive query logic

**What it teaches:** Explains declarative inference from facts and rules: repeatedly apply relationships until no new facts follow, using graph reachability as a worked example.

**In your apps:** For Cowboyai’s personal graph, distinguish a recorded connection from one derived through several links, and ask whether each rule actually justifies the conclusion you want to show.

<a id="reading-11"></a>

### 11 Rules Engine

[Rules Engine](https://martinfowler.com/bliki/RulesEngine.html)

Martin Fowler · Technical essay · Conceptual

Logic: Production rules and rule chaining

**What it teaches:** Explains condition/action rules and why chaining them creates implicit behavior that needs narrow scope, careful tests, and realistic expectations about maintainability.

**In your apps:** Useful before Cowboyai grows from a few graph rules into an opaque engine: define which rules may derive facts, which may trigger actions, and how interactions will be tested.

**Reading note:** Read alongside Clara's Approach for a constructive counterpoint rather than taking either as a universal verdict.

<a id="reading-12"></a>

### 12 Clara's Approach

[Clara's Approach](https://www.clara-rules.org/docs/approach/)

Clara Rules project · Design essay · Conceptual

Logic: Declarative expert systems and composable business rules

**What it teaches:** Explains how independent domain rules, immutable sessions, and ordinary testable code can make an expert system easier to understand and maintain.

**In your apps:** For Cowboyai, make each inference rule a small unit with explicit required facts rather than letting one large LLM prompt silently coordinate the whole system. The value is the design approach, not a requirement to adopt Clojure.

**Reading note:** Companion, not an additional counted article: Truth Maintenance explains retracting derived facts when their support disappears.

[Uncounted companion on truth maintenance](https://www.clara-rules.org/docs/truthmaint/)

<a id="reading-13"></a>

### 13 PROV Model Primer

[PROV Model Primer](https://www.w3.org/TR/prov-primer/)

W3C Provenance Working Group · Explanatory standards primer · Intermediate

Logic: Provenance and derivation

**What it teaches:** A worked tutorial on entities, activities, agents, derivation and versioning, showing how to record where information came from and what transformations produced it.

**In your apps:** For Cowboyai, retain the chain from dictionary entry or RDF assertion through any WordNet bridge and LLM proposal to the final answer; for NewsCalm, link every rewrite to its source version and processing step. Provenance enables inspection but does not itself prove truth.

<a id="reading-14"></a>

### 14 Provenance Semirings

[Provenance Semirings](https://www.cs.ucdavis.edu/~green/papers/pods07.pdf)

Todd J. Green, Grigoris Karvounarakis, and Val Tannen · Foundational research paper · Advanced

Logic: Algebraic provenance and explanation of query answers

**What it teaches:** Develops an algebraic record of which input facts, and which combinations of them, support a query answer, connecting relational queries and recursive rules to incomplete or probabilistic information.

**In your apps:** For Cowboyai, an answer should be able to identify its supporting source facts and alternative derivations; if a source is corrected, that structure helps identify affected answers. For NewsCalm, use the principle to retain a claim-to-source trail rather than storing only the final prose.

**Reading note:** Focus on the introduction and examples before the algebra. Provenance establishes origin and dependency, not whether a source is accurate.

<a id="models"></a>

## 3 Models and boundaries

What should be impossible to represent?

Type theory, contracts, and engineering patterns. For Python, TypeScript, and Swift, define valid inputs and outcomes before coordinating databases, network calls, or model output.

<a id="reading-15"></a>

### 15 Domain services vs Application services

[Domain services vs Application services](https://enterprisecraftsmanship.com/posts/domain-vs-application-services/)

Vladimir Khorikov · Article · Intermediate · Starter route

Logic: Business decisions and orchestration

**What it teaches:** Distinguishes the logic that makes a business decision from the application code that gathers information and carries the decision out; an if-statement alone does not tell you where the real decision lives.

**In your apps:** For Cowboyai, separate the rule for whether an answer is supported from dictionary/graph retrieval and response delivery. This also clarifies which NewsCalm preservation decisions belong in reusable policy rather than page handlers.

<a id="reading-16"></a>

### 16 Designing with types: Making illegal states unrepresentable

[Designing with types: Making illegal states unrepresentable](https://fsharpforfunandprofit.com/posts/designing-with-types-making-illegal-states-unrepresentable/)

Scott Wlaschin · Article · Conceptual · Starter route

Logic: Algebraic data types and domain invariants

**What it teaches:** Shows how explicitly named choices in a data model encode business rules and prevent invalid combinations from being constructed through the intended types.

**In your apps:** Use TypeScript discriminated unions or Swift enums for distinct evidence outcomes such as supported, contradicted, conflicting, and unknown, instead of mixing several booleans that can disagree.

**Reading note:** F# syntax is incidental; read the contact example as a business-rule model.

<a id="reading-17"></a>

### 17 Parse, don’t validate

[Parse, don’t validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)

Alexis King · Article · Advanced

Logic: Input parsing and trusted representations

**What it teaches:** Shows why checking data and throwing away the result is weaker than transforming it into a representation that preserves what has been established; boundaries should produce data the rest of the program can safely consume.

**In your apps:** For Cowboyai's imported dictionary/RDF records and NewsCalm's model output, create explicit accepted records before running downstream logic. A valid shape or type still does not establish that an LLM's factual claim is true.

<a id="reading-18"></a>

### 18 Functional architecture is Ports and Adapters

[Functional architecture is Ports and Adapters](https://blog.ploeh.dk/2016/03/18/functional-architecture-is-ports-and-adapters/)

Mark Seemann · Article · Advanced

Logic: Pure decision logic and side effects

**What it teaches:** Explains a functional core with an imperative shell: predictable functions make decisions from explicit inputs, while adapters handle databases, files and other outside-world effects.

**In your apps:** A useful architecture for Cowboyai's deterministic answer core: pass retrieved facts into a pure decision function, and keep WordNet reads, RDF access and LLM requests at the boundary. The Haskell/F# examples illustrate an idea transferable to Python and TypeScript.

<a id="reading-19"></a>

### 19 Introduction to Contract Programming

[Introduction to Contract Programming](https://www.hillelwayne.com/post/contracts/)

Hillel Wayne · Article · Intermediate

Logic: Preconditions, postconditions and contracts

**What it teaches:** Separates what a caller must establish before an operation, what the operation promises afterward and what must remain true throughout an object’s life.

**In your apps:** For Cowboyai’s Python transformations, write explicit input requirements and output guarantees; for SAVY date conversion, distinguish a valid internal timestamp from malformed external text that must be handled as an ordinary error.

<a id="reading-20"></a>

### 20 Propositions as Types

[Propositions as Types](https://homepages.inf.ed.ac.uk/wadler/papers/propositions-as-types/propositions-as-types.pdf)

Philip Wadler · Foundational paper / author manuscript · Advanced

Logic: Curry–Howard correspondence and constructive logic

**What it teaches:** Explains the connection between logical propositions, types, proofs, and programs, showing why a well-chosen type can carry evidence that a requirement has been met.

**In your apps:** A framework for understanding why an API should accept an already-validated claim or nonempty evidence bundle instead of an arbitrary string or list. Useful across TS, Python, and Swift, while remembering that ordinary typechecking does not prove real-world truth.

**Reading note:** Start with the introduction and the examples connecting logic with programming; the formal derivations can wait.

<a id="state"></a>

## 4 State and identity

What can happen next, and what stays the same?

State-machine models and UI engineering patterns. For SAVY and React screens, decide which transitions are allowed, which values are authoritative, and when an object or view keeps its identity.

<a id="reading-21"></a>

### 21 You don’t need a library for state machines

[You don’t need a library for state machines](https://stately.ai/blog/2021-01-20-you-dont-need-a-library-for-state-machines)

David Khourshid · Engineering article · Conceptual / intermediate · Starter route

Logic: State machines and statecharts

**What it teaches:** Models allowed behavior as states and event-driven transitions, then explains how nested and parallel states handle complexity beyond a flat list.

**In your apps:** For SAVY, map signed out, authenticating, ready, offline, saving and failed states before asking an AI to implement SwiftUI screens. Apply the same model to a Next.js onboarding flow so invalid transitions are designed out.

**Reading note:** The article’s code uses older XState conventions. Read it for the model and design tradeoffs; use current documentation for implementation.

<a id="reading-22"></a>

### 22 Choosing the State Structure

[Choosing the State Structure](https://react.dev/learn/choosing-the-state-structure)

React team · Official tutorial chapter · Intermediate

Logic: Single-source-of-truth UI logic

**What it teaches:** Treats state design as a consistency problem: avoid contradictory flags, duplicated objects and values that can be calculated from existing state.

**In your apps:** In Next.js/React screens, keep the actual source records, selected IDs and user choices authoritative; derive filtered lists, counts and presentation status instead of synchronizing multiple copies. The reasoning also helps identify single-source-of-truth problems in SAVY.

<a id="reading-23"></a>

### 23 You Might Not Need an Effect

[You Might Not Need an Effect](https://react.dev/learn/you-might-not-need-an-effect)

React team · Official tutorial chapter · Intermediate

Logic: Reactive UI calculations and synchronization

**What it teaches:** Distinguishes calculations during rendering, actions caused by user events, and synchronization with external systems; many apparent workflow problems disappear when logic is placed in the right category.

**In your apps:** Especially useful for NewsCalm's TypeScript/React rewrite flow: derive displays from existing data, put deliberate rewrite requests in event-driven logic, and reserve effects for genuine external synchronization.

### Bonus transcript Demystify SwiftUI

[Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/)

Apple, WWDC21 · Video transcript · Intermediate · Not counted in the 50

**What it teaches:** Explains SwiftUI through identity, lifetime and dependencies: when two views count as the same thing, how their state survives, and what makes updates propagate.

**In your apps:** For SAVY, this is the conceptual guide to stable record IDs, persistent selection and avoiding unexpected resets as synced data changes. Read the page's full transcript; it explains UI identity, not a network-sync conflict-resolution algorithm.

<a id="time"></a>

## 5 Time and shared data

What happens when two devices disagree?

Distributed-systems models and engineering guarantees. For SAVY’s iPhone, Mac, and AWS backend, ask what “saved” means, how edits are ordered, and which conflicts may merge automatically.

<a id="reading-24"></a>

### 24 Local-first software: You own your data, in spite of the cloud

[Local-first software: You own your data, in spite of the cloud](https://www.inkandswitch.com/essay/local-first/)

Martin Kleppmann, Adam Wiggins, Peter van Hardenberg and Mark McGranaghan · Research essay / paper · Conceptual / intermediate · Starter route

Logic: Replication, merge rules and local-first state

**What it teaches:** Connects offline use, speed, ownership, and collaboration to replication choices, including the difficulties of reconciling edits across devices.

**In your apps:** For SAVY’s SwiftUI iPhone and Mac apps, decide which actions should work immediately on-device, how edits reach the AWS backend, and which conflicts need explicit rules. Especially useful for reviewing a sync design before UI implementation.

**Reading note:** Published in 2019. Its product comparisons are historical; use the enduring design questions rather than treating it as a current vendor shortlist.

<a id="reading-25"></a>

### 25 Time, Clocks, and the Ordering of Events in a Distributed System

[Time, Clocks, and the Ordering of Events in a Distributed System](https://lamport.azurewebsites.net/pubs/time-clocks.pdf)

Leslie Lamport · Research paper (PDF) · Advanced

Logic: Causal ordering and logical clocks

**What it teaches:** Builds a ‘happened before’ relation and logical clocks to distinguish causal ordering from unreliable wall-clock timestamps across separate computers.

**In your apps:** When SAVY edits arrive from iPhone and Mac, ask whether one edit actually knew about the other before deciding which wins. Useful for preventing a late network response from silently overwriting a newer action.

**Reading note:** A larger Lamport timestamp alone does not prove that one event caused or knew about another. This is a foundation for reasoning about synchronization, not a ready-made sync algorithm.

<a id="reading-26"></a>

### 26 Please stop calling databases CP or AP

[Please stop calling databases CP or AP](https://martin.kleppmann.com/2015/05/11/please-stop-calling-databases-cp-or-ap.html)

Martin Kleppmann · Technical essay · Intermediate

Logic: Consistency guarantees and distributed-system tradeoffs

**What it teaches:** Replaces loose database labels with precise questions about what a reader can observe after a write, which requests can succeed during a partition, and what delay is acceptable.

**In your apps:** For SAVY with Aurora, or for cached Next.js data, specify whether a user must immediately see their latest change and what another device may show while catching up; for Cowboyai, distinguish ‘job accepted’ from ‘result visible everywhere.’

**Reading note:** The 2015 product-specific examples are historical. The useful lesson is precision about guarantees, not a current classification of database products.

<a id="reading-27"></a>

### 27 13.2. Transaction Isolation

[13.2. Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)

PostgreSQL Global Development Group · Official reference · Advanced

Logic: Transactional consistency

**What it teaches:** Two individually sensible operations can produce an impossible combined result when they run together; isolation levels specify which contradictions the database prevents.

**In your apps:** Use this to question concurrent edits and multi-record updates in your Postgres apps: does the final result still obey the product rule when two requests both act on an earlier snapshot?

<a id="reading-28"></a>

### 28 Building on Quicksand

[Building on Quicksand](https://arxiv.org/pdf/0909.1788)

Pat Helland and Dave Campbell · Research / systems-design paper (PDF) · Advanced

Logic: Eventual consistency, commutative operations and reconciliation

**What it teaches:** Connects eventual consistency to offline use, commutative operations, unique operation identities, and compensating actions rather than blindly copying database values.

**In your apps:** For SAVY, distinguish edits that can safely merge in either order from destructive conflicts requiring a decision. For Cowboyai, decide which partial results can be reconciled automatically and which actions must wait for stronger confirmation.

**Reading note:** Read its probabilistic guarantees as analysis of the specific asynchronous designs it discusses, not as a universal claim that all distributed systems lose committed work.

<a id="workflows"></a>

## 6 Workflows and recovery

What happens if the job stops halfway through?

Workflow and failure-recovery engineering patterns. For Cowboyai’s overnight LLM options and NewsCalm’s pipeline, decide who chooses the next step, which progress survives a crash, and how retries avoid duplicate work.

<a id="reading-29"></a>

### 29 Building effective agents

[Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)

Anthropic · Article · Conceptual · Starter route

Logic: Deterministic workflows and model-directed actions

**What it teaches:** Separates predefined, code-directed workflows from agents that choose their own next actions, then explains routing, chaining, parallelization and evaluator loops with practical diagrams.

**In your apps:** For Cowboyai's overnight LLM options, decide explicitly which choices the model may propose and which acceptance, routing and publication rules remain deterministic. Particularly helpful before adding an autonomous agent to a task that a fixed pipeline can handle.

<a id="reading-30"></a>

### 30 What do you mean by “Event-Driven”?

[What do you mean by “Event-Driven”?](https://martinfowler.com/articles/201701-event-driven.html)

Martin Fowler · Architecture essay · Conceptual

Logic: Events, commands, replay and separate read models

**What it teaches:** Separates event notification, state transfer, event sourcing, and CQRS, exposing how scattered notifications can hide a system’s real workflow.

**In your apps:** When SAVY publishes “item changed” or Cowboyai reports “job finished,” decide whether the message is a fact, a request to do work, a full state update or a record needed for replay. This prevents several different architectures being casually bundled together.

<a id="reading-31"></a>

### 31 Making retries safe with idempotent APIs

[Making retries safe with idempotent APIs](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/)

Malcolm Featonby · Engineering article · Intermediate

Logic: Idempotency and intent identity

**What it teaches:** Explains how stable request identifiers, atomic recording, and equivalent responses make retries represent one intended action when a timeout leaves the outcome uncertain.

**In your apps:** Give each SAVY save or Cowboyai job submission a stable operation ID. Reuse it across retries so a lost response does not create duplicate records, launch a second job or repeat an external action.

**Reading note:** Idempotency needs a defined scope, retention period and behavior when the same key arrives with changed parameters.

<a id="reading-32"></a>

### 32 Timeouts, retries, and backoff with jitter

[Timeouts, retries, and backoff with jitter](https://d1.awsstatic.com/builderslibrary/pdfs/timeouts-retries-and-backoff-with-jitter.pdf)

Marc Brooker · Engineering article (PDF) · Intermediate

Logic: Failure recovery, retry budgets and randomized timing

**What it teaches:** Explains why retries can turn a small failure into an outage, how timeouts should relate to latency, and why adding varied delays prevents many clients from retrying simultaneously.

**In your apps:** For Cowboyai’s Python service, choose which layer retries an LLM or AWS call and bound its attempts. Spread overnight jobs across time rather than starting them all at midnight. Apply the same discipline to SAVY reconnecting after lost connectivity.

**Reading note:** Retries with side effects require idempotency. The PDF is linked because the original Builders’ Library page now redirects to a JavaScript-heavy AWS page.

<a id="reading-33"></a>

### 33 Designing a Workflow engine from first principles

[Designing a Workflow engine from first principles](https://temporal.io/blog/workflow-engine-principles)

Shawn Wang, summarizing a Temporal engineering talk · Engineering article / annotated talk · Intermediate

Logic: Durable state machines, queues and transaction boundaries

**What it teaches:** Explains durable workflows through persistent state, queues, timers, and transaction boundaries, including the race between recording work and dispatching it.

**In your apps:** Use it to evaluate Cowboyai’s overnight-job architecture: where does a job’s state survive, who owns the timer, and what happens if a process dies between saving the next step and dispatching it? Also relevant when a Vercel request starts longer-running backend work.

**Reading note:** Published in 2021, with historical SDK availability notes. This is an architectural reading, not a recommendation that the existing stack must adopt Temporal.

<a id="reading-34"></a>

### 34 Of course you can build dynamic AI agents with Temporal

[Of course you can build dynamic AI agents with Temporal](https://temporal.io/blog/of-course-you-can-build-dynamic-ai-agents-with-temporal)

Mason Egger and Steve Androulakis · Engineering article · Intermediate

Logic: Deterministic replay around nondeterministic decisions

**What it teaches:** Separates unpredictable model and tool results from deterministic coordination, so recovery can reuse recorded decisions instead of asking a model to invent them again.

**In your apps:** For Cowboyai’s Python agents, preserve the results of completed LLM decisions and resume from recorded progress after a worker fails overnight. Use durable orchestration for the plan while keeping model calls and network effects in explicit activities.

**Reading note:** Durable replay does not automatically make external side effects exactly-once. Activities that can be retried still need idempotency or reconciliation; pair this with the AWS idempotency article.

<a id="reading-35"></a>

### 35 Patterns for Building LLM-based Systems & Products

[Patterns for Building LLM-based Systems & Products](https://eugeneyan.com/writing/llm-patterns/)

Eugene Yan · Article · Intermediate

Logic: Reliable AI product logic

**What it teaches:** A substantial systems essay connecting evaluations, retrieval, fine-tuning, caching, guardrails, defensive UX and feedback; it explains the purpose and trade-offs of the surrounding product logic.

**In your apps:** Use it to sketch Cowboyai's LLM boundary and NewsCalm's rewrite pipeline: what evidence enters, what output is checked, what can be cached safely, and how failures return to the product. Treat its 2023 model examples as illustrations rather than current model recommendations.

<a id="data"></a>

## 7 Data and permissions

Which records count, and who may change them?

Relational logic, invariants, and authorization policies. For Postgres, Supabase, and SAVY’s Cognito identity, distinguish what a query returns, what the database guarantees, and what a verified user is allowed to do.

<a id="reading-36"></a>

### 36 A Beginner’s Guide to the True Order of SQL Operations

[A Beginner’s Guide to the True Order of SQL Operations](https://blog.jooq.org/a-beginners-guide-to-the-true-order-of-sql-operations/)

Lukas Eder, creator of jOOQ · Article · Intermediate

Logic: Relational and declarative query logic

**What it teaches:** SQL describes the result you want; its logical sequence of joining, filtering, grouping and selecting differs from both the order you write and the database’s execution plan.

**In your apps:** For your Postgres/Supabase apps, use this to reason about a feed or dashboard: are you filtering individual articles before grouping them, or filtering whole groups afterward?

<a id="reading-37"></a>

### 37 The Three-Valued Logic of SQL

[The Three-Valued Logic of SQL](https://modern-sql.com/concept/three-valued-logic)

Markus Winand · Article · Intermediate

Logic: Three-valued logic and missing information

**What it teaches:** A missing value introduces a third answer, unknown; it behaves differently from false, especially in exclusions, filters and database checks.

**In your apps:** In SAVY or a Supabase app, decide explicitly what missing completion dates, ownership fields or classifications mean so that a filter does not silently hide records you intended to keep.

<a id="reading-38"></a>

### 38 5.5. Constraints

[5.5. Constraints](https://www.postgresql.org/docs/current/ddl-constraints.html)

PostgreSQL Global Development Group · Official reference · Intermediate

Logic: Database constraints and invariants

**What it teaches:** Constraints turn business rules into conditions the database must preserve, including uniqueness, valid relationships and required values.

**In your apps:** For your Postgres/Supabase data, make rules such as ‘every saved article references a real source record’ or ‘this identifier is unique’ hold regardless of which screen or API writes the data.

<a id="reading-39"></a>

### 39 Verifying JSON web tokens

[Verifying JSON web tokens](https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html)

AWS, Amazon Cognito documentation team · Official reference · Intermediate

Logic: Identity verification and trust boundaries

**What it teaches:** Reading a claim is different from establishing that a trusted issuer made it; identity depends on checking the signature and the token’s intended issuer, recipient, use and validity.

**In your apps:** This directly illuminates SAVY’s decoded-subject question: locate the verification step before using the subject to authorize access, including any verification already supplied by an API gateway or library.

<a id="reading-40"></a>

### 40 Row Level Security

[Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)

Supabase documentation team · Official reference · Intermediate

Logic: Authorization predicates

**What it teaches:** Authorization can be a predicate attached to the data: each request must satisfy rules about which existing rows it can access and which resulting rows it may create.

**In your apps:** For your Supabase apps, express ‘this user owns this record’ at the database boundary, and check both reading a record and changing its owner rather than relying on a hidden UI control.

<a id="reading-41"></a>

### 41 How Cedar authorization works

[How Cedar authorization works](https://docs.cedarpolicy.com/auth/authorization.html)

Cedar policy language team · Official reference · Intermediate

Logic: Policy-combination logic

**What it teaches:** Policy logic separates who, action, resource and context, then defines how multiple rules combine: Cedar defaults to denial and gives a matching prohibition priority over permission.

**In your apps:** Use the model to write a clear SAVY or Cowboyai sharing policy before implementation: who may read which item, under which conditions, and what should happen when permission rules conflict?

<a id="checks"></a>

## 8 Testing and safe failure

How would you discover that your rule is wrong?

Testing patterns, specifications, and formal verification. For all four app contexts, turn intended behavior into checks, include realistic bad inputs, and define an acceptable response when the system cannot justify an answer.

<a id="reading-42"></a>

### 42 The Enterprise Developer from Hell

[The Enterprise Developer from Hell](https://fsharpforfunandprofit.com/posts/property-based-testing/)

Scott Wlaschin · Article · Conceptual · Starter route

Logic: Property-based specifications

**What it teaches:** Passing a few examples is weak evidence; describing properties that every correct result must satisfy makes hidden assumptions and inadequate tests visible.

**In your apps:** For NewsCalm, ‘the rewrite sounds calmer’ is insufficient: ask what must stay true about the original event, people and claims even if the wording changes, and retain human-checked examples of meaning-changing failures.

<a id="reading-43"></a>

### 43 What is Property Based Testing?

[What is Property Based Testing?](https://hypothesis.works/articles/what-is-property-based-testing/)

David R. MacIver, creator of Hypothesis · Article · Conceptual

Logic: Property-based testing versus fuzzing

**What it teaches:** The creator of Hypothesis argues that property-based testing is principally the human work of identifying meaningful failure conditions, rather than simply generating random inputs or choosing a library.

**In your apps:** In Cowboyai’s Python code, ‘it did not crash’ is only a starting point; specify what a correct graph transformation must preserve before asking Hypothesis to explore inputs.

<a id="reading-44"></a>

### 44 Choosing properties for property-based testing

[Choosing properties for property-based testing](https://fsharpforfunandprofit.com/posts/property-based-testing-2/)

Scott Wlaschin · Article · Intermediate

Logic: Algebraic properties and test design

**What it teaches:** Provides reusable ways to discover useful test rules, including round trips, preserved quantities, repeated-operation stability and comparison with a simpler independent model.

**In your apps:** For SAVY’s timestamp parsing, test that encoding and decoding preserve the same instant across the formats you support; for Cowboyai, check that exporting and re-importing a graph preserves its recorded relationships.

<a id="reading-45"></a>

### 45 Metamorphic Testing

[Metamorphic Testing](https://www.hillelwayne.com/post/metamorphic-testing/)

Hillel Wayne · Article · Intermediate

Logic: Metamorphic testing and test oracles

**What it teaches:** When the exact correct output is difficult to specify, test relationships between related inputs and outputs, while remembering that consistent answers can still be consistently wrong.

**In your apps:** For NewsCalm, controlled changes to harmless formatting should not change the event conveyed by a rewrite; combine these checks with source-grounded examples so ‘destroyed’ becoming ‘criticized’ cannot pass simply because the rewrite agrees with itself.

<a id="reading-46"></a>

### 46 Evaluation & Hallucination Detection for Abstractive Summaries

[Evaluation & Hallucination Detection for Abstractive Summaries](https://eugeneyan.com/writing/abstractive/)

Eugene Yan · Article · Advanced

Logic: Factual consistency and inference checks

**What it teaches:** Separates fluency, coherence, relevance and source consistency, then examines entailment, question-answering and sampling approaches to checking generated summaries, including evaluator weaknesses.

**In your apps:** Highly specific to NewsCalm: a calmer rewrite must preserve who did what, negation, quantities and attribution, even when its wording changes. The key distinction is faithfulness to the source versus accuracy in the world; one does not automatically prove the other.

<a id="reading-47"></a>

### 47 Errors + Graceful Failure

[Errors + Graceful Failure](https://pair.withgoogle.com/chapter/errors-failing/)

Google PAIR, People + AI Guidebook · Design guide chapter · Conceptual

Logic: Failure and fallback logic

**What it teaches:** Connects probabilistic errors to product decisions: define what failure means, distinguish its possible sources, and give users a usable path when the system cannot succeed.

**In your apps:** For Cowboyai, specify when to abstain, ask a clarifying question, or use a deterministic answer; for NewsCalm, hold a failed rewrite unpublished for review and retain the original as evidence, with an empty feed preferable to unsuitable news.

<a id="reading-48"></a>

### 48 Why We Should Build Software Like We Build Houses

[Why We Should Build Software Like We Build Houses](https://lamport.azurewebsites.net/pubs/wired.pdf)

Leslie Lamport · Essay (PDF) · Conceptual

Logic: Specification and abstraction

**What it teaches:** Treats a precise behavioral description as a thinking tool, ranging from a sentence for a simple operation to a formal model for a subtle one.

**In your apps:** Before a Cowboyai agent or coding assistant changes a feature, give it the allowed behavior, failure behavior and facts that must remain true. For SAVY, specify what “saved” means when the phone is offline.

**Reading note:** This is Lamport’s author-hosted 2013 essay, rather than the expanded 2015 ACM article.

<a id="reading-49"></a>

### 49 How Amazon Web Services uses formal methods

[How Amazon Web Services uses formal methods](https://cdn.amazon.science/67/f9/92733d574c11ba1a11bd08bfb8ae/how-amazon-web-services-uses-formal-methods.pdf)

Chris Newcombe, Tim Rath, Fan Zhang, Bogdan Munteanu, Marc Brooker and Michael Deardeuff · Engineering case-study paper (PDF) · Intermediate

Logic: Temporal logic, invariants and model checking

**What it teaches:** Separates safety, meaning bad states never occur, from liveness, meaning needed progress eventually happens, and shows how AWS explored failures and event orderings with TLA+.

**In your apps:** Write two rules for an overnight Cowboyai job: a completed external action must not be duplicated, and an accepted job must eventually finish or reach an explicit failed state. A small model can test cancellation, crashes and retries around those rules.

**Reading note:** A checked design model is not a proof that all implementation code is correct. The case studies describe AWS’s experience at publication in 2015.

<a id="reading-50"></a>

### 50 Don't let Alloy facts make your specs a fiction

[Don't let Alloy facts make your specs a fiction](https://www.hillelwayne.com/post/alloy-facts/)

Hillel Wayne · Article · Advanced

Logic: Model-checking assumptions

**What it teaches:** A checker cannot find a failure you have excluded by assumption: formal models must include the bad inputs and situations the real environment can create.

**In your apps:** When testing SAVY authentication or NewsCalm validation, include forged claims and meaning-changing rewrites in the model instead of assuming identity or factual fidelity before the check begins.

## A note on applying the readings

The app connections and reading order are recommendations for understanding the designs. Historical code, models, and vendor examples illustrate ideas; check current documentation before implementing them. Source publication dates vary.
