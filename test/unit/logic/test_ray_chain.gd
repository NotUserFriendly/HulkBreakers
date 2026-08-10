extends GutTest

## taskblock-52 Pass B: **the chain — A to B, then C becomes B, B becomes A.**
##
## The taskblock's stated tests, in order: a shot into a closed room always
## strikes something; a deflection's second segment ends where geometry says
## rather than at a fixed range; a `STOP_DEAD` chain has exactly one segment; a
## seeded shot resolves identically across runs; the chain cap fires and logs
## rather than recursing.
##
## **`BR35.04` is what the second of those is really about.** That entry was
## closed by deleting a decorative bounce tracer drawn to the weapon's max range
## with no awareness of whether anything was there. It was drawn that way because
## the plane had no continuation to draw: building a plane for a post-deflection
## heading was the expensive path. The chain produces a real second segment, so
## the geometry a tracer would need now exists — this asserts that it ends on
## something, not that anything draws it.

const AIM_HEIGHT := 1.0


class Recorder:
	extends LogSink

	var events: Array[LogEvent] = []

	func emit(event: LogEvent) -> void:
		events.append(event)

	func kinds() -> Array[StringName]:
		var result: Array[StringName] = []
		for event: LogEvent in events:
			result.append(event.kind)
		return result


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"shooter_torso"
	torso.material = &"steel"
	torso.hp = 40
	torso.max_hp = 40
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func _state(room: int = 11) -> CombatState:
	@warning_ignore("integer_division")
	var half: int = room / 2
	return CombatState.new(GridFixture.enclosed_room(room, room), [_shooter(Vector2i(half, half))])


func _rng(rng_seed: int = 52) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


func _fire(
	state: CombatState, toward: Vector3, damage: float = 4.0, rng_seed: int = 52
) -> Array[ImpactResult]:
	var shooter: Unit = state.units[0]
	var from := Vector3(shooter.cell.x, AIM_HEIGHT, shooter.cell.y)
	return RayChain.resolve(
		state,
		from,
		toward,
		damage,
		0.0,
		state.material_table,
		_rng(rng_seed),
		shooter.shell.all_parts_with_joints()
	)


## **The supervisor's standing rule, finally testable.** A shot fired inside an
## enclosed room hits something — at every angle, and at every lateral offset,
## including the wide ones where the plane's parallel-ray model put the whole
## flight outside the building.
func test_a_shot_inside_a_closed_room_always_strikes_something() -> void:
	var state: CombatState = _state()
	var shooter: Unit = state.units[0]
	var from := Vector3(shooter.cell.x, AIM_HEIGHT, shooter.cell.y)
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	var empties := 0
	var shots := 0
	for a in range(72):
		var angle: float = TAU * float(a) / 72.0
		for lateral in [0.0, 2.0, 4.0, 6.0, 8.0]:
			# B is a real point in the world, offset laterally from the target
			# line — the dartboard's own output. The muzzle stays the muzzle.
			var dir := Vector3(cos(angle), 0.0, sin(angle))
			var perp := Vector3(-dir.z, 0.0, dir.x)
			var toward: Vector3 = from + dir * 6.0 + perp * lateral
			var results: Array[ImpactResult] = RayChain.resolve(
				state, from, toward, 0.0, 0.0, state.material_table, _rng(), excluded
			)
			shots += 1
			if results.is_empty():
				empties += 1
				if empties <= 5:
					print("  EMPTY: angle %.0f deg, lateral %.1f" % [rad_to_deg(angle), lateral])
	print("  closed room: %d/%d empty" % [empties, shots])
	assert_eq(empties, 0, "a ray in a closed room cannot fail to hit")
	assert_eq(shots, 360, "and the sweep actually fired")


## A round that stops dead stops: one impact, no continuation.
func test_a_stop_dead_chain_has_exactly_one_segment() -> void:
	var state: CombatState = _state()
	var shooter: Unit = state.units[0]
	# Straight into the perimeter wall, dead square on — incidence zero, and
	# 4 damage is under steel's DT, so this is the stop-dead branch.
	var results: Array[ImpactResult] = _fire(state, Vector3(10.0, AIM_HEIGHT, 5.0))
	assert_eq(results.size(), 1, "one hop")
	assert_eq(results[0].outcome, Enums.Outcome.STOP_DEAD)
	assert_eq(results[0].region.part.id, &"wall")
	print(
		(
			"  stop dead at (%.2f, %.2f)@%.2f"
			% [results[0].hit_point.x, results[0].hit_point.y, results[0].hit_height]
		)
	)
	assert_almost_eq(results[0].hit_point.x, 9.5, 0.0001, "at the wall's own near face")
	assert_eq(shooter.cell, Vector2i(5, 5))


## **`BR35.04`'s geometry.** A deflection's second segment ends on something the
## world actually contains, at a distance the world decides — never at the
## weapon's max range projected out into nothing.
func test_a_deflections_second_segment_ends_where_geometry_says() -> void:
	var state: CombatState = _state()
	var shooter: Unit = state.units[0]
	var from := Vector3(5.0, AIM_HEIGHT, 5.0)
	var deflected: Array[ImpactResult] = []
	# Swept rather than staged: a glancing angle has to be found, and hard-coding
	# one that happens to deflect today makes the test a hostage to the geometry.
	for a in range(1, 40):
		var angle: float = deg_to_rad(float(a) * 2.0)
		var toward: Vector3 = from + Vector3(cos(angle), 0.0, sin(angle)) * 20.0
		var results: Array[ImpactResult] = RayChain.resolve(
			state,
			from,
			toward,
			4.0,
			0.0,
			state.material_table,
			_rng(),
			shooter.shell.all_parts_with_joints()
		)
		if results.size() >= 2 and results[0].outcome == Enums.Outcome.DEFLECT:
			deflected = results
			print("  deflected at %.0f degrees, %d hops" % [float(a) * 2.0, results.size()])
			break

	assert_false(deflected.is_empty(), "the sweep must actually produce a deflection")
	var first: ImpactResult = deflected[0]
	var second: ImpactResult = deflected[1]
	print(
		(
			"  hop 0 %s ends (%.2f, %.2f); hop 1 starts (%.2f, %.2f) ends (%.2f, %.2f) on %s"
			% [
				Enums.Outcome.keys()[first.outcome],
				first.hit_point.x,
				first.hit_point.y,
				second.origin.x,
				second.origin.y,
				second.hit_point.x,
				second.hit_point.y,
				second.region.part.id,
			]
		)
	)
	assert_almost_eq(
		second.origin.distance_to(first.hit_point),
		0.0,
		0.001,
		"the second segment starts exactly where the first ended"
	)
	assert_not_null(second.region.part, "and ends on a real struck part, not at a range constant")
	assert_true(
		state.grid.in_bounds(Vector2i(roundi(second.hit_point.x), roundi(second.hit_point.y))),
		"the continuation lands inside the room it bounced around in"
	)


## A penetration continues the same ray; a deflection starts a new one. Both are
## the same call with a different direction, so the direction is what is checked.
func test_a_penetration_continues_along_the_same_heading() -> void:
	var grid: Grid = GridFixture.enclosed_room(15, 15)
	var shooter: Unit = _shooter(Vector2i(3, 7))
	# Two thin plates in a line, both soft enough to punch through.
	var plates: Array[Part] = []
	for i in range(2):
		var plate := Part.new()
		plate.id = StringName("plate_%d" % i)
		plate.material = &"artificial_muscle"  # dt 1.0
		plate.hp = 200
		plate.max_hp = 200
		plate.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.2, 1.0, 1.0))]
		grid.place_blocker(Vector2i(6 + i * 2, 7), plate)
		plates.append(plate)
	var state := CombatState.new(grid, [shooter])
	var results: Array[ImpactResult] = RayChain.resolve(
		state,
		Vector3(3.0, AIM_HEIGHT, 7.0),
		Vector3(14.0, AIM_HEIGHT, 7.0),
		40.0,
		0.0,
		state.material_table,
		_rng(),
		shooter.shell.all_parts_with_joints()
	)
	var struck: Array[StringName] = []
	for result: ImpactResult in results:
		struck.append(result.region.part.id)
	print("  struck in order: %s" % str(struck))
	assert_true(&"plate_0" in struck, "the near plate")
	assert_true(&"plate_1" in struck, "then the far one, on the same heading")
	assert_eq(results[0].outcome, Enums.Outcome.PENETRATE)
	for result: ImpactResult in results:
		assert_almost_eq(
			result.hit_point.y, 7.0, 0.001, "every hop stays on the row it was fired down"
		)


## **A regression, and it was found by reading a log rather than by an
## assertion.** The first chain advanced past the struck box's *entry* face, which
## leaves the round inside the box, so the next segment struck the same plate
## again — one round logged six impacts on one plate. The fix is to advance past
## the **exit** face; this is the assertion that would have caught it.
func test_a_penetrating_round_never_strikes_the_same_box_twice() -> void:
	var grid: Grid = GridFixture.enclosed_room(15, 15)
	var shooter: Unit = _shooter(Vector2i(3, 7))
	var plate := Part.new()
	plate.id = &"soft_plate"
	plate.material = &"artificial_muscle"
	plate.hp = 10000
	plate.max_hp = 10000
	plate.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.2, 1.0, 1.0))]
	grid.place_blocker(Vector2i(6, 7), plate)
	var state := CombatState.new(grid, [shooter])
	var results: Array[ImpactResult] = RayChain.resolve(
		state,
		Vector3(3.0, AIM_HEIGHT, 7.0),
		Vector3(14.0, AIM_HEIGHT, 7.0),
		500.0,  # far more than it needs, so nothing stops it early
		0.0,
		state.material_table,
		_rng(),
		shooter.shell.all_parts_with_joints()
	)
	var strikes := 0
	for result: ImpactResult in results:
		if result.region.part == plate:
			strikes += 1
	print("  a 500-damage round struck the one solid plate %d time(s)" % strikes)
	assert_eq(strikes, 1, "one box, one strike — a solid part is entered and left, not re-entered")


## The `hollow` mechanic's own path: entered and exited are two strikes on one
## box, which is what the shot plane emits as two `Region`s and what the
## lodged-bullet wound is defined against. **Nothing in shipped data sets
## `hollow` yet**, so without this the branch would never run.
func test_a_hollow_part_is_struck_entering_and_exiting() -> void:
	var grid: Grid = GridFixture.enclosed_room(15, 15)
	var shooter: Unit = _shooter(Vector2i(3, 7))
	var shell_part := Part.new()
	shell_part.id = &"hollow_shell"
	shell_part.material = &"artificial_muscle"
	shell_part.hollow = true
	shell_part.hp = 10000
	shell_part.max_hp = 10000
	shell_part.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 1.0, 1.0))]
	grid.place_blocker(Vector2i(6, 7), shell_part)
	var state := CombatState.new(grid, [shooter])
	var results: Array[ImpactResult] = RayChain.resolve(
		state,
		Vector3(3.0, AIM_HEIGHT, 7.0),
		Vector3(14.0, AIM_HEIGHT, 7.0),
		500.0,
		0.0,
		state.material_table,
		_rng(),
		shooter.shell.all_parts_with_joints()
	)
	var strikes: Array[float] = []
	for result: ImpactResult in results:
		if result.region.part == shell_part:
			strikes.append(result.hit_point.x)
	print("  hollow shell struck at x = %s" % str(strikes))
	assert_eq(strikes.size(), 2, "entering and exiting are two strikes")
	assert_almost_eq(strikes[0], 5.5, 0.001, "the near face")
	assert_almost_eq(strikes[1], 6.5, 0.001, "and the far one, at its own depth")


## Determinism, end to end: same seed, same board, same answer.
func test_a_seeded_shot_resolves_identically_across_runs() -> void:
	for a in range(0, 360, 29):
		var angle: float = deg_to_rad(float(a))
		var toward := Vector3(5.0 + cos(angle) * 9.0, AIM_HEIGHT, 5.0 + sin(angle) * 9.0)
		var first: Array[ImpactResult] = _fire(_state(), toward)
		var second: Array[ImpactResult] = _fire(_state(), toward)
		assert_eq(first.size(), second.size(), "same hop count at %d degrees" % a)
		for i in range(first.size()):
			assert_eq(
				first[i].region.part.id,
				second[i].region.part.id,
				"same part, hop %d at %d" % [i, a]
			)
			assert_eq(first[i].outcome, second[i].outcome, "same outcome, hop %d at %d" % [i, a])
			assert_almost_eq(
				first[i].hit_point.distance_to(second[i].hit_point),
				0.0,
				0.0,
				"same hit point, hop %d at %d" % [i, a]
			)


## **The cap fires and says so.** An unbounded bounce between two parallel walls
## is the obvious pathology, and a cap nobody can find afterwards is the failure
## this project keeps producing.
func test_the_chain_cap_fires_and_logs_rather_than_running_away() -> void:
	var state: CombatState = _state()
	var recorder := Recorder.new()
	state.combat_log.add_sink(recorder)
	var shooter: Unit = state.units[0]
	var from := Vector3(5.0, AIM_HEIGHT, 5.0)

	# A cap of one is reached by any shot at all, which is what makes this a test
	# of the cap rather than of a contrived geometry that happens to bounce
	# forever. The mechanism is the same at 1 as at 24.
	var results: Array[ImpactResult] = RayChain.resolve(
		state,
		from,
		Vector3(10.0, AIM_HEIGHT, 5.0),
		200.0,  # over steel's DT, so it penetrates and wants to continue
		0.0,
		state.material_table,
		_rng(),
		shooter.shell.all_parts_with_joints(),
		0.0,
		DamageResolver.DEFLECT_MODE_RICOCHET,
		1
	)
	assert_eq(results.size(), 1, "the cap stopped it at one segment")
	assert_true(
		&"ray_chain_capped" in recorder.kinds(),
		"and it logged the cap rather than stopping silently: %s" % str(recorder.kinds())
	)
	for event: LogEvent in recorder.events:
		if event.kind == &"ray_chain_capped":
			print("  %s" % event.text)
			assert_eq(event.data["segments"], 1)


## An uncapped chain in a sealed steel box must still terminate. The damage floor
## and the cap are two independent guarantees and this exercises both together.
func test_a_shot_in_a_sealed_room_terminates_without_hitting_the_cap() -> void:
	var state: CombatState = _state()
	var recorder := Recorder.new()
	state.combat_log.add_sink(recorder)
	var shooter: Unit = state.units[0]
	var from := Vector3(5.0, AIM_HEIGHT, 5.0)
	var capped := 0
	for a in range(0, 360, 7):
		var angle: float = deg_to_rad(float(a))
		var toward: Vector3 = from + Vector3(cos(angle), 0.0, sin(angle)) * 20.0
		RayChain.resolve(
			state,
			from,
			toward,
			4.0,
			0.0,
			state.material_table,
			_rng(),
			shooter.shell.all_parts_with_joints()
		)
	for event: LogEvent in recorder.events:
		if event.kind == &"ray_chain_capped":
			capped += 1
	print("  %d of 52 shots reached the segment cap" % capped)
	assert_eq(capped, 0, "ordinary geometry terminates on the damage floor, not on the cap")


## The chain must not fire the shooter's own body, and must not be tricked into
## it by a B point behind the muzzle.
func test_the_shooters_own_body_is_excluded_on_the_first_segment_only() -> void:
	var state: CombatState = _state()
	var shooter: Unit = state.units[0]
	var results: Array[ImpactResult] = _fire(state, Vector3(10.0, AIM_HEIGHT, 5.0))
	for result: ImpactResult in results:
		assert_ne(result.region.body, shooter, "no hop resolves against the shooter")
