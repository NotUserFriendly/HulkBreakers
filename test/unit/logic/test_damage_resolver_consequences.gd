extends GutTest

## docs/01/04: destruction's downstream consequences — matrix ejection (with
## the surrogate demotion it always carries) and dropping a destroyed
## non-root part's subtree as one intact assembly. Split out of
## test_damage_resolver.gd (which covers armor/DT/ricochet/crit/cook-off)
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


func test_destroying_a_limb_drops_its_whole_subtree_as_one_intact_assembly() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var hand: Part = built.hand
	var pistol: Part = built.pistol
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid, [unit])

	DamageResolver.apply_damage_to_part(arm, 10.0)
	var dropped: Array[Part] = DamageResolver.drop_subtree_if_destroyed(arm, state)

	assert_eq(dropped, [arm])
	assert_false(
		unit.shell.all_parts().has(arm), "the arm is no longer part of the unit's own assembly"
	)
	assert_true(
		state.grid.field_items[Vector2i(2, 2)].has(arm),
		"the dropped arm must land as a recoverable field item"
	)
	assert_true(
		PartGraph.walk(arm).has(hand) and PartGraph.walk(arm).has(pistol),
		"the arm's own subtree (hand, pistol) must still hang off it, fully assembled"
	)


func test_drop_subtree_if_destroyed_is_a_no_op_for_a_part_still_alive() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var state := CombatState.new(Grid.new(5, 5), [unit])

	assert_eq(DamageResolver.drop_subtree_if_destroyed(arm, state), [] as Array[Part])


func test_drop_subtree_if_destroyed_is_a_no_op_for_the_shells_own_root() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var torso: Part = built.torso
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(torso, 10.0)
	assert_eq(
		DamageResolver.drop_subtree_if_destroyed(torso, state),
		[] as Array[Part],
		"the root has no parent within its own shell to drop it from"
	)


## Same shape as _make_armed_unit, but the arm mangles into wreckage —
## docs/10 taskblock05 E1/E2: the arm is what becomes scrap, not the
## forearm-hand-pistol assembly it was carrying.
func _make_mangling_armed_unit(cell: Vector2i) -> Dictionary:
	var built: Dictionary = _make_armed_unit(cell)
	(built.arm as Part).mangles_into = &"twisted_sheet_metal"
	return built


func test_a_mangling_part_is_replaced_by_its_mangles_into_product() -> void:
	var built: Dictionary = _make_mangling_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(arm, 10.0)
	var dropped: Array[Part] = DamageResolver.drop_subtree_if_destroyed(arm, state)

	var wreckage: Part = null
	for part: Part in dropped:
		if part.id == &"twisted_sheet_metal":
			wreckage = part
	assert_not_null(wreckage, "the mangled arm must be replaced by its own mangles_into product")
	assert_false(
		dropped.has(arm), "the original arm never appears in the field itself once mangled"
	)
	assert_true(
		state.grid.field_items[Vector2i(2, 2)].has(wreckage),
		"the wreckage itself must land as a recoverable field item"
	)


func test_a_mangling_parts_children_drop_as_separate_intact_assemblies() -> void:
	var built: Dictionary = _make_mangling_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var hand: Part = built.hand
	var pistol: Part = built.pistol
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(arm, 10.0)
	var dropped: Array[Part] = DamageResolver.drop_subtree_if_destroyed(arm, state)

	assert_true(dropped.has(hand), "the hand must drop as its own separate assembly")
	assert_false(dropped.has(arm), "the scrapped arm itself is not among the dropped items")
	assert_true(
		PartGraph.walk(hand).has(pistol), "the hand's own subtree (the pistol) rides along with it"
	)
	assert_true(
		state.grid.field_items[Vector2i(2, 2)].has(hand),
		"the detached hand must land as its own recoverable field item"
	)
	# "A corpse holding its own loot" cannot happen anymore: the hand is
	# its own root now, never still hanging off the mangled arm.
	assert_false(PartGraph.walk(arm).has(hand))


## A non-mangling destroyed part never loses its own identity — "a broken
## pistol drops as a broken pistol." `broken` is derived from hp <= 0, not
## a second field: this only ever asserts hp, never a `.broken` property.
func test_a_broken_pistol_is_still_identifiably_a_pistol() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var pistol: Part = built.pistol
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(pistol, 10.0)
	var dropped: Array[Part] = DamageResolver.drop_subtree_if_destroyed(pistol, state)

	assert_eq(dropped, [pistol])
	assert_eq(pistol.id, &"pistol", "identity survives destruction when the part doesn't mangle")
	assert_true(pistol.hp <= 0, "broken is read straight off hp, never a separate flag")


func test_wreckage_yields_its_own_salvage() -> void:
	var wreckage: Part = FieldObjects.twisted_sheet_metal()
	assert_false(wreckage.salvage_yield.is_empty(), "wreckage must actually carry salvage_yield")


func test_a_mangling_parts_own_id_carries_no_salvage_the_wreckage_does() -> void:
	# The original template as authored in the real pool (docs/10
	# taskblock05 D2): a plate mangles into scrap, not the other way
	# around, and the plate itself carries none of the salvage credit.
	var plate := Part.new()
	plate.id = &"plate_medium_sheet_steel"
	plate.mangles_into = &"metal_scraps"
	assert_true(plate.salvage_yield.is_empty())
	assert_false(FieldObjects.metal_scraps().salvage_yield.is_empty())
