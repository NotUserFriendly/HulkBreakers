extends GutTest

## docs/09 taskblock06 Pass F: overwatch — the vehicle for testing Pass D's
## interruptible resolution, and staying in the game as its own mechanic.


func _make_overwatcher(cell: Vector2i, orientation: float, id: int) -> Dictionary:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]
	pistol.requires = {&"TRIGGER": 1}

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [wrist]

	# overwatch_weapon_id is deliberately NOT set here: CombatState.new()'s
	# constructor calls _start_turn(units[0]), which clears it (docs/09
	# taskblock06 F1) — callers must set it AFTER constructing the state,
	# same convention as unit.ap.
	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 0)
	unit.id = id
	unit.orientation = orientation
	return {"unit": unit, "pistol": pistol}


## torso box spans world Y 0.5-1.5 — its own projected center sits at
## Y=1.0, the point _torso_visible actually tests.
func _make_mover(cell: Vector2i, id: int) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.5, 1.0, 0.5))]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 1)
	unit.id = id
	return unit


func _make_blocker(top_y: float) -> Part:
	var blocker := Part.new()
	blocker.id = &"cover"
	blocker.is_destructible = false
	blocker.material = &"hull_plate"
	blocker.volume = [Box.new(Vector3(0.0, top_y * 0.5, 0.0), Vector3(1.0, top_y, 1.0))]
	return blocker


## docs/09 taskblock06 F2: "hugging cover so only your legs clear a crate
## does NOT trigger" — a blocker tall enough to still cover the torso's
## own center height, even though the mover's cell itself has full LoS.
func test_a_mover_whose_torso_stays_masked_by_cover_does_not_trigger() -> void:
	var built: Dictionary = _make_overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var mover: Unit = _make_mover(Vector2i(0, 5), 1)
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(0, 2)] = _make_blocker(2.0)  # taller than the torso's own Y=1.0 center
	var state := CombatState.new(grid, [overwatcher, mover])
	overwatcher.overwatch_weapon_id = &"pistol"

	Overwatch.check_trigger(state, mover)

	assert_eq(overwatcher.overwatch_weapon_id, &"pistol", "masked torso must never trigger a fire")
	assert_true(mover.shell.root.hp > 0)


## The same shape, but the cover is short enough that the torso's own
## center clears it — a real, positive trigger.
func test_a_mover_whose_torso_clears_cover_does_trigger() -> void:
	var built: Dictionary = _make_overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var mover: Unit = _make_mover(Vector2i(0, 5), 1)
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(0, 2)] = _make_blocker(0.3)  # well below the torso's Y=1.0 center
	var state := CombatState.new(grid, [overwatcher, mover])
	overwatcher.overwatch_weapon_id = &"pistol"
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	Overwatch.check_trigger(state, mover)

	assert_eq(overwatcher.overwatch_weapon_id, &"", "a clear torso must fire and spend the watch")
	assert_true(sink.events_of_kind(&"overwatch_triggered").size() == 1)


## docs/09 taskblock06 F2: "the trigger fires at the FIRST qualifying
## cell, not the nearest." The path moves TOWARD the overwatcher the
## whole way (each step strictly nearer than the last), so if the trigger
## picked the nearest cell it would let the mover run all the way to
## (5,0) before firing; it must instead freeze at (7,0), the first cell
## actually stepped onto.
func test_the_trigger_fires_at_the_first_qualifying_cell_not_the_nearest() -> void:
	# orientation -PI/2: BodyProjector.WORLD_FORWARD (0,1) rotated -90 deg
	# faces world +X, the axis the mover's whole path runs along.
	var built: Dictionary = _make_overwatcher(Vector2i(0, 0), -PI / 2.0, 0)
	var overwatcher: Unit = built.unit
	var mover: Unit = _make_mover(Vector2i(8, 0), 1)
	var grid := Grid.new(20, 20)
	# mover goes FIRST so it (not the overwatcher) is _start_turn()'s
	# units[0] target — the queued MoveAction requires state.current_unit()
	# == mover to be legal.
	var state := CombatState.new(grid, [mover, overwatcher])
	overwatcher.overwatch_weapon_id = &"pistol"
	mover.ap = 6
	var path: Array[Vector2i] = [Vector2i(8, 0), Vector2i(7, 0), Vector2i(6, 0), Vector2i(5, 0)]
	var queue := ActionQueue.new(mover)
	assert_true(queue.enqueue(MoveAction.new(mover, path), state))

	state.resolve_until(queue, Overwatch.check_trigger)

	assert_eq(
		mover.cell,
		Vector2i(7, 0),
		"must freeze at the first stepped-onto cell, not run closer toward the nearest one"
	)


## docs/09 taskblock06 F1: "arc: the unit's facing +/- 45 degrees." Facing
## 0.0 (world +Y, BodyProjector.WORLD_FORWARD) against a mover due +X —
## 90 degrees off, well outside the 45-degree arc.
func test_out_of_arc_movement_does_not_trigger() -> void:
	var built: Dictionary = _make_overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var mover: Unit = _make_mover(Vector2i(5, 0), 1)
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [overwatcher, mover])
	overwatcher.overwatch_weapon_id = &"pistol"

	Overwatch.check_trigger(state, mover)

	assert_eq(overwatcher.overwatch_weapon_id, &"pistol", "out-of-arc movement must never trigger")


## docs/09 taskblock06 F1: "fires once, then spent."
func test_overwatch_fires_only_once() -> void:
	var built: Dictionary = _make_overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var mover: Unit = _make_mover(Vector2i(0, 5), 1)
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [overwatcher, mover])
	overwatcher.overwatch_weapon_id = &"pistol"
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	Overwatch.check_trigger(state, mover)
	Overwatch.check_trigger(state, mover)
	Overwatch.check_trigger(state, mover)

	assert_eq(
		sink.events_of_kind(&"overwatch_triggered").size(),
		1,
		"repeated checks after firing must never trigger again"
	)


## docs/09: "if it changed the world, it's in the log."
func test_the_exchange_is_logged() -> void:
	var built: Dictionary = _make_overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var mover: Unit = _make_mover(Vector2i(0, 5), 1)
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [overwatcher, mover])
	overwatcher.overwatch_weapon_id = &"pistol"
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	Overwatch.check_trigger(state, mover)

	var triggered: Array[LogEvent] = sink.events_of_kind(&"overwatch_triggered")
	assert_eq(triggered.size(), 1)
	assert_eq(triggered[0].data.get("target_unit_id"), mover.id)
	assert_true(sink.events_of_kind(&"impact").size() > 0)


## docs/09/CLAUDE.md: determinism — the same seed always produces the
## same exchange.
func test_the_exchange_is_deterministic_from_the_same_seed() -> void:
	var damages: Array[float] = []
	for _i in range(2):
		var built: Dictionary = _make_overwatcher(Vector2i(0, 0), 0.0, 0)
		var overwatcher: Unit = built.unit
		var mover: Unit = _make_mover(Vector2i(0, 5), 1)
		var grid := Grid.new(10, 10)
		var state := CombatState.new(grid, [overwatcher, mover], 42)
		overwatcher.overwatch_weapon_id = &"pistol"

		Overwatch.check_trigger(state, mover)
		damages.append(10.0 - mover.shell.root.hp)

	assert_almost_eq(damages[0], damages[1], 0.0001)


## docs/09 taskblock07 Pass A/TESTS: "overwatch's torso check equals
## resolve_ray" — _torso_visible()'s own true/false answer must agree with
## an independently-built resolve_ray call at the torso's own rect center,
## never a second, separately-drifting notion of "what's in front of it."
func test_torso_visible_agrees_with_an_independently_built_resolve_ray_call() -> void:
	var built: Dictionary = _make_overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var pistol: Part = built.pistol
	var mover: Unit = _make_mover(Vector2i(0, 5), 1)
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(0, 2)] = _make_blocker(0.3)  # clears the torso — a real positive case
	var state := CombatState.new(grid, [overwatcher, mover])

	var visible: bool = Overwatch._torso_visible(state, overwatcher, mover, pistol)

	var direction := Vector2(mover.cell - overwatcher.cell)
	var plane: Array[Region] = ShotPlane.build(
		Vector2(overwatcher.cell.x, overwatcher.cell.y), direction.normalized(), state
	)
	var torso_region: Region = null
	for region: Region in plane:
		if region.part == mover.shell.root and region.body == mover:
			torso_region = region
	var muzzle: Vector3 = UnitGeometry.muzzle_point(overwatcher, pistol)
	var ray: Dictionary = AimPlaneGeometry.ray_from_muzzle(
		overwatcher.cell, mover.cell, torso_region.rect.get_center(), muzzle
	)
	var expected: HitResult = ShotPlane.resolve_ray(ray["origin"], ray["dir"], state)
	var expected_visible: bool = (
		expected != null and expected.part == mover.shell.root and expected.body == mover
	)

	assert_true(visible, "sanity: this fixture must actually clear cover")
	assert_eq(visible, expected_visible)
