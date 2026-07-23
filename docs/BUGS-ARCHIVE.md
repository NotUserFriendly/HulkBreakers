# BUGS — Archive (closed entries)

Closed bug reports, moved out of `docs/BUGS.md` so the live ledger holds only what is still open.
**`docs/BUGS.md` is the working file; this is the history.** An entry lands here only once it is
`Resolved` — supervisor-confirmed for `SUPERVISOR`-sourced bugs, per the provenance gate. Nothing
is derived or generated: an entry is moved once, verbatim, and never edited again.

Full text is preserved for every entry — investigations, dead ends, and hypotheses included, since
those are exactly what a future session needs when a bug turns out not to be as dead as it looked.

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

### BR32.06 — Resolved — Performance drop when orbiting the camera *and* a unit is selected  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). Framerate took a hit specifically when **both** were true:
  camera orbiting **and** a unit selected. Either alone was fine.
- **Resolved (supervisor-confirmed, 2026-07-22):** on re-check the hit is gone — it was incidentally
  knocked out during the BR32.02 cutout/shader troubleshooting (the depth-source rewrite changed the
  per-frame cutout work). Filed for the record; already fixed by the time it was written up. If aiming
  FPS regresses again, it belongs with the standing BR26.02 (low fps while aiming), same path.

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
