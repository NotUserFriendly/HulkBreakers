# BUGS.md — Bug Ledger

**The single place a bug's status lives.** New and resolved, with a rough report time and (for recent

**Status legend:** `Active` = open · `Suspected` = a possible lead, not yet a confirmed/described bug (the reporter refines it into a real status at their review pass) · `Pending Confirmation` = fix complete, supervisor verification pending · `Resolved` = confirmed fixed.
ones) the taskblock in play. Its job: **a resolved bug must have a closure marker here**, so an old
report — still readable in `taskblock_done/`, still describing acceptance criteria — is never
re-derived as open. If you fixed something, mark it RESOLVED here, even if the fix landed as a plain
commit outside the taskblock cadence. That out-of-cadence gap is exactly what let stale reports
recur.

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

### BR26.01 — Resolved — Opposing team teleports before the player's own attack lands  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the last blue unit took its turn and the opposing team
  appeared to jump to new positions before that unit's attack animation resolved."
- **Root cause:** `SquadControlOverlay._on_turn_ended` called `advance_ai_turns(battle)` — which
  fast-forwards every AI turn with NO animation at all, a single instant `refresh_unit_views` at its
  own end — BEFORE the human's own turn had even started its own animated `resolution_player.play()`,
  and that `play()` call wasn't even awaited.
- **Fix:** reordered so the human's own turn is fully awaited through its complete animated playback
  before `advance_ai_turns` runs at all.
- **2026-07-20:** supervisor could not verify — blocked by a separate, new issue encountered during
  the attempt. **Verification deferred to the next taskblock** (supervisor's own call) rather than
  chased now; still pending either way.
- **RESOLVED** 2026-07-21 — supervisor could not reproduce on retry. taskblock-26 Pass B1.
- **2026-07-21, follow-up:** the underlying "AI batch is one synchronous, unanimated block" mechanism
  this bug's own fix left in place resurfaced as a heavy hitch instead of a teleport — see **BR27.09**,
  which now carries the live investigation.

### BR26.02 — RESOLVED-PENDING-CONFIRMATION [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — Low framerate while aiming  ·  source: `SUPERVISOR`
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

### BR27.01 — Active — Player Step Out: four bugs, one system  ·  source: `SUPERVISOR`
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

### BR27.02 — Active — Chaingun bursts fire half-backward (visual only, hits are correct)  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-20, observed watching a live bout play out — "the most recent two chaingun
  bursts look odd, both look like half the burst is going backward."
- **First fix (taskblock-27 Pass A1):** every attack action's shot-plane `direction` was cell-anchored
  while `origin` was muzzle-anchored — two different anchors for the same ray, which could resolve a
  target at negative depth and animate as the round travelling backward. Both now share the muzzle
  anchor. **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082-732a-4a4f-a726-04186087ef69] at the time,
  proven via a constructed overshoot-geometry test.
- **2026-07-20: supervisor reports still visually backward** — but with a key new detail: "those
  backwards shots do seem to be hitting the things they're drawn as hitting." The actual hit
  resolution (which part takes the damage) is correct; only the drawn tracer/animation direction
  still reads as backward. This means the Pass A1 fix (a `ShotPlane`/`AttackAction` geometry fix)
  either isn't the code path driving the visible tracer, or there's a second, separate anchor
  mismatch specifically in the rendering path (`resolution_player.gd`'s own tracer-drawing code, not
  yet audited against this same origin/direction-anchor class of bug). **Reopened — not
  investigated further this pass**, per instruction to just log and wait.
- **2026-07-20 (taskblock-28 Pass C):** not investigated or fixed this pass either — but
  `out/combat.log` now prints every impact/miss event's own real origin/hit geometry (was already in
  `data` since tb22/23; `LogEvent._to_string()` just never rendered it, and `Overwatch._fire`'s own
  separate impact path had no geometry at all until this pass routed it through the shared logger).
  A future session chasing this bug can read the geometry straight from the log text instead of
  re-deriving it or relying on live playback. Still open; still unconfirmed.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** primary tracer
  read/write anchors now match (post first-fix) — no mismatch there. Suspect is the DEFLECT
  bounce-continuation segment: `resolution_player.gd:464-478` draws from the hit point to
  `deflect_end_*`, computed in `shot_resolution.gd:225-232` as `hit_point + reflected_dir *
  void_range`. `reflected_dir`'s sign/normal convention (`damage_resolver.gd:118-131`) has not been
  audited against this bug class — a flipped convention there would draw a visibly backward secondary
  ray for DEFLECT-outcome shots while leaving the real hit correct, matching "half the burst backward,
  hits correct" exactly. **Bonus find (separate, same bug class):** `overwatch.gd:264-265` still
  computes `origin` as a raw cell-center — never migrated to the muzzle-anchor fix `AttackAction`
  received in Pass A1. A second live instance of the exact same anchor-mismatch class, in a different
  code path. Neither finding implemented or tested yet.
- **2026-07-23 (live playtest, `out/combat.log`, units 0/1/2 supervisor-controlled) — a new angle,
  not yet reconciled with the 2026-07-21 suspects above.** Unit 0's 12-round chaingun burst at
  `(6, 19)`, fired from roughly `(4, 17)`: **all 12 of 12 pulls resolve `DEFLECT on wall`**, every one
  clustering around hit point `~(0.3-0.8, 13.7-14.8)` —
  e.g. `DEFLECT on wall [origin (3.95, 17.26)@1.53 -> hit (0.67, 13.80)@1.71]`. That hit point sits in
  the OPPOSITE quadrant from the aimed target: origin-to-target is `+x, +y`; origin-to-hit is
  `-x, -y`. Every pull agrees on roughly the same wrong-direction spot (scatter alone wouldn't do
  that), and — unlike the two-hop chain logged minutes later for unit 2 (`DEFLECT` immediately
  followed by its own `STOP_DEAD` continuation, sharing an origin/hit boundary) — each of these 12
  pulls logs exactly ONE impact event, no continuation segment. That means the anomaly sits in the
  FIRST forward ray-cast (muzzle to first wall) itself, not in the `reflected_dir` bounce-continuation
  segment the 2026-07-21 note suspected (which only governs what happens AFTER the first hit) — a
  candidate for a still-live anchor mismatch in the primary ray itself, distinct from that suspect,
  not yet root-caused. Logged only — not investigated or fixed this pass.
- **2026-07-23 (follow-up, read-only code investigation — no fix attempted): a concrete hypothesis
  for the first-segment anomaly above, arithmetically consistent with the logged numbers.**
  `damage_resolver.gd::resolve_shot` computes each hop's own logged point as
  `origin + dir * region.depth + perp * point.x` (`dir`/`perp` from the outer call's own `direction`,
  never re-derived per hop). Solving that equation backward for the unit-0 example above
  (`origin (3.95, 17.26)`, `dir` normalized toward `(6, 19)` ≈ `(0.76, 0.65)`, `hit (0.67, 13.80)`)
  requires `region.depth ≈ -4.3 to -5.3` — genuinely **negative**, i.e. the resolved region sits
  BEHIND the shooter along this shot's own fire line, not in front of it.
  **Why a negative-depth region could win at all:** `ShotPlane.build` (`shot_plane.gd:45`) sorts the
  whole plane with a bare `a.depth < b.depth` — no floor at zero anywhere — and `_find_next`
  (`damage_resolver.gd:837`) just walks that sorted array and returns the FIRST region whose rect
  overlaps the aim point. Negative-depth regions are a known, INTENTIONAL part of the plane (`docs/09`
  taskblock06 Pass H's own `AimController.window_depth` doc comment: "a body positioned behind the
  shooter along the fire line still gets a Region... so its own frontmost depth can be small or even
  negative") — but that fact was only ever handled defensively on the AIM-WINDOW side
  (`window_depth`'s own `MIN_WINDOW_DEPTH` clamp) and the SHOOTER's-own-body self-exclusion
  (`_first_hit_excluding`/`self_obstruction`, by identity). Neither guard stops a DIFFERENT body's
  region — a wall, say — from sorting first purely because its projected depth happens to be more
  negative than every real, forward obstacle, then winning `_find_next`'s linear scan if the aim
  point's lateral/height coordinates happen to fall inside that region's rect (which a wide/tall wall
  segment's own rect can do regardless of which side of the shooter it's actually on). If real, this
  would be a genuine RESOLUTION bug (which region gets picked), not merely a rendering-direction one —
  which would refine, not just extend, the 2026-07-20 report's own claim that "hit resolution... is
  correct; only the drawn tracer direction is backward" (that may hold for whatever case prompted that
  original report, but doesn't appear to hold for this DEFLECT case). **Not verified against a
  constructed fixture — this is a read-through-the-code hypothesis from one live example's own
  arithmetic, not a proven root cause.** No fix attempted.

### BR27.03 — Active — Other shots appear to resolve before an earlier shot's own deflect finishes  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-20, correcting a taskblock-27 misdiagnosis (see the correction note in
  `taskblock_done/Report-Taskblock27.md`): a shot and its own deflect are SUPPOSED to resolve
  simultaneously (not paused apart, as taskblock-27 Pass A2 assumed) — the real defect is that a
  DIFFERENT, later shot can appear to resolve/animate before an earlier shot's own deflect segment
  has finished.
- **Status:** not yet investigated. taskblock-27 Pass A2's own `DEFLECT_BEAT_MS` fix inserted a
  deliberate pause between a primary hit and its own deflect — per this correction, that pause is
  itself a wrong implementation of the actual intent (simultaneous primary+deflect) and does not
  address this bug at all. Likely candidate: `ResolutionPlayer`'s own inter-event sequencing between
  separate impact events, not the intra-event primary/deflect pairing `DEFLECT_BEAT_MS` targeted.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** confirmed not an
  intra-event bug — each `ResolutionPlayer.play()` call is fully await-serialized internally,
  primary+deflect included. The gap is a missing reentrancy guard: `play()` has no busy-flag, and
  `SpectatorOverlay.step_once()` (`spectator_overlay.gd:249-251`) calls `pause()` (only flips a bool,
  doesn't cancel anything in flight) then immediately awaits `_advance()` — so a Step/Play issued
  right after Pause can start a SECOND concurrent `play()` while an earlier turn's own deflect tracer
  is still animating. **Candidate fix (not yet applied):** add a busy/in-flight guard to
  `ResolutionPlayer.play()`, or have `pause()` actually await the in-flight `_advance()` before
  returning.

### BR27.04 — Active — Lighting differs between spectator and player view  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D1b: spectator and player view are said to light the board
  differently.
- **Investigated, no code fix applied:** `BattleScene._ready()` already builds
  `WorldPalette.world_environment()` and `WorldPalette.directional_light()` exactly once, as
  children of the shared `BattleScene` itself — strictly before either overlay
  (`SquadControlOverlay`/`SpectatorOverlay`) is installed via `set_overlay()`. Neither overlay
  constructs its own lighting anywhere; both render the same lights on the same world. The code
  does not support the premise of a divergence as currently written.
- **Status:** not resolved — needs the supervisor's own visual re-check (a real screenshot
  comparison) rather than a code claim, since no divergent lighting path was found to remove.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** re-confirms the prior
  pass's conclusion — no new code path found. Genuinely needs the supervisor's own visual/screenshot
  re-check, not further code digging.

### BR27.05 — Resolved — Action bar items still selectable without enough AP  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-20 (tb27 review). The tb27 Pass D3 fix (dim/disable unaffordable action-bar
  slots) **did not hold** — slots are still clickable/armable when the unit can't afford them.
- **Root cause (2026-07-21, tb30):** `ActionBar.refresh()`/`_on_box_gui_input()` both compared against
  `tactics.selection.selected_unit.ap` — the raw, un-queued unit. Per docs/09's own "queuing mutates
  nothing," `unit.ap` never drops for an action that's merely queued this turn, only once it resolves
  — so any AP already committed to an earlier queued action (e.g. a move that burned AP once MP ran
  out) was invisible to a LATER slot's own affordability check, which kept comparing against the
  unit's full starting AP.
- **Fix:** both call sites now read `tactics.selection.previewed_unit()` instead — the same source
  `SelectionController.reachable_cells()` already uses for the identical reason (it replays the
  current queue and returns what's actually left).
- **RESOLVED** 2026-07-21 — supervisor confirms: "I just cleared it visually." Commit `1c13ae5`. New
  regression test queues a move that burns AP via 0 MP, confirmed it fails without the fix and passes
  with it (`test_action_bar.gd::test_an_action_already_queued_this_turn_counts_against_a_later_
  affordability_check`). 1861/1861 green.

### BR27.06 — Resolved — Step Out no longer occurs at all  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-20 (tb27 review). After the tb27 Pass B flow restructure (BR27.01), Step Out
  now **doesn't happen at all** for the player — a regression past the original four symptoms.
- **Status:** reopened, and likely *the* blocker that stopped the supervisor verifying BR27.01/BR26.01
  ("blocked by a new, separate bug encountered during the attempt"). The split-flow restructure
  (confirm-cell → free out-leg → aim mode → fire → free return) probably breaks such that no step-out
  path completes. High priority — it gates confirmation of two other pending bugs.
- **2026-07-21 (taskblock-30): could not reproduce through any headless path — logged as a real
  negative result, not a fix.** Three new regression tests, each a strictly more realistic
  reproduction of the reported click sequence than the last, all pass on the SAME covered-corridor
  geometry `test_tactics_controller_step_out.gd` already used:
  1. `test_a_real_mouse_click_on_a_covered_enemy_also_enters_step_out_mode` — a real
     `InputEventMouseButton` through a real camera raycast into `TacticsController._handle_mouse_
     button` (every pre-existing test in the file drove `click_cell()` directly instead — a real,
     previously-uncovered code path, just not the bug).
  2. `test_action_bar.gd::test_clicking_an_affordable_action_still_arms_it` (already existed, already
     green) — a real ActionBar slot click arms `&"shoot"` correctly.
  3. `test_squad_control_overlay.gd::test_the_real_production_wiring_enters_step_out_on_a_covered_
     enemy` — the full real `SquadControlOverlay`/`TacticsController`/`ActionBar`/`CameraRig` wiring
     (`_build_ui`'s own construction, not a bare `TacticsController.new()`), driven by a real
     action-bar click THEN a real raycast-driven board click, end to end.
  - **Every layer of the reported click sequence checks out correctly in isolation and combined.**
    Two live hypotheses left, neither confirmable headlessly: (a) the trigger condition
    (`UnitAI.is_covered_from` + at least one legal `StepOutPlanner` candidate) may simply be too rare
    on REAL `MapGen`-generated maps to ever fire in practice — reading as "never occurs" without being
    a code regression; (b) the supervisor's own repro used a different weapon/geometry/click sequence
    than this fixture reproduces. **Needs either a more specific repro (which map/weapon/exact
    clicks) or a real-map rarity sweep before further guessing is worth the cost** — not chased
    further this cycle, per tb30's "don't loop within a block" instruction. Still open.
- **2026-07-21 (taskblock-30, same-day follow-up): hypothesis (a) disproved, root cause found.** A
  60-seed sweep of real `MapGen` maps driven through full AI-vs-AI bouts (`BoutSetup.build_bout` +
  `BoutRunner`) found ~1850 genuine covered-with-a-legal-candidate encounters across those 60 seeds —
  not rare at all. `MapGen._scatter_cover` never sets `grid.opacity` (only `blockers`), so the
  overwhelming majority of those are also plainly LOS-visible and clickable, not "no LOS at all" edge
  cases. That ruled out (a) and pointed back at the code path itself — same bug class as BR27.05:
  `TacticsController._enter_aim_or_step_out_mode` read `selection.selected_unit` directly. Per
  docs/09's own "queuing mutates nothing," that stays at wherever the shooter started the turn until
  the queue resolves — so a player who moves toward/into cover and THEN arms a shot had cover
  evaluated from the STALE pre-move cell, silently falling through to ordinary aim mode instead of the
  step-out the shooter's real, about-to-be-true position warranted. Every existing test in
  `test_tactics_controller_step_out.gd` armed+clicked from the shooter's own turn-start cell, never
  after a queued move — the exact gap that let this ship unnoticed.
- **Fix:** swapped to `selection.previewed_unit()` — the same source `reachable_cells()` already
  reads for the identical reason.
- **RESOLVED** 2026-07-21 — supervisor confirms: "step-out is occurring." Commit `d42f744`. New
  regression test queues a move from an uncovered cell into the same covered cell every other test in
  the file starts at, then arms+clicks: confirmed it fails without the fix (falls into ordinary aim
  mode) and passes with it. 1862/1862 green.

### BR27.07 — RESOLVED-PENDING-CONFIRMATION [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — Active-turn highlight lands on the wrong unit; change to facing-marker-only  ·  source: `SUPERVISOR`
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

### BR27.08 — RESOLVED-PENDING-CONFIRMATION [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — "Resolve to here" has never worked  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-20 (logged now; long-standing — backburnered since the button's introduction).
  The "Resolve to here" turn-control (resolve queued actions up to a chosen point) has never
  functioned. Logged here now that the ledger exists so it stops being an untracked known-broken.
- **Status:** open, not yet investigated.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** traces clean
  end-to-end now — button (`squad_control_overlay.gd:445-449`) → `QueuePanel._on_resolve_pressed`
  (`queue_panel.gd:104-107`) → `tactics.resolve_to_marker(_marker_index)`
  (`tactics_controller.gd:1006-1041`), which does slice the queue to a checkpoint index and resolve
  through it. Git history shows commit `888a25f` ("Resolve to Here now actually enables") already
  fixed the historical "button never enables" defect, with passing coverage in `test_queue_panel.gd`.
  **This ledger entry looks stale, not live — worth a quick supervisor re-check before spending
  further investigation on it.**
- **2026-07-22 (tb32 Pass D):** re-verified rather than blind-fixed — `resolve_to_marker()` still
  traces clean end-to-end, and `test_tactics_controller_resolve_to.gd::
  test_resolve_to_marker_applies_only_the_prefix_through_the_marker` is a real queue-then-resolve
  test (queues two move legs, resolves to the first marker, asserts the unit's own `.cell` actually
  only advanced one leg) — not a UI-state check that could pass while the real resolve silently
  no-ops. Nothing changed; this looks like it was already fixed by `888a25f` and the ledger simply
  never caught up. Marked pending, not `RESOLVED` outright, per the provenance gate (SUPERVISOR-sourced) —
  needs the supervisor to actually click the button and confirm.
- **2026-07-22 (supervisor correction): still active — the prior "already fixed" call was wrong.**
  `resolve_to_marker()` working correctly when called directly proves the RESOLUTION logic is fine,
  but says nothing about whether a real player can ever get a `_marker_index` set in the first place
  through the actual `QueuePanel` UI — that path was never exercised, in this session or (per
  `test_queue_panel.gd`) apparently ever with a real queue-then-resolve assertion. Re-opening for a
  real investigation of the click-to-select-a-row → `_marker_index` → resolve-button-enabled chain,
  not just the logic `resolve_to_marker()` itself already had coverage for.
- **2026-07-22, later: reproduced live by the supervisor** — "grayed out and unclickable," matching
  the original report exactly.
- **2026-07-22, follow-up investigation — a real, confirmed test-coverage gap found and closed, but
  the reported symptom itself still not reproduced:** every existing test in `test_queue_panel.gd`
  drove the marker via a helper explicitly documented as "the same path a real click does... without
  needing a live viewport" — `tree.get_root().get_child(index).select(...)` followed by manually
  calling `panel._on_item_selected()` directly. That is NOT the same path: it bypasses the `Tree`
  widget's own hit-testing and its `item_selected` signal entirely. **Nothing, ever, had verified that
  a real click on a real row in the real running game actually fires that signal at all** — exactly
  the class of gap that let BR27.06/BR30.02 hide before (a test that re-derives the behavior instead
  of reading the real thing back).
  - First built the naive version of this test against `test_queue_panel.gd`'s own bare fixture
    (`Tree.new()` with no size, added directly with no parent container) — it FAILED. Looked like a
    smoking gun, but turned out to be a fixture artifact, not the real bug: a bare `Tree` with no
    `custom_minimum_size` lays out at a tiny size, and `get_item_area_rect()` reported a row extending
    below the Tree's own visible rect — a click there falls outside `Control.has_point()`'s test and
    never reaches the Tree at all, regardless of any real production bug. Confirmed via a throwaway
    diagnostic (not committed): giving the same bare Tree the real production `custom_minimum_size =
    Vector2(320, 100)` (`squad_control_overlay.gd:397`) made the identical click resolve correctly.
  - Rebuilt the test against the FULL real `BattleScene`/`SquadControlOverlay` construction instead —
    real Tree sizing, real container hierarchy, a real `InputEventMouseButton` pushed through the real
    `Viewport` at the row's own real, laid-out screen rect (`test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_row_enables_resolve_to_here`). **This passes** — a real click on the
    first row of a freshly-queued single move correctly fires `item_selected` and enables the button.
    Also tried clicking the SECOND row of a 2-entry queue (a throwaway diagnostic, not committed,
    since "resolve to here" is presumably most useful mid-queue, not on the first entry) — also
    correctly selects/enables.
  - **So the click-to-enable mechanism itself checks out in every configuration tried so far, and the
    resolve-when-clicked logic already checked out in tb32 Pass D. Both halves work; the reported
    symptom still hasn't been reproduced by CC.** New regression coverage added either way (a real
    gap closes regardless of whether it's THIS bug): `test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_row_enables_resolve_to_here` (real click, full production wiring) and
    `test_queue_panel.gd::test_a_real_click_on_a_queue_row_enables_resolve_to_here` (same real-click
    proof against the bare fixture, given its own proper size this time — documents the fixture
    sizing gotcha inline so it isn't rediscovered blind next time).
  - **Not chased further blind — needs a few specific details to build a matching failing fixture:**
    (a) which overlay — ordinary `SquadControlOverlay`, or `SingleUnitOverlay`? (b) how many actions
    were queued, and which row (first / a later one) was clicked? (c) fresh turn, or after cycling
    through End Turn/Reset Turn at least once first? (d) does the ROW itself visibly highlight/select
    when clicked (proving the click reaches the Tree) while the button alone stays gray — or does
    NOTHING happen at all, row included? That last one matters most: if the row selects but the button
    doesn't, the bug is almost certainly cosmetic/redraw-timing in `_update_resolve_button()`'s effect
    on the real `Button` node — something no headless test can see (the FRAGCOORD/BR32.02 class of
    bug). If the row itself never highlights, the click isn't reaching the Tree at all in the live
    game, which every test above says shouldn't be possible — meaning something about the live render/
    input path differs from headless in a way not yet identified.
- **2026-07-22, supervisor's answers — every remaining code-level hypothesis ruled out:** (1) both
  `SquadControlOverlay` and `SingleUnitOverlay` show the identical symptom. (2) 1, 2, or 3 actions
  queued, moves interspersed with other action types or not — no difference. (3) fresh turn AND after
  cycling End Turn/Reset Turn — both. (4) **"I don't see any color, or opacity change" — nothing
  happens at all, including the row.** ("Grayed out" was also corrected to "alpha'd out" — the
  button's own look, not necessarily relevant to the row question, but the row-highlight answer is the
  load-bearing one.) This rules out queue length, action type, overlay variant, and turn-state as
  variables, and confirms it's the FIRST half (click never reaches Tree selection) rather than the
  second (selection works, only the button's own redraw is stuck) — narrowing but not yet solving it.
  - Tried two more hypotheses this round, both also ruled out by direct test:
    1. **A real mouse hover immediately before the click** (what an actual player does — move onto the
       row, which triggers `_on_tree_gui_input`'s own tooltip-on-hover, THEN click) rather than a cold
       click with no preceding motion event. Building this properly surfaced a real headless-testing
       limitation, not a game bug: `Viewport.get_mouse_position()` — which `_on_tree_gui_input` itself
       reads to position the tooltip (`tooltip_view.show_data(data, tree.get_viewport().
       get_mouse_position())`) — does **not** update from a synthetic `push_input()`-delivered
       `InputEventMouseMotion` the way a real OS cursor would; it read back `(0, 0)` regardless of the
       motion event's own `.position`. Worked around it by calling `tooltip_view.show_data()` directly
       with the row's real screen position instead, forcing the tooltip genuinely visible at (as close
       as achievable to) the real click point, THEN performing the real click. Still enables the
       button correctly — the (already `MOUSE_FILTER_IGNORE`) tooltip doesn't block the click, matching
       BR31.01's own finding for the turn-control buttons.
    2. Confirmed `HulkTheme` has **no override at all** for a `Tree` row's selection style
       (`selected`/`selected_focus`), nor for `Button`'s `disabled` state — both rely entirely on
       Godot's own default theme. Not a confirmed cause (the default selection highlight is normally a
       distinctly-colored fill, not something that should blend into this theme), but flagged as a
       secondary, unverified possibility: if the default highlight ever reads as visually identical to
       unselected in this specific dark theme, that alone could produce "I see no color change" even if
       the click IS registering underneath. Can't be ruled in or out without eyes on the real render.
  - **Genuinely exhausted what headless GUT can check here.** Every code-level variable tried
    (queue/overlay/turn-state/tooltip-overlap/theme-override-absence) either doesn't reproduce it or
    can't be tested without a real window. This now reads like the same class of bug as BR32.02's own
    shader saga — something only visible in a real, rendered, real-input build.
- **2026-07-22, decision: remove and rebuild rather than keep chasing an unreproducible root cause.**
  The `Tree`+marker+global-button mechanism was never conclusively root-caused despite an extensive
  investigation across several taskblocks, and the supervisor's own repeated live reproduction ruled
  out every code-level variable this session could construct — the strongest remaining signal was
  simply that nothing else in this codebase drives something this important through a `Tree`'s own
  click/selection signal, and every plain `Button`-based control in the same general screen region
  (End Turn, Reset Turn, action bar boxes) has never shown this class of problem. Rather than keep
  guessing at a live-only cause with no further lead, removed the whole `Tree`/marker mechanism and
  rebuilt the same capability on primitives with no such history: each queued action is now its own
  row with its own real "Resolve" button (`QueuePanel._entry_row()`), wired directly to
  `tactics.resolve_to_marker(index)` — no marker state, no `Tree`, no separate global button. Follows
  the same "clear every child, rebuild fresh from an array" convention
  `GenerateBoutOverlay._rebuild_team()`/`_entry_row()` already established, rather than inventing a new
  shape. Full design/rationale in `docs/SUPERSEDED.md`.
  - Verified with a real synthetic click (matching this session's own established rigor) against the
    FULL real `BattleScene`/`SquadControlOverlay` construction — `test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_rows_resolve_button_resolves_through_it` — and against a bare
    `QueuePanel` fixture — `test_queue_panel.gd`'s own suite, five tests covering empty-queue/N-rows/
    real-click-resolves-the-right-prefix/refresh-rebuilds-with-fresh-indices.
  - **Caught a real, separate layout bug while building this**, exactly the kind of thing only a real
    click test surfaces: the row's own expanding "what" label had no width bound inside its
    `ScrollContainer` (nothing forced a maximum, since `SIZE_EXPAND_FILL` is only well-defined once
    something bounds the available width), so the whole row — button included — landed hundreds of
    pixels past the right edge of a 1920-wide viewport. Fixed by disabling the `ScrollContainer`'s own
    horizontal scrolling, which makes it clamp its child to its own real width instead.
  - **A second, unrelated gotcha found and fixed in the test fixture itself, not the game:** the
    default headless GUT test viewport is tiny (64×64) — a row built wide enough to hold real text
    lands well outside that by construction, and a real click there is legitimately outside the
    viewport's own bounds, not a bug. Fixed by resizing the test viewport to `1920×1080`, matching the
    existing convention `test_tooltip_view.gd` already established for the identical reason.
  - **Not fixed in place — this is a replacement, not a patch**, precisely because the original bug's
    root cause was never conclusively identified. Marked `RESOLVED-PENDING-CONFIRMATION`, not plain
    `RESOLVED`, per the provenance gate — this still needs the supervisor's own live click to actually
    close it, since headless tests said the OLD mechanism should have worked too.
- **2026-07-22, supervisor review of the rebuild — two refinements, same session:**
  1. **"Resolving to an earlier point should keep the later queued items in the queue."** The prior
     behavior (inherited unchanged from the original `Tree`-based mechanism, itself dating to
     taskblock06/07) discarded EVERYTHING queued past the marker, not just the resolved prefix —
     `resolve_to_marker()`'s own `selection.reset_turn()` call erased the whole remaining queue.
     Replaced with new `SelectionController.keep_queue_suffix(from_index)`, which drops only the
     resolved prefix; the surviving suffix replays unmodified against the just-updated real state —
     safe since every `CombatAction` already re-validates itself against whatever `state` it's handed
     at apply time, never a captured reference (docs/09). A real design reversal, not a bug fix —
     logged in `docs/SUPERSEDED.md`.
  2. **"The coord info can be an on hover event for the MoveAction term... long paths make the readout
     stretch across the display."** New `CombatAction.short_describe()` (defaults to `describe()`
     unchanged for every action type) — `MoveAction` overrides it to drop only the unbounded `path=...`
     term (`"MoveAction(unit=%d)"`, matching every sibling action's own `ClassName(unit=%d, ...)` style
     — supervisor's own follow-up: "I'm okay with it saying MoveAction, it's just a stream of coords
     that look messy," so only the coordinate stream itself was cut, not the class-name format). The
     full `describe()` still surfaces as an extra "Detail" tooltip row whenever it actually differs
     (`TooltipBuilder.for_queue_entry()`) — the coordinate detail is still reachable, just on hover, not
     stretching every row by construction.
- **2026-07-22, supervisor report: "Hovering anywhere in the combat readout gives me the details of
  things behind it."** A real, confirmed bug in the rebuild, same class as the already-fixed action-bar
  case (`test_a_click_on_an_action_bar_box_never_reaches_the_board_underneath`) — a queue row's own
  `MOUSE_FILTER_PASS` correctly fired its own `mouse_entered`/`mouse_exited` (its own tooltip was never
  the problem), but PASS never marks a motion event handled, so it ALSO reached `TacticsController.
  _unhandled_input`'s `update_hover()` — a pure 3D ray-cast against the board at that screen position
  with no awareness of what UI is drawn there — showing whatever unit/tile sat behind the deliberately
  translucent readout panel instead of just the row's own tooltip. Confirmed live via a direct
  `mouse_moved` signal check (fires with PASS, silent with STOP) before touching anything. Fixed the
  same way the action bar was: `QueuePanel._entry_row()`'s own row is now `MOUSE_FILTER_STOP`, not
  PASS — still gets its own `mouse_entered`/`mouse_exited` (confirmed), never lets the same motion reach
  the board. `test_battle_scene_input.gd`'s own structural test (every non-interactive Control must not
  default to STOP) widened to also recognize a real `mouse_entered` connection as genuine interactivity,
  the same way it already recognized a real `gui_input` connection — a Control deliberately wired for
  hover is exactly as intentional as one wired for clicks. **Not fixed here, flagged as a related, not-
  yet-reported instance of the identical bug:** `ApMpPipRow`'s own AP/MP pip containers use the same
  `PASS` + `mouse_entered`/`mouse_exited` shape with no `gui_input` — likely has the same latent leak,
  just not yet reported, possibly because that row rarely sits over visible board content in practice.

### BR27.09 — Active — Major hitch on new-turn or end-turn  ·  source: `SUPERVISOR`
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

### BR30.01 — Resolved — Debug-spawned unit renders no visual model  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, live bout review). "Spawn unit does not create a visual
  model, but the inspect shows it, indicating something all the debug options use is the issue."
- **Root cause:** `BattleScene.unit_views` was only ever populated once, in `load_battle()`'s own build
  loop. `BoutInjector.spawn_unit` adds a unit straight into `combat_state.units` — real data, inspect
  panel reads it fine — but nothing ever constructed a `HitVolumeView` for it.
- **Fix:** new `BattleScene.sync_unit_views()` diffs `combat_state.units` against `unit_views` and
  builds the missing view(s), the exact same construction `load_battle()` runs. Both overlays'
  `_on_debug_panel_applied` call it before `refresh_unit_views()`.
- **RESOLVED** 2026-07-21 — supervisor confirms: "Fixed for spawning units."

### BR30.02 — Active — Debug move_object mutates state but the model never visually moves  ·  source: `SUPERVISOR`
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

### BR30.03 — Resolved — Debug-removed unit never visually looks dead  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, same review as BR30.01/BR30.02): "clicking remove on a
  unit is removing it data side, but not visually."
- **Root cause:** `HitVolumeView.is_downed()` (the one check `refresh()` makes to pick the DOWN pose)
  reads `Unit.resolve_matrix() == null`, never `alive` directly — the same thing a REAL kill leaves
  behind (`DamageResolver.eject_matrix_if_needed` nulls the hosting part's own `hosted_matrix`, drops
  it as a loose `Grid.field_items` entry, THEN calls `kill_unit`). `BoutInjector.remove_unit` only ever
  did the `kill_unit` half — `resolve_matrix()` kept finding the still-docked matrix, so the view never
  changed.
- **Fix (first pass):** `remove_unit` now ejects the hosted matrix the same way first (drops it as a
  real field item at the unit's own cell), then kills as before.
- **Renamed to `kill` (2026-07-21, same-day follow-up):** the supervisor's own next request split debug
  removal into two distinct verbs — "Kill is a new feature, that forces matrix ejection the way you
  designed," separate from a generalized `remove_object` ("fully vanishing it," BR30.02's own report
  covers the move/spawn/remove-object round). This fix's own behavior is unchanged, just renamed
  `BoutInjector.kill` — `remove_object` (new) is debug-only cleanup with no matrix ejection at all.
- **RESOLVED** 2026-07-21 — supervisor confirms: "looks fixed." Commit `c930930` (original fix),
  renamed in `6f42a4f`, 1860/1860 green.

### BR30.04 — Active — Waypoint colors shuffle when arming an attack and targeting a cover item  ·  source: `SUPERVISOR`
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

### BR30.05 — Active — Debug panel: clicks and scroll bleed through to the world board/camera  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-21, live debug-panel use. Two related symptoms: (1) clicking within the debug
  menu itself can also select a world cell (the click reaches the board underneath, not just the
  panel widget); (2) once the verb list's own `ItemList` is scrolled to the bottom, further scroll
  input bleeds through and zooms the world camera instead of stopping at the list's own end.
- **Status:** not yet investigated. Likely candidates: (1) some region within `DebugControlPanel`'s
  own layout still has a plain `Control.MOUSE_FILTER_IGNORE` container gap that isn't actually
  covered by an interactive child, letting a click over that gap fall through to the 3D
  viewport/`_unhandled_input` underneath (the same class of bug `docs/09` taskblock07 Pass B4 already
  fixed once elsewhere); (2) `ItemList`'s own scroll wheel input isn't marked handled once it can't
  scroll further, so the same wheel event continues on to `CameraRig`'s own zoom handler. Both are
  UI-event-consumption gaps in the SAME panel, not two unrelated bugs.

### BR30.07 / BR30.08 — Resolved — Pass D audit: `selected_unit` staleness, same class as BR27.05/BR27.06  ·  source: `CC`
- **Found:** 2026-07-21, taskblock-30 Pass D (a supervisor-authored audit task): "BR27.05 and BR27.06
  were the same bug in two places: view code read `selection.selected_unit` (raw, turn-start state)
  during the TACTICS phase, where — per docs/09's 'queuing mutates nothing' — `.cell`/`.ap` don't
  reflect queued-but-unresolved actions. ... Two instances days apart means this is a pattern, not two
  isolated bugs. Audit the rest." Every suspect read from the addendum's own list was checked (state vs
  identity), and none blind-fixed — each confirmed with a failing-then-passing test first.
- **BR30.07 — `TacticsController._confirm_step_out()` computed the outbound path from the stale
  cell:** `Pathfinder.astar(shooter.cell, firing_cell)` used `selection.selected_unit.cell` directly.
  `MoveAction.is_legal()` requires `path[0] == actual.cell` against wherever the unit's real
  (previewed) position is by validation time — so a move queued before triggering step-out silently
  failed `enqueue()` and fell through to `cancel_step_out()`, with no visible step-out at all. Every
  existing test armed+clicked from the shooter's own turn-start cell — the exact gap that also hid
  BR27.06 itself, in a spot BR27.06's own fix never reached (a different function). **State read,
  confirmed.** Fix: path from the queue's own preview instead, matching
  `_append_step_out_return_leg()`'s already-correct sibling pattern. Verified failing without the fix
  (silent cancel; queue only ever got 1 of the expected 2 entries) and passing with it.
  **RESOLVED** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit `8457ff0`, 1864/1864 green.
- **BR30.08 — `TooltipController.refresh()` showed LOS from the stale cell:** passed the raw
  `selected_unit` into `TileInspection.inspect()`, whose `visible_from_selected` field runs a real LOS
  check from `selected.cell` directly. A move queued toward a cell with different sightlines left the
  tooltip stuck showing visibility from the turn-start position. **State read, confirmed.** Fix:
  `previewed_unit()` instead. Verified failing without the fix and passing with it (an opaque cell
  blocks LOS from the start cell but not the queued destination). **RESOLVED**
  [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit `8457ff0`, 1864/1864 green.
- **Checked, not a bug:** `TacticsController.step_out_exposure()`/`_refresh_overlay()`'s
  `Overwatch.would_trigger_at()`/`all_threatened_cells()` calls also read `selected_unit` directly, but
  tracing `would_trigger_at()`'s own general-case branch shows it always re-resolves the mover by `id`
  and explicitly relocates the CLONE to the candidate cell before checking arc/range/LOS, regardless of
  what the passed reference's own `.cell` says — the stale reference only changes which internal branch
  runs, never the final answer. A direct empirical probe (temporary diagnostic, not committed) confirmed
  no output difference. No entry filed.
- **Confirmed correct as-is, no change needed:** `MoveHooks.new(selected_unit.cell)` (both call sites)
  — these run during REAL `resolve_until()`, where `selected_unit.cell` genuinely IS the live starting
  cell, not a preview concern; `confirm_shot()`'s own `shooter` reference and `_append_step_out_
  return_leg()` (both already use raw `selected_unit` ONLY for `.id`/identity, deferring all real
  geometry to previewed state — the correct split); `ap_mp_pip_row.gd` (already reads `previewed_unit()`
  — pre-existing correct pattern); `weapon_panel.gd` (purely structural shell/part reads — hp, wounds,
  manipulators — no position or queue dependency).

### BR30.10 — Pending Confirmation — Shots resolve straight through walls  ·  source: `SUPERVISOR`
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
  candidate follow-up investigation into AI engagement/target selection (`UnitAI._pick_engagement_
  position`/`_engagement_score`).
- **Verified:** `test_shot_plane.gd::test_a_wall_part_between_shooter_and_target_blocks_the_shot` (a
  wall Part between shooter and target intercepts the shot; the target is still there once the wall is
  excluded) and `test_map_gen.gd::test_exposed_wall_cells_carry_a_blocking_part_interior_walls_do_not`
  (every exposed wall cell across 50 seeds carries the blocker; every fully-interior one doesn't).
  1868/1869 green — the one remaining failure is `test_full_mission.gd` itself, above, a known,
  expected consequence, not chased this pass (supervisor's own call: "consider the full test failed
  for the moment, we have a couple other things to check").
- **RESOLVED-PENDING-CONFIRMATION** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit pending.

### BR30.11 — Pending Confirmation — Burst: shown as affordable without enough AP; step-out silently drops the shot  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-21, two symptoms the supervisor flagged separately, turned out to be one root
  cause: (1) "actions selectable when not enough AP available still," and (2) "step out seems to be
  working with shoot, but not with burst."
- **Root cause:** `ActionBar._can_afford()` (`src/view/action_bar.gd`) compared the unit's AP against
  the providing weapon's plain `provider.ap_cost` for EVERY action id, but `BurstAction` has always
  charged its own, usually-higher `weapon.weapon_def.burst_ap_cost` when authored
  (`BurstAction._ap_cost`, e.g. `data/parts/chaingun.tres`: `ap_cost = 2`, `weapon_def.burst_ap_cost =
  4`). A unit with enough AP for the plain cost but not the real burst cost saw (and could arm) BURST
  as affordable — only to have the actual shot silently rejected at `enqueue()` time
  (`BurstAction.is_legal()` correctly checks the real cost), with no visible error either way.
- **Step-out's own part in this:** proved, not assumed — `_enter_aim_or_step_out_mode`'s entry into
  step-out mode is genuinely action-id-agnostic (a direct test arming `&"burst"` against the same
  covered-corridor fixture `test_tactics_controller_step_out.gd` already used for `&"shoot"` entered
  step-out mode correctly, no fix needed there). What actually "doesn't work" with burst: a shooter
  steps out for free (the outbound leg never costs AP), then the SAME `confirm_shot()` -> `enqueue()`
  gate silently drops the real attack for the reason above — the unit holds the stepped-out position
  with nothing ever firing, reading as "step out doesn't work" when the move itself queued fine.
- **Fix:** `ActionCatalog.ap_cost_for(action_id, provider)` (new) — the one seam: `&"burst"` returns
  `weapon_def.burst_ap_cost` when authored, else falls back to `provider.ap_cost`, same as every other
  action. `ActionBar._can_afford()` and `BurstAction._ap_cost()` (now a one-line delegate) both read
  this instead of duplicating the branch — the "two parallel systems" trap this project's own
  convention warns against.
- **Verified:** `test_action_bar.gd::test_burst_dims_using_its_own_higher_ap_cost_not_the_weapons_
  plain_one` (fails without the fix, passes with it — confirmed via `git stash`) and
  `test_tactics_controller_step_out.gd::test_firing_burst_after_step_out_is_silently_rejected_with_
  insufficient_real_ap` (documents the exact silent-rejection mechanism: queue stays at 1 action, the
  free out-leg, burst never gets added). 1868/1869 green (the one failure is the unrelated,
  already-flagged `test_full_mission.gd`, BR30.10 above).
- **RESOLVED-PENDING-CONFIRMATION** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit pending.

---

### BR31.01 — RESOLVED — Bottom-right turn controls and tooltip popups fight over clicks  ·  source: `SUPERVISOR`
- **Confirmed fixed by the supervisor (2026-07-22).**
- **Reported:** 2026-07-22 (tb31 review), long-standing: "the controls on the bottom right of the
  player view don't block the tooltip popups, making them difficult to click."
- **Symptom (supervisor's words, exact interaction TBC before fixing):** the bottom-right controls
  (`turn_controls_column` — Resolve to Here / End Turn / Reset Turn) and the tooltip popup layer
  (`TooltipController`/`TooltipView`) overlap, and the tooltip's presence makes the controls hard to
  click. Not yet pinned to which layer intercepts which.
- **Candidate mechanism (do not blind-fix — confirm first):** a `mouse_filter`/z-order interaction
  between the tooltip layer and `turn_controls_column`, the same class as Pass A's own
  `TopLeftControls` STOP→IGNORE fix and BR30.05 (debug-panel click bleed-through). Likely the tooltip
  popup sits over the controls with a filter that swallows the click, or the controls' own hover
  raises a tooltip that then covers them. Reproduce and read the real node rects/filters back (docs/10
  standing rule 2) before changing anything.
- **2026-07-22 (tb32 Pass D) — reproduced, root cause is NOT mouse_filter:** a real synthetic click
  (`InputEventMouseButton` pushed through the real `Viewport`, `test_battle_scene_input.gd`, the one
  file that routes input through the actual Control tree rather than `click_cell()`) proves End Turn
  still receives the click even with the tooltip visually positioned directly over it —
  `TooltipView`/its label both already carry `MOUSE_FILTER_IGNORE`. The real bug: nothing ever hides a
  STALE tooltip left over from hovering the 3D board right before the cursor crosses onto a
  turn-control button. `TacticsController`'s own hover tracking (`update_hover()`, which would clear
  it) lives in `_unhandled_input`, which never fires while the cursor sits over a Control with the
  default `MOUSE_FILTER_STOP` (every `Button`) — Godot's GUI input layer consumes the motion event
  first. `QueuePanel`'s tree (`mouse_exited`) and `ApMpPipRow`'s AP/MP containers
  (`mouse_entered`/`mouse_exited`) already needed and got this exact fix for the same reason; the three
  `turn_controls_column` buttons never did. **Fix:** each button's own `mouse_entered` now calls
  `SquadControlOverlay._hide_stale_tooltip()`. Proven both ways in `test_battle_scene_input.gd`: a real
  click reaches End Turn regardless (confirms mouse_filter was never the problem), and a real
  `mouse_entered` on End Turn now hides a tooltip that was previously left stuck open.

### BR31.02 — RESOLVED-PENDING-CONFIRMATION [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — Wall/void generation cascaded through solid rock  ·  source: `SUPERVISOR`
- **Backfilled 2026-07-22** (retroactive ledger pass, CLAUDE.md rule 8 applied historically) —
  reported and fixed live during taskblock-31 itself; `docs/CHANGELOG.md` and
  `taskblock_done/Report-Taskblock31.md` both recorded it at the time, but it never got a `BR` id or
  an entry in this ledger. Filed now so a resolved bug's closure marker exists here too, per this
  file's own stated job.
- **Reported:** 2026-07-21, live play testing of tb31 Pass C's new wall/void model: "walls are
  generating where voids should [be]... there should be a single layer of walls."
- **Root cause:** `MapGen._finalize_walls_and_void()` classified AND mutated each `WALL` cell in the
  same scan pass — converting an exposed cell to `OPEN` made it read as a non-WALL neighbor for
  whatever `WALL` cell got scanned next, so exposure cascaded outward from every real opening through
  however much solid rock the scan order happened to reach. A real ASCII dump (seed 2, 40×30 —
  `BattleScene`'s own defaults) confirmed it: walls many tiles thick, effectively zero `VOID` anywhere
  on the map.
- **Fix:** split into two passes — classify every `WALL` cell's exposure against the grid's own
  untouched layout first, then apply every mutation in a second pass. Re-dumped the same seed: clean
  single-tile wall rings with real void space.
- **Verified:** re-confirmed via the same real ASCII dump technique, not just re-reading the code.
  Commit `9909d73`.

### BR31.03 — RESOLVED-PENDING-CONFIRMATION [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — Wall fading never visibly occluded anything  ·  source: `SUPERVISOR`
- **Backfilled 2026-07-22** (retroactive ledger pass) — same gap as BR31.02 above: reported and fixed
  live during taskblock-31, never given a `BR` id or an entry here until now.
- **Reported:** 2026-07-21, live play testing tb31 Pass C's wall-fade legibility feature: "I can't see
  wall fading doing anything" — then again, after a first fix attempt, "the wall fading is still not
  occurring, is it drawing between the camera and the orbited point, or is it something else?"
- **First root cause, fixed:** the occlusion check was world-space — "is this wall within 1 unit of the
  straight 3D line from camera to the focal unit." The tactical camera sits well above/back from the
  board, so that line spends almost its whole length far above wall height; the check essentially
  never fired for any wall more than a cell or two from the unit, the exact case that matters. Rewrote
  `WallLegibility.occludes()` → `occludes_on_screen()`: project both the wall and the focal unit
  through the real camera (`Camera3D.unproject_position()`), compare 2D screen distance, require the
  wall nearer in depth — the question a player would actually answer by eye, independent of camera
  angle. Commit `662e8d2`.
- **Second root cause, found when the supervisor reported it still wasn't working:** traced the whole
  pipeline end to end through the real production path (real `BattleScene`/`SquadControlOverlay`, real
  click-to-select, real `CameraRig` framing) and confirmed every intermediate value was already correct
  — `focal_unit` wiring, camera ownership, `unproject_position()`/depth math all checked out. The one
  link never directly verified: whether `GeometryInstance3D.transparency` alone renders a visible
  effect against an otherwise-opaque, `SHADING_MODE_PER_PIXEL` (lit) material — it doesn't. Switched to
  real alpha blending (`BaseMaterial3D.TRANSPARENCY_ALPHA` + `albedo_color.a`), the same mechanism
  `show_unit_ghost()` already proves renders correctly in this project, just kept lit (docs/10: real
  geometry stays lit). New `BoardView._set_wall_alpha()`, `WALL_FADE_ALPHA := 0.25`. Commit `dda90d4`.
- **Verified:** confirmed working in player view after the second fix. Moot in practice either way —
  this whole alpha-blend mechanism is itself superseded by tb32 A's per-fragment discard shader
  (`docs/SUPERSEDED.md`).

### BR32.01 — RESOLVED-PENDING-CONFIRMATION [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — Stray wall-cutout hole at a cell with no unit  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-22 (live bout, tb32 review). "A stray culling around cell 2,18, with no unit
  to produce that effect... that is the ONLY culling step I see, it's not showing on the units."
- **Root cause, confirmed by reading the code (no live repro available to me — this session has no
  Xvfb/GPU, so I can't run the actual bout myself):** `BoardView.wall_cutout_units` is a live
  reference to `CombatState.units`, fed unfiltered into the wall-cutout shader
  (`BoardView.update_wall_cutout`) every frame. Two ways a unit can leave the board while STAYING in
  that array at its own stale `.cell` forever: (a) **extraction** (`MissionState.extract_unit()` sets
  `alive = false`/`extracted = true` but never clears `.cell`, and nothing in the view layer ever
  read `.extracted` before this fix — the unit's own `HitVolumeView` doesn't even get hidden,
  a separate, more visible latent issue flagged below); (b) the **debug panel's "remove object" verb**
  on a unit (`BoutInjector.remove_object` → `CombatState.kill_unit` — same `alive = false`, cell
  untouched — plus `BattleScene.remove_unit_view()`, which DOES destroy the `HitVolumeView`,
  tracked in `_removed_unit_ids`). Either way, the cutout shader keeps cutting a hole at that unit's
  last position indefinitely, with nothing visibly there to explain it — exactly the reported
  symptom. ("Not showing on the units" is very likely just describing that no *currently on-board*
  unit happens to be behind a wall from the camera's current angle right now — not itself a bug,
  though unconfirmed without seeing the bout.)
- **Fix:** `update_wall_cutout()` now skips any unit with `.extracted == true`. A new
  `BoardView.exclude_unit_from_occlusion(unit_id)` (cleared on every `build()`, so a fresh battle
  never inherits a stale exclusion) is called from `BattleScene.remove_unit_view()` — the same
  `_removed_unit_ids` moment — and checked alongside `.extracted` in the cutout feed. Pass B's own
  `BattleScene._occluding_friendlies()` (same `wall_cutout_units` list, same class of bug for the
  friendly-fade effect) got the matching `.extracted` filter too, since an extracted friendly's own
  `HitVolumeView` stays live (extraction never calls `remove_unit_view`) and would otherwise visibly
  fade as if still standing there.
- **Separate, more visible latent issue flagged, not yet fixed:** nothing in the view layer reads
  `Unit.extracted` at all outside this fix — an extracted unit's own `HitVolumeView` never gets
  hidden or specially posed, so its body may just keep standing there, fully rendered, indefinitely.
  Worth a supervisor look independent of this ticket.
- **Not yet confirmed which of the two mechanisms (a)/(b) actually produced the (2,18) hole** — both
  are now fixed regardless, but knowing which would confirm the diagnosis. Did a unit get extracted
  or debug-removed near that cell?
- **2026-07-22 (supervisor):** if extraction/debug-removal was the cause, it happened on a PRIOR
  bout, not this one — the stray hole was already present on loading into the current bout. See
  **BR32.03** below — a distinct, not-yet-investigated angle (does something carry over across a
  "New Battle" that shouldn't?), since this fix's own `_excluded_from_occlusion` is cleared on every
  `BoardView.build()` and `wall_cutout_units` is reassigned fresh from the new `CombatState.units` on
  load, so neither of the mechanisms fixed here should be ABLE to survive a bout transition as
  currently understood — worth a real look, just not yet.

### BR32.02 — RESOLVED-PENDING-CONFIRMATION [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — Wall cutout never visibly appears near real units  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-22 (same live-bout review as BR32.01). "I rotated the camera around the
  units, they were still in their original spawn locations, next to walls. No culling observed at
  all."
- **First theory, tried and EMPIRICALLY DISPROVEN:** hypothesized (from Godot's own documentation —
  "FRAGCOORD... use[s] the same coordinate system" as `gl_FragCoord`, bottom-left origin) that
  `FRAGCOORD` and `Camera3D.unproject_position()` (top-left origin) disagreed on Y and needed a flip.
  Added the flip; the supervisor tested live and reported the cutout became visible but **detached
  from any unit, drifting/spiraling independently as the camera orbited** — worse, not fixed. A real
  orbiting-camera test proved the GDScript-side feed (position/depth/radius) tracks the unit
  correctly and stably at every angle, ruling that layer out. Two live, hardcoded-position diagnostic
  builds (a fixed hole at viewport center, then at a corner) settled it empirically: **`FRAGCOORD` is
  actually top-left-origin, Y-down — the SAME convention `unproject_position()` already uses.** No
  flip was ever needed; documentation for a different rendering context/shader type doesn't
  necessarily transfer, and this class of bug is entirely invisible to headless testing (dummy
  rendering never executes a fragment shader) — only live, real rendering could have caught it, and
  did, twice. **The flip has been reverted** (`update_wall_cutout()` feeds `unproject_position()`'s
  own output unchanged).
- **Second theory, tried and confirmed via a sequence of live diagnostic builds (all uncommitted,
  shader-file-only, removed once each landed):**
  1. Unconditional discard whenever `unit_count > 0` (ignoring all per-fragment math) made ALL walls
     vanish, not just ones near units — expected, since every wall shares ONE material/uniform set;
     confirmed the uniform data genuinely reaches the shader (not a wiring bug).
  2. Disabling the depth-compare entirely produced a correctly-positioned, correctly-sized porthole
     at every unit — confirmed the distance/radius/dither math is correct, and narrowed the bug to
     depth-compare specifically.
  3. Flipping the depth-compare direction (`<=` instead of `>=`) was wrong in BOTH directions — ruled
     out a simple sign flip; the depth VALUE itself (`frag_depth = length(VERTEX)`) had to be wrong,
     not just its comparison.
  4. `VERTEX` is documented to already arrive in view space by the time `fragment()` reads it — that
     documentation already failed once this investigation (`FRAGCOORD`'s own origin), and evidently
     doesn't hold here either. Replaced with true view-space depth reconstructed directly from the
     hardware depth buffer (`FRAGCOORD.z` + `INV_PROJECTION_MATRIX`, Godot's own standard recipe) —
     confirmed live: culling from the correct side (wall genuinely between camera and unit) now works
     as expected.
- **Fix:** `wall_cutout.gdshader`'s `fragment()` now computes `frag_depth` via the depth-buffer
  reconstruction above instead of `length(VERTEX)`. No GDScript changes needed — this was entirely a
  shader-side depth source bug.
- **Deferred, not a regression from this fix — logged, not chased further per instruction:** with the
  camera and unit on the SAME side of a wall (nothing should occlude at all), the cutout still fires
  and over-cuts neighboring wall segments, confirmed live via screenshot. See
  `taskblock_done/Report-Taskblock32.md` for the fuller writeup and a candidate cause — likely
  inherent to this shader's own 2D screen-space heuristic (nearer-than-unit + within-screen-radius),
  not a new bug introduced by this fix.
- **Both halves of this investigation (BR32.02's flip revert and this fix) were only possible because
  the supervisor tested live and reported back precisely** — no headless test can exercise a fragment
  shader at all (dummy/headless rendering never executes one), so every claim here was confirmed
  against a real, rendered build, not GUT.

### BR32.03 — Active — Wall cutout carries over across a bout transition; new units get none  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-22. The supervisor noticed BR32.01's own "stray culling, no unit there"
  symptom immediately on loading into the current bout — if extraction/debug-removal was the actual
  cause (BR32.01's own fix), it would have happened on a PRIOR bout, meaning something about that
  stale state survived a "New Battle" transition into this fresh one.
- **Explicitly not investigated yet, by instruction** — do not look into this until the supervisor's
  own review pass. Filed only so it isn't lost.
- **Why this looks surprising against BR32.01's own fix (not a contradiction, just unexplained):**
  `BoardView.wall_cutout_units` is reassigned fresh from the NEW `CombatState.units` on every
  `_on_battle_loaded()`, and `_excluded_from_occlusion` is cleared on every `BoardView.build()` — on
  paper, neither of BR32.01's two mechanisms should be able to survive a bout transition at all. If
  this reproduces again, that gap between "should be impossible" and "was observed" is the actual
  bug.
- **2026-07-22 (supervisor review — confirmed, promoted Suspected→Active):** reproduces. The cutout
  from the *prior* match persists into a new bout — old culling never cleared, and the new bout's own
  units get no cutout at all (the only hole visible is the stale one). So it's not just a leftover: what
  survives the transition also prevents the fresh feed from taking effect.
- **Key diagnostic — clicking "Assume Control" snaps the culls to their proper location.** So the feed
  isn't permanently broken, it's *stale until an event forces a re-read*: whatever Assume-Control does
  (re-selects/re-projects the live units) is exactly the refresh the bout-load path is missing. Same
  feed-timing family as **BR32.04** (cutout jumps to the resolved cell ahead of the move animation) —
  both are "`update_wall_cutout()` reads/refreshes at the wrong moment." The bout-load path (and unit
  spawn) needs to trigger the same re-feed Assume-Control already does.

### BR32.04 — Active — Clicking Resolve snaps the wall-cutout hole to the destination before the move animation catches up  ·  source: `SUPERVISOR`
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

### BR32.05 — Active — Wall cutout cuts walls that aren't between camera and unit (coarse heuristic)  ·  source: `SUPERVISOR`
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

### BR32.06 — Resolved — Performance drop when orbiting the camera *and* a unit is selected  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). Framerate took a hit specifically when **both** were true:
  camera orbiting **and** a unit selected. Either alone was fine.
- **Resolved (supervisor-confirmed, 2026-07-22):** on re-check the hit is gone — it was incidentally
  knocked out during the BR32.02 cutout/shader troubleshooting (the depth-source rewrite changed the
  per-frame cutout work). Filed for the record; already fixed by the time it was written up. If aiming
  FPS regresses again, it belongs with the standing BR26.02 (low fps while aiming), same path.

### BR32.07 — Active — Burst at/through a wall aims, then silently fails (no AP, no queued action)  ·  source: `SUPERVISOR`
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

### BR32.08 — Suspected — Dead or knocked-out shells may have strange cutout behavior  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). Not observed directly — flagged as a likely edge case: a
  dead or knocked-out shell may feed or interact with the wall-cutout oddly (still in
  `CombatState.units`? still fed to the cutout? faded as a friendly? left with a stale cell like
  BR32.01?).
- **Suspected, not confirmed** — logged so it isn't lost; confirm/describe at a review pass. Shares
  the unit-feed edge-case family with BR32.01 (extracted/removed) and BR32.03 (carryover).

### BR32.09 — Active — Spectator: current-unit indicator jumps to the next unit before the active turn resolves  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review, direct note). In spectator, the current-unit indicator
  advances to the next unit before the active unit has finished resolving its entire turn.
- **Likely the spectator-side sibling of BR27.07's ordering bug.** tb32 Pass D fixed the *player*-view
  early-flip by deferring `apply_active_turn_highlight()` until after the resolution animation
  (`SquadControlOverlay._on_turn_ended()`), but the spectator path wasn't touched — its indicator
  still flips ahead of resolution. Apply the same defer-until-animation-finishes fix on the spectator
  overlay's turn-end handler.

### BR32.10 — RESOLVED-PENDING-CONFIRMATION [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — AI gets stuck on opposite sides of U-shaped / concave maps  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review; long-standing — logged now, wasn't in the ledger). On
  U-shaped / concave map geometry, opposing units end up stuck on opposite sides, unable to path
  around to engage.
- **Root is the known AI pathing gap, not a new defect.** `docs/PLAN.md` (Support & combat gaps): the
  AI does single-turn reachability, not a genuine multi-turn shortest-path-to-nearest-LOS search — so
  a concave wall between two units, where no single turn's reachable set reaches the other side, leaves
  the AI with nothing to move toward. Same family as the AI line-of-fire gap. The real fix is the
  multi-turn approach-pathing design in PLAN; this entry tracks the observable symptom against it.
- **Fix (tb33 Pass B):** when no cell reachable this turn has a real shot (`_any_reachable_has_lof`
  false), `_plan_ranged` no longer hands off to the greedy least-bad-reachable-cell scorer at all —
  `LineOfFire.approach_path` Dijkstra-floods (`Pathfinder.nearest_matching`, lazy — the real
  `ShotPlane`-based LOF check only runs on cells as they're popped) to the nearest cell that WOULD
  have a clear shot, capped at weapon range + margin, and queues a move truncated to this turn's own
  MP budget (`Pathfinder.truncate_to_budget`). The same fallback re-fires next turn, walking the rest
  of the path, until a reachable cell genuinely has LOF and the normal engagement scorer takes back
  over. This is what a concave map needs that the tb27 C1 `obstruction_count` fix (above) couldn't
  give it: a real multi-turn path to a target cell, including the step that moves farther from the
  enemy before it curves back in — the move a per-turn distance/obstruction scorer can't make no
  matter how it's weighted.
- **Verified (headless):** `test_unit_ai_lof_fallback.gd` — a concave-pocket fixture where the AI's
  queued move includes a genuine Chebyshev-distance increase before it decreases
  (`test_ai_takes_a_step_that_increases_chebyshev_distance_before_it_decreases`); the fallback reaches
  a real shot and fires within a bounded number of simulated turns
  (`test_the_approach_fallback_eventually_reaches_a_lof_cell_and_fires`); a fully walled-off enemy
  falls through to hold/end-turn instead of freezing or erroring; an open-field engagement never
  enters the fallback at all; same seed/fixture produces the same path (determinism).
- **Not live-verified** — headless-only per the taskblock's own design (no rendering needed: grid +
  `ShotPlane`). Needs the supervisor's own hands-on confirmation on a real U-shaped/concave bout
  before promotion to `RESOLVED`.

---

### BR33.01 — Suspected — Aim-view scroll cycles walls; layer labels read as part names  ·  source: `SUPERVISOR`
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

### BR34.01 — Active — Every penetration/deflection hop replays the full bright hit-flash, not just the first  ·  source: `SUPERVISOR`
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

## Legacy (predates the `BR<taskblock>.<seq>` ID convention; IDs assigned retroactively)
*(Kept in their own trailing block rather than resorted into the main ascending sequence above —
same relative order this ledger has always kept them in, oldest work first. All `Resolved`.)*

### BR26.03 — Resolved — Muzzle origin inside the shooter's own armor  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the muzzle originates at the shoulder socket's center
  ('the literal shoulder, not *from* the shoulder'), so the ray starts inside the shooter's own
  geometry and can hit its own armor."
- **First attempt (taskblock-26 Pass A2):** `UnitGeometry.muzzle_point` returned the weapon's own box
  CENTER, not its forward emission point. **Reported still present.**
- **Second attempt (taskblock-27):** re-diagnosed — the first fix touched a function no real firing
  action actually consumed for its horizontal origin; every real attack built the shot plane from the
  shooter's own bare cell center instead. All five action files now anchor the shot plane on
  `Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE`, the shouldered muzzle position, computed
  before the plane is built.
- **RESOLVED** 2026-07-20 — supervisor confirms shots now consistently originate from outside the
  unit's own armor. taskblock-27 Pass A1 (fixing the chaingun-backward report, above) also removed a
  remaining anchor mismatch between `origin` and `direction` that had been obscuring a clean read on
  this one.

### BR26.04 — Resolved — Extract-tile marker / facing-indicator z-fight  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review), "same class as tb23's floor/indicator z-fighting."
- **First two attempts (taskblock-26 Pass A3, twice):** bumped `FACING_WEDGE_Y` in isolation each
  time. Both **reported still present.**
- **Third attempt (taskblock-27 Pass C2):** stopped bumping one marker in isolation and enumerated
  the whole ground-overlay height ladder instead. Found a real, previously unreported co-planar pair
  no prior test had ever checked: `TEAM_MARKER_Y` (0.01) was IDENTICAL to `EXTRACTION_TILE_HEIGHT`
  (0.010) — every unit standing on its own extraction tile z-fought, independent of the facing wedge
  entirely. Re-spaced all four named overlays as one ordered ladder with real clearance: extraction
  tile (0.010, unchanged) → team marker (0.06) → overwatch arc (0.09) → facing wedge (0.17).
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass C2.

### BR27.10 — Resolved — Spectator combat log word-wraps  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D1a: the spectator's own log label wraps lines; the player view's log
  already doesn't.
- **Fix:** `log_label.autowrap_mode = TextServer.AUTOWRAP_OFF`, the same setting the player-view log
  already carried — a direct port, not a new mechanism.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D1a.

### BR27.11 — Resolved — Inspect-on-hover missing in spectator view  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D1c (tb17-era note): inspect-on-hover should be on the shared control
  layer so both spectator and player view have it. Spectator view had none at all.
- **Fix:** `SpectatorOverlay._unhandled_input()` now routes `InputEventMouseMotion` to a new
  `_update_hover()`, reusing the same `UnitPicker.hit()` ray-pick the click handler already calls —
  whichever unit the cursor is actually over highlights (no "selected unit" gate; spectator view has
  no selection concept), mirroring `SquadControlOverlay._on_highlight_changed()`'s own
  clear-every-other-view behavior.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D1c.

### BR27.12 — Resolved — Wall tiles inspectable → opens the tile inspector  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D5: clicking a wall tile opens the tile inspector.
- **Fix:** `SpectatorOverlay`'s tile-click path now guards on `TerrainType.WALL` before ever calling
  `open_tile()` — a wall click is a real no-op, the same posture a miss off the board already had.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D5. (The garbage-viewport
  symptom this report also showed was a distinct, deeper bug — see the next entry, found and closed
  by CC in the same pass.)

### BR27.13 — Resolved — InspectPanel's null-root branch leaked stale isolate-viewport state ("garbage inspector")  ·  source: `CC`
- **Found:** while root-causing the wall-tile report above. `Grid.blockers` returns null identically
  for a wall cell and bare floor, so the tile lookup itself was never the bug. The real defect:
  `InspectPanel.open()`'s null-root branch (reached whenever `unit.shell.root == null`, which
  includes "no unit/object at this tile") never reset the preview viewport's own
  `own_world_3d`/isolate-focus state — so a "nothing to show" case could render an uncontrolled slice
  of the live board, carried over from whatever a PRIOR inspect had left the viewport in.
- **Fix:** the null-root branch now resets `_preview_viewport.own_world_3d = true` and calls
  `show_assembly(null, ...)`, so a "nothing to show" case can never leak the live-board state
  regardless of which caller reaches it.
- **RESOLVED** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — taskblock-27 Pass D5, proven both ways
  (fails without the fix, passes with it) by `test_inspect_panel.gd`'s new
  null-root-resets-viewport-state test. CC-sourced: found, fixed, and tested entirely by CC in one
  pass, no supervisor confirmation gate applies.

### BR11.01 — Resolved — Resource Editor — four layout bugs (stale-report source)  ·  source: `SUPERVISOR`
- **Reported:** recurring through 2026-07-20 (arrived repeatedly as a `## User Request` to launch
  `run_resource_editor.sh` and screenshot the bugs). Era: taskblock 11 was the active block when
  first reported.
- **Symptoms:** (1) nothing resized/expanded on window resize; (2) no visible column-resize grab
  handles in the Tree header; (3) header bar changed height/width while interacting; (4) 3D preview
  z-fought the ground disc (needed zoom-in + upward offset).
- **RESOLVED** 2026-07-18, ~101 commits before the last stale re-report, in three commits:
  - `713f411` — layout never resized, columns wouldn't drag, preview mis-framed
  - `1bff29b` — garbage edits, silent save loss, header jitter
  - `944d019` — preview: drop the dummy-matrix carrier, add `show_assembly`
- **Verified** both in code and by direct supervisor observation of the corrected tool — so this
  `SUPERVISOR`-sourced bug is legitimately `RESOLVED` (the gate was satisfied: the supervisor
  confirmed it).
- **Why it kept recurring:** the fixes landed as plain bugfix commits *outside* the "Taskblock N Pass
  X" cadence, so the usual "update CHANGELOG on landing" never fired. With no closure marker anywhere
  and the tb11 spec still on disk in `taskblock_done/` (gitignored-but-not-deleted, per repo
  convention), the taskblock-generating instance treated the living docs as authority, found nothing,
  and re-derived "go verify the Resource Editor" as open. **This ledger is the fix for that class.**

### BR22.01 — Resolved — Waist-line of impacts — the shot-plane Z-discard  ·  source: `SUPERVISOR`
- **Reported:** through mid-2026-07 review passes ("a line of impacts across the waist"; "only seeing
  ~20% of shots"; "no ricochets").
- **Symptom:** projection collapsed `Vector3 → Vector2(x, z)`, dropping the height axis — so vertical
  scatter collapsed to a horizontal band and tracers/ricochets pinned to one height.
- **RESOLVED** in **taskblock 23** (true-3D shot resolution): projection retains height, the dartboard
  scatters in 3D, `resolve_ray` accepts vertical shots, tracers draw the real 3D path. Tagged in
  `docs/CHANGELOG.md`.

### BR00.01 — Resolved — `los.gd` `range`-shadow (v1)  ·  source: `CC`
- **Symptom:** a param named `range` shadowed the builtin, failing at load/call time.
- **RESOLVED** in the v1 foundation work (noted historically in `docs/SUPERSEDED.md`). `gdlint` now
  catches this class faster than the engine does (see `docs/TOOLING.md` gotchas).

### BR26.05 — Resolved — Deflect tracers never drawn  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the resolver produces DEFLECT outcomes (a review bout
  logged 25), but resolution_player.gd references DEFLECT zero times — the bounced secondary ray is
  computed, logged, never drawn."
- **Fix:** `taskblock-26 Pass A1` (commit `7c07445`) — every DEFLECT-outcome impact event now
  carries its own `deflect_end_x/y/height`, drawn as a second, visually distinct tracer segment.
- **RESOLVED** — confirmed by the supervisor.

### BR26.06 — Resolved — Bout maker AI dropdown missing new playstyles  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: tb24/tb25 added playstyles (overwatch-capable set, PSYCHOTIC, TURTLE)
  but the bout setup menu's own AI dropdown was a hardcoded, independently-maintained list.
- **Fix:** `taskblock-26 Pass C1` (commit `67c7ca8`) — `GenerateBoutOverlay.PLAYSTYLES` is now a
  direct reference to `UnitAI.PLAYSTYLES`, not a hardcoded copy.
- **RESOLVED** — confirmed by the supervisor.

### BR26.07 — Resolved — Bout menu jumpy add/duplicate, not truly centered  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: adding/duplicating a roster entry reflows jarringly; the menu reads as
  intended-centered but isn't.
- **Fix:** `taskblock-26 Pass C2` (commit `67c7ca8`) — anchors pinned to 0.5 with
  `GROW_DIRECTION_BOTH` (no baked offset); every row reserves the same `ROW_MIN_HEIGHT`.
- **RESOLVED** — confirmed by the supervisor.

### BR26.08 — Resolved — Inspect header shows only the variant, not unit id/squad  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: the inspect panel showed the bot's variant but not which unit/squad
  this actually was in the current bout — two units built from the same variant read identically.
- **Fix:** `taskblock-26 Pass C3` (commit `67c7ca8`) — the title bar now reads "INSPECT — Unit N
  (Squad M) — <variant>" once a unit is open.
- **RESOLVED** — confirmed by the supervisor.

### BR27.14 — Resolved — Stab's slide-deflect could land back on the shooter's own body  ·  source: `CC`
- **Found:** while re-diagnosing A2 above (see that entry) — `DamageResolver._resolve_slide` (stab's
  own DEFLECT_MODE_SLIDE response) re-searches the WHOLE plane from index 0 with a lateral nudge, but
  hardcoded an EMPTY exclude list on that re-search, unlike every other plane lookup in `resolve_shot`.
  A stab that deflects and slides at point-blank range could therefore land back on the shooter's own
  body (which sits at the ray's own near-zero depth), the one lookup `resolve_shot`'s own first-hop
  exclusion never covered.
- **Fix:** `_resolve_slide` now takes `exclude_parts` and passes it through to its own `_find_next`
  call, the same shooter-parts list `resolve_shot` itself was given.
- **RESOLVED** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — proven both ways (fails without the fix,
  passes with it) by
  `test_damage_resolver_deflect_modes.gd::test_slide_deflect_never_lands_back_on_the_shooters_own_excluded_body`.

---

## Notes on scope
- **Design reversals** (a decision that changed shape) go in `docs/SUPERSEDED.md`, not here — that's
  "the design used to be X, now it's Y," not "something was broken."
- **Known-limitations that are deferred by choice** (a stubbed system awaiting its phase) live in
  `docs/PLAN.md`, not here — they aren't bugs, they're unbuilt work.
- This file is only for **things that were broken**: reported defects and their closure.
