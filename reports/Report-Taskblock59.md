# Taskblock 59 Report — the editor stops lying, and the tiers reach a bout

**All six passes landed — A through F — in order, on `master`, full gate green (3274 of 3274).
Fourteen supervisor reports were then worked after the block closed** — see *After the block* at the
end, which is where the most interesting corrections in this report are. That work is gated and
pushed too: full gate green, 339 scripts, 3322 tests, 0 failures.

**The block's own framing held everywhere it was applied**: *something authored a capability and
nothing authored the way in.* Five of the six passes are that shape, and Pass A turned out to be the
same thing one layer down — the editor's model could hold a placement the board had no way to draw,
and the view silently stopped tracking it.

**Pass F inverted.** Every completion figure this project had recorded was an all-`TRAINED` figure.
Taken again with tiers authored, **`MINDLESS` is the only tier that finishes a mission** — 33.3%
against 0% for `GRUNT`, `TRAINED` and `ELITE`. It cannot shoot, so it walks to the extraction cells;
every tier that can fight stops to fight and hits the turn cap. That is a finding about the AI's
priorities, and it is reported untuned as the pass required.

## Decisions made without asking

**Pass A: the editor refuses a second blocker on a cell, rather than warning about it.** The
editor's standing rule is *warn, never block*, and this is a refusal — so the line matters. It is
`MapSerializer`'s own: two blockers on one cell is *"not an authoring opinion, it is a file that does
not describe a map"*, because `Grid.blockers` is one part per cell. A board with no walkable surface,
an unnavigable pit and a stack of surfaces all stay authorable and merely warned about. **The
alternative was accepting it and rendering leniently**, which the acceptance forbids — *"model and
view agreeing, whichever way the placement resolves"* — and which is what produced the corruption.

**Pass A: the lenient render reverses a documented decision rather than extending it.**
`_refresh_board`'s comment argued for keeping the last good board. I deleted that behaviour outright
rather than adding a fallback beside it, because both halves of its argument were false and leaving
it as an option would have kept the failure mode reachable. Recorded in `SUPERSEDED.md`.

**Pass A: `EditorPanel`, and it is the fourth lint-gate-triggered split in this area.**
`editor_module.gd` hit the 1000-line limit for the third time and `board_view.gd` for the first, and
taskblock-58's report predicted exactly this. I took the panel rather than shaving comments, because
the block had three more passes that all add to that module. **The trigger was a linter, not an
insight** — worth saying plainly, since the same sentence now appears in four file headers.

**Pass B: the wall cutout is fixed as "not drawn, so not cut around" rather than "off in the
editor".** The taskblock offered both. The visibility rule needs no mode named in `BoardView`, holds
for any other surface that hides a unit, and reuses the exclusion set that already exists for the
debug *vanish* verb — so it cannot drift out of step with what `_hide_stranded` decided, because it
is the same decision.

**Pass B: the Map Thing picker composes `claim_<kind>` ids.** One list, with `claim` expanded per
claim kind, rather than a two-step pick. The composed ids are the only thing in that file that is
not already a vocabulary elsewhere, and one function composes and decodes them — so adding a claim
kind or a map thing still needs no edit there. **The alternative was a second list opening on
`claim`**, which is two questions where the author has one intention.

**Pass C: `MapPlacement.offset` is a new data field, taken on after checking rather than assumed.**
The supervisor asked me to size it first. `PlacedVolume.boxes_for` has exactly one production caller
and bakes its result into `Part.volume`, so the offset reaches every consumer with no signature
change anywhere; the eight `MapPlacement.new` call sites all use defaulted trailing params. **It
rides `size`'s path exactly**, which is why it was worth doing now rather than queuing.

**Pass D: a veneer is recognised by `LedgeVeneer.PART_ID`, one named part.** A tag would be the
open-vocabulary answer and I did not invent one: *which* parts compute their rise from the board is a
content question, and the check is in one place so a second facing part is an entry there rather than
a branch at the call site.

**Pass F: the per-tier probe is a command, not a suite test.** It plays 30 bouts and took 1474 s;
its first cut printed only a final table and was killed by its own timeout at 37 minutes having
emitted nothing, so it streams each row as it finishes. The
suite gets four cheap tests asserting the report's *shape* and that no threshold moved; the numbers
come from `tools/probe_tiers.gd`, which is the same split `probe_seeds.gd` already uses and for the
same reason — *"a gate that occasionally triples its own runtime teaches people to stop running it."*

## Tests that failed, then were corrected

**Nine failing before correction across the block**, five of them the useful kind — the change was
right and the fixture held an assumption that had stopped being true.

1. **`test_parts_list.gd::test_what_the_ghost_showed_is_what_gets_placed`, and it is the most
   valuable entry here.** It hovered a wall's **top** face and asserted the click authored a matching
   placement. That case never worked: a wall stacked on a wall is a second blocker on one cell, which
   `Grid.blockers` cannot hold. **The test passed throughout because it compared the ghost against
   `EditorController.placements` — the model — and never against the board.** The acceptance is *"what
   appears"*, and nothing appeared. It hovers a side face now, which lands in the neighbouring cell
   and really draws; the top face has its own test asserting the ghost declines to promise it.
2. **`test_editor_scale.gd::test_a_top_face_drag_leaves_the_base_where_it_was` caught a wrong model,
   not a typo.** My first `GizmoDrag.grow` added a fixed `amount/2` offset for an asymmetric face
   move. `PlacedVolume.boxes_for` scales boxes about the **part's origin**, so `wall` — authored with
   its base at y=0 — already grows upward on its own, and the fixed offset double-counted it: the top
   drag lifted the wall off its own floor by half the drag. Rewritten to solve for the offset from
   where the faces should end up, which is content-independent by construction.
3. **`test_editor_controller.gd::test_a_placement_outside_the_board_is_named`.** Failed on wording
   only, and that is the point: `EditorController` had a second sweep re-deriving out-of-bounds
   beside the serializer's. Deleting the duplicate changed the sentence. The test asserts the fact
   now — the cell, the bounds, that it is called out — rather than the phrasing.
4. **Two taskblock-57 readout tests pinned the exact content line** (`"ship_floor"`, `"empty"`),
   which Pass B deliberately changed by adding what is being placed. Both now assert the claim they
   were written for.
5. **`test_intelligence_tiers.gd`, twice, and one was a real finding.** The blackboard assertion
   failed because I built an unrestricted `WorldView`; `AiPlanner` sets `restricted = true` once for
   every planning call, and an unrestricted view answers `true` to every capability regardless of
   tier — so I was asserting against a view no planner sees. The overwatch assertion failed because
   **the taskblock's table and the authored data disagree**: the table describes `GRUNT` as having
   the shoot/cover/overwatch set, and `overwatch.tres` has read `[TRAINED, ELITE]` since
   taskblock-45. Left as authored and pinned, because which tier gains overwatch is a balance
   decision rather than a typo.

**A process failure worth recording separately.** My own `test_editor_visible_gaps.gd` dereferenced a
null `material_override` after an assertion failed, which under `-d` opens a Debugger Break and
**hangs** the run rather than failing it — the exact shape `run_tests.sh`'s header warns about and
which cost taskblock-58 hours. Caught by the `timeout` wrapper. The test guards the deref now.

## `SUPERVISOR`-owned entries moved to `Pending`

- **`BR59.01` — a refused placement freezes the editor's board.** To see it work: open the editor
  (`E`), place a pillar, click a second onto the same cell. Before, the pillar vanished and nothing
  placed afterwards ever appeared again. Now the click authors nothing, the combat log says *"(x, y)
  already has a 'pillar' on it; a cell holds one blocker"*, no ghost is offered for that face, and
  every later placement draws normally.
- **`BR59.02` — `Delete` removes the record but not the mesh.** The same defect from the other side.
  To see it work: place and delete a pillar — the mesh goes with the record. Then repeat the
  `BR59.01` sequence and delete afterwards; the delete now draws.

## Open questions

**1. `MINDLESS` outperforming every combat-capable tier is the block's largest finding, and it is
not an editor question.** Over seeds 0–5, three a side, 100-turn cap:

| tier | rate | outcomes | cost |
|---|---|---|---|
| `MINDLESS` | **33.3%** | 2 extracted, 4 at the cap | 112 s |
| `GRUNT` | 0.0% | 5 at the cap, 1 stranded | 230 s |
| `TRAINED` | 0.0% | 6 at the cap | 343 s |
| `ELITE` | 0.0% | 4 at the cap, 2 stranded | 466 s |
| mixed | 0.0% | 6 at the cap | 324 s |

`TERMINATED` is `BoutRunner`'s turn-cap safety net, not a defeat — so the combat-capable tiers **do
not lose, they fail to converge.** Cost rises monotonically with capability while completion does
not. **Two caveats stop this being over-read**: six seeds is a tiny sample, and seeds 0–11 is
recorded in `CompletionSampler`'s own header as the *pessimistic* corner of the seed space. The
relative ordering is the result; the absolute rates are not a rate — the same build's
`seeds_to_first_win`, drawing randomly, found a completion in 6 seeds on the full gate. **Nothing was
tuned.** The question is whether the AI over-values combat against the objective, and it wants its
own block.

**2. A prediction of mine was wrong and it shaped how I built the probe.** I expected an
all-`MINDLESS` squad might never complete a mission — the taskblock says so too — and I therefore
assumed that row would be the most expensive and would dominate the runtime. It is the **cheapest**
row and the only one that completes. Extraction is a movement objective; I had assumed it required
winning a fight. My first probe printed only a final table on that assumption and was killed by its
own timeout at 37 minutes having emitted nothing. It streams per row now.

**3. Suite cost is not a single number on this build, and my first attempt to report one was
wrong.** I recorded 1373.5 s after Pass E and framed it against taskblock-58's 770 s. **Both halves
of that were bad.** The 770 s predates all six passes here, so the comparison is exactly the stale
baseline taskblock-58's own report was written up for — and the 1373.5 s is not a property of the
build either. Three full-gate runs on the same tree measured **1373.5 s, 1330.6 s and 978.9 s**.

**The swing is `seeds_to_first_win`, and it is the corpus working as designed.** It plays seeds until
one completes, so the suite's cost scales inversely with the draw: the same tree reported *"seeds to
first completion: 6"* on one run and *"1"* on the next. At three units a side each of those seeds is
a much larger bout than the 1v1 it replaced, so the variance the corpus always had is now amplified
by roughly the roster size. `BR49.01` recorded this shape before, when a fixed sample made total
turns swing 657 to 1305 with no code change.

**What this means for anyone measuring:** a single full-gate wall-clock is not a comparable figure
any more, and quoting one is how the next stale baseline gets created. The stable numbers are the
work counters the runner already prints — bouts, turns, plans, candidates — and the per-tier probe's
own per-row timings, which are deterministic over a fixed seed window. If suite cost becomes the
question, that is what to compare, not the clock.

**4. Blocker stacking is refused, not solved.** Pass A closed the corruption by refusing what the
format cannot express, and the author's route to a taller wall is Pass C's Scale drag — which is the
better verb. What is still unreachable is stacking *distinct* things: a crate on a pillar. The
geometry is expressible today (`MapPlacement.offset`), the grid's idea of it is not. Queued.

**The supervisor re-asked this after the block and it is now scoped rather than merely queued** —
84 sites across 28 files, with the breakdown and the design question in `PLAN.md`. See *After the
block* below.


---

# After the block

Fourteen reports across four rounds of review, all against the editor. **Three of them corrected me
rather than the code**, and those are the entries worth reading.

## What was reported, and what it turned out to be

| # | reported | cause |
|---|---|---|
| 1 | Moving an item does not redraw until something else happens | The translate branch called `redraw()` (handles) and never `editor.refresh()` (the board). `_drag_claim` always had. |
| 2 | Scale handles fly off with the smallest movement | `amount_at` is a delta **from the grab**, applied to the **current** value — every motion event re-applied the whole drag. |
| 3 | "PL" takes two clicks to dismiss the parts list | The button's *border* reads `is_showing()` every frame; the *press* flipped `collapsed`, which nothing updates when the bar opens the list. |
| 4 | Terrain should stack | Scoped and **not started** — supervisor's call. |
| 5 | Side placement preview one tile low | The board draws a blocker at the cell's true height; the ghost drew at the target height. |
| 6 | Cutout/culling sphere on editor walls | One bout unit, seated on the board, feeding the shader a porthole. |
| 7 | A stale squad-0 unit 0 in the editor | **The same unit.** |
| 8 | Scale readout sits in the action bar | An anchor taskblock-57 flagged as a starting position; it happened to land on the bar. |
| 9 | Switching tools leaves gizmos attached | Nothing released the subject when a different tool was armed. |
| 10 | Horizontal drags should move the item | Never implemented; and unimplementable until 11 was fixed. |
| 11 | Moving a pillar moves the floor beneath | **The gizmo addressed a cell, not a placement.** |
| 12 | The move gizmo detaches from its part | The same defect as 11. |
| 13 | Floors can be placed in a tile that has one | `PartPicker.hit` has never considered surfaces. |
| 14 | Things placed 0.2 low after the fix for 5 | **I fixed the wrong side of it.** |

## The three corrections

**1. I changed the logic when the ghost was what was wrong (5, then 14).** The supervisor's words:
*"we needed to make the ghost match the logic, not make the logic match the ghost."* `BoardView`
draws a blocker at the cell's **true walkable height**, ignoring the placement's authored height —
which is correct, because `MapPlacement.height` is documented surfaces-only — while the ghost drew
at the target height. So the preview was lying and the placement was right. My first fix changed
`FacePlacement.target_for`, **the shared answer the click uses**, and so moved where things were
authored. Reverted in full; `PlacementGhostModule` now derives the height *and the facing* the board
will actually use. Ghost and board measured identical afterwards.

**2. I refused co-planar floors, which breaks a design rule with a named test (13).** Two floors in
a cell **can** be expressed — `Grid` holds an ordered surface stack and `MapSerializer` adds both —
so refusing is a *legality opinion*, which is exactly the line Pass A drew and stayed behind. It
also broke `test_an_illegal_placement_is_still_placed_and_only_warned_about`, a taskblock-56 F4
acceptance for *warn, never block*. Reverted. **The supervisor then reframed it and the reframing
was the answer**: *"it's not that floors in the same place is a problem, it's that I'm able to place
one there with a click."* `PartPicker.hit` has only ever considered units, blockers and field items —
its own header lists *"unit parts, scatter cover, walls, downed bots, field objects"* and floors are
in none of them — so a click on a tile struck **nothing**, the editor read that as "no face", and the
placement fell back into the cell just clicked. The author was not stacking floors; they were
clicking a floor and hitting empty space.

**3. Pass B's cutout fix covered the wrong half (6, 7).** It hid the units the authored board could
not **seat**. `BoardSwap.swap_board` seats every living unit on the *first free walkable cell*, so
the author's very first floor tile put a bout unit on the board — visible, and cutting the porthole.
Both symptoms were one unit, which is why they came and went together as more was placed, exactly as
reported. The editor now draws **no** bout unit at all: a statement about what the editor is, rather
than a fourth symptom cleared. Recorded against `BR57.01`, whose earlier fix this supersedes.

## Decisions made without asking

**The drag anchor is one entry point, not a convention.** `Gizmo.drag_start_state` snapshots the
subject when a handle is grabbed, and `GizmoModule.begin_drag` is the only way to start a drag — so a
caller cannot begin one without a snapshot and silently get the accumulating behaviour back. Making
it a method rather than two lines at the press site is what stops that being something anyone has to
remember, tests included. **The same defect was in the claim drags with no report against it**; six
motion events at a stationary pointer took a wall from 3.4 to 8.4.

**The toggle fix went in the shared button, not in the parts list.** Every module in the cluster
whose surface can be opened by other means had the same desync, and `is_showing` already exists to be
the one answer to *"is it up"*. It was also reachable from a fresh mount, where the first press closed
an already-closed list and looked like nothing happened.

**A placement moves by `height` if it is a surface and by `offset` otherwise.** Not a workaround —
it is what the two fields mean, and Pass C's `offset` is what made a blocker movable at all. This is
what stops a pillar's arrow moving the floor under it.

**Surfaces are picked opt-in.** `TacticsController` resolves aim through the same `PartPicker.hit`,
and making the ground targetable there is a change to *targeting* rather than a fix to the editor.
Off by default, pinned by a test asserting the aim path still cannot pick a floor.

**Terrain stacking was scoped and not started**, on the supervisor's call. Measured: `grid.blockers`
is read at **84 sites across 28 files**, 41 in production logic. The count is not the obstacle —
most readers need *every* blocker (`RayCaster` marches geometry, `SightSpans` derives occlusion)
while `DamageResolver` and `Detonation` do identity checks needing list semantics. The breakdown is
in `PLAN.md`, along with the design question to answer first: **what distinguishes a blocker from a
field item** once a cell can hold several of either, given `field_items` already stacks and draws and
only lacks blocking.

## Tests that failed, then were corrected

**Two, both fixtures holding assumptions that had stopped being true.**

1. **`test_face_placement.gd` authored a `wall` as `KIND_SURFACE`** — its helper hardcoded the kind.
   Inert until `FacePlacement` began distinguishing a deck from a thing standing on one, at which
   point the wall *was* the ground and a side placement landed on its roof. The test's claim was
   right; its fixture was not.
2. **`test_gizmo_drag_fidelity.gd` read the floor's height** to check a move had happened. Once the
   drag correctly moved the *topmost* placement, the floor stopped changing — which is the fix, not a
   regression.

**And a self-inflicted one worth recording.** A scripted edit meant to revert the co-planar refusal
sliced out five functions from `EditorController` — `placements_at`, `remove_top`, `clear_cell`,
`set_height`, `set_placement_size`. Caught immediately by a parse failure, restored from the commit,
re-applied surgically. **Scripted surgery on a file by text markers is how that happens**; the edit
was a range delete whose end marker sat past four functions I meant to keep.

## Open questions

**1. One test had to be reversed rather than fixed, and it is the block's own.**
`test_layout_review.gd::test_a_unit_the_board_can_seat_is_drawn_again` asserted *"they come back
once the board can seat them, so the fix is not 'hide the units'"* — taskblock-57's intent, and
exactly what the supervisor reported twice as a defect. It now asserts the opposite, paired with a
new test that launching a bout brings them back, so the pair still covers "the fix is not merely
hiding them". Recorded in `SUPERSEDED.md`. **It was caught by the full gate and by nothing else**,
which is the argument for the full gate on a change that touches a shared surface.

**2. `EditorTools` had reached into `GizmoModule`** for the two tool names — a `src/logic/` file
depending on `src/view/`, which is the golden rule this project is built on. Found and fixed while
adding `arms_the_gizmo`; the vocabulary now lives in logic and the module reads it. Worth a look at
whether anything else has drifted the same way.

**3. Horizontal moves snap to whole cells**, which is what was asked for — *"currently they should
snap by cell, but later they may be fully offsetable."* The machinery for the later half already
exists: `MapPlacement.offset` carries a sub-cell displacement and the board draws it. What is missing
is only the decision to let the drag write it.
