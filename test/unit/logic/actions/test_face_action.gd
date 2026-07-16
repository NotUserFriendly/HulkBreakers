extends GutTest

## docs/10 taskblock02 F3: FaceAction costs MP, not AP directly — same
## AP-to-MP burn MoveAction already uses (Appendix E). "Any action taken
## with a target faces for free" is covered against AttackAction, the one
## action in this codebase whose target actually sits at a different cell
## (GatherAction/PickUpAction always interact with the actor's own cell —
## no direction to face at all, so neither calls face_for_free).


func _make_unit(cell: Vector2i, agility: float = 0.0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.stat_mods = {"agility": agility}
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


func _armed_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## CombatState.new()'s own constructor calls _start_turn() on the first
## unit, which resets mp/ap (docs/09) — every fixture below sets them
## AFTER the state exists, never before.
func test_manual_face_deducts_exactly_one_mp() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(10, 10), [unit])
	unit.mp = 3.0

	var action := FaceAction.new(unit, 1.5)
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(unit.mp, 2.0, "exactly 1 MP, not the whole budget")
	assert_almost_eq(unit.orientation, 1.5, 0.0001)


func test_manual_face_burns_one_ap_for_mp_when_short() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(10, 10), [unit])
	unit.mp = 0.0
	unit.ap = 1
	var per_ap: float = unit.mp_per_ap()

	var action := FaceAction.new(unit, 0.7)
	assert_true(state.try_apply(action))

	assert_eq(unit.ap, 0)
	assert_almost_eq(unit.mp, per_ap - FaceAction.COST, 0.0001)


func test_facing_with_zero_mp_and_zero_ap_is_illegal() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(10, 10), [unit])
	unit.mp = 0.0
	unit.ap = 0

	var action := FaceAction.new(unit, 0.7)

	assert_false(action.is_legal(state))


func test_manual_face_emits_faced_with_reason_manual() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(10, 10), [unit])
	unit.mp = 3.0
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	state.try_apply(FaceAction.new(unit, 1.5))

	var events: Array[LogEvent] = sink.events_of_kind(&"faced")
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("reason"), &"manual")
	assert_eq(events[0].data.get("cost"), FaceAction.COST)
	assert_almost_eq(events[0].data.get("direction"), 1.5, 0.0001)


func test_an_attack_faces_the_target_for_free() -> void:
	var shooter := _armed_unit(Vector2i(0, 0), 0)
	var target := _armed_unit(Vector2i(3, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var mp_before: float = shooter.mp
	var ap_before: int = shooter.ap

	var weapon: Part = DeepStrike.find_operable_weapon(shooter)
	state.try_apply(AttackAction.new(shooter, weapon.id, target.cell))

	var expected: float = FaceAction.orientation_toward(Vector2i(0, 0), Vector2i(3, 0))
	assert_almost_eq(shooter.orientation, expected, 0.0001, "the shooter turns to face the shot")
	assert_eq(shooter.mp, mp_before, "facing that comes free with an action never spends MP")

	var faced_events: Array[LogEvent] = sink.events_of_kind(&"faced")
	assert_eq(faced_events.size(), 1)
	assert_eq(faced_events[0].data.get("reason"), &"free_with_action")
	assert_eq(faced_events[0].data.get("cost"), 0.0)
	# Only the AP the shot itself costs — nothing extra for the free turn.
	assert_eq(ap_before - shooter.ap, weapon.ap_cost)


func test_an_attack_already_facing_the_target_does_not_re_log_faced() -> void:
	var shooter := _armed_unit(Vector2i(0, 0), 0)
	var target := _armed_unit(Vector2i(3, 0), 1)
	shooter.orientation = FaceAction.orientation_toward(shooter.cell, target.cell)
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	var weapon: Part = DeepStrike.find_operable_weapon(shooter)
	state.try_apply(AttackAction.new(shooter, weapon.id, target.cell))

	assert_eq(sink.events_of_kind(&"faced").size(), 0, "already facing that way: nothing changed")
