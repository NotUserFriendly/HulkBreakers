extends GutTest


func _make_chassis(agility: float) -> Chassis:
	var legs := Part.new()
	legs.id = &"legs"
	legs.slot_type = Enums.SlotType.LEGS
	legs.hp = 5
	legs.max_hp = 5
	legs.stat_mods = {"agility": agility}

	var chassis := Chassis.new()
	chassis.install(legs)
	return chassis


func test_mp_per_ap_uses_base_plus_agility() -> void:
	var matrix := Matrix.new()
	var chassis := _make_chassis(3.0)
	var unit := Unit.new(matrix, chassis, Vector2i(0, 0))
	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP + 3.0, 0.0001)


func test_mp_per_ap_defaults_to_base_with_no_agility_stat() -> void:
	var matrix := Matrix.new()
	var chassis := Chassis.new()
	var unit := Unit.new(matrix, chassis, Vector2i(0, 0))
	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP, 0.0001)


func test_mp_per_ap_reflects_live_part_swaps() -> void:
	var matrix := Matrix.new()
	var chassis := _make_chassis(1.0)
	var unit := Unit.new(matrix, chassis, Vector2i(0, 0))
	var before: float = unit.mp_per_ap()

	var faster_legs := Part.new()
	faster_legs.slot_type = Enums.SlotType.LEGS
	faster_legs.hp = 5
	faster_legs.max_hp = 5
	faster_legs.stat_mods = {"agility": 5.0}
	chassis.install(faster_legs)

	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP + 5.0, 0.0001)
	assert_true(unit.mp_per_ap() > before)


func test_new_unit_starts_alive_with_no_held_core() -> void:
	var unit := Unit.new(Matrix.new(), Chassis.new(), Vector2i(1, 1), 2)
	assert_true(unit.alive)
	assert_null(unit.held_core)
	assert_eq(unit.squad_id, 2)
	assert_eq(unit.id, -1)
