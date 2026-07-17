extends GutTest

## taskblock-07 Pass F1/TESTS: "every hoverable surface returns a
## TooltipData; no tooltip computes a number locally; hovering an enemy
## yields its status (no gating — taskblock-04 E1)." Pure and
## headless-testable, same split as InventoryRows/WeaponRows: the view
## only ever renders what TooltipBuilder hands it.


func _make_unit(root: Part, squad: int = 0) -> Unit:
	return Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), squad)


func _row_value(data: TooltipData, label: String) -> Variant:
	for row: Dictionary in data.rows:
		if row.label == label:
			return row.value
	return null


func _row_changed(data: TooltipData, label: String) -> bool:
	for row: Dictionary in data.rows:
		if row.label == label:
			return row.changed
	return false


## "no tooltip computes a number locally" — condition is a direct
## "%d/%d" % [part.hp, part.max_hp] read, not a derived percentage or any
## other locally invented number.
func test_for_part_shows_raw_fields_with_no_local_arithmetic() -> void:
	var part := Part.new()
	part.id = &"plate"
	part.hp = 6
	part.max_hp = 10
	part.material = &"steel"
	part.mass = 3.5
	part.bulk = 1.5

	var data: TooltipData = TooltipBuilder.for_part(part, MaterialTable.default_table())

	assert_eq(_row_value(data, "condition"), "%d/%d" % [part.hp, part.max_hp])
	assert_eq(_row_value(data, "mass"), "%.1f" % part.mass)
	assert_eq(_row_value(data, "bulk"), "%.1f" % part.bulk)


func test_for_part_flags_condition_as_changed_only_when_damaged() -> void:
	var whole := Part.new()
	whole.hp = 5
	whole.max_hp = 5
	var damaged := Part.new()
	damaged.hp = 3
	damaged.max_hp = 5

	assert_false(
		_row_changed(TooltipBuilder.for_part(whole, MaterialTable.default_table()), "condition")
	)
	assert_true(
		_row_changed(TooltipBuilder.for_part(damaged, MaterialTable.default_table()), "condition")
	)


func test_for_part_includes_salvage_yield_when_present() -> void:
	var part := Part.new()
	part.id = &"scrap"
	part.hp = 1
	part.max_hp = 1
	part.salvage_yield = {&"metals": 4}

	var data: TooltipData = TooltipBuilder.for_part(part, MaterialTable.default_table())

	assert_ne(_row_value(data, "salvage"), null)


func test_for_part_with_a_row_shows_socket_and_inert_state() -> void:
	var part := Part.new()
	part.id = &"gadget"
	part.hp = 1
	part.max_hp = 1
	var row := InventoryRow.new(part, 1, InventoryRow.Kind.SOCKET, &"ARM", 5.0, true)

	var data: TooltipData = TooltipBuilder.for_part(part, MaterialTable.default_table(), row)

	assert_eq(_row_value(data, "socket"), "ARM")
	assert_true(_row_changed(data, "inert"))


## taskblock-07 F1/TESTS: "hovering an enemy yields its status (no gating —
## taskblock-04 E1)" — a unit on a DIFFERENT squad than the viewer still
## gets its full living-part breakdown, exactly like the player's own.
func test_for_unit_shows_full_status_regardless_of_squad() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 6
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var socket := Socket.new(&"ARM")
	socket.occupant = arm
	torso.sockets = [socket]
	var enemy := _make_unit(torso, 1)  # squad 1 — not the viewer's squad

	var data: TooltipData = TooltipBuilder.for_unit(enemy, MaterialTable.default_table())

	assert_eq(data.title, "unit %d — squad %d" % [enemy.id, enemy.squad_id])
	assert_eq(_row_value(data, "torso"), "%d/%d" % [10, 10])
	assert_eq(_row_value(data, "arm"), "%d/%d" % [4, 6])
	assert_true(_row_changed(data, "arm"), "a damaged part must be flagged changed")


func test_for_unit_omits_destroyed_parts() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 0
	arm.max_hp = 6
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var socket := Socket.new(&"ARM")
	socket.occupant = arm
	torso.sockets = [socket]
	var unit := _make_unit(torso)

	var data: TooltipData = TooltipBuilder.for_unit(unit, MaterialTable.default_table())

	assert_eq(_row_value(data, "arm"), null, "a destroyed part has already left the tree (docs/09)")


func test_for_action_shows_requires_and_requires_action() -> void:
	var action := ActionDef.new(&"overwatch", "Overwatch", "OW", {}, &"shoot")

	var data: TooltipData = TooltipBuilder.for_action(action)

	assert_eq(data.title, "Overwatch")
	assert_eq(_row_value(data, "needs"), "shoot")


func test_for_queue_entry_shows_describe_ap_and_mp() -> void:
	var entry: Dictionary = {"describe": "move to (3, 4)", "ap": 2, "mp": 1.5}

	var data: TooltipData = TooltipBuilder.for_queue_entry(entry)

	assert_eq(data.title, "move to (3, 4)")
	assert_eq(_row_value(data, "AP"), "2")
	assert_eq(_row_value(data, "MP"), "1.5")


func test_for_tile_shows_terrain_when_nothing_else_is_present() -> void:
	var info: Dictionary = {
		"cell": Vector2i(3, 4),
		"terrain": Enums.TerrainType.OPEN,
		"unit": null,
		"field_object": null,
		"cover_value": 0.0,
		"visible_from_selected": null,
	}

	var data: TooltipData = TooltipBuilder.for_tile(info, MaterialTable.default_table())

	assert_eq(data.title, "cell (3, 4)")
	assert_eq(_row_value(data, "terrain"), Enums.TerrainType.keys()[Enums.TerrainType.OPEN])


## taskblock-07 F1/TESTS: "hovering an enemy yields its status" — for_tile
## with a unit present hands back that unit's OWN tooltip, not a merged
## terrain+unit blob.
func test_for_tile_with_a_unit_delegates_to_the_units_own_status() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 8
	torso.max_hp = 8
	var enemy := _make_unit(torso, 1)
	var info: Dictionary = {
		"cell": Vector2i(1, 1),
		"terrain": Enums.TerrainType.OPEN,
		"unit": enemy,
		"field_object": null,
		"cover_value": 0.0,
		"visible_from_selected": true,
	}

	var data: TooltipData = TooltipBuilder.for_tile(info, MaterialTable.default_table())

	assert_eq(data.title, "unit %d — squad %d" % [enemy.id, enemy.squad_id])


func test_for_tile_with_a_field_object_shows_its_own_detail() -> void:
	var crate := FieldObjects.crate()
	var info: Dictionary = {
		"cell": Vector2i(2, 2),
		"terrain": Enums.TerrainType.OPEN,
		"unit": null,
		"field_object": crate,
		"cover_value": 0.0,
		"visible_from_selected": null,
	}

	var data: TooltipData = TooltipBuilder.for_tile(info, MaterialTable.default_table())

	assert_eq(data.title, crate.display_name if crate.display_name != "" else String(crate.id))
	assert_ne(_row_value(data, "condition"), null)


func test_for_tile_on_an_empty_cell_returns_an_empty_tooltip_data() -> void:
	var data: TooltipData = TooltipBuilder.for_tile({}, MaterialTable.default_table())

	assert_eq(data.title, "")
	assert_true(data.rows.is_empty())
