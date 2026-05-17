# Agent Role Taxonomy — Grill Plan

Detailed reference for the 8 grill-agent roles. SKILL.md keeps the one-line summary; this file is the deep cut. Load when picking a dispatch in Gate 2.

## How to use this taxonomy

Each grill role answers **one** sharp question. The questions are deliberately non-overlapping — if two roles end up answering the same question, collapse them. The minimum signal a role must return is: **verdict + cited evidence**. "Feels risky" is a not-finding.

For any plan with ≥3 levers, **always include Steel-manner** — empirically the highest-yield role. It produces the only kind of finding that changes a decision rather than refining it.

---

## 1. Empirical Falsifier

**Question:** Does the data actually support this claim?

**When to dispatch:**
- The plan asserts a metric improvement ("X reduces Y by N%")
- A lever's pitch references "data shows" / "we know" / "evidence suggests"
- A baseline file or experiment ledger exists and could be cross-checked

**When to skip:**
- The plan is purely architectural or definitional (no measurable claim)
- A recent 30-run batch already covered the same claim
- The "evidence" requested is unmeasurable in available infra

**Evidence types it must cite:**
- Frozen baseline path (`experiments/baseline-<date>.json`)
- Specific exam IDs and metrics
- Falsifiable predictions ("if X is true, we should see Y; we don't")
- Statistical caveats (sample size, confidence interval)

**Anti-pattern:** Returning "the data is mixed" without naming the runs. Force a specific contradicting datapoint or accept the claim.

---

## 2. Code Contradiction Hunter

**Question:** Does this proposal collide with existing code or contracts?

**When to dispatch:**
- The plan changes a schema, contract, or shared interface
- The plan adds a closed enum or required field
- The plan describes behavior that overlaps with existing deterministic logic (suppressors, validators, guards)

**When to skip:**
- The plan is greenfield (no existing code to collide with)
- The plan is purely documentation or process

**Evidence types it must cite:**
- `file:line` of the conflicting code
- The exact contract clause being broken
- A call-graph reference if behavior is indirect

**Load-bearing pattern from the claim-examiner project:** The Wave 3 grill caught a proposed `required: bookingRef` schema change that would have broken `suppressDuplicateNoRefAirlineTint` Case A (`transaction-ledger.service.ts:1797`) which keys explicitly off `!tx.bookingReference`. Without this role, that lever would have shipped and regressed.

**Anti-pattern:** Vague "this might conflict with existing code". Force the file:line.

---

## 3. Sequencing / Race Critic

**Question:** What runs before what? What's in-flight that conflicts?

**When to dispatch:**
- The plan adds a pipeline stage, middleware, or post-processing pass
- Other plans / waves are in-flight in the same area
- Feature flags or rollout windows are involved

**When to skip:**
- The change is self-contained and idempotent
- The work area has no other in-flight changes

**Evidence types it must cite:**
- Other plan docs / commit SHAs the change interacts with
- Order-of-execution diagrams or call sites
- Feature-flag dependency chain

**Load-bearing pattern:** The Wave 3 grill caught that a proposed second-pass `AI_EMISSION_REPAIRED` merge would race the existing `suppressReplacementTickets` pass — two passes competing produces inscrutable metrics. The fix was to extend the existing suppressor, not add a parallel one.

---

## 4. Cost / Complexity Critic

**Question:** Is the engineering estimate honest? What's hidden?

**When to dispatch:**
- The plan claims "1 day" or "quick win"
- The plan involves migrations, schema changes, or dependency upgrades
- The work spans multiple services / repos

**When to skip:**
- The change is a single file < 50 lines

**Evidence types it must cite:**
- The actual migration scope (which entities, how many call sites)
- Test churn (how many tests need updating)
- Dependency cascade (what else has to move)

**Load-bearing pattern:** The Wave 3 grill re-classified "use prompt-optimizer to A/B-test the ledger prompt" from "1-2 days quick win" to **Wave 3B (1-2 days actual)** because `transaction-ledger.service.ts:2299` uses a hardcoded template literal, not `PromptRegistryService` — wiring it up is a separate migration before A/B is even possible.

---

## 5. Scope Critic

**Question:** Is this the smallest version that solves the problem?

**When to dispatch:**
- The plan has ≥3 levers
- The pitch includes phrases like "while we're in there" or "also let's…"
- The change is in an area that already has multiple half-finished features

**When to skip:**
- The plan is a forced single move
- The user has explicitly framed the task as a refactor

**Evidence types it must cite:**
- Which lever(s) could be cut without losing the stated goal
- Which lever solves the load-bearing problem alone

**Anti-pattern:** Suggesting "we should also…". Scope Critic *removes* scope, never adds.

---

## 6. Reversibility / Blast-radius Critic

**Question:** If this ships wrong, what's the rollback cost and who breaks?

**When to dispatch:**
- The plan touches production data, billing, auth, or user-visible behavior
- The plan changes a deployed contract (API, schema)
- The plan modifies orchestration / queue / job code that can leave half-processed state

**When to skip:**
- Pure local refactor
- Behind an off-by-default feature flag with kill switch

**Evidence types it must cite:**
- Rollback recipe (commit revert, flag flip, data backfill)
- Affected systems / downstream consumers
- On-call impact (does this page someone?)

**Load-bearing pattern from `start-be.sh` incident (2026-05-12):** The reversibility critic would have caught that running `npm run start:dev` directly leaves orphan workers connected to the same Bull queue, producing bimodal results across batches. Cost of being wrong: corrupted eval runs. Mitigation: hardened `./start-be.sh` script.

---

## 7. Steel-manner

**Question:** What's the strongest version of the *opposite* position?

**When to dispatch:** **Always**, for any plan with ≥3 levers.

**When to skip:** Single-move forced plans with no opposite position.

**Evidence types it must cite:**
- Refs / quotes from the school of thought arguing the opposite
- Concrete examples of when the opposite approach won
- Specifically: "the version of this plan where we do *nothing* and instead…"

**Why this is the highest-yield role:** Most grills produce "this might fail because…" findings that refine the plan. Steel-manner produces "have you considered NOT doing this at all and instead…?" — which is what changes the *decision*. Most of the levers killed in the Wave 3 grill died to Steel-manner reframings, not to falsification.

**Anti-pattern:** Producing a weak straw-version of the opposite ("we could do nothing, but that's bad because…"). The role only earns its slot if the steel-manned position is genuinely defensible.

---

## 8. Domain Specialist

**Question:** What project-specific gotcha would invalidate this?

**When to dispatch:**
- The project has known idiosyncrasies that generic critics will miss
- The plan touches infrastructure with project-specific contracts
- The user has memory entries or playbooks that capture domain rules

**When to skip:**
- The plan is in a domain where the generic critics' coverage is sufficient
- No domain knowledge has been captured for this area

**Evidence types it must cite:**
- The specific project rule / memory entry / playbook the plan violates
- A past incident where the same gotcha bit

**Example — claim-examiner gotchas** (shown to illustrate the *shape* of project-specific knowledge a Domain Specialist should be primed with; substitute your own project's equivalents before dispatching):

- Foreign-anchor count is necessary but not sufficient for suppression to fire
- The `divergence` metric reads 84–95% uniformly and is unusable as a gate signal
- `IDLE_TIMEOUT_MS` at 90s causes ADK timeouts; 210s is the validated floor
- `start-be.sh` must be used; bypassing it produces zombie workers
- Per-claim target $ must be sourced from the authoritative examiner (never guessed)
- Foreign-anchor + suppression-name combinations are the actual signal, not divergence

Notice the shape: each gotcha is a **falsifiable rule grounded in a past incident or a specific file/metric**. Vague maxims ("be careful with prompts") don't qualify — a Domain Specialist armed with vague rules will return vague findings.

**For your own project:** before dispatching, ask the user "What's the load-bearing gotcha in this area that a generic critic would miss?" and capture the answer in the same falsifiable-rule shape.

---

## Picking a dispatch — heuristic

| Plan signal | Roles to include |
|---|---|
| Adds a schema/contract change | Code Contradiction Hunter (always) |
| Asserts a measurable improvement | Empirical Falsifier (always) |
| Has ≥3 levers | Steel-manner (always) + Scope Critic |
| Touches in-flight work | Sequencing/Race Critic |
| Claims "quick win" | Cost/Complexity Critic |
| Hits prod / shared state | Reversibility/Blast-radius Critic |
| Domain has known gotchas in memory | Domain Specialist |

Never dispatch more than 5 in parallel. Beyond that, aggregation cost dominates and the rejection table becomes noisy. For very large plans (>10 levers), grill **per cluster** of related levers, not per individual lever.
