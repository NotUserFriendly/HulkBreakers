# SUPERSEDED.md — The Reversal Ledger

**Append-only historical record.** Every design decision that was true once and has since been
overwritten. Its job: keep an old note, comment, or commit that assumes the *former* shape from being
mistaken for current truth. Rarely edited — only appended when something is reversed.

For current state see `CHANGELOG.md`; for forward work see `PLAN.md`.

---

| Was | Now | Changed in |
|---|---|---|
| Slot-keyed `SlotType` / `Part.slot_type` | inverted attachment — parts declare `attaches_to`, sockets declare `socket_type` | early (pre-audit) |
| Exposure table / `exposure_weight` / `_weighted_choice` / `CoverInfo.profile` | continuous projection into the depth-sorted shot plane | early (pre-audit) |
| "robot" / "chassis" / "Frame" vocabulary | "cyborg / bot / shell"; `Frame` → `Shell` | early (pre-audit) |
| `resolve_projectile(plane, point)` — 2D plane lookup | `resolve_ray(muzzle, dir)`; the shot plane demoted to the aiming *window* | tb06 A / tb07 A |
| `cook_off()` + `VOLATILE` as the trigger | `failure_mode = DETONATE`; the tag is descriptive, the mode drives it | tb09 A3 |
| `BREAK` failure mode | deleted — a part leaves the body **only** via a severed joint, never its own failure | tb09 C2 |
| MANGLE detaches children / swaps to a wreckage item | MANGLE **stays attached**, keeps **¼ residual DT**, socket still hittable; a live two-stage state (`is_mangled`) | tb05 → revised tb09 A1 |
| Subtree-drop owned by part destruction | subtree-drop owned **entirely by joints** — lose the tree below a hit only when the *joint* is cut | tb09 C |
| DT is a flat `material.dt` lookup | DT is a **`dt_curve` table** per material, thickness-interpolated | tb09 E |
| `Part.recoil` (dead field) | deleted; recoil is **computed** (`RecoilResolver`, damage↑/barrel↓), widens the dartboard across a burst | tb13 D |
| `Part.damage` / gun-owned damage | damage lives on **`AmmoDef`**; the gun (`WeaponDef`) is a multiplier | tb10-ammo / tb13 A |
| Definitions hardcoded in `.gd` | all moved to **`.tres`** via `DataLibrary` (res:// builtin + user:// override, user wins) | tb10 |
| Cover as a cell scalar (`set_cover_value`) | cover is **placed field-object parts** that block movement and project into the shot plane | tb16 B |
| Bot facing: single face at end of move | **per-tile** facing — face each tile before stepping; interrupted move leaves you facing your travel direction | tb16 A |
| Battle and Bout as separate scenes | **one `BattleScene`**; control is a swappable **overlay** (squad / single-unit / spectator / generate-bout); `bout_view.gd` / `simulate_bout_menu.gd` retired | tb15 |
| `SpectatorOverlay` reused a full `TacticsController`/`TooltipController`/`TooltipView` stack for hover-inspect | replaced by a raycast (`UnitPicker.hit()`) + `InspectPanel` — no `TacticsController` needed for spectator inspect at all (hover-inspect itself had to be re-added separately, BR27.11) | tb17 C1 → tb21 B |
| Spectator camera hard-cuts to each newly-acting unit | removed outright — spectator has full manual camera control (orbit/pan/zoom), no automatic movement by default | tb17 C2 |
| Action ordering: facing is fastest (tb06) | overwatch fast, facing slow — an aimed-and-waiting overwatcher resolves before a reorienting unit; flip to lower-resolves-first | tb18 / tb19 A |
| "Lean" (the step-out mechanic) | renamed **Step Out** — "lean" reserved for a future literal-lean ability | tb19 B |
| `PowerResolver.max_ap_for` (simple power read) | surplus (output − consumers) → AP via a **diminishing `power_to_ap_curve`** | tb20 F → revised tb22 B |
| Extract ends the bout on the first unit out | **squad 0 must get its whole team off**; asymmetric extraction (red: 1-AP action; blue: hold the tile to end-of-next-round); empty enemy squad is not terminal | tb22 A |
| One guessed muzzle-to-impact tracer segment, pinned to a constant height | every shot/ricochet hop draws its own tracer at its real, logged point (tb22 D), fully 3D — no longer pinned to a constant height at all (tb23 D) | tb22 D → revised tb23 D |
| Flat `UISink` combat log (one line per event) | hierarchical fold at **render time only** (`LogFold`/`LogFoldGroup`/`HierarchicalUiSink`) into action-level, expandable summaries — the event stream itself untouched | tb22 F |
| `InventoryPanel` (always-visible left-column tree) as player view's inventory surface | deleted; **`InspectPanel`** is the one inventory surface in player view too, same as spectator | tb22 I |
| `BodyProjector` flattens every part's projection to one height plane (Y forced to 0) | real vertical extent retained — a head projects higher than a waist, a foot lower | tb23 A |
| `ShotPlane.resolve_ray` rejects any non-horizontal shot (`push_error` if `dir.y != 0`) | accepts a true 3D ray; a ricochet's reflected direction branches vertically too | tb23 C |
| Each squad's own spawn cells double as its own extraction tiles (teams never cross) | bout-setup places each side's extraction on the **opposing** side, forcing engagement | tb23 E1 |
| AI and the player's own UI hardcoded `AttackAction` regardless of what a weapon actually provides | firing action derived from the weapon's own `provides_actions` via `ActionCatalog.build_firing_action`, for both | tb24 A |
| Burst-only weapons enforced only as a UI convention (the action bar just never showed the button) | `is_legal` enforces `provides_actions` as a real engine rule | tb24 B |
| Overwatch was assignable but the AI never actually considered/chose it — a stranded mechanic | the AI weighs and can hold overwatch through the same catalog seam the player's own action bar reads | tb24 C |
| Step Out's own two automated legs cost real MP/AP, no discount ("the automation is in ASSEMBLY, not in cost") | both legs are free (`MoveAction.free`) — no MP/AP either direction, for the AI and the player alike | tb27 B2 |
| Every squad defaults to `HUMAN` ("Control All Squads"); `CombatState.controller_for()` falls back to HUMAN for any unset squad | `SquadController.UNASSIGNED` is the zero-default; a bout **hard-errors at construction** if any squad on the board is unassigned; control is set explicitly (`assign_all_to_human`/`assign_rest_to_ai`) — no silent gameplay default | tb31 B |
| Walls as **indestructible** terrain — "terrain is a Part flagged indestructible" (`docs/02`), the BR30.10 wall model (a `WALL`-terrain cell with an indestructible blocker) | a wall is **high-DT destructible cover** — a blocker `Part` on an otherwise-passable `OPEN` tile; negative space is a new `VOID` terrain fill; only the void past a wall is indestructible. (`Pathfinder` now also clears a destroyed blocker, walls and scatter cover alike) | BR30.10 → reversed tb31 C |
| `ActionDef.requires_target: bool` — two targeting shapes (board-target, or not) | `Enums.TargetingMode` (`BOARD`/`NONE`/`PART_PICKER`); the action bar dispatches by mode and overwatch/repair reach the bar directly instead of bolted-on overlay buttons | tb31 D |
| Active unit recolors its facing wedge/team marker to `ACTIVE_TURN_COLOR` (tb27 D2) | facing-marker-assembly **visibility** only — team marker + facing wedge toggle together for the active unit, no recolor at all; presence indicates whose turn it is, not color | BR27.07 → reversed tb32 D |
| Wall occlusion: one focal wall faded at a time via per-object GDScript alpha (`BoardView.WALL_FADE_ALPHA`/`_set_wall_alpha`, tb31 C, BR31.03) | per-fragment dithered `discard` shader cuts a screen-space porthole around **every** unit at once (`wall_cutout.gdshader`); GDScript only feeds uniforms, the shader owns the discard decision | tb31 C → reversed tb32 A |
| Friendly-blocks-aim fade drawn as a separate translucent ghost overlay next to the friendly (`BoardView._friendly_fade_overlay`, tb32 B first version) — left the friendly's own real `HitVolumeView` fully opaque underneath it | fades the friendly's own real body directly (`HitVolumeView.set_occlusion_faded()`), decision owned by `BattleScene._process()` | tb32 B (same-taskblock redesign, after live testing showed the first version unreadable) |
| `AttackAction`/`BurstAction.is_legal()` required a live target `Unit` at `target_cell` | also legal against a shootable non-unit `Part` (`Grid.shootable_part_at`) — cover, walls, downed bots, loose field items; melee actions (`Stab`/`Slash`/`Grind`) unchanged, still require a real Unit | tb32 C |
| Queue panel: a `Tree` widget — click a row to set a stop marker, then press a separate global "Resolve to Here" button gated on that marker (`QueuePanel._marker_index`/`_update_resolve_button()`) | each queued action is its own real `Button`, resolving `tactics.resolve_to_marker(index)` directly on press — no marker state, no `Tree`, no global button (`QueuePanel._entry_row()`) | BR27.08 → rebuilt |
| `resolve_to_marker()` called `selection.reset_turn()` after a partial resolve — discarded the ENTIRE remaining queue, prefix and suffix alike (`docs/10` taskblock06 G1's own original "then start queuing again" design) | `SelectionController.keep_queue_suffix()` drops only the resolved prefix; whatever was queued past the marker survives, replayed against the just-updated real state | BR27.08 (supervisor follow-up) |
| A queued `MoveAction`'s own queue-row text was its full `describe()` — `"MoveAction(unit=%d, path=%s)"`, the path unbounded in length | `CombatAction.short_describe()` (new; defaults to `describe()`) — `MoveAction` overrides it to drop only the `path=...` term (`"MoveAction(unit=%d)"`); the full path only reaches the hover tooltip, as an extra "Detail" row | BR27.08 (supervisor follow-up) |
| **Checkpoint discipline** — five committed-artifact gates (`./checkpoint.sh N`) at foundation phases, each a hard stop for human review (a surviving v2.1 standing rule; `docs/09`) | retired — CC was told early to prefer clean reports over generated artifacts, so the ritual sat unused ~30 blocks; its review job is now done live (supervisor plays/bug-hunts in spectator/reviews docs) + tester-mode. `test_checkpoint_1–4.gd` survive as ordinary regression tests; checkpoint 5 retires with `test_full_mission` | tb31 review → tb32 |
| AI fire gate/engagement scorer's "is this line clear" question read `LoS.has_los` (opacity-only) — correct until tb31 C made walls real cover-`Part`s `ShotPlane` blocks but `LoS` has no reason to agree with; BR30.10's own bout found 81% of impacts landing on a wall as a result | `LineOfFire.has_clear_line_of_fire` (new, `ShotPlane`-based) answers the fire/standoff gate instead; `LoS`/`obstruction_count` stay unchanged and still answer genuinely sight-based questions (`is_covered_from`) | BR30.10 → reversed tb33 A |
| AI stuck on U-shaped/concave maps (BR32.10) when no reachable cell has a shot — the per-turn engagement scorer picked the least-bad reachable cell regardless of whether the far side was ever reachable at all | `LineOfFire.approach_path` Dijkstra-floods to the nearest cell that WOULD have a shot and queues a move toward it, truncated to this turn's MP, re-firing turn over turn until one is reachable | tb33 B |
| `BodyProjector._FACE_NORMALS`/`_FACE_CORNERS_A`/`_FACE_CORNERS_B` — four side faces only (`docs/02`: "top/bottom ignored — shots travel horizontally in this abstraction"), a 2-corner-plus-tilt-widening encoding that can't express a horizontal face's own real footprint | six faces (`+/-X`, `+/-Z`, `+/-Y`), each carrying its own real 4 local corners as `+/-1` multipliers on all three axes (`_FACE_CORNERS`) | tb36 Pass B |
| `_project_box`'s facing/visibility test — purely horizontal (`world_lateral.dot(toward_shooter)`), "shots are still level in this pass" | fully 3D — the face's real world normal (including its vertical component) against the ray's own real 3D direction | tb36 Pass B |
| `ShotPlane.resolve_ray`'s own `vertical_slope` — reconstructs a tilted ray's real height at a candidate's depth (`muzzle.y + vertical_slope * depth`), independently of `build` | `ShotPlane.build` shears every region's own `rect.position.y` onto height relative to the ray's real path, once, at the source (`_shear`) — `resolve_ray` just reads a plane already built that way | tb36 Pass C |
| `Grid.height` — row count, a name that collides with a cell's own real elevation the moment one exists | `Grid.rows` (kept `width`); `Grid.level` (a per-cell integer, default 0) added in the same commit | tb36 Pass D |
| `ShotPlane.build`'s `_shear` step (tb36 Pass C) applied unconditionally whenever `origin.y`/`direction.y` were nonzero — silently correct only because no caller besides `resolve_ray` ever passed real elevation | opt-in via a new `shear: bool` param, only `resolve_ray` sets it — every other caller now passes real muzzle height/direction too (tb37 Pass A) and needs absolute, unsheared region height | tb37 Pass A |
| `DamageResolver._find_next`/`resolve_shot`/`_resolve_slide` assumed a dartboard aim point's own height was always anchored at depth zero | anchored at the aim point's own real depth via a threaded `point_depth` parameter — true for a ricochet's fresh continuation plane by construction (`point_depth` defaults to `0.0` there, unchanged), false for a first hop | tb37 Pass A |
| Every shooter/attacker self-exclusion list built from `Shell.all_parts()` (BR36.01: never covered a socket's own synthetic joint region) | `Shell.all_parts_with_joints()` — a NEW method, deliberately not a change to `all_parts()`/`PartGraph.walk()` themselves (those back `living_parts()`'s hp>0 filter, which a joint handle's own default hp=1 would otherwise silently satisfy forever) | tb37 Pass B |
| `Pathfinder.move_cost(cell)` — a per-DESTINATION cost, level-blind by design (tb36's own acceptance test pinned this) | `move_cost(from, to)` — a real edge cost: ramps ordinary regardless of level delta, climbing capability-gated and capped at 1 level, hopping down uncapped-capability but capped at 2 levels | tb37 Pass C |
| `MapGen.generate` wrote `Grid.level` 0 everywhere (tb36's own deliberate inertness) | authors real elevation — a seeded fraction of rooms raised one level, each connected to ground level by a `RAMP` tile, backstopped by a general stranded-elevation repair pass | tb37 Pass D |
| `Unit.level`'s own doc comment: "nothing else writes it this pass (no vertical movement verb exists yet)" | `MoveAction`/`ClimbAction`/`HopDownAction` all re-sync `level` (and the new `Unit.height`) on every real cell change; `Overwatch.would_trigger_at`'s speculative clone re-syncs both for its hypothetical cell too | tb37 Pass D |
| `Grid.level: Array[int]` / `Unit.level: int` — whole levels plus a ramp's own fixed `+0.5` rest offset, the only non-integer height in the game | `Grid.level: Array[float]` / `Unit.level: float` — genuinely arbitrary elevation; `Pathfinder.MAX_CLIMB_LEVELS`/`MAX_HOP_DOWN_LEVELS` become real height caps and climb cost scales proportionally to rise (`CLIMB_COST * rise / LEVEL_HEIGHT`) instead of a flat per-level charge; `HopDownAction`'s drop-distance check now goes through `Unit.height`/`true_height_for_cell` (ramp-aware) instead of raw levels, matching `ClimbAction`'s own convention | tb37 Pass E follow-up (supervisor) |
| `BoardView`'s ground — one flat `PlaneMesh` for the whole grid, with no per-cell height at all | `_build_terrain`: one flat top quad per cell at that cell's own real height, plus vertical riser quads between differently-elevated orthogonal neighbors — a stepped, XCOM-style terrace (supervisor's own call over a smooth heightmap) | tb37 Pass E follow-up (supervisor) |
| `BoardView._build_grid_lines` — one flat mesh spanning the whole grid at a single world height, tracing the old flat ground plane underneath a raised cell's own terraced floor | per-cell: each cell draws its own complete 4-edge border at its own real height, so a riser boundary gets a line framing each side's own step instead of one line cutting through it | tb37 Pass E follow-up (supervisor) |
| `BoardPicker.cell_at_ray`/`plane_hit_t` (taskblock03 D1) — intersected a single fixed `y == 0` plane unconditionally, never updated when elevation landed | an optional `grid` param resolves against the real terrain via iterative refinement (guess a height, find the crossing, look up that cell's own real height, repeat, capped at 4 passes); `grid` defaults to null so every pre-elevation flat-board caller is unaffected | tb37 Pass E follow-up (supervisor) |
| `Grid.terrain`/`Grid.level` authored directly by `MapGen`, the sole source of truth for a cell's own walkability and height | `MapGen` derives a flyweight `Surface` (`ship_floor`/`ramp` Part + real height + facing) onto every floored cell instead; `terrain`/`level` stay populated (a migration bridge still reads them for any grid that predates real placement) but are no longer where a REAL, `MapGen`-generated map's own answer comes from | tb38 Pass B |
| `UnitGeometry.true_height_for_cell`/`Pathfinder`'s walkability and move-cost gate read `Grid.level`/the terrain enum directly | both read a cell's own placed, `walkable`-tagged `Surface` instead (`GridLegacyBridge.is_legacy` falls back to the old formula only for a grid that never authored any surface at all) | tb38 Pass C |
| Ramp height model (tb37): one terrain-marked tile, a flat `+0.5` level offset — a 45°, one-tile-per-level rise | a real `Ramp` part with a facing, two tiles per full level, `+0.5` per tile, a unit standing on either tile at the `+0.25` midpoint between its own low/high edge (`RampGeometry`) | tb38 Pass C |
| `GridLegacyBridge` — a fallback that let `Pathfinder._base_cost`/`move_cost`/`UnitGeometry.true_height_for_cell` read `Grid.level`/`terrain` directly on a grid that never authored real `Surface`s | deleted outright, along with `tools/legacy_grid_bridge_burndown.gd`; all three readers require real placed surfaces unconditionally, no fallback | tb39 Pass C |
| `Pathfinder._terrain_costs`/`_min_possible_cost`, `CombatState.terrain_costs` — a per-terrain-code cost dictionary only ever consulted inside the now-deleted legacy-bridge branch | retired outright (dead weight, not migrated); `Pathfinder.new(grid, can_climb)` drops the parameter entirely — "wall blocks"/"unfloored is unwalkable" already worked independent of this dict | tb39 Pass C |
| `Enums.TerrainType` (`OPEN`/`WALL`/`SPAWN_A`/`SPAWN_B`/`VOID`/`RAMP`) — one enum conflating physical ground state with game spawn markers | `Enums.SpawnMarker` (`NONE`/`SPAWN_A`/`SPAWN_B`) — spawn markers only; every physical fact (floor, wall, ramp, empty) now lives entirely in placed `Surface`s/`Grid.blockers`, with nothing left to enumerate | tb39 Pass D |
| `Grid.terrain: Array[int]` / `get_terrain`/`set_terrain` | `Grid.spawn_marker: Array[int]` / `get_spawn_marker`/`set_spawn_marker` — same array, renamed to say what it actually holds now that "terrain" no longer means anything physical | tb39 Pass D |
| `Grid.level: Array[float]` / `get_level`/`set_level` | deleted outright, no replacement field — a cell's real elevation is read back through `UnitGeometry.true_height_for_cell`/`Surface.height`, never stored a second time on `Grid` itself | tb39 Pass D |
| "Void" used for both the lore setting (voidhulk) and the physical absence of floor/terrain (`TerrainType.VOID`, "a cell with nothing in it") | "void" is a lore term only; the physical state is "empty" or "unfloored" in code and comments (`MapGenScratch.CellKind.EMPTY`, `AsciiRender.CHAR_EMPTY`, `BoardView`'s `EMPTY_BORDER_COLOR`/`EMPTY_FILL_COLOR`/`_build_empty_indicators`, `TileInspection.PhysicalState.EMPTY`) | tb39 Pass D |
| tb39 Pass D's "void is lore-only" left as a prose/judgement rule — identifiers and comments still spelled the word freely as long as they didn't assert it as the physical-state enum value | grep-strict: `grep -rniE "\bvoid\b" --include=*.gd src test tools \| grep -v -- "-> void"` must return zero lines, enforced by `test_void_vocabulary_guard.gd`. `WorldPalette.VOID` (3D background color) → `BACKDROP`; `MapGen._finalize_walls_and_void` → `_finalize_walls_and_empty`; `ShotResolution`/`ResolutionPlayer`'s miss-tracer cluster (`void_range`, "void ray"/"tracer"/"endpoint" — a distinct concept, how far a *missed* shot's tracer draws) → `miss_range`/"miss ray"/"tracer"/"endpoint"; ordinary-English "void" in comments rewritten | tb40 Pass A |
| `BoutInjector`: "a rejected call is a true no-op (nothing mutated, no log entry, no RNG draw)" — a refused verb wrote NOTHING to the combat log, and ~40 `return false` paths across the injector were silent even to `push_error` | a refused call still mutates nothing and still draws no RNG, but it is never silent: every verb emits a `command` event before it can be refused and a `command_outcome` after, carrying a machine-readable `reason` (`destination_occupied`, `unknown_part_id`, `mid_resolution`, ...). `CommandLog` is the one emitter; `CombatState.try_apply` uses it too | tb41 Pass C |
| `BoutInjector._move_unit`/`_place_cover`/`_clear_cover`/`_spawn_field_item` returned a bare `bool`, and `_attach` a `Part`-or-null — three genuinely different failures collapsing into one null, so no caller could report WHICH | each returns its own refusal reason (`StringName`, `&""` on success; `_attach` returns `{"part", "reason"}`), so the public verb fronting it can name the actual cause | tb41 Pass C |
| Combat-log scroll **hand-off**: "scrolling while hovered scrolls the log, but at the top or bottom of the content it falls through to the camera rather than dead-stopping" (taskblock-41 Pass F's own spec, and the `PLAN.md` item behind it) | **the log absorbs the wheel whenever the cursor is over it, at the ends too** — it is a solid surface for the wheel exactly as it already was for clicks. The supervisor corrected this after using it; the spec's own behaviour is what `BR30.05` already reports as a bug for the debug panel ("further scroll input bleeds through and zooms the world camera instead of stopping at the list's own end"), so implementing it as written reproduced a known defect in a second place. `LogScrollHandoff` and its tests deleted | tb41 Pass F follow-up |
| `MOUSE_FILTER_STOP` assumed sufficient to keep a wheel event away from `CameraRig` (it is sufficient for clicks, which is why left/middle/right always behaved) | **measured false.** A STOP control consumes ordinary clicks but a wheel still reaches `_unhandled_input` unless something actively consumes it — `RichTextLabel` scrolls without consuming. A panel that must block the wheel scrolls it explicitly and calls `set_input_as_handled()`. Verified with a spy at that exact input stage, plus a control case proving the spy sees wheels that miss the panel | tb41 Pass F follow-up |
| docs/09 taskblock-07 Pass B4: "a plain container has no click of its own" — applied to `DebugControlPanel`, which sat at `MOUSE_FILTER_IGNORE` and let clicks fall through to the board (`BR30.05` symptom 1) | the rule is scoped to genuinely INVISIBLE containers (`InspectPanel`'s own root, empty padding), which is what it was written about. A container that draws a real background blocks what lands on it — `BR34.02`'s own resolution, generalised. `DebugControlPanel` is a `PanelContainer` with an opaque `HulkTheme` background and is now `STOP` | BR30.05 fix |
| **"An AI turn's seconds are spent scoring candidate cells"** — carried unmeasured from tb35 through tb42 into tb43's own framing ("attack the candidate count and the work per candidate"), and the reason three passes in a row attacked `_pick_engagement_position` | **measured false.** Per repositioning turn, means over 60 turns: `_any_reachable_has_lof` **271.9ms**, `_pick_engagement_position` **98.3ms**, `_nearest_living_enemy` 15.0ms, `Pathfinder.reachable` 2.5ms. The candidate search is ~25% of a planning turn; the **LOF prefilter scan over the whole reachable set** is ~70%, and it is paid identically by a batch leader and a batch follower, which is why tb43 Pass D's leader/follower split bought 4% instead of an order of magnitude. `tools/bench_ai_planning.gd --profile` is the instrument | tb43 Pass D |
| tb43's own Pass D acceptance: "if a follower isn't dramatically cheaper, the local scan is too wide" | **the diagnosis, not the constant, was wrong.** The scan is radius 1 — at most 9 cells — and narrowing it further cannot help, because what a follower still pays is the shared prologue above. Widening or narrowing `FOLLOWER_SCAN_RADIUS` is not the lever | tb43 Pass D |
| `UnitAI` — the engagement-score planner: a hand-ordered cascade of branches (fire in place → approach fallback → closing fallback → engagement search → step out → overwatch → hold) ranked by seven penalty constants each dominating the one below it | `UtilityPlanner` — one loop scoring every (cell, action) pair and taking the best. Precedence is not written down at all; it emerges from authored weights, so changing what a unit prefers is a `.tres` edit rather than a re-ordering of branches. See the retirement note below for the measured before/after | tb45 Pass E |
| `UnitAI.PLAYSTYLES` and the per-playstyle preferred-range constants (`AGGRESSIVE_PREFERRED_RANGE` 0, `SKIRMISHER` 5, `MARKSMAN` 7) | `AiPlanner.PLAYSTYLES` (the vocabulary outlives the planner — `Matrix.playstyle` authors it and the bout dropdown reads it); the preferred ranges dissolve into `UtilityContext.standoff_for`, which reads the weapon's own authored `effective_range` and falls back to one flagged default. **Retiring the playstyle vocabulary itself is still `PLAN.md`'s, not done here** | tb45 Pass E |
| `UnitAI.is_covered_from` — a shared cover predicate parked inside the planner, read by `StepOutPlanner` and `TacticsController` for the PLAYER's own step-out affordance | `Cover.is_covered_from`, its own file. Three callers outlived the planner they were reaching into; a shared predicate living in a file scheduled for deletion is how a "no hanging references" acceptance turns into a scramble | tb45 Pass E |
| `UnitAI._preferred_firing_action_id`/`_provided_firing_action_id` — burst-over-shoot-over-stab preference living in the planner | `ActionCatalog.preferred_firing_action_id`/`provided_firing_action_id`, beside `provider_for` and `build_firing_action`. It is a question about the WEAPON, not about the plan, and taskblock-45 briefly had two planners that would each have needed a copy | tb45 Pass B |
| taskblock-43 Pass D's follower planner — the batch leader publishes a **destination** and each follower scans the handful of cells around it | the leader publishes an **objective** (advance / hold / withdraw / flank) and it is injected as a consideration input. A follower consumes it for free — one more entry in a dictionary it was already building — where the local scan was never dramatically cheaper (that pass's own unmet acceptance). It also fixes a behavioural problem the destination had: every follower converging on one cell is a queue, not a manoeuvre | tb45 Pass C |
| `AiDecisionLog.emit` — the tb35 branch-name decision log (`&"ai_decision"`, "which branch `plan_turn` took and why, if it held") | deleted with the branches it named. `emit_utility_decision` is the survivor: per candidate, per consideration, the raw input AND the curve output, plus tier, profile, visible set and the margin over second place | tb45 Pass E |
| `WorldView.remembered` readable by every restricted observer regardless of tier | gated on `WorldView.MEMORY_TIERS`. **`MINDLESS` is strictly current-sight-only** and stops knowing an enemy exists the moment line of sight breaks. This overrides taskblock-45 Pass B's own third test bullet, which asked for a `MINDLESS` unit acting on a stale remembered position — the two are mutually exclusive, and the supervisor chose current-sight-only. Chasing a stale sighting is Grunt's behaviour and arrives with `PLAN.md`'s *fill in the tier table* | tb45 Pass B (supervisor) |
| `LineOfFire.approach_path` / `closing_path` — a Dijkstra flood toward the nearest cell with a real line of fire, plus an A* fallback toward the enemy, both invoked as an explicit BRANCH when no reachable cell had a shot (tb33 Pass B, tb35 Pass B) | deleted, with their tests and the `APPROACH_MARGIN`/`APPROACH_DEFAULT_RADIUS` constants. Their only caller was the engagement-score planner, so taskblock-45 left them compiling with nothing calling them and a doc comment describing a branch that no longer ran. **What replaces them is not a branch at all**: `UtilityContext._closes_distance` reads PATH distance from one flood rooted at the target, so a cell behind a wall is correctly further than one spatially nearer, and working around concave geometry falls out of ordinary scoring. `Pathfinder.reachable_costs` exposes the cost map `reachable()` always built and discarded | tb46 Pass C |
| `AiPlanner.PLAYSTYLES` and the whole playstyle vocabulary — `AGGRESSIVE` / `COVER_SEEKER` / `SKIRMISHER` / `MARKSMAN` / `PSYCHOTIC` / `TURTLE`, carried on `Matrix.playstyle` and `BoutRosterEntry.playstyle`, translated to a profile id by `AiPlanner.profile_id_for` | **deleted, including the bridge.** A bout names a `UtilityProfile` id directly (`Matrix.ai_profile`, `BoutRosterEntry.ai_profile`). The vocabulary mixed three unrelated axes into one word — a temperament, a role, and a preferred range — so it could not express "cautious but close-quarters" without a seventh name that would have mixed them again; standoff is now scored against the unit's own weapon range and cover-seeking is a weight. **Nothing replaces the list in code**: the `.tres` files under `res://data/utility_profiles/` are the list, and the bout maker's `[AI ▾]` menu reads `DataLibrary.utility_profiles_pool()`, so a new profile is a file and no code edit. The hardcoded list is exactly what let six playstyles quietly select between two profiles, five of them landing on the same one | tb46 Pass E |
| The bout maker's default roster paired each weapon with a range-matched playstyle — MARKSMAN on the sniper rifle, SKIRMISHER on the chaingun, AGGRESSIVE on the shotgun | paired by **temperament** (`cautious` / `defensive` / `aggressive`), because the profile no longer carries a preferred range for a weapon to be matched against. The rationale changed, not just the values — pairing by weapon would now be pairing on a property that does not exist | tb46 Pass E |
| `docs/11`'s tier table read as a specification of four built rows | **four rows specified, most of them built, and one column of one row unreachable.** `item` / `call help` / `bait` / `ambush` have no executor and `call help` has no mechanism at all, so they are `PLAN.md` items rather than authoring. More importantly `Unit.intelligence_tier` defaults to `TRAINED` and **nothing authors it** — every completion rate this project has ever measured is an all-Trained rate, and the Mindless, Grunt and Elite rows including the whole Elite lookahead are reachable from tests only | tb46 Pass E |
| `tools/profile_suite.gd` as a second entry point beside `gut_cmdln.gd` — the only one that collected work counts, and the only one that did **not** fail the build (it called `quit(0)` unconditionally after writing its JSON) | `tools/run_suite.gd`, the single runner: it collects the counts AND propagates the exit code. Artifacts became opt-in via `WRITE_PROFILE`, since they are committed and rewriting them every run churned the tree | tb48 Pass A2 |
| `WatchedRunOverlay`, a fifth `SpectatorOverlay` subclass (tb47 Pass D) | `WatchedRunPanel`, a `VBoxContainer` hosted by whichever overlay is up — the shape `CombatLogPanel` has always had, and the reason it survived every overlay argument untouched. Subclassing an overlay to reuse its toolbar is how the hierarchy `PLAN.md` wants dissolved got five members | tb48 Pass B1 |
| `SuiteRun`'s log path keyed on a `static` per-instance counter | keyed on the **process id** as well. The counter restarts at 0 in every process, and the suite contains tests that launch suites — so a nested `SuiteRun` truncated the file the game's panel was tailing. The panel then read the nested run's verdict as its own: a forced fast gate reported "PASSED — 20 passing, 0 failing", which is `test_grid.gd`'s count | tb48 Pass B2 |
| The work budget gating only AI work (bouts, turns, floods) | `ui_builds` joins them — the first gated counter that is not AI work. `test_spectator_overlay.gd` costs 32.5 s with **zero bouts**, so the suite's most expensive non-bout file was invisible to the thing meant to notice files getting expensive. Counted at `HulkTheme.build()`, which every overlay's `_build_ui` calls and nothing in `src/logic/` does | tb48 Pass D |
| taskblock-48's own guess that `test_ai_batch_yield.gd`'s 18.4 s-per-bout was the `PlanPacer`'s frame yields | **measured false.** Same seed, tight 18 485 ms against paced 19 660 ms, 54 turns either way, 344 yields — the pacer is 6%, about 3.4 ms a yield. The cost is bout LENGTH: 54 turns against the completion sampler's mean of ~13 under the same AI, at roughly 340 ms a turn either way. Nothing was cut, because nothing about it is incidental | tb48 Pass D |
| `CompletionSampler` naming `&"AGGRESSIVE"` as the profile its bouts fight under | `&"aggressive"`, a `UtilityProfile` that exists. taskblock-46 Pass E retired the playstyle vocabulary and missed this one call site; an unknown profile id does not throw, it falls back to unweighted scoring, so **every completion rate measured between those two blocks was measured with no profile weights applied** — 56% unweighted against 72% weighted, mean turns 26.8 against 13.5 | tb47 Pass D |
| `CompletionSampler.SAMPLE_SEEDS = 20`, sized so an in-gate escalation was rare | **8**, re-derived rather than adjusted. taskblock-46 sized 20 when a dip silently added ~330 s to a gate someone was waiting on; the escalation is a manual command now, so a dip costs a person deciding to run one and the gate gets to be cheap instead. n=8 asks for an escalation about one run in thirteen at 98 s, against 244 s at n=20 | tb47 Pass C |
| `test_tb38_flat_bout_guard.gd` as an AI-vs-AI bout | a scripted action queue through the same `resolve_until`. Four re-pins in two taskblocks were all deliberate AI changes, none of them findings the guard could report; it now guards movement, per-tile facing, AP accounting, turn structure and the log's shape, and no longer guards what the AI decides — which a hash never reported usefully | tb46 Pass E |
| **`ShotPlane` as the shot RESOLVER** — every candidate on the board projected into one depth-sorted 2D silhouette, a shot resolved by point-in-rect against it | **`RayChain`** marches a real ray from the muzzle through the aimed point. **Built, tested and approved, but the default flag is NOT yet flipped** — flipping it red-lights 14 tests (see `CombatState.shot_resolver`), so the plane still resolves shots today. The plane keeps its **aiming** job (centre mass, aim layers, self-obstruction, AI line-of-fire) and is neither deleted nor retired. Measured before adopting: seam 56/200 → 0/200 empty; over 216 seeded shots **zero** cases where the plane hit and the ray missed against 64 the other way; reported hit points lying on the surface they claim to strike 100/152 → 216/216; release build 6 715 → 2 021 usec per shot and 148 829 → ~24 256 usec per twelve-round burst | tb52 A-F |
| A scattered round modelled as a ray **parallel** to the shooter-to-target line, displaced sideways by the whole dartboard offset (`_find_next` tests every region at a constant lateral) | the round **diverges from the muzzle**: A is the gun, B is the aimed point, and the shot is the line between them. The parallel model is what put a wide-offset flight — muzzle included — outside the building, which is the real cause of `BR34.05`'s wide-offset half and of `PLAN.md`'s *Wide scatter passing through a wall seam*; **the recorded "adjacent wall rects do not tile edge-to-edge" cause is not measurable** (0/3690 empties in a room that holds every offset) | tb52 A |
| The angle of incidence approximated from a projected `Region` (an axis-aligned box of projected corners; the struck face's real orientation does not survive projection) | the **real struck-face normal**, from the slab test that found the hit (`UnitPicker.ray_box_hit`) — `docs/03`'s deflect/penetrate/stop maths has always been written against a real surface angle and finally gets one | tb52 B |
| `grid.surfaces` in no resolver at all — `ShotPlane` looped units and blockers, `PartPicker` looped units, blockers and field items, and floors were in neither | **floors are ordinary geometry**: `ship_floor` and `ramp` carry an authored `volume` whose top face sits at the surface height, and the march covers units, joints, blockers, field items and surfaces. This is `BR34.05`'s "or the floor" half, which previously had nothing to resolve against | tb52 D |
| `Part.is_destructible` declared, set on `ship_floor`/`ramp`, and **read by no logic anywhere** | the flag is enforced in `DamageResolver.apply_damage_to_part` — an indestructible part stops the round but never reaches zero. Dead until floors became shootable, at which point a 1-hp deck plate would have been destroyed by the first round to strike it | tb52 D |
| The aim preview resolving through its own `ShotPlane.resolve_ray` — a second plane built and walked purely to answer "what is under the reticle" | `AimController._resolve_hit` follows `CombatState.shot_resolver`, so the preview and the shot go through **one** query. `docs/08`'s pillar ("the tooltip and the damage come from the same call") was previously true only by two implementations agreeing | tb52 E |

---

## The engagement-score planner, retired (tb45 Pass E)

**What it was.** `src/logic/ai/unit_ai.gd`, 1369 lines at the end, the only decision-maker for a
non-human unit's turn from taskblock-14 onward. It decided a turn by walking a fixed cascade of
branches and picked a cell with `_engagement_score`, an additive score built from seven penalty
constants — `NO_LOF_PENALTY` 2000, `OBSTRUCTION_PENALTY_WEIGHT` 1000, `ALLY_BLOCKED_PENALTY` 1000,
`SUPPRESSION_PENALTY` 25, `MIN_RANGE_PENALTY` 20, `OPPORTUNITY_ATTACK_PENALTY` 15,
`COVER_SCORE_BONUS` 10 — each deliberately sized to dominate the one below it.

**Why it was replaced rather than tuned.** That total ordering *was* the design, and every new
consideration had to be inserted at the right height in it. The file was raised past the linter's
`max-file-lines` cap **eight times**, every one justified by "part two replaces this file". The
deeper cost was structural: answering "can I shoot from here" per candidate cell meant a real
`ShotPlane` build per candidate, which taskblock-43 measured at ~70% of a planning turn.

**Measured before/after**, both planners over the same 24 seeds from one standalone probe, the old
one run from a worktree at `107af1e` (2026-07-28):

| | old | new |
|---|---|---|
| seeds 0–11 | 9/12 (75.0%) | 5/12 (41.7%) |
| seeds 12–23 | 12/12 (100%) | 8/12 (66.7%) |
| **combined** | **21/24 (87.5%)** | **13/24 (54.2%)** |
| mean turns to complete | 23.6 | **10.6** |
| per-unit plan cost, mission bout | 139.90 ms | **86.51 ms** |
| per-unit plan cost, 3v3 combat bout | 485.16 ms | **131.25 ms** |
| `ShotPlane` builds per turn | 29.1 | **0.0** |

**The completion regression is real and was landed knowingly, but it is smaller than the figure that
decided it.** The block was landed on a mid-change reading of 37.5%; re-measured after the final
fixes it is 54.2%, and `MIN_COMPLETION_RATE` came back from 0.25 to 0.35. The dominant failure is
`TERMINATED` — mostly **not losing fights, failing to finish** — and seeds 1, 2 and 6 fail under both
planners, so three of the eleven failures predate this block. Ruled out as causes: the information
restriction (identical 33.3% unrestricted) and the candidate-set cull (no change). CC recommended
against landing and against moving the floor; the supervisor decided otherwise, and the objection is
recorded in `test_full_mission.gd` beside the constant.

**`ShotPlane` builds per turn falling to exactly zero is the structural claim**, not a speed
tweak: line-of-fire is now a bit test against one `VisibilityField` built per target per turn, and
the canonical resolver is consulted only when an action is actually enqueued.

---

## Ordering the LOF prefilter scan, superseded by inverting the query

**Raised** taskblock-43 (as `PLAN.md` NEXT item 2, from the block's own profiling).
**Superseded** before implementation, by AI v2 part one.

taskblock-43 measured `UnitAI._any_reachable_has_lof` at **271.9ms** per repositioning turn against
`_pick_engagement_position`'s **98.3ms**, and proposed sorting the scan nearest-target-first so its
early-return fires sooner. Exact, cheap, and correct as far as it went — but the same block's branch
census found **19 of 60 turns end with no reachable cell having a line at all**, and ordering does
nothing for those: they must still scan everything to prove the negative. That half was written up as
"real work, not a follow-up."

Inverting the query answers both halves at once. One shadowcast from the target produces a visibility
field; `reachable & vis[target] == 0` settles the negative case in a word operation, so the case that
ordering could not help stops existing rather than being reordered. The prefilter contract (never
report "no line" where one exists, `ShotPlane` stays final) means the field never has to be exact to
be sound.

Not a reversal of anything built — the ordering change was never implemented. Recorded because the
reasoning that produced it was sound and is worth keeping: it was the right fix for the half of the
problem that had been measured, and it was replaced by re-examining the half that hadn't.

## `UnitAI.plan_turn` is a synchronous pure function

**Was** (taskblock-14 Pass B onward, and stated at the top of `unit_ai.gd`): `(unit, state, mission,
playstyle) -> ActionQueue`, synchronous, callable from anywhere.

**Now** (taskblock-44): `(unit, view, mission, playstyle, pacer) -> ActionQueue`, **a coroutine**, and
it takes a `WorldView` rather than a `CombatState`.

Two independent changes landed on the same signature:

- **Pass C** replaced the state with a view, because the rebuild's tiers gate *information* and that
  needs a chokepoint. `CombatState` is reachable only through `canonical_state_for_resolvers()`, which
  may be passed to a resolver and never dereferenced.
- **Pass D** made it a coroutine so it can yield mid-plan. This was forced, not preferred: GDScript
  rejects a conditional `await` at parse time — any function containing one is a coroutine and every
  caller must await — so the only alternatives were a second synchronous planner (two code paths
  deciding the same thing) or no mid-plan yield at all.

**What did NOT change: purity and determinism.** The planner still draws no randomness of its own,
still has zero SceneTree dependency (the pacer carries a `Signal` the view supplies), and a headless
caller passing no pacer never suspends. `test_plan_turn_is_pure_and_deterministic` still holds, and a
seeded bout is byte-identical with and without slicing.

## The retired plan
`PLAN.md` v2.1 and earlier described the from-scratch foundation build (Phase 0 harness, v1-survival
table, exposure-table deletion, the `los.gd` `range`-shadow bug fix). All shipped. The v2.1 plan is
fully retired. Of its two standing rules, only **enums-vs-open-data** survives into v3; the other,
**checkpoint discipline**, was itself later retired (see the ledger row below) once the from-scratch
foundation shipped and live supervisor review replaced the artifact gates.

## Overwatch resolves its own shot (observed tb28 — not yet changed)
**Was:** overwatch's `_fire` is a self-contained shot resolver — it builds its own shot plane, samples
the dartboard, and resolves damage/crit/pen directly, independent of the normal firing path. This was
the original intent when overwatch was built.
**Now (intended, not yet implemented):** overwatch should be a **trigger** that fires the unit's
*provided* firing action — burst preferentially, a shot as fallback — through the shared resolver, the
same way tb24 made the AI derive actions from `ActionCatalog`. The self-contained resolver is a
parallel system (violates the no-parallel-systems rule as it now stands) and it has inherited the
pre-tb27 cell-anchored origin/direction bug (the backward-shot class, cf. BR27.02).
**Status:** logged as a superseded design, **NOT changed yet** (supervisor's call). The eventual fix
replaces `_fire`'s bespoke resolution with "construct and resolve the weapon's provided firing
action." Until then, overwatch works but off the shared path. *(The inherited backward-shot symptom,
if/when it surfaces visually, is a BUG — file it separately; the parallel-path design itself is this
reversal, not a bug.)*
**tb31 D update:** overwatch got its first real UI call site (armable from the action bar via
`TargetingMode.NONE` → `ActionCatalog.build_untargeted_action` → `OverwatchAction`), so it's no longer
a stranded, UI-less mechanic — but `_fire`'s self-contained resolver is **still unchanged**. The
parallel-resolver reversal above remains pending; only reachability changed, not resolution.
