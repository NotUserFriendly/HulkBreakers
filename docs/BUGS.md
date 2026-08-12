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
only ever write `Pending`. **The supervisor may promote any entry to `SUPERVISOR`
ownership at any time**, including CC-found ones, so that anything worth watching cannot be silently
closed. Owner is the gate; read it, not the source.

**Status legend:**
- `Active` — open.
- `Suspected` — a possible lead, not yet a confirmed or fully described bug. The reporter refines it
  into a real status at their review pass.
- `Pending` — the fix is complete and CC believes it works, but the owner hasn't seen it
  work yet. The only status CC may write toward closure on a `SUPERVISOR`-owned entry. 
  (Pending *what*: the owner seeing it work.)
- `Resolved` — confirmed fixed by the owner.
- `Obsolete` — the entry can no longer be confirmed or reproduced because the code it describes was
  replaced or removed, not because anyone verified a fix. Closing an entry this way is an honest
  "this question no longer exists" — never use `Resolved` for it, since that would assert a
  verification that never happened. Point at whatever superseded it.

Closed entries (`Resolved`, `Obsolete`) move verbatim to `docs/BUGS-ARCHIVE.md`.

**Convention:** one flat list, sorted by BR number ascending (`BR26.xx` before `BR27.xx` before
`BR30.xx`, lowest sequence first within a taskblock) — no category sections. **Status is inline in the
entry heading** (`Active` / `Suspected` / `Pending` / `Resolved` / `Obsolete`), right after the ID,
so status and ID are both visible while scanning. Entries reported before the `BR<taskblock>.<seq>` convention existed
have no ID to sort by — they follow at the end, in their own legacy block, oldest work first. Recent
entries get a timecode + taskblock; older migrated ones get a rough date. `Resolved` entries name the
fixing commit(s)/taskblock so the closure is verifiable.

**Every bug carries an ID:** `BR<taskblock>.<seq>` — e.g. `BR27.01` (Bug Report, reported during
taskblock 27, first of that block). **The ID is assigned at report time and never changes** — a bug
reported in tb27 stays `BR27.xx` even if fixed in tb30, so the handle is stable across its whole life
between supervisor, CC, and the reviewer. Put the ID in the entry heading.

**Every bug carries a `source`**, recording who found it:
- **`CC`** — found by CC during its own work, usually a pure-code bug.
- **`SUPERVISOR`** — reported by the supervisor (the human overseeing the project). CC often
  *can't see* what was reported (a visual glitch, a "feels wrong" behavior), so it may have fixed
  the wrong thing.

**But `owner` is what gates closure, not `source`** — see the `owner` paragraph above. Owner defaults
to the source and the supervisor may promote any entry to `SUPERVISOR` ownership at any time, so the
two can differ and **only `owner` decides what you may write**:
- On a **`CC`-owned** entry, CC owns the whole loop (sees it, fixes it, tests it) and **may write
  `Resolved` directly.**
- On a **`SUPERVISOR`-owned** entry, **CC may NEVER write `Resolved` or `Obsolete`.** The most it may
  write is **`Pending`** (fix complete, CC believes it works, awaiting the supervisor seeing it work).
  Only the supervisor promotes `Pending` → `Resolved`.

**Session stamps.** CC has no sequential session counter — what it *does* have is a **session
UUID** embedded in its scratchpad directory path (e.g. `.../83fb8082-732a-4a4f-a726-04186087ef69/
scratchpad`). CC stamps its closure marks with the **full UUID**, not a shortened prefix — a prefix
is one collision away from misattributing a stamp to the wrong session on a long-lived machine, and
the full string costs nothing to write (e.g.
`Pending [CC 83fb8082-732a-4a4f-a726-04186087ef69]`). If CC is refreshed it
gets a *new* UUID, so a later session reading an earlier session's `Pending` mark sees a
**different** stamp than its own — that's the signal it's *another instance's* unverified claim. It
must NOT promote it to `Resolved` on the strength of a prior CC's word, only on the supervisor's. A
pending mark whose UUID isn't your current one is a claim to re-check, not a closure to trust.

**End-of-taskblock digest.** At the end of each taskblock, CC lists every `SUPERVISOR`-owned entry
it moved to `Pending` this block — a "here's what I think I fixed, please
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

## Clusters — how the ledger is sorted, and which entries will eat a hunt

**Every open entry carries a `cluster:` line, and that line is the sort.** Added at taskblock-60
Pass D so a hunt opens against a grouped list rather than a chronological one. `grep 'cluster:
`shot-geometry`' docs/BUGS.md` is the whole query; **nothing is derived and no index is
maintained**, which is the same posture the `^### BR` heading grep already has. A cluster is a
claim about *shared cause*, not about subject matter — `BR52.09` and `BR54.02` are both "the model
and the picture disagree" and are in different clusters, because one is a missing teardown path and
the other is a timing gap, and a hunt that treats them as one thing will fix neither.

**A cluster is a lead, not a verdict.** Several were assigned from a title and an entry body rather
than from a reproduction; where an entry's own cluster is uncertain, its body says so.

| cluster | what it means |
|---|---|
| `shot-geometry` | where a round actually goes, against where it was aimed |
| `wall-cutout` | the shader that opens walls between the camera and a unit |
| `overwatch` | declaration, triggering, and what a declined trigger records |
| `view-model-membership` | the view and the model disagree about **what exists** |
| `two-clocks` | the view runs ahead of playback — they disagree about **when** |
| `framerate` | see the section below; **these are not hunted** |
| `determinism` | same seed, different bout |
| `test-infrastructure` | the suite lying about its own results |
| `engine-abort` | an engine-level crash or abort |
| `camera` | framing and transitions |
| `input-affordance` | a click that does nothing, or the wrong thing, with no feedback |
| `map-generation` | what the generator produces |
| `ai-behaviour` | what a unit decides |
| `rendering` | lighting and materials |
| `accounting` | a claim in a doc or a log that the code does not support |
| `pending-confirmation` | fixed, awaiting the owner seeing it work |

### The deep ones — named before a hunt starts, not discovered during one

**Knowing which entries will eat a day is worth more before starting than an hour during.**

**Five of the ten named below have since closed** (taskblock-66 doc review, checked rather than
assumed): `BR32.04`, `BR32.05`, `BR32.08`, `BR51.01` and `BR52.07` are all in
`docs/BUGS-ARCHIVE.md`. Their paragraphs are kept because the *reasoning* in them still applies to
the entries beside them — but **nothing here sends you after a closed entry**, and the wall-cutout
bullet in particular describes a cluster that is now empty. Statuses were not changed by this
review; only this line was added.

- **`BR51.01` / `BR54.01` / `BR52.07` — shot geometry.** taskblock-60 Pass B made these readable:
  every firing path now emits a `weapon_used` event carrying origin, direction, the shooter's own
  facing, and the angle between the last two. **Read the new log before forming a theory.** They are
  three symptoms that may be one cause and may be three. **Pass B already removed one suspect**:
  `AttackAction` free-faces at its target before firing, so a queued attack reads near-zero
  off-facing and `BR54.01` is not a stale-facing effect. That points at the aim point itself, which
  `docs/02` measures as the frontmost region's centre — 20.1 degrees off-axis at one cell.
- **`BR32.04` / `BR32.05` / `BR32.08` — the wall cutout.** `BR32.05` needs a real ray test in the
  shader, which was a rewrite when it was filed. **`RayCaster` and `PartPicker`'s struck-point
  reporting now exist**, so it is materially cheaper than the entry suggests — **re-read it before
  deferring it again.** Note that `BR32.04` is also a `two-clocks` symptom (the hole snaps to the
  destination before the move animates) and may not need the shader work at all.
- **`BR52.12` / `BR52.15` — overwatch.** `BR52.12`'s own finding is that overwatch fires only on
  movement and nothing moved, **which points at the AI rather than at overwatch.** Confirm which
  before either is worked.
- **`BR55.01` — an intermittent engine abort in `LoS.has_los`.** Intermittent, engine-level, and
  taskblock-58 rewrote what `LoS` consults. **Re-verify it still reproduces before hunting it.**
- **`BR52.14` — `test_suite_run.gd` intermittent in the full gate, passing targeted.** Test
  infrastructure, not game behaviour, and **it will waste a hunt.**

## Re-opening a closed entry is allowed

**A `Resolved` or `Obsolete` entry can come back.** A fix that did not hold, a symptom that returns, a
closure made on a verdict that later evidence contradicts — **move it back and say why, with the date
and who reopened it.** The archive is history, not a promise.

**If you are not sure whether something is the old entry returning or a new defect, ask.** Filing a
duplicate costs a triage; re-opening the wrong entry buries a distinct bug inside one that reads as
understood.

**Watch for a fix that overshot rather than missed.** `BR61.07` was reopened because a
too-early teardown became a too-late one — the same clock, corrected past the target. **A symptom that
inverted is still the same entry**, and closing it and filing its mirror would lose the fact that one
change caused both.

---

## A deviation is not a defect without a declared standard

**Before filing "X is now A where it used to be B", say what A *should* be.** A number that moved is
evidence; a number that is wrong needs a bar to be wrong against. Without one, every measurement
becomes a bug and the ledger fills with entries nobody can close because nobody can say what closing
would look like.

**Two entries were filed that way and both have been re-handled.** The framerate group below sits
because the bar is now written down. `BR45.03` — *the planner completes 54.2% where the old one did
87.5%* — left the ledger entirely: no completion standard was ever declared, and taskblock-59's
per-tier measurement inverted the comparison. It is a tuning question and lives in `PLAN.md`.

**A deviation with a real defect underneath is a different thing**, and the answer is to retitle rather
than to close. `BR58.01` was filed as a 1.3x cost regression; the defect is that planning aborts on
wall-clock and therefore varies by machine. **The number was context and the title buried the bug.**

---

## Framerate: the bar, and why these entries sit

**The release bar is 120 fps at 4K.** Anything below that is not acceptable at ship; this is a
turn-based game with a handful of units and it should not struggle. **Resolution is part of the bar** —
120 at 4K is roughly 160 on the supervisor's display, so a number taken at 1080p is not a number
against the bar and should say which it is.

**The working tolerance right now is far looser, deliberately.** A **1% low above 40** and **no frame
over roughly 100 ms** is acceptable for the moment. Framerate is a *chase it if it is severe* problem
until the game is closer to done, and severe means below that tolerance — not below the release bar.

**Judge on the 1% low and the worst frame, never on an average.** The perf panel reports five figures
and they disagree by design; an average is the one that hid a stutter for five blocks.

**So the framerate entries below stay `Active` and are not hunted.** They are real defects measured
against the release bar and none is severe against the working tolerance. **This is written here so a
triage does not re-derive it every time** — the question *"is 100 out of 160 a bug?"* has been asked and
answered, and the answer is *yes, and not yet.*

**`BR58.01` is not one of them.** It is measured in milliseconds and reads as a performance entry, but
the defect is that planning aborts on wall-clock and therefore varies by machine. That is a determinism
bug and it is chased on its own terms.

---

### BR64.03 — Suspected — owner: `CC`
**An `ELITE` chose `roam` with an enemy two cells away, and it does not reproduce on bare ground**
- **cluster:** `ai-behaviour`
- **Source:** `CC`, 2026-08-10, tb64 Pass A3  ·  **CC session:** `4d8755ca-841c-4dc7-aa67-432a6b560498`
- **`Suspected`, not `Active`: this is a lead, not yet a described bug.** It is the residue of
  `BR63.05` (`SUPERVISOR`-owned, still open) once the two `MINDLESS` observations in that entry
  turned out to be a tier gate rather than sight. **That entry is the report; this is the chase.**
- `roam`'s `enemy_unknown` precondition is `target == null`, and `target` is
  `_nearest_known_enemy()`, so the unit genuinely knew of no enemy. The inference in `BR63.05` is
  sound for **this** observation even though it is wrong for the rest of that entry.
- **Does not reproduce on a bare board.** `test_close_range_firing_decision.gd` runs the real
  `combat_tester_sniper_rifle` (`ELITE`) against an enemy at 1, 2 and 3 cells with no geometry
  present: `enemies_visible = 1` every time, and it plans, backs off past its own `min_range` and
  fires. So whatever this is, it needs a real board.
- **Two readings, and nothing separates them yet:**
  1. **Ordinary geometry.** After tb64 Pass B the sweep still measures **193 blind pairs at
     Chebyshev 2 (8.72%)** on a generated board. A single observation at two cells is entirely
     consistent with that, and would make this not-a-bug.
  2. **A knowledge-layer defect above `LoS`.** `WorldView.units_visible_to` gates on
     `MEMORY_TIERS`/`restricted` before sight is ever asked, and **nothing has measured that path
     on a generated board with a real roster** — only on fixtures.
- **What would separate them:** run a seeded bout to the turn that produced the `roam`, and for
  that unit dump `units_visible_to` beside a direct `LoS.has_los` to the enemy's cell. If sight
  says yes and the view says no, it is reading 2; if both say no, it is reading 1 and this closes
  `Obsolete` against the geometry. **The decision log already records `visible_unit_ids` per
  decision**, so most of the instrument exists.
### BR64.02 — Active — owner: `CC`
**`kitted_chaingun` assembles with no weapon**
- **cluster:** `data-authoring`
- **Source:** `CC`, 2026-08-10, tb64 Pass A3  ·  **CC session:** `4d8755ca-841c-4dc7-aa67-432a6b560498`
- `KitEquipper.equip` pushes `KitEquipper: chaingun never made it into its own kit container
  backpack` and the resulting unit has no damaging part at all — `_find_weapon_id` answers `&""`
  and the unit can never fire.
- **Filed, not fixed, and deliberately out of the combat cross-product.** The supervisor's call:
  *"kitted chaingun and laborers were built as part of tests, not actually designed out. They
  should not be used for combat testing."* `test_close_range_firing_decision.gd` scopes itself to
  `profile_family == &"combat_tester"` for that reason, so this preset is measured by nothing.
- It is still an equipping defect rather than a preset-authoring one — the kit names a chaingun and
  the equipper drops it — so it wants chasing on `KitEquipper`'s terms, not by editing the preset.
### BR63.01 — Pending — owner: `SUPERVISOR`  ·  **CC session:** `4d8755ca-841c-4dc7-aa67-432a6b560498`
**Ladders generate for a one-level rise, and both pieces are two units tall**
- **cluster:** `map-generation`
- **Source:** `SUPERVISOR`, 2026-08-10, post-taskblock-63 review.
- A rise of 1 gets a ladder at all, where a step or a single piece should cover it.
- **Both the top and bottom ladder pieces are 2 units tall.** Each should be **1 unit**.
- **For a short rise only the top piece should generate.** A bottom piece with nothing to climb is
  scenery pretending to be a route.
- Check this against `MapGen`'s rise thresholds and against `step_height` — a rise of 1 is above the
  default free step but well below anything needing a two-piece ladder.
- **tb64 Pass F, measured — confirmed, with the arithmetic.** `_open_a_route_out` on a 1.0 rise
  returns true and stamps **one** segment: `_stamp_ladder` computes
  `ceil(rise / Surface.LADDER_SEGMENT_RISE)` = `ceil(1.0 / 2.0)` = 1. **`LADDER_SEGMENT_RISE` is
  2.0 and the part's box is 2.0 tall**, so a one-level rise gets a ladder that overshoots its own
  destination by a full level. The report's *"each should be 1 unit"* is therefore a change to
  `Surface.LADDER_SEGMENT_RISE` **and** to `ladder.tres`'s box, and it moves climb pricing —
  `Pathfinder`'s ladder branch and `Surface.ladder_serves_climb` both read that constant.
- **The "two pieces" are one ladder drawn twice, and that is `BR63.02`.** See that entry: on a 4.0
  rise the segments are at `h=0.00` and `h=2.00`, but the cell also emits a **third** box at the
  same height as the first, half a cell away in z. Fixing the double-draw may be all *"only the
  top piece should generate"* actually needs.
- **Ladders are rarer than the report implies**, which is worth knowing before tuning thresholds:
  seed `642296523` at 40x30 carries 16 ladder cells, and seeds `4242` and `7` carry **none at
  all**. Every ladder on `642296523` serves a rise of 2.80–4.00, so no one-level ladder appears on
  that board — the reported one came from a seed not sampled here.
- **tb64 Pass F: fixed, unconfirmed.** `Surface.LADDER_SEGMENT_RISE` 2.0 -> 1.0 and `ladder.tres`'s
  box with it, on the supervisor's call. A 1.0 rise now stamps **one piece topping out at exactly
  1.00** instead of one standing a full level proud of the floor it served.
- **Climb cost did not move and needed no compensating constant.** The instruction was "hold climb
  cost steady", and `Pathfinder.move_cost` already prices a ladder edge as
  `ceil(CLIMB_COST * level_delta * LADDER_COST_SCALE)` — by **rise**, never by segment count. So
  halving the segment changes how many pieces stand and nothing about what climbing costs.
  `test_a_climbs_price_follows_its_rise_not_its_segment_count` pins that, since the claim is only
  true while the formula stays height-based.
- **A 4.0 rise now stacks four flush segments** at 0/1/2/3 where it stacked two, asserted with no
  gap between them.
- **Side effect, measured:** a 1.0 ladder tops out below `LoS.SIGHT_HEIGHT` (1.25), so a
  ground-level segment no longer blinds anyone. On the sweep seed `ladder (surface)` falls from
  **101 blind pairs to 37**.
### BR63.02 — Pending — owner: `SUPERVISOR`  ·  **CC session:** `4d8755ca-841c-4dc7-aa67-432a6b560498`
**The two ladder pieces are visually indistinguishable, and one is offset oddly**
- **cluster:** `input-affordance`
- **Source:** `SUPERVISOR`, 2026-08-10, post-taskblock-63 review.
- The piece that spawns attached to a ship floor sits at a **strange offset**; the other is centred on
  an edge as expected. **They should be tellable apart at a glance** — an author and a player both need
  to know which end of a ladder they are looking at.
- Likely the same placement-record work as `BR62.05`: an offset that was previously implicit is now
  carried explicitly, and one of the two pieces is not setting it.
- **tb64 Pass F, measured — and it is a double-draw, not an offset on one piece.** A side-attaching
  ladder gets **two homes** from `GridPlacement.place`: it becomes a `Surface` at its own cell
  *and* an occupant of a floor's `LEDGE` socket. Both are then drawn, from different transforms.
  On a 4.0 rise at cell `(2,2)`, `surfaces_at` emits three boxes where there are two segments:

  ```
  root=ship_floor  box=ladder  h=0.00  world_centre=(2.00, 1.00, 1.95)
  root=ladder      box=ladder  h=0.00  world_centre=(2.00, 1.00, 2.45)
  root=ladder      box=ladder  h=2.00  world_centre=(2.00, 3.00, 2.45)
  ```

  The first two are **the same physical ladder at the same height, 0.5 apart in z** — the socket
  chain puts it on the floor's north ledge (`2.00 - 0.05`), its own `Surface` record puts it at
  cell centre `+0.45`. *"One sits at a strange offset while the other is centred on its edge"* is
  exactly this pair.
- **Same root cause as `BR64.01`'s first half**, from the other side: one `Part` reachable through
  two roots. Sight was fixed by excluding per box; drawing needs the opposite — one of the two
  emissions has to stop being drawn, and **which one is the design call**, since the socket
  transform is the physically-correct ledge position and the `Surface` record is what the mover
  and `ladder_serves_climb` read.
- **tb64 Pass F: fixed, unconfirmed. The `Surface` record won**, on the supervisor's call, because
  it is already the authority everything else reads — `Surface.ladder_reach_at` and
  `ladder_serves_climb` walk `grid.surfaces_at` and never touch the socket links.
- **`UnitGeometry.surface_placements` is the one entry point** a placed `Surface` is emitted
  through, and it walks the part's own volume without descending into sockets. A named function
  rather than a flag threaded through `BoardView`, `RayCaster.obstructed` and
  `RayCaster._consider_surface` — a flag half-applied is how the two ray loops came to disagree in
  `BR64.01`, and the same shape was available here.
- **The attachment itself is untouched.** It is the placement grammar, and an occupied socket is
  what stops a second ladder taking the same face; it simply stops emitting geometry.
- **Safe because every socket occupant of a surface is independently placed** — measured, not
  assumed: across five generated boards, **35 occupants, all carrying their own `Surface`, zero
  orphans**. Only `ladder` (`STACK`) and `ship_floor` (four `LEDGE`s) author sockets at all.
  **The stated limit:** a future part socketing a purely decorative child onto a floor would stop
  being drawn. That is written into `surface_placements`' own comment.
- **Measured:** the `ladder (surface on ship_floor)` blame bucket — 57 blind pairs — is gone
  entirely, and the cell emits one box per segment instead of two.
- **To see it:** a ladder should be one panel per level, on one face, with no second panel half a
  cell away from it.
### BR63.03 — Pending — owner: `SUPERVISOR`  ·  **CC session:** `4d8755ca-841c-4dc7-aa67-432a6b560498`
**Extracted units remain on the map**
- **cluster:** `view-model-membership`
- **Source:** `SUPERVISOR`, 2026-08-10, post-taskblock-63 review.
- A unit that extracts is still drawn on the board. **The mission's own record says it left; the view
  says it is standing there.**
- **Same class as `BR61.07` and `BR54.02`** — the model and the view disagreeing about what exists,
  which `PLAN`'s *Player view and sim view* addresses structurally.
- Check whether the unit is also still *targetable* and still *takes turns*, which would make it a
  gameplay defect rather than a drawing one.
- **tb64 Pass G: it was both, and the answer to that question is yes.** Two independent causes:
  - **Gameplay.** `MissionState.extract_unit` set `alive = false` and cleared the cell **by hand**
    — the same two lines `CombatState.kill_unit` runs under a comment calling itself *"the one
    place a unit's alive flag flips to false"*. It never copied the third thing that function
    does: **advance the turn when the departing unit is the current one.** So `_current_unit_id`
    pointed at someone who had gone home and the turn never ended — **`BR51.04`/`BR51.05`
    reintroduced through a second door**, selection included, since `SelectionController.select`
    requires `unit == current_unit()`. Fixed by routing extraction through `kill_unit`.
  - **Drawing.** Every *other* way a unit stops participating destroys geometry: a killed unit's
    parts drop to `hp <= 0` and `BodyProjector.projects` refuses them, so it empties out box by
    box with no view rule at all. **Extraction destroys nothing**, so `HitVolumeView.refresh()`
    faithfully rebuilt a whole intact body. It now draws nothing for an extracted unit, and
    `refresh_transforms` refuses so the cheap path cannot keep it on screen.
  - **Keyed on `extracted`, deliberately not on `alive`** — an inert shell whose matrix was ejected
    is still lying there to be shot and stripped, and is pinned by its own test.
  - Targeting and cell occupancy were **already** correct and are pinned rather than changed.
  - **To see it:** extract a unit. It should vanish from the board, stop being handed turns, and
    stop blocking selection.
### BR63.05 — Active — owner: `SUPERVISOR`
**Units do not see enemies at one to two cells**
- **tb64: the stated cause is wrong for most of what was reported, and the title overstates it.**
  Measured at the decision level on a **bare board with no geometry on it at all**
  (`test_close_range_firing_decision.gd`): every preset saw its enemy at 1, 2 and 3 cells —
  `enemies_visible = 1` in all 18 cases. **Sight was never the failure for the reported silence.**
  - **The two `MINDLESS` units that chose `seek_extraction` at one cell had no firing action at
    all.** `shoot.tres` is gated `GRUNT`/`TRAINED`/`ELITE` and `docs/11` says so deliberately, so
    `shoot` was never in their candidate list — not offered, not refused, absent. The library's
    only `MINDLESS` preset was `combat_tester_pump_shotgun`, **armed with a weapon its own tier
    could never fire**. Fixed by re-tiering it to `TRAINED` on the supervisor's call (*"none of the
    combat testers should be mindless"*); the tier gate itself is untouched.
  - **The `ELITE` that chose `roam` at two cells is not reproduced on bare ground** — the sniper
    plans, backs off past its own `min_range` to `(4,8)`/`(5,7)`, and fires. This is the one
    observation still unexplained, and it is the only part of this entry that is still about sight.
- **What the sight sweep did find** (`test_generated_board_sight_sweep.gd`, seed `642296523` at
  40x30, 445 standable cells): blindness inside Chebyshev 3 is real but **ordinary geometry**, not
  a regression — **19 blind pairs at 1 cell (1.49%), 193 at 2 (8.72%), 510 at 3 (17.56%)**. At
  `c3b665d` the same seed measured 1.60% / 7.08% / 15.69%. **Caveat: not the same board** — tb63
  Pass D1 changed generation (559 standable cells then, 445 now).
  - **Re-taken after Pass B, and the first figures were wrong.** A2 reported 1.97% / 9.39% /
    17.84% with `BR64.01` still live; fixing it cleared 29 blind pairs that were never real
    occlusion. The tb63-made-it-worse gap narrows from ~2 points to well under 1 at close range,
    which weakens the regression reading further rather than strengthening it.
- **Orthogonal adjacency is unblockable and that half of the narrowing below holds** — 667 pairs,
  0 blind. **The diagonals are not**: 605 pairs, 19 blind. `_nearest_known_enemy` measures
  `Grid.distance_chebyshev`, so *"one cell away"* includes the four diagonals, where two
  non-exempt cells sit between the pair. tb64 Pass A1's fixture only ever tested `(2,2)->(3,2)`.
- **`_stand_wall` is a minor contributor, not the cause.** Reverted to a bare `place_blocker` on an
  identical board layout: 751 blind pairs -> 709, so tb63 Pass D2 accounts for **5.6%**. Measured
  before Pass B; the isolation's *direction* is unaffected, but the two figures are pre-`BR64.01`
  and should not be compared against the 722 above.
- **What blinds is decided by height, not by being a wall** — the blame table, by the occluding
  box's own part (post-Pass-B): `ship_floor` 177, `wall` 168, `pillar` 157, `forklift` 85,
  `ladder` 101 (57 of them socketed into a floor's `LEDGE` socket), `scrap_pile` 14, `goo_barrel`
  10, `barrel_pallet` 8, `crate` 2. **Cover blames 276 against the walls' 168.** A prior CC session recorded the
  opposite — *"cover does not block sight, only walls blind"* — generalising from `crate` (0.70)
  to a class that contains `pillar` (1.80) against a `SIGHT_HEIGHT` of 1.25. That reading is what
  steered this entry at the walls tb63 made taller.
- **cluster:** `ai-behaviour`
- **Source:** `SUPERVISOR`, 2026-08-10, post-taskblock-63 review.
- **The failure is proven at decision time; the cause is suspected and unverified.** An `ELITE` unit
  chose **`roam`** — whose preconditions require `enemy_unknown` — with an enemy **two cells away**.
- Path: `_nearest_known_enemy` → `WorldView.units_visible_to` → `_has_direct_sight` → `LoS.has_los` →
  `RayCaster.obstructed`. **A sight failure feeding the planner, not a firing failure.**
- **Suspected: taskblock-63 Pass D2's `_stand_wall`.** A wall is placed at the lowest neighbouring floor
  and *sized* to clear the highest, so with `TALL_ROOM_LEVEL = 4` a wall can be **6.4 tall where it was
  2.4**. Occlusion now reads `blocker_height_for_cell` rather than `true_height_for_cell`, so lines that
  used to pass over a short wall hit a tall one.
- **The hypothesis does not explain blindness at one cell**, and that gap narrows sharply:
  `_has_direct_sight` is *only* `LoS.has_los`, and `has_los` **exempts every part at either endpoint
  cell**. Between two orthogonally adjacent cells at the same floor height nothing on the line can
  block. **So it is one of four things:** the cells were at different heights and the slanted ray
  clipped a neighbour; `_endpoints` is not exempting what it should; `RayCaster.obstructed` reports
  geometry not on the line; or the units were not where the log says.
- **Build the two-cell headless fixture before the seed sweep.** Two adjacent floored cells, a unit on
  each, walked through wall/no-wall and same/different height. It reproduces and names the cause, or it
  does not and the systemic sweep is warranted. **Minutes against a sweep's build.**
- **The test written for this guarantees the failure rather than catching it**:
  `test_no_generated_wall_is_shorter_than_the_floor_beside_it` asserts walls are *tall enough* and
  nothing asserts the converse.
### BR26.02 — Active — owner: `SUPERVISOR`
**Low framerate while aiming**
- **cluster:** `framerate`
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
- **2026-08-04 — every number above predates taskblock-55 Pass B and the board it describes no longer
  exists.** That pass deleted the per-cell ground quad and draws the walkable parts as real boxes, so
  *"768 terrain cells"* is now 768 six-faced tiles: **1 536 terrain triangles became 9 216, a 6x
  increase**, on an entry about framerate. **Not re-measured deliberately** — a number taken now would
  likely be stale again by the time this is worked, and the point is only that the existing figures
  cannot be trusted as a baseline. Re-take them when the work actually starts.
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

- **2026-07-31 (supervisor — REOPENED from `Pending`, with an acceptance bar).** Framerate is much better
  and is **not good enough**: *"I have a beefy PC. If I can't run an aiming sequence, with static actors,
  no background thinking, at 160 steady, then there is still something wrong."*
- **That is the closure condition, and it is testable rather than a feeling:** aim view, actors static,
  no AI planning, **a steady 160 with no dips** — judged on the perf panel's *1% low* and *worst frame*,
  never on an average. taskblock-51 measured `min 7.5, avg 140.1` in one session; the average is the
  statistic that hid this for five blocks.
- **The named lead is `BR51.15`** — a distinct hitch as the over-the-shoulder camera swings behind the
  unit. The remaining session minimum is one stall, not a load: `PerfStats` reported the fastest frame's
  neighbours as `prev 116.2, next 260.0`, which disproved the queued-frames theory.
- **Per-motion cost is 113 504 → 8 878 usec** across four distinct fixes. What remains is not the same
  bug at lower amplitude; treat the residue as its own investigation.

### BR27.09 — Active — owner: `SUPERVISOR`
**Major hitch on new-turn or end-turn**
- **cluster:** `framerate`
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
  - **2026-08-04 — that pointer is dangling.** `reports/` keeps a rolling five and Taskblock 44's
    report is long gone, so the procedure survives only in git history. Recorded rather than
    reconstructed: CLAUDE.md's rule is to carry the fact inline and never point at a report, and this
    entry is what that rule is for.
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

### BR27.15 — Active — owner: `SUPERVISOR`
**Step out: the dartboard does not open on the first click; a second click is required**
- **cluster:** `input-affordance`
- **Source:** `SUPERVISOR`  ·  **Split from `BR27.01` part (1), 2026-08-04** — see that entry in
  `docs/BUGS-ARCHIVE.md` for the original four-way framing and the full taskblock-27 Pass B history.
- **Reported:** taskblock-27, as *"doesn't open the dartboard, always resolves a center-mass shot"*.
  **Mutated rather than resolved** by the Pass B fix, and re-reported 2026-07-21 with a precise repro:
  *"clicking shoot, then clicking an enemy, doesn't bring up the dartboard if the unit had to step
  out; clicking again brings up the dartboard."*
- **2026-07-22 (tb32 review):** still reproduces, unchanged. tb32 did not touch it.

**CC investigation, `e5393c3a-bd26-4668-8905-c50cf31e04cb`, 2026-08-04 — read from source, no code
touched.** The 2026-07-21 note guessed this was *"the two-step step-out flow itself... reading as
'doesn't work' without a clear in-between visual cue — not yet investigated code-side."* **That guess
is correct, and the cause is sharper than a missing cue: there is no cue at all.**

- **The two-step flow is real and is by design.** `TacticsController.confirm_shot()` branches on
  `stepping_out_at != null` and hands to `_confirm_step_out()`. So clicking a covered enemy enters
  **step-out-cell-choice mode** (`_enter_aim_or_step_out_mode` → `_enter_step_out_mode`), and only a
  *second* confirm queues the free outbound leg and opens ordinary aim. The dartboard not appearing on
  the first click is the designed sequence, not a broken path.
- **Nothing in the view layer reads step-out state.** A grep for `stepping_out_at` / `step_out` across
  `src/view/` and `src/debug/` returns **only `tactics_controller.gd` itself**. No overlay, no panel,
  no marker.
- **`_enter_step_out_mode` emits `aim_changed` and calls `_refresh_overlay()`, and neither shows
  anything about it.** `_refresh_overlay()` draws reachable cells, ghost paths, the end-position ghost
  and the overwatch arc — the same four it draws in every other mode. `aim_changed`'s consumers are
  `aim_view` (which reads `aiming_at`, still null here, so correctly draws no dartboard), the action
  bar, and the squad control overlay. **None draws the candidate cells.**
- **So the player is given nothing.** The candidate cells are chosen and sorted by safety
  (`_step_out_candidates`, safest first), the mouse wheel cycles them (`cycle_step_out_cell`), and a
  second click confirms — and **none of that is visible**. No highlight on the cell about to be
  stepped to, no indication the wheel does anything, no prompt that a second click is expected. The
  outbound leg is not queued until confirm, so even the ghost shows nothing new.
- **This is therefore a missing view affordance, not a defect in the flow.** Worth deciding
  explicitly, because the two available fixes are different in kind: **draw the mode** (highlight the
  selected candidate and its alternatives, which also makes the wheel-cycling discoverable — it is
  currently invisible too), or **collapse the flow** so the first click both picks the safest
  candidate and opens aim, leaving the wheel to re-pick while aiming. The first preserves the
  deliberate choice step taken in Pass B; the second removes it.
- **What is NOT broken, confirmed:** the flow itself is fully guarded and green —
  `test_tactics_controller_step_out.gd` holds
  `test_confirming_a_step_out_cell_queues_only_the_free_outbound_leg_then_opens_aim`,
  `test_firing_after_a_step_out_completes_the_free_move_attack_move_triple`,
  `test_cancelling_aim_mid_step_out_undoes_the_free_outbound_leg` and
  `test_wheel_cycles_the_step_out_cell_and_wraps`. Every one passes. **They test the controller's
  state, which is correct; nothing tests that a player can see it**, which is the gap.

### BR34.04 — Active — owner: `SUPERVISOR`
**Sniper camera frames the target from an odd angle**
- **cluster:** `camera`
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

**taskblock-61 Pass E4 — `Pending`. It was framing the target from BEHIND, and that is measured
rather than inferred.** CC session `906e0f07-5b0a-47bd-8444-fb42ed468da2`.

- **`CameraOrbitState.sniper_framing` now takes the shooter and solves a viewing angle**, where it
  previously took only the target and kept the rig's current yaw and pitch. The entry's diagnosis
  was exactly right: tb34 Pass D's decision was correct against a spec that only asked for
  *centred*, and this rig centres at any angle because it faces its own `pan_offset` pivot.
- **The measured old behaviour, read off the real `Camera3D` with the solve disabled** — shooter at
  cell (2,3), target at (9,15), a genuinely diagonal pair:
  - **1.248 units to the side** of the shooter-to-target line;
  - **2.139 units PAST the target**, i.e. on the far side, looking back at it *away* from the
    shooter — not a high angle so much as the wrong end of the shot;
  - **1.694 units up** rather than the 0.6 it now rides at.
  **"Frames from an odd angle" was understating it**; the camera was behind the thing being shot.
- **The two supervisor statements are reconciled rather than picked between.** *"Directly above the
  line drawn between shooter and target, looking along it"* and *"a short distance from the target,
  in line between shooter and target"*: the camera sits on the line, on the shooter's side, lifted
  by `SNIPER_UP_OFFSET`.
- **The distance is unchanged** — the same closed-form solve that fits the target's angular
  footprint to the usable half FOV, which already *is* "a short distance from the target". Only the
  direction changed. The horizontal leg is derived as `sqrt(zoom^2 - up^2)` so the lift does not
  push the camera further out than the fit asked for; a test reads the real distance back and pins
  it against the solved one.
- **`SNIPER_UP_OFFSET` is flagged, not designed, and is not a new number** — it is
  `ATTACK_UP_OFFSET`, the lift the over-the-shoulder framing already uses, given its own name so
  the two can be tuned apart. **If the sniper view wants to be flatter or higher, that constant is
  the one line to move**, and it is the only number in this fix anybody chose.
- **A degenerate shooter/target pair still keeps the current angle**, gated on the horizontal
  vector exactly as `attack_framing` gates its own solve — with no line to sit on there is nothing
  to solve, and a test pins it.
- **Verified by reading the built node back, per `docs/10` rule 2, on a diagonal pair.** The
  assertion is the perpendicular offset from the vertical plane through the shooter-target line,
  derived from the two units' own positions and never from the solver's formula. **All three new
  rig tests were confirmed red with the solve disabled** before being accepted.
- **To see it:** aim at something more than `SNIPER_FRAME_DISTANCE` (5) cells away. The camera
  should settle **behind and slightly above your own shooter, looking down the shot** — you should
  be reading the shot's own geometry, with the target centred at the far end. Previously it framed
  the target from whatever heading the tactical camera was last at, frequently from the far side.
- **`BR51.01`'s note that this "may be one defect with" it is not supported by this fix.** The lean
  that entry is about is `ATTACK_RIGHT_OFFSET` on the over-the-shoulder path; this is the sniper
  path, which has no lateral offset at all and never did. They share a symptom vocabulary, not a
  mechanism.
- **Tests:** `test_camera_rig.gd::test_the_sniper_camera_sits_on_the_shooter_to_target_line`,
  `::test_the_sniper_camera_sits_above_the_line_by_its_own_offset`,
  `::test_the_lift_does_not_push_the_camera_past_its_solved_distance`;
  `test_camera_orbit_state.gd::test_sniper_framing_solves_a_new_angle_rather_than_keeping_the_
  current_one` (**a reversal** — the old `keeps_the_current_yaw_and_pitch` test is quoted in place
  rather than deleted) and `::test_a_degenerate_shooter_target_pair_keeps_the_current_angle`.

**2026-08-09 — back to `Active` on the supervisor's own instruction, and the fix is not the
question any more.** *"Camera is still weird, but I'm looking at doing a refactor of the camera
system (cutting the sniper cam entirely) so set back to active with that note."*

- **`Pending` was the wrong status to leave it at and `Resolved` would have been worse.** The Pass
  E4 work landed and is measurable — the camera provably sits on the shooter-to-target line now,
  where it previously sat 2.139 units past the target — **and it still does not read right to the
  only person who can see it.** That is the whole reason this entry is `SUPERVISOR`-owned.
- **Do not spend another pass tuning this.** The planned refactor **cuts `sniper_framing`
  entirely**, so `SNIPER_UP_OFFSET`, `SNIPER_FRAME_DISTANCE`, `SNIPER_ZOOM_SLACK` and the whole
  distance branch in `CameraRig.ease_to_framing` are all on the way out. Work spent moving those
  numbers is work the refactor discards — the same trap `BR35.02` was in before taskblock-56.
- **What the refactor should carry forward, so it is not re-derived:** the rig faces its own
  `pan_offset` pivot by construction, so `pan_offset = target.center` centres the target at *any*
  yaw and pitch — which is why centring was never the hard part and the viewing *angle* always
  was. And `docs/10` rule 2 exists because this rig's yaw bug survived a full suite of
  row/column-aligned cases; **any replacement needs a diagonal readback case from day one.**
- **When the refactor lands, this closes `Obsolete` rather than `Resolved`** unless the new camera
  is separately confirmed — the code it describes will be gone, which is not the same as anyone
  having verified a fix.

### BR35.02 — Pending — owner: `SUPERVISOR`
**Spectator's tile-inspect click can silently resolve to a cell hidden behind a wall**
- **cluster:** `input-affordance`
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
- **2026-08-05 (tb58 Pass C) — the primitive this needs now exists; the bug is untouched.**
  [CC `5b7ef20b-5059-45dd-bc08-da8dc537ad93`] The stated fix is *"a real line-of-sight/geometry check
  between the camera and the resolved cell"*, and there was none to call. `RayCaster.cast_geometry` /
  `RayCaster.obstructed` are exactly that: analytic ray-vs-box against blockers, placed surfaces and
  field items, no scene tree, no physics server. **Recorded so the next attempt does not re-derive
  the check**, not as progress on the entry — nothing in `SpectatorOverlay` calls it, and the entry's
  own "do not fix this one individually" instruction still governs.
- **2026-07-28 (review session `HBPaR3`) — promoted to `SUPERVISOR` ownership.**
- **Do not fix this one individually.** It is the third of a set — with BR27.04 (lighting differs
  between the two views) and BR32.09 (spectator's current-unit indicator jumps early) — all of which
  are the same root: `SpectatorOverlay` re-implements a subset of `SquadControlOverlay`'s panels
  because it cannot inherit them without dragging in `TacticsController` and the whole unit-input path.
  `PLAN.md`'s *One view, toggleable modules* dissolves the class. Fixing an instance is work that
  refactor discards.
- Supervisor clarification note: Obsolete this if it cannot be reproduced during the taskblock-71 bug hunt.

**taskblock-56 Pass D — the refactor landed, and this one did NOT evaporate. Still `Active`, and
deliberately not `Pending`.** CC session `4ec878cf-1434-4676-8bd3-05c92eed071a`.

- **The class it blamed is gone.** `SpectatorOverlay` no longer exists; the click path is
  `BoardInspectModule.handle_input`, a module any mode can mount. The other two members of the set
  were already `Resolved` and archived before this block — so the "third of a set" framing is spent,
  and this is now a lone entry.
- **But the defect is unchanged, because it was never a duplication bug.** The note above says the
  set's shared root is Spectator re-implementing Squad's panels. That is true of `BR27.04` and
  `BR32.09` — two implementations of one panel cannot disagree once there is one panel — and it is
  **not** true of this one: the blind `y == 0` plane math was not a second copy of anything the
  player view did better. There was nothing to converge on. Moving it into a module moved it.
- **What did improve, and it is not nothing.** taskblock-51 Pass K had already made the primary pick
  `PartPicker` — real ray-vs-box against bodies, blockers and field items — so `BoardPicker.cell_at_ray`
  is now only the **fallback** for a ray that missed every piece of geometry. The reported symptom
  needs that fallback to fire and to land on an occluded open tile. Narrower than when this was
  written; not closed by it.
- **And the fix now lands once.** Whatever geometry check this eventually gets goes into one module
  rather than into whichever overlay happened to own the click, which is the part of the refactor's
  promise that does apply here.
- **`Pending` would be a false claim** — nothing was fixed, so the honest status is the one it
  already has. Recorded here rather than silently left alone, because taskblock-56 asked for all
  three to be re-checked after the collapse and "checked, still open, and here is why the stated
  cause was wrong" is the answer for this one.

- **2026-08-09 (taskblock-61 Pass D — fixed; `Pending`)** [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`].
  `BoardPicker.cell_visible_from` casts from the camera to the resolved cell's own **surface
  point** and rejects the click if anything real stands in the way.
  - **This entry's own "do not fix this one individually" instruction no longer applies**, and that
    is recorded rather than quietly ignored: taskblock-56 Pass D already found the set's framing
    *"spent"* — the other two members closed, the class it blamed dissolved — and noted that
    whatever check this got would *"land once"* in the module rather than per overlay. It did.
  - **Gated on the fallback only, deliberately.** taskblock-51 Pass K made the primary pick
    `PartPicker`, real ray-vs-box against bodies, blockers and field items — and a thing the ray
    genuinely struck is by definition not hidden. Only `cell_at_ray`'s blind plane math needed a
    guard, which is also why the symptom was narrow enough to survive this long.
  - **The endpoint exemption is the subtlety.** The cell being clicked must never count as the
    thing hiding it, or clicking a wall would stop inspecting that wall and a floor would blind
    whoever clicked it — the failure `LoS` names in its own doc comment. `grid.parts_at(cell)` is
    excluded, exactly as `LoS.has_los` excludes both endpoint cells.
  - Three tests: a cell behind a wall is not visible, a wall is still inspectable by clicking it,
    and a raised tile is not blinded by its own floor.
  - **To see it:** spectate a bout with squads on different levels and click a wall face, then
    click open ground you can see is hidden behind a wall. The first should inspect the wall; the
    second should now do nothing rather than opening a cell you have never seen.
- **2026-08-09 (taskblock-61 Pass D — how to see it, and why CC will not invent a repro)**
  [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]. The supervisor asked how best to recreate this. **The
  honest answer is that CC cannot show the path is reachable**, and the reasoning is worth more than
  a guessed route:
  - **It was never observed.** Source is `CC`, found by a tb35 code-audit sweep and later promoted
    to `SUPERVISOR` ownership. Nobody has ever seen the symptom.
  - **The window narrowed twice since it was written.** taskblock-51 Pass K made the primary pick
    `PartPicker`, and taskblock-59 gave that call `include_surfaces = true` — so units, blockers,
    field items **and floors** are all tested by the real ray. The fallback runs only when the ray
    struck **nothing at all**.
  - **And the only things the fallback can open are a blocker or a floor tile** — both already
    tested by the primary pick. **So reaching this path usefully requires the two pickers to
    disagree**, not an ordinary click. That is a much narrower claim than the entry's original
    "click a wall face and it resolves behind it".
  - **So it is instrumented rather than staged.** `inspect_fallback` logs whenever the path runs at
    all, with the cell the plane math named and the guard's verdict. **A session with no
    `inspect_fallback` line at all is evidence this entry is closer to `Obsolete` than to fixed**;
    a line reading `HIDDEN, click dropped` is the defect caught in the act.
  - **If a route is wanted anyway**, the conditions that make it likeliest: enable *Inspect Floor
    Tiles* in the debug panel (a fallback click with no blocker does nothing without it, so there
    is no symptom either way), take a shallow camera angle on a multi-level board, and click across
    a gap — an unfloored cell or the space above a wall — where the ray can miss every box while
    the plane solve still names a cell beyond.
- **2026-08-09 (supervisor) — DID NOT REPRODUCE.** *"I couldn't reproduce it."* Tried against the
  guarded build after CC's own reachability analysis above concluded it could not show the path was
  reachable at all.
- **STANDING INSTRUCTION FROM THE OWNER: if it fails to reproduce a second time, close it
  `Obsolete`.** Not `Resolved` — nobody has ever seen this symptom, so there is no fix anyone can
  confirm; the honest closing status is "the question no longer exists". **Whoever picks this up
  next does not need to ask again**: one more genuine attempt that produces nothing, and it closes.
  The `inspect_fallback` log line is the evidence to check — a session with no such line is the
  second non-reproduction.
- **What survives either way:** `BoardPicker.cell_visible_from` and its three tests stay. The guard
  is cheap and correct whether or not the path is live, and it is the thing that would catch this
  if the two pickers ever do disagree.

### BR40.01 — Active — owner: `CC`
**Attack-camera framing can end up looking THROUGH the shooter's own standing platform when the
- **cluster:** `camera`
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

### BR45.01 — Active — owner: `CC`
**Surrogate demotion from an ambiguous DAG node is an unresolved placeholder, and says so loudly on
- **cluster:** `accounting`
every fire**
- **Source:** `CC`  ·  **CC session:** `a56eac1a-eddb-4d30-946a-4c8e594ef198`
- **Raised 2026-07-27 by the supervisor noticing the warning volume in `run_tests.sh`.** The warning
  is not new and nothing in taskblock-44 caused it — `SurrogateLadder.demote` has emitted it since
  taskblock-03 Pass A2 (`fc1d9b7`). What changed is that taskblock-44 added tests that run real
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

### BR51.14 — Active — owner: `CC`
**Hovering tiles with a unit selected drops 160 fps to ~20, while moving only**
- **cluster:** `framerate`
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
- **`Pending` (taskblock-51). Measured first, and it was not what triage assumed.** 42 527 -> 18 454
  usec per motion (23 -> 54 fps), clones 48 -> 19 per 30 calls. The cost was `TooltipController.refresh`
  being wired to `mouse_moved` as well as `hover_changed`: every motion rebuilt the tooltip, and
  building one calls `previewed_unit()`, a `CombatState.dup()`. Motion now repositions only. The hover
  is also coalesced to one update per drawn frame, which the reticle already had.
- **Back to `Active` on the supervisor's reading of five live dumps.** *"I don't think the bug is gone,
  but it's no longer a problem while panning, which takes out the majority of the bite."* The measurement
  agrees and is unusually clean: **1% low reads 20.0 / 19.9 / 19.8 / 19.6 / 19.5** across the five dumps
  — the same ~20 fps originally reported, pinned to a tenth, over 4 400-5 000 frames.
- **So the tooltip clone was a real cost and not the whole cost.** Removing it doubled the per-motion
  figure (42 527 -> 18 454 usec) and the remaining 19 clones per 30 calls are genuine rebuilds, one per
  newly hovered tile. **The next lever is memoising `previewed_unit()`** — `BR26.02` records two
  attempts at that, both reverted for concrete reasons (callers mutate the previewed unit; state changes
  within a frame when a resolution spends AP), so it needs its own pass rather than a retry.
- **Paused by the supervisor, not abandoned.**

### BR51.15 — Active — owner: `SUPERVISOR`
**A distinct hitch as the over-the-shoulder camera swings behind the unit**
- **cluster:** `framerate`
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-31, taskblock-51 fourth hunt.
- **Repro:** enter aim with the over-the-shoulder camera and watch the moment it arrives behind the
  shooter. A distinct hitch lands exactly there, separate from the general aim-view cost.
- **This is the ~7.5 fps session minimum, and it now has a cause to look at.** Every session this block
  recorded a minimum of **7.1–8.1** regardless of what else changed — one slow frame, not a sustained
  load. A hitch tied to a specific camera position is a much better lead than a stray stall.
- **Suspects, in order:** the camera passing through wall geometry (which the supervisor separately
  proposes fixing with a camera-attached cutout — see `PLAN.md`), the framing tween completing and
  triggering a rebuild, or the occlusion pass re-evaluating as friendlies cross the near plane.

### BR51.18 — Suspected — owner: `SUPERVISOR`
**A unit slid sideways during a bout watched from both spectator and player control**
- **cluster:** `two-clocks`
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-31, in the same bout that confirmed `BR51.11`. *"This run in particular had unit 0
  on squad 0 slide sideways, but I think that was an unrelated interaction between spectator and player
  control."*
- **`Suspected`, and filed on the supervisor's own hedge** rather than as a confirmed defect: it was seen
  once, in a session that switched control modes, and the reporter's own reading is that the mode switch
  caused it. Logged so a second sighting has something to attach to instead of being rediscovered.
- **What "sideways" would mean mechanically:** the slide tween moves a view between two world anchors,
  while the facing tween rotates it (`BR51.11`, same function). A unit translating without its facing
  following is those two coming apart — most likely a view whose display cell and real cell disagree
  after an overlay swap re-created it mid-playback.
- **Do not work this before it is reproduced.** Taskblock-51 Pass I's spectator/player divergence
  cluster is the same neighbourhood, and `PLAN.md`'s *One view, toggleable modules* would discard an
  instance fix here.
- **Re-checked 2026-08-07 (taskblock-60 follow-up): still unreproduced, and still structurally
  possible.** `ResolutionPlayer` continues to hold `_display_cell` and `_display_orientation` as
  **two separate dictionaries**, seeded independently, which is exactly the shape that lets a
  translation and a rotation come apart. So the described mechanism has not been closed off by
  anything since — but nothing has reproduced it either, and no second sighting has been reported.
  **Left `Suspected`**; one sighting plus the reporter's own hedge is not a described defect.

### BR51.24 — Active — owner: `SUPERVISOR`
**A part destroyed by an explosion disappears from inspect but stays on the model**
- **cluster:** `view-model-membership`
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-01, sixth hunt. *"Bot parts destroyed by an explosion just seem to vanish from
  inspect, but are still visually there."*
- **This is the one real defect from that session** — the supervisor's own distinction: the rest were
  symptoms of the detonation work in progress, not bugs. This one is about part destruction and the
  inspect panel, systems that long predate it.
- **Two readings, and they are opposite defects.** taskblock-09 C2 records that *"a destroyed PART never
  detaches on its own hp reaching 0 — only a severed JOINT does"*. If that still holds, the **model is
  right and inspect is wrong** to hide it. If destroyed parts are meant to leave the assembly, the model
  is stale. **Establish which before touching either**, because the fix points in opposite directions.
- **`refresh_unit_views` does run on this path**, so it is not the missing board rebuild that explained
  the barrel staying drawn — that was a separate cause with the same appearance.
- **Not reproduced by CC.** Reported from play; no headless repro is recorded yet.

### BR51.25 — Active — owner: `SUPERVISOR`
**Non-unit objects render untransformed in the inspect preview**
- **cluster:** `view-model-membership`
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-31, seventh hunt. **Re-scoped 2026-07-31** — first
  reported as barrels intersecting their tile base on the board; the supervisor clarified that **the
  world map places them correctly across levels** and the fault is in the **inspect preview**.
- **`InspectPanel` frames its subject two different ways.** A unit goes through `_isolate_focus`
  (`inspect_panel.gd:544-558`), which merges every mesh's world AABB and puts the camera at
  `center + CAMERA_DIRECTION * radius * CAMERA_DISTANCE_FACTOR`. **Everything else takes the fixed
  path at `:265`** — `_preview_camera.position = CAMERA_TARGET + CAMERA_DIRECTION`, aimed at a
  constant rather than at the object. A barrel or support therefore renders against a camera that has
  no idea where it is, which reads exactly as "no transform."
- **This is the same fallback path `BR48.01` came out of** — the non-unit branch that set
  `own_world_3d` and stripped the board's lighting. Second defect found in it, which is itself the
  finding: **the non-unit path has never been exercised as carefully as the unit path.**
- **The fix is probably to give it the AABB treatment**, not to add an offset — `_isolate_focus`
  already does the right thing generically and the fallback predates it. Confirm which meshes a
  blocker actually exposes before assuming they merge the same way.

### BR52.02 — Active — owner: `CC`
**A test file that fails to parse is dropped from the run and the suite still exits 0**
- **cluster:** `test-infrastructure`
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-01, taskblock-52 Pass B, by walking into it. Renaming `PartPicker._near_ray`
  to `near_ray` left four stale calls in `test_selection_target.gd`. The run printed
  `Failed to load script "res://test/unit/logic/test_selection_target.gd" with error "Parse error"`
  — **and exited 0.** All ten of that file's tests simply did not run, and nothing said so in the
  summary.
- **Observed, not inferred:** the error text and the zero exit code came out of the same run.
- **Why this matters more than the typo that exposed it.** The whole feedback loop rests on "green
  before a pass commits". A green run that silently covers fewer files than the last one is the
  strongest possible version of the failure this project keeps finding — a passing assertion beside
  a live defect — because here there is no assertion at all.
- **`test_suite_audit_csv.gd` does not catch it.** It compares the CSV snapshot against the files on
  disk, so a file that is present but unloadable looks completely normal to it; it reported
  "2598 rows against 2631 declared tests in 277 files" and passed in the same run.
- **The fix is a count, not a parser.** GUT knows how many scripts it was asked to collect and how
  many it actually collected; failing the run when those differ is the whole of it. Not attempted
  in this taskblock — it is harness work and taskblock-52 is a resolver block.

- **2026-08-02 (taskblock-52 Pass F): a second, worse half of the same gap.** A script error at
  *runtime* — not a parse error — opens a **debugger break that halts the run waiting for input on
  stdin**. Observed directly: a failing assertion raised `Out of bounds get index '0'`, GUT printed
  `Debugger Break, Reason: ...` and `Enter "help" for assistance.`, and the run sat there until a
  ten-minute timeout killed it.
- **So the two failure modes are opposite and both bad:** a *parse* error silently drops a file and
  the gate still passes; a *runtime* error hangs the gate forever. Neither reports what happened in
  the summary, and the second is indistinguishable from an infinite loop in the code under test —
  which is exactly what it looked like on first sight, since the change in flight was a new resolver.
- **The likely fix is one flag**, not a redesign: Godot takes `--quit-on-error`-style handling for
  headless runs, and GUT can be told not to break. Worth confirming which knob rather than guessing.

### BR52.06 — Active — owner: `SUPERVISOR`
**A leg appears to have no model**
- **cluster:** `view-model-membership`
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-08-02, live. *"leg doesn't seem to have a model."*
- **Not yet investigated.** Recorded verbatim rather than guessed at — "no model" could be a missing
  `Part.mesh_scene`, a part whose `volume` is empty (so `UnitGeometry.placements` emits no box for it
  and `HitVolumeView` draws nothing), or a part sitting at a socket transform that puts it inside
  another. **The middle one is worth checking first**, because taskblock-52 Pass D found exactly that
  shape on `ship_floor`: a real, shipped Part carrying no `volume` at all.
- **Worth knowing which leg and on which preset** — the combat tester bodies clad every limb, so a
  missing model on one of them narrows quickly.
- **A concrete cause found, 2026-08-06 (taskblock-60 Pass C): see `BR60.02`.** `UnitGeometry`
  emits boxes under `if part.hp > 0` while `BodyProjector.projects` also admits `is_mangled` and
  `is_disabled` — so **a mangled leg at 0 hp is hittable and draws nothing**, measured on a real
  assembled body. That matches this report exactly and needs no timing or refresh explanation.
- **The `volume` theory in the bullet above is ruled out.** Every leg part in `data/parts`
  (`leg`, `thigh`, `leg_cladding`) authors real boxes, checked file by file.
- **To confirm it is this and not something else:** the leg should still stop rounds. If the
  invisible leg is also un-hittable, this is a different defect and `BR60.02` is not its cause.

### BR52.09 — Active — owner: `SUPERVISOR`
**A destroyed cover object's model stays on the board**
- **cluster:** `view-model-membership`
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-02. *"forklift was obviously destroyed, I was flagging that the model stayed
  visible after destruction."*
- **CC's first write-up of this entry was wrong and is withdrawn.** It answered a question that was not
  asked — treating the report as "the forklift is not dying" and filing an analysis of deflect angles
  and penetration thresholds. The forklift dies correctly; **this is a view bug, not a resolver or
  balance one.**
- **Confirmed in code.** `BoardView._spawn_blocker` is called once per `grid.blockers` entry inside
  `build()`, creating a `MeshInstance3D` per box. **No handle to it is kept and nothing ever removes
  it.** The only `queue_free` in the file is `_clear(container)`, which tears down *everything* and is
  only reached from a full `build()`. There is no per-part teardown path and nothing in `src/view/`
  listens for `part_destroyed` at all.
- **So a destroyed blocker's mesh persists until the whole board is rebuilt** — i.e. until the next
  bout. The mechanical state is correct underneath it: the part is destroyed, salvage is credited, and
  the resolver stops treating it as an obstacle. Only the picture is stale.
- **2026-08-09 (tb61 Pass G): `BR61.07` is this entry's mirror, and the two are one question.**
  [CC `906e0f07-5b0a-47bd-8444-fb42ed468da2`] The debug injection path *does* rebuild the board
  (`sync_board_view`, which has only two callers and neither real resolution path is one), so there
  a destroyed blocker's model went away **too early** — before its own explosion had animated. Here
  it never goes away at all. **Both are the same missing thing: nothing sequences blocker teardown
  against the animation that explains it.** `BR61.07` was fixed by moving the injection path's
  rebuild after playback, which is an ordering correction and deliberately not a teardown
  mechanism — **the `part_destroyed`-driven teardown this entry asks for would close both**, and
  inventing one ahead of the design decision below is what that fix declined to do.
- **Visible in the same battle**: three forklifts are destroyed
  (`out/logs/combat-20260802-164344.log`), and units keep firing into the board afterwards with the
  models still standing.
- **Worth deciding rather than assuming, which is why this is not fixed here:** a destroyed cover
  object should probably not simply vanish. `DamageResolver.DROPPED_TAG` and `part.mangles_into`
  (`wreckage_pool`) already exist, and `_spawn_blocker` already reads `DROPPED_TAG`, so "replace with
  wreckage" is a real option alongside "remove". Picking one is a design call.
- **Checked against two entries it resembles and is neither.** `BR51.24` (a part destroyed by an
  explosion stays on the model) is the same *appearance* in a different subsystem — a **unit's** part
  under `HitVolumeView`, where `refresh_unit_views` does run; this is a **blocker** under
  `BoardView`, which has no per-part path at all. `BR35.03` (Resolved) is the opposite problem, debug
  verbs rebuilding the whole board too often; its fix gates rebuilds to `DebugVerbs.affects_board()`,
  which is why the board *can* be rebuilt — **nothing triggers one when combat destroys a blocker.**

### BR52.10 — Pending — owner: `SUPERVISOR`
**An AI unit fires a full burst through the ally standing directly in front of it, killing them**
- **cluster:** `shot-geometry`
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-02. *"Can't tell for sure, but it looks like AI isn't trying to avoid shooting
  allies in the back."* **Confirmed, and it is worse than the report supposed** — reproduced from
  `out/combat.log` (seed 2), Turn 0.
- **What happened, from the log.** Unit 4 (cell `(20,5)`) and unit 3 (cell `(19,5)`) are squadmates
  standing in a line. Unit 4 fires a 12-round chaingun burst at `(12,3)`; unit 3 is directly between
  them. **Eight consecutive pulls resolve on unit 3**, destroying `torso_cladding` then `torso`, and
  ending with `matrix_ejected: combat_tester_chaingun_0 from torso` and
  `surrogate_demoted: unit 3 FULL -> PERIPHERAL`. **Unit 3 takes no further turn in the battle.** One
  AI unit removed a third of its own squad on turn zero.
- **The muzzle is physically inside the ally.** Every one of those eight impacts logs
  `origin (19.02, 5.08)@1.53 -> hit (19.02, 5.08)@1.53` — **hit point equal to origin, zero distance.**
  That is not a resolver defect: `chaingun.tres`'s box is `center (0,0,0.4) size (0.15,0.15,0.9)`, so
  `muzzle_point`'s tip (`center + (0,0,size.z/2)`) sits **0.85 forward of the grip**. From cell
  `(20,5)` that puts the muzzle tip at x=19.02, and unit 3's body boxes at cell `(19,5)` span
  x[18.5,19.5]. The ray legitimately starts inside the ally and hits at t=0. **The geometry is right;
  the decision to fire is what is wrong.**
- **Root cause in the AI, located — and it is a regression, not a gap that was always there.**
  `UtilityContext._lof_possible(cell)` is `field == null or field.allows(cell)` — a
  **visibility-field** test, i.e. terrain and opacity only. `_nearest_known_enemy` correctly skips
  allies as *targets* (`candidate.squad_id == unit.squad_id ... continue`), but **nothing scores
  whether a friendly unit occupies the firing line.** `INPUT_LINE_OF_FIRE` and `PRED_LOF_BLOCKED` both
  read that same terrain-only check, so a squadmate at point-blank range is invisible to the decision.
- **The check used to exist and was lost with the planner rewrite.** `docs/SUPERSEDED.md` records the
  engagement-score planner retiring in tb45 Pass E and `LineOfFire.approach_path`/`closing_path` being
  deleted in tb46 Pass C; `BR35.05` describes a real bout in which units logged **`held:
  ally_in_line`**, so the old branch planner did refuse a shot through a squadmate. `UtilityPlanner`
  replaced the branches with scored weights and **no consideration carries that rule**.
- **Two vestiges confirm it rather than a reading of intent**, and both will mislead the next reader:
  - `LineOfFire`'s own doc comment still advertises `first_hit` as *"Shared by
    `has_clear_line_of_fire` and **the planner's ally-in-line check**"* — that check has no caller in
    `src/` any more, and `first_hit`/`has_clear_line_of_fire` are now reached only from tests.
  - `AiDecisionLog.emit` — the branch log that carried `hold_reason`, i.e. the thing that *printed*
    `ally_in_line` — is still in the tree with **zero callers**; only `emit_utility_decision` is
    called. `docs/SUPERSEDED.md` says it was "deleted with the branches it named", which is not quite
    true: it was orphaned.
- **`BR35.05` is the same defect described against the deleted implementation** and is closed
  `Obsolete` in favour of this entry — see `docs/BUGS-ARCHIVE.md`. **Not a duplicate filing: one entry
  survives, and it is this one**, because it describes the code that exists.
- **Not fixed, and deliberately not designed unasked.** The fix is a real design call, not a patch:
  whether friendly-fire risk should **veto** a shot (a precondition) or **penalise** it (an input),
  and whether a player unit gets the same treatment or the asymmetry in `docs/06` applies. Both
  options are one-line in shape and very different in behaviour. **Flagged for a decision.**
- **Why the log made it findable at all** is worth keeping: `hit == origin` is a shape that reads as a
  resolver bug and is not one. Anything that resolves at zero distance should probably be a named,
  greppable condition rather than something a reader has to notice by comparing two coordinate pairs.

**`Pending [CC 93549217-f453-4fd6-b8f3-cecf9532290e]` — fixed at taskblock-61 Pass A.**

**`UtilityContext._lof_possible` now refuses a cell with a squadmate in the firing line.** It read
`field == null or field.allows(cell)` — a `VisibilityField` test, so terrain and opacity and no
units at all. It now also fails when a living squadmate stands on `Grid.line(cell, target.cell)`,
endpoints excluded.

**No new input and no new weight, deliberately.** `shoot.tres` already carries `line_of_fire` as a
consideration and `UtilityScorer`'s product model preserves a zero at every `n` — so answering
`false` here vetoes shooting from that cell outright, which is exactly the `held: ally_in_line`
refusal the retired branch planner performed. Inventing a "friendly fire risk" weight would have
been a balance number nobody chose, expressing something the existing veto already says.

**Read through `WorldView.units_visible_to`, never `_state.units`** — the seam that class exists to
hold. It costs nothing: *"allies are always known: they are on the radio"*, so a squadmate is in
the list at every intelligence tier including `MINDLESS`.

**Measured over four bouts, before and after:**

| | impacts | landing on a squadmate |
|---|---|---|
| before | 1803 | **121 (6.71%)** |
| after | 1642 | **37 (2.25%)** |

**A 66% reduction, not elimination, and the residual is expected rather than mysterious.** The
check is cell-granular and conservative by design — a cheap filter whose `true` is confirmed later
against the real resolver — and under two-phase turns an ally can move into a line after the
decision that fired was made. **Do not read the remaining 2.25% as the fix failing**; read it as
the difference between "never aims through a squadmate" and "no round ever touches one", which are
different promises and only the first was ever made.

**To see it work:** watch a bout with three units a side. Units that line up behind one another
should now hold or reposition rather than firing through the unit in front. The
`test_ally_in_line.gd` fixture is `BR52.10`'s own geometry — shooter at `(20,5)`, squadmate at
`(19,5)`, enemy at `(12,5)` — and two of its five assertions go red if the check is reverted.

### BR52.12 — Active — owner: `SUPERVISOR`
**Overwatch is declared constantly and never once fires, and a declined trigger logs nothing**
- **cluster:** `overwatch`
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-02. *"Log the failed overwatch as a bug, I can't really see what's happening with
  it until I can see its pie slice but that IS a bug either way."*
- **Measured** in `out/logs/combat-20260802-164344.log`: **12 `overwatch_declared` events, zero
  overwatch fire events of any kind.** Every unit on both squads ends every turn holding, and it never
  resolves once in three rounds.
- **`Overwatch.check_trigger` only runs on movement** — it is called per cell step of a queued
  `MoveAction`. That battle contains **14 `move` events: 13 in Turn 0, and exactly one afterwards**
  (unit 0, Turn 2, line 692). So there was almost nothing for an overwatcher to trigger on: after the
  opening turn both squads stand still and trade bursts. **Whether that is an overwatch defect or an
  AI-never-moves defect is not decidable from this log**, which is the actual problem below.
- **The real defect is that a declined trigger is silent.** `_qualifying_overwatchers` /
  `_qualifying_weapon` reject on armed-state, `LoS.has_los`, `_in_arc`, range and torso visibility, and
  **none of those rejections emit anything.** So "never armed", "arc missed", "LoS failed", "out of
  range" and "never evaluated at all" are indistinguishable in the log — including for the one move in
  Turn 2 that *should* have been evaluated against two armed enemies with a firing line good enough to
  burst through moments earlier.
- **This is squarely the `CLAUDE.md` rule about a supervisor-reported feeling**: *"the AI does
  nothing"* has to become a number or a named decision in the combat log or it stays an adjudication.
  `arc_cells` and `would_trigger_at` already exist and already compute exactly the per-cell answer the
  pie slice would draw — so the decision is derivable today and simply is not emitted.
- **Not fixed.** The instrument (a logged decline carrying which gate rejected it) is the part that
  makes everything after it checkable, and it should land before anyone tunes the mechanic.
- **Checked against the two closed overwatch entries and it is not a re-opening of either.**
  `BR24.02` (overwatch structurally unable to trigger for a volumed torso) was fixed with
  `exclude_parts` and has a regression test. `BR24.03` (no `mid_move_hook` in `BoutRunner.step()`, so
  overwatch never ran in an AI-vs-AI bout) is the closest match to this symptom and is **still
  fixed** — verified in source, not assumed: `bout_runner.gd` calls
  `state.resolve_until(queue, Overwatch.check_trigger)`. The hook is wired; there was simply almost
  nothing to trigger on.

### BR52.14 — Suspected — owner: `CC`
**`test_suite_run.gd` fails intermittently in the full gate and passes standalone**
- **cluster:** `test-infrastructure`
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-02, during the `BR52.11` gate. One full run reported 1 failure; the same file
  passed **7/7 standalone**, and the immediately following full gate passed **2668/2668, exit 0**.
- **It is not a new break.** `out/suite_failures.json` — the ordered-run learning cache — records
  **3 fails in 138 runs** for this file, so it predates this session's changes.
- **A plausible mechanism, unverified.** This file **shells out to run a nested suite**, and
  `run_tests.sh` already carries a guard for that shape (*"`WRITE_PROFILE=1` leaks it into every
  subprocess"*, and only the full gate may write whole-suite artifacts). A nested run competing with
  the outer one over a shared path is the family the guard exists for; whether this is another member
  of it is **not established**, and the failure detail was lost because the run's output was piped
  through `tail`.
- **What it needs is a captured failure**, not a theory: the next full-gate run of this file that goes
  red should have its complete output kept. Filed so the ~2% flake is not rediscovered from scratch.
- **Re-measured 2026-08-07 (taskblock-60 follow-up): `out/suite_failures.json` now records 3 fails
  in 236 runs, with the last failure at run 138.** So it has not reproduced in **98 consecutive
  runs**, four of them gates driven by this taskblock. The rate has fallen from 3/138 (2.2%) to
  3/236 (1.3%) purely by not recurring.
- **Deliberately NOT closed on that.** Ninety-eight clean runs is not a fix, nobody changed
  anything aimed at it, and the entry's own requirement — a captured failure — is still unmet.
  Writing `Resolved` here would assert a verification that never happened. **Left `Suspected`, with
  the number attached** so the next person can see whether it is decaying or dormant rather than
  re-deriving the rate.

### BR52.15 — Active — owner: `CC`
**Overwatch can be declared repeatedly in one turn**
- **cluster:** `overwatch`
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-08-01.
- `OverwatchAction.is_legal` checks alive, current turn, AP, weapon health and manipulator capability —
  and **never checks whether the unit is already on overwatch**. `apply` sets
  `actual.overwatch_weapon_id` unconditionally, so a unit with AP to spare can declare it again, paying
  `AP_COST` each time for no additional effect.
- **Declaring overwatch should end the unit's turn.** Watching a firing lane and then acting again is
  the contradiction — the design intent is that after declaring, the unit does nothing else.
- **The AP question is a design change, not part of this fix** — see `PLAN.md`'s *Overwatch: declaring
  it ends the turn, and spending buys quality*. Fix the double-declaration here; leave the scaling
  alone.
- **Filed as `BR52.01`, renumbered to `BR52.15` (`CC`, 2026-08-02).** That id was already taken by a
  `Resolved` entry in `docs/BUGS-ARCHIVE.md` — the `PartPicker`/`BoardView` height disagreement — which
  is cited from `ray_caster.gd`, `part_picker.gd`, `test_selection_target.gd`, `docs/PLAN.md` and
  `docs/CHANGELOG.md`. Two entries sharing an id breaks `grep '^### BR'` as the index. **The entry was
  also pasted twice**; the duplicate was dropped. `BR52.05` is deliberately not reused — it was
  withdrawn, not unassigned.
- **Related but distinct: `BR52.12`** (overwatch is declared constantly and never fires). This entry is
  about declaring it *too often*; that one is about it never *resolving*. A battle logging 12
  declarations and zero fires showed one declaration per unit per turn, so the double-declaration here
  was not what produced those twelve.

### BR54.01 — Active — owner: `SUPERVISOR`
**AI rounds leave the muzzle at up to 43 degrees off the unit's own facing**
- **cluster:** `shot-geometry`
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-03. *"AI controlled units are firing at strange angles. Specifically the
  sniper rifle and shotgun equipped unit, the chaingun unit seems to be firing predictably by
  comparison."*
- **Confirmed and measured** from `out/combat.log` (bout seed 2), 63 first-hop shots across six
  AI units. Angle between each unit's logged `faced` orientation and the direction its round
  actually travelled:

  | unit | shots | range (cells) | worst off-facing |
  |---|---|---|---|
  | 0 (chaingun) | 24 | 4.8 – 18.6 | **6.1°** |
  | 3 (chaingun) | 24 | 3.4 – 10.6 | **8.6°** |
  | 2 | 3 | 1.7 – 1.8 | 11.1° |
  | 4 | 2 | 1.3 | 11.8° |
  | 1 | 4 | 2.1 – 4.5 | **35.3°** |
  | 5 | 6 | 2.3 – 5.3 | **43.1°** |

- **It is a range effect, not a weapon effect.** The chaingun looks predictable because those two
  units were shooting from 7–18 cells; every badly-deviating shot is from under 5.3. The
  supervisor's read — that it is the sniper/shotgun units — is the same observation seen through
  who happened to be standing close.
- **A worked example, decomposed.** Turn 1, unit 5 at cell `(12,5)`, muzzle `(12.51, 4.40)`,
  facing **2.03 rad** — which from its cell points exactly at cell `(14,4)`, where **unit 2**
  stood. Its three rounds struck bodies at `(14.75, 4.98)`, `(14.82, 4.90)`, `(14.99, 5.15)` —
  which is **unit 1**, at `(15,5)`. Resolving the hit against the muzzle-to-target axis gives a
  **lateral displacement of 1.14 cells at a depth of 2.01**, i.e. the ray left 29.5° off the axis
  it was aimed along. **The unit targeted one enemy and its rounds went to another.**
- **Two plausible causes were checked and eliminated**, which is most of this entry's value:
  - **Not the dartboard scatter.** Authored maximum ring radii are **0.03** cells (sniper_rifle),
    **0.1** (pump_shotgun) and **0.6** (chaingun); `RangeModel.accuracy_multiplier` returns 1.0
    inside effective range, so no widening applies. The measured lateral displacement is **1.1 –
    2.6 cells** — one to two orders of magnitude larger than the widest scatter any of these
    weapons can produce.
  - **Not a plane/aim frame mismatch.** `ShotPlane.elevation_for` builds the plane's axis as
    `Vector2(target_cell) - origin_flat` with `origin_flat` being the **muzzle**, and
    `ShotResolution._aim_point_world` rebuilds the same muzzle-to-target-cell axis. The two agree,
    so the lateral value is not being applied in a rotated frame.
- **The remaining suspect, unverified:** the aim point itself. `AttackAction` takes
  `ShotPlane.center_of(plane, target)` as a lateral/height pair and
  `ShotPlane.depth_of(plane, target)` as its depth. If `center_of` returns the centre of the
  target's **projected region** rather than a point on the muzzle-to-target axis, a body whose
  composed parts sit off its cell centre would pull the aim sideways — and at 2 cells that is
  tens of degrees. **Not established**; it is where the next look should start.
- **Why it is newly visible.** Before taskblock-52 the shot plane modelled a scattered round as a
  ray **parallel** to the shooter-to-target line, so a round always appeared to leave along the
  gun's facing however far off the aim point sat. The ray chain marches muzzle-to-aim-point, so
  the same lateral offset now genuinely **rotates** the round. The resolver change is correct and
  this is the appearance it exposed, not something it broke.
- **To see it:** put two AI units within about three cells of a shooter and watch which one the
  gun points at against which one takes the hit.

**taskblock-56 Pass B — the remaining suspect is CONFIRMED, and it is not the whole of the 43°.**
CC session `4ec878cf-1434-4676-8bd3-05c92eed071a`. An investigation, not a fix — nothing here
changed the aim path.

- **`ShotPlane.center_of` does exactly what this entry suspected.** It returns
  `best.rect.get_center()` where `best` is the target's **frontmost region** — whichever single
  projected face of whichever single part sits nearest the shooter. Not the body's centroid, and
  not a point on the muzzle-to-target axis. Read off a real plane, not off the source: on an
  assembled body the winner is the *pistol* at close range, a *plate_small_steel* at three cells,
  and *arm_cladding* at ten, because depth ordering shifts as the projection angle does.
- **The range effect this entry measured falls straight out of it.** The lateral error is a fixed
  distance in the body, so the angle it subtends grows as range shrinks. Measured, level ground,
  one assembled body:

  | range (cells) | frontmost region | aim height | off-axis |
  |---|---|---|---|
  | 1 | pistol | 0.80 | **20.1°** |
  | 2 | pistol | 0.80 | 5.9° |
  | 3 | plate_small_steel | 1.36 | 0.6° |
  | 10 | arm_cladding | 1.36 | −0.1° |

  Swept across the target's eight facings, the worst at 1 cell was **20.1°** and the worst at 5
  cells was **3.2°**. **This is the entry's own "it is a range effect, not a weapon effect",
  reproduced from the geometry instead of from the log.**
- **It does not account for the full deviation, and that matters.** This entry measured **43.1°**
  at 2.3–5.3 cells for unit 5 and **35.3°** at 2.1–4.5 for unit 1. The mechanism above tops out
  near **20°** at *one* cell and around **7°** at two. So it is a confirmed contributor of exactly
  the right shape and range-dependence, and **something else is also in play** — do not close this
  on the strength of the confirmation alone. Caveat on the comparison: the probe body carries a
  pistol, and the logged units did not; a weapon mounted further off the centreline would widen
  the lateral, though the chaingun units — the well-behaved ones — argue range dominates loadout.
- **The aim point goes DOWN as well as sideways**, which was not in this entry's framing. Its
  height is the winning part's height, dropping to the gun's **0.80** at close range from the upper
  body's **1.36**. Worth carrying to `BR51.01`, whose widened symptom is *"shots go left AND down"*.
- **`ShotPlane.center_of`'s no-region fallback is a latent second defect, unreported until now.**
  It returns `Vector2(target.cell.x, target.cell.y)` — a grid cell coordinate pair handed back
  where every caller expects a `(lateral, world height)` point in plane space. It fires only when
  the target projects no region at all, which is why nothing has seen it. **Not fixed here** (this
  pass is an investigation) and not given its own ID pending the supervisor's read, since it may
  be unreachable in practice.
- **Where this lands the design question.** Whether the aim point *should* be the frontmost
  region's centre, the body's centroid, or a point on the muzzle-to-target axis is a decision
  nobody has made — the current behaviour was never chosen, it is what "frontmost region" came to
  mean once bodies stopped being single boxes. Recorded in `docs/02` as a finding, explicitly not
  as intended behaviour. **Picking one is a design call, not a patch.**

**taskblock-61 Pass A — the range effect is confirmed independently, and the cause is now a design
decision rather than an investigation.**

`weapon_used` (taskblock-60 Pass B) was built for this entry and this is its first reading. 1391
first-hop impacts paired to the shot that announced them, across six AI bouts, measuring the angle
between the announced muzzle-to-target axis and where the round actually landed:

| range (cells) | n | mean | median | worst |
|---|---|---|---|---|
| 0 – 2 | 601 | **17.20°** | 9.84° | 89.36° |
| 2 – 4 | 154 | **15.60°** | 7.93° | 68.94° |
| 4 – 8 | 271 | 4.31° | 2.14° | 47.57° |
| 8+ | 365 | **2.51°** | 1.16° | 47.28° |

**Monotonic decay with range** — but **CC's first reading of that table was wrong and is corrected
here.** It attributed the decay to the aim point alone and called `docs/02`'s 20.1-degree
measurement an independent agreement. It is not independent: `docs/02` measured the aim-point
offset with no scatter, while the table above measures muzzle-to-target-cell against where the
round *landed*, which contains **the aim point and the weapon's scatter cone together**. A
fixed-radius scatter ring subtends an angle that grows as range shrinks for exactly the same
geometric reason the aim-point offset does, so the two are indistinguishable in that column.

**The supervisor caught this from the other side, 2026-08-07:** *"this does seem to imply that shot
recoil is behaving unpredictably. Even if a shot is aimed at an outstretched pistol, the cone angle
of fired shots should still be smaller than what's observed."*

**Decomposed, by comparing each sweep against what its own weapon's authored rings can subtend:**

| weapon | widest authored ring | can subtend at 1c / 2c / 8c | measured mean, 0-2 cells |
|---|---|---|---|
| `pistol` | 0.500 cells | 26.6° / 14.0° / 3.6° | **17.2°** |
| `sniper_rifle` | 0.030 cells | 1.7° / 0.9° / 0.2° | **8.8°** |

- **The pistol sweep is fully explained by its own scatter** and shows no anomaly at all. The first
  sweep was all-pistol, so **the headline table above is mostly a scatter cone, not the aim point.**
- **The sniper sweep is not.** Its authored scatter cannot exceed 1.7 degrees at any range in the
  sample, and the measurement is **8.8 degrees under two cells and 13.0 degrees at two-to-four** —
  roughly **ten times** what scatter permits. **That residual is the real `BR54.01`**, and it is
  what the aim point explains.
- **A content observation that falls out of the same table:** `pistol.tres` authors a **0.5-cell**
  widest ring against `chaingun`'s 0.6. `docs/02` describes the chaingun's huge radii as "aim
  centre mass, accept the spray"; a sidearm nearly as wide as a chaingun looks like a number nobody
  chose. **Not changed here** — balance is not invented — but worth a look.

**Fixed 2026-08-07 (taskblock-61): `ShotPlane.center_of` returns the TORSO's centre.** Supervisor's
call — *"aiming at the torso's center is likely the best aim point for a unit to use"*, with
per-body-part targeting arriving later for smarter units. The torso is the shell's `root`, which
needs no new tag and no authoring, and the frontmost region remains the fallback when the root
projects nothing at that angle.

**A second sweep on a different roster reproduced the decay** — 8+ cells at mean 1.44°, worst
3.49° — and found **no** long-range outliers at all. The 47° readings in the 4-8 and 8+ rows above
appear in one roster and not the other and are **not explained**; whoever picks this up should
isolate them before treating the table's tail as meaningful.

**A limit of both sweeps, stated rather than buried:** each produced exactly one weapon
(`pistol` in the first, `sniper_rifle` in the second) because the roster construction collapsed.
**So this confirms the RANGE half and does not test the weapon-independence half** — that still
rests on this entry's original per-unit table.

**And taskblock-60 Pass B removed a suspect.** `AttackAction.apply` calls `FaceAction.face_for_free`
toward its target *before* firing, so a queued attack always leaves with facing ≈ travel. **The 43
degrees cannot be the unit pointing the wrong way.**

**What is left is a decision, not a hunt.** `docs/02` states it outright: whether the aim point
*should* be the frontmost region's centre, the body's centroid, or a point on the muzzle-to-target
axis **is an open design question**, and the table above is a consequence rather than an intent. A
unit aiming at the pistol in an enemy's outstretched hand is not obviously wrong; a unit doing that
at one cell and missing the body entirely probably is.

### BR54.02 — Active — owner: `SUPERVISOR`
**A destroyed part vanishes from the shell before the tracer that destroyed it draws**
- **cluster:** `two-clocks`
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-08-03.
- The part disappears from the model at *resolution* time, while `ResolutionPlayer` has not yet drawn
  the shot that killed it. The player sees the consequence before the cause.
- **It should vanish when the tracer of the shot that destroyed it finishes playing**, not when the
  action resolves.
- **Same two-clocks shape as `BR27.07`** — RESOLUTION owns the mutation and completes immediately,
  while playback is still catching up, so anything keyed to live state runs ahead of the animation. The
  active-turn highlight was the first instance; this is the second, on the model rather than the
  overlay.
- **`PLAN.md`'s *Player view and sim view — render a snapshot* is the structural answer.** A view
  drawing from the last *played* state cannot show a part removed by a shot that has not been drawn.
  A narrow fix is deferring the removal until its impact plays; it is worth taking, and it is an
  instance of a class rather than the class.

### BR55.01 — Active — owner: `CC`
**Intermittent engine abort in `LoS.has_los` — an out-of-bounds cell reaches `Grid.get_opacity`**
- **cluster:** `engine-abort`
- **Source:** `CC`  ·  **CC session:** `e5393c3a-bd26-4668-8905-c50cf31e04cb`
- **Seen once in a full-suite run during taskblock-55 Pass D**, and **not reproducible**: the same
  file passed 12/12 in isolation immediately afterward, and the next full run was green at 2781
  tests. Recorded because a hard abort is worth a ledger entry even at one sighting — nothing about
  it was investigated away.
- **Not caused by this block's changes, as far as the trace goes.** The crash is on the AI planning
  path and taskblock-55 touched only the section format and the board view. Recorded rather than
  attributed.
- **The trace, most recent first:**
  ```
  [0] has_los            (src/logic/los.gd:18)
  [1] _has_direct_sight  (src/logic/world_view.gd:217)
  [2] units_visible_to   (src/logic/world_view.gd:118)
  [3] is_covered_from    (src/logic/cover.gd:41)
  [4] _is_covered        (src/logic/ai/utility_context.gd:688)
  [5] predicates_for     (src/logic/ai/utility_context.gd:555)
  [6] _score_all         (src/logic/ai/utility_planner.gd:262)
  [7] _apply_lookahead   (src/logic/ai/utility_planner.gd:184)
  [8] plan_turn          (src/logic/ai/utility_planner.gd:96)
      test_batch_objective.gd::test_a_follower_decides_differently_with_and_without_an_objective
  ```
- **The leading hypothesis, from reading the line.** `los.gd:18` is
  `grid.get_opacity(cells[i])` inside the `Grid.line(a, b)` walk, and `Grid.get_opacity` indexes a
  flat array as `cell.y * width + cell.x` with **no bounds check**. An endpoint outside the grid —
  or a cell the supercover line produces outside it — indexes past the array and aborts. `LoS`
  never calls `in_bounds`, and neither does `Grid.get_opacity`.
- **Why it would be intermittent.** The suite deliberately samples from the clock in
  `test_full_mission.gd`, so the boards and unit positions the AI plans against differ run to run
  (the suite's own note records a measured 19% spread in turn count across three runs). A rare
  position is exactly the shape of thing that would surface at one run in several.
- **What would settle it:** a bounds check in `LoS.has_los`, or in `Grid.get_opacity` itself, would
  turn the abort into a diagnosable value. Neither is in taskblock-55's scope, and guessing at the
  fix without a reproduction would be a change nobody could verify.

### BR55.03 — Active — owner: `SUPERVISOR`
**`HulkTheme.build()` caching was reported done and is absent from the code**
- **cluster:** `accounting`
- **Source:** review audit, 2026-08-04.  ·  Provenance: taskblock-51 Pass B1.
- **The spec and the report are quoted inline below rather than pointed at.** Both files rotate —
  `reports/` keeps a rolling five, so Taskblock 51's report is deleted at taskblock 56 — and CLAUDE.md's
  rule is to carry the fact inline because a pointer at either will dangle. Copied here 2026-08-04
  [CC `e5393c3a-bd26-4668-8905-c50cf31e04cb`] while both still existed:
  - **What Pass B1 asked for, verbatim:** *"`test_spectator_overlay.gd` costs 32.4 s across 37 real
    scene builds and zero bouts — the largest non-bout file in the suite. Caching the theme collapses
    it. **It costs the `ui_builds` counter**, which taskblock-48 added specifically to make view-only
    cost visible, dropping it from ~344 to ~1. **The supervisor has accepted that trade.** Record in
    `CHANGELOG.md` that the counter's meaning changed, so a later reader does not take a low
    `ui_builds` as evidence the view got cheaper."*
  - **What the report claimed, verbatim:** the pass table row *"B — ledger repairs, caching | **B1
    done**; B2 and B3 untouched (B3 left unmerged on supervisor instruction)"*.
  - **Corroborating the "assess the session" note below:** Pass B2 of that same block was *"Split
    `BR27.01`"*, recorded as untouched and in fact not done until 2026-08-04 — so the report tracked
    two of the three sub-passes correctly and got only B1 wrong.
- `src/view/hulk_theme.gd` builds a fresh `Theme` on **every** call and increments `ui_builds` on
  every call. **There is no cache, no static holder, and no caching at any of the five call sites** —
  `spectator_overlay`, `squad_control_overlay`, `generate_bout_overlay`, `builder_scene`,
  `resource_editor`. `test/unit/logic/test_work_counters.gd` still asserts that building an overlay
  moves `ui_builds`, which is precisely the assertion a cache would have had to change.
- **The spec also required a `CHANGELOG.md` entry** recording that the counter's meaning had changed,
  so a later reader would not read a low `ui_builds` as evidence the view got cheaper. **No such entry
  exists either.**
- **Either the pass never landed and the report is wrong, or it landed and was reverted with no
  `SUPERSEDED.md` row.** Both are worth knowing and the second is worse. The absence of *any* trace —
  no cache, no changelog line, no reversal row — points at the first.
- **Assess the session before re-attempting.** The same report says *"B2 and B3 untouched"*, so
  something was tracking that block at pass granularity and still recorded this one wrongly; a long
  session is the likeliest explanation and is worth confirming rather than assuming.
- **The original prize was 32.4 s** in `test_spectator_overlay.gd`, the largest non-bout file in the
  suite, across 37 real scene builds. Still available.

### BR57.03 — Active — owner: `SUPERVISOR`
**Player view drops frames while panning the camera**
- **cluster:** `framerate`
- **Source:** `SUPERVISOR`, 2026-08-05, observed in-game ("Player view is dropping FPS when panning.
  It might be in the current combat log").  ·  **CC session:**
  `cb234571-515f-4b21-bfe1-1abb38912aa0`
- **One real cost was found and removed. The report is NOT confirmed fixed** — see below.

**What was removed.** `CombatLogPanel._on_log_hovered` runs on every `InputEventMouseMotion` over
the log and called `_line_offsets()`, which walked the whole label calling `get_line_offset(i)` once
per line. On a long log that is hundreds of engine calls per motion event, and a camera pan produces
a motion event per frame. The offsets are cached between text changes now, keyed on the line count
so they cannot go stale and point the hover preview at the wrong line.

**Why this stays open.** *"Removed obviously wasted work"* is not *"fixed the framerate"*, and this
project's own rule is that a performance claim is a number rather than an adjudication — CC cannot
see a framerate. The supervisor's hunch was well aimed and the cost was real; whether it was **the**
cost is unmeasured.

**The next suspect, if it still drops.** `TacticsController.update_hover` also runs per motion event
and ray-picks against every unit and every blocker. `BR35.01` already added a cheap reject in front
of the per-box test for exactly this reason, which is evidence that this path has been expensive
before. `PerfStats` and the perf monitor are the instruments; the readout now survives an overlay
swap, so it can be turned on in one view and read in another.

### BR58.01 — Active — owner: `CC`
**`PlanPacer` aborts planning on wall-clock, so the same seed plans differently on different machines**
- **cluster:** `determinism`
- **2026-08-07 — retitled.** This was filed as *"geometric sight raised per-turn planning cost by
  1.3x"*, which reported a deviation and buried the defect. **The cost is context. The bug is that
  whether a unit finishes planning depends on how fast the machine is.**
- `PlanPacer.should_abort()` compares `Time.get_ticks_msec()` against a deadline. A slower machine
  aborts a plan a faster one completes, so **the viewed and headless paths diverge and the same seed
  does not reproduce** — which contradicts the standing determinism rule outright.
- **Latent since taskblock-44.** Nothing observed it while mean planning cost stayed under the budget;
  taskblock-58 pushed the mean past it and made it visible. **412 ms mean at Pass B against a 400 ms
  budget — already exceeded before that block.**
- **A budget that fires on ordinary turns is not a backstop, it is a governor.** Raising the number
  hides this until the next cost increase.
- **Fix direction**, so it is not re-derived: **pace on candidates, not milliseconds** — same seed, same
  candidates, same order, so both paths abort identically. Keep wall-clock only as a genuinely
  pathological backstop, seconds rather than milliseconds. `note_candidate()` must then count
  **unconditionally**, which means headless bouts start aborting too — **that is the fix, not a
  regression: determinism means both paths do the same thing, not that neither aborts.**
- **The cap is a measurement.** The suite reports ~900 candidates/turn mean over 1,063 turns, and **a
  mean is not a cap** — it lives in the tail. Balance-adjacent, so it must not be invented.

### BR60.02 — Active — owner: `CC`
**A mangled or disabled part is hittable and undrawn — the view and the shot plane disagree about which parts exist**
- **cluster:** `view-model-membership`
- **Source:** `CC`  ·  **CC session:** `93549217-f453-4fd6-b8f3-cecf9532290e`
- **Found:** 2026-08-06, taskblock-60 Pass C, while testing the claim that seven view entries
  share one root. **They do not, and this is what one of them turned out to be.**

**Two functions answer "does this part exist" and they answer differently.**

- `BodyProjector.projects(part)` — what a **shot** resolves against — returns
  `hp > 0 or is_mangled or is_disabled`. Its own doc states the rule: *"a part at 0 hp still
  projects — still occludes, still hittable — if it failed under MANGLE or DISABLE (both stay
  fully attached, `docs/03`)."*
- `UnitGeometry.assembly_placements` — what the **view** draws, via
  `HitVolumeView` — emits boxes under a bare `if part.hp > 0`.

**Measured on a real assembled body**, reading both back rather than re-deriving either:

| leg state | `projects()` | placement boxes drawn |
|---|---|---|
| healthy | true | 1 |
| destroyed (plain 0 hp) | false | 0 |
| **mangled at 0 hp** | **true** | **0** |
| **disabled at 0 hp** | **true** | **0** |

**So a mangled limb is a thing you can shoot and cannot see.** That is `docs/10`'s "render is
hitbox" pillar broken outright, not a timing artefact — the two callers disagree in the same
frame, with no animation involved.

**This is very likely `BR52.06`** (*"a leg doesn't seem to have a model"*). A leg is among the
likeliest parts to be mangled rather than cleanly destroyed, and mangling leaves it attached, so
the unit keeps walking around with an invisible limb that still stops rounds. That entry's own
proposed theory — a part authoring no `volume` — is **ruled out**: every leg part in
`data/parts` authors real boxes, checked.

**Which side is wrong is a real decision and is not made here.** Either the view should draw
what projects (a mangled limb is visibly wrecked, which is the reading `docs/03`'s mangle state
implies), or `projects()` is too generous and a mangled part should stop being hittable. **They
must not be decided separately** — this is the fourth time this codebase has found two answers
to one membership question (`PLAN.md`'s *Derive plane/picker membership instead of answering it
in four places* records the other three), and the fix belongs with that item rather than as a
fifth local patch.

**taskblock-61 Pass B — the obvious fix was tried, it is wrong, and that is this entry's most
useful finding.**

**What was tried.** Make `UnitGeometry.assembly_placements` defer to `BodyProjector.projects`
instead of testing `hp > 0` itself. Every argument pointed that way: the projector's own doc
comment claims to be *"the only answer"*, `Part.is_disabled` promises a part that *"still occupies
its socket and still occludes shots as geometry"*, and `docs/10`'s pillar is render-is-hitbox.

**What happened.** `test_los.gd::test_destroying_a_wall_with_a_real_shot_clears_los_through_it`
went red — **a destroyed wall went back to blocking line of sight** — along with a bout-determinism
golden downstream of it. **`Part.failure_mode` defaults to `&"MANGLE"` and `wall.tres` authors
none**, so every destroyed wall on every board is `is_mangled`, the projector admits it, and giving
it boxes again resurrects it. `docs/02`'s settled tb31 Pass C rule is explicit the other way:
destroy a wall and *"its cell clears to fully passable ground, the same as any other dead cover"*.

**So the framing in this entry's own heading is wrong, and it is corrected here rather than
quietly.** These are **not two answers to one question**. They are two different questions applied
in series, and the series is load-bearing:

| | asks | consumers |
|---|---|---|
| `BodyProjector.projects` | *may this part be considered at all* | `RayCaster`, `SightSpans` gate on it |
| `UnitGeometry.assembly_placements` | *does it still have volume* | the same callers, immediately after |

Collapsing them conflates **"not excluded"** with **"still solid"**.

**The real disagreement is upstream of both, and it is a content/design question.** `MANGLE` being
the *default* failure mode means almost everything is mangled at 0 hp — which is not what
`Part.is_mangled` describes. Its own comment is about *"the wreckage look"*, a part that *"isn't
simply gone"*, and `docs/01` says a part with `mangles_into` set is **replaced** by wreckage.
**A rule that tells a wrecked cladding plate from a demolished wall cannot be a boolean over
`is_mangled`.** Candidates, none chosen here:

- **Key on `mangles_into`** — a part that names a wreck becomes that wreck and keeps volume; one
  that does not is simply gone. Closest to `docs/01`'s stated model.
- **Stop defaulting `failure_mode` to `MANGLE`**, so mangling is something a designer opts into.
  Changes every unauthored part in the library, which is the whole library.
- **Give the projector a second question** — "considered" versus "solid" — making the current
  series explicit rather than accidental.

**Consequence for `BR52.06`, and it is worse than "invisible".** `RayCaster` gates on `projects`
and then marches `assembly_placements`, so an empty box list means the ray finds nothing. **A
mangled leg is invisible AND intangible**, not merely undrawn — which fits *"a leg appears to have
no model"* more exactly than the original reading did.

**Characterised by `test_membership_disagreement.gd`**, which asserts the current contradictory
behaviour on purpose, states that those assertions describe a defect rather than an intent, and
pins the `failure_mode` default that makes any naive fix resurrect walls. **When this entry is
decided, that file wants rewriting rather than patching.**

**The rule is chosen, and the work is a refit rather than a fix (supervisor, 2026-08-07).**
Mangling becomes **replacement**: a mangled thing becomes a wreck part with its own volume and a
lower DT, so it blocks shots poorly because it *is* a poor blocker; destroy the wreck and it is
gone under the ordinary `hp > 0` rule. *"A mangled wall is a wall that no longer works as a wall; a
mangled leg is a leg that no longer works as a leg."* **`is_mangled` then stops being a membership
question at all, which is what closes this entry.**

**Explicitly deferred out of the hunt**, on the supervisor's instruction that a major refit does
not happen mid-bug-hunt. Recorded as `PLAN.md`'s *Mangling is replacement, and a mangled thing no
longer works as that thing*, with the measured scope: `Part.mangles_into` is **read by nothing**,
so this is a new mechanic; `failure_mode` defaults to `MANGLE`; six batteries and `wall` author no
wreck to become.

**Still `Active`, and it closes as a consequence of that item rather than on its own.**
taskblock-61 fixed nothing here.

### BR61.01 — Active — owner: `SUPERVISOR`
**Every test run rotates and writes the supervisor's live combat log, so CC's tooling and the supervisor's play sessions land in the same files**
- **cluster:** `test-infrastructure`
- **Source:** `SUPERVISOR`, 2026-08-07 — *"your tools should print to log as well. We may have
  clobbered a bit there, your tools and my tests printing to the same files."*  ·  **CC session:**
  `93549217-f453-4fd6-b8f3-cecf9532290e`

**Confirmed.** `FileSink` defaults to `res://out/combat.log` and archives the previous session into
`res://out/logs/<timestamp>.log` on first construction per path. `BattleScene` constructs one
unconditionally — so **any test that builds a real `BattleScene` rotates the live log and writes
into it.** The view suite does that many times per run, and a full gate takes ~23 minutes of it.

**The damage is to the monitoring channel, which `docs/09` calls "CC's and your monitoring channel
— one channel, two consumers."** Concretely, this session:

- CC read a pistol shot out of a session log and reported it to the supervisor as a **working
  control** proving the defect was selective. The supervisor had fired no pistol. The reading was
  from a different bout, and the conclusion drawn from it was wrong (see `BR51.01`).
- Timestamped session logs interleave: `combat-20260809-023129.log` contains only pistol shots and
  no chaingun/sniper/shotgun, and lines up with a CC gate rather than a play session.

**The fix is a path, not a mechanism.** `FileSink._init` already takes one — `BattleScene` is the
only caller that defaults it. A test-owned path (an env var the suite sets, or a `res://out/test/`
default when running headless) separates the two consumers without touching rotation, `tail -f`,
or the startup `log: <path>` line the supervisor uses.

**Not fixed here** — filed mid-investigation, and the supervisor is isolating runs by hand for now.
**Worth doing before the next hunt**, because a shared monitoring channel that silently mixes two
sources produced a wrong conclusion within an hour of being noticed.

**Promoted to `SUPERVISOR` ownership at the supervisor's request, 2026-08-07:** *"I want to have a
hand in its creation."* So the separation is a design conversation rather than a CC chore — where
the test log lives, whether the split is by path or by process, and what the startup line says are
all decisions about a channel `docs/09` gives two consumers. **CC may not close this.**

### BR61.02 — Active — owner: `CC`
**The aim camera's lean moves a stationary cursor's aim point by 1.5 cells**
- **cluster:** `shot-geometry`
- **Source:** `CC`  ·  **CC session:** `93549217-f453-4fd6-b8f3-cecf9532290e`
- **Found:** 2026-08-07, taskblock-61, while hunting `BR51.01`. **Filed only now that `BR51.01` is
  settled** — filing entries off a moving diagnosis is how a ledger fills with near-misses.

**`CameraRig.aim_at` rotates the real `Camera3D` toward the reticle by up to `MAX_LEAN_DEG` (5.0),
and `TacticsController.aim_reticle_at_screen` casts the cursor ray through that same camera.** So
the camera moves in response to where the reticle is, and the reticle is computed by projecting
through the camera.

**Measured**, and `test_aim_ray_is_camera_dependent.gd` pins it: the same screen pixel resolves to
`(0.0000, 0.0000)` un-leaned and `(+1.5000, 0.0000)` after the lean. **The shift equals the reticle
offset leaned toward** — the lean drags the aim point onto itself rather than merely nudging it.

**Bounded, not compounding.** `aim_at` calls `look_at(centre)` before leaning, so each frame
re-bases on the un-leaned pose; six cycles move the reading by 0.00000 cells. That matters for the
fix: a compounding error would need the loop cut, a bounded one needs the cursor's meaning anchored
to something the camera does not move.

**This is NOT `BR51.01`** — removing the lean was implemented and the reported symptom persisted in
game, which is what sent that hunt elsewhere. It is a real defect of its own, and a much smaller one.

**Do not "fix" it by un-leaning the projection.** That restores the old answer exactly (pinned in
the same test file), which is what makes it look like a fix while leaving the cursor's meaning
dependent on a camera pose. **Do not delete the lean either** — supervisor, 2026-08-07:
*"disconnecting the flourish and the actual result is what we're trying for here."* The shape is
`PLAN.md`'s *Take the camera out of shot processing*.

### BR61.03 — Active — owner: `CC`
**The aim preview and the shot resolution anchor their planes at different points**
- **cluster:** `shot-geometry`
- **Source:** `CC`  ·  **CC session:** `93549217-f453-4fd6-b8f3-cecf9532290e`
- **Found:** 2026-08-07, taskblock-61, while hunting `BR51.01`.

**Two planes, two anchors, and each file's own comment admits its choice:**

| | origin | height |
|---|---|---|
| `TacticsController._build_aim_state` (preview) | shooter's **cell** | **ground** — *"no specific weapon is in view for the aim PREVIEW itself ... same no-muzzle convention"* |
| `AttackAction.apply` (resolution) | **shouldered muzzle** | **muzzle** |

**taskblock-26 Pass A2 moved the resolution anchor off the cell centre and left the preview
behind.** Its own comment explains why the resolution had to move — the tracer was landing "dead in
the middle of the shooter's own torso" — and nothing carried that to the preview.

**Measured at 0.067 cells of centre-mass difference at 2 range, decaying to 0.006 at 12.** Real,
small, and **not** `BR51.01`, which it was briefly suspected of being.

**The weapon IS available to the preview**, so the comment's premise is stale: `TacticsController`
already passes `weapon.id` into `ActionCatalog.build_firing_action` a few lines away.

### BR61.04 — Active — owner: `CC`
**The wall-cutout feed rebuilds every body's full geometry every frame**
- **cluster:** `framerate`
- **Source:** `CC`  ·  **CC session:** `74ebb574-245b-48e8-aed2-e1d09ea25527`
- **2026-08-09 (taskblock-61 Pass C1).** Found while measuring a regression CC had just introduced
  next to it, and it is the larger number. `BoardView.update_wall_cutout` runs from `_process` and
  needs each unit's body centre, which it gets from `UnitGeometry.bounding_box` — a full
  `placements()` tree walk plus `placements_aabb`'s **eight corner transforms per box**. A real
  assembled shell is **48 boxes**. Measured at **3 114 usec per frame for a 16-unit roster** on a
  32x24 board: **45% of a 144 fps frame, 19% of a 60 fps one**, spent entirely on recomputing
  geometry that did not change.
- **Nothing about it is per-frame except the camera.** A body's box layout changes only when the
  unit moves, turns, re-poses or loses a part; the camera orbiting is what forces the reprojection,
  and reprojection needs one `Vector3` per unit, not the whole box tree.
- **`BattleScene._occluding_friendlies` pays it a second time** in the same frame, on the same
  units, for the friendly-fade effect — `bounding_sphere` per unit per frame there too.
- **Fix direction, not implemented:** cache the box per unit against whatever actually invalidates
  it. **The lifecycle is the whole difficulty**, exactly as `BR32.04`'s own recorded fix shape
  found — a stale cached position is a new class of bug, and `docs/00`'s "read the real node back"
  argues for reading the rendered transform rather than caching a derived value. Worth doing
  together with `BR32.04`, which needs the rendered position for the same call.
- **Deliberately not fixed in Pass C1**, which was hunting `BR32.05`/`BR32.08`. Recorded with the
  measurement so it is not re-derived.

### BR61.05 — Active — owner: `CC`
**The friendly-fade ghost reads logical positions while bodies are still animating**
- **cluster:** `wall-cutout`
- **Source:** `CC`  ·  **CC session:** `74ebb574-245b-48e8-aed2-e1d09ea25527`
- **2026-08-09 (taskblock-61 Pass C1).** `BR32.04` in a second place. `BattleScene.
  _occluding_friendlies` decides which squadmates to ghost from `UnitGeometry.bounding_sphere(unit).
  center` for both the active unit and each candidate — the **logical** body. `resolve_to_marker()`
  mutates `unit.cell` synchronously while `ResolutionPlayer` tweens the visible body over several
  frames, so during any slide the fade is computed against positions nobody is looking at: a
  friendly can ghost before it has visibly moved into the way, or stay solid while visibly standing
  in it.
- **Not a guess** — the same function, the same call, the same frame as the cutout defect fixed in
  this pass; it was found by reading the code next to it.
- **Fix direction:** the same one, and cheaper here — `BattleScene` already holds `unit_views`, so
  it needs no new plumbing at all, just `view.global_transform * position` per unit.
- **Deliberately not fixed alongside `BR32.04`.** That entry is `SUPERVISOR`-owned and awaiting a
  look; changing a second visible effect in the same commit would make what the supervisor sees
  harder to attribute. One change at a time on a subsystem under verification.

### BR61.06 — Suspected — owner: `CC`
**A destroyed part reports `part_destroyed` and `part_mangled` in the same instant**
- **cluster:** `wall-cutout`
- **Source:** `CC`  ·  **CC session:** `74ebb574-245b-48e8-aed2-e1d09ea25527`
- **2026-08-09 (taskblock-61 Pass D).** Seen in the supervisor's own live burst, immediately after
  obstructed shots became legal — a chaingun burst chewing through a forklift:
  ```
  impact: STOP_DEAD on forklift ...
  part_destroyed: forklift
  part_mangled: forklift
  burst_pull: 4/12
  ```
  **Both, for one part, at one instant.** Destroyed and mangled are meant to be different outcomes.
- **Almost certainly `Part.failure_mode` defaulting to `MANGLE`** with no cover or terrain part
  authoring one — the same default taskblock-61 Pass B already caught resurrecting destroyed walls
  as sight blockers, and the same one `BR60.02`'s mangle refit exists to settle.
- **Why it may be harmless today and is still worth an entry:** `BodyProjector.projects()` returns
  `hp > 0 or is_mangled or is_disabled`, so a destroyed-and-mangled part still *projects* — but
  `UnitGeometry.assembly_placements` emits boxes on a bare `hp > 0`, so it has no geometry to meet.
  The forklift's own later rounds passed through to the wall behind it correctly. **The
  contradiction is in the events, not yet in the behaviour** — which is exactly the kind of thing
  that becomes a real defect the moment something starts reading `is_mangled`.
- **`Suspected` on purpose:** the mechanism is inferred from the log and the known default, not
  confirmed by reading the emitting code. Do not fix ahead of `BR60.02`'s refit, which owns the rule.

### BR61.07 — Pending — owner: `SUPERVISOR`  ·  **CC session:** `4d8755ca-841c-4dc7-aa67-432a6b560498`
**A debug injection tears the destroyed thing off the board before its explosion animates**
- **cluster:** `two-clocks`
- **Source:** `SUPERVISOR`  ·  **CC session:** `906e0f07-5b0a-47bd-8444-fb42ed468da2`
- **Found:** 2026-08-09, confirming `BR51.21` in a live session. *"Explosion plays, destroyed
  things disappear before the explosion plays."* Filed separately rather than reopening `BR51.21`,
  whose own defect — no injection animating at all — is fixed and confirmed.

**Mechanism, read from source rather than inferred.** `DebugPanelModule._on_debug_panel_applied`
runs its view resync **before** it plays the injection's events:
`sync_unit_views` → `sync_board_view` (when `DebugVerbs.affects_board`) → `refresh_unit_views` →
`_play_injection`. `sync_board_view` is a full `BoardView.build()`, and a blocker's mesh comes from
`UnitGeometry.assembly_placements`, **which emits boxes under a bare `hp > 0`.** A barrel forced to
0 hp therefore produces no placements, so the rebuild drops its model — and only then does the
detonation animate, at a cell that is already empty.

**The sync-before-play order is not simply wrong, which is why this needs a decision rather than a
swap.** `BR51.21`'s own entry records why it is right: `ResolutionPlayer._prime` is documented as
running in the same frame `refresh_unit_views()` did, and that is what stops a unit flashing at its
destination and jumping back. **The order is correct for units and wrong for the board** — a moved
unit must be primed before playback, a destroyed object must survive until after it.

**`sync_board_view` has exactly two callers and neither real resolution path is one of them**
(`debug_panel_module.gd` and `editor_module.gd`). `PlaybackModule` and `UnitInputModule` both go
`refresh_unit_views` → `ResolutionModule.play` and never rebuild the board. So this ordering exists
only on the injection path.

**It is the mirror of `BR52.09`, and they are one question.** On the real path nothing tears a
destroyed blocker's model down at all, so it wrongly *stays* (`BR52.09`, `Active`); on the debug
path `sync_board_view` tears it down early, so it wrongly *goes*. **Both are the same missing
thing: nothing sequences blocker teardown against the animation that explains it.** A fix that
moves the board sync after playback closes this one and leaves `BR52.09` untouched; a real
teardown path driven by `part_destroyed` would close both, and is what `BR52.09` already asks for.

**Also touches `BR60.02`.** The bare `hp > 0` in `assembly_placements` is the same membership
disagreement that entry owns — `BodyProjector.projects()` answers `hp > 0 or is_mangled or
is_disabled` for the same part. The disappearance here is that disagreement made visible.

**taskblock-61 Pass G — `Pending`, fixed in the same session it was reported.** CC session
`906e0f07-5b0a-47bd-8444-fb42ed468da2`.

- **The resync is split along the line the two rules actually fall on.** Unit syncs
  (`sync_unit_views` / `refresh_unit_views`) stay **before** playback, because
  `ResolutionPlayer._prime` needs the frame `refresh_unit_views()` ran in; `sync_board_view` moves
  **after** it, because a destroyed object has to survive until its own explanation has played.
  **Not a line moved down** — the old order was correct for one of the two and wrong for the other,
  and nothing had separated them.
- **`_play_injection` is now awaited.** Without the `await`, `_on_debug_panel_applied` detaches at
  the first suspend inside `ResolutionModule.play` and the board rebuild runs immediately anyway —
  the same defect wearing a different shape.
- **A board verb that animates nothing is not delayed.** `_play_injection` returns without
  suspending on an empty list, so the rebuild still lands in the same frame. Pinned by its own
  test, because the obvious fix trades a visual bug for an unresponsive debug panel.
- **Measured both ways.** Board meshes across a forced detonation: **62 before, 62 while the
  explosion plays** with the fix; **62 before, 61 while it plays** without it — the barrel's mesh
  gone at the moment its own detonation started.
- **To see it:** set a goo barrel's HP to 0 and press Apply. **The barrel should still be on the
  board while the explosion plays over it, and vanish as the animation ends** — not blink out first
  and leave the explosion hanging in empty space.
- **`BR52.09` is untouched and is the other half of this.** On the real path nothing tears a
  destroyed blocker's model down at all, so it wrongly stays; a `part_destroyed`-driven teardown
  would close both and is what that entry already asks for. **This fix deliberately does not
  attempt it** — it corrects an ordering on the injection path and invents no teardown mechanism.
- **Tests:** `test_squad_control_overlay.gd::test_a_destroyed_blocker_keeps_its_mesh_until_its_
  explosion_has_played` (confirmed red on the old ordering) and
  `::test_a_board_verb_with_nothing_to_animate_still_rebuilds_immediately`.

- **2026-08-10 (supervisor via `HBPaR3`) — REOPENED, and the symptom has inverted.** It was *too
  early* — the destroyed thing left the board before its tracer played. It is now **comically late**.
- **A two-clocks fix that overshot rather than landed.** The removal moved from resolution time to
  playback time and is now waiting for something longer than the impact — plausibly the whole action's
  playback rather than the individual hit that caused it.
- **`BR54.02` is the same pairing from the other side** (a part vanishing before the tracer that
  destroyed it), so whatever clock this now reads, check that entry against it too.

- **tb64 Pass G — `Pending` again, and the diagnosis in the reopening was right.** The rebuild was
  running after `await _play_injection(events)` — after the **whole** sequence — so a one-event
  injection looked fine and a longer one left wreckage standing until the last tracer finished.
  *"Waiting for something longer than the impact"* is exactly what it was doing.
- **The clock is now the destroying event's own playback.** `ResolutionPlayer` fires an optional
  `on_board_changed` hook after it has finished awaiting an event whose kind is in
  `BOARD_CHANGING_KINDS` (`part_destroyed`, `detonate` — open by content, so a later verb joins as
  data). It rides the same *"is this the final hop of a pull"* decision the pacing already makes,
  so a continuation hop cannot tear the board down before anything was seen.
- **Both directions are pinned now, which is what the reopening cost.** Too-early stays covered by
  `test_a_destroyed_blocker_keeps_its_mesh_until_its_explosion_has_played` (62 board meshes before,
  62 while the explosion plays); too-late is covered by
  `test_the_board_hook_fires_once_per_destroying_event_not_once_per_action` — **two destroying
  events must produce two resyncs, not one.** Counted rather than timed, because wall-clock
  ordering inside playback is flaky to assert and the count encodes the fix exactly.
- **A board verb that destroys nothing still rebuilds once, in the same frame.** `place_cover` and
  `move_object` change the board with no event to ride, so the end-of-playback rebuild survives for
  them, guarded so a verb that already resynced mid-playback does not do it twice.
- **`BR54.02` is NOT addressed and is not claimed to be.** That entry is about a *unit's* part, and
  unit views are refreshed **before** playback on purpose — `ResolutionPlayer._prime` needs the
  frame `refresh_unit_views()` ran in, which is `BR51.21`'s own reasoning. This pass moved the
  board clock only; the unit-part clock is untouched and still wants the `part_destroyed`-driven
  teardown `BR52.09` asks for.
- **To see it:** force a detonation that destroys more than one thing. Each should stay on the
  board until its own explosion has played and then go — not all of them at the very end.

### BR61.08 — Active — owner: `SUPERVISOR`
**AI turns are not animated**
- **cluster:** `two-clocks`
- **Source:** `SUPERVISOR`, 2026-08-09, post-taskblock-61 review.
- An AI unit's turn resolves without playback — the board updates and nothing plays. **The player sees
  results, never the action that produced them**, which is the whole point of `ResolutionPlayer`.
- **Related to `BR51.21`** (a debug injection never animated because nothing called
  `ResolutionPlayer.play()`), resolved in taskblock-61 Pass E3. **Check whether the AI batch path has
  the same omission** before treating this as a new mechanism.

### BR61.09 — Active — owner: `SUPERVISOR`
**A shot can be silently refused: no AP spent, no aim window, back to overview**
- **cluster:** `input-affordance`
- **Source:** `SUPERVISOR`, 2026-08-09, post-taskblock-61 review.
- Picking a target sometimes drops straight back to the overview camera with nothing spent and nothing
  said. **The supervisor: *"not a bug, just never defined"*** — the refusal is legitimate, the silence
  is not.
- **This is `PLAN.md`'s *A legality check answers a bare boolean* with a face on it.** A refusal that
  cannot say why is indistinguishable from a bug, and this is the second time that has cost a session.
- **Likely subsumed by the aiming rebuild**; confirm rather than assume.

### BR61.10 — Active — owner: `SUPERVISOR`
**The dartboard does not scale with distance**
- **cluster:** `input-affordance`
- **Source:** `SUPERVISOR`, 2026-08-09, post-taskblock-61 review.
- Its radii are fixed rather than being **the radii at a marked distance, extrapolated for every
  other**. A target at 3 cells and one at 18 present the same board, so the aim reads as equally
  precise at any range.
- **Likely subsumed by the aiming rebuild.**

### BR61.11 — Active — owner: `SUPERVISOR`
**Terrain parts are hoverable through the combat log, producing tooltips over the panel**
- **cluster:** `input-affordance`
- **Source:** `SUPERVISOR`, 2026-08-09, post-taskblock-61 review.
- Hovering the combat log raises tooltips for terrain behind it. **The panel is not consuming the
  hover**, so the board picks it up underneath.
- **Third instance of a full-rect container's input handling being wrong** — after `BR31.01` and the
  `TopLeftControls` fix, both listed under the `mouse_filter` sweep. **Check that sweep's scope covers
  the log before fixing this one locally.**

### BR61.12 — Active — owner: `SUPERVISOR`
**The end-turn confirmation dialog does not match the rest of the UI**
- **cluster:** `input-affordance`
- **Source:** `SUPERVISOR`, 2026-08-09, post-taskblock-61 review.
- Different visual language from every other panel. **Low priority and jarring** — the supervisor's own
  weighting.
- Worth folding into whatever next touches confirmation dialogs rather than a pass of its own.

### BR61.13 — Active — owner: `SUPERVISOR`
**Frame drops during initial map generation, not persisting into a bout**
- **cluster:** `framerate`
- **Source:** `SUPERVISOR`, 2026-08-09, post-taskblock-61 review.
- The non-bout spawn drops frames; entering a bout clears it. **A one-time cost that shows**, rather
  than a sustained rate.
- **Judged against the ledger's hitch bar** — worst frame over roughly 100 ms — not against an average.
  Measure before treating it as severe.

### BR61.14 — Active — owner: `SUPERVISOR`
**A large hitch on the camera move from overview to over-the-shoulder**
- **cluster:** `framerate`
- **Source:** `SUPERVISOR`, 2026-08-09, post-taskblock-61 review.
- Found while troubleshooting something else. **Distinct from `BR51.15`**, which is the hitch as the
  OTS camera *swings behind* the unit; this is the transition into OTS at all.
- **Both are likely retired by the aiming and camera rebuild**, so measure and record rather than
  tuning the current rig.
