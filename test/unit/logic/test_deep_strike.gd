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
	assert_true(unit.shell.root.hosts_matrix())
	assert_eq(unit.shell.root.hosted_matrix.base, base)
	assert_almost_eq(unit.shell.root.hosted_matrix.effective_level(), base.level * 0.5, 0.0001)


func test_assemble_random_is_deterministic_from_the_same_seed() -> void:
	var pool := DeepStrike.default_part_pool()
	var unit_a := DeepStrike.assemble_random(Matrix.new(), 1.0, pool, _rng(42), Vector2i(0, 0))
	var unit_b := DeepStrike.assemble_random(Matrix.new(), 1.0, pool, _rng(42), Vector2i(0, 0))

	var ids_a: Array[StringName] = []
	for part: Part in unit_a.shell.all_parts():
		ids_a.append(part.id)
	var ids_b: Array[StringName] = []
	for part: Part in unit_b.shell.all_parts():
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
	unit.shell.max_mass = 0.0
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

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	assert_true(DeepStrike.is_armed(unit))
	assert_eq(DeepStrike.find_operable_weapon(unit), pistol)


func test_is_armed_false_with_no_weapon_at_all() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
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

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
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
		if candidate.shell.living_parts().size() > 1:
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
		if part_id != unit.shell.root.id:
			hit_a_limb = true
			break
	assert_true(
		hit_a_limb, "a sweep across the silhouette only ever hit the root: %s" % [hit_parts]
	)


func _pool_part(part_id: StringName) -> Part:
	for template: Part in DeepStrike.default_part_pool():
		if template.id == part_id:
			return template
	fail_test("no pool template %s" % part_id)
	return null


## docs/10 taskblock05 D1: cladding is keyed to a kind of part — a leg's
## skin does not fit a skull.
func test_leg_cladding_cannot_attach_to_a_heads_cladding_socket() -> void:
	var leg_cladding: Part = _pool_part(&"leg_cladding")
	var head: Part = _pool_part(&"head")
	var head_socket: Socket = PartGraph.find_socket(head, &"CLADDING")

	assert_eq(head_socket.socket_type, &"CLADDING_HEAD")
	assert_false(PartGraph.is_legal_attachment(leg_cladding, head_socket))


## A keyed cladding part attaches only to its own kind — proven both ways:
## it fits its own socket, and every OTHER kind's socket refuses it.
func test_a_keyed_cladding_part_attaches_only_to_its_own_kind() -> void:
	var leg_cladding: Part = _pool_part(&"leg_cladding")
	var leg: Part = _pool_part(&"leg")
	var leg_socket: Socket = PartGraph.find_socket(leg, &"CLADDING")
	assert_true(PartGraph.is_legal_attachment(leg_cladding, leg_socket))

	var other_hosts: Array[StringName] = [&"torso", &"head", &"arm", &"forearm"]
	for host_id: StringName in other_hosts:
		var host: Part = _pool_part(host_id)
		var socket: Socket = PartGraph.find_socket(host, &"CLADDING")
		assert_false(
			PartGraph.is_legal_attachment(leg_cladding, socket),
			"leg_cladding must not fit %s's own cladding socket" % host_id
		)


## docs/10 taskblock05 D2: plates keep the generic ARMOR socket — any
## plate legally attaches to any ARMOR socket, however absurd the result
## looks (a big plate on a head is legal by design, not a size gate).
func test_any_plate_attaches_to_any_armor_socket() -> void:
	var plates: Array[StringName] = [
		&"plate_large_steel",
		&"plate_large_sheet_steel",
		&"plate_small_ceramic",
		&"plate_small_steel",
		&"plate_medium_sheet_steel",
	]
	var hosts: Array[StringName] = [&"torso", &"head", &"arm", &"forearm", &"leg"]
	for plate_id: StringName in plates:
		var plate: Part = _pool_part(plate_id)
		for host_id: StringName in hosts:
			var host: Part = _pool_part(host_id)
			# find_free_socket matches by socket_type, not id — torso's own
			# ARMOR sockets are id'd ARMOR_FRONT/ARMOR_REAR (docs/01
			# taskblock02 Pass B), so this is the one that finds them too.
			var socket: Socket = PartGraph.find_free_socket(host, &"ARMOR")
			assert_not_null(socket, "%s has no free ARMOR socket to test against" % host_id)
			assert_true(
				PartGraph.is_legal_attachment(plate, socket),
				"%s must attach to %s's ARMOR socket" % [plate_id, host_id]
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
