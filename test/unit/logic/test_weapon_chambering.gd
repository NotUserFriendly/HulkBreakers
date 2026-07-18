extends GutTest

## taskblock-13 Pass B: "chambering is legal iff ammo.case_family ==
## gun.accepts_family AND ammo.case_length <= gun.max_case_length." All
## fixtures here are hand-authored per CLAUDE.md ("if a test needs a
## concrete list, the test authors it as a fixture") — the taskblock's
## own worked examples (a mini-grenade, cross-compatible fictional
## rounds), not content meant to ship.


func _gun(accepts_family: StringName, max_case_length: float) -> Part:
	var weapon := Part.new()
	weapon.id = &"test_gun"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.accepts_family = accepts_family
	weapon.weapon_def.max_case_length = max_case_length
	return weapon


func _round(id: StringName, case_family: StringName, case_length: float) -> AmmoDef:
	var ammo := AmmoDef.new()
	ammo.id = id
	ammo.case_family = case_family
	ammo.case_length = case_length
	return ammo


func test_same_family_under_max_length_chambers() -> void:
	var gun: Part = _gun(&"12GA", 70.0)
	var round: AmmoDef = _round(&"short_12ga", &"12GA", 50.0)

	assert_eq(WeaponResolver.chamber_error(gun, round), "")


func test_same_family_over_max_length_is_rejected_by_name() -> void:
	var gun: Part = _gun(&"12GA", 70.0)
	var too_long: AmmoDef = _round(&"long_12ga_magnum", &"12GA", 89.0)

	var error: String = WeaponResolver.chamber_error(gun, too_long)

	assert_ne(error, "", "an over-length round must be rejected, never silently accepted")
	assert_true(error.contains("long_12ga_magnum"), "the reason must name the offending round")
	assert_true(error.contains("test_gun"), "the reason must name the gun it doesn't fit")


func test_different_family_is_rejected_regardless_of_length() -> void:
	var gun: Part = _gun(&"12GA", 70.0)
	# Shorter than the chamber allows — length alone would pass; family
	# must still be what actually stops it.
	var wrong_family: AmmoDef = _round(&"tiny_762", &"762x39", 10.0)

	var error: String = WeaponResolver.chamber_error(gun, wrong_family)

	assert_ne(error, "")
	assert_true(error.contains("tiny_762"))


## "Two different-diameter fictional rounds in one family both chamber —
## diameter is not consulted." AmmoDef has no diameter field at all
## (deliberately — see its own header); this proves two rounds that would
## read as wildly different real-world calibers still both chamber as
## long as the family tag and length agree.
func test_two_different_diameter_rounds_in_one_family_both_chamber() -> void:
	var gun: Part = _gun(&"JRAM_10", 40.0)
	var slim: AmmoDef = _round(&"jram_slim", &"JRAM_10", 30.0)
	var fat: AmmoDef = _round(&"jram_fat", &"JRAM_10", 35.0)

	assert_eq(WeaponResolver.chamber_error(gun, slim), "")
	assert_eq(WeaponResolver.chamber_error(gun, fat), "")


## docs' own worked example: "a mini-grenade that drops into a regular gun
## just declares that gun's family" — nothing about the round's own
## identity (a grenade, not a bullet) matters to chambering; only the
## family tag does.
func test_a_mini_grenade_chambers_in_a_normal_gun_by_family_alone() -> void:
	var rifle: Part = _gun(&"556x45", 45.0)
	var mini_grenade: AmmoDef = _round(&"mini_grenade_556", &"556x45", 40.0)

	assert_eq(WeaponResolver.chamber_error(rifle, mini_grenade), "")


## "A long 12GA shell fits the pump but not a short-chambered gun; a short
## 12GA shell fits everything in the 12GA family."
func test_long_shell_fits_the_long_chamber_but_not_the_short_one() -> void:
	var pump := _gun(&"12GA", 89.0)  # 3.5" magnum chamber
	var derringer := _gun(&"12GA", 70.0)  # short-chambered
	var long_shell: AmmoDef = _round(&"12ga_magnum", &"12GA", 89.0)
	var short_shell: AmmoDef = _round(&"12ga_standard", &"12GA", 70.0)

	assert_eq(
		WeaponResolver.chamber_error(pump, long_shell), "", "the long chamber fits its own shell"
	)
	assert_ne(
		WeaponResolver.chamber_error(derringer, long_shell),
		"",
		"the short chamber must reject the long shell"
	)
	assert_eq(
		WeaponResolver.chamber_error(pump, short_shell),
		"",
		"the long chamber also fits the short shell"
	)
	assert_eq(
		WeaponResolver.chamber_error(derringer, short_shell),
		"",
		"the short shell fits everything in its own family"
	)


## ".410/.45LC cross-compat = same family, both under the chamber's max
## length" — two nominally different rounds sharing one family tag.
func test_cross_compatible_rounds_share_one_family() -> void:
	var revolver := _gun(&"REVOLVER_45", 33.0)
	var dot_410: AmmoDef = _round(&"dot_410", &"REVOLVER_45", 33.0)
	var dot_45lc: AmmoDef = _round(&"dot_45lc", &"REVOLVER_45", 33.0)

	assert_eq(WeaponResolver.chamber_error(revolver, dot_410), "")
	assert_eq(WeaponResolver.chamber_error(revolver, dot_45lc), "")


## `try_chamber` mutates `weapon.ammo_id` only on success, and returns the
## same "" / named-reason string `chamber_error` does.
func test_try_chamber_loads_on_success_and_leaves_the_weapon_untouched_on_failure() -> void:
	var gun: Part = _gun(&"12GA", 70.0)
	var good: AmmoDef = _round(&"good_round", &"12GA", 60.0)
	var bad: AmmoDef = _round(&"bad_round", &"9mm", 19.0)

	assert_eq(WeaponResolver.try_chamber(gun, good), "")
	assert_eq(gun.ammo_id, &"good_round")

	var error: String = WeaponResolver.try_chamber(gun, bad)
	assert_ne(error, "")
	assert_eq(gun.ammo_id, &"good_round", "a rejected round must never overwrite what's chambered")


## A part with no WeaponDef at all can't chamber anything — named, not a
## silent crash.
func test_a_non_weapon_part_cannot_chamber_anything() -> void:
	var not_a_gun := Part.new()
	not_a_gun.id = &"torso"
	var round: AmmoDef = _round(&"9mm_fmj", &"9mm", 19.0)

	var error: String = WeaponResolver.chamber_error(not_a_gun, round)

	assert_ne(error, "")
	assert_true(error.contains("torso"))


## Sanity check against the real, shipped data: the four reference guns
## actually chamber their own reference ammo (each round's case_length was
## authored to land exactly at its gun's own max_case_length).
func test_the_real_reference_guns_chamber_their_own_reference_ammo() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()

	var chaingun: Part = DataLibrary.get_part(&"chaingun")
	var sniper: Part = DataLibrary.get_part(&"sniper_rifle")
	var pump: Part = DataLibrary.get_part(&"pump_shotgun")
	var round_556: AmmoDef = DataLibrary.get_ammo(&"556x45_fmj")
	var round_762: AmmoDef = DataLibrary.get_ammo(&"762x51_fmj")
	var round_12ga: AmmoDef = DataLibrary.get_ammo(&"12ga_buckshot")

	assert_eq(WeaponResolver.chamber_error(chaingun, round_556), "")
	assert_eq(WeaponResolver.chamber_error(sniper, round_762), "")
	assert_eq(WeaponResolver.chamber_error(pump, round_12ga), "")
	assert_ne(
		WeaponResolver.chamber_error(chaingun, round_762),
		"",
		"a 762x51 round must not fit a gun chambered for 556x45"
	)

	DataLibrary.reset()
