extends GutTest

## docs/04 taskblock02 Pass D4: decay/hold/regen, gated by socket + power +
## organics. Every unit here is already "exposed" (exposed_turns > 0) —
## LifeSupport.tick() is a no-op otherwise, same as plain
## Unit.tick_organics_decay() always was.


func _bare_unit(cell: Vector2i = Vector2i(0, 0)) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.sockets = [
		Socket.new(&"MATRIX", Transform3D.IDENTITY, &"MATRIX"),
		Socket.new(&"BACK", Transform3D.IDENTITY, &"BACK_L"),
		Socket.new(&"BACK", Transform3D.IDENTITY, &"BACK_R"),
	]
	torso.dock_matrix(Matrix.new())
	return Unit.new(torso.hosted_matrix, Shell.new(torso), cell)


## Socket-attached (not `.contents`) — `Shell.is_powered()` walks the
## socket tree via `all_parts()`, same as every other living-part check.
func _attach_reactor(unit: Unit) -> Part:
	var reactor := Part.new()
	reactor.id = &"reactor"
	reactor.hp = 3
	reactor.max_hp = 3
	reactor.attaches_to = [&"BACK"]
	reactor.material = &"sheet_steel"
	reactor.tags = [&"POWER_SOURCE", &"VOLATILE"]
	reactor.cook_off_damage = 6.0
	reactor.cook_off_radius = 2.0
	reactor.volume = [Box.new(Vector3.ZERO, Vector3(0.18, 0.26, 0.10))]
	PartGraph.attach(reactor, unit.shell.root, PartGraph.find_socket(unit.shell.root, &"BACK_L"))
	return reactor


## Also socket-attached: a backpack (`is_container`) must itself be part
## of the socket tree for `Shell.consume_organics()`'s own `all_parts()`
## walk to ever reach its contents.
func _attach_backpack_with_organics(unit: Unit) -> Part:
	var organics := Part.new()
	organics.id = &"organics_ration"
	organics.tags = [&"ORGANICS"]

	var backpack := Part.new()
	backpack.id = &"backpack"
	backpack.attaches_to = [&"BACK"]
	backpack.is_container = true
	backpack.max_bulk = 10.0
	backpack.contents = [organics]
	PartGraph.attach(backpack, unit.shell.root, PartGraph.find_socket(unit.shell.root, &"BACK_R"))
	return backpack


func test_decay_advances_when_exposed_and_unpowered() -> void:
	var unit := _bare_unit()
	unit.exposed_turns = 1

	LifeSupport.tick(unit, SurrogateLadder.default_ladder())

	assert_eq(unit.exposed_turns, 2, "no power source at all: decay advances exactly as before")


func test_holds_with_power_and_no_organics() -> void:
	var unit := _bare_unit()
	_attach_reactor(unit)
	unit.exposed_turns = 1
	var tier_before: SurrogateTier = unit.surrogate_tier

	LifeSupport.tick(unit, SurrogateLadder.default_ladder())

	assert_eq(unit.exposed_turns, 1, "powered, no fuel: holds, doesn't advance")
	assert_eq(unit.surrogate_tier, tier_before)


func test_winds_back_and_consumes_organics_when_powered_and_carried() -> void:
	var unit := _bare_unit()
	_attach_reactor(unit)
	var backpack := _attach_backpack_with_organics(unit)
	unit.exposed_turns = 2

	LifeSupport.tick(unit, SurrogateLadder.default_ladder())

	assert_eq(unit.exposed_turns, 1, "powered + organics: winds back one")
	assert_true(backpack.contents.is_empty(), "the ration is consumed, not just checked for")


func test_regen_floors_at_zero_and_never_fires_once_nothing_is_exposed() -> void:
	var unit := _bare_unit()
	_attach_reactor(unit)
	var backpack := _attach_backpack_with_organics(unit)
	unit.exposed_turns = 0  # already fully recovered

	LifeSupport.tick(unit, SurrogateLadder.default_ladder())

	assert_eq(unit.exposed_turns, 0, "never goes negative")
	assert_false(backpack.contents.is_empty(), "nothing exposed: organics aren't touched at all")


func test_killing_the_reactor_stops_power_and_cooks_off() -> void:
	var unit := _bare_unit()
	var reactor := _attach_reactor(unit)
	var state := CombatState.new(Grid.new(10, 10), [unit])

	assert_true(unit.shell.is_powered())

	reactor.hp = 0
	var cooked: Array[Unit] = DamageResolver.cook_off(reactor, state)

	assert_false(unit.shell.is_powered(), "a destroyed reactor no longer counts as living")
	assert_has(cooked, unit, "VOLATILE + destroyed: it cooks off")


func test_killing_the_reactor_resumes_decay_on_the_next_tick() -> void:
	var unit := _bare_unit()
	var reactor := _attach_reactor(unit)
	_attach_backpack_with_organics(unit)
	unit.exposed_turns = 1
	reactor.hp = 0  # already destroyed, same as after a resolved shot

	LifeSupport.tick(unit, SurrogateLadder.default_ladder())

	assert_eq(
		unit.exposed_turns, 2, "no living power source: decay, never regen, even with fuel on hand"
	)
