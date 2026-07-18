extends GutTest

## taskblock-13 Pass H: harden the gun sim against the cases that don't
## come up in a normal battle and therefore rot silently. All seeded, all
## deterministic, all must terminate — no crash, no non-termination, no
## NaN/degenerate scatter.

## Throwaway root, never the real `res://data`/`user://data` — same
## contract test_data_library.gd's own header documents. A couple of
## tests here save a fixture AmmoDef through DataLibrary.save (its
## `get_ammo` always hands back a fresh duplicate; a locally mutated
## instance never reaches what BurstAction itself fetches unless it's
## actually persisted first), and this is where that write must land
## instead of the player's real save data.
const TEST_USER_ROOT := "user://test_weapon_sim_hardening"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all(DataLibrary.BUILTIN_ROOT, TEST_USER_ROOT)


func after_each() -> void:
	DataLibrary.reset()
	_remove_dir_recursive(TEST_USER_ROOT)


func _remove_dir_recursive(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	var dir: DirAccess = DirAccess.open(absolute)
	if dir == null:
		return
	var ammo_dir: DirAccess = DirAccess.open(absolute + "/ammo")
	if ammo_dir != null:
		ammo_dir.list_dir_begin()
		var file_name: String = ammo_dir.get_next()
		while file_name != "":
			if not ammo_dir.current_is_dir():
				ammo_dir.remove(file_name)
			file_name = ammo_dir.get_next()
		ammo_dir.list_dir_end()
		DirAccess.remove_absolute(absolute + "/ammo")
	DirAccess.remove_absolute(absolute)


func _weapon(
	id: StringName, burst_size: int, mechanical_accuracy: float = 0.9, barrel_length: float = 1.0
) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.hp = 6
	weapon.max_hp = 6
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 2.0
	weapon.scatter = [Ring.new(0.1, 1.0)]
	weapon.provides_actions = [&"burst"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.burst_size = burst_size
	weapon.weapon_def.burst_ap_cost = 1
	weapon.weapon_def.mechanical_accuracy = mechanical_accuracy
	weapon.weapon_def.barrel_length = barrel_length
	return weapon


func _shooter(weapon: Part) -> Unit:
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var torso := Part.new()
	torso.id = &"shooter_torso"
	torso.hp = 20
	torso.max_hp = 20
	torso.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.3))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]
	return Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)


func _target(hp: int = 5000, material: StringName = &"") -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.material = material
	torso.hp = hp
	torso.max_hp = hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), Vector2i(3, 0), 1)


func _fire_twice(build: Callable) -> Array:
	var results: Array = []
	for run in range(2):
		results.append(build.call())
	return results


## `burst_size` of 1: BurstAction itself refuses it (there's no burst mode
## at all below 2) — the correct, documented handling of this extreme,
## not a crash.
func test_burst_size_of_one_is_cleanly_rejected_as_illegal() -> void:
	var weapon := _weapon(&"gun", 1)
	var shooter := _shooter(weapon)
	var target := _target()
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])

	assert_false(BurstAction.new(shooter, &"gun", Vector2i(3, 0)).is_legal(state))


## `burst_size` of a very large N: must still terminate, deterministically.
func test_a_very_large_burst_size_still_terminates_and_replays_identically() -> void:
	var results: Array = _fire_twice(
		func() -> int:
			var weapon := _weapon(&"gun", 200)
			weapon.weapon_def.burst_ap_cost = 1
			var shooter := _shooter(weapon)
			shooter.ap = 1000
			var target := _target()
			var state := CombatState.new(Grid.new(10, 10), [shooter, target], 555)
			BurstAction.new(shooter, &"gun", Vector2i(3, 0)).apply(state)
			return target.shell.root.hp
	)
	assert_eq(results[0], results[1])


## A fixture round saved for real through DataLibrary — `get_ammo`
## always hands back a fresh duplicate (taskblock-10 B), so a locally
## mutated AmmoDef instance never reaches what BurstAction itself
## fetches unless it's actually persisted first.
func _save_ammo(id: StringName, projectile_num: int) -> void:
	var ammo := AmmoDef.new()
	ammo.id = id
	ammo.projectile_num = projectile_num
	assert_eq(DataLibrary.save(DataLibrary.TYPE_AMMO, ammo), [] as Array[ValidationError])


## `projectile_num` of 1 and of many, both via the real firing path.
func test_projectile_num_of_one_and_of_many_both_terminate_cleanly() -> void:
	for projectile_num: int in [1, 50]:
		_save_ammo(&"hardening_test_round", projectile_num)
		var weapon := _weapon(&"gun", 3)
		weapon.ammo_id = &"hardening_test_round"
		var shooter := _shooter(weapon)
		var target := _target()
		var state := CombatState.new(Grid.new(10, 10), [shooter, target], 1)
		var sink := MemorySink.new()
		state.combat_log.add_sink(sink)

		BurstAction.new(shooter, &"gun", Vector2i(3, 0)).apply(state)

		assert_eq(
			sink.events_of_kind(&"impact").size(),
			3 * projectile_num,
			"projectile_num %d: 3 pulls x %d pellets" % [projectile_num, projectile_num]
		)


## A large burst of a high-pellet round at once — hundreds of rays in one
## activation, still bounded and terminating.
func test_a_large_burst_of_a_high_pellet_round_terminates() -> void:
	_save_ammo(&"hardening_test_round", 20)
	var weapon := _weapon(&"gun", 30)
	weapon.weapon_def.burst_ap_cost = 1
	weapon.ammo_id = &"hardening_test_round"
	var shooter := _shooter(weapon)
	shooter.ap = 100
	var target := _target()
	var state := CombatState.new(Grid.new(10, 10), [shooter, target], 2)
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BurstAction.new(shooter, &"gun", Vector2i(3, 0)).apply(state)

	assert_eq(sink.events_of_kind(&"impact").size(), 30 * 20, "30 pulls x 20 pellets = 600 rays")


## `mechanical_accuracy` at the degenerate extremes — perfect and useless
## — neither may produce NaN/inf or a crash.
func test_mechanical_accuracy_at_zero_and_one_both_produce_finite_points() -> void:
	for accuracy: float in [0.0, 1.0]:
		var weapon := _weapon(&"gun", 2, accuracy)
		var ammo := AmmoDef.new()
		ammo.projectile_num = 12
		var rng := RandomNumberGenerator.new()
		rng.seed = 9

		var points: Array[Vector2] = SpreadPattern.sample(Vector2.ZERO, weapon, ammo, rng)

		assert_eq(points.size(), 12)
		for p: Vector2 in points:
			assert_false(is_nan(p.x) or is_nan(p.y))
			assert_false(is_inf(p.x) or is_inf(p.y))


## Perfect accuracy (1.0): every pellet must land exactly on the center —
## base_pattern(1.0) collapses the radius to 0.
func test_perfect_mechanical_accuracy_collapses_the_pattern_to_the_center() -> void:
	var weapon := _weapon(&"gun", 2, 1.0)
	var ammo := AmmoDef.new()
	ammo.projectile_num = 8
	var rng := RandomNumberGenerator.new()
	rng.seed = 4

	for p: Vector2 in SpreadPattern.sample(Vector2.ZERO, weapon, ammo, rng):
		assert_almost_eq(p.x, 0.0, 0.0001)
		assert_almost_eq(p.y, 0.0, 0.0001)


## Zero and a very long `barrel_length` — recoil/spread at the extremes,
## both finite, neither a crash (BarrelFactor's own floor is what makes
## zero safe).
func test_zero_and_very_long_barrel_length_produce_finite_recoil_and_spread() -> void:
	for barrel_length: float in [0.0, 1000.0]:
		var weapon := _weapon(&"gun", 2, 0.5, barrel_length)

		var recoil: float = RecoilResolver.step_amount(weapon, 6.0)
		assert_false(is_nan(recoil) or is_inf(recoil))
		assert_gt(recoil, 0.0)

		var ammo := AmmoDef.new()
		ammo.projectile_num = 9
		var rng := RandomNumberGenerator.new()
		rng.seed = 6
		for p: Vector2 in SpreadPattern.sample(Vector2.ZERO, weapon, ammo, rng):
			assert_false(is_nan(p.x) or is_nan(p.y))
			assert_false(is_inf(p.x) or is_inf(p.y))


## A cartridge exactly at `max_case_length` — the boundary of chambering,
## legal (`<=`, never `<`).
func test_a_cartridge_exactly_at_max_case_length_chambers() -> void:
	var weapon := Part.new()
	weapon.id = &"gun"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.accepts_family = &"TEST"
	weapon.weapon_def.max_case_length = 50.0
	var test_round := AmmoDef.new()
	test_round.id = &"boundary_round"
	test_round.case_family = &"TEST"
	test_round.case_length = 50.0

	assert_eq(
		WeaponResolver.chamber_error(weapon, test_round),
		"",
		"exactly at the limit must still chamber"
	)

	test_round.case_length = 50.0001
	assert_ne(
		WeaponResolver.chamber_error(weapon, test_round),
		"",
		"a hair over the limit must still reject"
	)


## "Recoil accumulation across a long burst not diverging to nonsense" —
## a 100-pull burst's own last step must still be finite and, while
## larger than the first, bounded in a way that stays a real number, not
## an overflow/NaN.
func test_recoil_does_not_diverge_across_a_long_burst() -> void:
	var weapon := _weapon(&"gun", 2, 0.9, 0.3)  # short barrel: recoil matters
	var step: float = WeaponResolver.resolve_recoil_step(weapon, 6.0).current
	var scatter: Array[Ring] = [Ring.new(0.1, 1.0)]

	var widened: Array[Ring] = RecoilResolver.widen(scatter, step, 99)  # pull 100 of 100

	assert_false(is_nan(widened[0].radius) or is_inf(widened[0].radius))
	assert_gt(widened[0].radius, scatter[0].radius, "100 accumulated steps must still be wider")


## "Ricochet depth cap holding under a burst that generates many
## simultaneous deflections" — a burst into a wide ring of angled plates
## (Pass G's own rig shape), all sub-DT, all deflecting: the sim must
## still terminate and stay seed-deterministic no matter how many
## simultaneous ricochets that produces.
func test_ricochet_depth_cap_holds_under_a_burst_of_many_simultaneous_deflections() -> void:
	var results: Array = _fire_twice(
		func() -> int:
			var rig := Part.new()
			rig.id = &"stress_rig"
			rig.hp = 200
			rig.max_hp = 200
			rig.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.3))]
			var sockets: Array[Socket] = []
			for angle_deg in range(-80, 81, 20):
				var socket := Socket.new(
					&"ARMOR", Transform3D(Basis(Vector3.UP, deg_to_rad(angle_deg)), Vector3.ZERO)
				)
				socket.occupant = DataLibrary.get_part(&"wedge_plate_shallow")
				sockets.append(socket)
			rig.sockets = sockets

			var weapon := _weapon(&"gun", 20)
			weapon.damage = 3.0  # sub-DT vs steel (6): every hit is a real deflection
			weapon.weapon_def.burst_ap_cost = 1
			var shooter := _shooter(weapon)
			shooter.ap = 100
			var target := Unit.new(Matrix.new(), Shell.new(rig), Vector2i(3, 0), 1)
			var state := CombatState.new(Grid.new(10, 10), [shooter, target], 123)

			BurstAction.new(shooter, &"gun", Vector2i(3, 0)).apply(state)
			return target.shell.root.hp
	)
	assert_eq(results[0], results[1], "many simultaneous deflections must still replay identically")
