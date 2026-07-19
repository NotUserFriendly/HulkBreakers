extends GutTest

## taskblock-20 Pass E: "closes the angle-lock stalemate by design — higher
## penetration converts deflects into stop-deads." Every claim here is read
## off a real `DamageResolver.resolve_impact` call (CLAUDE.md: never
## re-derive a second copy of the same formula) — live probes found the
## exact angle/bonus_pen/damage combinations below (getting the region's
## own surface_normal axis right for a chosen incidence angle, and keeping
## damage under `effective_dt` so the PENETRATE branch doesn't fire first
## and hide the deflect/stop-dead decision entirely) before this file was
## written.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## `region.surface_normal = (1, 0, 0)`, so `dir = (cos, sin)` of the desired
## incidence angle IS that angle by construction — matches how
## `resolve_impact` reads `Vector2(surface_normal.x, surface_normal.z)`.
func _region(material: StringName) -> Region:
	var part := Part.new()
	part.id = &"test_plate"
	part.material = material
	var region := Region.new(Rect2(-0.1, -0.1, 0.2, 0.2), 1.0, part, Vector3(1, 0, 0))
	region.thickness = 0.1
	return region


func _dir_for_incidence(degrees: float) -> Vector2:
	return Vector2(cos(deg_to_rad(degrees)), sin(deg_to_rad(degrees)))


## "a high-pen oblique shot stop-deads where a low-pen shot at the same
## angle deflects" — steel (dt 6, deflect_threshold_deg 30 by default), 40
## degrees (> 30, a deflect at bonus_pen 0), weak damage so effective_dt (6
## minus bonus_pen) always stays well above it either way.
func test_bonus_pen_converts_an_oblique_deflect_into_a_stop_dead() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	var region: Region = _region(&"steel")
	var dir: Vector2 = _dir_for_incidence(40.0)

	var low_pen: ImpactResult = DamageResolver.resolve_impact(dir, 1.0, region, table, 0.0)
	assert_eq(low_pen.outcome, Enums.Outcome.DEFLECT, "unchanged baseline: no pen, still deflects")

	# scale 10 (the table default) * bonus_pen 2 -> +20 degrees -> threshold
	# 50, and 40 <= 50. effective_dt = 6 - 2 = 4, damage 1 doesn't penetrate.
	var high_pen: ImpactResult = DamageResolver.resolve_impact(dir, 1.0, region, table, 2.0)
	assert_eq(
		high_pen.outcome, Enums.Outcome.STOP_DEAD, "penetration bites in instead of skipping off"
	)


## "no angle lets a high-pen round deflect for zero plate damage" — a
## deflect deals no damage to the part it bounces off (only a spawned
## ricochet's own later hit matters); enough bonus_pen must close that
## door at EVERY incidence, including the most grazing one (near 90
## degrees) that a fixed threshold could never reach. `reactive` (dt 12)
## keeps effective_dt (12 - 6 = 6) safely above the weak damage used here,
## so this is genuinely testing the deflect/stop-dead boundary, not an
## incidental penetrate.
func test_enough_bonus_pen_closes_the_deflect_door_at_the_most_grazing_angle() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	var region: Region = _region(&"reactive")
	var dir: Vector2 = _dir_for_incidence(89.99)

	var result: ImpactResult = DamageResolver.resolve_impact(dir, 0.5, region, table, 6.0)

	assert_eq(result.outcome, Enums.Outcome.STOP_DEAD)
	assert_gt(result.part_damage, 0.0, "stop-dead genuinely damages the plate, unlike a deflect")


## "small-arms-vs-heavy still deflects" — `bonus_pen <= 0` (every weapon
## authored so far; no gun names an AmmoDef yet) must leave the ORIGINAL,
## fixed-threshold behavior completely unchanged: no gap closed.
func test_zero_bonus_pen_leaves_the_original_fixed_threshold_unchanged() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	var region: Region = _region(&"steel")

	var just_inside: ImpactResult = DamageResolver.resolve_impact(
		_dir_for_incidence(29.0), 1.0, region, table, 0.0
	)
	var just_outside: ImpactResult = DamageResolver.resolve_impact(
		_dir_for_incidence(31.0), 1.0, region, table, 0.0
	)

	assert_eq(
		just_inside.outcome, Enums.Outcome.STOP_DEAD, "under the material's own 30deg threshold"
	)
	assert_eq(just_outside.outcome, Enums.Outcome.DEFLECT, "over it — deflects, exactly as before")


## A negative `bonus_pen` (buckshot, docs/09 F: "armor gets HARDER to beat,
## not easier") narrows the window instead — the same relationship, run in
## reverse, not a separate code path.
func test_negative_bonus_pen_narrows_the_stop_dead_window() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	var region: Region = _region(&"steel")
	var dir: Vector2 = _dir_for_incidence(10.0)  # comfortably under the base 30deg threshold

	var mild_penalty: ImpactResult = DamageResolver.resolve_impact(dir, 1.0, region, table, -1.5)
	assert_eq(mild_penalty.outcome, Enums.Outcome.STOP_DEAD, "threshold 30-15=15, still above 10")

	var harsh_penalty: ImpactResult = DamageResolver.resolve_impact(dir, 1.0, region, table, -2.5)
	assert_eq(harsh_penalty.outcome, Enums.Outcome.DEFLECT, "threshold 30-25=5, now under 10")


## "the relationship is a tunable" — a real MaterialTable field, read live,
## never a hardcoded constant in DamageResolver.
func test_the_deflect_threshold_bonus_pen_scale_is_a_real_table_tunable() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	var region: Region = _region(&"steel")
	var dir: Vector2 = _dir_for_incidence(40.0)

	table.deflect_threshold_bonus_pen_scale = 0.0
	var no_scale: ImpactResult = DamageResolver.resolve_impact(dir, 1.0, region, table, 2.0)
	assert_eq(no_scale.outcome, Enums.Outcome.DEFLECT, "zeroed tunable: bonus_pen buys nothing")

	table.deflect_threshold_bonus_pen_scale = 20.0
	var doubled_scale: ImpactResult = DamageResolver.resolve_impact(dir, 1.0, region, table, 2.0)
	assert_eq(doubled_scale.outcome, Enums.Outcome.STOP_DEAD, "a bigger tunable converts sooner")
