class_name BattleView
extends Node2D

## Thin view layer: click-to-select, click-to-move (reachable highlight),
## click-to-attack (hit location + cover), swap control, New Battle. All game
## rules stay in src/logic and src/data — this node only translates clicks
## into Action objects and redraws.

const MAP_WIDTH := 24
const MAP_HEIGHT := 18
const TILE_PX := GridView.TILE_PX

var grid: Grid
var state: CombatState
var squad_a: Array[Unit] = []
var squad_b: Array[Unit] = []
var selected_unit: Unit = null
var mode: String = "move"  # "move" or "attack"

var grid_view: GridView
var overlay: OverlayLayer
var units_container: Node2D
var camera: Camera2D
var panel: SidePanel
var _markers: Dictionary = {}  # Unit -> UnitMarker


func _ready() -> void:
	var world := Node2D.new()
	add_child(world)

	grid_view = GridView.new()
	world.add_child(grid_view)

	overlay = OverlayLayer.new()
	world.add_child(overlay)

	units_container = Node2D.new()
	world.add_child(units_container)

	camera = Camera2D.new()
	camera.position = Vector2(MAP_WIDTH * TILE_PX / 2.0, MAP_HEIGHT * TILE_PX / 2.0)
	camera.zoom = Vector2(1.4, 1.4)
	camera.enabled = true
	add_child(camera)

	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)
	panel = SidePanel.new()
	panel.position = Vector2(20, 20)
	panel.swap_requested.connect(_on_swap_requested)
	panel.new_battle_requested.connect(_on_new_battle_requested)
	panel.mode_toggle_requested.connect(_on_mode_toggle_requested)
	ui_layer.add_child(panel)

	_start_new_battle()


## Fresh top-level seed for a brand-new battle — everything downstream
## (MapGen, CombatState.rng) is then fully deterministic from it (Appendix A).
func _start_new_battle() -> void:
	var battle_seed: int = randi()
	grid = MapGen.generate(battle_seed, MAP_WIDTH, MAP_HEIGHT)
	grid_view.render(grid)
	overlay.set_grid(grid)
	overlay.clear_selection_overlays()

	for marker: UnitMarker in _markers.values():
		marker.queue_free()
	_markers.clear()

	var spawn_a: Array[Vector2i] = _find_cells(Enums.TerrainType.SPAWN_A)
	var spawn_b: Array[Vector2i] = _find_cells(Enums.TerrainType.SPAWN_B)
	squad_a = _make_squad(spawn_a, 0, "a")
	squad_b = _make_squad(spawn_b, 1, "b")

	var all_units: Array[Unit] = squad_a + squad_b
	state = CombatState.new(grid, all_units, battle_seed)

	for unit: Unit in all_units:
		var marker := UnitMarker.new()
		marker.setup(unit)
		marker.position = grid_view.map_to_local(unit.cell)
		units_container.add_child(marker)
		_markers[unit] = marker

	_deselect()


func _find_cells(terrain_code: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain_code:
				result.append(cell)
	return result


func _make_squad(spawn_cells: Array[Vector2i], squad_id: int, prefix: String) -> Array[Unit]:
	var units: Array[Unit] = []
	var count: int = mini(2, spawn_cells.size())
	for i in range(count):
		var matrix := Matrix.new()
		matrix.id = StringName("%s_matrix_%d" % [prefix, i])
		units.append(Unit.new(matrix, _make_chassis("%s%d" % [prefix, i]), spawn_cells[i], squad_id))
	return units


func _make_chassis(prefix: String) -> Chassis:
	var chassis := Chassis.new()
	chassis.max_mass = 1000.0

	var torso := Part.new()
	torso.id = StringName("%s_torso" % prefix)
	torso.slot_type = Enums.SlotType.TORSO
	torso.part_type = Enums.PartType.ARMOR
	torso.exposure_weight = 30.0
	torso.hp = 10
	torso.max_hp = 10
	torso.is_container = true
	torso.max_volume = 10.0
	chassis.install(torso)

	var legs := Part.new()
	legs.id = StringName("%s_legs" % prefix)
	legs.slot_type = Enums.SlotType.LEGS
	legs.part_type = Enums.PartType.MOBILITY
	legs.exposure_weight = 20.0
	legs.hp = 8
	legs.max_hp = 8
	legs.stat_mods = {"agility": 1.0}
	chassis.install(legs)

	var l_arm := Part.new()
	l_arm.id = StringName("%s_l_arm" % prefix)
	l_arm.slot_type = Enums.SlotType.L_ARM
	l_arm.part_type = Enums.PartType.SENSOR
	l_arm.exposure_weight = 10.0
	l_arm.hp = 6
	l_arm.max_hp = 6
	chassis.install(l_arm)

	var head := Part.new()
	head.id = StringName("%s_head" % prefix)
	head.slot_type = Enums.SlotType.HEAD
	head.part_type = Enums.PartType.SENSOR
	head.exposure_weight = 10.0
	head.hp = 6
	head.max_hp = 6
	chassis.install(head)

	var core := Part.new()
	core.id = StringName("%s_core" % prefix)
	core.slot_type = Enums.SlotType.CORE
	core.part_type = Enums.PartType.ARMOR
	core.exposure_weight = 15.0
	core.hp = 6
	core.max_hp = 6
	chassis.install(core)

	var weapon := Part.new()
	weapon.id = StringName("%s_weapon" % prefix)
	weapon.slot_type = Enums.SlotType.R_ARM
	weapon.part_type = Enums.PartType.WEAPON
	weapon.exposure_weight = 15.0
	weapon.hp = 5
	weapon.max_hp = 5
	chassis.install(weapon)

	var spare_weapon := Part.new()
	spare_weapon.id = StringName("%s_spare_weapon" % prefix)
	spare_weapon.slot_type = Enums.SlotType.R_ARM
	spare_weapon.part_type = Enums.PartType.WEAPON
	spare_weapon.hp = 5
	spare_weapon.max_hp = 5
	spare_weapon.volume = 2.0
	torso.contents.append(spare_weapon)

	return chassis


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos: Vector2 = grid_view.get_local_mouse_position()
		var cell: Vector2i = grid_view.local_to_map(local_pos)
		_handle_cell_click(cell)


func _handle_cell_click(cell: Vector2i) -> void:
	if state == null or state.is_over() or not grid.in_bounds(cell):
		return

	var clicked_unit: Unit = _unit_at(cell)

	if clicked_unit != null and clicked_unit == state.current_unit():
		_select_unit(clicked_unit)
		return

	if selected_unit == null:
		return

	if mode == "attack":
		if clicked_unit != null and clicked_unit != selected_unit:
			_try_attack(clicked_unit)
	else:
		_try_move(cell)


func _unit_at(cell: Vector2i) -> Unit:
	for unit: Unit in _markers.keys():
		if unit.alive and unit.cell == cell:
			return unit
	return null


func _select_unit(unit: Unit) -> void:
	if selected_unit != null and _markers.has(selected_unit):
		_markers[selected_unit].selected = false
		_markers[selected_unit].refresh()
	selected_unit = unit
	_markers[unit].selected = true
	_markers[unit].refresh()
	panel.show_unit(unit)
	_refresh_overlays()


func _deselect() -> void:
	if selected_unit != null and _markers.has(selected_unit):
		_markers[selected_unit].selected = false
		_markers[selected_unit].refresh()
	selected_unit = null
	panel.show_unit(null)
	overlay.clear_selection_overlays()


func _refresh_overlays() -> void:
	if selected_unit == null:
		overlay.clear_selection_overlays()
		return

	if mode == "move":
		var pf := Pathfinder.new(state.grid, state.terrain_costs)
		var budget: float = selected_unit.mp + float(selected_unit.ap) * selected_unit.mp_per_ap()
		overlay.set_reachable(pf.reachable(selected_unit.cell, budget))
		overlay.set_attack_range([])
	else:
		var cells: Array[Vector2i] = []
		for y in range(grid.height):
			for x in range(grid.width):
				var c := Vector2i(x, y)
				if Grid.distance_chebyshev(selected_unit.cell, c) <= AttackAction.DEFAULT_RANGE and LoS.has_los(grid, selected_unit.cell, c):
					cells.append(c)
		overlay.set_attack_range(cells)
		overlay.set_reachable([])


func _try_move(cell: Vector2i) -> void:
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var path: Array[Vector2i] = pf.astar(selected_unit.cell, cell)
	if path.is_empty():
		return
	if not state.try_apply(MoveAction.new(selected_unit, path)):
		return
	_markers[selected_unit].position = grid_view.map_to_local(selected_unit.cell)
	panel.show_unit(selected_unit)
	_refresh_overlays()
	_end_turn_if_out_of_ap()


func _try_attack(target: Unit) -> void:
	var action := AttackAction.new(selected_unit, target)
	if not state.try_apply(action):
		return

	overlay.show_hit(target.cell, _describe_hit(action.last_hit))
	_markers[target].refresh()
	panel.show_unit(selected_unit)
	_end_turn_if_out_of_ap()


func _describe_hit(hit: HitResult) -> String:
	if hit == null:
		return ""
	if hit.part != null:
		return "Hit: %s" % Enums.SlotType.keys()[hit.part.slot_type]
	if hit.cover_object != null:
		return "Hit cover!"
	if hit.blocked:
		return "Blocked by terrain"
	return "Miss"


func _on_swap_requested(slot_type: Enums.SlotType, container: Part, new_part: Part) -> void:
	if selected_unit == null:
		return
	if not state.try_apply(SwapPartAction.new(selected_unit, slot_type, container, new_part)):
		return
	panel.show_unit(selected_unit)
	_markers[selected_unit].refresh()
	_end_turn_if_out_of_ap()


func _on_mode_toggle_requested() -> void:
	mode = "attack" if mode == "move" else "move"
	panel.set_mode_label(mode)
	_refresh_overlays()


func _on_new_battle_requested() -> void:
	_start_new_battle()


func _end_turn_if_out_of_ap() -> void:
	if selected_unit != null and selected_unit.ap <= 0:
		state.try_apply(EndTurnAction.new(selected_unit))
		_deselect()
