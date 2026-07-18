extends GutTest

## taskblock-10 Pass D: "the reference ammo set loads and validates."
## Exercises the REAL `res://data/ammo/` (not a fixture root, unlike
## test_data_library.gd's own contract tests) — this is the actual
## checked-in reference table, straight from the design's own numbers.

## id -> {damage, bonus_pen, projectile_num, stack_type, stacks_inflicted}
const EXPECTED: Dictionary = {
	&"9mm_fmj":
	{"damage": 4.0, "bonus_pen": 1.0, "projectile_num": 1, "stack_type": &"", "stacks": 0.0},
	&"9mm_incendiary":
	{"damage": 3.0, "bonus_pen": 0.0, "projectile_num": 1, "stack_type": &"BURN", "stacks": 1.0},
	&"556x45_fmj":
	{"damage": 4.0, "bonus_pen": 3.0, "projectile_num": 1, "stack_type": &"", "stacks": 0.0},
	&"556x45_ap":
	{"damage": 4.0, "bonus_pen": 6.0, "projectile_num": 1, "stack_type": &"", "stacks": 0.0},
	&"762x51_fmj":
	{"damage": 6.0, "bonus_pen": 3.0, "projectile_num": 1, "stack_type": &"", "stacks": 0.0},
	&"762x51_ap":
	{"damage": 6.0, "bonus_pen": 6.0, "projectile_num": 1, "stack_type": &"", "stacks": 0.0},
	&"12ga_buckshot":
	{"damage": 3.0, "bonus_pen": -2.0, "projectile_num": 9, "stack_type": &"", "stacks": 0.0},
	&"12ga_flechette":
	{"damage": 3.0, "bonus_pen": 0.0, "projectile_num": 7, "stack_type": &"BLEED", "stacks": 1.0},
}


func before_each() -> void:
	DataLibrary.reset()
	# Real res://data/ammo, but an empty user root — a developer's own
	# real user://data (if any exists on this machine) must never leak
	# into this test.
	DataLibrary.load_all(DataLibrary.BUILTIN_ROOT, "user://test_ammo_def_empty_root")


func after_each() -> void:
	DataLibrary.reset()


func test_the_reference_ammo_set_loads_and_validates() -> void:
	assert_true(DataLibrary.errors().is_empty(), "no reference round may fail validation")
	for id: StringName in EXPECTED:
		assert_not_null(DataLibrary.get_ammo(id), "%s must load" % id)


func test_every_reference_round_matches_the_ammo_table() -> void:
	for id: StringName in EXPECTED:
		var expected: Dictionary = EXPECTED[id]
		var ammo: AmmoDef = DataLibrary.get_ammo(id)
		assert_eq(ammo.damage, expected.damage, "%s.damage" % id)
		assert_eq(ammo.bonus_pen, expected.bonus_pen, "%s.bonus_pen" % id)
		assert_eq(ammo.projectile_num, expected.projectile_num, "%s.projectile_num" % id)
		assert_eq(ammo.stack_type, expected.stack_type, "%s.stack_type" % id)
		assert_eq(ammo.stacks_inflicted, expected.stacks, "%s.stacks_inflicted" % id)


## "bonus pen can be negative — buckshot" (taskblock-09 F): armor gets
## HARDER to beat, never easier.
func test_buckshot_bonus_pen_is_negative() -> void:
	assert_lt(DataLibrary.get_ammo(&"12ga_buckshot").bonus_pen, 0.0)


## "a slug is one ray at the dartboard point" (taskblock-10): every
## reference round here except the two shotgun shells is a slug.
func test_only_the_shotgun_shells_have_more_than_one_projectile() -> void:
	for id: StringName in EXPECTED:
		var ammo: AmmoDef = DataLibrary.get_ammo(id)
		if id in [&"12ga_buckshot", &"12ga_flechette"]:
			assert_gt(ammo.projectile_num, 1, "%s must be a spread round" % id)
		else:
			assert_eq(ammo.projectile_num, 1, "%s must be a single slug" % id)
