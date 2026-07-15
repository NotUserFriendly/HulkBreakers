extends GutTest


func test_render_marks_only_changed_values() -> void:
	# Base chaingun: 5 Damage, 10 projectile burst, recoil 10. Spin Up adds
	# projectiles and cuts recoil; damage is untouched (docs/08 worked example).
	var damage := StatValue.new(5.0, 5.0, [])
	var burst := (
		StatValue
		. new(
			10.0,
			14.0,
			[ModSource.new("Spin Up", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, 4.0)],
		)
	)
	var recoil := (
		StatValue
		. new(
			10.0,
			8.0,
			[ModSource.new("Spin Up", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, -2.0)],
		)
	)

	var text: String = (
		DescriptionBuilder
		. render(
			[
				{"label": "Damage", "value": damage},
				{"label": "Burst", "value": burst},
				{"label": "Recoil", "value": recoil},
			]
		)
	)

	assert_true(text.contains("Damage: 5"))
	assert_false(text.contains("[5]"), "damage did not change and must not be bracketed")
	assert_true(text.contains("Burst: [14]"))
	assert_true(text.contains("Recoil: [8]"))


func test_render_appends_a_new_effect_line_from_ammo() -> void:
	# "Load incendiary ammo and it appends: Shots inflict 0.5 stacks of burn."
	var burn := (
		StatValue
		. new(
			0.0,
			0.5,
			[ModSource.new("Incendiary Rounds", Enums.ModSourceKind.AMMO, Enums.ModOp.ADD, 0.5)],
		)
	)
	var text: String = DescriptionBuilder.render([{"label": "Burn stacks", "value": burn}])
	assert_eq(text, "Burn stacks: [0.5]")


func test_drill_down_lists_each_source_with_its_operation() -> void:
	var value := (
		StatValue
		. new(
			10.0,
			18.0,
			[
				ModSource.new("Ceramic Plate", Enums.ModSourceKind.PART, Enums.ModOp.ADD, 5.0),
				ModSource.new("Spin Up", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, 3.0),
			],
		)
	)
	var lines: Array[String] = DescriptionBuilder.drill_down(value)
	assert_eq(lines.size(), 2)
	assert_true(lines[0].contains("Ceramic Plate"))
	assert_true(lines[0].contains("PART"))
	assert_true(lines[1].contains("Spin Up"))


func test_drill_down_is_empty_for_an_unmodified_stat() -> void:
	var value := StatValue.new(5.0, 5.0, [])
	assert_eq(DescriptionBuilder.drill_down(value), [] as Array[String])
