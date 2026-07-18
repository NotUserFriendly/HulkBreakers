extends GutTest

## taskblock-09 E: DT as a lookup table, not a formula — composite/
## ablative/reactive armor has no clean formula, and this game only ever
## authors a handful of thicknesses per material. `dt_at()` is the entire
## read path once a curve is authored; these tests are all pure data, no
## CombatState or shot plane involved.


func test_dt_at_interpolates_linearly_between_authored_points() -> void:
	var entry := MaterialEntry.new()
	entry.dt_curve = [Vector2(2, 3), Vector2(6, 8), Vector2(12, 20)]

	assert_eq(entry.dt_at(2.0), 3.0, "exactly on the first point")
	assert_eq(entry.dt_at(6.0), 8.0, "exactly on the second point")
	assert_eq(entry.dt_at(12.0), 20.0, "exactly on the last point")
	assert_almost_eq(entry.dt_at(4.0), 5.5, 0.0001, "halfway between (2,3) and (6,8)")
	assert_almost_eq(entry.dt_at(9.0), 14.0, 0.0001, "halfway between (6,8) and (12,20)")


func test_dt_at_clamps_below_the_first_and_above_the_last_point() -> void:
	var entry := MaterialEntry.new()
	entry.dt_curve = [Vector2(2, 3), Vector2(6, 8), Vector2(12, 20)]

	assert_eq(entry.dt_at(0.0), 3.0, "below the first point: clamp, never extrapolate")
	assert_eq(entry.dt_at(-5.0), 3.0)
	assert_eq(entry.dt_at(50.0), 20.0, "above the last point: clamp, never extrapolate")


func test_a_thicker_plate_of_the_same_material_yields_higher_dt() -> void:
	var entry := MaterialEntry.new()
	entry.dt_curve = [Vector2(2, 3), Vector2(6, 8), Vector2(12, 20)]

	assert_lt(entry.dt_at(2.0), entry.dt_at(6.0))
	assert_lt(entry.dt_at(6.0), entry.dt_at(12.0))


func test_editing_a_curve_row_changes_dt_with_no_code_change() -> void:
	var entry := MaterialEntry.new()
	entry.dt_curve = [Vector2(2, 3), Vector2(6, 8)]
	var before: float = entry.dt_at(6.0)

	entry.dt_curve = [Vector2(2, 3), Vector2(6, 30)]
	var after: float = entry.dt_at(6.0)

	assert_eq(before, 8.0)
	assert_eq(after, 30.0)
	assert_ne(before, after, "the same call, the same thickness — only the authored row changed")


func test_dt_at_falls_back_to_the_flat_dt_field_when_no_curve_is_authored() -> void:
	var entry := MaterialEntry.new(6.0)
	assert_true(entry.dt_curve.is_empty())
	assert_eq(entry.dt_at(0.0), 6.0)
	assert_eq(entry.dt_at(100.0), 6.0, "flat dt ignores thickness entirely, at any value")
