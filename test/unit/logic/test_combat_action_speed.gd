extends GutTest

## docs/09 taskblock06 Pass E: action speed — a SECOND ordering axis (docs/09
## Appendix G already orders UNITS by initiative; this orders ACTIONS at
## one instant). taskblock-18 A2 reframed this as "time to resolve": LOWER
## speed now resolves first, ties broken deterministically by unit id.


func _make_armed_unit(cell: Vector2i, weapon_speed: float, id: int) -> Dictionary:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.speed = weapon_speed

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	torso.sockets = [grip]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell)
	unit.id = id
	return {"unit": unit, "pistol": pistol}


func test_lower_speed_resolves_first_regardless_of_queue_order() -> void:
	var built_a: Dictionary = _make_armed_unit(Vector2i(0, 0), 40.0, 0)
	var built_b: Dictionary = _make_armed_unit(Vector2i(1, 0), 100.0, 1)
	var state := CombatState.new(Grid.new(10, 10), [built_a.unit, built_b.unit])

	var fast_attack := AttackAction.new(built_a.unit, &"pistol", Vector2i(1, 0))
	var face := FaceAction.new(built_b.unit, 0.0)
	# Deliberately queued slowest-first — order_by_speed must reorder it.
	var ordered: Array[CombatAction] = CombatAction.order_by_speed([face, fast_attack], state)

	assert_eq(
		ordered[0], fast_attack, "the pistol (speed 40) must resolve before FaceAction (speed 100)"
	)
	assert_eq(ordered[1], face)


## docs/09 taskblock06 Pass E: "a part carrying a speed modifier reorders
## resolution without a code change" — the mechanic itself, proven by
## setting ONE weapon's own `speed` field LOWER than FaceAction's fixed
## 100 and watching it move to the front, no code touched.
func test_a_weapon_with_a_lower_speed_out_paces_a_face_action() -> void:
	var built_a: Dictionary = _make_armed_unit(Vector2i(0, 0), 10.0, 0)  # faster than FaceAction
	var built_b: Dictionary = _make_armed_unit(Vector2i(1, 0), 40.0, 1)
	var state := CombatState.new(Grid.new(10, 10), [built_a.unit, built_b.unit])

	var fast_attack := AttackAction.new(built_a.unit, &"pistol", Vector2i(1, 0))
	var face := FaceAction.new(built_b.unit, 0.0)
	var ordered: Array[CombatAction] = CombatAction.order_by_speed([face, fast_attack], state)

	assert_eq(ordered[0], fast_attack, "a 10-speed weapon must out-pace FaceAction's fixed 100")
	assert_eq(ordered[1], face)


func test_attack_actions_speed_reads_the_weapons_own_field_live() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(0, 0), 40.0, 0)
	var state := CombatState.new(Grid.new(10, 10), [built.unit])
	var attack := AttackAction.new(built.unit, &"pistol", Vector2i(1, 0))

	assert_almost_eq(attack.speed(state), 40.0, 0.0001)

	(built.pistol as Part).speed = 999.0
	assert_almost_eq(
		attack.speed(state), 999.0, 0.0001, "must read the weapon live, not cache a value"
	)


## docs/09 taskblock06 Pass E: "ties are deterministic" — same speed,
## broken by unit id ascending, consistently regardless of queue order.
func test_tied_speed_breaks_deterministically_by_unit_id() -> void:
	var built_a: Dictionary = _make_armed_unit(Vector2i(0, 0), 40.0, 5)
	var built_b: Dictionary = _make_armed_unit(Vector2i(1, 0), 40.0, 2)
	var state := CombatState.new(Grid.new(10, 10), [built_a.unit, built_b.unit])

	var attack_a := AttackAction.new(built_a.unit, &"pistol", Vector2i(1, 0))
	var attack_b := AttackAction.new(built_b.unit, &"pistol", Vector2i(0, 0))

	var order_1: Array[CombatAction] = CombatAction.order_by_speed([attack_a, attack_b], state)
	var order_2: Array[CombatAction] = CombatAction.order_by_speed([attack_b, attack_a], state)

	assert_eq(order_1[0], attack_b, "unit id 2 must win the tie over unit id 5")
	assert_eq(order_2[0], attack_b, "the same tie-break regardless of the input order")


func test_face_actions_speed_and_unit_id_are_fixed_and_correct() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(0, 0), 40.0, 3)
	var state := CombatState.new(Grid.new(10, 10), [built.unit])
	var face := FaceAction.new(built.unit, 0.0)

	assert_almost_eq(face.speed(state), 100.0, 0.0001)
	assert_eq(face.unit_id(), 3)
