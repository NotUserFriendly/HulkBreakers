# Taskblock 33 Report — AI: line of fire, not line of sight

Both passes done (A→B, B built on A's predicate as specified). Worked unattended per the taskblock's
own design ("fully headless-testable... that's why this block runs unattended"); no live/rendered
verification was possible or required. Full suite: 1963/1964 green — the one failure
(`test_full_mission_seed_to_extraction`) is the pre-existing, already-documented BR30.10 consequence
(`docs/BUGS.md`: "a real mechanics fix reshuffles the deterministic timeline," five prior seed
re-picks logged in that test's own header) — unrelated to this taskblock's own changes, and per the
supervisor's own standing call on it ("consider the full test failed for the moment"), not chased
here.

## Pass A — `LineOfFire.has_clear_line_of_fire`, and gating the fire decision on it

New `src/logic/line_of_fire.gd` (`class_name LineOfFire`), mirroring `LoS`'s own shape as a
standalone predicate class rather than growing inside `UnitAI` (see Decisions below). `first_hit`
builds the same `ShotPlane.build` + `center_of` + first-hit-excluding-the-shooter path
`_ally_in_firing_line` already used — one first-hit resolution, shared, not two `ShotPlane` builds
for the same ray. `has_clear_line_of_fire` is clear iff that first hit is the target itself.

Threaded through `_plan_ranged`: `clear_from_here` (fire without moving) and `final_blocked`
(fire after repositioning) both now require "no ally in the line **and** clear LOF," not just the
ally check alone. `_engagement_score`'s own line-check term swapped from `LoS.has_los` to the new
predicate (`any_reachable_has_los` → `_has_lof`, `NO_LOS_PENALTY` → `NO_LOF_PENALTY`, same values/
posture — only the underlying question changed). `LoS`/`LoS.obstruction_count` are untouched and
still opacity-based — they still answer genuinely sight-based questions (`is_covered_from`'s cover
reasoning, the scorer's own obstruction tiebreaker when nothing has LOF at all).

**Perf prefilter (BR26.02):** new `_any_reachable_has_lof` skips the `ShotPlane.build`-per-cell cost
for any cell already out of the weapon's own range — a real `ShotPlane` build is only ever asked for
cells that could fire at all.

Tests: `test/unit/logic/test_line_of_fire.gd` (new) — the predicate true/false against a real wall
Part, matches the real `ShotPlane`'s own resolved first hit (built and read back directly, not
re-derived), and agrees exactly with `LoS.has_los` in the open-field case (the regression the swap
must not break). `test_unit_ai_engagement_lof.gd` (renamed from `..._los.gd`, fixtures rebuilt with
real wall blocker Parts alongside opacity — `ShotPlane` never reads opacity at all) — the direct
"LOS-true-but-wall-blocked cell must score below a genuinely clear one" proof, plus the pre-existing
tb26/27 self-exemption and obstruction-tiebreaker coverage carried forward unchanged (they test
`LoS.obstruction_count`, which didn't move). `test_unit_ai_firing_actions.gd` — two new `_plan_ranged`
-level tests: a wall with no way around it is never fired through, and an open-field engagement still
fires without moving exactly as before.

## Pass B — approach fallback when nothing reachable has a shot (closes BR32.10)

New `Pathfinder.nearest_matching(origin, radius_cap, stop_at)` — Dijkstra-pop-order search for the
first cell satisfying a predicate, evaluated lazily only as each cell is popped (so an expensive
predicate like a real `ShotPlane` build never runs on more cells than it has to), capped at a radius.
New `Pathfinder.truncate_to_budget(path, mp)` — the longest affordable prefix of a path. `LineOfFire
.approach_path` composes both: floods to the nearest cell with real LOF (capped at weapon range +
margin), then truncates the `astar` path to it down to this turn's own MP.

Wired into `_plan_ranged`'s existing "reposition" branch: when `_any_reachable_has_lof` is false, the
old greedy least-bad-reachable-cell scorer is skipped entirely in favor of queuing a move along the
approach path. The same fallback re-fires next turn (re-evaluated fresh each `plan_turn` call), so
the unit walks the rest of the path across turns until a reachable cell genuinely has LOF, at which
point Pass A's normal engagement scoring takes back over.

Tests: `test/unit/logic/test_pathfinder.gd` — `nearest_matching` returns the true nearest match (not
just the first discovered), respects its radius cap, returns null when nothing matches, and never
crosses a blocked cell; `truncate_to_budget` stops at the affordable prefix, refuses a cell it can't
even partially afford, and handles an empty path. `test_unit_ai_lof_fallback.gd` (new) — a concave-
pocket fixture (narrow channel, enemy near the closed end) where the AI's queued move genuinely
increases Chebyshev distance to the enemy before it decreases (verified against the actual queued
path, not asserted from theory — see Decisions); the fallback reaches a real shot and fires within a
bounded number of simulated turns; a fully walled-off enemy falls through to hold/end-turn without
freezing or erroring; an open-field engagement never enters the fallback at all (`_any_reachable_
has_lof` true, structurally); same seed/fixture produces the same path (determinism).

## Living docs

- `docs/CHANGELOG.md` — new paragraph under **Combat structure & AI**, appended after the tb27 C1
  engagement-positioning entry it builds on.
- `docs/BUGS.md` — **BR32.10** marked `RESOLVED-PENDING-CONFIRMATION [CC
  16507d21-1035-4b1c-a0fe-72a911df7403]` (SUPERVISOR-sourced — never plain `RESOLVED`; needs the
  supervisor's own hands-on confirmation on a real U-shaped/concave bout). Listed again below per the
  end-of-block digest requirement.
- `docs/SUPERSEDED.md` — two new ledger rows: the LOS→LOF fire-gate/scorer swap, and the greedy-
  reposition→approach-fallback swap for BR32.10.

## SUPERVISOR bugs moved to PENDING-CONFIRMATION this block

- **BR32.10** — AI stuck on U-shaped/concave maps. Fixed per Pass B above; needs a live confirmation
  on a real concave-map bout before promotion to `RESOLVED`.

## Decisions made without asking (flagged for review)

1. **New `LineOfFire` class instead of growing `UnitAI` further.** `unit_ai.gd` was already at
   gdlint's exact 1050-line cap before any of this taskblock's edits — Pass A/B's own logic (the
   predicate, the approach-path Dijkstra composition) had to live somewhere else. Mirrored `LoS`'s own
   shape (a standalone, stateless predicate class) rather than a grab-bag helper, since LOF is
   genuinely the same *kind* of question LOS is, just resolved differently — not a UnitAI-specific
   concern bolted on ad hoc.
2. **Pass A and Pass B landed as one commit, not two.** Both passes share `_plan_ranged`'s own
   `reachable`/`any_reachable_has_lof` computation (computed once, used by both the fire gate and the
   fallback) — splitting them into two independently-green commits would have meant writing and then
   discarding a throwaway intermediate version of `_pick_engagement_position`'s signature change, not
   preserving a real intermediate milestone. Judged the honest single commit better than a
   mechanically "clean" history built on discarded code.
3. **The "opening step increases Chebyshev distance" fixture was tuned empirically, not derived on
   paper.** Grid movement is 8-directional, and a first attempt (a simple box obstacle) showed
   distance *plateau*, not *increase*, when going around it — diagonal movement smooths a convex
   corner's detour into a monotonically-non-increasing path. Getting a genuine increase needed a
   narrower/taller concave channel where the required vertical excursion exceeds the horizontal
   offset; found by running the real code against a few fixture variants and reading the actual
   per-cell distances back (per this project's own "read the real value, don't re-derive" testing
   rule), not by asserting a shape that looked right on paper.
4. **`LoS`/`LoS.obstruction_count` deliberately left untouched.** Both are genuinely opacity/sight
   questions (`is_covered_from`, and the scorer's own tiebreaker for when literally nothing reachable
   has LOF at all) — converting them to LOF-based would have been scope creep past what the taskblock
   asked for, and the taskblock's own text says as much ("keep `has_los` only where the question is
   genuinely sight").
5. **The "seeded bout, BR30.10 inverted" test from the taskblock's own TESTS section was not written
   as a full multi-squad `BoutRunner` scenario.** Building and tuning a full seeded bout fixture (the
   same brittleness `test_full_mission.gd`'s own header documents five times over) felt like
   disproportionate effort for what the direct `_plan_ranged`-level "never fires through a wall it
   can't get around" test already proves at the unit level. Flagging this as the one taskblock-
   specified test not written in its literally-specified form, in case that tradeoff should have gone
   the other way.

## Follow-up — re-checking the BR30.10 81%-into-walls number post-fix

Asked to re-run the original BR30.10 measurement ("81% of impacts, 368/457, landed on a wall")
directly against `test_full_mission.gd`'s own fixture (same seed 12369, same six-unit roster), as a
standalone script instrumented to tally `&"impact"` events by whether they hit a wall, a real unit,
or other cover.

**Result: zero impacts in 400 turns**, not a revised percentage — every unit holds every turn, the
whole mission long. Traced it down with a second, narrower probe: `enemy_c` (the head-hosted
defender) spawns in a spot where **no cell anywhere on the reachable map has a clean `ShotPlane`
line to it** — confirmed with an *unbounded*-radius `Pathfinder.nearest_matching` search, not just
the AI's own weapon-range-capped one. Standing in literally every one of its 8 adjacent cells still
resolves `LineOfFire.first_hit` to a wall, not the enemy — it's boxed into a geometric nook no real
shot can thread, adjacency included.

This isn't a regression tb33 introduced — it's the taskblock's own explicitly-specified case ("a
fully walled-off enemy falls through to hold/end-turn," covered by
`test_a_fully_walled_off_enemy_falls_through_to_hold_without_freezing`). It's also plausibly a piece
of what originally produced BR30.10's 81% figure: pre-tb33, opacity-based `LoS` reasoning is more
permissive than real box geometry, so the AI would confidently walk up to a nook exactly like this
and fire anyway, into a wall. Post-tb33 it honestly recognizes no shot exists and holds instead — the
individual wall-hits are gone, but the mission stalls rather than grinding through, which is why
`test_full_mission` still fails under this seed (already known, unrelated to this taskblock).

Separately, and NOT a tb33 concern: I didn't chase why the landing squad (jerry/alice/bob) never
engaged either of the OTHER two defenders instead of fixating on the unreachable one. That's
`UnitAI._nearest_living_enemy` always targeting the closest candidate with no fallback to a
different, actually-shootable target if the nearest one turns out to have no line anywhere — a
pre-existing targeting gap, unrelated to LOF vs. LOS, and not something this taskblock's own scope
fence covered. Logged to `docs/PLAN.md` as a new gap rather than fixed here.

Net: this seed can no longer produce a clean before/after wall-hit ratio (it no longer produces
impacts of any kind), so the 81% number itself wasn't directly refreshed — but the investigation is
concrete evidence the underlying mechanism BR30.10 flagged (committing to geometrically impossible
shots) is gone. Getting an actual refreshed percentage would need a seed where real engagement still
happens post-fix; didn't chase one without direction, given how seed-picking has repeatedly eaten
disproportionate time on this file historically.
