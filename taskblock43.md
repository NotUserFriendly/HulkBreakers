# Taskblock 43 — AI planning cost: cut the search, not the smarts

*Closes the remainder of BR27.09. Depends on taskblock-42 Passes A–E.*

taskblock-42 relocated this bug rather than fixing it: the log sink, the view rebuild, and the
synchronous batch are all handled, and ~1.7s per unit remains inside `UnitAI.plan_turn`. taskblock-35
Pass A3 already halved that once (2023ms → 974ms) and it grew back, because that fix made each
line-check cheaper while the number of candidate cells kept growing underneath it. **This block attacks
the candidate count and the work per candidate, not the cost of a single check.**

Three changes, staged from exact to lossy, **measured separately**. The supervisor's prior is that all
three are needed; the measurements decide whether the last one is.

**This block unblocks taskblock-42 Pass F.** Verifying six tracer and hit-visual bugs means watching
shots resolve, and the hitch is what makes that unverifiable. F and G follow this block.

---

# PASS A — Early-out on score (exact, no behaviour change)

`_engagement_score` computes the distance penalty first and *then* walks two lines for every candidate
cell regardless of how bad that distance already was: `is_covered_from` and `_ally_in_firing_line`, each
tracing a path from the candidate to the enemy.

Those two terms are **bounded constants** — `COVER_SCORE_BONUS` and `ALLY_BLOCKED_PENALTY`. So once a
cell's cheap terms alone put it far enough below the best complete score seen so far, no line walk can
rescue it, and both walks can be skipped.

`_pick_engagement_position` tracks the running best and passes it in; `_engagement_score` takes a
"can't beat this" threshold and returns early.

**Correctness requirement, and this is the pass's real risk:** enumerate **every** term in
`_engagement_score` that can *improve* a cell's score, and prove their sum is bounded. If any term is
unbounded, or depends on a value that isn't known before the walks, the early-out is unsound and will
silently change which cell wins. Write the enumeration in the report. If a term can't be bounded,
exclude it from the skip condition rather than assuming a bound.

**Acceptance is identical output**, not a perf number: for a set of seeded scenarios, the chosen cell is
the same before and after, for every unit on every turn. The speedup is a side effect.

**TESTS:** a seeded bout produces a byte-identical action sequence with and without the early-out;
the skip actually fires (assert on the count of avoided walks, or the test proves nothing); a scenario
where every cell is equally good still terminates and picks the same cell it used to.

---

# PASS B — Cull the candidate rectangle (approximate)

Score cells inside a rectangle with two corners on the acting unit and its target, rather than every
cell `Pathfinder.reachable` returns. Filter the reachable set; do not replace it as the source.

**Pad asymmetrically.** A couple of cells laterally is right, but a unit whose
`_target_distance(weapon, preferred_range)` is larger than its current distance wants to move *away*
from the target — and those cells sit behind the unit, outside the rect, in the one direction a
symmetric pad is thinnest. Extend the far side of the rect (beyond the unit, away from the target) by
the weapon's preferred range. Without this, an optimization quietly shoves long-range units into knife
fights.

**Always retain the unit's own cell** in the candidate set regardless of the rect — it is the standing
fallback and several branches assume it's present.

**Be honest about the size of this one.** `reachable` is a blob centred on the unit; the rect keeps
roughly the portion facing the target. Commonly a half to a quarter, not an order of magnitude. It
compounds with A and D rather than carrying the block.

**Not identical output** — a cell outside the rect could have won before. Acceptance is behavioural:

- `test_full_mission.gd`'s `MIN_COMPLETION_RATE` holds. That test exists for exactly this and is the
  canary for every behaviour change in this block.
- Report how often the chosen cell differs from the pre-cull choice across the seed sweep. A small
  number is fine; a large one means the rect is cutting cells the AI actually wanted.

**TESTS:** a long-range unit standing inside its minimum range still finds and chooses a cell behind
itself; the unit's own cell is always a candidate; a target diagonally distant produces a rect that
contains the direct approach.

---

# PASS C — Batch plumbing only, no behaviour change

**`squad_id` cannot carry this.** It already exists on `Unit`, but it is the *team* — `0`/`1`,
player/enemy, two rosters in `generate_bout_overlay`, and that meaning is assumed throughout the tests.
A batch is a sub-group within a team and needs its own field.

- **A new field on `Unit`** — `batch_id: int = 0`, where `0` means "independent, plans for itself."
  Default is independent, so nothing changes until a bout deliberately assigns one.
- **An injector verb** to set it, in `BoutInjector` and `DebugVerbs`, so batches are hand-assignable
  when building a bout. **Manual assignment only** — generated missions do not assign batches in this
  block.
- **A view indicator** showing which units are batched, which batch they're in, and which member is
  currently leading. Without this the next pass is unverifiable by eye.

No planning changes here. This pass exists so Pass D can be built against something testable.

**TESTS:** the verb sets and clears batch membership; `batch_id` survives `dup()` and re-registration
(`CombatState.add_unit` re-registers every unit including dead ones — the field has to ride along);
default-zero units behave exactly as they do today.

---

# PASS D — Leader plans, followers follow

## D1. Derive the leader; do not store one

Turn order is not a static list — `CombatState.advance_turn` calls `_fastest_by_initiative(candidates)`
each time. So **the leader is the first member of a batch to take a turn in the current round**, which
is a derived value, not a role.

This matters because it makes leader death free. Storing a leader id would require promotion logic, a
staleness check, and a field to keep in sync across `dup()` and mid-combat spawns. Deriving it means
that when the leader dies, the next-fastest living member is simply first next round and is therefore
the leader — **no promotion code, and nothing that can desync.** Do not add a `leader_id`.

## D2. What each role does

**Leader** — plans normally. Full `_pick_engagement_position` over the (now culled, now early-outed)
candidate set. Pays the real cost, once per batch per round.

**Follower** — skips the positional search entirely:

1. Read the leader's chosen destination from this round's batch plan.
2. Path toward it and pick a decent cell within a small radius of it — a local scan over a handful of
   cells, not a search over everything reachable.
3. Run the ordinary shot decision from there, unchanged.

**Followers keep the cheap "can I fire from where I stand?" check.** Only the expensive positional
search is replaced. A follower that already has a shot should still take it rather than jogging toward
the leader first.

## D3. Lifetime and edges

- The batch plan is **round-scoped** — computed when the leader acts, invalidated at the round boundary.
- **Leader dies mid-round after planning:** followers keep the cached destination for the remainder of
  that round. Simplest option, and it reads correctly — the squad completes the manoeuvre it was already
  committed to, then reorganises next round.
- A batch whose every member is dead is inert; no special handling needed if the plan is round-scoped.

**Acceptance:** `MIN_COMPLETION_RATE` holds, and the report gives measured per-unit planning cost for a
leader versus a follower. If a follower isn't dramatically cheaper, the pass hasn't done its job and the
local scan is too wide.

**TESTS:** a follower's plan does not call `_pick_engagement_position`; a two-unit batch produces one
full plan and one cheap plan per round; killing the leader mid-round leaves followers on the cached
destination, and the next round's leader is the next-fastest living member; a `batch_id == 0` unit is
byte-identical to today.

---

# Measurement

Same discipline as taskblock-42: **the 0ms turn dump, before and after each pass individually.** A
combined figure cannot answer whether the rect earned its behavioural risk, or whether followers earned
theirs. taskblock-35 already demonstrated that a single end-of-block number lets a regrowth hide.

Report the per-unit planning cost alongside the turn-boundary number, since the per-unit figure is what
this block is actually moving.

**BR27.09 stays `Active`** unless the supervisor closes it. Append; do not change status.

---

# Not this block's job

- **The lossy sightline change** — moving to a cell in weapon *range* without requiring a clear line,
  and firing anyway. That returns later as attribute-gated behaviour: a dumb unit gets the cheap check
  and shoots into a wall, a smart one gets the full sightline. It is a **feature**, not an optimization,
  and it is gated on Attributes. Do not build it here, and do not build anything that precludes it —
  where a planner decides how much rigour to spend should end up being one place in the code rather than
  a decision rediscovered per call site.
- **Automatic batch assignment** in generated missions. Manual only.
- **The AI rebuild.** This block is triage on a system that wants replacing; keep the changes legible
  and localized rather than clever, because they are meant to be thrown away.
- taskblock-42 Passes F and G — they follow this block.
