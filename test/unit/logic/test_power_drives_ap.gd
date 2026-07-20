extends GutTest

## taskblock-20 Pass F: "AP stops being a flat baseline and becomes a
## function of the shell's power system." Every claim here is read off a
## real `CombatState.advance_turn()`/`_start_turn()` cycle (CLAUDE.md:
## never re-derive a second copy of the same formula) — live probes found
## the exact multi-turn trajectories below (including a real gap: the
## first version of `PowerResolver` recharged batteries but never actually
## discharged them, so a battery-only shell never drained at all) before
## this file was written.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## A single-unit shell with a custom power loadout — deliberately NOT the
## real torso/reactor.tres (those are Pass A/authored-content fixtures);
## this isolates PowerResolver's own formula from body/socket geometry.
func _powered_unit(
	power_produced: float,
	battery_capacity: float,
	battery_power_out: float,
	battery_power_in: float,
	battery_charge: float
) -> Dictionary:
	var root := Part.new()
	root.id = &"test_root"
	root.hp = 10
	root.max_hp = 10
	var reactor_socket := Socket.new(&"BACK")
	var battery_socket := Socket.new(&"MOUNT", Transform3D.IDENTITY, &"battery_mount")
	root.sockets = [reactor_socket, battery_socket]

	var reactor := Part.new()
	reactor.id = &"test_reactor"
	reactor.hp = 5
	reactor.max_hp = 5
	reactor.tags = [&"POWER_SOURCE"]
	reactor.power_produced = power_produced
	reactor_socket.occupant = reactor

	var battery := Part.new()
	battery.id = &"test_battery"
	battery.hp = 4
	battery.max_hp = 4
	battery.tags = [&"POWER_SOURCE", &"BATTERY"]
	battery.battery_capacity = battery_capacity
	battery.battery_power_out = battery_power_out
	battery.battery_power_in = battery_power_in
	battery.battery_charge = battery_charge
	battery_socket.occupant = battery

	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	return {"unit": unit, "reactor": reactor, "battery": battery, "state": state}


## taskblock-22 Pass B1: `_powered_unit`'s own fixture, plus one consumer
## part (`power_consumed`) on the root — set BEFORE the unit/CombatState
## are ever constructed, since construction already runs one real
## turn-start (`_start_turn`) that computes `max_ap` from whatever the
## parts say at that instant.
func _powered_unit_with_consumer(
	power_produced: float,
	battery_capacity: float,
	battery_power_out: float,
	battery_power_in: float,
	battery_charge: float,
	consumer_power: float
) -> Dictionary:
	var root := Part.new()
	root.id = &"test_root"
	root.hp = 10
	root.max_hp = 10
	root.power_consumed = consumer_power
	var reactor_socket := Socket.new(&"BACK")
	var battery_socket := Socket.new(&"MOUNT", Transform3D.IDENTITY, &"battery_mount")
	root.sockets = [reactor_socket, battery_socket]

	var reactor := Part.new()
	reactor.id = &"test_reactor"
	reactor.hp = 5
	reactor.max_hp = 5
	reactor.tags = [&"POWER_SOURCE"]
	reactor.power_produced = power_produced
	reactor_socket.occupant = reactor

	var battery := Part.new()
	battery.id = &"test_battery"
	battery.hp = 4
	battery.max_hp = 4
	battery.tags = [&"POWER_SOURCE", &"BATTERY"]
	battery.battery_capacity = battery_capacity
	battery.battery_power_out = battery_power_out
	battery.battery_power_in = battery_power_in
	battery.battery_charge = battery_charge
	battery_socket.occupant = battery

	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	return {"unit": unit, "reactor": reactor, "battery": battery, "consumer": root, "state": state}


func test_ap_derives_from_reactor_power_alone() -> void:
	var built: Dictionary = _powered_unit(4.0, 0.0, 0.0, 0.0, 0.0)
	assert_eq(built.unit.max_ap, 4)
	assert_eq(built.unit.ap, 4)


func test_ap_derives_from_battery_power_alone() -> void:
	# capacity 6, but power_out 3 caps how much of it is usable in one turn.
	var built: Dictionary = _powered_unit(0.0, 6.0, 3.0, 0.0, 6.0)
	assert_eq(built.unit.max_ap, 3, "capped by battery_power_out, not raw capacity")


func test_ap_derives_from_reactor_and_battery_combined() -> void:
	var built: Dictionary = _powered_unit(2.0, 6.0, 3.0, 0.0, 6.0)
	assert_eq(built.unit.max_ap, 5, "reactor 2 + battery discharge 3")


## "disabling/detonating the reactor drops the shell" — no explicit kill,
## the emergent consequence of a power-only shell whose one reactor is now
## destroyed: 0 available power from its own next turn start onward.
func test_destroying_the_only_reactor_crumbles_ap_to_zero_next_turn() -> void:
	var built: Dictionary = _powered_unit(6.0, 0.0, 0.0, 0.0, 0.0)
	assert_eq(built.unit.max_ap, 6, "sanity: powered before the reactor dies")

	built.reactor.hp = 0
	built.unit.ap = 0
	built.state.advance_turn()

	assert_eq(built.unit.max_ap, 0)
	assert_eq(built.unit.ap, 0)
	assert_true(built.unit.alive, "still a unit on the board — 0 AP, not a forced kill")


## "a battery-only shell's AP falls as batteries drain" — battery_power_out
## caps each turn's draw well under raw capacity, so it takes a couple of
## turns to bottom out; the trajectory must actually FALL, not stay flat.
func test_a_battery_only_shells_ap_falls_as_the_battery_drains() -> void:
	var built: Dictionary = _powered_unit(0.0, 6.0, 3.0, 2.0, 6.0)
	var ap_by_turn: Array[int] = [built.unit.max_ap]

	for i in range(3):
		built.unit.ap = 0
		built.state.advance_turn()
		ap_by_turn.append(built.unit.max_ap)

	assert_eq(ap_by_turn, [3, 3, 0, 0], "drains to nothing with no reactor to recharge it")


## taskblock-22 Pass B1: "consumers subtract from output first" — a
## power-hungry part lowers AP even though the reactor's own output never
## changed. Surplus = 6 (reactor) - 2 (consumer) = 4, still inside the
## curve's own 1:1 run, so this reads as a plain subtraction.
func test_a_consumer_lowers_ap_below_what_the_reactor_alone_would_give() -> void:
	var built: Dictionary = _powered_unit_with_consumer(6.0, 0.0, 0.0, 0.0, 0.0, 2.0)

	assert_eq(built.unit.max_ap, 4, "6 power - 2 consumed = 4 surplus, still 1:1 under the curve")


## "a bot with many power-hungry parts has less AP — load a shell down and
## it slows." Consumers eating the WHOLE output leave a real, working
## power system at exactly 0 surplus, never a negative one.
func test_a_consumer_that_eats_the_whole_output_floors_ap_at_zero_not_negative() -> void:
	var built: Dictionary = _powered_unit_with_consumer(4.0, 0.0, 0.0, 0.0, 0.0, 10.0)

	assert_eq(built.unit.max_ap, 0)
	assert_eq(PowerResolver.surplus(built.unit), 0.0)


## A wound-disabled/destroyed consumer draws nothing — same
## `operable_parts()` gate every other power field already reads.
func test_a_destroyed_consumer_stops_drawing_power() -> void:
	var built: Dictionary = _powered_unit_with_consumer(6.0, 0.0, 0.0, 0.0, 0.0, 2.0)
	assert_eq(built.unit.max_ap, 4, "sanity: the consumer is drawing before it's destroyed")

	built.consumer.hp = 0
	built.unit.ap = 0
	built.state.advance_turn()

	assert_eq(built.unit.max_ap, 6, "a destroyed consumer draws nothing — back to the full surplus")


## taskblock-22 Pass B1: "the curve bends down at the top" — the
## taskblock's own two example points, authored exactly:
## 8 surplus -> 6 AP, 12 surplus -> 8 AP.
func test_the_curve_bends_down_past_the_flat_baseline() -> void:
	assert_eq(PowerResolver.ap_for_surplus(8.0), 6)
	assert_eq(PowerResolver.ap_for_surplus(12.0), 8)


## "existing shells land near ~6 AP by default" — a bare reactor.tres
## alone (6.0 power_produced, no consumers) lands at EXACTLY today's
## baseline, not just "near" it.
func test_the_curve_is_one_to_one_up_to_the_flat_baseline() -> void:
	assert_eq(PowerResolver.ap_for_surplus(0.0), 0)
	assert_eq(PowerResolver.ap_for_surplus(3.0), 3)
	assert_eq(PowerResolver.ap_for_surplus(6.0), 6)


## Clamped, never extrapolated past either end — same posture
## `MaterialEntry.dt_at()` already established for its own curve.
func test_the_curve_clamps_at_its_own_outer_ends() -> void:
	assert_eq(PowerResolver.ap_for_surplus(-5.0), 0)
	assert_eq(PowerResolver.ap_for_surplus(1000.0), 10)


## 12->8 and 20->10 both authored: a genuinely diminishing rate (0.25
## AP/surplus) below what the 0->6 run (1.0 AP/surplus) already
## established — the curve really does keep bending down, not just
## plateau once.
func test_the_curve_keeps_diminishing_past_its_second_bend() -> void:
	var mid: int = PowerResolver.ap_for_surplus(16.0)
	assert_gt(mid, 8)
	assert_lt(mid, 10)


## A bare Shell, no CombatState — `_powered_unit`'s own CombatState.new()
## already runs one full recharge+discharge cycle at construction time
## (turn start for the fastest unit), which would silently pre-empt
## whatever starting `battery_charge` these isolated recharge-only tests
## mean to assert against.
func _powered_shell(
	power_produced: float,
	battery_capacity: float,
	battery_power_out: float,
	battery_power_in: float,
	battery_charge: float
) -> Dictionary:
	var reactor := Part.new()
	reactor.id = &"test_reactor"
	reactor.hp = 5
	reactor.max_hp = 5
	reactor.power_produced = power_produced

	var battery := Part.new()
	battery.id = &"test_battery"
	battery.hp = 4
	battery.max_hp = 4
	battery.battery_capacity = battery_capacity
	battery.battery_power_out = battery_power_out
	battery.battery_power_in = battery_power_in
	battery.battery_charge = battery_charge

	var root := Part.new()
	root.id = &"test_root"
	root.hp = 10
	root.max_hp = 10
	var reactor_socket := Socket.new(&"BACK")
	var battery_socket := Socket.new(&"MOUNT", Transform3D.IDENTITY, &"battery_mount")
	reactor_socket.occupant = reactor
	battery_socket.occupant = battery
	root.sockets = [reactor_socket, battery_socket]

	return {"shell": Shell.new(root), "reactor": reactor, "battery": battery}


func test_batteries_recharge_from_reactor_power() -> void:
	var built: Dictionary = _powered_shell(5.0, 6.0, 3.0, 2.0, 1.0)

	PowerResolver.recharge_batteries(built.shell)

	assert_eq(built.battery.battery_charge, 3.0, "1.0 + min(power_in=2, room=5, reactor=5)")


func test_recharge_never_exceeds_capacity() -> void:
	var built: Dictionary = _powered_shell(5.0, 6.0, 3.0, 2.0, 5.0)

	PowerResolver.recharge_batteries(built.shell)

	assert_eq(built.battery.battery_charge, 6.0, "capped at capacity, not 5.0 + 2.0 = 7.0")


func test_recharge_is_a_no_op_with_no_reactor_power() -> void:
	var built: Dictionary = _powered_shell(0.0, 6.0, 3.0, 2.0, 1.0)

	PowerResolver.recharge_batteries(built.shell)

	assert_eq(built.battery.battery_charge, 1.0, "nothing to recharge FROM")


## "power numbers are flagged placeholders" — real authored data
## (`res://data/parts/`), not hardcoded inside PowerResolver/DamageResolver.
func test_reactor_and_battery_power_stats_are_authored_data() -> void:
	var reactor: Part = DataLibrary.get_part(&"reactor")
	var battery: Part = DataLibrary.get_part(&"battery")

	assert_gt(reactor.power_produced, 0.0)
	assert_gt(battery.battery_capacity, 0.0)
	assert_gt(battery.battery_power_out, 0.0)
	assert_gt(battery.battery_power_in, 0.0)
	assert_eq(
		battery.battery_charge, battery.battery_capacity, "authored to start full, like hp/max_hp"
	)


## taskblock-20 Pass F's own "so nothing breaks": a shell with no power
## parts anywhere (every shell built before this pass, most test fixtures)
## must leave `max_ap` completely untouched by a real turn-start cycle —
## not silently reset to a baseline, and not zeroed, whatever it already
## was.
func test_a_shell_with_no_power_system_is_unaffected_by_a_turn_cycle() -> void:
	var root := Part.new()
	root.id = &"unpowered_root"
	root.hp = 10
	root.max_hp = 10
	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0))
	unit.max_ap = 2
	var state := CombatState.new(Grid.new(5, 5), [unit])

	assert_eq(unit.max_ap, 2, "untouched by CombatState's own construction-time turn start")

	unit.ap = 0
	state.advance_turn()

	assert_eq(unit.max_ap, 2, "still untouched after a real turn cycle")


## taskblock-22 Pass E1: a Tool Battery (an Arc Welder's own dedicated
## reserve) must never contribute to the whole-shell AP economy — it's a
## separate, local store RepairAction draws from directly, not a second
## power source for the unit at large.
func test_a_tool_battery_never_contributes_to_the_whole_shell_ap_economy() -> void:
	var root := Part.new()
	root.id = &"root"
	root.hp = 10
	root.max_hp = 10
	var socket := Socket.new(&"TOOL_BATTERY")
	root.sockets = [socket]

	var tool_battery := Part.new()
	tool_battery.id = &"tool_battery"
	tool_battery.hp = 3
	tool_battery.max_hp = 3
	tool_battery.battery_capacity = 6.0
	tool_battery.battery_power_out = 3.0
	tool_battery.battery_charge = 6.0
	tool_battery.tags = [&"POWER_SOURCE", &"BATTERY", &"TOOL_BATTERY"]
	socket.occupant = tool_battery

	var shell := Shell.new(root)

	assert_false(
		PowerResolver.has_power_system(shell),
		"a tool battery alone must never register as a real power system"
	)
	assert_eq(PowerResolver.battery_power(shell), 0.0)

	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0))
	unit.max_ap = 2
	var state := CombatState.new(Grid.new(5, 5), [unit])
	assert_eq(unit.max_ap, 2, "unaffected — same as any shell with no real power system")

	unit.ap = 0
	state.advance_turn()
	assert_eq(unit.max_ap, 2, "still unaffected after a real turn cycle")
	assert_eq(tool_battery.battery_charge, 6.0, "a normal turn-start discharge must never drain it")
