class_name BattleScene
extends Node3D

## docs/10 Phase 12.1: one battle, hand-seeded, from a "New Battle" button.
## No hand-authored .tscn for logic (CLAUDE.md): the .tscn is a bare Node3D
## with this script attached; every child is built here in code.
##
## taskblock-15 Pass A: this is now THE one battle scene — `BoutView` and
## `SimulateBoutMenu` are retired. It builds the world (CameraRig,
## BoardView, one HitVolumeView per unit, the combat-log file sink) exactly
## once and hosts a single swappable `ControlOverlay`, which owns
## everything about HOW a human watches/controls the units (input mapping,
## panels, pacing). Swapping overlays never rebuilds the world — "the world
## is one thing; how you watch and control it is the variable."

## Fires once `load_battle()` has finished rebuilding the world (unit_views,
## board, camera) from a fresh CombatState — the active overlay's own cue
## to re-wire itself (TacticsController.setup(), re-attach its own log
## sink) without a full teardown/setup cycle, e.g. on every "New Battle"
## press. Not fired on the very first `load_battle()` call from `_ready()`
## (there is no overlay yet to hear it) — `set_overlay()` covers that case
## via its own call to `overlay.setup(self)`.
signal battle_loaded

## Temporarily swapped for dartboard verification (runNotes.md follow-up) —
## seed 20260715's blue unit rolls a two-handed sword with only one hand to
## wield it (unarmed in practice). Seed 2 gives both squads a working
## pistol. Revert to 20260715 once verification is done.
const DEFAULT_SEED := 2
## taskblock-17 Pass A: the old 12x10 was well under
## `MapGen.MIN_LEAF_SIZE * 2` (24, taskblock-16's own room-size raise) on
## BOTH axes, so `_split_and_carve` could never split it at all — every
## real battle was silently one room, no hallways, ever since taskblock-16
## landed. 40x30 (~`MIN_LEAF_SIZE * 3` / `MIN_LEAF_SIZE * 2` with room to
## spare) reliably splits 2-3 times per axis instead of just clearing the
## bar once.
const GRID_WIDTH := 40
const GRID_HEIGHT := 30
## runNotes.md: "a 16:9 1080p minimum window should be what we work off
## going forward." project.godot's viewport_width/height sets the launch
## size; this is the actual resize floor.
const MIN_WINDOW_SIZE := Vector2i(1920, 1080)

var board_view: BoardView
var camera_rig: CameraRig
var unit_views: Array[HitVolumeView] = []
var combat_state: CombatState
## taskblock-15 Pass A: every overlay needs a MissionState to hand
## `UnitAI.plan_turn`/`BoutRunner` — including the plain hand-seeded
## default battle, which has none of its own yet (Phase 12 scope: "no
## mission loop"). An empty-objectives MissionState is inert for that
## case (UnitAI's own non-combat branch just walks to extraction) and
## costs nothing; a squad later set to AI under SquadControlOverlay
## auto-resolves through this same object, for free.
var mission: MissionState
## docs/09 taskblock03 Pass B: "one stream, many sinks — never two
## streams." A fresh file per `load_battle()` call — one session, one
## replayable log. World-level (every overlay's own combat_state writes to
## disk, regardless of which one is watching); the on-screen log widget
## itself is overlay-owned (SquadControlOverlay/SpectatorOverlay each
## place and size it differently).
var file_sink: FileSink
var overlay: ControlOverlay
## taskblock-30: owned here, not by whichever overlay happens to be
## installed — `ControlOverlay`'s own header already establishes that
## swapping overlays "never rebuilds the world," and `CombatState` is the
## one shared source of truth regardless of who's watching it.
## `BoutInjector` itself only ever held a bare `CombatState` reference
## (never anything overlay-specific), so owning it at the world level
## (rebuilt alongside `file_sink` on every `load_battle()`) is what lets
## it survive a `SpectatorOverlay` <-> `SquadControlOverlay` swap
## (`toggle_blue_control()`) instead of being torn down with whichever
## overlay first constructed it. Each overlay's own debug-gated UI
## affordance (see `spectator_overlay.gd`/`squad_control_overlay.gd`) just
## reads this, never constructs its own.
var bout_injector: BoutInjector
## taskblock-30 follow-up (supervisor): unit id -> true, for every unit
## `remove_unit_view()` has deliberately made vanish (debug `remove_object`
## on a unit). `CombatState.kill_unit` never deletes from `state.units`
## (by design — never break a held reference), so the unit is still there
## for `sync_unit_views()` to find on the NEXT debug verb's own sync pass;
## without this it would silently resurrect a view for a unit the operator
## just removed. Reset on every `load_battle()` — a fresh bout starts with
## nothing removed, regardless of what a previous bout's ids meant.
var _removed_unit_ids: Dictionary = {}


func _ready() -> void:
	if get_window() != null:
		get_window().min_size = MIN_WINDOW_SIZE

	add_child(WorldPalette.world_environment())
	add_child(WorldPalette.directional_light())

	camera_rig = CameraRig.new()
	add_child(camera_rig)

	board_view = BoardView.new()
	add_child(board_view)

	# set_overlay() BEFORE the first new_battle() call — SquadControlOverlay
	# connects to battle_loaded here with combat_state still null, so its
	# log_sink is already attached by the time load_battle() (inside
	# new_battle(), below) emits that signal, strictly before new_battle()
	# goes on to emit the session-start event. Reversing this order drops
	# that first line silently — nothing was listening yet when it fired.
	set_overlay(SquadControlOverlay.new())
	new_battle(DEFAULT_SEED)


## tb32 Pass B: "a friendly unit standing between the camera and your
## active unit... fade it." Lives here, not `BoardView`, because the
## actual fade applies to a friendly's own `HitVolumeView` (its real
## rendered body, `HitVolumeView.set_occlusion_faded` — see that doc
## comment for why a separate ghost overlay wasn't enough) and only
## `BattleScene` holds both the live camera (via `board_view`) and
## `unit_views`. Re-evaluated every frame — the camera can move
## continuously (drag-to-orbit) with no signal of its own to react to,
## same reasoning `BoardView.update_wall_cutout` already established.
func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var occluding: Array[Unit] = _occluding_friendlies(camera)
	for view: HitVolumeView in unit_views:
		view.set_occlusion_faded(view.unit != null and view.unit in occluding)


## Every OTHER unit sharing `board_view.aim_active_unit`'s own squad that
## currently sits within `BoardView.OCCLUSION_RADIUS_TILES` of, and
## nearer the camera than, the active unit — reuses `WallLegibility.
## occludes_on_screen`/`pixel_radius_for_tiles` unchanged, the same
## screen-space-and-nearer test the wall cutout shader's own per-unit
## radius uses, just against `aim_active_unit` instead of a wall.
func _occluding_friendlies(camera: Camera3D) -> Array[Unit]:
	var result: Array[Unit] = []
	var active: Unit = board_view.aim_active_unit if board_view != null else null
	if camera == null or active == null or not is_instance_valid(active):
		return result
	var active_position: Vector3 = UnitGeometry.bounding_sphere(active).center
	if camera.is_position_behind(active_position):
		return result
	var camera_position: Vector3 = camera.global_position
	var active_screen: Vector2 = camera.unproject_position(active_position)
	var active_depth: float = camera_position.distance_to(active_position)
	var viewport_height: float = float(get_viewport().size.y)
	var radius: float = WallLegibility.pixel_radius_for_tiles(
		BoardView.OCCLUSION_RADIUS_TILES, active_depth, camera.fov, viewport_height
	)
	for unit: Unit in board_view.wall_cutout_units:
		if unit == null or not is_instance_valid(unit) or unit == active:
			continue
		if unit.squad_id != active.squad_id:
			continue
		# A unit that's actually left the board (extraction) keeps its
		# stale `.cell` forever and its own HitVolumeView stays live (no
		# remove_unit_view() call on that path) — without this, an
		# extracted friendly would visibly fade as if it were still
		# standing there blocking the shot.
		if unit.extracted:
			continue
		var position: Vector3 = UnitGeometry.bounding_sphere(unit).center
		if camera.is_position_behind(position):
			continue
		var occludes: bool = WallLegibility.occludes_on_screen(
			camera.unproject_position(position),
			camera_position.distance_to(position),
			active_screen,
			active_depth,
			radius
		)
		if occludes:
			result.append(unit)
	return result


## docs/09 taskblock06 Pass I1: "toggleable" — flips every HitVolumeView's
## own overlay together, the same "one flag, every unit" scope
## ControlsOverlay's own H-key toggle already uses for the help legend.
## World-level: every unit's own hit volumes, regardless of which overlay
## is currently watching them.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	if key_event.keycode == ControlBindings.SIMULATE_BOUT_KEY:
		set_overlay(GenerateBoutOverlay.new())
		return
	if key_event.keycode != ControlBindings.TOGGLE_HIT_VOLUMES_KEY:
		return
	var show: bool = not (unit_views[0].show_hit_volumes if not unit_views.is_empty() else false)
	for view: HitVolumeView in unit_views:
		view.show_hit_volumes = show
		view.refresh()


## taskblock-15 Pass A: the ONE place a `ControlOverlay` swap happens —
## `GenerateBoutOverlay` hands off to `SpectatorOverlay` (A2) exactly this
## way, and `_ready()`'s own default (`SquadControlOverlay`) goes through
## it too, so there is only ever one code path that installs an overlay.
## Tears the old one down first (its own UI/connections), then wires the
## new one against the world already built.
func set_overlay(new_overlay: ControlOverlay) -> void:
	if overlay != null:
		overlay.teardown()
		remove_child(overlay)
		overlay.queue_free()
	overlay = new_overlay
	add_child(overlay)
	overlay.setup(self)


## taskblock-21 Pass C: "assume control of blue team <-> watch." No new
## control system — the overlay swap directly above, exposed as a toggle.
## Squad 0 is "blue" (the same convention `WorldPalette.team_color`/
## `MissionState.player_squad_id` already use); squad 1 ("red") is never
## touched here, so it stays AI regardless of which way this flips.
## `set_overlay`'s own teardown (which SpectatorOverlay's `teardown()`
## already routes through `pause()`) is what makes toggling safe mid
## auto-play — nothing new to guard here either.
func toggle_blue_control() -> void:
	var next_controller: Enums.SquadController = (
		Enums.SquadController.AI
		if combat_state.controller_for(0) == Enums.SquadController.HUMAN
		else Enums.SquadController.HUMAN
	)
	combat_state.set_squad_controller(0, next_controller)
	if next_controller == Enums.SquadController.HUMAN:
		set_overlay(SquadControlOverlay.new())
	else:
		set_overlay(SpectatorOverlay.new())


## Rebuilds the world (board, camera framing, one HitVolumeView per unit)
## from an already-built `CombatState`/`MissionState` — `new_battle()`
## below is the hand-seeded default path through this; `GenerateBoutOverlay`
## (taskblock-14's `BoutSetup`) is the other. Emits `battle_loaded` so
## whichever overlay is ALREADY active (e.g. "New Battle" pressed again
## under `SquadControlOverlay`) can re-wire itself without a full
## teardown/setup cycle.
func load_battle(state: CombatState, p_mission: MissionState) -> void:
	for view: HitVolumeView in unit_views:
		remove_child(view)
		view.queue_free()
	unit_views.clear()
	_removed_unit_ids.clear()

	if file_sink != null:
		file_sink.close()
	file_sink = FileSink.new()

	combat_state = state
	mission = p_mission
	combat_state.combat_log.add_sink(file_sink)
	bout_injector = BoutInjector.new(combat_state)

	board_view.build(combat_state.grid, combat_state.material_table, mission.team_extraction_cells)
	camera_rig.center_on(
		Vector3(
			(combat_state.grid.width - 1) * UnitGeometry.CELL_SIZE * 0.5,
			0.0,
			(combat_state.grid.height - 1) * UnitGeometry.CELL_SIZE * 0.5
		)
	)

	for unit: Unit in combat_state.units:
		var view := HitVolumeView.new()
		add_child(view)
		view.setup(unit, combat_state.material_table)
		unit_views.append(view)

	# taskblock-27 Pass D2: correct from the very first turn too, not just
	# once `refresh_unit_views()` first runs post-turn.
	apply_active_turn_highlight()

	battle_loaded.emit()


## taskblock-22 Pass G2: the isolate camera's own lookup — InspectPanel
## asks for the LIVE HitVolumeView already rendering `unit_id` on the real
## board (not a fresh duplicate) so it can view the genuine article from
## a second camera. Null for an id with no live view (there never should
## be one mid-battle, but a caller with no live board at all — a bare
## unit test — has nothing to look up either).
func find_unit_view(unit_id: int) -> HitVolumeView:
	for view: HitVolumeView in unit_views:
		if view.unit != null and view.unit.id == unit_id:
			return view
	return null


## taskblock-30 follow-up (supervisor report): "spawn unit doesn't create
## a visual model, even though the inspect panel shows it." `BoutInjector.
## spawn_unit` adds a real unit straight into `combat_state.units` — every
## OTHER path that grows the roster runs through this scene's own
## `load_battle()` build loop above, once, at load time; nothing kept
## `unit_views` in sync with `combat_state.units` after that. Diffs the
## two and builds a fresh `HitVolumeView` (the exact same construction
## `load_battle()` already runs) for any unit that doesn't have one yet —
## a no-op once every unit already does, so safe to call after every debug
## verb, not just `spawn_unit`.
func sync_unit_views() -> void:
	for unit: Unit in combat_state.units:
		if _removed_unit_ids.has(unit.id) or find_unit_view(unit.id) != null:
			continue
		var view := HitVolumeView.new()
		add_child(view)
		view.setup(unit, combat_state.material_table)
		unit_views.append(view)


## taskblock-30 follow-up (supervisor): "remove... fully vanishing it" —
## the debug-only counterpart to `sync_unit_views()`'s creation side.
## Destroys `unit`'s own `HitVolumeView` entirely (not just re-rendered
## downed — that's `kill`'s own, narratively real, distinct debug verb)
## and remembers its id so a LATER debug verb's own `sync_unit_views()`
## pass never resurrects it. `CombatState.kill_unit`/`BoutInjector.
## remove_object` already handle the DATA side (mark dead, vacate the
## cell) — this is purely the view-layer half, since `BoutInjector` itself
## is view-agnostic and can't touch the SceneTree at all. No real gameplay
## path ever deletes a view this way — a debug-only visual operation, not
## a front for something real.
func remove_unit_view(unit: Unit) -> void:
	_removed_unit_ids[unit.id] = true
	if board_view != null:
		board_view.exclude_unit_from_occlusion(unit.id)
	for i in range(unit_views.size()):
		if unit_views[i].unit == unit:
			var view: HitVolumeView = unit_views[i]
			unit_views.remove_at(i)
			remove_child(view)
			view.queue_free()
			return


## taskblock-30 follow-up (supervisor report): `board_view.build()` was
## only ever called once, in `load_battle()` — the exact same "data
## changed, nothing rebuilds the view" gap `sync_unit_views()` already
## closed for units, just never noticed for `Grid.blockers`/`field_items`
## (a debug `place_cover`/`clear_cover`/`spawn_object`/`remove_object`/
## `move_object`-on-a-cell call mutates them correctly, but nothing ever
## redrew the board). `build()` already does a full clear-and-rebuild of
## its own static geometry from whatever `grid` currently holds — calling
## it again is the correct resync, not a parallel mechanism.
func sync_board_view() -> void:
	board_view.build(combat_state.grid, combat_state.material_table, mission.team_extraction_cells)


## Every HitVolumeView rebuilt from the unit it already tracks — a
## destroyed part disappears, a moved unit redraws at its new cell. Shared
## by every overlay that resolves a turn for real (docs/09: resolution
## already mutated combat_state synchronously by the time this is called).
##
## taskblock-19 Pass I2: `affected_unit_ids` (default null: every view,
## the safe fallback for a caller with no more precise signal) narrows
## this to just the units a turn's own events actually named
## (`LogPlayback.affected_unit_ids`) — `refresh()` tears down and
## rebuilds a unit's entire mesh subtree from its own socket tree, real
## work that a normal turn has no reason to repeat for every OTHER unit
## on the board that this turn never touched.
## tb32 Pass D (BR27.07): `apply_highlight` lets a caller defer the
## active-turn flip separately — `SquadControlOverlay._on_turn_ended()`
## does, until the previous unit's own action has actually finished
## animating (`await resolution_player.play(events)`); calling this with
## the flip still bundled in used to flip the indicator to the NEXT unit
## before that animation ever played, a real confirmed bug (docs/
## Bugs-add.md's own investigation). True by default so every other
## existing caller (`advance_ai_turns`, `SpectatorOverlay._advance()`)
## keeps its current "always stays in sync, no deferral" behavior
## unchanged.
func refresh_unit_views(affected_unit_ids: Variant = null, apply_highlight: bool = true) -> void:
	for view: HitVolumeView in unit_views:
		if affected_unit_ids == null or (view.unit != null and view.unit.id in affected_unit_ids):
			view.refresh()
	if apply_highlight:
		apply_active_turn_highlight()


## Public (tb32 Pass D): a caller that deferred the flip via
## `refresh_unit_views(..., false)` calls this directly once it's actually
## safe to flip.
func apply_active_turn_highlight() -> void:
	var current: Unit = combat_state.current_unit() if combat_state != null else null
	for view: HitVolumeView in unit_views:
		view.set_active_turn(view.unit != null and view.unit == current)


## Public (not just _ready-internal) so a headless caller/test can seed a
## battle without going through button input. A small hand-seeded fight,
## two squads of deep-struck cyborgs, wrapped in an empty-objectives
## MissionState (see `mission`'s own doc comment above).
func new_battle(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var state: CombatState = _seed_battle(rng)
	var fresh_mission := MissionState.new(RunState.new(), state)
	fresh_mission.objectives = []
	load_battle(state, fresh_mission)
	# docs/09 taskblock03 Pass B2: the seed at session start, so a session
	# is replayable from its own log file alone. This scene has no separate
	# loadout selection to log (assemble_random draws everything — geometry,
	# loadout, the works — from this one seed already).
	combat_state.combat_log.emit(_session_start_event(seed_value))


func _seed_battle(rng: RandomNumberGenerator) -> CombatState:
	var grid: Grid = MapGen.generate(rng.randi(), GRID_WIDTH, GRID_HEIGHT)
	var pool: Array[Part] = DataLibrary.parts_pool()
	var spawn_a: Vector2i = _first_cell_of_terrain(grid, Enums.TerrainType.SPAWN_A, Vector2i(2, 2))
	var spawn_b: Vector2i = _first_cell_of_terrain(grid, Enums.TerrainType.SPAWN_B, Vector2i(9, 7))
	var units: Array[Unit] = [
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, spawn_a, 0),
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, spawn_b, 1),
	]
	var state := CombatState.new(grid, units, rng.randi())
	# tb31 Pass B: every squad must be assigned explicitly now — squad 0
	# (the player's own squad, the same seam `toggle_blue_control()` already
	# flips) HUMAN, squad 1 AI. BR30.09's own root cause was this path
	# assigning nothing at all and silently inheriting a default.
	state.assign_rest_to_ai([0])
	return state


## runNotes.md: "the red unit may be spawning in a non-navigable space" —
## MapGen carves real SPAWN_A/SPAWN_B zones but its own `generate()` return
## signature only hands back the Grid, not the cells it placed them at
## (test files already re-derive them the same way, e.g.
## test_full_mission.gd's `_cells_of_terrain`). `fallback` only fires if a
## map somehow has no cell of that terrain at all.
func _first_cell_of_terrain(grid: Grid, terrain: int, fallback: Vector2i) -> Vector2i:
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain:
				return cell
	return fallback


## docs/09 taskblock03 Pass B2: "log the seed... at session start, so a
## session is replayable from its own log file." unit_id -1: no specific
## unit caused this, same convention `log_impact_result` already uses for
## cover/terrain.
func _session_start_event(seed_value: int) -> LogEvent:
	return LogEvent.new(
		0, Enums.Phase.TACTICS, -1, &"session_start", {"seed": seed_value}, "seed=%d" % seed_value
	)


func _exit_tree() -> void:
	if file_sink != null:
		file_sink.close()
