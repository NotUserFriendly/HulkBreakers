# BUGS.md — Bug Ledger

**The single place a bug's status lives.** New and resolved, with a rough report time and (for recent
ones) the taskblock in play. Its job: **a resolved bug must have a closure marker here**, so an old
report — still readable in `taskblock_done/`, still describing acceptance criteria — is never
re-derived as open. If you fixed something, mark it RESOLVED here, even if the fix landed as a plain
commit outside the taskblock cadence. That out-of-cadence gap is exactly what let stale reports
recur.

**Convention:** newest at the top of each section. Recent entries get a timecode + taskblock; older
migrated ones get a rough date. `RESOLVED` entries name the fixing commit(s)/taskblock so the closure
is verifiable.

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
scratchpad`). CC stamps its closure marks with that UUID — the short prefix is enough to read at a
glance (e.g. `RESOLVED-PENDING-CONFIRMATION [CC 83fb8082]`). If CC is refreshed it gets a *new* UUID,
so a later session reading an earlier session's `PENDING-CONFIRMATION` sees a **different** stamp than
its own — that's the signal it's *another instance's* unverified claim. It must NOT promote it to
`RESOLVED` on the strength of a prior CC's word, only on the supervisor's. A pending mark whose UUID
isn't your current one is a claim to re-check, not a closure to trust.

**End-of-taskblock digest.** At the end of each taskblock, CC lists every `SUPERVISOR`-sourced bug
it moved to `RESOLVED-PENDING-CONFIRMATION` this block — a "here's what I think I fixed, please
confirm" roll-up — so pending items surface at a natural review point without interrupting mid-work.

---

## ✅ Resolved

### Resource Editor — four layout bugs (stale-report source)  ·  source: `SUPERVISOR`
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

### Waist-line of impacts — the shot-plane Z-discard  ·  source: `SUPERVISOR`
- **Reported:** through mid-2026-07 review passes ("a line of impacts across the waist"; "only seeing
  ~20% of shots"; "no ricochets").
- **Symptom:** projection collapsed `Vector3 → Vector2(x, z)`, dropping the height axis — so vertical
  scatter collapsed to a horizontal band and tracers/ricochets pinned to one height.
- **RESOLVED** in **taskblock 23** (true-3D shot resolution): projection retains height, the dartboard
  scatters in 3D, `resolve_ray` accepts vertical shots, tracers draw the real 3D path. Tagged in
  `docs/CHANGELOG.md`.

### `los.gd` `range`-shadow (v1)  ·  source: `CC`
- **Symptom:** a param named `range` shadowed the builtin, failing at load/call time.
- **RESOLVED** in the v1 foundation work (noted historically in `docs/SUPERSEDED.md`). `gdlint` now
  catches this class faster than the engine does (see `docs/TOOLING.md` gotchas).

### Deflect tracers never drawn  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the resolver produces DEFLECT outcomes (a review bout
  logged 25), but resolution_player.gd references DEFLECT zero times — the bounced secondary ray is
  computed, logged, never drawn."
- **Fix:** `taskblock-26 Pass A1` (commit `7c07445`) — every DEFLECT-outcome impact event now
  carries its own `deflect_end_x/y/height`, drawn as a second, visually distinct tracer segment.
- **RESOLVED** — confirmed by the supervisor.

### Bout maker AI dropdown missing new playstyles  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: tb24/tb25 added playstyles (overwatch-capable set, PSYCHOTIC, TURTLE)
  but the bout setup menu's own AI dropdown was a hardcoded, independently-maintained list.
- **Fix:** `taskblock-26 Pass C1` (commit `67c7ca8`) — `GenerateBoutOverlay.PLAYSTYLES` is now a
  direct reference to `UnitAI.PLAYSTYLES`, not a hardcoded copy.
- **RESOLVED** — confirmed by the supervisor.

### Bout menu jumpy add/duplicate, not truly centered  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: adding/duplicating a roster entry reflows jarringly; the menu reads as
  intended-centered but isn't.
- **Fix:** `taskblock-26 Pass C2` (commit `67c7ca8`) — anchors pinned to 0.5 with
  `GROW_DIRECTION_BOTH` (no baked offset); every row reserves the same `ROW_MIN_HEIGHT`.
- **RESOLVED** — confirmed by the supervisor.

### Inspect header shows only the variant, not unit id/squad  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: the inspect panel showed the bot's variant but not which unit/squad
  this actually was in the current bout — two units built from the same variant read identically.
- **Fix:** `taskblock-26 Pass C3` (commit `67c7ca8`) — the title bar now reads "INSPECT — Unit N
  (Squad M) — <variant>" once a unit is open.
- **RESOLVED** — confirmed by the supervisor.

### Stab's slide-deflect could land back on the shooter's own body  ·  source: `CC`
- **Found:** while re-diagnosing A2 below (see that entry) — `DamageResolver._resolve_slide` (stab's
  own DEFLECT_MODE_SLIDE response) re-searches the WHOLE plane from index 0 with a lateral nudge, but
  hardcoded an EMPTY exclude list on that re-search, unlike every other plane lookup in `resolve_shot`.
  A stab that deflects and slides at point-blank range could therefore land back on the shooter's own
  body (which sits at the ray's own near-zero depth), the one lookup `resolve_shot`'s own first-hop
  exclusion never covered.
- **Fix:** `_resolve_slide` now takes `exclude_parts` and passes it through to its own `_find_next`
  call, the same shooter-parts list `resolve_shot` itself was given.
- **RESOLVED** — proven both ways (fails without the fix, passes with it) by
  `test_damage_resolver_deflect_modes.gd::test_slide_deflect_never_lands_back_on_the_shooters_own_excluded_body`.

---

## ⏳ Resolved — pending supervisor confirmation
*(CC-fixed `SUPERVISOR` bugs awaiting verification. CC writes here, never straight to Resolved;
the supervisor promotes confirmed ones up to Resolved.)*

### Opposing team teleports before the player's own attack lands  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the last blue unit took its turn and the opposing team
  appeared to jump to new positions before that unit's attack animation resolved."
- **Root cause:** `SquadControlOverlay._on_turn_ended` called `advance_ai_turns(battle)` — which
  fast-forwards every AI turn with NO animation at all, a single instant `refresh_unit_views` at its
  own end — BEFORE the human's own turn had even started its own animated `resolution_player.play()`,
  and that `play()` call wasn't even awaited.
- **Fix:** reordered so the human's own turn is fully awaited through its complete animated playback
  before `advance_ai_turns` runs at all.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass B1.
- **2026-07-20:** supervisor could not verify — blocked by a separate, new issue encountered during
  the attempt. **Verification deferred to the next taskblock** (supervisor's own call) rather than
  chased now; still pending either way.

### Muzzle origin inside the shooter's own armor  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the muzzle originates at the shoulder socket's center
  ('the literal shoulder, not *from* the shoulder'), so the ray starts inside the shooter's own
  geometry and can hit its own armor."
- **First attempt (taskblock-26 Pass A2, commit `7c07445`):** `UnitGeometry.muzzle_point` returned
  the weapon's own box CENTER, not its forward emission point — changed to return the box's forward
  tip. **2026-07-20: supervisor reported still present.**
- **Re-diagnosis:** that fix touched a function no real firing action actually consumed for its
  horizontal origin. Every real attack (`AttackAction`/`BurstAction`/`GrindAction`/`SlashAction`/
  `StabAction`) built the shot plane — and therefore the logged/drawn `impact.origin` — from the
  shooter's own bare CELL center (`Vector2(actual.cell.x, actual.cell.y)`), never from
  `shouldered_muzzle_point`'s own (already-correct) result. Real self-hits were already impossible
  either way (every shooter part is excluded by identity on the plane's first lookup), so this was
  purely the visible/logged origin sitting dead center in the shooter's own torso.
- **Second fix:** all five action files now anchor the shot plane on
  `Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE` (the same continuous muzzle position
  `ShotPlane.resolve_ray` already anchors the reticle/overwatch path on), computed from
  `shouldered_muzzle_point` before the plane is built, not after.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — second attempt, proven via
  `test_attack_action.gd::test_impact_origin_comes_from_the_real_muzzle_not_the_bare_cell_center`.
- **2026-07-20:** supervisor reports it looks better, but other currently-active issues (the
  backward-looking bursts, below) obscure a clean read on this one — left pending rather than
  promoted, verification revisited once those are out of the way.
- **taskblock-27 Pass A1 root-caused the obscuring issue** (see the next entry) as sharing this
  exact anchor-mismatch class — `direction` was still cell-anchored while `origin` (this bug's own
  fix) was muzzle-anchored. With both now sharing one anchor, the obscuring issue should be gone,
  clearing the way for this one to get a real read.

### Chaingun bursts fire half-backward  ·  source: `SUPERVISOR`
- **Reported:** 2026-07-20, observed watching a live bout play out — "the most recent two chaingun
  bursts look odd, both look like half the burst is going backward." Logged without a diagnosis at
  the time (`out/combat.log`'s own text doesn't carry per-impact origin/direction data).
- **Root-caused (taskblock-27):** the taskblock-26 A2 fix (above) moved the shot plane's own
  `origin` to the real muzzle position but left `direction` computed cell-to-cell
  (`Vector2(target_cell - actual.cell)`) — origin and direction anchored on DIFFERENT points for the
  same ray. For a target beside the shooter, that mismatch can put the target's own resolved depth
  at a NEGATIVE value relative to the (wrongly-anchored) direction — exactly what reads as the round
  travelling backward when a tracer animates from the muzzle along that direction for `depth` units.
- **Fix:** `direction := Vector2(target_cell) - origin` in all five action files — direction now
  shares `origin`'s own muzzle anchor, so the target's own depth is always the true, non-negative
  distance from the muzzle to it, by construction.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass A1, proven via
  `test_attack_action.gd::test_direction_shares_the_muzzle_anchor_so_a_close_target_never_resolves_behind_the_ray`
  (constructs the exact overshoot geometry: fails under the old cell-anchored direction, passes under
  the fix).

### Shot/deflect pair has no pause between the primary impact and its own deflect  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27: expected shot → (pause) → its deflect → (delay) → next shot/deflect
  pair; actual — a shot and its own deflect fired with zero gap between them, reading as
  simultaneous rather than "hit, then bounce."
- **Root cause:** `ResolutionPlayer._play_impact` (taskblock-26 Pass A1's own deflect-tracer
  addition) called `await _spawn_tracer(from, to)` for the primary segment, then immediately
  `await _spawn_tracer(to, deflect_to, ...)` for the deflect — no wait between them at all.
  `INTER_SHOT_BREAK_MS` only ever separates DISTINCT top-level impact/miss events, never the two
  segments of one DEFLECT event's own pair.
- **Fix:** new `DEFLECT_BEAT_MS` (100ms, same flagged-placeholder posture as `INTER_SHOT_BREAK_MS`)
  — a real timer awaited between the primary segment and its own deflect segment.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass A2, proven via
  `test_resolution_player.gd::test_deflect_tracer_waits_a_beat_after_the_primary_impact` (fails
  without the fix, passes with it).

### Player Step Out: four bugs, one system  ·  source: `SUPERVISOR`
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
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass B, proven via
  `test_tactics_controller_step_out.gd`'s updated/new tests (cell-confirm queues only the free
  out-leg and opens aim; firing completes the free triple; canceling aim undoes the out-leg) and
  `test_step_out_planner.gd::test_the_triple_costs_no_mp_for_either_leg`.

### Extract-tile marker / facing-indicator z-fight  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review), "same class as tb23's floor/indicator z-fighting."
- **First two attempts (taskblock-26 Pass A3, twice):** bumped `FACING_WEDGE_Y` in isolation each
  time — first cleared the two markers named in the report, then (after that failed) cleared
  `OVERWATCH_ARC_HEIGHT` too. Both **reported still present.**
- **Third attempt (taskblock-27 Pass C2):** stopped bumping one marker in isolation and enumerated
  the whole ground-overlay height ladder instead. Found a real, previously unreported co-planar
  pair no prior test had ever checked: `TEAM_MARKER_Y` (0.01) was IDENTICAL to
  `EXTRACTION_TILE_HEIGHT` (0.010) — every unit standing on its own extraction tile (an ordinary
  end-of-turn occurrence) z-fought, independent of the facing wedge entirely. Re-spaced all four
  named overlays as one ordered ladder with real clearance: extraction tile (0.010, unchanged) →
  team marker (0.06) → overwatch arc (0.09) → facing wedge (0.17), documented so a future ground
  overlay takes the next rung rather than picking a value independently.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass C2, proven via
  `test_hit_volume_view.gd::test_team_marker_no_longer_coplanar_with_the_extraction_tile_marker`
  (fails without the fix, passes with it) and the updated
  `test_the_facing_wedge_clears_every_ground_tier_marker_including_the_overwatch_arc` (now also
  checks the team marker, which it never had before).

### Skirmisher (and every other playstyle) squares off through walls, never takes space  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: `_plan_ranged` seeks the preferred standoff distance but never checks
  line of sight — a skirmisher faces off at range through a wall and never advances to gain a real
  line.
- **First fix (taskblock-26 Pass B2, commit `dac1d1b`):** `_engagement_score` gained a dominant
  `NO_LOS_PENALTY`, exempting the unit's own origin cell so `StepOutPlanner`'s move/fire/return
  fallback wasn't starved of its own "didn't reposition" signal.
- **Second fix (CC, re-diagnosed after a 60-real-map sweep found the first fix froze the unit
  outright):** `_pick_engagement_position` now precomputes whether ANY reachable cell has real LOS
  this turn; the self-cell exemption only applies when that's true — with no LOS cell reachable at
  all, plain progress toward `preferred_range` outscores freezing in place.
- **2026-07-20: supervisor reports still unresolved**, and pointed at `out/combat.log` from a live
  bout (6 units, mtime AFTER the second fix landed) as evidence. That log shows every one of the 6
  units, EVERY turn from Turn 2 through at least Turn 17, doing nothing but
  `_face_if_nothing_else_queued`'s bare defensive re-face ("faced ... (manual_first)") followed
  immediately by `turn_end` — the exact same cell, same facing, forever. This is broader than the
  original report (every playstyle routes through `_plan_ranged`, not just SKIRMISHER) and confirms
  the second fix does not cover every case.
- **Root cause of the second failure:** the second fix only rewards a reachable cell for reducing
  raw Chebyshev distance toward `preferred_range`. Once a unit is already AT (or very near) its own
  preferred standoff distance — the common steady state, reached quickly from most spawn layouts —
  every reachable cell scores no better on that axis, REGARDLESS of whether moving
  perpendicular/around a wall would eventually gain real LOS. The fix only helps the narrower "still
  clearly farther than preferred range" case (monotonic distance improvement); it does nothing once
  the unit has already closed to its own preferred band but still lacks a line, which is exactly
  where these 6 units appear to have settled by Turn 2.
- **Third fix (taskblock-27 Pass C1):** when no reachable cell has real LOS, `_engagement_score` now
  scores primarily on `LoS.obstruction_count` (new — opaque cells between a cell and the enemy, the
  same `Grid.line` walk `has_los` already does, just counting instead of early-exiting), weighted to
  dominate `distance_penalty`. This strictly decreases as a unit works around a corner even while
  raw distance plateaus or worsens, unlike the second fix's own "match a number" metric.
- **Honest result, re-measured on the same 60-real-map sweep:** seeds that never reach real LOS by
  the end of the bout dropped from 16/60 to 8/60 (0/60 fully frozen either way, both before and
  after). A genuine, measured improvement — **not a complete fix.** A long corridor requiring a
  unit to temporarily move AWAY from the enemy before a gap appears can still trap this per-turn
  greedy scorer (it only ever compares reachable cells THIS turn, never plans a multi-turn route) —
  closing that would need a real shortest-path-to-nearest-LOS-cell search, out of scope for one
  attempt.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass C1, third attempt, measurably
  better but not guaranteed complete; proven via
  `test_unit_ai_engagement_los.gd::test_obstruction_count_beats_raw_distance_when_nothing_reachable_has_los`
  (fails without the fix, passes with it) and the 60-real-map re-sweep above.

### Spectator combat log word-wraps  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D1a: the spectator's own log label wraps lines; the player view's
  log already doesn't.
- **Fix:** `log_label.autowrap_mode = TextServer.AUTOWRAP_OFF`, the same setting the player-view
  log already carried — a direct port, not a new mechanism.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass D1a.

### Turn indicator for the player-controlled unit  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D2: "no clear indication of whose turn it is" in player view.
- **Fix:** the active unit's own facing wedge AND team marker now recolor to a distinct
  `ACTIVE_TURN_COLOR` (`HitVolumeView.set_active_turn()`), driven by
  `BattleScene._apply_active_turn_highlight()` off `combat_state.current_unit()`. Wired from both
  `load_battle()` (correct from turn one) and `refresh_unit_views()` (stays correct as the turn
  advances, for either overlay — both already call it after every turn). Along the way, found and
  fixed a previously-unnoticed gap: `set_selected()` never actually recolored the facing wedge at
  all, only the team marker — both now go through one shared `_recolor_markers()`.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass D2, proven via
  `test_hit_volume_view.gd`'s new `test_set_active_turn_recolors_both_the_marker_and_the_facing_wedge`/
  `test_set_active_turn_false_reverts_to_the_ordinary_team_color`, and
  `test_battle_scene.gd`'s new `test_load_battle_marks_the_current_units_own_view_as_active`/
  `test_refresh_unit_views_moves_the_active_turn_highlight_as_the_turn_advances` (both fail without
  the `_apply_active_turn_highlight()` wiring, pass with it).

### Actions clickable without enough AP  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D3: the action bar lets a player arm an action the unit can't afford.
- **Fix:** `ActionBar._can_afford()` compares `ActionCatalog.provider_for(unit, def.id).ap_cost`
  against the unit's current AP (the same provider lookup firing itself already resolves through —
  no new legality path). An unaffordable slot dims to the same tier an empty slot uses but keeps
  its initials text (so "can't afford" reads distinctly from "nothing here"), and
  `_on_box_gui_input()` refuses to arm it.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass D3, proven via
  `test_action_bar.gd`'s new affordability tests (fail without the fix, pass with it).

### Camera doesn't reset after aiming  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D4: after aiming, the camera stays in third-person attack framing
  instead of returning to the pre-aim view.
- **Fix:** `CameraRig.start_aiming()` snapshots the current orbit state
  (`_pre_aim_yaw/pitch/zoom/pan_offset`); `stop_aiming()` eases back to it via a newly-shared
  `_ease_to()` helper (factored out of `ease_to_attack_framing()`, so both directions tween through
  the same code).
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass D4, proven via
  `test_camera_rig.gd`'s new pre-aim-restore test (fails without the fix, passes with it).

### Wall tiles inspectable → garbage inspector  ·  source: `SUPERVISOR`
- **Reported:** taskblock-27 D5: clicking a wall tile opens the tile inspector showing a
  seemingly-random tile in the viewport.
- **Root cause:** not the tile lookup — `Grid.blockers` returns null identically for a wall cell
  and bare floor, so that hypothesis didn't hold up under research. The real bug was
  `InspectPanel.open()`'s null-root branch (reached whenever `unit.shell.root == null`, which
  includes "no unit at this tile") leaking whatever `own_world_3d`/isolate-focus state the
  viewport was already in from a PRIOR inspect — a wall click reused a stale live-board render
  slice instead of clearing it.
- **Fix:** the tile-click path in `SpectatorOverlay` now guards on `TerrainType.WALL` before ever
  calling `open_tile()`; `InspectPanel.open()`'s null-root branch additionally resets
  `_preview_viewport.own_world_3d = true` and calls `show_assembly(null, ...)` so a "nothing to
  show" case can never leak the live-board state, regardless of which caller reaches it.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-27 Pass D5, proven via
  `test_spectator_overlay.gd`'s new wall-tile-guard test and `test_inspect_panel.gd`'s new
  null-root-resets-viewport-state test (both fail without the fix, pass with it).

---

## 🔧 Active / Open

### Lighting differs between spectator and player view  ·  source: `SUPERVISOR`
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

### Low framerate while aiming  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review), filed in the taskblock's own scope fence as explicitly
  deferred: "B-tier; investigate separately — likely the inspect field updating every frame; not a
  correctness bug, don't rush a fix into this block."
- **Status:** not investigated. Flagged for the post-tb26 testing/tooling review (pairs with a "what
  does CC do repeatedly" audit) rather than fixed under taskblock-26's own scope.

---

## Notes on scope
- **Design reversals** (a decision that changed shape) go in `docs/SUPERSEDED.md`, not here — that's
  "the design used to be X, now it's Y," not "something was broken."
- **Known-limitations that are deferred by choice** (a stubbed system awaiting its phase) live in
  `docs/PLAN.md`, not here — they aren't bugs, they're unbuilt work.
- This file is only for **things that were broken**: reported defects and their closure.
