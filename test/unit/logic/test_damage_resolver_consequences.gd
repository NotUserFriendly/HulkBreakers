extends GutTest

## docs/01/04/taskblock-09 A: destruction's downstream consequences — matrix
## ejection (with the surrogate demotion it always carries) and each
## failure_mode's own dispatch (MANGLE/DISABLE stay attached; the old
## subtree-drop-on-destroy is gone, taskblock-09 C2 — a part leaves the body
## only via a severed JOINT now, tested where joints are built). Split out
## of test_damage_resolver.gd (which covers armor/DT/ricochet/crit/detonate)
## purely to stay under gdlint's max-public-methods.


func _make_matrix_hosting_torso(cell: Vector2i) -> Dictionary:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	torso.sockets = [Socket.new(&"MATRIX")]
	var link := Matrix.new()
	link.id = &"link"
	torso.hosted_matrix = link
	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell)
	return {"unit": unit, "torso": torso, "link": link}


func test_destroying_the_matrix_hosting_part_ejects_it_demotes_and_disables() -> void:
	var built: Dictionary = _make_matrix_hosting_torso(Vector2i(2, 2))
	var unit: Unit = built.unit
	var torso: Part = built.torso
	var link: Matrix = built.link
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid, [unit])

	DamageResolver.apply_damage_to_part(torso, 10.0)
	var ejected: Matrix = DamageResolver.eject_matrix_if_needed(torso, state)

	assert_eq(ejected, link)
	assert_null(torso.hosted_matrix, "the part no longer hosts the matrix once it's ejected")
	assert_true(
		state.grid.field_items[Vector2i(2, 2)].has(link),
		"the ejected matrix must land as a recoverable field item, never simply discarded"
	)
	assert_false(unit.alive, "unpiloted once its matrix ejects")
	# PERIPHERAL: demoting FULL is genuinely ambiguous on the DAG (docs/04
	# taskblock03 A2) — this is SurrogateLadder.demote()'s flagged,
	# deterministic placeholder tie-break, not asserting it's the "right"
	# branch to fall to.
	assert_eq(unit.surrogate_tier.id, &"PERIPHERAL", "one step down from FULL")
	assert_eq(unit.exposed_turns, 1, "the exposure clock must start ticking")


func test_eject_matrix_if_needed_is_a_no_op_for_a_part_that_hosts_none() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 0
	torso.max_hp = 5
	var state := CombatState.new(Grid.new(5, 5))
	assert_null(DamageResolver.eject_matrix_if_needed(torso, state))


## docs/01: only torso and head templates ever declare a MATRIX socket —
## destroying either ejects, destroying an arm never does.
func test_destroying_a_head_that_hosts_the_matrix_ejects_it() -> void:
	var head := Part.new()
	head.id = &"head"
	head.hp = 3
	head.max_hp = 3
	head.attaches_to = [&"NECK"]
	head.sockets = [Socket.new(&"MATRIX")]
	var link := Matrix.new()
	link.id = &"link"
	head.dock_matrix(link)

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 20
	torso.max_hp = 20
	var neck := Socket.new(&"NECK")
	neck.occupant = head
	torso.sockets = [neck]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(head, 10.0)
	var ejected: Matrix = DamageResolver.eject_matrix_if_needed(head, state)

	assert_eq(ejected, link)
	assert_null(head.hosted_matrix)
	assert_false(unit.alive)


func test_destroying_an_arm_never_ejects_a_matrix() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 0
	arm.max_hp = 4
	arm.attaches_to = [&"SHOULDER"]
	# An arm has no MATRIX socket to dock into in the first place — hosted_matrix
	# stays null no matter what, so there is nothing for destruction to eject.
	assert_false(arm.hosts_matrix())

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 20
	torso.max_hp = 20
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))
	var state := CombatState.new(Grid.new(5, 5), [unit])

	assert_null(DamageResolver.eject_matrix_if_needed(arm, state))
	assert_true(unit.alive, "an arm's destruction never unpilots the unit")


func test_a_torso_chewed_to_spinal_still_functions_it_only_stops_at_matrix_ejection() -> void:
	# docs/04: demotion tracks matrix-hosting-part destruction, not simply
	# taking damage — a hit that doesn't destroy the host leaves the
	# surrogate tier untouched.
	var built: Dictionary = _make_matrix_hosting_torso(Vector2i(2, 2))
	var unit: Unit = built.unit
	var torso: Part = built.torso
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(torso, 2.0)  # 5 hp -> 3, still alive
	DamageResolver.eject_matrix_if_needed(torso, state)

	assert_eq(unit.surrogate_tier.id, &"FULL", "the host survived, nothing should have demoted yet")
	assert_true(unit.alive)


## torso -[SHOULDER]- arm -[WRIST]- hand -[GRIP]- pistol
func _make_armed_unit(cell: Vector2i) -> Dictionary:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 3
	arm.max_hp = 3
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	arm.sockets = [wrist]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell)
	return {"unit": unit, "torso": torso, "arm": arm, "hand": hand, "pistol": pistol}


## taskblock-09 A1: MANGLE is the default failure_mode — reaching 0 hp
## flips `is_mangled`, but the part (and everything hanging off it) never
## leaves the tree. Only a severed JOINT does that now (Pass C).
func test_a_mangling_part_stays_attached_and_flips_is_mangled() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var hand: Part = built.hand
	var pistol: Part = built.pistol
	var state := CombatState.new(Grid.new(5, 5), [unit])

	assert_eq(arm.failure_mode, &"MANGLE", "MANGLE is the default failure_mode")
	DamageResolver.apply_damage_to_part(arm, 10.0)
	var impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(arm, state, impact)

	assert_true(arm.is_mangled, "reaching 0 hp under MANGLE must flip is_mangled")
	assert_true(unit.shell.all_parts().has(arm), "a mangled part stays in the unit's own assembly")
	assert_true(
		PartGraph.walk(arm).has(hand) and PartGraph.walk(arm).has(pistol),
		"the arm's own subtree (hand, pistol) must still hang off it, fully assembled"
	)
	assert_true(state.grid.field_items.is_empty(), "MANGLE never drops anything as a field item")


## docs/03/taskblock-09 A2: DISABLE stays attached too — dead weight, still
## occupies its socket, contributes nothing (that half is Shell.living_
## parts()'s pre-existing hp>0 filter, not new here).
func test_a_disabled_part_stays_attached_and_flips_is_disabled() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	arm.failure_mode = &"DISABLE"
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(arm, 10.0)
	var impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(arm, state, impact)

	assert_true(arm.is_disabled, "reaching 0 hp under DISABLE must flip is_disabled")
	assert_false(arm.is_mangled, "a part has exactly one failure_mode, never both flags")
	assert_true(unit.shell.all_parts().has(arm), "a disabled part stays in the unit's own assembly")


## A non-mangling destroyed part never loses its own identity — "a broken
## pistol is still a pistol." `broken` is derived from hp <= 0, not a
## second field: this only ever asserts hp, never a `.broken` property.
## taskblock-09 A1: MANGLE (the default) no longer detaches or swaps
## anything on its own — `mangles_into` is a cosmetic/salvage hook, empty
## here, so the pistol just stays exactly itself.
func test_a_broken_pistol_is_still_identifiably_a_pistol() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var pistol: Part = built.pistol
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(pistol, 10.0)
	var impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(pistol, state, impact)

	assert_eq(pistol.id, &"pistol", "identity survives destruction when the part doesn't mangle")
	assert_true(pistol.hp <= 0, "broken is read straight off hp, never a separate flag")
	assert_true(unit.shell.all_parts().has(pistol), "still attached — nothing severed it")


func test_wreckage_yields_its_own_salvage() -> void:
	var wreckage: Part = DataLibrary.get_part(&"twisted_sheet_metal")
	assert_false(wreckage.salvage_yield.is_empty(), "wreckage must actually carry salvage_yield")


func test_a_mangling_parts_own_id_carries_no_salvage_the_wreckage_does() -> void:
	# The original template as authored in the real pool (docs/10
	# taskblock05 D2): a plate mangles into scrap, not the other way
	# around, and the plate itself carries none of the salvage credit.
	var plate := Part.new()
	plate.id = &"plate_medium_sheet_steel"
	plate.mangles_into = &"metal_scraps"
	assert_true(plate.salvage_yield.is_empty())
	assert_false(DataLibrary.get_part(&"metal_scraps").salvage_yield.is_empty())


## taskblock-09 E1: "compute the resolved number first, then quarter it" —
## a mangled part's residual DT is exactly 1/4 of what dt_at() would
## otherwise resolve to at that same thickness, not a separately-curved
## number. thickness feeds DT ONLY (taskblock-09 E2) — hp/max_hp are
## plain authored numbers, never derived from it; asserted here directly
## rather than as a separate near-empty test.
func test_mangle_residual_dt_is_exactly_a_quarter_of_the_resolved_value() -> void:
	var table := MaterialTable.new()
	var entry := MaterialEntry.new()
	entry.dt_curve = [Vector2(2.0, 4.0), Vector2(8.0, 16.0)]
	table.set_entry(&"composite", entry)

	var plate := Part.new()
	plate.id = &"plate"
	plate.material = &"composite"
	plate.hp = 12
	plate.max_hp = 12

	var region := Region.new(Rect2(), 0.0, plate, Vector3(1.0, 0.0, 0.0))
	region.thickness = 8.0  # dt_at(8.0) == 16.0

	var dir := -Vector2(1.0, 0.0)  # dead-on
	var intact: ImpactResult = DamageResolver.resolve_impact(dir, 10.0, region, table)
	assert_eq(intact.effective_dt, 16.0, "an intact part reads the full resolved DT")
	assert_ne(intact.outcome, Enums.Outcome.PENETRATE, "10 damage must not beat the full 16 DT")

	plate.is_mangled = true
	var mangled: ImpactResult = DamageResolver.resolve_impact(dir, 10.0, region, table)
	assert_eq(mangled.effective_dt, 4.0, "1/4 of 16 — the same resolved number, just quartered")
	assert_eq(mangled.outcome, Enums.Outcome.PENETRATE, "10 damage easily beats the quartered 4 DT")

	assert_eq(plate.hp, 12, "thickness/mangling only ever change DT, never hp")
	assert_eq(plate.max_hp, 12)
