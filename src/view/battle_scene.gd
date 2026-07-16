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
var tactics: TacticsController
var aim_view: AimView
var unit_views: Array[UnitView] = []
var combat_state: CombatState


func _ready() -> void:
	add_child(HulkTheme.world_environment())

	camera_rig = CameraRig.new()
	add_child(camera_rig)

	board_view = BoardView.new()
	add_child(board_view)

	tactics = TacticsController.new()
	add_child(tactics)
	tactics.turn_ended.connect(_on_turn_ended)

	var ui := CanvasLayer.new()
	add_child(ui)
	var layout := VBoxContainer.new()
	ui.add_child(layout)

	var buttons := HBoxContainer.new()
	layout.add_child(buttons)
	var new_battle_button := Button.new()
	new_battle_button.text = "New Battle"
	new_battle_button.pressed.connect(_on_new_battle_pressed)
	buttons.add_child(new_battle_button)
	var end_turn_button := Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	buttons.add_child(end_turn_button)

	var aim_readout := RichTextLabel.new()
	aim_readout.bbcode_enabled = false
	aim_readout.custom_minimum_size = Vector2(320, 60)
	aim_readout.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	layout.add_child(aim_readout)

	aim_view = AimView.new()
	add_child(aim_view)
	aim_view.setup(tactics, aim_readout)

	new_battle(DEFAULT_SEED)


func _on_new_battle_pressed() -> void:
	new_battle(int(Time.get_ticks_usec()))


func _on_end_turn_pressed() -> void:
	tactics.end_turn()


## Resolution has already mutated combat_state for real (docs/09) — every
## UnitView rebuilds from the unit it already tracks, so a destroyed part
## disappears and a moved unit redraws at its new cell.
func _on_turn_ended() -> void:
	for view: UnitView in unit_views:
		view.refresh()


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
	tactics.setup(combat_state, board_view, camera_rig)

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
