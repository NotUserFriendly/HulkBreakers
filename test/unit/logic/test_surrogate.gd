extends GutTest

## docs/04 taskblock02 Pass D: surrogates dock like everything else.
## Fixtures deliberately don't touch the shared reference-humanoid pool —
## a torso with a single SURROGATE_SPINAL socket is enough to prove the
## general mechanism (CLAUDE.md: "if a test needs a concrete list, the
## test authors it as a fixture").


func _spinal_only_torso() -> Part:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.7, 0.3))]
	torso.material = &"artificial_bone"
	torso.sockets = [
		Socket.new(&"SURROGATE_SPINAL", Transform3D.IDENTITY, BodyAssembler.SURROGATE_SOCKET_ID),
		Socket.new(&"MATRIX", Transform3D.IDENTITY, &"MATRIX"),
	]
	return torso


func _template() -> ShellTemplate:
	return ShellTemplate.new(&"torso", [], 500.0, 50.0)


func _tier(id: StringName, ladder: Array[SurrogateTier]) -> SurrogateTier:
	for tier: SurrogateTier in ladder:
		if tier.id == id:
			return tier
	fail_test("no tier %s in ladder" % id)
	return null


func test_a_bare_matrix_cannot_dock_where_only_a_surrogate_socket_exists() -> void:
	var pool := {&"torso": _spinal_only_torso()}
	var template := ShellTemplate.new(&"torso_no_matrix", [], 500.0, 50.0)
	var bare_torso := Part.new()
	bare_torso.id = &"torso_no_matrix"
	bare_torso.hp = 10
	bare_torso.max_hp = 10
	bare_torso.sockets = [
		Socket.new(&"SURROGATE_SPINAL", Transform3D.IDENTITY, &"SURROGATE_SPINAL")
	]
	pool[&"torso_no_matrix"] = bare_torso

	var unit: Unit = BodyAssembler.assemble(template, null, pool, Matrix.new(), Vector2i(0, 0))

	assert_null(unit)
	assert_push_error("cannot host a matrix")


func test_a_full_surrogate_cannot_dock_in_a_spinal_only_socket_rank_too_big() -> void:
	var ladder := SurrogateLadder.default_ladder()
	var pool := {&"torso": _spinal_only_torso()}

	var unit: Unit = BodyAssembler.assemble_cyborg(
		_template(), null, pool, Matrix.new(), _tier(&"FULL", ladder), ladder, Vector2i(0, 0)
	)

	assert_null(unit)
	assert_push_error("cannot attach")


func test_a_spinal_surrogate_can_dock_in_its_own_socket() -> void:
	var ladder := SurrogateLadder.default_ladder()
	var pool := {&"torso": _spinal_only_torso()}

	var unit: Unit = BodyAssembler.assemble_cyborg(
		_template(), null, pool, Matrix.new(), _tier(&"SPINAL", ladder), ladder, Vector2i(0, 0)
	)

	assert_not_null(unit)


func test_a_brain_only_surrogate_also_fits_a_spinal_socket_smaller_fits_bigger() -> void:
	var ladder := SurrogateLadder.default_ladder()
	var pool := {&"torso": _spinal_only_torso()}

	var unit: Unit = BodyAssembler.assemble_cyborg(
		_template(), null, pool, Matrix.new(), _tier(&"BRAIN_ONLY", ladder), ladder, Vector2i(0, 0)
	)

	assert_not_null(unit)


func test_attaches_to_is_derived_so_a_new_ladder_rung_updates_every_surrogate() -> void:
	var custom_ladder: Array[SurrogateTier] = [
		SurrogateTier.new(&"FULL", "Full", 0, &"SURROGATE_FULL", []),
		SurrogateTier.new(
			&"HALF", "Half — a rung nobody hand-edited anything for", 1, &"SURROGATE_HALF", []
		),
		SurrogateTier.new(&"BRAIN_ONLY", "Brain", 2, &"SURROGATE_BRAIN", []),
	]
	var full: Array[StringName] = SurrogateLadder.derive_attaches_to(
		custom_ladder[0], custom_ladder
	)
	var half: Array[StringName] = SurrogateLadder.derive_attaches_to(
		custom_ladder[1], custom_ladder
	)
	var brain: Array[StringName] = SurrogateLadder.derive_attaches_to(
		custom_ladder[2], custom_ladder
	)

	assert_eq(full, [&"SURROGATE_FULL"])
	assert_eq(half, [&"SURROGATE_FULL", &"SURROGATE_HALF"])
	assert_eq(brain, [&"SURROGATE_FULL", &"SURROGATE_HALF", &"SURROGATE_BRAIN"])


func test_the_matrix_docks_inside_the_surrogate_and_unit_resolves_it_through_two_levels() -> void:
	var ladder := SurrogateLadder.default_ladder()
	var pool := {&"torso": _spinal_only_torso()}
	var matrix := Matrix.new()

	var unit: Unit = BodyAssembler.assemble_cyborg(
		_template(), null, pool, matrix, _tier(&"SPINAL", ladder), ladder, Vector2i(0, 0)
	)

	assert_null(unit.shell.root.hosted_matrix, "the shell root itself never hosts it directly")
	var surrogate: Part = (
		PartGraph.find_socket(unit.shell.root, BodyAssembler.SURROGATE_SOCKET_ID).occupant
	)
	assert_eq(surrogate.hosted_matrix, matrix, "the surrogate hosts it, one level down")
	assert_eq(unit.resolve_matrix(), matrix, "Unit resolves it by walking the tree either way")


func test_destroying_the_torso_drops_the_surrogate_with_the_matrix_in_it() -> void:
	var ladder := SurrogateLadder.default_ladder()
	var pool := {&"torso": _spinal_only_torso()}
	var matrix := Matrix.new()
	var unit: Unit = BodyAssembler.assemble_cyborg(
		_template(), null, pool, matrix, _tier(&"SPINAL", ladder), ladder, Vector2i(3, 3)
	)
	var surrogate: Part = (
		PartGraph.find_socket(unit.shell.root, BodyAssembler.SURROGATE_SOCKET_ID).occupant
	)
	var state := CombatState.new(Grid.new(10, 10), [unit])

	unit.shell.root.hp = 0
	var ejected: Part = DamageResolver.eject_surrogate_if_needed(unit.shell.root, state)

	assert_eq(ejected, surrogate)
	assert_eq(ejected.hosted_matrix, matrix, "the matrix travels with it, not left behind")
	assert_has(state.grid.field_items[unit.cell], surrogate)
	assert_false(unit.alive, "the unit goes unpiloted")
	assert_null(
		DamageResolver.eject_matrix_if_needed(unit.shell.root, state),
		"the root itself never hosted a bare matrix directly"
	)


func test_destroying_the_surrogate_itself_ejects_a_bare_matrix() -> void:
	var ladder := SurrogateLadder.default_ladder()
	var pool := {&"torso": _spinal_only_torso()}
	var matrix := Matrix.new()
	var unit: Unit = BodyAssembler.assemble_cyborg(
		_template(), null, pool, matrix, _tier(&"SPINAL", ladder), ladder, Vector2i(1, 1)
	)
	var surrogate: Part = (
		PartGraph.find_socket(unit.shell.root, BodyAssembler.SURROGATE_SOCKET_ID).occupant
	)
	var state := CombatState.new(Grid.new(10, 10), [unit])

	surrogate.hp = 0
	var ejected: Matrix = DamageResolver.eject_matrix_if_needed(surrogate, state)

	assert_eq(ejected, matrix)
	assert_null(surrogate.hosted_matrix)
	assert_has(state.grid.field_items[unit.cell], matrix)
	assert_false(unit.alive)


## SPINAL grants no LOCOMOTION at all (docs/04: torso+head only, no limbs).
func test_a_part_needing_a_capability_the_surrogate_lacks_is_inert_but_still_shootable() -> void:
	var ladder := SurrogateLadder.default_ladder()
	var pool := {&"torso": _spinal_only_torso()}
	var unit: Unit = BodyAssembler.assemble_cyborg(
		_template(), null, pool, Matrix.new(), _tier(&"SPINAL", ladder), ladder, Vector2i(0, 0)
	)
	var leg := Part.new()
	leg.id = &"leg"
	leg.hp = 4
	leg.max_hp = 4
	leg.body_requires = [&"LOCOMOTION"]
	leg.volume = [Box.new(Vector3.ZERO, Vector3(0.1, 0.5, 0.1))]
	unit.shell.root.contents.append(leg)  # attachment point irrelevant to this test

	assert_false(unit.can_use_part(leg, ladder), "SPINAL grants no LOCOMOTION")
	assert_true(leg.hp > 0, "inert never means destroyed")


func test_a_part_needing_a_capability_the_surrogate_has_is_usable() -> void:
	var ladder := SurrogateLadder.default_ladder()
	# FULL (rank 0, carries LOCOMOTION) needs a cavity roomy enough for it —
	# the SPINAL-only fixture above is deliberately too small for this one.
	var torso := _spinal_only_torso()
	torso.sockets[0].socket_type = &"SURROGATE_FULL"
	var pool := {&"torso": torso}
	var unit: Unit = BodyAssembler.assemble_cyborg(
		_template(), null, pool, Matrix.new(), _tier(&"FULL", ladder), ladder, Vector2i(0, 0)
	)
	var leg := Part.new()
	leg.id = &"leg"
	leg.body_requires = [&"LOCOMOTION"]

	assert_true(unit.can_use_part(leg, ladder))


func test_a_part_with_no_body_requires_is_always_usable_even_unpiloted() -> void:
	var pool := {&"torso": _spinal_only_torso()}
	var unit: Unit = BodyAssembler.assemble(_template(), null, pool, Matrix.new(), Vector2i(0, 0))
	var plate := Part.new()
	plate.id = &"plate"

	assert_true(unit.can_use_part(plate, SurrogateLadder.default_ladder()))
