extends GutTest

## taskblock-09 F: bonus penetration is a DT discount, penetration only —
## `effective_dt = max(0, dt_at(material, thickness) - bonus_pen)`, and it
## never touches the incidence/deflect decision (deflection is geometry,
## not energy).


func test_positive_bonus_pen_lets_a_sub_dt_shot_penetrate_for_its_full_damage() -> void:
	var table := MaterialTable.new()
	table.set_entry(&"steel", MaterialEntry.new(7.0))
	var part := Part.new()
	part.id = &"plate"
	part.material = &"steel"
	part.hp = 10
	part.max_hp = 10
	var region := Region.new(Rect2(), 0.0, part, Vector3(1.0, 0.0, 0.0))

	var dir := -Vector2(1.0, 0.0)  # dead-on: would stop-dead without penetrating
	var without_pen: ImpactResult = DamageResolver.resolve_impact(dir, 5.0, region, table)
	assert_ne(without_pen.outcome, Enums.Outcome.PENETRATE, "5 damage alone must not beat DT 7")

	# "A 5-damage / 2-pen round beats DT 7 and deals 5" — the taskblock's
	# own example.
	var with_pen: ImpactResult = DamageResolver.resolve_impact(dir, 5.0, region, table, 2.0)
	assert_eq(with_pen.outcome, Enums.Outcome.PENETRATE)
	assert_eq(with_pen.effective_dt, 5.0, "DT 7 - 2 pen = effective DT 5")
	assert_eq(with_pen.part_damage, 5.0, "bonus pen defeats armor, it never adds damage")


func test_negative_bonus_pen_raises_the_bar() -> void:
	var table := MaterialTable.new()
	table.set_entry(&"steel", MaterialEntry.new(7.0))
	var part := Part.new()
	part.id = &"plate"
	part.material = &"steel"
	part.hp = 10
	part.max_hp = 10
	var region := Region.new(Rect2(), 0.0, part, Vector3(1.0, 0.0, 0.0))

	var dir := -Vector2(1.0, 0.0)
	# 8 damage alone beats DT 7...
	var without_pen: ImpactResult = DamageResolver.resolve_impact(dir, 8.0, region, table)
	assert_eq(without_pen.outcome, Enums.Outcome.PENETRATE)

	# ...but buckshot's own -2 pen raises effective DT to 9, and 8 no
	# longer beats it.
	var with_negative_pen: ImpactResult = DamageResolver.resolve_impact(
		dir, 8.0, region, table, -2.0
	)
	assert_eq(with_negative_pen.effective_dt, 9.0, "DT 7 - (-2) = 9: armor got harder to beat")
	assert_ne(with_negative_pen.outcome, Enums.Outcome.PENETRATE)


func test_effective_dt_floors_at_zero_for_large_positive_pen() -> void:
	var table := MaterialTable.new()
	table.set_entry(&"steel", MaterialEntry.new(7.0))
	var part := Part.new()
	part.id = &"plate"
	part.material = &"steel"
	part.hp = 10
	part.max_hp = 10
	var region := Region.new(Rect2(), 0.0, part, Vector3(1.0, 0.0, 0.0))

	var dir := -Vector2(1.0, 0.0)
	var result: ImpactResult = DamageResolver.resolve_impact(dir, 0.1, region, table, 500.0)
	assert_eq(result.effective_dt, 0.0, "a huge positive pen floors at 0, never goes negative")
	assert_eq(result.outcome, Enums.Outcome.PENETRATE, "any positive damage now beats DT 0")


## Same shot, same oblique angle, with and without bonus pen — a
## deflection is decided purely by `deflect_threshold_deg`/incidence, which
## `resolve_impact` never reads `bonus_pen` anywhere near. This only holds
## while the shot doesn't ALSO penetrate outright because of the pen (kept
## well under DT here on purpose, with or without a modest bonus_pen).
func test_bonus_pen_never_alters_the_deflect_decision() -> void:
	var table := MaterialTable.new()
	table.set_entry(&"steel", MaterialEntry.new(50.0))
	var part := Part.new()
	part.id = &"plate"
	part.material = &"steel"
	part.hp = 10
	part.max_hp = 10
	var region := Region.new(Rect2(), 0.0, part, Vector3(1.0, 0.0, 0.0))

	var rad: float = deg_to_rad(80.0)  # well past the 30 degree default threshold
	var dir := -Vector2(cos(rad), sin(rad))

	var without_pen: ImpactResult = DamageResolver.resolve_impact(dir, 3.0, region, table)
	var with_pen: ImpactResult = DamageResolver.resolve_impact(dir, 3.0, region, table, 5.0)

	assert_eq(without_pen.outcome, Enums.Outcome.DEFLECT)
	assert_eq(
		with_pen.outcome, Enums.Outcome.DEFLECT, "bonus pen must never turn a deflect into a hit"
	)
	assert_eq(without_pen.retained_fraction, with_pen.retained_fraction)
	assert_eq(without_pen.reflected_dir, with_pen.reflected_dir)
