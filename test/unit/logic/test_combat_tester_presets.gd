extends GutTest

## The "Combat Tester" bot presets (tools/author_combat_tester_presets.gd)
## — one shared body loadout (full body, cladding everywhere via the
## reference humanoid's own defaults; wedge chest armor; half-cylinder
## armor on both legs) across three weapon variants. These prove the
## shipped .tres content actually assembles the way it was authored to,
## through the real DataLibrary/DeepStrike path every other bot uses —
## never a parallel check against the authoring script's own intentions.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _assemble(preset_name: StringName) -> Unit:
	var preset: BotPreset = DataLibrary.get_preset(preset_name)
	assert_not_null(preset, "%s must be a loaded preset" % preset_name)
	var matrix := Matrix.new()
	matrix.id = StringName("%s_matrix" % preset_name)
	return DeepStrike.assemble_from_preset(preset, matrix, Vector2i(0, 0))


func test_all_three_variants_load_and_assemble_with_no_violations() -> void:
	var preset_names: Array[StringName] = [
		&"combat_tester_chaingun", &"combat_tester_sniper_rifle", &"combat_tester_pump_shotgun"
	]
	for preset_name: StringName in preset_names:
		var unit: Unit = _assemble(preset_name)
		assert_not_null(unit, "%s must assemble" % preset_name)
		var violations: Array[String] = DeepStrike.validate_assembly(unit)
		assert_eq(violations, [] as Array[String], "%s: %s" % [preset_name, violations])


func test_all_three_variants_share_the_same_profile_family() -> void:
	var chaingun: BotPreset = DataLibrary.get_preset(&"combat_tester_chaingun")
	var sniper: BotPreset = DataLibrary.get_preset(&"combat_tester_sniper_rifle")
	var shotgun: BotPreset = DataLibrary.get_preset(&"combat_tester_pump_shotgun")
	assert_eq(chaingun.profile_family, &"combat_tester")
	assert_eq(sniper.profile_family, &"combat_tester")
	assert_eq(shotgun.profile_family, &"combat_tester")


func test_group_by_family_lists_all_three_variants_together() -> void:
	var groups: Dictionary = BoutSetup.group_by_family(DataLibrary.presets_pool())
	var members: Array[BotPreset] = groups.get(&"combat_tester", [])
	assert_eq(members.size(), 3)
	var labels: Array = members.map(func(m: BotPreset) -> String: return m.variant_label)
	assert_true(&"Chaingun" in labels or "Chaingun" in labels)
	assert_true("Sniper Rifle" in labels)
	assert_true("Pump Shotgun" in labels)


## "All body parts, cladding everywhere" — the reference humanoid's own
## defaults, untouched by this preset's loadout: head, both arms, both
## forearms, both legs, torso, all with their own cladding still
## attached.
func test_the_body_has_every_part_and_cladding_everywhere() -> void:
	var unit: Unit = _assemble(&"combat_tester_chaingun")
	var all_parts: Array[Part] = PartGraph.walk(unit.shell.root)
	var ids: Array = all_parts.map(func(p: Part) -> StringName: return p.id)

	for expected: StringName in [&"torso", &"head", &"arm", &"forearm", &"leg"]:
		assert_true(expected in ids, "%s must be present" % expected)

	var cladding_ids: Array[StringName] = [
		&"torso_cladding", &"head_cladding", &"arm_cladding", &"forearm_cladding", &"leg_cladding"
	]
	for cladding_id: StringName in cladding_ids:
		var count: int = ids.count(cladding_id)
		assert_gt(count, 0, "%s must be attached somewhere on the body" % cladding_id)


## "Wedge shaped chest armor" — mounted on the torso's own ARMOR_FRONT.
func test_the_chest_wears_the_torso_sized_wedge() -> void:
	var unit: Unit = _assemble(&"combat_tester_chaingun")
	var socket: Socket = PartGraph.find_socket(unit.shell.root, &"ARMOR_FRONT")
	assert_not_null(socket)
	assert_eq(socket.occupant.id, &"wedge_plate_torso")


## "Half-cylinder armor on both thighs" — both legs, never the arms.
func test_both_legs_wear_the_half_cylinder_plate_and_arms_do_not() -> void:
	var unit: Unit = _assemble(&"combat_tester_chaingun")
	var leg_count := 0
	var arm_has_half_cylinder := false
	for part: Part in PartGraph.walk(unit.shell.root):
		if part.id == &"leg":
			var socket: Socket = PartGraph.find_socket(part, &"LEG_ARMOR")
			if socket.occupant != null and socket.occupant.id == &"half_cylinder_plate":
				leg_count += 1
		elif part.id == &"arm" or part.id == &"forearm":
			var socket: Socket = PartGraph.find_socket(part, &"ARMOR")
			if socket.occupant != null and socket.occupant.id == &"half_cylinder_plate":
				arm_has_half_cylinder = true
	assert_eq(leg_count, 2, "both legs must wear the half-cylinder plate")
	assert_false(arm_has_half_cylinder, "the arms/forearms must keep their own default armor")


func test_each_variant_carries_its_own_named_weapon() -> void:
	var expected: Dictionary = {
		&"combat_tester_chaingun": &"chaingun",
		&"combat_tester_sniper_rifle": &"sniper_rifle",
		&"combat_tester_pump_shotgun": &"pump_shotgun",
	}
	for preset_name: StringName in expected:
		var unit: Unit = _assemble(preset_name)
		var weapon: Part = DeepStrike.find_operable_weapon(unit)
		assert_not_null(weapon, "%s must carry an operable weapon" % preset_name)
		assert_eq(weapon.id, expected[preset_name])
