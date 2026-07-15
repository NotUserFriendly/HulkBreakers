class_name BattleScene
extends Node3D

## docs/10 Phase 12.1: one battle, hand-seeded, from a "New Battle" button.
## No mission loop, no mission verbs yet — just something a human can see
## and orbit a camera around. No hand-authored .tscn for logic (CLAUDE.md):
## the .tscn is a bare Node3D with this script attached; every child is
## built here in code.

const DEFAULT_SEED := 20260715
const GRID_WIDTH := 12
const GRID_HEIGHT := 10

var board_view: BoardView
var camera_rig: CameraRig
var unit_views: Array[UnitView] = []
var combat_state: CombatState


func _ready() -> void:
	add_child(HulkTheme.world_environment())

	camera_rig = CameraRig.new()
	add_child(camera_rig)

	board_view = BoardView.new()
	add_child(board_view)

	var ui := CanvasLayer.new()
	add_child(ui)
	var button := Button.new()
	button.text = "New Battle"
	button.pressed.connect(_on_new_battle_pressed)
	ui.add_child(button)

	new_battle(DEFAULT_SEED)


func _on_new_battle_pressed() -> void:
	new_battle(int(Time.get_ticks_usec()))


## Public (not just _ready-internal) so a headless caller/test can seed a
## battle without going through button input.
func new_battle(seed_value: int) -> void:
	for view: UnitView in unit_views:
		remove_child(view)
		view.queue_free()
	unit_views.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	combat_state = _seed_battle(rng)

	board_view.build(combat_state.grid, combat_state.material_table)
	camera_rig.center_on(
		Vector3(
			(combat_state.grid.width - 1) * UnitGeometry.CELL_SIZE * 0.5,
			0.0,
			(combat_state.grid.height - 1) * UnitGeometry.CELL_SIZE * 0.5
		)
	)

	for unit: Unit in combat_state.units:
		var view := UnitView.new()
		add_child(view)
		view.setup(unit, combat_state.material_table)
		unit_views.append(view)


## A small hand-seeded fight, two squads of deep-struck cyborgs — reusing
## DeepStrike's pool for quick, varied loadouts rather than re-authoring
## parts here. Mission loop, roster/loadout selection: out of scope for
## Phase 12 (one battle, no mission).
func _seed_battle(rng: RandomNumberGenerator) -> CombatState:
	var grid: Grid = MapGen.generate(rng.randi(), GRID_WIDTH, GRID_HEIGHT)
	var pool: Array[Part] = DeepStrike.default_part_pool()
	var units: Array[Unit] = [
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, Vector2i(2, 2), 0),
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, Vector2i(9, 7), 1),
	]
	return CombatState.new(grid, units, rng.randi())
