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

	if file_sink != null:
		file_sink.close()
	file_sink = FileSink.new()

	combat_state = state
	mission = p_mission
	combat_state.combat_log.add_sink(file_sink)

	board_view.build(combat_state.grid, combat_state.material_table)
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

	battle_loaded.emit()


## Every HitVolumeView rebuilt from the unit it already tracks — a
## destroyed part disappears, a moved unit redraws at its new cell. Shared
## by every overlay that resolves a turn for real (docs/09: resolution
## already mutated combat_state synchronously by the time this is called).
func refresh_unit_views() -> void:
	for view: HitVolumeView in unit_views:
		view.refresh()


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
	return CombatState.new(grid, units, rng.randi())


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
## unit caused this, same convention `_log_impact` already uses for
## cover/terrain.
func _session_start_event(seed_value: int) -> LogEvent:
	return LogEvent.new(
		0, Enums.Phase.TACTICS, -1, &"session_start", {"seed": seed_value}, "seed=%d" % seed_value
	)


func _exit_tree() -> void:
	if file_sink != null:
		file_sink.close()
