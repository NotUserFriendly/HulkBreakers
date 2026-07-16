extends GutTest

## docs/00/04/07: deep strike is the project's randomization stress test.
## The fuzz test below is "the real point" — everything else here just
## proves the individual pieces it depends on.


func _rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


func test_assemble_random_hosts_the_matrix_on_the_root_part() -> void:
	var base := Matrix.new()
	base.id = &"jerry"
	var unit := DeepStrike.assemble_random(
		base, 0.5, DeepStrike.default_part_pool(), _rng(1), Vector2i(0, 0)
	)
	assert_true(unit.frame.root.hosts_matrix())
	assert_eq(unit.frame.root.hosted_matrix.base, base)
	assert_almost_eq(unit.frame.root.hosted_matrix.effective_level(), base.level * 0.5, 0.0001)


func test_assemble_random_is_deterministic_from_the_same_seed() -> void:
	var pool := DeepStrike.default_part_pool()
	var unit_a := DeepStrike.assemble_random(Matrix.new(), 1.0, pool, _rng(42), Vector2i(0, 0))
	var unit_b := DeepStrike.assemble_random(Matrix.new(), 1.0, pool, _rng(42), Vector2i(0, 0))

	var ids_a: Array[StringName] = []
	for part: Part in unit_a.frame.all_parts():
		ids_a.append(part.id)
	var ids_b: Array[StringName] = []
	for part: Part in unit_b.frame.all_parts():
		ids_b.append(part.id)
	assert_eq(ids_a, ids_b)


func test_validate_assembly_passes_a_normal_random_cyborg() -> void:
	var unit := DeepStrike.assemble_random(
		Matrix.new(), 1.0, DeepStrike.default_part_pool(), _rng(7), Vector2i(0, 0)
	)
	assert_eq(DeepStrike.validate_assembly(unit), [] as Array[String])


func test_validate_assembly_catches_a_mass_violation() -> void:
	var unit := DeepStrike.assemble_random(
		Matrix.new(), 1.0, DeepStrike.default_part_pool(), _rng(7), Vector2i(0, 0)
	)
	unit.frame.max_mass = 0.0
	var violations: Array[String] = DeepStrike.validate_assembly(unit)
	assert_true(violations.size() > 0)
	assert_true(violations[0].begins_with("mass"))


func test_is_armed_true_when_a_weapon_has_its_required_manipulators() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	torso.sockets = [Socket.new(&"MATRIX")]
	torso.hosted_matrix = Matrix.new()
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.damage = 5.0
	pistol.requires = {&"TRIGGER": 1}
	var socket := Socket.new(&"GRIP")
	socket.occupant = pistol
	hand.sockets = [socket]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	var unit := Unit.new(Matrix.new(), Frame.new(torso), Vector2i(0, 0))
	assert_true(DeepStrike.is_armed(unit))
	assert_eq(DeepStrike.find_operable_weapon(unit), pistol)


func test_is_armed_false_with_no_weapon_at_all() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	var unit := Unit.new(Matrix.new(), Frame.new(torso), Vector2i(0, 0))
	assert_false(DeepStrike.is_armed(unit))
	assert_null(DeepStrike.find_operable_weapon(unit))


func test_is_armed_false_when_the_weapon_has_no_capable_manipulator() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.damage = 5.0
	pistol.requires = {&"TRIGGER": 1}
	var socket := Socket.new(&"GRIP")
	socket.occupant = pistol
	torso.sockets = [socket]  # no TRIGGER-capable hand anywhere

	var unit := Unit.new(Matrix.new(), Frame.new(torso), Vector2i(0, 0))
	assert_false(DeepStrike.is_armed(unit))


## Taskblock correction 2: before every pool part carried a `volume`, a
## deep-struck cyborg's arms/hands/weapons contributed mass, RAM,
## capabilities, and could fire — but had no geometry, so a burst could only
## ever land on the torso. Find a seed that actually attaches a limb and
## sweep the projected silhouette to prove a non-root part is now reachable.
func test_a_burst_into_a_deep_struck_cyborg_can_hit_a_limb_not_just_the_root() -> void:
	var pool: Array[Part] = DeepStrike.default_part_pool()
	var unit: Unit = null
	for seed_value in range(50):
		var candidate := DeepStrike.assemble_random(
			Matrix.new(), 1.0, pool, _rng(seed_value), Vector2i(0, 0)
		)
		if candidate.frame.living_parts().size() > 1:
			unit = candidate
			break
	assert_not_null(unit, "expected at least one of 50 seeds to attach a limb")

	var regions: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))
	print("\n=== deep-struck cyborg silhouette (limb-hit sweep) ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(regions, 2.0), 4, 2))

	var hit_parts: Array[StringName] = []
	var x := -2.0
	while x <= 2.0:
		var region: Region = ShotPlane.resolve_projectile(regions, Vector2(x, 0.5))
		if region != null and not hit_parts.has(region.part.id):
			hit_parts.append(region.part.id)
		x += 0.05

	var hit_a_limb := false
	for part_id: StringName in hit_parts:
		if part_id != unit.frame.root.id:
			hit_a_limb = true
			break
	assert_true(
		hit_a_limb,
		"a sweep across the silhouette only ever hit the root: %s" % [hit_parts]
	)


## docs/07's "real point": no crashes, no malformed assemblies, across many
## seeds and arbitrary part combinations.
func test_fuzz_many_random_cyborgs_never_crash_and_always_validate() -> void:
	var pool: Array[Part] = DeepStrike.default_part_pool()
	const SEED_COUNT := 200
	for seed_value in range(SEED_COUNT):
		var unit := DeepStrike.assemble_random(
			Matrix.new(), 1.0, pool, _rng(seed_value), Vector2i(0, 0)
		)

		var violations: Array[String] = DeepStrike.validate_assembly(unit)
		assert_eq(
			violations,
			[] as Array[String],
			"seed %d produced a malformed assembly: %s" % [seed_value, violations]
		)

		# Must project a sane shot plane: no crash, and the unit is actually
		# visible from at least one angle (it always has a root part).
		var regions: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))
		assert_true(regions.size() > 0, "seed %d produced an unprojectable unit" % seed_value)

		# Armed or knowably unarmed — never an exception either way.
		var armed: bool = DeepStrike.is_armed(unit)
		assert_true(armed == true or armed == false)
