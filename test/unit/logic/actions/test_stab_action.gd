extends GutTest

## taskblock-25 Pass B (docs/PLAN.md "Phase M — Melee"): a strike resolves
## through the SAME shot plane a shot does — armor DT, deflection,
## penetration, layered-body traversal, no separate path. Fixtures mirror
## test_attack_action.gd's own `_make_weapon`/`_make_shooter`/`_make_target`
## almost verbatim, swapping &"shoot" for &"stab" and range for reach.


func _make_weapon(id: StringName, damage: float, reach: float, ap_cost: int = 1) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = damage
	weapon.ap_cost = ap_cost
	weapon.burst = 1
	weapon.provides_actions = [&"stab"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.weapon_length = reach
	weapon.scatter = [Ring.new(0.05, 1.0)]
	return weapon


func _make_striker(cell: Vector2i, weapon: Part, shell_reach: float = 0.0) -> Unit:
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
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	var shell := Shell.new(torso)
	shell.shell_reach = shell_reach
	return Unit.new(Matrix.new(), shell, cell, 0)


func _make_target(cell: Vector2i, hp: int = 10) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = hp
	torso.max_hp = hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 1)


func test_is_legal_true_within_reach() -> void:
	var weapon := _make_weapon(&"knife", 20.0, 1.0)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	assert_true(StabAction.new(striker, &"knife", Vector2i(1, 0)).is_legal(state))


func test_is_legal_false_beyond_reach() -> void:
	var weapon := _make_weapon(&"knife", 20.0, 1.0)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(5, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	assert_false(StabAction.new(striker, &"knife", Vector2i(5, 0)).is_legal(state))


func test_is_legal_false_without_a_stab_provider() -> void:
	var weapon := _make_weapon(&"knife", 20.0, 1.0)
	weapon.provides_actions = [&"shoot"]  # never authored to stab
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	assert_false(StabAction.new(striker, &"knife", Vector2i(1, 0)).is_legal(state))


func test_is_legal_false_without_enough_ap() -> void:
	var weapon := _make_weapon(&"knife", 20.0, 1.0, 3)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	striker.ap = 1

	assert_false(StabAction.new(striker, &"knife", Vector2i(1, 0)).is_legal(state))


## The core claim of Pass B: a stab that penetrates does so through
## `DamageResolver` exactly like a shot — an unarmored torso takes real
## damage, no melee-specific damage formula.
func test_apply_deals_damage_through_the_shot_plane() -> void:
	var weapon := _make_weapon(&"knife", 20.0, 1.0, 2)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	var before_ap: int = striker.ap

	StabAction.new(striker, &"knife", Vector2i(1, 0)).apply(state)

	assert_eq(striker.ap, before_ap - 2)
	assert_lt(target.shell.root.hp, 10, "an unarmored torso stabbed with damage 20 must penetrate")


## Same `impact` event shape a shot produces — the log doesn't know or
## care that this came from a stab instead of a shot.
func test_impact_event_matches_the_ordinary_shot_shape() -> void:
	var weapon := _make_weapon(&"knife", 20.0, 1.0, 2)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	StabAction.new(striker, &"knife", Vector2i(1, 0)).apply(state)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_true(impacts.size() > 0)
	assert_eq(impacts[0].data.get("target_unit_id"), target.id)


## docs/PLAN.md Pass B: "not a special always-hits rule, just point-blank
## range through the existing accuracy pipeline" — the SAME RangeModel
## curve a ranged shot reads, fed melee's own tiny range_cells, must
## already scatter tighter than a shot fired from farther away.
func test_dartboard_scatter_is_tighter_at_melee_range_than_at_range() -> void:
	var weapon := _make_weapon(&"knife", 20.0, 1.0)
	weapon.weapon_def.effective_range = 1.0
	weapon.weapon_def.max_range = 20.0

	var melee_scale: float = RangeModel.dartboard_radius_scale(weapon, 1)
	var ranged_scale: float = RangeModel.dartboard_radius_scale(weapon, 15)

	assert_lt(
		melee_scale,
		ranged_scale,
		"the existing accuracy curve alone must already be tighter close up"
	)


## docs/PLAN.md Pass B: "aimed parts are melee's core advantage... a
## strike targets a joint/internal MORE reliably than a shot." Not a new
## aiming mechanism — `InternalTargeting.aim_offset_for` is the exact same
## call a ranged attacker already uses; melee's own advantage is the
## tighter dartboard around whatever point it returns, proven by feeding
## it straight into StabAction with no melee-specific handling at all.
func test_a_stab_can_aim_at_an_internal_part_via_the_existing_aimed_targeting() -> void:
	var weapon := _make_weapon(&"knife", 20.0, 1.0, 2)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	var direction := Vector2(1, 0)
	var plane: Array[Region] = ShotPlane.build(Vector2(0, 0), direction, state)
	var aim_offset: Variant = InternalTargeting.aim_offset_for(
		state, striker, target, target.shell.root, plane
	)
	assert_true(aim_offset is Vector2, "sanity: the fixture's own torso must be a legal aim target")

	var action := StabAction.new(striker, &"knife", Vector2i(1, 0), aim_offset)
	assert_true(action.is_legal(state))
	action.apply(state)

	assert_lt(target.shell.root.hp, 10, "an aimed stab must still resolve real damage")


## taskblock-25 Pass D: `weapon_def.stab_width` is read and threaded
## through as the strike's own spherecast radius — the deeper "can't
## thread a gap narrower than its width" claim is proven at the
## DamageResolver level (test_damage_resolver_spherecast.gd); this is the
## wiring sanity check, an ordinary single-target hit unaffected by a real
## authored width.
func test_a_wide_stab_still_hits_its_target_normally() -> void:
	var weapon := _make_weapon(&"spear", 20.0, 1.0, 2)
	weapon.weapon_def.stab_width = 0.3
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	StabAction.new(striker, &"spear", Vector2i(1, 0)).apply(state)

	assert_lt(target.shell.root.hp, 10, "a wide stab must still hit an ordinary, ungapped target")
