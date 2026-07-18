extends GutTest

## taskblock-10 Pass D: "the validator is shared with the Resource Editor
## (taskblock-11) — one module, two callers." Unit-level coverage of
## `DataValidator` itself, independent of `DataLibrary`'s own
## load/reject-by-name tests (test_data_library.gd).


func test_a_valid_part_produces_no_errors() -> void:
	var part := Part.new()
	part.id = &"torso"
	assert_eq(DataValidator.validate(part), [] as Array[ValidationError])


func test_a_bad_failure_mode_produces_a_named_error() -> void:
	var part := Part.new()
	part.id = &"reactor"
	part.failure_mode = &"NOT_A_REAL_MODE"
	var errors: Array[ValidationError] = DataValidator.validate(part)
	assert_eq(errors.size(), 1)
	assert_eq(errors[0].resource_id, &"reactor")
	assert_eq(errors[0].field, &"failure_mode")


func test_a_valid_ammo_row_produces_no_errors() -> void:
	var ammo := AmmoDef.new()
	ammo.id = &"9mm_fmj"
	assert_eq(DataValidator.validate(ammo), [] as Array[ValidationError])


## TEST: "a bad stack_type produces a named error with the row's id."
func test_a_bad_stack_type_produces_a_named_error_with_the_rows_id() -> void:
	var ammo := AmmoDef.new()
	ammo.id = &"9mm_mystery"
	ammo.stack_type = &"POISON"
	var errors: Array[ValidationError] = DataValidator.validate(ammo)
	assert_eq(errors.size(), 1)
	assert_eq(errors[0].resource_id, &"9mm_mystery")
	assert_eq(errors[0].field, &"stack_type")


## TEST: "a dt_curve out of order is caught."
func test_a_dt_curve_out_of_order_is_caught() -> void:
	var material := MaterialEntry.new()
	material.id = &"warped_steel"
	material.dt_curve = [Vector2(1.0, 3.0), Vector2(0.5, 6.0)]
	var errors: Array[ValidationError] = DataValidator.validate(material)
	assert_eq(errors.size(), 1)
	assert_eq(errors[0].resource_id, &"warped_steel")
	assert_eq(errors[0].field, &"dt_curve")


func test_an_ascending_dt_curve_produces_no_errors() -> void:
	var material := MaterialEntry.new()
	material.id = &"layered_ceramic"
	material.dt_curve = [Vector2(0.0, 3.0), Vector2(1.0, 6.0), Vector2(2.0, 9.0)]
	assert_eq(DataValidator.validate(material), [] as Array[ValidationError])
