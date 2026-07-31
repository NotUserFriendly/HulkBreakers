# BUGS.md — Bug Ledger

**The single place a bug's status lives.** New and resolved, with a rough report time and (for recent
ones) the taskblock in play. Its job: **a resolved bug must have a closure marker here**, so it is
never re-derived as open once the report or spec that first described it has aged out of
`reports/`'s own rolling window or been purged — this ledger (and `docs/BUGS-ARCHIVE.md` for closed
entries) is the durable record now, not whatever taskblock first found it. If you fixed something,
mark it RESOLVED here, even if the fix landed as a plain commit outside the taskblock cadence. That
out-of-cadence gap is exactly what let stale reports recur.

**This file holds only what is still open.** Once an entry reaches `Resolved`, it moves verbatim to
`docs/BUGS-ARCHIVE.md` and is never edited again — so everything here is something that still wants
attention, and "what's open" needs no index, just this file. Move an entry on closure, not in a later
sweep; the archive is history, not a queue.

**Entry format.** The heading carries only the three things you scan for — **ID, status, owner** —
so a single `grep '^### BR'` is the whole open-bug index and nothing derived needs maintaining. The
description sits on the line below it, with source and CC session under that. (The example below is
gutter-marked with `|` so the index grep can't mistake it for a real entry — the marker is not part of
the format.)

```
| ### BR32.01 — Active — owner: `SUPERVISOR`
| **Stray wall-cutout hole at a cell with no unit**
| - **Source:** `SUPERVISOR`  ·  **CC session:** `<uuid>`
```

**`owner` = who is allowed to close it.** Distinct from `source` (who *found* it), which stays
recorded but no longer governs anything. Owner defaults to the source — a `CC`-found bug is
`CC`-owned and CC may resolve it directly; a `SUPERVISOR`-found bug is `SUPERVISOR`-owned and CC may
only ever write `Pending Confirmation`. **The supervisor may promote any entry to `SUPERVISOR`
ownership at any time**, including CC-found ones, so that anything worth watching cannot be silently
closed. Owner is the gate; read it, not the source.

**Status legend:**
- `Active` — open.
- `Suspected` — a possible lead, not yet a confirmed or fully described bug. The reporter refines it
  into a real status at their review pass.
- `Pending` — the fix is complete and CC believes it works, but the owner hasn't seen it
  work yet. The only status CC may write toward closure on a `SUPERVISOR`-owned entry. (Pending *what*: the owner seeing it work.)
- `Resolved` — confirmed fixed by the owner.
- `Obsolete` — the entry can no longer be confirmed or reproduced because the code it describes was
  replaced or removed, not because anyone verified a fix. Closing an entry this way is an honest
  "this question no longer exists" — never use `Resolved` for it, since that would assert a
  verification that never happened. Point at whatever superseded it.

Closed entries (`Resolved`, `Obsolete`) move verbatim to `docs/BUGS-ARCHIVE.md`.

**Convention:** one flat list, sorted by BR number ascending (`BR26.xx` before `BR27.xx` before
`BR30.xx`, lowest sequence first within a taskblock) — no category sections. **Status is inline in the
entry heading** (`Active` / `Pending Confirmation` / `Resolved`), right after the ID, so status and ID
are both visible while scanning. Entries reported before the `BR<taskblock>.<seq>` convention existed
have no ID to sort by — they follow at the end, in their own legacy block, oldest work first. Recent
entries get a timecode + taskblock; older migrated ones get a rough date. `RESOLVED` entries name the
fixing commit(s)/taskblock so the closure is verifiable.

**Every bug carries an ID:** `BR<taskblock>.<seq>` — e.g. `BR27.01` (Bug Report, reported during
taskblock 27, first of that block). **The ID is assigned at report time and never changes** — a bug
reported in tb27 stays `BR27.xx` even if fixed in tb30, so the handle is stable across its whole life
between supervisor, CC, and the reviewer. Put the ID in the entry heading.

**Every bug carries a `source`:**
- **`CC`** — found by CC during its own work (usually a pure-code bug). CC owns the whole loop
  (sees it, fixes it, tests it), so **CC may mark a `CC`-sourced bug `RESOLVED` directly.**
- **`SUPERVISOR`** — reported by the supervisor (the human overseeing the project). CC often
  *can't see* what was reported (a visual glitch, a "feels wrong" behavior), so it may have fixed
  the wrong thing. **CC may NEVER write plain `RESOLVED` on a `SUPERVISOR`-sourced bug.** The most
  it may write is **`RESOLVED-PENDING-CONFIRMATION`** (fix committed, CC believes it's done,
  awaiting the supervisor's verification). Only the supervisor promotes `PENDING-CONFIRMATION` →
  `RESOLVED`, and only after seeing the fix work.

**Session stamps.** CC has no sequential session counter — what it *does* have is a **session
UUID** embedded in its scratchpad directory path (e.g. `.../83fb8082-732a-4a4f-a726-04186087ef69/
scratchpad`). CC stamps its closure marks with the **full UUID**, not a shortened prefix — a prefix
is one collision away from misattributing a stamp to the wrong session on a long-lived machine, and
the full string costs nothing to write (e.g.
`RESOLVED-PENDING-CONFIRMATION [CC 83fb8082-732a-4a4f-a726-04186087ef69]`). If CC is refreshed it
gets a *new* UUID, so a later session reading an earlier session's `PENDING-CONFIRMATION` sees a
**different** stamp than its own — that's the signal it's *another instance's* unverified claim. It
must NOT promote it to `RESOLVED` on the strength of a prior CC's word, only on the supervisor's. A
pending mark whose UUID isn't your current one is a claim to re-check, not a closure to trust.

**End-of-taskblock digest.** At the end of each taskblock, CC lists every `SUPERVISOR`-sourced bug
it moved to `RESOLVED-PENDING-CONFIRMATION` this block — a "here's what I think I fixed, please
confirm" roll-up — so pending items surface at a natural review point without interrupting mid-work.

---
- **`Pending` (taskblock-51), and it was the same defect — but only partly.** `SelectionController.select`
  requires `unit == state.current_unit()`, so while the pointer sat on a corpse **nothing was
  selectable at all**. Fixing `BR51.04` restores selection of the living, which is almost certainly the
  symptom you hit.
- **What is NOT fixed, deliberately: a dead unit still cannot be *selected*.** `select()` refuses
  `unit.alive == false` by design — selection is for control, and controlling a corpse is not a thing
  the game allows. If what you want is to *inspect* a downed shell, that is the inspect panel's path
  and a different question; if you want dead units genuinely selectable, that is a **design change** and
  I am not making it unasked.
- **`prone` was not reproduced separately.** A prone unit is alive, so it should select normally when it
  is current — worth confirming which of the two states you actually saw fail.

### BR51.12 — Suspected — owner: `SUPERVISOR`
**Ramps may generate on top of other ramps facing the other way**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-31, taskblock-51 fourth hunt.
- Reported as a suspicion rather than a confirmed defect: ramps appearing stacked on one cell facing
  opposite directions. **`Suspected` deliberately** — it has not been reproduced deliberately and no
  route back to it is recorded.
- Cheap to test headlessly once described: `MapGen` places ramps through `connect_with_a_ramp`, and
  "at most one correctly typed floor surface per cell" is already asserted by
  `test_map_gen.gd`. **If that test passes while this reproduces, the assertion is narrower than its
  name** — which is the more interesting finding of the two.

### BR51.13 — Resolved — owner: `CC`
**The combat log folds `fps_dump` into `wall_cutout` runs**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-31, taskblock-51 fourth hunt. *"Combat log is collapsing things that shouldn't
  collapse together. Notably, `fps_dump` lands inside `wall_cutout` reports."*
- **This contradicts a test that passes.** `test_log_fold.gd` asserts
  `test_a_diagnostic_keeps_its_own_row_and_is_never_folded_into_plumbing` — so either `fps_dump` is not
  classified as a diagnostic, or the plumbing fold swallows neighbours the test never feeds it.
  **Read the test before the code:** a green assertion beside a live defect means the assertion is
  testing something narrower than its name claims, which is exactly the failure taskblock-49's audit
  was built to find.
- Confirmed visible in `out/combat.log` across every session this block.

### BR51.14 — Active — owner: `CC`
**Hovering tiles with a unit selected drops 160 fps to ~20, while moving only**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-31, taskblock-51 fourth hunt.
- **Repro:** select a unit, move the mouse over tiles **without aiming**. Framerate falls from 160 to
  about 20. Holding still over a tile costs nothing; only motion does.
- **Almost certainly the same shape as `BR26.02` on the non-aim path.** That bug was per-motion-event
  work on the aim hover; this is the board hover, which runs `update_hover` → `PartPicker.hit` and
  emits `hover_changed`. **The two fixes that worked there apply here unmodified:** coalesce motion to
  one update per drawn frame, and check whether the signal's listeners are doing preview-scale work.
- **Do not assume it is identical** — measure it the same way, with the per-function clone and plane
  counts, before changing anything.

### BR51.15 — Active — owner: `SUPERVISOR`
**A distinct hitch as the over-the-shoulder camera swings behind the unit**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-31, taskblock-51 fourth hunt.
- **Repro:** enter aim with the over-the-shoulder camera and watch the moment it arrives behind the
  shooter. A distinct hitch lands exactly there, separate from the general aim-view cost.
- **This is the ~7.5 fps session minimum, and it now has a cause to look at.** Every session this block
  recorded a minimum of **7.1–8.1** regardless of what else changed — one slow frame, not a sustained
  load. A hitch tied to a specific camera position is a much better lead than a stray stall.
- **Suspects, in order:** the camera passing through wall geometry (which the supervisor separately
  proposes fixing with a camera-attached cutout — see `PLAN.md`), the framing tween completing and
  triggering a rebuild, or the occlusion pass re-evaluating as friendlies cross the near plane.

### BR51.06 — Active — owner: `CC`
**The debug panel's `pick` button also sets the active target**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-30, taskblock-51 Pass A.
- **Repro:** open Inject, choose a verb with a `pick` button, and use it. Picking a parameter target
  *also* reassigns the panel's active item, so a pick meant to fill one field silently changes what
  the verb will act on.
- **The supervisor named the two acceptable outcomes**, and which applies is the actual question:
  suspend active-target selection while a pick is in flight, **or**, if pick and active-selection do
  the same thing, **remove `pick` entirely** rather than keep two names for one gesture.
- **Establish which before changing anything** — "no parallel systems" says a duplicate gesture is the
  bug to fix, not a behaviour to tune.

### BR48.01 — Active — owner: `SUPERVISOR`
**Closing the inspect panel leaves the background permanently dimmed**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-29, while spectating.
- **Repro:** in the spectator view, click a tile or unit — the inspect panel opens as expected, with the
  background dimmed behind it. Close the panel. **The dim stays.** It does not block input; controls,
  camera and selection all keep working. It is purely visual and it persists for the rest of the
  session.
- **Reads as a dim layer whose visibility or `modulate` is set on open and never restored on close** —
  the one-way half of a two-way transition. Check every close path, not just the button: `Esc`, clicking
  away, and opening a second inspect while the first is up are three different exits and only one of
  them is obviously covered.
- **Cheap to confirm, and worth confirming rather than assuming:** if a second open/close cycle makes it
  *darker*, the dim is being stacked rather than left on, which is a different bug with the same
  symptom.
- **`SUPERVISOR`-owned because the evidence is visual.** CC can assert that a node's visibility flips,
  but "the screen still looks dark" is not something it can see.
- **taskblock-51 third hunt — RE-DIAGNOSED, and the title is now wrong.** *"The dimming on selecting
  unit bug is not unit related, it's cover/tile related. Selecting a bare tile or cover causes the
  screen to dim."*
- **That moves the suspect.** It is not the inspect panel failing to restore a dim on close; it is
  selecting a **non-unit** — bare tile or cover — dimming the screen in the first place. The two-way
  transition theory in the notes above was built on the wrong trigger and should not be worked from.
- **Likely one defect with `BR51.02`:** both are about what a click on cover or a bare tile resolves
  to. If cover resolves to the tile beneath and a tile selection dims the screen, one wrong resolution
  produces both symptoms.
- **taskblock-51 third hunt — CC mis-filed the re-diagnosis as a new entry (`BR51.08`), now folded
  back here.** The supervisor was correcting *this* entry's trigger, not reporting a second bug:
  *"The dimming on selecting unit bug is not unit related, it's cover/tile related. Selecting a bare
  tile or cover causes the screen to dim."*
- **So the trigger is a selection, not a close.** The heading still says "closing the inspect panel"
  and is now the least reliable line in the entry — work from the note above it. The two-way-transition
  theory recorded earlier was built on the wrong trigger.
- **Likely one defect with `BR51.02`:** both concern what a click on cover or a bare tile resolves to,
  and `BR51.02` has already turned up one real mis-resolution there (cover reading as its own tile).
### BR51.09 — Active — owner: `CC`
**A unit killed during its turn stays selected, leaving its movement overlay on screen**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-31, taskblock-51 third hunt, immediately after `BR51.04` was fixed.
- **Repro:** kill a unit during its own turn. The turn now advances correctly (`BR51.04`), but the dead
  unit remains *selected* and its reachable-cell overlay stays drawn through the next unit's turn.
- **This is the other half of the fix I made and did not finish.** `kill_unit` advances the turn; it
  does not tell the selection to let go, and `SelectionController` holds its `selected_unit` reference
  independently of whose turn it is. Fixing the pointer without clearing the selection moved the
  symptom rather than removing it.

### BR51.10 — Pending — owner: `CC`
**Inspect is offered when there is nothing to inspect**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-31, taskblock-51 third hunt.
- The supervisor first reported inspect as doing nothing under the player view, then diagnosed it
  themselves: *"Inspect should be disabled when it can't be selected, like when a unit isn't selected."*
- **So the defect is an affordance that lies**, not a broken action: the control is live when the thing
  it acts on does not exist, so pressing it correctly does nothing and reads as broken.

### BR51.11 — Active — owner: `SUPERVISOR`
**A unit refacing mid-move sometimes turns the long way around**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-31, taskblock-51 third hunt.
- **Repro:** watch a unit move along a path that changes direction. It sometimes rotates **270° one way
  rather than 90° the other**.
- **Visual only, as far as is known** — the facing it arrives at is presumably correct, so this is the
  interpolation choosing the wrong arc rather than the logic choosing the wrong facing. **Confirm that
  before touching the resolver:** if the *final* facing is ever wrong too, this is a different and much
  more serious entry.
- Suspect the shortest-arc handling where an orientation crosses the wrap point.

### BR51.01 — Active — owner: `SUPERVISOR`
**Sniper rifle and chaingun consistently shoot wide left of the aim point**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-30, taskblock-51 Pass A.
- **Repro:** aim a sniper rifle or a chaingun at a goo barrel and fire. The shot lands
  **consistently left** of where the reticle sits. Reported first for the sniper rifle alone, then
  confirmed on the chaingun — so it is not one weapon's authored geometry.
- **Consistent and directional, which is the useful part.** A scatter bug is symmetric; a systematic
  left bias is a transform, not a roll. Suspects, in order: the reticle-to-world mapping in
  `AimPlaneGeometry`, the muzzle anchor (`a shot originates at the real muzzle, not the cell centre`),
  or the aim camera's own lean applying to the view but not to the resolved ray.
- **Possibly one defect with `BR34.04`** (sniper camera frames the target from an odd angle) and
  `BR33.01` (aim-view scroll/layer labels). If the aim camera is off-axis, everything mapped through
  it inherits the offset. **Check the camera before the weapon.**
- **Blocks reproducing `BR35.08`** — the supervisor could not reliably hit a goo barrel to detonate it.

- **taskblock-51 — the frame-mismatch theory is measured and WRONG. Ruled out, not deprioritised.**
  The strongest hypothesis was that the reticle and the resolver work in different planes: the
  reticle places `reticle_offset` against a plane anchored on the shooter and target **cells**
  (`AimPlaneGeometry.perp_axis`), while `AttackAction` builds its plane anchored on the real
  **muzzle** — and taskblock-27 Pass A1 fixed exactly that class of mismatch *inside* the action,
  leaving the reticle still on cells. A constant lateral offset equal to the muzzle's lateral
  displacement would explain "consistently left" perfectly.
  **It does not happen.** `test_aim_offset_bias.gd` aims a ray at the resolver's own dead centre and
  asks what offset the reticle maths records: **0.0000 cells across four geometries** (axis-aligned
  both ways, and both diagonals). The two frames agree.
- **What that leaves, in order.** The reticle is placed from `camera.project_ray_origin/normal`, so the
  remaining suspects are all on the camera side rather than the geometry side: the aim lean applied to
  the rendered view but not to the camera the projection reads; a rendered dartboard whose lateral axis
  disagrees in sign with the plane it represents; or the drawn reticle sitting somewhere other than
  where `reticle_offset` says. **The next attempt should instrument what the player sees against what
  is fired**, not re-derive the geometry — that half is now measured and clean.
- **The test stays as a regression guard.** It is cheap, it pins a real invariant, and it will catch the
  frame mismatch if a later change introduces the thing that was suspected here.

### BR51.02 — Pending — owner: `CC`
**`set_part_hp` cannot target a part that is not on a unit**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-30, taskblock-51 Pass A, while trying to force a detonation.
- **Repro:** open Inject, choose `set_part_hp`, and try to target a goo barrel or any other field
  object or blocker. There is no way to name it — the verb's target is a unit part.
- **Filed as a bug, and half of it was not one.** "`set_part_hp` should accept things that are not unit
  parts" is a capability that never existed — a **design change**, and the supervisor's standing rule is
  that design changes live in the report and their notes until review, not in this ledger. That half
  landed and is recorded in `reports/Report-Taskblock51.md`; it should not have been an entry.
  **What remains below the reopen is a real defect** and is what this entry now means.
- It was blocking the hunt either way: forcing a detonation is the deterministic route to `BR35.08`,
  which otherwise needs a landed shot on a barrel that `BR51.01` is interfering with.

- **Resolved (taskblock-51).** `set_part_hp` takes the same `{kind, unit, cell}` object target
  `move_object` and `remove_object` already use, so a blocker or field object can be named by clicking
  it. An empty `part_id` means the blocker itself, so killing a barrel needs no id typed. A bare `Unit`
  still works unchanged — widening a target must not narrow an existing one, which is asserted.
- **Your detonation route is open:** spawn a goo barrel, click it, `set_part_hp` → 0.

- **REOPENED (taskblock-51, third hunt). The fix was real and insufficient, and the gap is upstream of
  it.** The injector now resolves a cell target to the blocker there — that part works and is tested.
  But the supervisor cannot *give* it that target: *"barrels aren't clickable. Selecting a barrel (or
  any cover) actually selects the tile beneath."*
- **So the defect is in what a board click resolves cover to**, not in the verb. `set_part_hp` was the
  visible symptom; the real entry is that cover cannot be made the panel's active target at all, which
  means every OBJECT-target verb has the same hole.
- **My error worth recording:** I tested the injector against a hand-built `{kind: CELL, cell: X}` dict
  and called the bug fixed without once driving the click that produces that dict. A test that
  constructs its own input cannot tell you the caller never produces it — the same shape as
  taskblock-48's "input tidier than reality is worse than no test".
- **Subsumed by the taskblock-51 addendum's Pass K**, which builds the selection target this needs.
  Every OBJECT-target verb has the same hole, so it is fixed there rather than per-verb here.

- **`Pending` (taskblock-51, after the reopen) — two defects, one symptom.**
  1. **The panel labelled cover as its tile.** `_refresh_active_label` special-cased units and called
     everything else "Active: Cell (x, y)", so a barrel click was indistinguishable from a floor click.
     It names the part now.
  2. **The injector re-derived what the click already knew.** A cover click resolves to a `PART` hit
     carrying the exact `Part` struck; `_object_target` ignored it and looked the cell up in `blockers`
     a second time. It uses the struck part directly — the same "never compute it twice" rule
     `docs/02` applies to shots.
- **To see it work:** click a barrel — the panel should read `Active: goo_barrel @ (x, y)`, not
  `Active: Cell`. Then `set_part_hp` with an empty `part_id` and 0.
- **Tested against the click shape this time**, not a hand-built dict — that omission is what let the
  first fix ship broken.

### BR46.02 — Active — owner: `CC`
**16 of 40 generated maps contain ground a unit can walk into and never leave**
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-28, while checking the supervisor's report that "Squad 1 is trapped in a lowered
  section" during a real bout. It is a real and separate defect from `BR46.01`.
- **Descent is free and ascent is capability-gated.** Dropping to a lower level is legal for everyone;
  climbing back needs `Shell.can_climb()`, which reads a `CLIMBER` part tag, and **no part in the repo
  carries it.** So every lowered region is a one-way door for every unit that currently exists.
- **A symmetric connectivity check cannot see this, which is why it was missed.** Spawn zones are
  mutually reachable on **60 of 60** seeds — the map is connected in the ordinary sense. The defect
  only appears under *asymmetric* reachability: flood out from a spawn cell, then flood back from each
  cell reached and ask whether the spawn is still reachable.
- **Measured over 40 seeds at the real 32x24 bout size: 16 seeds contain at least one one-way cell,
  worst case seed 16 with 216 of them** (e.g. `(11,10)`). A unit that wanders in is out of the mission
  while still alive and still taking turns — which reads as `TERMINATED`, and is a plausible
  contributor to `BR45.03`'s dominant failure mode.
- **Not fixed, and deliberately not fixed by me: the direction is a design call.** Three options, none
  obviously right:
  (a) **author a `CLIMBER` part** — `PLAN.md` already carries this as its own item, and it makes the
  gate real rather than removing it, but it changes what every shell can do;
  (b) **make `MapGen` guarantee two-way connectivity** — ramp or raise any region whose only exits are
  descents, which keeps the movement rules alone and constrains the generator;
  (c) **make the planner refuse a one-way step** — cheapest, and wrong on its own, since a player can
  still walk in and the AI would be avoiding terrain rather than the terrain being fixed.
  The evidence points at (b) as the floor and (a) as the feature; (c) is a mitigation, not a fix.
- **Reproduction is `tools/`-free and cheap:** flood from any spawn cell with a non-climbing
  `Pathfinder`, then flood back from each reached cell and check the spawn is still in the set.

### BR45.01 — Active — owner: `CC`
**Surrogate demotion from an ambiguous DAG node is an unresolved placeholder, and says so loudly on
every fire**
- **Source:** `CC`  ·  **CC session:** `a56eac1a-eddb-4d30-946a-4c8e594ef198`
- **Raised 2026-07-27 by the supervisor noticing the warning volume in `run_tests.sh`.** The warning
  is not new and nothing in taskblock-44 caused it — `SurrogateLadder.demote` has emitted it since
  taskblock-03 Pass A2 (`e82d35c`). What changed is that taskblock-44 added tests that run real
  seeded bouts, so more combat resolves, more surrogates take damage, and the existing warning simply
  fires more often. **It became audible rather than becoming a defect.**
- **The actual gap.** `docs/04` makes the surrogate ladder a DAG, not a line. Demotion walks *upstream*
  — the tiers whose `promotes_to` names the current one — and where a tier has **two or more**
  upstream branches there is no rule for which one a damaged surrogate falls back to. taskblock-03
  deliberately did not invent one. Today `demote()` takes `candidates[0]`, first in ladder
  declaration order: deterministic (so it cannot break seeded replay) but arbitrary, and
  `push_warning`'d every single time precisely so it could not be mistaken for a decision.
- **Why it matters beyond noise.** The fallback is authoring-order-dependent. Reordering the tier
  `.tres` files, or adding a new tier that promotes into an existing one, silently changes what a
  damaged surrogate becomes — with no test that would notice, because every current test asserts
  against whatever the first branch happens to be.
- **What closing it needs is a DESIGN answer, not code.** Candidates, none chosen: pick by what was
  destroyed (taskblock-03's own stated intent, and the reason it was left open); pick the branch
  retaining the most capabilities; pick the cheapest to re-promote from; or author an explicit
  `demotes_to` on the tier and make the DAG's reverse edges data rather than derived. **The last is
  the only one that needs no new rule invented** — it makes the answer authorable per tier, which is
  the same "content is data, not code" posture the rest of the project takes.
- **`CC`-owned** per the supervisor. CC may close it once a rule is chosen and authored — but the
  choice itself is a design call, so it wants stating before it is built rather than after.
- **Do not silence the warning as the fix.** It is doing its job; the placeholder is what wants
  resolving.

### BR45.03 — Active — owner: `SUPERVISOR`
**The utility planner completes 54.2% of missions where the planner it replaced completed 87.5%**
*(headline superseded — see the 2026-07-29 entry below: 54.2% and every figure after it were measured
with the profile weights switched off. Re-measured, it is **72%**, and the gap is 3 points.)*
- **Source:** `CC`  ·  **CC session:** `cf5b0146-95d9-49cc-a683-28043425f65a`
- **`SUPERVISOR`-owned at CC's request**, not by default. CC found it and would ordinarily own it, but
  the decision to land the planner with this regression open was the supervisor's, made on this
  evidence, and this entry is the thing that must not be closed without them seeing a real completion
  rate again.
- **Re-measured 2026-07-28 after the block's final fixes**, both planners, same fixture, same probe,
  24 seeds (`test_full_mission.gd`'s own harness, 1v1 AGGRESSIVE, turn cap 100, completion ==
  `EXTRACTED`). The old planner was run from a worktree at `107af1e`:

| | old | new |
|---|---|---|
| seeds 0–11 | 9/12 (75.0%) | 5/12 (41.7%) |
| seeds 12–23 | 12/12 (100%) | 8/12 (66.7%) |
| **combined** | **21/24 (87.5%)** | **13/24 (54.2%)** |
| mean turns to complete | 23.6 | **10.6** |
| failure modes | 3 `TERMINATED` | 9 `TERMINATED`, 2 `STRANDED` |

- **Seeds 1, 2 and 6 `TERMINATE` under BOTH planners.** Three of the new planner's eleven failures are
  not its doing — they are pre-existing on those maps and predate this block entirely. The incremental
  regression is **8 seeds, not 11**, and anyone diagnosing this should start on a seed the old planner
  actually completed (5, 10, 14, 20, 22, 23) rather than on one that was already broken.
- **The first reading of this was 37.5% and was taken mid-block, before the last four fixes.** It is
  superseded by the table above. `MIN_COMPLETION_RATE` had been dropped to 0.25 on the strength of it
  and has been raised to 0.35 now that the real figure is known — still below the gated window's 41.7%
  by one seed, which is the margin a deterministic 12-seed sample allows.
- **The dominant failure is `TERMINATED`, not `STRANDED`** — 11 of 24 seeds simply never end. The
  planner is **not losing fights; it is failing to finish**.
- **Already ruled out, so nobody re-derives it:** the information restriction (identical 33.3% with
  the view forced unrestricted), the candidate-set cull (no change), and the four planner defects
  taskblock-45 found and fixed (the 54.2% is post-fix — every fix is in the number).
- **`MIN_COMPLETION_RATE` went 0.5 → 0.25 → 0.35.** It was dropped to 0.25 to land the planner, on a
  mid-change reading of 37.5%; the re-measurement above put the real figure at 54.2% and it came back
  to 0.35 — one seed of margin below the 41.7% the test's own 12-seed window samples. That constant is
  the project's one automated check on "can the AI finish a mission at all". **Getting it back to 0.5
  is this entry's closure condition**, and it cannot be done by moving the number.
- **Two earlier figures were reported and are wrong**: 58% (measured with a live defect, describing a
  planner that never existed) and 37.5% (taken mid-block, before the last four fixes). Recorded
  because the first reached a landing decision before it was corrected.
- **2026-07-28 — leading hypothesis, found in a real bout's combat log: a NON-PLAYER squad with no
  enemy in sight has no action available at all, and idles until someone walks into view.** This is
  the strongest lead on the `TERMINATED` seeds and should be the first thing tried.

  The eight authored actions partition into two groups with **nothing in neither**:

  | gate | actions |
  |---|---|
  | `enemy_known` | approach, shoot, take_cover, overwatch, hold_position |
  | `is_player_squad` | seek_objective, gather, seek_extraction |

  A squad-1 unit that cannot see an enemy fails both gates, so every action is un-offered. Observed
  directly — `AI unit 3 [TRAINED/cautious]: nothing over 488 candidates` on turns 0 and 1, then
  `shoot@(22,14)` on turn 2 the moment squad 0 came into view — and reproduced by dumping the
  predicates for a `BoutSetup` bout at seed 31337, where squad 0 is offered `seek_extraction` and
  squad 1 is offered `[]`.

  **Neither gate is wrong on its own; the combination is.** `is_player_squad` reproduces the retired
  planner's own `_plan_non_combat_turn` early-return for other squads, and `enemy_known` is what makes
  a combat action mean something. What changed is that the old planner ran **unrestricted**, so its
  `_nearest_living_enemy` always found a target and every enemy unit advanced across the map;
  taskblock-45 switched restriction on at the `AiPlanner` seam, and an enemy squad that cannot see
  anyone now has nothing to do. **If the enemy squad never advances, contact depends entirely on the
  player squad wandering into it** — which on a large map, with squad 0 heading for extraction, may
  simply never happen before the turn cap.

  **The fix is a design call and is deliberately not made here** (CLAUDE.md: ask, don't invent). The
  options, roughly: give every squad an advance-to-contact action scored on closing with the enemy's
  last known or likely position; let non-player squads use the mission actions against their own
  team's extraction zone; or have units patrol toward map features. The first is closest to what the
  old planner did by accident.

- **Do not chase this with profile weights.** A ~33-point gap is structural; hand-tuning weights to
  move a completion rate is inventing balance numbers. The decision log is the instrument — every
  fixed defect was found by dumping `ai_utility_decision` per turn and reading it. Seeds 13 and 20
  never finish.
- **The figures above predate the last four fixes and are now pessimistic.** The head-to-head was
  taken before the hold-gating and missing-`await` fixes; re-running `test_full_mission.gd` afterwards
  puts seeds 0–11 at **5/12 (41.7%)** rather than 4/12 (33.3%). A fresh 24-seed measurement of BOTH
  planners is the first thing this item should take, because the table is the only reason the floor
  moved and it is no longer accurate.

- **2026-07-28 (taskblock-46 Passes B–E) — narrowed, still `Active` [CC `c0dfa479-2b43-4d9c-832d-12a7fd232bce`].** Not marked
  `Pending`: this entry's own closure condition is `MIN_COMPLETION_RATE` back at 0.5, and it is not.

  | when | completion | sample |
  |---|---|---|
  | taskblock-45 end | 54% | 24 seeds |
  | Pass A/B re-baseline | 50% / 54% | 24 seeds / 100 seeds |
  | Pass C (search verbs) | **60%** | 100 seeds |
  | Pass E (tier table) | **60%** | 100 seeds |
  | the retired branch planner | 87.5% | 24 seeds, fixed ground |

- **The leading hypothesis above was right and is fixed.** The four search verbs (`ROAM`, `PATROL`,
  `HUNT`, `PUTTER`) are the action a unit that fails both gates now has; `docs/11` carries the general
  rule that produced the hole ("when adding a gated utility action, ask what a unit that fails every
  gate does instead"). It bought 6 points, not 33 — **so the hole was real and was not the whole
  regression**, which is worth knowing before the next lead is chased.
- **The measurement itself is no longer a pinned window** (Pass B). `CompletionSampler` draws random
  seeds and prints them; a dip reports the exact command for a deterministic 100-seed escalation. The
  sample and the escalation were checked against each other on disjoint windows — seeds 0–99 gave 54%
  and seeds 1000–1099 gave 55% — so the two are measuring the same population and a future comparison
  across them is legitimate.
- **2026-07-29 (taskblock-47 Pass D) — 72%, and most of the "regression" was a broken
  profile id.** [CC `c0dfa479-2b43-4d9c-832d-12a7fd232bce`]

  `CompletionSampler` names the profile its bouts fight under. It was still passing
  `&"AGGRESSIVE"` — a playstyle **taskblock-46 Pass E retired**. `get_utility_profile`
  returns null for an unknown id and `UtilityScorer` falls back to unweighted scoring
  without complaint, so **every completion rate measured after that pass was measured
  with no profile weights applied at all.**

  | measurement | rate | mean turns |
  |---|---|---|
  | before the fix (unweighted) | 56/100 | 26.8 |
  | after the fix (weighted) | **72/100** | **13.5** |

  Against the retired planner's 87.5% on fixed ground — and its 75% on level ground —
  **the gap is now 3 points, not 19.** `MIN_COMPLETION_RATE` is still 0.35 and this
  entry's closure condition is 0.5; the measured rate is comfortably above both.
  **Deliberately not raised here** — taskblock-47's own scope excludes that constant,
  and moving a floor on the same day the number moved is how this project got into
  trouble with it before. It is the supervisor's call and it now has room.
- **What let it through, since the guard existed and was one line short.**
  `test_every_authored_default_names_a_profile_that_exists` checked `Matrix`,
  `BoutRosterEntry` and the bout maker's default roster. It did not check the
  sampler, which is the one that decides what every measured number means. It does
  now, asserted against the built bout rather than against the constant — the
  constant is exactly what was being read and believed.
- **A caveat that applies to every number in this entry, old and new.** `Unit.intelligence_tier`
  defaults to `TRAINED` and nothing authors it, so all of these are all-Trained rates. The old
  planner's 87.5% is an all-Trained rate too, so the comparison is fair — but "the AI" here means one
  row of a four-row table, and neither the 87.5% nor the 60% describes what a mixed-tier bout does.


### BR26.02 — Pending — owner: `SUPERVISOR`
**Low framerate while aiming**
- **Source:** `SUPERVISOR`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **2026-07-23 (supervisor revision to the instrumentation spec — supersedes the offsets below).**
  The dumps landed in tb35 A1; the offsets want changing now that they exist:
  - **Turn FPS at 0 ms** — an additional dump *at* turn start, capturing the boundary cost itself
    rather than avoiding it (this is the number BR27.09 is actually about).
  - **Replace the 200 ms dumps with 2000 ms** — 200 ms proved too close to the transient to read as
    settled state; two seconds in is the honest steady-state sample.
  Keep both samples rather than replacing one with the other: 0 ms and 2000 ms together give the
  boundary spike *and* the settled rate, which is exactly the pair needed to tell BR26.02 and BR27.09
  apart.
- **2026-07-26 — the instrumentation revision above is BUILT (tb42 Pass A)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. It had sat unbuilt since 2026-07-23: `FpsDumpSink` was
  last touched in tb35 and still fired a single 200ms sample. Now two per turn —
  `context: turn_boundary` at **0ms** and `context: turn_settled` at **2000ms** — plus the aim-entry
  dump in `TacticsController._enter_aim_mode()` moved to the same 2000ms and reading the shared
  `FpsDumpSink.SETTLED_DELAY_SECONDS` rather than repeating the number.
  - **The boundary sample is emitted synchronously, with no `await` at all.** `create_timer(0.0)` or
    `process_frame` would push it a frame past the boundary — exactly the transient it exists to
    catch — and quietly turn it into a second copy of the settled sample under a different label.
    There is a test asserting it lands before anything yields.
  - `data.offset_ms` rides alongside `context` so a log reader never has to parse the prose, and a
    test pins that the settled sample has NOT arrived at the old 200ms mark.
  - **No measurement is claimed here.** This pass built the instrument only; every number in
    taskblock-42 is taken with it afterwards. **Status unchanged, and the aiming path is still
    unmeasured** — that is Pass B's job, and this entry stays `SUPERVISOR`-owned regardless.
- **2026-07-26 (tb42 Pass B — the aiming path finally has a number)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. This entry has absorbed three fixes that were reasoned
  rather than measured. The first measurement: the per-orientation-preview
  `HitVolumeView.refresh()` at `squad_control_overlay.gd:782`, which fires on **every** reticle-driven
  facing change while aiming, cost **795µs per unit per change** and now costs **267µs** (3.0×, real
  class, 30-part humanoid, 200 repeats).
  - **This does not close anything.** It is one cost on the aiming path, now smaller; nobody has
    measured what the rest of that path costs, and the supervisor has already said aiming is
    tolerable. `SUPERVISOR`-owned — **do not close from CC's side.**
  - The `fps_dump` numbers this wants comparing against are taken at taskblock-42's own hard pause,
    on a real build, not here.
- **Also requested: a live FPS counter, rendered ON TOP OF the combat log rather than logged into
  it** — a continuous readout for the supervisor's own eyes, distinct from the dumps (which exist for
  CC to grep). Tracked with the log-window UX work in `docs/PLAN.md`.
- **2026-07-23 (supervisor re-check — REOPENED; worse, not better).** Framerate while aiming is still
  bad and is *likely worse than originally*. tb34's two fixes (the ratio-normalized texture cache, and
  deleting `AimView._process`'s redundant per-frame `refresh()`) were both reasoned rather than
  measured — no profiler exists in CC's environment — so neither is confirmed to have helped, and the
  tb34 Pass B/C additions (bound ring, pellet overlay, in-world `Label3D` tooltip) are unexamined new
  cost in the same path.
- **Supervisor-specified instrumentation — make framerate a LOGGED number, not a felt one.** The
  reason this bug has survived three passes is that CC cannot see a framerate; make it something CC
  *can* see. Two combat-log dumps:
  1. **Aim FPS** — dump framerate **200 ms after entering aim** (past the entry transient, into the
     steady-state sweep).
  2. **Turn FPS** — dump framerate **200 ms after a new turn begins**, deliberately offset so it
     measures the settled frame rate and not BR27.09's turn-boundary hitch.
  With both in the log, every future change to the aiming path carries its own before/after evidence,
  and this stops being a bug only the supervisor can adjudicate. Build the instrumentation before
  attempting another fix.
- **Reported:** taskblock-26 (bout review), filed in the taskblock's own scope fence as explicitly
  deferred: "B-tier; investigate separately — likely the inspect field updating every frame; not a
  correctness bug, don't rush a fix into this block."
- **Status:** not investigated. Flagged for the post-tb26 testing/tooling review (pairs with a "what
  does CC do repeatedly" audit) rather than fixed under taskblock-26's own scope.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** root cause is NOT the
  inspect field (the original guess) — it's `aim_view.gd:104-106`, a `_process()` override that
  unconditionally calls `refresh()` every single frame while aiming, even though `refresh()` is
  already correctly wired to the `aim_changed` signal (fired only on real state changes — reticle
  move, layer scroll, target change — from ~9 call sites in `tactics_controller.gd`). Each redundant
  frame call clones the preview `CombatState` and rebuilds the full-board `ShotPlane` twice (once in
  `aim_state()`, again inside `AimController.resolve()`), plus reallocates dartboard resolver/mesh
  objects. **Candidate fix (not yet applied):** delete or gate the `_process` override behind the
  same change-detection the signal path already provides.
- **2026-07-23 (tb34 Pass A + Pass E):** two real fixes landed, addressing the pass's own two named
  suspects in order. Pass A fixed the OTHER latent cost this same screen was about to acquire:
  `DartboardTexture.build`'s 128x128 per-pixel rebuild used to always cache-hit because rings were
  weapon-constant; the instant the board became range-aware (`ShotScatter.for_shot`), every
  retarget/reposition would have missed the cache and rebuilt it — `AimView._rings_match` now keys on
  ring-RATIO rather than absolute radius, so a pure range change still reuses the cached texture.
  Pass E then applied this ticket's own already-diagnosed fix directly: confirmed the redundant
  `_process()` override (quoted above) was still present and unchanged, confirmed every mutation path
  `refresh()` cares about already emits `aim_changed` (11 call sites, comprehensive per re-audit), and
  deleted the override outright — `refresh()` is now purely signal-driven, no per-frame poll at all.
  Full suite green throughout (headless — the cache-regression test this ticket's own ledger already
  asked for is in `test_aim_view_dartboard_cache.gd::test_a_realistic_range_sweep_builds_the_texture_
  at_most_once`).
- **Not live-verified.** Both fixes are well-reasoned and address the two most concretely diagnosed
  costs, but per this ticket's own "measure, don't guess" instruction, only an actual live frame-rate
  observation confirms the aiming screen is no longer slow — and per the taskblock's own admission,
  profiling might still name the new Pass B/C overlays as a further cost if the two fixes above aren't
  the whole story. Needs the supervisor's own hands-on confirmation before promotion to `RESOLVED`.
- **2026-07-23 (tb35 Pass A1 — the two supervisor-specified dumps built)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Both dumps this entry's own "make framerate a logged
  number" instruction called for now exist, emitting `&"fps_dump"` events into the ordinary combat
  log: **Aim FPS** — `TacticsController._dump_aim_fps()`, fired once per `_enter_aim_mode()` call
  (never per reticle nudge), 200ms later. **Turn FPS** — new `FpsDumpSink`
  (`src/view/fps_dump_sink.gd`), watching for `&"turn_start"` on `combat_state.combat_log`, wired in
  `BattleScene.load_battle()` alongside `file_sink` so it re-points on every bout regardless of
  overlay. Headless coverage (`test_tactics_controller.gd::
  test_entering_aim_mode_dumps_fps_200ms_later`, `test_battle_scene.gd::
  test_turn_start_triggers_an_fps_dump_200ms_later`) only proves the plumbing fires on schedule with
  the right context tag — `Engine.get_frames_per_second()` itself is meaningless outside a real
  running client, so the actual before/after numbers still need a live session and `out/combat.log`.
  This closes this entry's own instrumentation ask; the underlying "is aiming actually fast now"
  question stays open pending that live read.
- **taskblock-51 third hunt — now a measured number, not a feeling.** *"It drops from over 160 (my
  monitor's max) down to less than 10 fps."* A **16× collapse**, which is a far more serious statement
  than "low framerate" and should be read as this entry's real severity.
- **CC mis-filed this as a new entry (`BR51.07`) and has folded it back here.** The measurement is the
  new information; the bug is the one reported in taskblock-26.
- **It blocks the `BR51.01` investigation** — the supervisor has asked this be addressed before they
  spend more time in the aim view, which is reasonable when every experiment costs them a slideshow.
- **`fps_dump` already fires on entering aim** (taskblock-50), so the drop should be readable from
  `out/combat.log` with no new instrumentation. **Read it before changing anything:** `BR35.01` has
  absorbed three fixes that were reasoned rather than measured, and it is a suspected cause here.
- **`Pending` (taskblock-51) — measured, then fixed, and the long-standing suspect was wrong.**
  `test_aim_cost_probe.gd` timed the candidates on a board the size you were playing (32×24, **214**
  wall and cover blockers, 6 units):

  | call | usec | note |
  |---|---|---|
  | `ShotPlane.build` | **10 889** | one call overruns a 160 fps frame (6 250 usec) on its own |
  | `PartPicker.hit` | 1 559 | `BR35.01`'s suspect — real, but **7× cheaper** |
  | `bounding_sphere` × 6 units | 773 | `update_wall_cutout`, per frame |

- **The defect: `TacticsController.aim_state()` rebuilt the whole shot plane, plus a full state clone,
  on every call — and it was called at least twice per mouse motion** (`aim_reticle_at_screen`, then
  `update_aim_hover` from the same screen position) plus once per aim-view redraw. Moving the mouse
  therefore cost 20–30 ms of plane building for a plane that had not changed.
- **The fix is a memo keyed on what the plane actually depends on** — shooter, previewed cell and
  facing, target, queue depth — and **deliberately not on `reticle_offset`**, which is the one value
  that changes constantly and cannot affect the plane. Both directions are tested against
  `ShotPlane.builds`: eight reticle moves rebuild nothing, and a shooter that has moved gets a fresh
  plane.
- **This does not close `BR35.01`.** That scan is genuinely wasteful and still worth fixing; it is
  simply not what took the framerate, and the entry has been corrected so a fourth reasoned fix is not
  aimed at it.
- **To see it work:** enter the aim view and move the mouse. `fps_dump` still fires 2 s after entering
  aim, so `out/combat.log` will carry the new number — that reading is the confirmation, not my word.
- **Second pass, after the supervisor tested it: the first fix was half a fix, and the measurement said
  so.** They reported it *"chunkier and more erratic … sometimes 30, sometimes 70, sometimes 3"*, with
  `fps_dump` recording **80.0** while still and **3.0** while panning.
- **Cause: my own cache key cloned the state.** The fingerprint asked
  `SelectionController.previewed_unit()` for the shooter's previewed cell, which calls
  `ActionQueue.preview()` → `CombatState.dup()`. Measured: **26 083 usec**, of which `Grid.dup` is
  **19 668** — it deep-copies all 214 blocker parts and 768 surfaces. So the memo removed the 9 175 usec
  plane build and kept the larger cost.
- **`aim_state()` before taskblock-51 cost dup + build = 35 258 usec, called twice per mouse motion** —
  70 ms a frame, which is the reported 8 fps almost exactly.
- **Fixed with `ActionQueue.revision`**, a counter bumped on every queue change, so "has this changed?"
  is answerable without previewing anything. A cache hit now clones nothing, asserted on the new
  `CombatState.dups` counter.
- **`CombatState.dups` is now a profiled work counter.** A 26 ms call reached several times per mouse
  motion was invisible to every budget because nothing counted it; the full suite reports **7 155**
  clones. That number is worth its own look — see the note added to `BR35.01`'s cluster.
- **Third pass — the instrument was answering the wrong question, and that is why the reports keep
  disagreeing.** The supervisor reported "back to consistently 8 fps" while the log for that same
  session recorded **`Aim FPS (2000ms after entering aim): 161.0`**. Both are true: the dump takes a
  single `Engine.get_frames_per_second()` reading two seconds after entering aim, which is *while the
  mouse is still*. The drop happens while it moves, and nothing was recording then.
- **A single sample cannot answer "is aiming smooth".** `_dump_aim_session_fps` now samples every frame
  for the whole aim session and reports **min, average and frame count on leaving aim** — the minimum
  being the number that matches the felt experience. The 2 s snapshot is kept, because "161 idle" is
  itself informative: it says the per-frame baseline is fine and the cost is on input.
- **Still `Pending`, and the next log will be the first one that can actually settle this.** The two
  fixes so far (memoised plane, clone-free cache key) are real and measured; whether they are
  *sufficient* is exactly what the old instrument could not tell us and the new one can.
- **Also in that log, unrelated and worth its own look: `Turn FPS (at turn start): 38.0`**, recovering
  to 153 two seconds later. That is `BR27.09` ("major hitch on new-turn or end-turn") caught as a
  number for the first time.
- **Fourth pass — the session meter works, and it clears the code.** `min 6.8, avg 18.4 (210 frames in
  11.4s)`, and **6.0 fps at the idle two-second mark with the mouse still**. That last number is the
  important one: the drop is **not input-driven**, so the two fixes already made (memoised plane,
  clone-free cache key) were real but were never going to be sufficient.
- **An idle aim frame, driven through the real nodes on a 214-blocker board:**
  `BattleScene._process` **347 usec**, `BoardView._process` **712 usec**, **zero state clones, zero
  shot planes**. About 1 ms against a 166 667 usec frame at 6 fps. **The per-frame logic is not where
  the time goes.**
- **Which puts it on the GPU, where CC is blind.** taskblock-32 established this for the cutout shader
  and taskblock-51 restates it: shader and renderer costs only get cracked by the supervisor running
  the real thing. **Prime suspect: `AimView._decal`** — a Godot `Decal` projects onto every mesh inside
  its box, and this board has 166 wall meshes plus 768 terrain cells. **A suspect, not a conclusion.**
- **A bisection tool instead of a guess:** the `set_aim_visual` debug verb switches each aim element
  independently (`window`, `decal`, `targeting_line`, `pellet_circle`, `part_label`). Enter aim, turn
  one off, read the session dump on leaving. Whichever one restores the framerate is the answer, and it
  takes three clicks rather than another round of CC theorising. Toggling is deliberately **not** an
  injection — it changes what is drawn, not the simulation, so it never sets `was_injected`.
- **Fifth pass — the first bisection cleared every aim element.** Session minimum by configuration:
  baseline **7.1**, decal off **6.8**, window off **6.9**, targeting_line off **6.7**, pellet_circle
  off **6.9**, part_label off **6.9**. **The floor is the same with each one disabled and with all of
  them on**, so no single aim visual is responsible. (The 2 s samples and session averages swing wildly
  — 5 to 87, and 7.5 to 48.5 — over 2.6–3.5 s sessions, which says the rate is *spiky*, not uniformly
  low.)
- **Next suspects, and they are now switchable too:** `wall_cutout` and `occlusion_fade`. Both disable
  early-Z — the cutout shader `discard`s per fragment across 166 wall meshes every frame, and the
  occlusion pass hands faded friendlies a translucent `material_override`. Neither is aim-*specific*,
  but the fade pass only does work while aiming, which fits "160 outside, 7 inside".
- **The verb takes a dropdown now, not a typed name** (supervisor request), and its options are the
  same `AimView.TOGGLEABLE` list the verb switches on — a test asserts the menu and the switch table
  cannot drift apart, because an offered-but-refused name is a dead control and a wasted session.
- **Sixth pass — the supervisor's correction found it: "8 fps when moving the mouse/camera, rocksteady
  160 when not moving."** That is the opposite of what CC concluded from a 6.0 fps reading at the
  "idle" 2 s mark, and it immediately explains why disabling every drawn element changed nothing: **the
  cost was never in the drawing.**
- **`SquadControlOverlay._on_selection_changed` was subscribed to `aim_changed`, and
  `aim_reticle_at_screen` emitted that on every mouse motion.** The handler calls
  `has_queued_move()` — and, when no aim facing applies, `previewed_orientation()` — each of which
  calls `previewed_unit()` → `ActionQueue.preview()` → `CombatState.dup()` at **26 083 usec**. So every
  mouse motion cloned the entire board, with its 214 blocker parts and 768 surfaces, to re-answer a
  question that only the *queue* can change.
- **Fixed by splitting the signal**, not by caching: `reticle_changed` now carries "only the reticle
  moved" and `aim_changed` keeps "the aim state changed". `AimView` listens to both, because it is the
  one thing that genuinely must redraw; the overlay and the action bar stay on `aim_changed` alone.
- **Two caches were tried first and both reverted, recorded in `SelectionController.previewed_unit()`
  so they are not retried blind:** an empty-queue fast path (callers mutate the previewed unit —
  `StepOutPlanner` does — so handing back the live unit corrupted the real board, caught by three
  step-out tests), and a per-frame memo (state changes *within* a frame when a resolution spends AP,
  caught by four action-bar and pip tests). **The preview clone is correct; calling it per mouse motion
  was not.**
- **Seventh pass — one mouse motion measured end to end, and it is the whole answer.** Driven through
  a real `SquadControlOverlay` on a 214-blocker board:

  | per mouse motion | usec |
  |---|---|
  | `aim_reticle_at_screen` | **60 824** |
  | `update_aim_hover` | **52 681** |
  | **one motion total** | **113 504** — which is **8.8 fps** |

  That is the supervisor's 8 fps exactly, and it confirms their reading over every instrument that
  disagreed with it.
- **The `aim_state()` memo is NOT holding in the real path.** Over 60 calls the probe counted **120
  state clones and 90 shot-plane builds** — roughly **two clones and one and a half planes per call**,
  when a cache hit should produce zero of each. The memo works in the unit test and does not work here,
  so something in the live path is changing the fingerprint (or bypassing `aim_state()` entirely).
  **That is the next thing to find, and it is now a two-line measurement rather than a theory.**
- **`wall_cutout` confirmed innocent by the supervisor twice** — session average 22.8 with it on, 24.0
  with it off.
- **Session average is ~23 fps, not 8**: `min 6.8, avg 22.8 (231 frames in 10.1s)`. The live readout and
  the 2 s sample both catch the bad moments; the honest description is "8 while moving, 160 while
  still, averaging 23 over a session that mixes both".
- **Eighth pass — FOUND AND FIXED, and it was a site my own previous fix missed.**
  `update_aim_hover` still emitted `aim_changed`. The signal split converted `scroll_layer`,
  `move_reticle` and `aim_reticle_at_screen`, but not the one handler that runs on **every** motion —
  and `aim_reticle_at_screen` calls it internally, so **both** motion paths still reached the expensive
  listener.
- **Measured through a real `SquadControlOverlay` on a 214-blocker board:**

  | per mouse motion | before | after |
  |---|---|---|
  | `aim_reticle_at_screen` | 62 179 usec | **8 777** |
  | `update_aim_hover` | 54 429 usec | **101** |
  | **one motion** | **116 608 usec (8.6 fps)** | **8 878 usec (113 fps)** |
  | state clones | 2 per call | **0** |

- **Two changes, both small:** emit `reticle_changed` rather than `aim_changed`, and **only when the
  hovered part actually changed** — a signal that fires on every motion regardless is one every
  listener has to defend itself against. Hovering "reads, it never re-aims" was already this
  function's contract from taskblock-34 Pass C; it was contradicting that in the most expensive place
  available.
- **What remains: one `ShotPlane.build` per motion, ~8 800 usec.** `AimController._resolve_hit` calls
  `ShotPlane.resolve_ray`, which builds its own plane to cast one ray. That genuinely varies with the
  reticle, so it is not obviously cacheable — and at 113 fps it is **not being chased on
  speculation**. If the supervisor still feels it, that is the next and last known cost.
- **Still `Pending`:** the numbers are CC's; the confirmation is the supervisor's.
- **Ninth pass — the supervisor reframed it again, correctly: "the dartboard almost seems to lazily
  follow the cursor, not be attached to it."** That is **input latency**, not framerate, and it has a
  different cause from everything above.
- **`aim_reticle_at_screen` ran once per motion EVENT.** A mouse polls at 500–1000 Hz against a game
  drawing at 60–160 fps, so `_unhandled_input` ran the full reticle update many times per frame — each
  ~8 800 usec after the earlier fixes — and **every one but the last was immediately overwritten**. The
  queue backed up and the reticle drew cursor positions from several events ago.
- **Coalesced: the newest position is stored and applied once in `_process`.** Safe because this is an
  absolute raycast through the literal cursor rather than an accumulated delta, so the intermediate
  positions carry no information — asserted in the test rather than assumed, since if it ever became
  relative the optimisation would start silently losing movement.
- **The eighth pass's numbers, confirmed live by the supervisor:** 2 s aim samples now **116** and
  **160** (were 8 and 6); session averages **32.8** and **46.2** (was 22.8). **`BR27.09` improved with
  it** — turn-start FPS **93** and **147**, against the **38.0** recorded earlier in this block.
- **The session minimum is still ~7.1–7.8**, so one stall per session survives. That is the next thread
  if the supervisor still feels it: a single slow frame, not a sustained cost.

### BR27.01 — Active — owner: `SUPERVISOR`
**Player Step Out: four bugs, one system**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27: Step Out works for the AI but the player's own path was broken four
  ways — (1) doesn't open the dartboard, always resolves a center-mass shot; (2) charges MP for the
  automated legs; (3) the ghost snaps back to the base cell instead of holding the step-out
  waypoint; (4) the intended sequence (pick step-out → ghost holds the cell → dartboard opens there
  → fire resolves the whole move/fire/return) wasn't followed.
- **Root cause:** `TacticsController._confirm_step_out()` called `StepOutPlanner.build_triple()`
  wholesale the instant the player confirmed a candidate cell — queuing the WHOLE move+attack+move
  triple (an automated center-mass shot) in one click, never entering ordinary aim mode at all. The
  ghost "snapping back" was a direct symptom of this: the entire triple (ending back at origin)
  was queued and previewed in the same instant the step-out cell was chosen, so there was never a
  sustained moment where the ghost held the stepped-out position for the player to see. `MoveAction`
  had no discount mechanism at all — `StepOutPlanner`'s own doc comment stated "real MP/AP cost for
  both legs, no discount" as a deliberate original design choice.
- **Fix:** split the flow. Confirming a step-out cell now queues ONLY the free outbound leg
  (`MoveAction.free`, new — no MP/AP either direction, docs/SUPERSEDED.md), then hands off into
  ORDINARY aim mode from the stepped-out position (`_framing_shooter()`/`aim_state()` already read
  the previewed unit, so the camera and dartboard follow the queued move for free). Firing
  (confirm_shot() again, now in aim mode) appends the free return leg once a real shot actually
  queues. Canceling aim mid-step-out (before firing) undoes the queued outbound leg. The ghost
  "snapping back" is now correct, not a bug — it only happens once the return leg is genuinely
  queued (after firing), the truthful final resting position; during the aim phase it holds the
  stepped-out cell via the same queued-move preview machinery every other action already uses.
  `free` applies to the AI's own `StepOutPlanner` usage too, not just the player's — the same shared
  maneuver, same cost either way.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — taskblock-27 Pass B,
  proven via `test_tactics_controller_step_out.gd`'s updated/new tests (cell-confirm queues only the
  free out-leg and opens aim; firing completes the free triple; canceling aim undoes the out-leg)
  and `test_step_out_planner.gd::test_the_triple_costs_no_mp_for_either_leg`.
- **2026-07-20:** supervisor could not verify — blocked by a new, separate bug (now logged as
  **BR27.06 — Step Out no longer occurs at all**, a regression from this very restructure). Until
  BR27.06 is fixed, BR27.01 can't be confirmed. **Verification deferred**; still pending, and now
  gated behind BR27.06.
- **2026-07-21:** BR27.06 now has a fix pending its own confirmation (commit `d42f744`). Worth
  re-attempting BR27.01's own verification alongside BR27.06's — same play session either way.
- **2026-07-21 (broken down by the supervisor, same session as BR27.06's confirmation):** parts (2)
  and (3) confirmed **RESOLVED** — no more MP charged for the automated legs, ghost no longer snaps
  back. Part (4) ("the intended sequence wasn't followed") was the supervisor's own original
  rephrasing of (1)-(3) together, not a distinct fourth symptom — folded in, not tracked separately.
  Part (1) has **mutated, not resolved** — reopened with a precise new repro: "clicking shoot, then
  clicking an enemy, doesn't bring up the dartboard if the unit had to step out; clicking again brings
  up the dartboard." Likely the two-step step-out flow itself (first click enters step-out-cell-choice
  mode, a second click/`confirm_shot()` is what actually opens ordinary aim mode per the Pass B fix
  above) reading as "doesn't work" without a clear in-between visual cue — not yet investigated
  code-side. **BR27.01 stays open for this one remaining piece.**
- **2026-07-22 (tb32 review — still reproduces):** unchanged — step-out after shooting still does not
  open the dartboard immediately on the step-out; a second click is required. tb32 didn't touch this.
  The one open piece (part 1) persists exactly as the 2026-07-21 repro describes.
### BR27.03 — Active — owner: `SUPERVISOR`
**Other shots appear to resolve before an earlier shot's own deflect finishes**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20, correcting a taskblock-27 misdiagnosis: Pass A2 had assumed a shot and
  its own deflect were wrongly paused apart and inserted a fix for that — but they're SUPPOSED to
  resolve simultaneously, that was never broken. The real, still-open defect is different: a
  DIFFERENT, later shot can appear to resolve/animate before an EARLIER shot's own deflect segment
  has finished.
- **Status:** not yet investigated. taskblock-27 Pass A2's own `DEFLECT_BEAT_MS` fix (a deliberate
  pause between a primary hit and its own deflect) does not address this bug and is itself now a
  wrong implementation of the intended simultaneous behavior — not reverted, only reclassified.
  Likely candidate: `ResolutionPlayer`'s own inter-event sequencing between separate impact events,
  not the intra-event primary/deflect pairing `DEFLECT_BEAT_MS` targeted.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** confirmed not an
  intra-event bug — each `ResolutionPlayer.play()` call is fully await-serialized internally,
  primary+deflect included. The gap is a missing reentrancy guard: `play()` has no busy-flag, and
  `SpectatorOverlay.step_once()` (`spectator_overlay.gd:249-251`) calls `pause()` (only flips a bool,
  doesn't cancel anything in flight) then immediately awaits `_advance()` — so a Step/Play issued
  right after Pause can start a SECOND concurrent `play()` while an earlier turn's own deflect tracer
  is still animating. **Candidate fix (not yet applied):** add a busy/in-flight guard to
  `ResolutionPlayer.play()`, or have `pause()` actually await the in-flight `_advance()` before
  returning.
### BR27.07 — Active — owner: `SUPERVISOR`
**Active-turn highlight lands on the wrong unit; change to facing-marker-only**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor check — looks right, BLOCKED on full confirmation).** The change reads as
  correct on inspection, but it cannot be properly verified while **BR34.06** (every AI unit passing
  every turn) is live — there aren't enough real turn transitions to watch. Re-check after BR34.06.
- **Reported:** 2026-07-20 (tb27 review). Two parts: (a) **design change** — instead of recoloring the
  active unit's facing wedge + team marker (tb27 D2), the supervisor wants *only the current unit to
  show a facing marker at all* (the marker's presence indicates whose turn it is, not a color). (b)
  **bug** — the current-unit highlight sometimes lands on the *next* or *prior* unit, not the active
  one.
- **Status:** open. Note the design change supersedes part of D2 (which shipped as a feature in
  CHANGELOG) — the "recolor" approach is being replaced by "only the active unit has a facing marker."
  The wrong-unit bug may be independent (an off-by-one in whichever index drives the highlight) and
  should be checked even after the design change, in case the change is built on the buggy selector.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here) — concrete ordering bug,
  confirmed:** `SquadControlOverlay._on_turn_ended()` (`squad_control_overlay.gd:573-582`) calls
  `refresh_unit_views()` — which flips the highlight to the new current unit — at line 574, BEFORE
  `await resolution_player.play(events)` at line 577 animates the unit whose turn just ended. The
  marker visually jumps to the next unit while the previous unit is still animating its own queued
  action. **Compounding bug:** `SingleUnitOverlay._on_turn_ended()` (`single_unit_overlay.gd:40-42`)
  calls `super._on_turn_ended(events)` WITHOUT `await` — since the parent implementation contains an
  internal `await`, this lets `_auto_select_if_current()` run immediately, racing ahead of the
  parent's own animation/AI-batch completion. **Candidate fix (not yet applied):** reorder so
  `refresh_unit_views()`'s highlight flip runs after the animation await completes; add the missing
  `await` in `SingleUnitOverlay`.
- **2026-07-22 (tb32 Pass D) — both parts done:** (a) design change — `HitVolumeView.set_active_turn()`
  no longer recolors anything (`ACTIVE_TURN_COLOR` retired); it toggles the facing wedge's own
  `.visible` instead, so only the current unit ever shows a facing marker at all, exactly as
  requested. (b) ordering bug — `BattleScene.refresh_unit_views()` gained an `apply_highlight: bool =
  true` parameter; `SquadControlOverlay._on_turn_ended()` now passes `false` and calls the (newly
  public) `battle.apply_active_turn_highlight()` itself AFTER `await resolution_player.play(events)`
  completes, so the marker no longer jumps to the next unit mid-animation. `SingleUnitOverlay._on_
  turn_ended()` now `await`s its `super` call, closing the compounding race. Every other existing
  caller (`advance_ai_turns`, `SpectatorOverlay`) keeps the old default (`apply_highlight` true, no
  deferral) unchanged.
- **2026-07-22 (supervisor tweak):** "facing marker" means the WHOLE disk/facing-pip assembly (the
  ground marker AND the wedge together), not the wedge alone — the first pass only toggled the
  wedge's own visibility, leaving every unit's ground disk always showing regardless of whose turn
  it is. `set_active_turn()` now toggles both `_team_marker.visible` and `_facing_wedge.visible`
  together.
- **2026-07-28 (supervisor check — REOPENED from `Pending`).** Now checkable, since BR34.06 is
  `Resolved`. Observed: **unit 1 holds the highlight, the highlight jumps to unit 2, and only then does
  unit 1 move.** Reads as if a turn is being passed before its animation finishes.
- **That symptom is consistent with the highlight reading live state rather than playback position.**
  `BattleScene.apply_active_turn_highlight` sets it from `combat_state.current_unit()`, and RESOLUTION
  advances `current_unit` when the *action* resolves — while `ResolutionPlayer` is still drawing the
  previous unit's move. Two clocks, one signal. `battle_scene.gd:472-478` already names the hazard in
  prose: the batch badge is unconditional in `refresh_unit_views` **unlike the active-turn highlight,
  which "a caller might want to defer until an animation finishes."** The defer appears not to be
  happening on every path — there are three call sites.
- **Check whether this is the same defect the entry originally described.** The original was the
  highlight landing on the *wrong* unit; this is the right unit at the *wrong time*. If the selector is
  now correct and only the timing is off, say so and rewrite the entry rather than carrying both
  descriptions forward.
- **The general fix is `PLAN.md`'s *Player view and sim view — render a snapshot*.** A view that draws
  the last resolved state cannot show a highlight for a turn whose animation has not played. The narrow
  fix is deferring the highlight until playback drains; the narrow fix is worth taking now, but it is an
  instance of the class that item dissolves.
- **taskblock-51 duplicate check — suspected the same defect as `BR32.09`, NOT merged.** The supervisor
  answered both with one observation: *"Indicator moves to next unit before animation completes when AI
  is controlling. Indicator moves with unit correctly when player is controlling."* That is one
  behaviour, and it is the *timing* description in `BR32.09` rather than the *wrong unit* this entry's
  title claims — so this heading may also be stale.
- **Both are `SUPERVISOR`-owned, so CC has flagged rather than combined them.** Merging is the owner's
  call; the useful finding is that the AI-driven path does not defer and the player-driven one does.
### BR27.09 — Active — owner: `SUPERVISOR`
**Major hitch on new-turn or end-turn**
- **Source:** `SUPERVISOR`
- **Three concrete costs, measured headlessly (tb21 Pass E) — recorded here so they stop living in a
  planning doc.** Real logic and view classes timed directly, not through GUT. None of the three is
  fixed:
  1. **The combat-log UI sink reassigns `label.text` in full on every event** — ~175–180µs per call at
     a 200-line scrollback, and a real 3v3 bout averages 9.9 events per turn (peak 29), so a heavy turn
     pays ~5ms just relaying text nobody scrolled to. `HierarchicalUiSink` inherited the identical
     pattern, so it is still live. *Fix:* incremental `RichTextLabel.append_text` for the new line, plus
     a line-cap strategy other than trim-every-line. **This one gets worse the moment the planned log
     verbosity work lands** — that item's cost scales linearly with event count.
  2. **`HitVolumeView.refresh()` rebuilds every mesh and material from scratch** for the acting unit on
     every turn (~550–600µs on a 27-part unit), even on turns where nothing about its geometry changed.
     *Fix:* skip the rebuild when the turn's only events were `turn_start`/`turn_end`/`faced`.
  3. **Turn-start power recompute re-walks the same unchanged part graph 5–6 times** per `_start_turn`
     (uncached `all_parts()`/`operable_parts()`) — smaller (~175µs) but pure waste. *Fix:* compute
     `operable_parts()` once and thread it through.
  Initiative re-sort was measured and **ruled out** (~40µs per turn across a 12-unit roster) — not a
  contributor, don't re-investigate it.
- **Reported:** 2026-07-20 (tb27 review). A significant frame hitch fires on either the new-turn or
  end-turn transition — supervisor can't yet tell which of the two triggers it.
- **Status:** open. First step is isolating which transition (instrument both, or bisect). Possibly
  related to per-turn work done synchronously (a full `refresh_unit_views` / re-resolve on the turn
  boundary).
- **2026-07-21 — pinned down, likely the same underlying mechanism as the now-retired BR26.01
  ("opposing team teleports"):** supervisor reports the transition precisely now — "at the end of
  player unit turns, there's a heavy lag spike, then all the opposing units move and act in one go."
  BR26.01's own fix only reordered so the human's own turn finishes animating BEFORE the AI batch
  starts; it never gave the AI batch itself any animation. A read-only investigation pass
  (`docs/Bugs-add.md`, rolled in here) confirms the mechanism: `advance_ai_turns`
  (`control_overlay.gd:68-83`) calls `BoutRunner.step()` once per consecutive AI unit with **no yield
  between iterations**, and each `step()` runs full per-candidate pathfinding/LOS/cover scoring via
  `UnitAI.plan_turn` — the entire AI batch executes synchronously in one frame, which is both the
  hitch (all that planning work landing in one frame) and the "one go" (no animation between AI units,
  just a single `refresh_unit_views` once the whole batch is done).
- **Candidate fix (not yet applied):** yield between AI units in the loop (e.g.
  `await get_tree().process_frame`) to spread the planning cost across frames instead of one
  synchronous batch — would likely also restore *some* per-unit animation pacing, though the AI batch
  is deliberately unanimated by design (only the human's own turn animates), so a fix here is about
  the hitch specifically, not necessarily adding animation.
- **2026-07-23 (tb34 review — worse and broader than logged):** the hitch is **several seconds long**,
  not a frame spike. And the scope is wider than the AI-batch case above: **every player turn now ends
  in a long hitch**, not only turns followed by the opposing team's batch move. That second part
  matters — the `advance_ai_turns` synchronous-batch mechanism explains a hitch *before the AI acts*,
  but it does not explain a hitch at the end of a player turn with no AI batch pending. Either there's
  a second cost on the player turn-end path (a full `refresh_unit_views` / re-resolve on the boundary,
  the original 2026-07-20 suspicion), or the AI planning is now more expensive per unit than it was —
  tb33 added a real `ShotPlane` build per candidate cell to the engagement scorer and an approach
  flood on the no-LOF path, both inside `UnitAI.plan_turn`, which is exactly the code this entry says
  runs synchronously for the whole batch. **Instrument the player turn-end path separately from the AI
  batch before fixing** — the candidate fix above (yield between AI units) addresses only one of the
  two, and would leave a several-second player-turn hitch untouched.
- **2026-07-23 (tb35 Pass A3 — one real cost measured and cut, not the whole bug)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Confirmed the "tb33 added a real `ShotPlane` build per
  candidate cell" suspicion directly: `_any_reachable_has_lof` and `_engagement_score` each
  independently resolved `LineOfFire.first_hit` for the same (unit, enemy, cell) — up to ~2 real
  `ShotPlane.build`s per reachable cell, ~96 reachable cells on a normal map, every single
  reposition-or-hold turn. Added `LineOfFire.cached_first_hit` (opt-in, `null` default — every other
  caller unaffected) and threaded one per-turn memo `Dictionary` through `_plan_ranged` →
  `_any_reachable_has_lof`/`_pick_engagement_position`/`_engagement_score`/`_ally_in_firing_line` so
  each cell resolves once, not twice. Measured on the same 60-turn `BoutSetup` bout used to verify
  BR34.06: average per-turn cost for a reposition/hold turn dropped from **2023ms to 974ms** — roughly
  halved, matching "cut the duplicate resolution" exactly. **Not a full fix:** ~974ms/turn is still
  real, unavoidable per-cell `ShotPlane.build` cost this memoisation can't remove without a bigger
  algorithmic change (out of scope for "memoise per cell" as specified) — BR27.09 stays open. The
  original player-turn-end-hitch-with-no-AI-batch question above is also still unaddressed; this pass
  only measured and cut the AI-planning half.
- **2026-07-26 (tb42 Pass B — cost #2 cut, not eliminated)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. `HitVolumeView.refresh()` freed every child and
  re-instanced all of them even when only a transform had changed — which is the most common case
  there is, a unit that moved. Added `refresh_transforms()`: same nodes, new transforms.
  **Measured on a real 30-part reference humanoid (34 child nodes per view), 200 repeats:**

  | path | before | after | |
  |---|---|---|---|
  | move refresh (post-AI-batch) | 858µs | **351µs** | 2.4× |
  | orientation preview (aim path) | 795µs | **267µs** | 3.0× |

  The "before" figure corroborates this entry's own original ~550–600µs on a 27-part unit.
  - **Partial, and the remainder is named.** The teardown is gone; what is left is
    `UnitGeometry.placements()` recomposing the socket tree, which the cheap path cannot skip — it
    needs the new transforms. Removing that needs cached geometry, a larger change than this pass.
  - **The cheap path REFUSES rather than guesses.** It compares a signature of everything the node
    SET depends on (part order, per-part box counts, render path per part, downed-ness, hit-volume
    toggle) and returns false on any difference, so the caller falls back to a full rebuild. The risk
    here was never speed, it was a view that silently stops updating in a case nobody enumerated.
  - A test pins that a cheap refresh lands the scene in a state **identical** to a full rebuild, node
    for node. Writing it surfaced a real ordering defect: rebuilding the ground markers appended them
    to the end of the child list, so the two paths held the same nodes in different tree order.
    Nothing rendered differently, but "identical" stopped being literally true — fixed with
    `move_child`.
- **2026-07-26 (tb42 Pass C — cost #3 confirmed, collapsed, and it is SMALL)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Instrumented `PartGraph.walk` before changing
  anything: **exactly five full socket-tree walks per turn start** — `recharge_batteries`,
  `has_power_system`, `max_ap_for` (three internally), `discharge_batteries`, `mp_per_ap`, each
  walking independently. **This entry's own "5–6 times" was right.** Collapsed to one walk threaded
  through all of them: **117.7µs → 39.6µs per unit per turn start (3.0×)**.
  - **Say the unwelcome half plainly: this is noise next to the real problem.** ~78µs saved per unit
    per turn, against a hitch this entry now describes as *several seconds*. It is a genuine
    inefficiency genuinely removed, and it will not be felt. Cost #2 (tb42 Pass B) is ~10× larger,
    and cost #4 (the synchronous AI batch) is four orders of magnitude larger.
  - **Explicit threading, not a per-turn cache.** A cache needs invalidating on every structural
    change to the part tree, and a stale power reading is a silent wrong number rather than a crash.
    Threading has no state to go stale — the "cache invalidates on any structural change" acceptance
    is met by there being nothing to invalidate. Every existing call site is untouched: the new
    parameters default to empty and walk on demand exactly as before.
- **2026-07-26 (tb42 Pass D — cost #4: the batch yields now, and THE HITCH IS NOT FIXED)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. `advance_ai_turns` was a bare `while` loop with no
  `await` anywhere in it; it now yields a frame between units, so input is processed and the board
  draws while the batch runs, and each unit's own move becomes visible as it happens instead of the
  whole opposing team appearing to teleport at the end.
  - **The measurement that matters, and it is bad: a single `BoutRunner.step()` costs ~1672ms.**
    24 steps of a real 3v3 bout took **40.1 seconds** of pure planning. **Yielding BETWEEN steps
    therefore buys one responsive frame every ~1.7 seconds — it does not fix this entry.** The
    several-second hitch is one `UnitAI.plan_turn` call, not an accumulation of small ones, and no
    amount of yielding around it addresses that.
  - **This relocates the bug.** Costs #1–#3 are now measured and cut (5–10ms, ~500µs, ~78µs
    respectively) and together they are **under 1%** of a single step. The remaining ~1.7s/step lives
    inside `UnitAI.plan_turn` — per-candidate-cell pathfinding, LOS and cover scoring, which tb35
    Pass A3 already halved once (2023ms → 974ms per turn) by removing duplicate `ShotPlane` work and
    named the remainder as real per-cell geometry. It has since grown again. **That is the whole
    bug now, and it wants an algorithmic pass of its own, not another sweep.**
  - **Determinism verified, and it was the acceptance rather than the speed.** A seeded bout driven
    through the yielding overlay path and through a tight `BoutRunner` loop with no yielding lands
    in an identical state (`test_ai_batch_yield.gd`). `step()` draws only from `state.rng` and
    nothing on the frame path touches it.
  - **Coalescing fork, decided before implementing:** refresh only the units THAT step touched,
    after that step. taskblock-19 Pass I2's measured waste was refreshing the whole board repeatedly;
    this is proportional to what changed (usually one unit), and Pass B made each ~2.4× cheaper. The
    accumulated set still gets one final pass so the active-turn highlight lands on the real end
    state.
  - **Status unchanged — `Active`.** Three of its four named costs are closed as costs; the entry's
    actual symptom is not.
- **2026-07-27 (tb44 Pass D — the hitch becomes a wait you can navigate)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. **This does not make planning faster and is not meant
  to.** taskblock-42 Pass D yielded BETWEEN `BoutRunner.step()` calls, which bought nothing, because
  one step is the entire think. The planner now yields **inside** one unit's plan — every `chunk`
  candidate cells — so input is processed and the board draws while a unit is still deciding, with
  the acting unit named on screen ("<name> is thinking…", never a bare "Thinking…").
  - **The planner chain is coroutines now**, which was forced rather than chosen: GDScript rejects a
    conditional-await single implementation at parse time (any function containing `await` is a
    coroutine and every caller must await), and a second synchronous planner would be two code paths
    deciding the same thing. Headless callers pass no pacer, nothing ever suspends, and the whole
    suite is unchanged — 2301/2301.
  - **A hard turn budget backs the label**, because a visible "thinking" state that never ends is
    worse than a freeze: the player waits longer before concluding something is wrong. Past
    `budget_msec` the scan stops and the unit acts on its best cell so far, which is safe at any
    iteration because the incumbent is seeded with the unit's own cell and only ever replaced on a
    strict improvement.
  - **Frame boundaries do not change decisions** — a seeded bout is identical with and without
    slicing, asserted directly. The one thing that DOES change a decision is an abort, which is the
    trade the budget makes deliberately and is covered by its own case.
  - Status unchanged, `Active`. The per-step figure is untouched by this pass by design; what changed
    is that the wait is navigable rather than frozen.
- **2026-07-27 (tb44 Pass B — the line-of-fire query inverted; ~700ms -> ~525ms per AI step)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. The planner cast from N candidate cells to one target,
  paying a real `ShotPlane.build` per candidate. It now builds **one `VisibilityField` per target per
  turn** (`src/logic/visibility_field.gd`) and each candidate's question becomes a bit test.
  `PackedInt64Array`, flat `i = x + y*W + z*W*H`.
  - **Measured, editor_debug, same bench/seeds/steps throughout:** **~686-712ms -> ~523-528ms per AI
    step (~24%)**. Exported release: **~412ms**, still ~1.29x under debug.
  - **The field is a conservative PREFILTER; `ShotPlane` stays final.** One obligation — never report
    "no line" where one exists. It therefore deliberately over-includes in three places, each costing
    a cast it could in principle have saved: cover never occludes (cover blocks shots, not sight),
    units never occlude, and any cell at a different elevation from the target is always allowed
    (occlusion data here is 2D, so it says nothing reliable about a shot passing over a wall).
  - **The occluder test is opacity AND a blocker the plane would actually resolve against**
    (`BodyProjector.projects`, extracted so there is one answer rather than two). Opacity alone would
    be genuinely WRONG: `Grid.opacity` is never cleared when a wall is destroyed, so a dead wall would
    occlude in the field while shots pass straight through it — under-inclusion, the one failure mode
    that matters. There is a direct test for exactly that.
  - **The negative case now costs nothing.** `field.allows_none(reachable)` settles "nobody can shoot
    from anywhere reachable" with **exactly zero** `ShotPlane` builds, asserted as a number rather
    than a bound. That was 19 of 60 turns in taskblock-43's census.
  - **Where the cost moved, which is Pass B4's answer and matters for Pass D.** Per repositioning turn:
    `any_lof_scan` **271.9ms -> 77.8ms**, new `field_build` **4.2ms** — but `engagement_search`
    **98.3ms -> 251.2ms**. It did not get slower; it was previously being subsidised. The old scan
    built a `ShotPlane` for nearly every reachable cell and left them in the per-turn memo, so the
    scorer ran warm. Now the scan short-circuits and the scorer pays for its own casts on the cells the
    field allows. **The remaining cost is per-candidate casts inside `_engagement_score`**, not the
    prefilter.
  - Acceptance was identical output and it holds: full suite green including `test_full_mission.gd`
    and the byte-identical seeded-bout tests. **Status unchanged, `Active`** — CC appends numbers, the
    supervisor closes.
- **2026-07-27 (tb44 Pass A COMPLETE — the release number exists, and debug overhead is NOT the story)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. The supervisor installed export templates, CC wrote
  `export_presets.cfg` (+ a committed `.example`) and `tools/bench_release.sh`, and the measurement
  this pass asks for is done. Same bench, same seeds, same steps, both builds:

  | build | ms per AI step |
  |---|---|
  | `editor_debug` (every historical figure in this entry) | ~686-712 |
  | `exported_debug` | ~665 |
  | **`exported_release`** | **~530-554** |

  - **Release is ~1.29x faster — it is not the explanation.** A hoped-for answer here was "most of the
    hitch is the harness"; it is not. Roughly 78% of the debug cost survives into a real player build,
    so **the AI planning cost is genuine** and the rebuild's urgency stands essentially unchanged.
    `candidates_skipped` was identical (2306) across all three builds, which is the cross-check that
    the same deterministic work ran in each.
  - **Getting there required fixing BR44.01** (`docs/BUGS-ARCHIVE.md`): the first-ever export of this
    project loaded **no data at all**, and presented as a bare SIGFPE with no message. Every number
    above is from a build with that fix in.
  - **Two structural things worth knowing.** An export template **ignores `-s res://...`** — it is
    tools-only — so the bench needed a main-scene entry point (`run/main_scene.bench`, activated by
    the preset's `bench` custom feature) alongside the existing `-s` one, sharing one implementation
    via `AiPlanningBench`. And `BuildIdentity` did its job: `bench_release.sh` refuses to report a
    number unless the binary itself declares `build=exported_release`, so a silent fallback to a debug
    binary cannot be mistaken for the real figure.
- **2026-07-27 (tb44 Pass A — every number in this entry came from a tools binary, and now says so)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. **The release-vs-debug measurement this pass asks for
  could NOT be taken here and no proxy was substituted.** `~/.local/share/godot/export_templates/` is
  empty and the project has no `export_presets.cfg` (it is gitignored), so `--export-release` refuses.
  The pass's own instruction on this is "say so and stop"; the exact procedure for the supervisor to
  run it locally is in `reports/Report-Taskblock44.md`.
  - **What the missing number means for this entry:** every figure above — the ~1672ms, the ~1498ms,
    tb35's 2023ms→974ms, tb43's whole bench series — was taken on an **editor/tools binary**, which
    carries GDScript's per-line debug overhead by a factor nobody has measured. **They may all be
    proportionally right and absolutely wrong.** That does not invalidate any of the A/B comparisons
    (both sides shared the build) but it does mean the absolute severity of this bug is unknown.
  - **Built instead: the provenance itself.** `src/debug/build_identity.gd` classifies the running
    build (`editor_debug` / `exported_debug` / `exported_release`) and is stamped into both
    instruments — `tools/bench_ai_planning.gd` prints it as its first line with an explicit warning
    when the build is not representative, and every `FpsDumpSink` event now carries it in `data`, so a
    framerate read out of `out/combat.log` says which build produced it. Status unchanged, `Active`.
- **2026-07-26 (tb43 Passes C+D — batches land, and they measure the block's own premise WRONG)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. `Unit.batch_id` (0 = independent), a `set_batch`
  injector verb, a round-scoped `BatchPlan` on `CombatState`, a board badge, and the planner split:
  the first member of a batch to take a turn claims the lead and pays for the full positional search,
  every later member that round reads its destination and scans a handful of cells around it instead.
  Leadership is derived, never stored — no `leader_id`, no promotion logic, nothing to desync.
  - **Pass D's stated acceptance is NOT met, and this is the block's most useful finding.** It asks
    for a follower to be "dramatically cheaper" than a leader, and says that if it isn't, "the local
    scan is too wide." Measured on `tools/bench_ai_planning.gd --batched`: **leader ~330ms, follower
    ~317ms — about 4%.** The scan is not too wide (radius 1, at most 9 cells); **the diagnosis in the
    taskblock is wrong**, and the profile says where the time actually is.
  - **`_any_reachable_has_lof` is the hog, not `_pick_engagement_position`.** Per repositioning turn
    (`--profile`, means over 60 turns): **`_any_reachable_has_lof` 271.9ms, `_pick_engagement_position`
    98.3ms** (warm cache, which is the real in-planner order), `_nearest_living_enemy` 15.0ms,
    `Pathfinder.reachable` 2.5ms. So the positional search is **~25% of a planning turn**, and
    removing it outright for followers cannot save more than that. Everything before it is paid by
    leader and follower alike.
  - **This retargets BR27.09.** Passes A, B and D all attacked the candidate search — a quarter of
    the cost — because that is where three taskblocks in a row assumed the time went. The **LOF
    prefilter scan over the whole reachable set is the actual remaining bug**, and the cheapest exact
    attack on it is ordering: it early-returns on the first cell with a clear line, and currently
    walks `reachable` in BFS-from-the-unit order rather than trying cells nearest the target first.
    Deliberately NOT built here — this block is triage with a stated scope, and an unrequested fifth
    pass on the newly-found real cause is how a scope fence stops meaning anything.
  - Branch census over the same 60 turns, which is what makes the above legible: `repositioned` 23,
    `no_lof_no_route` 15, `followed_leader` 10, `closing_fallback` 4, `fired_in_place` 5,
    `stepped_out` 2. **19 of 60 turns end with no reachable cell having a line at all**, and each of
    those scanned every reachable cell to find that out.
  - Whole-bout effect of batching one squad of three: **~671ms -> ~646ms per AI step**, two runs each.
    Real, small, and honest about being small.
  - **Status unchanged — `Active`.** `SUPERVISOR`-owned; nothing here closes it, and the per-step
    figure has not moved by anything like the order of magnitude that would.
- **2026-07-26 (tb43 Pass B — the candidate rectangle, and a repeatable bench to judge it by)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. `_pick_engagement_position` now scores only the
  reachable cells inside a rectangle with two corners on the acting unit and its target
  (`src/logic/ai/engagement_rect.gd`), padded 2 cells laterally and, on the far side beyond the unit,
  by the weapon's own standoff distance — the asymmetric half, without which a unit that wants to
  back off finds no candidates behind it.
  - **The numbers here are NOT comparable to this entry's earlier ones and the reason matters.**
    Every figure above came from a bench nobody kept; `tools/bench_ai_planning.gd` is now in the
    tree, fixed at 5 seeds x 12 steps of a 3v3, and every number below is from it. **On that bench:
    ~745ms -> ~674ms per AI step (~9%)**, taken twice per build. Treat the earlier ~1672/~1498ms as a
    different instrument's readings, not as a series this continues.
  - **Honest size, and the block predicted it: the rect keeps 64.9% of candidates**, mean 95.7 -> 62.1
    per decision. It does not carry this bug and was never going to.
  - **The behavioural cost, measured rather than assumed: the chosen cell differs in 7 of 60
    decisions (11.7%).** Full-suite green including `test_full_mission.gd`'s `MIN_COMPLETION_RATE`.
    Much of that 11.7% is cells that *tie* — on open ground a whole arc sits at exactly the standoff
    distance and scores identically, so dropping one changes the cell without changing the decision.
  - **The LOF scan deliberately still sees the WHOLE reachable set.** Culling before it would let a
    discarded cell flip which BRANCH runs (engagement vs. the approach fallback), a far larger
    behaviour change than picking a different cell inside the branch this pass is scoped to.
- **2026-07-26 (tb43 Pass A — exact early-out in the candidate scorer)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. `_engagement_score` walked two paths per candidate
  cell (`is_covered_from`, `_ally_in_firing_line`) regardless of how bad the cell's cheap terms
  already were. **Bound enumeration, in full, because the soundness rests on it:** every term is a
  non-negative penalty subtracted from the total — distance, obstruction, ally-blocked, min-range,
  suppression, opportunity, no-LOF — and **exactly one term can raise the score**, `cover_bonus`,
  bounded by `COVER_SCORE_BONUS` (zero when `weight_cover` is false). Dropping every not-yet-computed
  penalty therefore gives a true upper bound, and a cell that cannot beat the best complete score so
  far is skipped whole. `<=` is correct because selection is strict `score > best_score`: a cell that
  can at best tie never wins.
  - **Measured: ~1672ms → ~1498ms per AI step (~10%)**, 203 candidates skipped across 12 steps.
    Real, exact, and **nowhere near enough on its own** — the taskblock's own expectation.
  - **Acceptance was identical output, not the number.** A seeded bout produces a byte-identical
    action sequence, and a separate test asserts the skip actually fires — an early-out that never
    runs passes an identical-output test trivially.
  - Any future term that can INCREASE a cell's score must join the ceiling, or this silently starts
    choosing a different cell. Stated in the code at the branch itself.
- **2026-07-26 (tb41 Pass A — cost #1 fixed, but by coalescing, NOT by the `append_text` this entry
  prescribes)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. **Supervisor approved the override; this
  is an append, not a status change.** Cost #1's stated fix — "incremental `RichTextLabel.append_text`
  for the new line" — fits `UISink`, which genuinely is append-only. It **cannot** fit
  `HierarchicalUiSink`, which this entry itself flags as having inherited the same pattern and still
  being live: a new event there routinely rewrites an **existing** group's summary rather than
  appending a row, and expand/collapse re-renders everything. There is no correct incremental append
  against a folding model. What landed instead: `emit()` updates the model and marks dirty, and the
  label draw happens at most once per frame, driven from `ControlOverlay._process` (new
  `UiLogSink` base, shared by both sinks). Two properties `append_text` would not have given: it is
  correct for the folding sink, and **render cost stops scaling with event count at all** rather than
  merely getting cheaper per event — which is what makes tb41 Pass D's deliberate verbosity
  affordable instead of a regression. Incremental `append_text` in `UISink` alone is still available
  on top, and is deliberately **not** taken here: it should only be judged against the coalesced
  baseline, not the old per-event one.
  - **Measured, real classes against a real `RichTextLabel` in a real tree** (same posture tb21 Pass E
    used for the original figures), at this entry's own scenario — 200-line scrollback, 3v3, 9.9
    events/turn averaged, peak 29. Before = render after every emit (exactly what these sinks did),
    after = one render for the frame, 200 repeats each:

    | | peak turn (29 events) | average turn (10 events) |
    |---|---|---|
    | `UISink` before | 4845µs | 1677µs |
    | `UISink` after | **225µs** | **193µs** |
    | `HierarchicalUiSink` before | 10058µs | 3263µs |
    | `HierarchicalUiSink` after | **870µs** | **495µs** |

    The `UISink` "before" figure works out to ~167µs per event, which corroborates this entry's own
    original ~175–180µs measurement closely enough to trust the rest. **`HierarchicalUiSink` was
    never actually measured before and is roughly twice as expensive as the sink that was** — a peak
    turn cost ~10ms in the sink that is the one actually wired into both live overlays, not the ~5ms
    this entry estimated from the flat sink. Headless and a real x11 display agreed within ~2% on
    every figure, so the headless number is trustworthy for this particular cost and no GPU frame is
    needed to re-measure it later.
  - **The hitch is still there, and that is the expected result.** This entry is now a
    several-second hitch whose known mechanism is `advance_ai_turns` stepping the whole AI batch
    synchronously with no yield; the sink was ~5–10ms of it. Cost #1 is closed as a cost. Costs #2
    (`HitVolumeView.refresh()` rebuilding every mesh per turn) and #3 (turn-start power recompute
    re-walking the part graph 5–6 times) are untouched, as is the AI batch itself and the
    player-turn-end-with-no-AI-batch question. **Not resolved, not pending — still `Active`.**
- **2026-07-28 — taskblock-45's numbers, appended per that block's own instruction ("append the
  numbers; the supervisor closes it"). CC does not close this — it is `SUPERVISOR`-owned.**

  The AI batch cost this entry has tracked since taskblock-27 is now measured directly, at the one
  seam every AI turn is planned through (`AiPlanner`'s own `plans`/`plan_usec`/`plan_shot_planes`
  counters), rather than by timing `BoutRunner.step()` from outside and mixing planning with damage
  resolution:

  | | old planner | utility planner |
  |---|---|---|
  | per-unit plan cost, 3v3 combat bout | 485.16 ms | **131.25 ms** |
  | per-unit plan cost, mission bout | 139.90 ms | **86.51 ms** |
  | `ShotPlane` builds per turn | 29.1 | **0.0** |

  - **The per-candidate `ShotPlane` cast is gone outright, not reduced.** That was ~70% of a
    planning turn by taskblock-43's profile and is the cost this entry has circled for four blocks.
    Line of fire is now a bit test against one `VisibilityField` built per target per turn; the
    canonical resolver is consulted only when an action is actually enqueued.
  - **The synchronous-batch mechanism this entry names is also addressed, from two directions.**
    taskblock-44 Pass D made the planner a coroutine that yields mid-plan through `PlanPacer`, and
    taskblock-45 found that `SquadControlOverlay._on_turn_ended` was calling `advance_ai_turns`
    **fire-and-forget** — it is a coroutine, so the handler returned the instant the planner first
    suspended and the batch completed later, unobserved. Both call sites are awaited now.
  - **Costs #2 and #3 remain untouched** (`HitVolumeView.refresh()` rebuilding every mesh per turn;
    the turn-start power recompute re-walking the part graph). Whether the hitch is still *felt* is
    a supervisor observation, not something CC can assert — which is why this stays `Active`.
  - Numbers are `editor_debug`. `tools/bench_release.sh` takes the release figure, which is the one
    that describes the game.
- **taskblock-51 — measured for the first time.** A live session recorded
  `fps_dump: Turn FPS (at turn start): 38.0`, recovering to **153.0** two seconds later. So the hitch
  is real, is roughly a 4x drop, and lasts on the order of a second — no longer a feeling.
- **taskblock-51 — improved as a side effect of `BR26.02`'s fixes, measured:** turn-start FPS went
  **38.0** to **93** and **147** across two later sessions, recovering to 134–157 after two seconds.
  **Not closed** — a hitch remains and it has never been the subject of its own investigation.

### BR30.02 — Active — owner: `SUPERVISOR`
**Debug move_object mutates state but the model never visually moves**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, live bout review), tested BEFORE BR30.01 (spawn) in the
  same session — so NOT explained by testing move against an already-invisible just-spawned unit (an
  earlier CC theory here, now known wrong; see BR30.01's own history). Both "Move On Next Click" and
  manual cell-entry Apply are reported affected. `unit.cell` genuinely changes (confirmed via inspect);
  the rendered model does not.
- **Status:** could not reproduce through any headless path tried so far — logged as a real negative
  result, not a fix. Built a REAL `BattleScene` + `SpectatorOverlay`/`SquadControlOverlay`, drove the
  debug panel's actual `_on_apply_pressed()`/`applied` signal for real, and read `HitVolumeView`
  transforms (both the root and a child marker) back per CLAUDE.md's own view-math rule, across three
  scenarios: a fresh bout, a bout after driving several real AI turns through the normal animated
  `ResolutionPlayer` path first (in case a stale cosmetic offset from a real animation was leaking into
  a later debug move), and through both overlays. In all three, `battle.refresh_unit_views()` (already
  wired to the panel's own `applied` signal) correctly rebuilt the moved unit's mesh at the new cell —
  no bug found in `move_object`, `HitVolumeView.refresh()`, `UnitGeometry`, or the `applied` signal
  wiring itself.
- **Needs a more specific repro before further guessing is worth the cost** (per tb30's own "don't loop
  within a block" instruction): does the status label read "Move Object: applied"? Is the camera
  actually framing the destination cell (a correct-but-off-screen move would look identical to "nothing
  happened" without a wrong transform)? Does re-selecting/re-inspecting the same unit afterward show it
  at the new cell in the 3D view specifically (not just the inspect panel's own text)? Exact steps
  (verb used, source/destination cells, which overlay) would let this become a matching headless
  fixture instead of a fourth guess.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here) — concrete asymmetry,
  confirmed:** in `debug_control_panel.gd`, the "Move On Next Click" path's own
  `_begin_move_on_next_click` (:349-363) explicitly snapshots the active object BEFORE arming the
  destination-cell picker, specifically to dodge a signal race (a comment at :344-348 explains why).
  But `_on_apply_pressed`'s OBJECT-param resolution (`_resolve_param`, :414-415) has NO equivalent
  snapshot — it reads whatever `_active` is live at Apply time. Since `_start_picking`'s one-shot
  listener (:371-379) shares the same `board_clicked` signal as the panel's always-on tracker
  (`_arm_active_tracking`, :185-192), clicking "Pick" on the destination CELL field can silently
  overwrite `_active` and swap out the intended unit object before Apply resolves it — explaining
  "data mutates, model doesn't move" without any bug in `move_object`/`HitVolumeView`/the `applied`
  signal itself. This would specifically explain the manual cell-entry Apply path IF the supervisor's
  own workflow used that field's "Pick" button rather than typing coordinates by hand. **Candidate fix
  (not yet applied):** give `_on_apply_pressed`'s OBJECT resolution the same snapshot-before-arming
  treatment `_begin_move_on_next_click` already uses.
### BR30.04 — Active — owner: `SUPERVISOR`
**Waypoint colors shuffle when arming an attack and targeting a cover item**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21, found while confirming BR27.05: "selecting an attack, then trying to shoot
  a cover item causes your waypoint colors to shuffle."
- **Status:** open, not yet investigated. Likely candidate given the symptom: `BoardView.
  show_ghost_paths()` cycles `LEG_COLORS` by queue index (`LEG_COLORS[i % LEG_COLORS.size()]`) — if
  arming an attack against a cover item (rather than a unit) somehow re-queues/re-indexes the existing
  move legs, or a targeting-mode preview call feeds it a different leg count/order than what's actually
  queued, the per-leg color assignment would visibly shift without the underlying queued path changing.
  Not yet confirmed — needs a real repro (which action, what leg count was already queued, which cover
  item) before touching the code.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here) — confirms the ledger's
  own hypothesis above:** `LEG_COLORS` has only 4 entries (`board_view.gd:36-41`), cycled via `i % 4`
  (:376). Targeting a COVERED target routes through the step-out triple
  (`tactics_controller.gd:603-621`, `872-926`), which appends 1-2 extra "free" `MoveAction` legs
  indistinguishable from real ones in `show_ghost_paths`'s own input list — pushing the total leg
  count past 4 and wrapping colors. Targeting an uncovered unit adds zero extra legs, so it never
  wraps, which is why the bug only shows on cover-item targeting. **Candidate fix (not yet applied):**
  either grow the color palette past 4, or exclude free step-out legs from the color-cycling index so
  only "real" queued legs consume a color slot.
### BR30.10 — Pending — owner: `SUPERVISOR`
**Shots resolve straight through walls**
- **Source:** `SUPERVISOR`
- **2026-07-23 (supervisor check — NOT confirmable yet).** Rounds are definitely striking walls now,
  so the core of the fix is doing something — but there are enough remaining inconsistencies that the
  fix can't be signed off. Three specific findings came out of this check and are filed separately:
  **BR32.07** (burst can't engage a wall at all — symptom has since shifted, see that entry),
  **BR34.05** (misses vanish instead of striking anything), and the depth-floor defect that tb35 Pass B
  addresses. Leave `Pending Confirmation` until those are settled — several of them are probably the
  "inconsistencies" observed here rather than separate phenomena.
- **Reported:** 2026-07-21, live play testing BR27.01: an attack against an enemy on the opposite side
  of a wall tile connects as if the wall isn't there. Confirmed by the supervisor as their very first
  test case, deliberately, not an accidental cross-cover shot.
- **Root cause, confirmed by code:** `LoS.has_los()` (`src/logic/los.gd`) and `ShotPlane.build()`
  (`src/logic/shot_plane.gd:19-46`) read entirely disjoint data. `LoS` reads only `grid.opacity` (set
  to `1.0` for wall cells by `MapGen.generate()`, `map_gen.gd:52-56`) — correctly treats walls as
  opaque for TACTICAL gating (aim-mode/step-out decisions). `ShotPlane.build()` only ever projects
  `state.units` and `state.grid.blockers` (`shot_plane.gd:24,33`) into the depth-sorted hit plane —
  never `grid.opacity`. `MapGen` never writes a `blockers` entry for WALL cells — only
  `_scatter_cover()` (`map_gen.gd:201-208`) populates `blockers`, and only for scattered cover props on
  `OPEN` cells. So a real wall has an opacity flag but no Part, no mesh, nothing in `grid.blockers` —
  it is entirely invisible to the actual damage-resolution path, which only ever sees shooter, target,
  and scattered-cover Parts. `docs/02` (`docs/02-projection-and-targeting.md:82-84`) already documents
  the intended fix: terrain should be "a Part flagged indestructible" living in the same plane as
  everything else — never implemented for walls, only for scattered cover.
- **View-layer confirmation:** walls have no 3D volume either — `BoardView._build_wall_indicators()`
  (`src/view/board_view.gd:239-245`) only draws a flat floor decal (`WALL_INDICATOR_HEIGHT = 0.015`)
  plus a thin decorative cross; no `CollisionShape`/`StaticBody` exists for walls anywhere in
  `src/view/`. This matches the supervisor's own observation that walls are "visually nothing" beyond
  the debug 'x' marker.
- **Fix:** `MapGen._stamp_wall_geometry()` (new, runs last in `generate()`, after
  `_ensure_spawns_connected` so it sees the grid's final layout) gives every WALL cell that borders at
  least one non-WALL cell a real, indestructible `Part` in `grid.blockers` — `data/parts/wall.tres`
  (new: a full-cell box, `is_destructible = false`, matching docs/02's own "terrain is a Part flagged
  indestructible"). A WALL cell buried in solid, unreachable rock (no non-WALL neighbor) deliberately
  gets no blocker — it can never be the nearest hit along any real ray, so skipping it is a pure perf
  win (`ShotPlane.build`'s own per-shot scan is unculled), not a behavior change.
  `LoS.has_los()` is unchanged (opacity-only) — it already correctly treated walls as opaque; only the
  hit-resolution side was blind to them.
- **Side effect, expected and not chased further this pass:** as a direct consequence of walls now
  really blocking, this landed a follow-on discovery — a live seed-search on `test/integration/
  test_full_mission.gd` (whose own hardcoded `SEED` now fails, same "a real mechanics fix reshuffles
  the deterministic timeline" pattern that test's own header already documents five times over) showed
  **81% of all impacts in one full mission (368/457) landing on a wall instead of the intended
  target** — the AI appears to fire without ever verifying a genuinely clear line of fire, trusting
  `ShotPlane` alone to arbitrate (harmless before this fix, since nothing ever blocked a shot). Likely
  why missions now grind through more turns under the fix. Not filed as its own bug yet — flagged here
  as the reason `test_full_mission.gd`'s current failure may need more than a seed re-pick, and as a
  candidate follow-up investigation into AI engagement/target selection (taskblock-45 retired the
  planner named here; the successor is `UtilityContext`/`UtilityScorer` — `UnitAI._pick_engagement_
  position`/`_engagement_score`).
- **Verified:** `test_shot_plane.gd::test_a_wall_part_between_shooter_and_target_blocks_the_shot` (a
  wall Part between shooter and target intercepts the shot; the target is still there once the wall is
  excluded) and `test_map_gen.gd::test_exposed_wall_cells_carry_a_blocking_part_interior_walls_do_not`
  (every exposed wall cell across 50 seeds carries the blocker; every fully-interior one doesn't).
  1868/1869 green — the one remaining failure is `test_full_mission.gd` itself, above, a known,
  expected consequence, not chased this pass (supervisor's own call: "consider the full test failed
  for the moment, we have a couple other things to check").
- **RESOLVED-PENDING-CONFIRMATION** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit pending.
- **2026-07-28 (supervisor check — still blocked, left `Pending` deliberately).** Cannot be confirmed
  until the drawn beams are trustworthy: this entry's evidence is read off tracers, and
  `PLAN.md`'s **Tracers and hit visuals** covers the defects that make them unreliable.
- **Three of that cluster corrupt this entry's evidence specifically**, so it cannot be signed off
  while any of them is open:
  - **BR35.07** — `STOP_DEAD` tracers drawn *past* their own hit point. A round that correctly stops at
    a wall is drawn continuing through it, which is this entry's exact symptom rendered by a different
    bug.
  - **BR34.05** — misses vanish instead of striking anything, so a round that *should* mark a wall
    leaves no evidence either way.
  - **BR35.04** — a DEFLECT's bounce tracer is a decorative fixed-range projection rather than the real
    continuation, so a post-deflection path tells you nothing about what it actually hit.
- **Re-check after that cluster lands**, not before. Watching for wall strikes against tracers that
  misreport where rounds stopped is how this entry produced three spin-off findings and no closure last
  time.

### BR32.04 — Active — owner: `SUPERVISOR`
**Clicking Resolve snaps the wall-cutout hole to the destination before the move animation catches up**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (BR27.08 rebuild review). "On clicking resolve, cull position moves to the
  right cell immediately, while animation plays separately, splitting them."
- **Explicitly not investigated yet, by instruction — "likely a process change so just flag it for
  now."** Filed only so it isn't lost.
- **Candidate mechanism, not confirmed:** `resolve_to_marker()` resolves the queued prefix against real
  `CombatState` synchronously — `unit.cell` (and whatever `BoardView.update_wall_cutout()` projects
  from `wall_cutout_units`, a live reference into `combat_state.units`) updates the very next frame.
  The visual slide itself (`ResolutionPlayer`, driven off the `queue_partially_resolved`/`turn_ended`
  event stream) plays out separately, over multiple frames, from wherever the model's own
  `HitVolumeView` transform currently sits. If the wall-cutout shader's own per-frame feed
  (`BattleScene._process()`/`BoardView.update_wall_cutout()`) reads the unit's real, already-resolved
  `.cell` rather than the model's own currently-animated transform, the cutout hole would jump to the
  destination instantly while the model is still visibly sliding toward it — a real position, but the
  WRONG one to be reading from mid-animation. Consistent with the supervisor's own "likely a process
  change" guess: whichever `_process()` feeds the cutout's unit positions would need to read the
  animated/rendered position (or hold the old one) until the slide finishes, not the authoritative
  logical cell the instant it changes.
- **Not yet reproduced or fixed.** Needs a live look, not guessed at further here.
- **2026-07-23 (tb35 Pass D — the candidate mechanism confirmed exactly, still not fixed)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Read `ResolutionPlayer._play_slide`/`_set_slide_anchor`
  (`resolution_player.gd:312-350`) directly: a move's own tween mutates `view.position`/`view.basis`
  (the `HitVolumeView` node's real, currently-animating transform) every tween step, over the slide's
  own duration. `BoardView.update_wall_cutout()` never reads that node at all — it recomputes each
  unit's own screen position fresh from `UnitGeometry.bounding_sphere(unit).center`, which is built
  from `unit.cell`, the model's own already-resolved, instantaneous cell. So the candidate mechanism
  above is exactly right: the cutout jumps to the destination the instant `resolve_to_marker()`
  mutates state, while the SAME unit's own visible body is still several tween-frames from actually
  arriving there.
  - **Fix direction (not implemented — real architectural surface, not a one-line change):**
    `BoardView` has no visibility into `HitVolumeView`'s own current transform at all today (only
    `BattleScene` holds `unit_views`); `update_wall_cutout()` needs to read the unit's own CURRENTLY
    RENDERED position (docs/00's own "read the real node back, don't re-derive it" rule, applied here)
    rather than recomputing from the logical model whenever an animation is in flight. The cleanest
    shape found by reading the code: a `Dictionary[int, Vector3]` of "current display position per
    unit," written by `_set_slide_anchor` every tween tick (it already computes the exact anchor
    needed) and consulted by `update_wall_cutout()` before falling back to the logical
    `bounding_sphere` position for a unit that isn't mid-animation. Not implemented this pass —
    correctly scoping the override's own lifecycle (when it's cleared, so a stale display position
    can't itself become a new staleness bug) wants its own careful pass, not a rushed one at the tail
    of an already-long taskblock.
### BR32.05 — Active — owner: `SUPERVISOR`
**Wall cutout cuts walls that aren't between camera and unit (coarse heuristic)**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). The cutout shape mostly works, but the *shape* is wrong at
  the edges: looking at a unit with a wall **behind** them, a chunk is cut out of the top of that wall
  even though it's ordered behind the unit; and the cut exposes the interior (wall-to-wall) textures
  of each wall.
- **This is BR32.02's explicitly-deferred facet, now the supervisor's review item.** BR32.02 fixed the
  depth *source* so the cutout appears at all; this is the separate, deferred precision problem its
  report flagged: the shader's occlusion test is a coarse single-scalar heuristic — "fragment nearer
  the camera than the unit's reference depth AND within its screen-space radius" — with **no real 3D
  ray / line-of-sight check** against the camera-to-unit line. A wall merely *near* a unit (adjacent,
  or behind but close) satisfies both conditions by geometric coincidence, so walls that aren't
  actually occluding get cut. Same root as the same-side over-cutting BR32.02 deferred (multiple
  adjacent walls cut at once in a corridor).
- **Candidate fixes (from BR32.02's own analysis, not yet chosen):** a real per-fragment ray/line-
  segment test against the camera-to-unit line, or gate on the *angle* between camera→wall and
  camera→unit rather than screen-space pixel distance + a bare depth compare.
- **Interior-texture exposure** is a sub-symptom (the cut reveals unlit/placeholder wall interiors);
  it may largely resolve once the shape is corrected, and is otherwise shader-pass polish, not worth
  chasing separately before then.
- **2026-07-25 (tb40 Pass C — elevation diagnosis, reasoned from shader source, not run; no fix, per
  the pass's own scope)** [CC d0685fa0-63d7-4f3e-b29b-f52886a5e0bc]. Read `wall_cutout.gdshader`'s
  `fragment()` and `BoardView.update_wall_cutout`/`WallLegibility.pixel_radius_for_tiles` end to end
  against two named cases (unit on level 3, wall at level 0 in front and below, genuinely occluding —
  should cut; unit on level 0, wall at level 3 behind them, occluding nothing — should not cut).
  **Same root cause as the rest of this entry — no real ray/line-of-sight test — but elevation opens a
  genuinely new way for the SAME coarse heuristic to misfire, not just a bigger blast radius on the
  existing same-side over-cut:**
  - **The depth gate (`frag_depth >= unit_depths[i]` → skip) is itself already elevation-correct.**
    Both sides of the compare are real 3D Euclidean distances (`length(view_pos.xyz)` reconstructed
    from the hardware depth buffer on the shader side; `camera_position.distance_to(bounding_sphere(
    unit).center)` on the GDScript side, and `bounding_sphere` already reads `unit.height` — real
    elevation, not a flattened ground-plane read). Nothing here assumes a flat map.
  - **Case 1 (should cut) is not newly broken by elevation.** A fragment that is genuinely ON the
    camera-to-unit ray projects, by definition, to very nearly the SAME screen position as the unit
    itself — screen-space proximity is not a flat-map assumption, it's true of any real 3D projection
    regardless of height. Reasoned through; no failure mode found here.
  - **Case 2 (should not cut) exposes a case the depth gate cannot catch once height varies.** On a
    flat map, "positioned behind the unit relative to the camera" and "farther from the camera in
    Euclidean distance" are the same condition, because everything sits near one shared height — so
    the depth gate has always doubled as a correct "is this wall really between camera and unit" proxy
    *for that reason*, not because it's a real occlusion test. Once a wall can be elevated far above a
    low unit, that equivalence breaks: a wall that is horizontally BEHIND the unit (farther along the
    ground-plane line from camera through unit) can still be Euclidean-NEARER to an elevated camera
    than the low unit is, purely because it sits closer to the camera's own altitude — geometry no
    flat map can produce. `frag_depth >= unit_depths[i]` then evaluates false (wall reads as nearer),
    the screen-space radius check is the only remaining gate, and `WallLegibility`'s own doc comment
    already concedes that gate was sized for "the tactical camera sits well above and back... a wall
    within N world units of that [camera-to-ground-unit] ray almost never fires" — a premise about
    where walls and units sit relative to the camera that elevation is specifically what breaks.
  - **Conclusion: do not open a new BUGS.md entry** — the fix (a real ray/line-of-sight test, or
    gating on the angle between camera→wall and camera→unit, both already named above as candidate
    fixes) is the same fix this entry already wants; elevation just adds one more concrete geometry
    that motivates it, worth having on record for whoever picks the candidate fixes.
- **taskblock-51 Pass A — elevation is not the variable.** The supervisor set cell levels to vary the
  vertical separation and the misbehaviour was unchanged, which rules out the "cannot distinguish
  vertical from horizontal separation" half of the suspected cause and leaves the screen-space
  heuristic itself.
- **Supervisor's proposed fix, recorded as theirs:** the cutout is a 2D projection taken at the camera
  angle; **tilt that projection to vertical and align it with the grid tiles** and the problem is
  bypassed rather than tuned. This is a different shape from taskblock-51's own suggestion of a ray or
  angle test in the shader, and it is cheaper — worth trying first.
- **taskblock-51 duplicate check — not a duplicate, but the cutout has been "fixed" three times
  already.** `BR31.03` (*wall fading never visibly occluded anything*, `Obsolete`), `BR32.01` (*stray
  hole at a cell with no unit*, `Resolved`) and `BR32.02` (*never visibly appears near real units*,
  `Resolved`) are all archived against this same shader path.
- **That history is the finding.** Three closures and the subsystem still misbehaves suggests the
  heuristic itself is the defect rather than each symptom — which is what the supervisor's own proposed
  fix says: stop projecting at the camera angle, tilt to vertical and align to grid tiles. **Check the
  archived three before starting**, so a fourth symptom-level fix is not attempted.
### BR32.07 — Active — owner: `SUPERVISOR`
**Burst at/through a wall aims, then silently fails (no AP, no queued action)**
- **Source:** `SUPERVISOR`
- **2026-07-23 (supervisor re-check — the symptom has SHIFTED).** It is now reported as **"cannot
  seem to aim at a wall with burst"** — i.e. the aim step itself no longer engages, where the original
  report was "lets you aim the dartboard, then silently fails out." That is a different failure point,
  not a rewording: something between tb32 and now moved the failure *earlier*, from confirm/queue to
  aim. Prime suspect is tb34's targeting rework — `ShotScatter.for_shot` and the `TargetingMode`
  dispatch both sit in the burst aim path, and tb32 Pass C's `HitKind.PART` targeting is what makes a
  wall aimable at all. Re-derive the failure point before fixing; the original diagnosis (the PART
  branch of `BurstAction.is_legal()`/`apply()`) may now be aimed at the wrong seam.
- **Reported:** 2026-07-22 (tb32 review). A shot **directed at a wall or through a wall** (both cases)
  lets you aim the dartboard, then silently fails out — no AP spent, no action queued. Appears
  **burst-specific**.
- **Where to look:** tb32 Pass C made non-unit Parts targetable (`HitKind.PART`,
  `Grid.shootable_part_at`) and Pass D routed burst through `TargetingMode`. `BurstAction` legality
  now accepts a PART target, but the confirm/queue path silently no-ops for burst against a wall — the
  aim succeeds (dartboard opens) but nothing commits. Likely `BurstAction.is_legal()`/`apply()`'s PART
  branch (vs `AttackAction`'s) or the burst confirm path dropping the action. Contrast with single
  shoot to isolate. Related in spirit to BR30.11 (burst step-out silently dropping the shot) — check
  whether it's the same silent-drop seam, and whether the intent/outcome logging idea in PLAN would
  have surfaced it.
- **2026-07-23 (tb35 Pass C — re-derived the failure point, found no code-level break)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Traced the full aim-entry chain for a burst-armed click
  on a wall cell end to end: `TacticsController.click_cell` → `PartPicker.hit` (`HitKind.PART`) →
  `_enter_aim_mode` → `aim_state()` → `AimController.resolve()` → `ShotScatter.for_shot()`. Every step
  is generic over action id — `ActionCatalog`'s own `&"burst"` entry gets the same `TargetingMode.
  BOARD` as `&"shoot"`, `_click_part()` dispatches on `armed_action != null` alone, and
  `ShotScatter.for_shot()` never even receives the `AimTarget`, only `target_cell`/`weapon` — it
  cannot distinguish a wall target from a unit target and has no code path assuming a live `Unit`.
  The one place action id is read in this whole chain (`AimController.recoil_bound_radius`) only
  gates a cosmetic ring overlay, guarded against a null/empty case, and cannot block aim entry.
  **New headless regression, confirmed passing:**
  `test_tactics_controller.gd::test_arming_burst_and_clicking_a_wall_enters_aim_mode` — arms burst,
  clicks a real wall-blocker cell, asserts `aiming_at != null` and `aim_state()` non-empty. Passes
  cleanly. **Not fixed, because nothing reproducibly breaks at this level** — if the live symptom
  persists, it likely lives outside the `TacticsController`/`AimController`/`ShotScatter` chain (a
  render-layer/raycast issue in the real click path, or `PartPicker`'s own collision setup against
  live `BoardView` scene nodes — the same class of headless-vs-live gap BR27.08 hit) rather than in
  the targeting logic itself. Recommend a live re-check before further investigation here; stays
  Active, not Pending, since no fix was made.
### BR32.08 — Suspected — owner: `SUPERVISOR`
**Dead or knocked-out shells may have strange cutout behavior**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). Not observed directly — flagged as a likely edge case: a
  dead or knocked-out shell may feed or interact with the wall-cutout oddly (still in
  `CombatState.units`? still fed to the cutout? faded as a friendly? left with a stale cell like
  BR32.01?).
- **Suspected, not confirmed** — logged so it isn't lost; confirm/describe at a review pass. Shares
  the unit-feed edge-case family with BR32.01 (extracted/removed) and BR32.03 (carryover).
- **taskblock-51 Pass A — did not reproduce, and the attempt is recorded rather than the conclusion.**
  The supervisor fired shots near a dead body in the spectator view and saw **no obvious cutout
  behaviour** around it. That is not a clearance: this entry is `Suspected` precisely because the
  original observation was vague, and one session that did not see it does not establish it never
  happens. **What was tried:** shots resolving near a downed shell, watched from the spectator view.
  **What was not:** a shell downed *between* camera and a living unit, which is the geometry the
  cutout actually keys on.

### BR32.09 — Active — owner: `SUPERVISOR`
**Spectator: current-unit indicator jumps to the next unit before the active turn resolves**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review, direct note). In spectator, the current-unit indicator
  advances to the next unit before the active unit has finished resolving its entire turn.
- **Likely the spectator-side sibling of BR27.07's ordering bug.** tb32 Pass D fixed the *player*-view
  early-flip by deferring `apply_active_turn_highlight()` until after the resolution animation
  (`SquadControlOverlay._on_turn_ended()`), but the spectator path wasn't touched — its indicator
  still flips ahead of resolution. Apply the same defer-until-animation-finishes fix on the spectator
  overlay's turn-end handler.
### BR33.01 — Suspected — owner: `SUPERVISOR`
**Aim-view scroll cycles walls; layer labels read as part names**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb33 review). Scrolling while aiming "cycles parts on a unit (or at least
  it looks that way)." The original intent: scrolling cycles between the current enemy and what stands
  *behind* it — preferably other enemies, with cover acceptable now that cover is real.
- **The mechanism is correct; the input to it isn't.** `AimController.layers_for` groups the shot
  plane by `region.body` and sorts nearest-first — one layer per distinct body, which *is* the
  intended "current enemy, then what's behind it." `ShotPlane.build` sets `region.body = unit` for a
  unit's parts and `= part` for an unowned cover Part, so grouping is genuinely body-level, not
  part-level.
- **What changed:** tb31 C turned walls into cover-`Part`s that live in the shot plane, so **every
  wall is its own body and therefore its own aim layer**. Scrolling a walled scene now cycles wall
  after wall. Compounding it, `AimView._body_name` renders a non-Unit body as its raw part id
  (`wall`, `scrap_pile`, `pillar`) — debug strings that read like part names, which is most likely
  what makes it look like part-cycling. A three-blocks-earlier change to terrain quietly degraded
  aiming; nobody connected the two.
- **Suspected, and deliberately not fixed yet.** The supervisor will observe scroll behaviour on
  tb34's finished aim view before deciding — the fix is a policy call, not a mechanism one.
  **Options when decided:** skip walls by default (cover still reachable), rank enemies ahead of cover
  regardless of depth, or collapse contiguous walls into a single layer; plus player-facing names
  instead of `unit_3` / raw part ids.
- **taskblock-51 Pass A — still reproduces, no new information.** The supervisor adds that **this
  feature is not what they originally intended** and is *"more likely to be obsoleted than fixed"* —
  the aim-view scroll cycling walls is a symptom of a design they no longer want, so effort spent
  fixing it may be spent on something due for removal. **Do not fix ahead of that decision.**

### BR34.01 — Active — owner: `SUPERVISOR`
**Every penetration/deflection hop replays the full bright hit-flash, not just the first**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (live playtest). A single queued shot that penetrates or deflects through
  several objects visually reads as multiple separate shots firing — "the bright raycast flashing
  should only play for the first hit," not for every subsequent hop of the same trigger pull.
- **Root cause, read-only investigation (quick look, not a fix):** `DamageResolver.resolve_shot`
  correctly returns one `Array[ImpactResult]` per trigger pull, one entry per hop (wall, then cover,
  then the target, say) — that's the right granularity for damage/consequence bookkeeping.
  `ResolutionPlayer.play()` (`resolution_player.gd:148`) reuses that SAME granularity directly for
  PLAYBACK: its own loop treats every `&"impact"`/`&"miss"` `LogEvent` as an independent "shot"
  (`is_shot := event.kind == &"impact" or event.kind == &"miss"`), inserting `INTER_SHOT_BREAK_MS`
  between them, and `_play_impact()` (`resolution_player.gd:440`) unconditionally calls
  `_spawn_tracer()` — the full bright-live-to-dull-fade flash — for every one of them. Nothing in
  `LogEvent.data`/`ImpactResult` distinguishes "the first hop of this trigger pull" from "hop 2+,
  the same round continuing forward" — the log's own per-hop granularity (correct for its own job) is
  being read as the playback's own per-shot granularity (wrong for this job), conflating two different
  concerns. A 3-hop PENETRATE chain from one queued attack currently plays THREE full bright flashes
  with pacing gaps between them, reading as three separate trigger pulls.
- **Distinct from BR27.02** (the backward-tracer-direction ticket) — this is about flash/pacing
  REPETITION per hop, not the direction of any single segment. Both live in the same playback/
  resolution-geometry neighborhood but are separate defects.
- **Not investigated further, no fix attempted** — logged per instruction. A real fix needs a design
  call on what SHOULD distinguish "first hit of a pull" from "continuation," which doesn't exist in
  the data today (candidate: thread a hop index/continuation flag through `ImpactResult`/`LogEvent`,
  then have `ResolutionPlayer` skip the live flash — or use a dimmer one — and skip the inter-shot gap
  for hop index > 0). That's a design/implementation question for whoever picks this up, not answered
  here.

---
### BR34.03 — Active — owner: `SUPERVISOR`
**`AttackAction` in the move queue isn't label-pruned like `MoveAction`**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb34 review). The queue row for an attack still renders the verbose default
  form; it should read as compactly as the move rows now do — `AttackAction(unit=2)`.
- **Known pattern, already solved once:** BR27.08's follow-up work shortened the `MoveAction` queue
  label (commit "keep the queued suffix on partial resolve, short Move label"). Apply the same
  treatment to `AttackAction` — and while in there, check the remaining action types (burst, overwatch,
  repair, the melee actions) rather than fixing one and leaving the next to be reported separately.
### BR34.04 — Active — owner: `SUPERVISOR`
**Sniper camera frames the target from an odd angle**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (post-tb34 check). tb34 Pass D's sniper framing engages past 5 cells and
  does centre the target, but the viewing angle it centres *from* reads wrong.
- **Supervisor-specified intent:** the camera should sit **directly above the line drawn between
  shooter and target**, looking along it — so the shot's own geometry is what you're reading, rather
  than an arbitrary heading that happens to contain the target.
- **Why it landed this way (not a defect in the code, a gap in the spec):** tb34 Pass D deliberately
  *kept the rig's existing yaw/pitch* and only solved zoom, because this rig always faces its own
  `pan_offset` pivot — so setting `pan_offset = target.center` centres the target at any angle, and
  the taskblock only asked that it centre. CC flagged exactly this as decision 4 ("keeps the shooter
  out of its own solve entirely… computing a shooter-relative viewing direction anyway would have been
  unrequested scope"). The decision was correct against the spec as written; the spec was
  under-specified. **The fix is the shooter-relative solve that was explicitly not done:** derive yaw
  from the shooter→target vector and position above it.
- Camera math — verify by reading the built node's `global_transform`/`unproject_position` back, per
  `docs/10` rule 2, including a diagonal case (the yaw bug that rule exists for survived a full suite
  of row/column-aligned cases).
- **taskblock-51 Pass A — the aim camera is a fixed rig, and that is the lead.** The supervisor reports
  it sits **back and right of the shooter** while shots land **left** — *"a possibly matching angle"*.
  A fixed offset producing a fixed error in the opposite lateral direction is a transform that has not
  been undone, not a roll. See `BR51.01`, which this may be one defect with.
- **The camera cannot be orbited to test this**, so the screen-relative/world-relative split proposed in
  taskblock-51 is not available. Diagnose it headlessly against the resolved ray instead.

- **taskblock-51 Pass A — the supervisor's own framing of the fix:** the sniper camera *"should
  probably be a short distance from the target, in line between shooter and target"*. Today it frames
  from a high angle. That is a solvable framing constraint rather than a bug in the solver, and it is
  the shape to aim at.

### BR34.05 — Active — owner: `SUPERVISOR`
**Misses vanish instead of striking anything**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (post-tb34 check, during the BR30.10 verification). A missed shot appears
  to travel into nothing — it strikes no obstacle at all on its way out, passing through an arena that
  is enclosed on every side.
- **Supervisor's stated rule for how this SHOULD work — a design statement, not just a repro:** a shot
  should **nearly always hit something**. The floor, or one of the many walls surrounding the arena.
  The only legitimate ways for a round to hit nothing are **through an already-broken wall** or **out
  through the ceiling**. Anything else vanishing is wrong.
- **Why this matters more than a visual nit:** it means "miss" is currently modelled as *terminate the
  round*, rather than *continue until something stops it*. That has real consequences now that walls
  are destructible and decompression is a planned hook — a missed burst that should be chewing a wall
  behind the target is instead doing nothing, and the arena never accumulates the damage a firefight
  should leave. It also interacts with **BR34.01** (per-hop playback): a miss that continues has hops,
  and hops are what that entry is about.
- Likely the same neighbourhood as tb35 Pass B's depth floor and the `&"miss"` handling in
  `ResolutionPlayer`/`shot_resolution.gd` — check whether a miss even builds a continuation ray, or
  simply stops.
- **2026-07-23 (tb35 Pass B2 — root-caused and reproduced, not fixed)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. `resolve_shot` does build a real continuation — the
  question was never "does it try," it genuinely finds nothing to hit in some cases. Reproduced
  directly: fired hundreds of simulated shots (`DamageResolver.resolve_shot`) from a unit standing in
  a fully-walled room (real `grid.blockers` Parts on every perimeter cell, both a hand-built room and
  real `BoutSetup`-generated maps) with a wide range of aim points. At an ordinary/tight lateral
  offset (|x| under ~1 unit — the range any single weapon's own authored scatter ring realistically
  produces), **zero** shots vanished, before or after this taskblock's own depth-floor fix — so this
  is a genuinely different defect from BR34.06/BR27.02, not the same one re-surfacing. Once the
  lateral offset is pushed wide (|x| beyond ~4-5 units), misses start appearing reliably (56/200 at
  |x| up to 8) — **`ShotPlane.build` projects each wall cell as its own independent rect; adjacent
  cells' projected rects are not guaranteed to tile edge-to-edge from an arbitrary shooter angle, so a
  sufficiently wide lateral offset can thread a real gap between them and pass clean through, even
  though the room is genuinely enclosed.**
  - **Why a real weapon can reach that range:** a burst's own scatter widens per pull
    (`RecoilResolver.widen`, `factor = 1.0 + resolved_step * recoil_step`) — a late pull in a long
    burst (the chaingun bursts logged elsewhere in this file routinely run 20-30 pulls) can multiply
    the base outer ring (chaingun: `0.6`) several times over, and `RangeModel.dartboard_radius_scale`
    widens it further at long range (up to `1.0 / ACCURACY_FLOOR ≈ 2.86x`). The two compound: a late
    pull of a long burst fired at range is exactly the shape of shot most likely to reach the lateral
    offsets that expose this gap — and exactly the shape of shot ("the most recent chaingun bursts")
    this ledger already has several live reports about.
  - **The supervisor's own "or the floor" half of the design rule has no geometry to hit at all** —
    `ShotPlane.build` only ever projects `state.units` and `state.grid.blockers`; there is no modeled
    floor/ground-plane Region anywhere in this system. That half of the fix is a real feature gap, not
    a bug in existing code.
  - **Not fixed this pass — needs a design call, not an invented number.** This touches `ShotPlane`/
    `BodyProjector`, the shared geometry every single shot in the game resolves against; three
    directions, not picked between: (a) make adjacent same-material blocker cells project as one
    contiguous rect run instead of independent per-cell boxes, closing the seam at the source: (b) cap
    dartboard scatter radius (post-recoil, post-range-widen) at some bound that guarantees plane
    coverage — a real balance number, not this session's to invent; (c) add a genuine floor Region so
    at least the "hits the floor" half of the design rule has something to resolve against. Flagging
    for supervisor/design input rather than guessing.
- **taskblock-51 third hunt — the supervisor re-reported this and CC mis-filed it as a new entry
  (`BR51.03`), now folded back here.** Their words: *"Misses still happening when there is something for
  a bullet to hit; damage should drop outside of range but the bullet should still hit something"*, and
  on being asked whether it was a design change rather than a defect: *"Leave it as a bug, I tried to
  have this changed before so if it's still occurring it's a bug."* — which is this entry, reported
  2026-07-23.
- **One nuance the re-report adds:** range should **attenuate damage**, not delete the projectile. That
  sharpens the fix: the termination is happening at the range gate, not only at the resolution.
- **Still open, still `SUPERVISOR`-owned. Nothing was closed by the merge** — a duplicate record was
  removed, not a bug.
### BR35.01 — Active — owner: `CC`
**`PartPicker.hit` scans every `grid.blockers`/`field_items` entry on every hover, not just ones near the ray**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23 (tb35 Pass C, `Grid.blockers` audit sweep). `PartPicker.hit()`
  (`part_picker.gd:40,48`) iterates every entry in `grid.blockers` and `grid.field_items`
  unconditionally, running a full per-box ray test (`_nearest_t`) against each one regardless of the
  ray's own direction or distance from it. Before tb31 C, `blockers` held a handful of scattered cover
  props — cheap to fully scan. Now it holds every wall cell on the map (confirmed: real generated
  bouts run 200+ blocker entries), and this runs on **every mouse-move**, not just clicks
  (`TacticsController.update_hover()` calls `_cell_at()` → `PartPicker.hit()` on hover, per its own
  doc comment) — a real, newly-introduced per-frame cost, not hypothetical.
- **Not fixed this pass.** The safe fix (march only cells the ray plausibly crosses — a bounded
  grid-DDA walk along the ray's own 2D projection, the same shape `LoS.has_los` already bounds its own
  opacity walk to) touches core picking geometry with a real risk of silently skipping a genuine hit
  if the bound is gotten wrong, and this codebase has already been burned once by a plausible-looking
  formula nobody could verify without a live client (docs/00's own attack-camera yaw story). Flagging
  rather than guessing at a fix under time pressure.
- **2026-07-26 — NOT addressed (tb42 Pass E)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Named in
  the pass as a companion item and deliberately left: `PartPicker.hit` still scans every
  `grid.blockers`/`field_items` entry per call. Stated rather than quietly dropped — it is `CC`-owned
  and small, and belongs to whoever picks this up next.
- **taskblock-51 — measured, and it is NOT the aim-view framerate cause.** `PartPicker.hit` costs
  **1 559 usec** on a 214-blocker board against `ShotPlane.build`'s **10 889**. `BR26.02` was caused by
  the aim plane being rebuilt per mouse motion, not by this scan.
- **Still worth fixing on its own merits** — it is real waste on every hover — but this entry has now
  absorbed three reasoned-not-measured fixes, and the standing instruction to measure first applies
  with more force, not less, now that the obvious theory has been falsified once.

### BR35.02 — Active — owner: `SUPERVISOR`
**Spectator's tile-inspect click can silently resolve to a cell hidden behind a wall**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23 (tb35 Pass C, view-layer `Grid.blockers` audit sweep). `SpectatorOverlay`'s
  tile-inspect path (`_unhandled_input`) resolves a click via `BoardPicker.cell_at_ray` — pure
  `y == 0` ground-plane math with no geometry/occlusion awareness at all. Before tb31 C, cover was
  short and sparse, so a ground-plane hit reliably matched the tile the camera could actually see. Now
  walls are 2.4m tall and dense; a click that LOOKS like it's on a wall's face, or on an open tile
  actually hidden behind a wall from the camera's own angle, still resolves via blind plane math to
  whichever cell the ray crosses at `y=0` — which can be a cell on the far side of the wall, never
  visible at all. The only existing filter excludes the resolved cell if IT ITSELF is a wall tile; it
  does nothing for a resolved open tile that's occluded by an intervening one.
- **Not fixed this pass.** Needs a real line-of-sight/geometry check between the camera and the
  resolved cell (or a real physics/geometry raycast against the wall meshes `BoardView` already
  builds) before trusting `BoardPicker`'s own result — a genuine new check, not a one-line guard, and
  risky to improvise without live verification.
- **2026-07-28 (review session `HBPaR3`) — promoted to `SUPERVISOR` ownership.**
- **Do not fix this one individually.** It is the third of a set — with BR27.04 (lighting differs
  between the two views) and BR32.09 (spectator's current-unit indicator jumps early) — all of which
  are the same root: `SpectatorOverlay` re-implements a subset of `SquadControlOverlay`'s panels
  because it cannot inherit them without dragging in `TacticsController` and the whole unit-input path.
  `PLAN.md`'s *One view, toggleable modules* dissolves the class. Fixing an instance is work that
  refactor discards.

### BR35.03 — Active — owner: `CC`
**Every debug-panel verb rebuilds the entire board view, not just ones that touch blockers/field items**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23 (tb35 Pass C, view-layer `Grid.blockers` audit sweep). `SpectatorOverlay.
  _on_debug_panel_applied()` calls `battle.sync_board_view()` (a full teardown/rebuild of every
  static mesh — walls, field items, indicators) after **every** debug verb, including ones with no
  possible effect on board geometry (`set_ap`, `set_mp`, `force_current_unit`, ...). Before tb31 C
  this rebuilt a handful of props each time; now it rebuilds hundreds of wall meshes on every single
  debug action regardless of relevance. Debug-build-only (`OS.is_debug_build()`), so the blast radius
  is limited, but it's a real, newly-heavier cost every time.
- **Not fixed this pass.** The fix is straightforward in shape (gate the rebuild to verbs that can
  actually touch `grid.blockers`/`field_items` — `move_object`/`spawn_object`/`remove_object`) but
  getting the verb-id list exactly right (not missing one that can add/move/remove a blocker or field
  item) wants a careful pass of its own rather than a rushed guess at the end of an already-long one.
- **2026-07-26 — `Pending` (tb42 Pass E)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Both overlays'
  `_on_debug_panel_applied` called `sync_board_view()` — a full `BoardView.build()` of terrain, grid
  lines, every blocker and every field item — after **every** verb, including the ~20 that only ever
  touch one unit's AP, facing, pose or parts. `DebugVerbs.affects_board()` is now the one authority
  both overlays read; the same question answered separately in two files is how they drift.
  `move_object`/`remove_object` stay in the list unconditionally: either can target a cell or a unit,
  decided at call time, and a missed board rebuild is invisible-until-noticed while an extra one is
  merely slow.
  - A test checks the list against `DebugVerbs.all()`, and immediately earned it: my first draft
    listed `place_cover`/`clear_cover`, which are **not** panel verbs (the panel exposes
    `spawn_object`/`remove_object`, which front both). They matched nothing and would have quietly
    misled the next reader.
  - **To confirm:** open `Inject...`, apply a unit-only verb (Set AP, Set Facing), and check the board
    does not visibly rebuild; then apply Set Cell Level or Spawn Object and check it does.
- **2026-07-28 (review session `HBPaR3`) — moved from `Pending` back to `Active`.** A `CC`-owned
  `Pending` is not a stable state: `Pending` means the *owner* has not seen the fix work, and CC is the
  owner here. Either it is verifiable and should be closed, or it is not and CC is the wrong owner.
  Returned to `Active` so it is picked up in the next bug hunt rather than sitting in a status that
  nobody can discharge.

### BR35.04 — Active — owner: `SUPERVISOR`
**A DEFLECT's drawn "bounce" tracer is a decorative fixed-range projection, not the real continuation**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **2026-07-23 (supervisor observation — independently seen, and a decision made).** Observed live as
  *"some drawn deflect raycasts are blue"* — the same defect from the visual side that this entry
  found in the log. The blue segments are exactly these decorative fixed-range projections; the real
  continuation, when one exists, is a separate `stop_dead` ray drawn independently.
- **Supervisor's call: remove the decorative projection entirely.** Do not try to make it agree with
  the real resolution — draw only geometry that corresponds to something that actually resolved.
  A tracer nobody can distinguish from a real hit, drawn to an arbitrary distance, is worse than no
  tracer: it invented the "wall impacts" the supervisor spent a whole review session investigating.
  **Owner promoted to `SUPERVISOR`** — the fix is visual, so closure needs a live look.
- **See also BR35.07**, the same class of defect on the `STOP_DEAD` tracer (drawn past its own hit
  point). Filed separately per the supervisor's own rule that one entry tracks one observed symptom.
- **Found:** 2026-07-23, reading a real chaingun burst out of `out/combat.log` at the supervisor's own
  request. Every `DEFLECT` outcome logs a `deflect_end_x/y/height` (`shot_resolution.gd:225-232`),
  drawn by `ResolutionPlayer._play_impact` as a second, visually distinct segment
  (`resolution_player.gd:457-478`) — but that endpoint is `hit_point + reflected_dir * void_range`,
  where `void_range` is just the weapon's own authored max range (or the map's longest side,
  unauthored) — **a fixed-distance projection with zero awareness of whether anything is actually
  there.** The code's own doc comment says this is deliberate: drawn "regardless of whether a real
  ricochet hop happens to follow it." Meanwhile `DamageResolver` separately does a REAL recursive
  search along that same reflected direction, and when it finds something, that's its own
  independent, correctly-resolved `impact` event (a `STOP_DEAD`/`PENETRATE`/etc. a few lines later in
  the log) — with its own separately-drawn tracer.
- **The two are drawn as if they agree; they usually don't.** On a real burst read from the log: a
  deflect at (24.91, 4.01) had a REAL follow-up wall hit only ~3.7 units further on, at (25.65, 0.43)
  — but the cosmetic bounce line was drawn a full 12 units out (the chaingun's own max range) in the
  same direction, sailing straight through/past the real wall with no awareness it was there. Two
  visually distinct tracers, same origin, same direction, different endpoints, both drawn as if
  each were the truth. For pulls where the real recursive search found NOTHING (most of them, in
  that same burst), the "wall impact" the supervisor visually saw was **purely the decorative
  projection** — no wall actually took damage there, nothing mechanical happened at that point at
  all; whether it visually reads as a hit is coincidence.
- **Why this matters more than a visual nit (supervisor's own framing):** visible raycasts need to
  match under-the-hood behavior as closely as possible, specifically *because* CC's own debugging
  process depends on reading the log and reasoning about what the drawn scene must have looked like —
  a drawn tracer that routinely disagrees with the mechanically-resolved outcome breaks that
  correspondence, the same class of problem the whole `docs/00` "read the real node back" rule exists
  to prevent, just on the logging/replay side instead of the geometry side.
- **Not fixed yet.** Candidate fix: when the real recursive search succeeds, draw the bounce segment
  to THAT hit's own real coordinates (already logged as its own event) instead of the fixed
  `void_range` projection — the cosmetic projection should only ever be the fallback for the case
  where the recursive search genuinely finds nothing, mirroring `log_miss_result`'s own "void" ray
  exactly, not a separate always-drawn distance regardless of a real hit existing.
### BR35.05 — Active — owner: `CC`
**`approach_path`/`closing_path` have no ally-awareness — squadmates converge into each other's own line of fire**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23, reading a real bout's own `out/combat.log` at the supervisor's own request
  ("units that are close all holding action"). On turn 0, units 1/2/3 (all sharing a similar start
  position and the same target) independently compute nearly identical `closing_fallback` paths —
  unit 1 and unit 3's own move sequences share the corridor `(6,14)→(7,13)→(7,11)→(11,7)` cell for
  cell — and end up bunched close together: unit 1 at (13,7), unit 3 at (13,8), **directly adjacent**.
  Unit 0's and unit 2's own `ai_decision` lines log `held: ally_in_line` — a squadmate is standing
  in their own intended shot.
- **Root cause:** `LineOfFire.approach_path` (tb33) and `LineOfFire.closing_path` (tb35 Pass A, this
  session) both compute "the nearest cell that gets a shot" (or "the nearest cell that closes
  distance") purely from grid/LOF geometry — **neither has any notion of where other allies already
  are or are heading.** `closing_path` inherited this blind spot from `approach_path` rather than
  fixing it. When several squadmates share a similar starting position and target, they independently
  converge on the same corridor/destination and end up close enough to block each other's own shots,
  which then makes every one of them hold.
- **Not fixed yet.** A real fix (giving the fallback pathing awareness of cells allies already occupy
  or are heading toward, so a squad spreads out instead of stacking) is a genuine design question —
  how much to weight "don't stack with an ally" against "get to a real shot as fast as possible" —
  not a one-line patch, and not guessed at here.
### BR35.07 — Active — owner: `SUPERVISOR`
**`STOP_DEAD` tracers are drawn past their own hit point, reading as a penetration that never happened**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb35 review, live). A drawn `STOP_DEAD` ray continues visibly *beyond* the
  point where it actually stopped, so a round that was halted dead reads on screen as though it
  punched through and carried on.
- **Same class as BR35.04, different outcome type:** tracer geometry drawn from something other than
  what the resolver actually produced. Where BR35.04 is a deliberately decorative fixed-range
  projection on `DEFLECT`, this is a `STOP_DEAD` segment overshooting its own resolved endpoint —
  worth confirming whether it shares the same drawing path (`ResolutionPlayer._play_impact`) and the
  same "draw to a distance, not to the hit" habit, or is a separate length/endpoint error.
- **The reason this matters beyond looks:** it makes the two outcomes visually indistinguishable.
  `STOP_DEAD` and `PENETRATE` are mechanically different results, and if a stopped round is drawn
  like a penetrating one, the player cannot read what their weapon actually did — the same class of
  harm as the dartboard understating spread (tb34): the display teaching a rule the sim doesn't
  follow.
- Filed separately from BR35.04 per the supervisor's own convention — one entry per observed symptom,
  cross-linked, rather than bundling by shared root.

### BR35.08 — Active — owner: `SUPERVISOR`
**Detonations are invisible — nothing is drawn when an explosion resolves**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb35 review, live). A detonation resolves mechanically but draws nothing
  at all, so neither the fact of the explosion nor its extent is visible.
- **Supervisor-specified presentation (a spec, not a suggestion):** draw a **translucent red sphere**
  originating at the detonation point that **grows outward**, its **final radius matching the actual
  explosion radius** — so the visual is a readout of the real mechanical extent, not decoration —
  then **fades out**.
  - **Grow : fade time ratio is 1 : 3.**
  - **Total time is exposed as a tunable in the same place bullet timing lives**, defaulting to
    **1000 ms**.
- **Read the radius from the resolved detonation, never a parallel constant.** The whole value here is
  that the sphere teaches the player the real blast extent; a separately-authored visual radius that
  drifts from the mechanical one would be BR35.04's mistake again in a new place — a drawn thing that
  looks authoritative and isn't.

- **taskblock-51 Pass A — blocked, not attempted.** The deterministic route (spawn a goo barrel, zero
  its HP) is unavailable because `set_part_hp` cannot target a non-unit part (`BR51.02`), and the
  fallback of shooting one is unreliable because of `BR51.01` and `BR51.03`. **Three bugs deep before
  this one can be looked at** — which is the argument for fixing `BR51.02` before anything else in the
  block.

### BR40.01 — Active — owner: `CC`
**Attack-camera framing can end up looking THROUGH the shooter's own standing platform when the
shooter is elevated on a small platform and the target is below**
- **Source:** `CC`  ·  **CC session:** `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`
- **Reported:** 2026-07-25 (tb40 Pass D, discovered building checkpoint 8's own loadable scenario —
  not something Pass B's headless height-delta matrix could have caught: that matrix checks only
  whether both bounding SPHERES fit inside the FOV cone, with no scene geometry in the harness at all
  to occlude against. `checkpoint_8.gd`'s scenario B is a real render, with a real platform.)
- **Repro:** `./checkpoint.sh 8` → `b_target_below.png` (shooter on a 3x3 platform at level 3, cell
  (5,3); target on the ground at level 0, cell (1,3); a real wall at (3,3)). The rendered frame shows
  almost nothing but a huge, near, blank green expanse — no wall, no target, no drop-off — filling
  the whole visible area.
- **Root cause, confirmed numerically** (reproduced the exact solve standalone):
  `CameraOrbitState.attack_framing(shooter, target)` for this pair solves `camera_pos = (8.49, 3.6,
  2.1)` — **x=8.49, well past the platform's own far edge (the platform only spans x in [4,6])**,
  because `_solve_back` pushes the camera backward along the shooter->target line far enough to fit
  both bodies' angular footprint, with no awareness that "backward" here walks the camera clean off
  the platform the shooter is standing on. The platform's own solid mass — quite close to the camera
  now, and directly on the line toward the target — fills the frame. `_both_fit`'s own fit check
  still reports true throughout, correctly, because it only tests each SPHERE's angular footprint
  against the FOV — it has no concept of intervening solid terrain at all, on a flat map or this one.
  This is a real gap in the solver, not a mock/scenario artifact: any elevated stand small enough for
  `back` to walk the camera past its own edge would reproduce this in real play, not just this
  fixture.
- **Not fixed.** Out of taskblock-40 Pass D's own scope (build a loadable scenario + checklist, not a
  camera fix) and out of Pass B's own scope too (Pass B's fence was "fix the vertical anchor if the
  numbers show a problem" — this isn't an anchor-height problem, it's a missing occlusion/terrain
  awareness the anchor fix wouldn't touch). Candidate fix directions, not chosen: cap `back` at the
  shooter's own platform extent (clamp the search's `hi` to stay within the shooter's floored area,
  where knowable), or a real occlusion check against `Grid.blockers`/placed `Surface`s alongside the
  angular fit — the same class of fix BR32.05 already wants for the wall cutout, possibly shareable.

