---
name: grill-plan
description: Use this skill when the user asks to grill, stress-test, red-team, or adversarially review a plan, proposal, architecture decision, lever set, or roadmap. Triggered by phrases like "grill this plan", "grill these levers", "stress-test the proposal", "red-team this", "challenge these decisions", "is this ready to ship", "find what's wrong with this plan". The skill has THREE gates — it first decides whether grilling will actually be effective for the input; if yes, it proposes a parallel-agent dispatch with explicit roles; only then does it execute the grill. Output is a rejection/acceptance table with empirical citations.
---

# Grill Plan

## ⛔ STOP — Do this first

Before any tool calls, post this to the user:

> **Grill Plan activated.** Three gates before we start.
>
> 1. **Gate 1 · Effectiveness check** — I read the plan, classify it, and score whether grilling will produce signal. If LOW, I recommend an alternative (ship the small version / get evidence first / make the cheap reversible call).
> 2. **Gate 2 · Dispatch plan** — If grilling is viable, I propose N parallel agents with distinct roles, one sharp question per agent. You approve before any sub-agent fires.
> 3. **Gate 3 · Execute + converge** — Run the dispatch, aggregate findings, iterate until a pass produces no new substantive challenges.
>
> Stops at every gate.

Then ask: _"What's the plan you want grilled? Paste it, point me at a file, or describe it. Also: what's the cost-of-being-wrong here — reversible / mildly expensive / hard-to-unwind?"_

**Do not start Gate 1 until the user replies.**

---

## ⛔ Golden Rules

1. **Never skip Gate 1.** Running a grill on a forced move or trivial change is theater. The check costs <2 minutes and saves a session.
2. **One question per agent.** Each agent gets ONE question. If a role needs two ("is this empirically supported AND does it contradict existing code"), split it into two roles. Agents drift when given two questions.
3. **Each agent must cite evidence** — a file:line, a baseline ref, a prior experiment, a vendor doc, a falsifiable prediction. "Feels risky" is not a finding.
4. **Evidence beats consensus.** If 4 agents say "ship it" and 1 agent finds a load-bearing contradiction with file:line evidence, the contradiction wins. The grill is not a vote.
5. **Agents propose, main session disposes.** Never let an agent grade itself. The aggregation pass is the judge of which verdicts hold.
6. **The rejection table is the deliverable.** Bullet-point summaries get lost; a table with a "Why" column survives compression.
7. **Mark convergence explicitly.** State the iteration count when no new challenges survive a pass.
8. **Never grill the user's *decision*; grill the *plan*.** If the user has decided and is asking for execution help, this skill is the wrong tool.

---

## Gate 1 — Effectiveness check

Read the plan. Classify it on these axes:

| Axis | Options |
|---|---|
| Plan type | architecture · AI-tuning lever set · migration · UX redesign · refactor · code change · contract/API · ops/deploy · 1-line trivial |
| Decision cost-of-being-wrong | reversible / mildly expensive / hard-to-unwind |
| Lever count | 1 (forced move) / 2–3 / 4+ |
| Evidence base | empirical (baseline/data exists) · partial · zero |
| Time-to-ship vs. time-to-grill | ship<grill / ship≈grill / ship>>grill |

Then score **grilling viability**:

- **HIGH** — ≥3 levers, hard-to-unwind, has or could have evidence base, and ship-cost ≥ grill-cost. → Proceed to Gate 2.
- **MEDIUM** — 2–3 levers OR evidence base partial. Recommend a **scoped** grill (1–2 agents, focused on the 1–2 questions actually worth challenging). → Reduced Gate 2.
- **LOW** — forced move, or fully reversible, or zero evidence base, or trivial. → Do not grill. Recommend the alternative.

**LOW-viability alternatives** (suggest whichever fits):
- **"Just ship the small version"** — reversible cheap calls don't need adversarial review.
- **"Get evidence first"** — if claims are unfalsifiable without a batch run, recommend the user run their measurement infrastructure first (e.g. `/eval-batch` in the claim-examiner project, or whatever batch-eval / load-test / metric harness their stack has).
- **"Pick the steel-manned opposite"** — for forced moves where the question is direction not which-lever.
- **"Decide and move on"** — flag that grilling will produce fake objections and waste cycles.

**Output Gate 1 as this exact block:**

---

### Gate 1 result

**Plan type:** <type>
**Cost-of-being-wrong:** <reversible / mild / hard-to-unwind>
**Lever count:** <N>
**Evidence base:** <empirical / partial / zero>

**Viability: <HIGH / MEDIUM / LOW>**

**Reasoning:**
- <3–4 bullets>

**Recommendation:** <Proceed to Gate 2 with N agents | Scoped grill, N agents | Do not grill — <alternative>>

---

## ⏸️ Awaiting Your Decision — Gate 1

Reply with:
- ✅ **"Proceed"** — I move to Gate 2 dispatch
- ✏️ **"Reframe: [your input]"** — I rerun Gate 1
- 🚫 **"Skip grilling, do [alternative]"** — I exit with the alternative recommendation

---

**Wait for the user's reply.** Do not proceed to Gate 2 without explicit approval.

---

## Gate 2 — Dispatch plan

For each lever (or each major claim) in the plan, pick the roles worth dispatching. The eight-role taxonomy:

| Role | Question it owns |
|---|---|
| **Empirical Falsifier** | Does the data actually support this claim? |
| **Code Contradiction Hunter** | Does this proposal collide with existing code or contracts? |
| **Sequencing / Race Critic** | What runs before what? What's in-flight that conflicts? |
| **Cost / Complexity Critic** | Is the engineering estimate honest? What's hidden? |
| **Scope Critic** | Is this the smallest version that solves the problem? |
| **Reversibility / Blast-radius Critic** | If this ships wrong, what's the rollback cost and who breaks? |
| **Steel-manner** | Argue the strongest version of the *opposite* position |
| **Domain Specialist** | Project-specific gotchas (memory-backed) |

**Load `references/role-taxonomy.md` before picking a dispatch** — it has the canonical heuristic dispatch table plus per-role when-to-dispatch / when-to-skip / evidence-required detail.

**Two non-negotiable picking rules** (everything else lives in the reference):
- **Always include Steel-manner** for plans with ≥3 levers — empirically the highest-yield role.
- **Cap parallel dispatch at 5.** Beyond that, aggregation cost dominates. For plans with >10 levers, grill per cluster of related levers, not per individual lever.

**Output Gate 2 as this exact block:**

---

### Gate 2 dispatch plan

| # | Agent role | Single question | Levers in scope | Evidence to cite |
|---|---|---|---|---|
| 1 | <role> | <one sharp question> | <lever IDs or "all"> | <expected evidence type> |
| 2 | … | … | … | … |

**Total agents: <N>** — all parallel-safe (independent scope).
**Convergence rule:** Iterate until one full pass produces no substantive new challenges.

---

## ⏸️ Awaiting Your Decision — Gate 2

Reply with:
- ✅ **"Dispatch"** — I fire N sub-agents in parallel
- ✏️ **"Adjust: [add/remove/refine roles]"** — I revise the dispatch
- 🚫 **"Stop here"** — I exit with the dispatch plan as the deliverable

---

**Wait for the user's reply.**

---

## Gate 3 — Execute + converge

When approved, dispatch all N agents in a **single message with multiple Agent tool calls** so they run concurrently. Brief each agent with:

- The full plan text (or pointer to it)
- ONLY their single question — not the others'
- The evidence type they must cite
- A 200-word response cap to keep aggregation tractable

When all agents return, aggregate into:

```markdown
## Grill output — iteration <N>

### Rejected / deferred

| Lever | Original claim | Verdict | Why | Cited by |
|---|---|---|---|---|
| L1 | "<quoted pitch>" | **Drop** / **Defer** / **Re-scope** | <reason + file:line or baseline ref> | Agent <#> |
| … | | | | |

### Accepted

| Lever | Verdict | Surviving rationale | Cited by |
|---|---|---|---|
| L2 | **Keep** | <reason + evidence> | Agent <#> |

### New questions raised

- <Question agents surfaced that the plan didn't address>

### Convergence

- Iteration <N>: <count> new challenges. <"Converged" if 0, else "Re-grill needed">
```

**Convergence check.** If the iteration produced ≥1 new substantive challenge that changes a verdict, run a second pass with the agents most likely to find more — usually Steel-manner and Code Contradiction Hunter. State the iteration count explicitly. Stop after 3 iterations regardless; further passes produce diminishing returns.

**Hand-off.** Once converged, paste the rejected / accepted tables into the user's planning doc — they're the load-bearing output and survive context compression better than bullet summaries. (In the claim-examiner project specifically, the table becomes the Phase 3 "decision grill" section of `/wave-plan`.)

---

## Bundled resources

- `references/role-taxonomy.md` — Deep cut on each of the 8 agent roles (when to dispatch, when to skip, evidence requirements, anti-patterns, project-specific gotchas) + heuristic dispatch table. **Load during Gate 2.**
- `examples/wave-3-grill-walkthrough.md` — Worked example: real grill on the claim-examiner Wave 3 plan (7 levers, 5 agents, 2 iterations, 4 averted regressions). Reference shape for new grills.
