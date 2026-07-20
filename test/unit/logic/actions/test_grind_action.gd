extends GutTest

## taskblock-25 Pass C (docs/PLAN.md "Phase M — Melee"): the "hold" payload
## — class `GrindAction` (see its own doc comment for why the class name
## differs from the action id). "Stacked bonus-pen, raw/linear, uncapped"
## and "continues if it gets through cladding" — both proven together with
## a plated torso: only enough accumulated bonus-pen actually penetrates
## the plate and lets the round's spill reach what's behind it.


func _make_striker(cell: Vector2i, weapon: Part) -> Unit:
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

	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func _make_weapon(damage: float, base_bonus_pen: float, hit_count: int) -> Part:
	var weapon := Part.new()
	weapon.id = &"saw"
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = damage
	weapon.ap_cost = 1
	weapon.bonus_pen = base_bonus_pen
	weapon.burst = hit_count  # doubles as the hold's own hit count
	weapon.provides_actions = [&"hold"]
	return weapon


## A CHEST-socketed plate in front of the torso — same layered fixture
## shape as test_damage_resolver.gd's own
## test_rifle_round_over_dt_damages_the_plate_and_the_part_behind, so only
## an actual PENETRATE (never STOP_DEAD) lets damage spill through to it.
func _make_plated_target(cell: Vector2i, plate_hp: int, torso_hp: int) -> Dictionary:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = torso_hp
	torso.max_hp = torso_hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var plate := Part.new()
	plate.id = &"plate"
	plate.material = &"grind_test_plate"
	plate.hp = plate_hp
	plate.max_hp = plate_hp
	plate.attaches_to = [&"CHEST"]
	plate.volume = [Box.new(Vector3(0.0, 0.5, 0.4), Vector3(2.0, 1.0, 0.2))]

	var socket := Socket.new(&"CHEST")
	socket.occupant = plate
	torso.sockets = [socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 1)
	return {"unit": unit, "torso": torso, "plate": plate}


func _table() -> MaterialTable:
	var table := MaterialTable.new()
	# DT 10, high deflect threshold — a dead-on hit (this fixture's own
	# geometry) always reads STOP_DEAD, never DEFLECT, while it fails.
	table.set_entry(&"grind_test_plate", MaterialEntry.new(10.0, 60.0))
	return table


func test_is_legal_false_without_a_hold_provider() -> void:
	var weapon := _make_weapon(5.0, 2.0, 3)
	weapon.provides_actions = [&"stab"]
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var built: Dictionary = _make_plated_target(Vector2i(1, 0), 30, 30)
	var state := CombatState.new(Grid.new(10, 10), [striker, built.unit])

	assert_false(GrindAction.new(striker, &"saw", Vector2i(1, 0)).is_legal(state))


## Two hits at base bonus-pen (2, 4) never clear DT 10 against damage 5 —
## every hit reads STOP_DEAD, the plate takes damage, and NOTHING spills
## through to the torso behind it.
func test_two_hits_never_accumulate_enough_bonus_pen_to_penetrate() -> void:
	var weapon := _make_weapon(5.0, 2.0, 2)
	var striker := _make_striker(Vector2i(2, 5), weapon)
	var built: Dictionary = _make_plated_target(Vector2i(2, 2), 30, 30)
	var state := CombatState.new(Grid.new(10, 10), [striker, built.unit])
	state.material_table = _table()

	GrindAction.new(striker, &"saw", Vector2i(2, 2)).apply(state)

	assert_eq(built.plate.hp, 20, "two STOP_DEAD hits of 5 damage each")
	assert_eq(built.torso.hp, 30, "nothing ever got through cladding to reach the torso")


## The THIRD hit's own accumulated bonus-pen (6) finally clears DT 10 minus
## itself (effective DT 4 <= damage 5) — a real PENETRATE, and its own
## spill (part_damage 5 - effective_dt 4 = 1) reaches the torso behind it.
## The exact same weapon, only the hit count differs from the test above.
func test_a_third_hit_accumulates_enough_bonus_pen_to_penetrate_and_spill_through() -> void:
	var weapon := _make_weapon(5.0, 2.0, 3)
	var striker := _make_striker(Vector2i(2, 5), weapon)
	var built: Dictionary = _make_plated_target(Vector2i(2, 2), 30, 30)
	var state := CombatState.new(Grid.new(10, 10), [striker, built.unit])
	state.material_table = _table()

	GrindAction.new(striker, &"saw", Vector2i(2, 2)).apply(state)

	assert_eq(
		built.plate.hp, 15, "three hits of 5 damage each, the third a PENETRATE not STOP_DEAD"
	)
	assert_eq(built.torso.hp, 29, "the third hit's own 1-point spill must reach the torso")


## "No deflect at all: chew through or nothing" — an oblique fixture that
## WOULD ricochet under ranged combat's own default must never spawn a
## ricochet here (already proven generally at the DamageResolver level;
## this confirms GrindAction actually wires DEFLECT_MODE_NONE through).
func test_a_hold_never_deflects() -> void:
	var weapon := _make_weapon(3.0, 0.0, 1)
	# direction (3,4): the exact ~37-degree-incidence oblique angle
	# test_damage_resolver.gd's own DEFLECT fixtures already use — clears
	# steel's default 30-degree deflect threshold.
	var striker := _make_striker(Vector2i(0, 0), weapon)

	var target_torso := Part.new()
	target_torso.id = &"cover"
	target_torso.material = &"steel"
	target_torso.hp = 20
	target_torso.max_hp = 20
	target_torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var target := Unit.new(Matrix.new(), Shell.new(target_torso), Vector2i(3, 4), 1)
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	GrindAction.new(striker, &"saw", Vector2i(3, 4)).apply(state)

	var impacts: Array = sink.events_of_kind(&"impact")
	assert_eq(impacts.size(), 1, "one hit, one impact — never a ricochet chain")
	assert_eq(
		impacts[0].data.get("outcome"), Enums.Outcome.DEFLECT, "sanity: the fixture must deflect"
	)
