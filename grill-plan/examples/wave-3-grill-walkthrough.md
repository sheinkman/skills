# Worked example — Wave 3 plan grill

A real grill that ran on the claim-examiner project in May 2026. Shows what each gate produced and why the rejection table is the load-bearing output.

## Context

After Wave 0+1 shipped (commit `c83f0de`), the team had a draft Wave 3 plan with **7 AI-tuning levers**. The goal: improve target-hit rate on the dices-a1 family beyond the 2/10 baseline.

## Gate 1 — Effectiveness check

| Axis | Value |
|---|---|
| Plan type | AI-tuning lever set |
| Cost-of-being-wrong | hard-to-unwind (prompt changes regress silently) |
| Lever count | 7 |
| Evidence base | partial (89-run baseline existed, 10-run dices investigation existed) |
| Time-to-ship vs. time-to-grill | ship >> grill |

**Viability: HIGH.** Proceed to Gate 2.

## Gate 2 — Dispatch plan

5 agents dispatched in parallel:

| # | Role | Question | Levers in scope |
|---|---|---|---|
| 1 | Empirical Falsifier | Does the 89-run baseline support each lever's claim? | All 7 |
| 2 | Code Contradiction Hunter | Does any lever collide with existing suppression / cgate logic? | L1, L5 (schema + post-hoc merge) |
| 3 | Cost/Complexity Critic | Is "1-2 days" honest for the prompt-optimizer A/B claim? | L3 |
| 4 | Steel-manner | What's the strongest version of "do nothing and instead measure first"? | All 7 |
| 5 | Domain Specialist | Which lever violates a claim-examiner gotcha? | All 7 |

## Gate 3 — Execute + converge

Agents ran in parallel. Aggregation produced this table (the load-bearing output):

### Rejected / deferred

| Lever | Original claim | Verdict | Why | Cited by |
|---|---|---|---|---|
| L1 — Schema tightening (closed `coverageCode` enum, required `bookingRef`) | "$0 cost, half-day" | **Drop** | Required `bookingRef` directly contradicts `suppressDuplicateNoRefAirlineTint` Case A at `transaction-ledger.service.ts:1797` which keys off `!tx.bookingReference`. Closed enum breaks across policies (field is `exposureCode`, per-policy data). | Code Contradiction Hunter |
| L2 — Few-shot grounding | "Examples produce more consistent output" | **Defer** | Prompt already 12KB with explicit rubric at line 2351. Failure isn't missing instructions — it's instructions ignored. Adding more text dilutes attention budget. | Steel-manner |
| L3 — Prompt-optimizer A/B | "1-2 days, use existing infra" | **Re-classify as Wave 3B** | `transaction-ledger.service.ts:2299` is a hardcoded template literal, not wired into `PromptRegistryService`. Real cost: 1-2 days migration *before* A/B is possible. | Cost/Complexity Critic |
| L5 — `AI_EMISSION_REPAIRED` post-hoc merge | "Belt-and-suspenders" | **Re-scope** | Duplicates existing `suppressReplacementTickets` pass. Two passes will race — metrics become inscrutable. Either extend the existing suppressor OR narrow to the no-anchor case. | Sequencing/Race Critic |
| L6 — Self-consistency voting | (already known weak) | Confirmed reject | — | — |
| L7 — RAG / precedent corpus | (deferred from earlier wave) | Confirmed defer | — | — |
| Proposed divergence-RMI guard | "Catch high-divergence APPROVEs" | **Drop** | Empirical: divergence reads 84-95% uniformly across all 10 dices runs *including the 2 target hits*. Guard would fire on 100% of runs. | Domain Specialist + Empirical Falsifier |

### Accepted

| Lever | Verdict | Surviving rationale | Cited by |
|---|---|---|---|
| Wave 3A — Diagnostic instrumentation first | **Keep** | No prompt or code lever survived without "measure the specific Group C failure mode first". | Steel-manner |
| Wave 3A.5 — Extend `suppressReplacementTickets` for no-anchor case | **Keep, scoped** | Narrowed from L5. Targets the specific Group C signature (foreign=2, ≥2 TINT same carrier, one higher amount, passport-loss extracted signal). | Code Contradiction Hunter |
| Wave 3B — Wire `TRANSACTION_LEDGER` into `PromptRegistryService` | **Keep, deferred** | Re-classified from L3. Pre-requisite for any future prompt A/B. | Cost/Complexity Critic |

### Convergence

- Iteration 1: 15 substantive challenges
- Iteration 2 (Steel-manner re-pass on accepted levers): 0 new challenges
- **Converged at iteration 2.**

## What this grill prevented

Without the grill:
1. **L1** would have shipped a required `bookingRef` field that broke Case A suppression — direct regression on every claim with missing booking refs.
2. **L3** would have been estimated as 1-2 days; actual cost (1-2 days migration + 1-2 days A/B) would have blown the wave estimate by 2-3×.
3. **L5** would have raced the existing suppressor and made post-Wave-3 metrics inscrutable.
4. **The divergence guard** would have fired on 100% of runs including target hits — silently downgraded every APPROVE to RMI.

## What the grill cost

- 5 agents × ~3 minutes each (parallel) = ~3 min wall-clock
- 1 aggregation pass = ~2 min
- 1 re-pass = ~3 min
- **Total: ~8 min for 15 substantive challenges and 4 averted regressions.**

## What "ineffective grilling" would have looked like

If the plan had been "just bump IDLE_TIMEOUT from 90s to 210s" (a single forced move with empirical backing from Wave 0+1):

- Lever count: 1
- Cost-of-being-wrong: reversible (revert one line)
- Evidence base: empirical (PID 24609 data)
- Time-to-ship vs. grill: ship << grill

**Gate 1 would have scored LOW** and recommended "just ship the small version" — no grill. That's the right answer.

## Takeaway pattern

The grill is high-leverage when (a) lever count ≥3, (b) at least one lever changes a contract, and (c) cost-of-being-wrong is hard-to-unwind. Below those bars, grilling produces fake objections to a forced move and wastes a session.
