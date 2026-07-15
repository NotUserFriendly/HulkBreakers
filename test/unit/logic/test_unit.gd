extends GutTest


func _make_frame(agility: float) -> Frame:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.stat_mods = {"agility": agility}
	return Frame.new(root)


func test_mp_per_ap_uses_base_plus_agility() -> void:
	var matrix := Matrix.new()
	var frame := _make_frame(3.0)
	var unit := Unit.new(matrix, frame, Vector2i(0, 0))
	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP + 3.0, 0.0001)


func test_mp_per_ap_defaults_to_base_with_no_agility_stat() -> void:
	var matrix := Matrix.new()
	var frame := Frame.new(Part.new())
	var unit := Unit.new(matrix, frame, Vector2i(0, 0))
	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP, 0.0001)


func test_mp_per_ap_reflects_live_part_swaps() -> void:
	var matrix := Matrix.new()
	var frame := _make_frame(1.0)
	var unit := Unit.new(matrix, frame, Vector2i(0, 0))
	var before: float = unit.mp_per_ap()

	# Simulate a swap by mutating the root's stats directly (SwapPartAction
	# proper is rebuilt in Phase 6 against the socket model).
	frame.root.stat_mods = {"agility": 5.0}

	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP + 5.0, 0.0001)
	assert_true(unit.mp_per_ap() > before)


func test_new_unit_starts_alive_with_no_held_matrix() -> void:
	var unit := Unit.new(Matrix.new(), Frame.new(Part.new()), Vector2i(1, 1), 2)
	assert_true(unit.alive)
	assert_null(unit.held_matrix)
	assert_eq(unit.squad_id, 2)
	assert_eq(unit.id, -1)
