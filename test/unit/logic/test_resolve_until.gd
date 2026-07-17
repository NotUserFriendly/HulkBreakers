extends GutTest

## docs/09 taskblock06 Pass D: interruptible resolution. Overwatch (Pass F)
## doesn't exist yet — these tests stand in for its own mid-move trigger
## with a directly-injected `mid_move_hook` Callable, exercising exactly
## the same seam Pass F will plug a real trigger check into.


## torso -[HIP]- leg (carries agility, so destroying it lowers mp_per_ap)
## -[SHOULDER]- arm -[WRIST]- hand(TRIGGER) -[GRIP]- pistol.
func _make_mobile_armed_unit(cell: Vector2i, squad: int = 0) -> Dictionary:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
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

	var leg := Part.new()
	leg.id = &"leg"
	leg.hp = 3
	leg.max_hp = 3
	leg.stat_mods = {&"agility": 1.0}  # BASE_MP 2.0 + 1.0 = 3.0 mp_per_ap while alive

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	var hip := Socket.new(&"HIP")
	hip.occupant = leg
	torso.sockets = [shoulder, hip]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, squad)
	return {"unit": unit, "leg": leg, "arm": arm, "hand": hand, "pistol": pistol}


func _straight_path(start: Vector2i, length: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	for i in range(1, length):
		path.append(start + Vector2i(i, 0))
	return path


## docs/09 taskblock06 D2/D3: losing the leg mid-move lowers mp_per_ap
## enough that the remaining path can no longer be paid for (no AP left to
## convert with) — resolution stops there, AP stays spent, MP is whatever
## the pool holds at that instant.
func test_a_leg_lost_mid_move_stops_resolution_and_refunds_mp_but_not_ap() -> void:
	var built: Dictionary = _make_mobile_armed_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var leg: Part = built.leg
	var grid := Grid.new(20, 20)
	var state := CombatState.new(grid, [unit])
	# CombatState.new() -> _start_turn() resets ap to max_ap, so this must
	# happen AFTER construction, not before.
	unit.ap = 3
	# 10-cell path (9 steps): at the boosted 3.0 mp_per_ap the leg gives,
	# all 3 AP exactly covers all 9 steps (legal when queued). Losing the
	# leg after step 1 drops the rate to the base 2.0 -- the 2 AP left
	# only buys 4 more MP, one short of the 8 the remaining 8 steps need.
	var path: Array[Vector2i] = _straight_path(Vector2i(0, 0), 10)
	var queue := ActionQueue.new(unit)
	assert_true(queue.enqueue(MoveAction.new(unit, path), state))

	var destroyed_at := Vector2i(1, 0)
	var hook := func(_s: CombatState, u: Unit) -> void:
		if u.cell == destroyed_at:
			DamageResolver.apply_damage_to_part(leg, 10.0)

	var outcome: Dictionary = state.resolve_until(queue, hook)

	assert_eq(outcome.kind, Enums.ResolveOutcome.STOPPED)
	assert_eq(outcome.reason, &"mid_move_interrupt")
	assert_eq(unit.cell, destroyed_at, "the unit must have frozen exactly where the leg was lost")
	assert_eq(unit.ap, 2, "the 1 AP actually spent converting to MP stays spent; the rest is idle")
	assert_eq(outcome.refund.ap, 0)
	assert_almost_eq(
		outcome.refund.mp, unit.mp, 0.0001, "the refund is whatever MP the pool actually holds"
	)
	assert_gt(unit.mp, 0.0, "there really is leftover MP to hand back as change")


## docs/09 taskblock06 D2: "an arm lost mid-move does NOT stop the move" —
## losing the arm never touches agility/MP, so the queued move completes
## in full; the queue then stops at the NEXT action once ITS own legality
## fails (the weapon is gone).
func test_an_arm_lost_mid_move_does_not_stop_the_move_but_stops_at_the_now_illegal_shot() -> void:
	var built: Dictionary = _make_mobile_armed_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var enemy_root := Part.new()
	enemy_root.id = &"enemy_torso"
	enemy_root.hp = 5
	enemy_root.max_hp = 5
	var enemy := Unit.new(Matrix.new(), Shell.new(enemy_root), Vector2i(5, 0), 1)
	unit.ap = 6
	var grid := Grid.new(20, 20)
	var state := CombatState.new(grid, [unit, enemy])

	var path: Array[Vector2i] = _straight_path(Vector2i(0, 0), 4)
	var queue := ActionQueue.new(unit)
	assert_true(queue.enqueue(MoveAction.new(unit, path), state))
	assert_true(queue.enqueue(AttackAction.new(unit, &"pistol", Vector2i(5, 0)), state))

	var destroyed_at := Vector2i(1, 0)
	# Mirrors what a real impact's _resolve_destruction_consequences does:
	# destroy the part AND drop its subtree, so the hand+pistol it was
	# carrying actually detach from the tree — a bare apply_damage_to_part
	# alone would leave them structurally reachable (PartGraph.walk never
	# prunes on a PARENT's hp), understating what "blown off" means.
	var hook := func(s: CombatState, u: Unit) -> void:
		if u.cell == destroyed_at:
			DamageResolver.apply_damage_to_part(arm, 10.0)
			DamageResolver.drop_subtree_if_destroyed(arm, s)

	var outcome: Dictionary = state.resolve_until(queue, hook)

	assert_eq(
		unit.cell, Vector2i(3, 0), "the move must have completed in full despite the arm loss"
	)
	assert_eq(outcome.kind, Enums.ResolveOutcome.STOPPED)
	assert_eq(outcome.reason, &"next_action_illegal", "it stops at the shot, not mid-move")


## docs/09 taskblock06 D2: "a plate scratch stops nothing."
func test_a_minor_scratch_mid_move_stops_nothing() -> void:
	var built: Dictionary = _make_mobile_armed_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	unit.ap = 6
	var grid := Grid.new(20, 20)
	var state := CombatState.new(grid, [unit])
	var path: Array[Vector2i] = _straight_path(Vector2i(0, 0), 4)
	var queue := ActionQueue.new(unit)
	assert_true(queue.enqueue(MoveAction.new(unit, path), state))
	assert_true(queue.enqueue(EndTurnAction.new(unit), state))

	var hook := func(_s: CombatState, u: Unit) -> void:
		if u.cell == Vector2i(1, 0):
			DamageResolver.apply_damage_to_part(arm, 1.0)  # a scratch, arm survives

	var outcome: Dictionary = state.resolve_until(queue, hook)

	assert_eq(outcome.kind, Enums.ResolveOutcome.COMPLETED)
	assert_eq(unit.cell, Vector2i(3, 0))
	assert_true(arm.hp > 0, "a scratch must not have destroyed the arm")


## docs/10 taskblock06 D4: "only the interrupted unit gets control back" —
## another unit's own queue/state is entirely untouched by this one call.
func test_only_the_interrupted_units_own_state_is_touched() -> void:
	var built: Dictionary = _make_mobile_armed_unit(Vector2i(0, 0), 0)
	var unit: Unit = built.unit
	var leg: Part = built.leg
	var bystander: Unit = _make_mobile_armed_unit(Vector2i(10, 10), 1).unit
	var grid := Grid.new(20, 20)
	var state := CombatState.new(grid, [unit, bystander])
	# CombatState.new() -> _start_turn() resets ap to max_ap, so this must
	# happen AFTER construction, not before.
	unit.ap = 3
	var bystander_ap: int = bystander.ap
	var bystander_cell: Vector2i = bystander.cell
	var path: Array[Vector2i] = _straight_path(Vector2i(0, 0), 10)
	var queue := ActionQueue.new(unit)
	assert_true(queue.enqueue(MoveAction.new(unit, path), state))

	var hook := func(_s: CombatState, u: Unit) -> void:
		if u.cell == Vector2i(1, 0):
			DamageResolver.apply_damage_to_part(leg, 10.0)

	state.resolve_until(queue, hook)

	assert_eq(bystander.ap, bystander_ap, "a bystander unit's AP must be untouched")
	assert_eq(bystander.cell, bystander_cell, "a bystander unit's position must be untouched")


## docs/09: "if it changed the world, it's in the log" — the stop itself,
## its reason, and the refund all show up as a real event.
func test_the_outcome_and_refund_are_logged() -> void:
	var built: Dictionary = _make_mobile_armed_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var leg: Part = built.leg
	var grid := Grid.new(20, 20)
	var state := CombatState.new(grid, [unit])
	# CombatState.new() -> _start_turn() resets ap to max_ap, so this must
	# happen AFTER construction, not before.
	unit.ap = 3
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var path: Array[Vector2i] = _straight_path(Vector2i(0, 0), 10)
	var queue := ActionQueue.new(unit)
	assert_true(queue.enqueue(MoveAction.new(unit, path), state))

	var hook := func(_s: CombatState, u: Unit) -> void:
		if u.cell == Vector2i(1, 0):
			DamageResolver.apply_damage_to_part(leg, 10.0)

	state.resolve_until(queue, hook)

	var events: Array[LogEvent] = sink.events_of_kind(&"resolution_stopped")
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("reason"), &"mid_move_interrupt")
	assert_true(events[0].data.has("refund_mp"))


## docs/09 taskblock06 D2/CLAUDE.md: determinism — the same setup always
## stops at the same cell with the same outcome.
func test_the_same_seed_and_setup_stops_at_the_same_interrupt_point() -> void:
	var outcomes: Array[Dictionary] = []
	var cells: Array[Vector2i] = []
	for _i in range(2):
		var built: Dictionary = _make_mobile_armed_unit(Vector2i(0, 0))
		var unit: Unit = built.unit
		var leg: Part = built.leg
		var grid := Grid.new(20, 20)
		var state := CombatState.new(grid, [unit], 7)
		# CombatState.new() -> _start_turn() resets ap to max_ap, so this
		# must happen AFTER construction, not before.
		unit.ap = 3
		var path: Array[Vector2i] = _straight_path(Vector2i(0, 0), 10)
		var queue := ActionQueue.new(unit)
		queue.enqueue(MoveAction.new(unit, path), state)

		var hook := func(_s: CombatState, u: Unit) -> void:
			if u.cell == Vector2i(1, 0):
				DamageResolver.apply_damage_to_part(leg, 10.0)

		outcomes.append(state.resolve_until(queue, hook))
		cells.append(unit.cell)

	assert_eq(cells[0], cells[1])
	assert_eq(outcomes[0].reason, outcomes[1].reason)
	assert_almost_eq(outcomes[0].refund.mp, outcomes[1].refund.mp, 0.0001)
