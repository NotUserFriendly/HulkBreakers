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
