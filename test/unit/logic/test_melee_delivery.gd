extends GutTest

## taskblock-25 Pass A (docs/PLAN.md "Phase M — Melee"): lean is a POSE
## change, not a second exposure system — these fixtures mirror
## test_overwatch.gd's own masked/clears-cover geometry exactly, swapping
## "the mover already stands there" for "the mover leans there from
## farther away," to prove the SAME existing torso check answers both.


## Mirrors test_overwatch.gd's own _make_overwatcher verbatim.
func _overwatcher(cell: Vector2i, orientation: float, id: int) -> Dictionary:
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

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 0)
	unit.id = id
	unit.orientation = orientation
	return {"unit": unit, "pistol": pistol}


## The striker — a real, volumed torso (world Y 0.5-1.5, center Y=1.0),
## `orientation` facing back toward the overwatcher so a forward lean
## reduces its own projected depth (docs/PLAN.md: leaning moves the torso
## toward what it's striking).
func _striker(cell: Vector2i, orientation: float, shell_reach: float, id: int) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.5, 1.0, 0.5))]
	var shell := Shell.new(torso)
	shell.shell_reach = shell_reach
	var unit := Unit.new(Matrix.new(), shell, cell, 1)
	unit.id = id
	unit.orientation = orientation
	return unit


func _weapon(length: float) -> Part:
	var weapon := Part.new()
	weapon.id = &"knife"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.weapon_length = length
	return weapon


## Mirrors test_overwatch.gd's own _make_blocker verbatim — full torso
## height (well past Y=1.0), so exposure here can only be about DEPTH
## ordering (does the leaned torso now sit in front of this, or still
## behind it), never about peeking over a short wall.
func _blocker(top_y: float) -> Part:
	var blocker := Part.new()
	blocker.id = &"cover"
	blocker.is_destructible = false
	blocker.material = &"hull_plate"
	blocker.volume = [Box.new(Vector3(0.0, top_y * 0.5, 0.0), Vector3(1.0, top_y, 1.0))]
	return blocker


func _grid_with_blocker() -> Grid:
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(0, 3)] = _blocker(2.0)
	return grid


func test_apply_lean_leaves_pose_idle_when_weapon_alone_covers_the_distance() -> void:
	var striker: Unit = _striker(Vector2i(0, 5), PI, 0.7, 1)
	var lean: float = MeleeDelivery.apply_lean(striker, _weapon(1.3), 1.0)

	assert_eq(lean, 0.0)
	assert_true(striker.pose.overrides.is_empty())


func test_apply_lean_sets_a_root_override_proportional_to_the_shortfall() -> void:
	var striker: Unit = _striker(Vector2i(0, 5), PI, 0.7, 1)
	var lean: float = MeleeDelivery.apply_lean(striker, _weapon(0.3), 1.0)

	assert_almost_eq(lean, 0.7, 0.0001)
	assert_true(striker.pose.overrides.has(Poses.ROOT_SOCKET_ID))


func test_reset_pose_snaps_back_to_idle() -> void:
	var striker: Unit = _striker(Vector2i(0, 5), PI, 0.7, 1)
	MeleeDelivery.apply_lean(striker, _weapon(0.3), 1.0)

	MeleeDelivery.reset_pose(striker)

	assert_true(striker.pose.overrides.is_empty())


## The overwatcher's own torso check is genuinely blind to the leaned
## striker at a small lean (still behind the blocker's own depth).
func test_a_small_lean_still_masked_by_cover_does_not_trigger() -> void:
	var built: Dictionary = _overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var striker: Unit = _striker(Vector2i(0, 5), PI, 1.0, 1)
	var state := CombatState.new(_grid_with_blocker(), [overwatcher, striker])
	overwatcher.overwatch_weapon_id = &"pistol"

	var triggered: bool = MeleeDelivery.resolve_exposure(state, striker, _weapon(0.0), 1.0)

	assert_false(triggered)
	assert_eq(overwatcher.overwatch_weapon_id, &"pistol", "still masked, must never fire")


## The same geometry, a bigger lean — the torso now projects IN FRONT of
## the blocker's own depth and the existing torso check fires for real,
## through the exact same code path a queued move's mid-move hook uses.
func test_a_large_lean_clears_cover_and_triggers() -> void:
	var built: Dictionary = _overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var striker: Unit = _striker(Vector2i(0, 5), PI, 3.0, 1)
	var state := CombatState.new(_grid_with_blocker(), [overwatcher, striker])
	overwatcher.overwatch_weapon_id = &"pistol"

	var triggered: bool = MeleeDelivery.resolve_exposure(state, striker, _weapon(0.0), 3.0)

	assert_true(triggered, "a lean past cover must fire the existing torso check")
	assert_eq(overwatcher.overwatch_weapon_id, &"", "the watch fired and spent")


## The proportional claim, both halves in one place: the ONLY thing that
## differs between the masked and the clear case above is the size of the
## lean, never a separate calc.
func test_a_larger_required_lean_exposes_more_than_a_smaller_one() -> void:
	var small_built: Dictionary = _overwatcher(Vector2i(0, 0), 0.0, 0)
	var small_overwatcher: Unit = small_built.unit
	var small_striker: Unit = _striker(Vector2i(0, 5), PI, 1.0, 1)
	var small_state := CombatState.new(_grid_with_blocker(), [small_overwatcher, small_striker])
	small_overwatcher.overwatch_weapon_id = &"pistol"

	var large_built: Dictionary = _overwatcher(Vector2i(0, 0), 0.0, 0)
	var large_overwatcher: Unit = large_built.unit
	var large_striker: Unit = _striker(Vector2i(0, 5), PI, 3.0, 1)
	var large_state := CombatState.new(_grid_with_blocker(), [large_overwatcher, large_striker])
	large_overwatcher.overwatch_weapon_id = &"pistol"

	var small_triggered: bool = MeleeDelivery.resolve_exposure(
		small_state, small_striker, _weapon(0.0), 1.0
	)
	var large_triggered: bool = MeleeDelivery.resolve_exposure(
		large_state, large_striker, _weapon(0.0), 3.0
	)

	assert_false(small_triggered)
	assert_true(large_triggered)


## The core "un-exposed" guarantee: this is the EXACT same geometry that
## triggers when leaned (test_a_large_lean_clears_cover_and_triggers) —
## proving a weapon that covers the distance outright never even asks the
## overwatch question, not just that it happens not to fire.
func test_an_unexposed_striker_cannot_be_interrupted() -> void:
	var built: Dictionary = _overwatcher(Vector2i(0, 0), 0.0, 0)
	var overwatcher: Unit = built.unit
	var striker: Unit = _striker(Vector2i(0, 5), PI, 3.0, 1)
	var state := CombatState.new(_grid_with_blocker(), [overwatcher, striker])
	overwatcher.overwatch_weapon_id = &"pistol"

	# weapon_length 3.0 covers the whole distance on its own — no lean.
	var triggered: bool = MeleeDelivery.resolve_exposure(state, striker, _weapon(3.0), 3.0)

	assert_false(triggered)
	assert_eq(overwatcher.overwatch_weapon_id, &"pistol", "never even asked, must still be armed")
	assert_true(striker.pose.overrides.is_empty(), "an uncovered strike never touches the pose")


func test_find_step_in_cell_returns_null_when_already_in_reach() -> void:
	var striker: Unit = _striker(Vector2i(0, 0), 0.0, 1.0, 1)
	var target: Unit = _striker(Vector2i(0, 1), 0.0, 0.0, 2)
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	striker.mp = 10.0

	var result: Variant = MeleeDelivery.find_step_in_cell(state, striker, target, _weapon(0.0))

	assert_null(result)


func test_find_step_in_cell_finds_a_reachable_cell_within_reach_of_the_target() -> void:
	var striker: Unit = _striker(Vector2i(0, 0), 0.0, 1.0, 1)
	var target: Unit = _striker(Vector2i(0, 5), 0.0, 0.0, 2)
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	striker.mp = 10.0

	var result: Variant = MeleeDelivery.find_step_in_cell(state, striker, target, _weapon(0.0))

	assert_not_null(result)
	var cell: Vector2i = result
	assert_true(
		MeleeReach.in_reach(striker.shell, _weapon(0.0), Grid.distance_chebyshev(cell, target.cell))
	)
	assert_ne(cell, striker.cell)


## docs/PLAN.md Pass A: "distance > shell + weapon: can't reach — step in
## (a real cell move, Step-Out-style, reach-gated) then strike." The found
## cell must be a real, pathable destination — fed straight into an
## ordinary MoveAction, no melee-specific move machinery, so it triggers
## overwatch through the exact same mid-move hook any other move already
## does (test_overwatch.gd's own suite proves that path fires; this only
## proves the cell this function hands it is a legal one to walk).
func test_find_step_in_cell_is_a_legal_destination_for_a_real_move_action() -> void:
	var striker: Unit = _striker(Vector2i(0, 0), 0.0, 1.0, 1)
	var target: Unit = _striker(Vector2i(0, 5), 0.0, 0.0, 2)
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	striker.mp = 10.0

	var result: Variant = MeleeDelivery.find_step_in_cell(state, striker, target, _weapon(0.0))
	var cell: Vector2i = result
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var path: Array[Vector2i] = pf.astar(striker.cell, cell)
	var queue := ActionQueue.new(striker)

	assert_true(queue.enqueue(MoveAction.new(striker, path), state))


func test_find_step_in_cell_returns_null_when_nothing_reachable_is_in_range() -> void:
	var striker: Unit = _striker(Vector2i(0, 0), 0.0, 1.0, 1)
	var target: Unit = _striker(Vector2i(0, 9), 0.0, 0.0, 2)
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	striker.mp = 1.0

	var result: Variant = MeleeDelivery.find_step_in_cell(state, striker, target, _weapon(0.0))

	assert_null(result)
