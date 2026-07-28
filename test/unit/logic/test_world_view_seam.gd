extends GutTest

## taskblock-44 Pass C: the information chokepoint.
##
## The rebuild's tiers gate what a unit KNOWS, not just what it can do. That only
## works if information access has exactly one door, and **this file is the lock
## on it.** A prose rule with no enforcement is what BR40.02 was — a rename
## orphaned two scenario scripts for fifteen taskblocks because nothing re-ran
## them — so the rule is a grep guard, in the same shape as taskblock-40's
## spawn-marker guard and taskblock-41's parse guard.
##
## **The boundary is not `CombatState` versus not-`CombatState`.** It is
## knowledge-about-units versus everything else, and that line runs THROUGH
## `Grid` and THROUGH `BatchPlan` rather than around them. Geometry is free; a
## Mindless unit still knows where the walls are. Occupancy is not geometry, and
## the blackboard is a tier capability.

## taskblock-45 Pass E: the guard follows the planner. The old one is retired; the
## files that now read unit knowledge are the utility planner and the context that
## feeds it, and BOTH are watched — a chokepoint guarded in one of the two files
## that can bypass it is not a chokepoint.
const PLANNER_PATHS: Array[String] = [
	"res://src/logic/ai/utility_planner.gd",
	"res://src/logic/ai/utility_context.gd",
]


func _planner_source() -> String:
	var combined: String = ""
	for path: String in PLANNER_PATHS:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "%s must be readable for this guard to mean anything" % path)
		if file != null:
			combined += file.get_as_text() + "\n"
	return combined


func _code_lines() -> Array[String]:
	var code: Array[String] = []
	for raw: String in _planner_source().split("\n"):
		var line: String = raw.strip_edges()
		# Doc comments legitimately DISCUSS the forbidden names — the seam's own
		# rationale is written at the call sites. The guard is about code.
		if line.begins_with("#"):
			continue
		code.append(raw)
	return code


# --- the chokepoint ----------------------------------------------------------


## **Occupancy is exactly what tiers gate.** `Grid` carries `occupant_id` and
## `get_occupant_id()` right beside `blockers` and `surfaces`, so handing the
## planner a raw grid would let it read the position of every unit on the board —
## including ones `units_visible_to` just filtered out. That is the whole seam
## bypassed by a one-line accessor, and a guard watching only `CombatState`
## fields would never see it.
func test_the_planner_never_reads_occupancy_off_the_grid() -> void:
	for line: String in _code_lines():
		assert_false(
			line.contains("occupant_id"),
			"occupancy must arrive through units_visible_to, not the grid: %s" % line.strip_edges()
		)


## The four information reads the seam exists to own. Geometry (`view.grid`) is
## deliberately absent from this list — it is free.
func test_the_planner_never_reads_unit_knowledge_off_a_combat_state() -> void:
	var forbidden: Array[String] = [
		"state.units", "state.batch_plans", "state.round_number", "state.squads"
	]
	for line: String in _code_lines():
		for needle: String in forbidden:
			assert_false(
				line.contains(needle),
				"%s must come from the WorldView: %s" % [needle, line.strip_edges()]
			)


## **The resolver door must stay a door and not become an accessor.** Passing the
## canonical state to `ShotPlane` is the intended use; reading a field off it is
## the entire seam defeated, and a guard watching direct field access would not
## catch it. So: never followed by a dot.
func test_the_resolver_door_is_never_dereferenced() -> void:
	for line: String in _code_lines():
		assert_false(
			line.contains("canonical_state_for_resolvers()."),
			"the resolver door may only be passed, never read through: %s" % line.strip_edges()
		)


## Guards that can pass because they are looking at nothing are worse than no
## guards. This proves the source was actually loaded and the seam is in use.
func test_the_guard_is_reading_a_real_planner_that_uses_the_view() -> void:
	var source: String = _planner_source()

	assert_gt(source.length(), 10000, "the planner source really was read")
	assert_true(source.contains("view: WorldView"), "the planner takes a view")
	assert_true(source.contains("units_visible_to"), "and gets its unit knowledge through it")


# --- the seam is load-bearing ------------------------------------------------


func _armed_unit(id: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var weapon := Part.new()
	weapon.id = StringName("%s_gun" % id)
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = 1
	weapon.provides_actions = [&"shoot"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 30.0
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


## **This matters more than the rest of the file**, because everything in part
## two is built on the assumption that restricting the view actually changes what
## a unit decides. If restriction changes nothing, the seam is decorative and
## part two is built on sand.
func test_a_restricted_view_makes_the_unit_decide_differently() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var hunter: Unit = _armed_unit(&"hunter", Vector2i(2, 8), 0)
	var hidden: Unit = _armed_unit(&"hidden", Vector2i(20, 8), 1)
	var state := CombatState.new(grid, [hunter, hidden])
	state.force_current_unit(hunter.id)
	for unit: Unit in state.units:
		unit.ap = unit.max_ap

	var full: WorldView = WorldView.full(state)
	assert_eq(
		UtilityContext.build(hunter, full).target, hidden, "unrestricted, it knows about the enemy"
	)

	var blind: WorldView = WorldView.full(state)
	blind.restricted = true
	# No line of sight and no remembered sighting: as far as this unit knows, the
	# board is empty.
	for y in range(grid.rows):
		GridFixture.place_wall(grid, Vector2i(11, y))

	assert_null(
		UtilityContext.build(hunter, blind).target,
		"restricted and with nothing remembered, there is no enemy to plan against"
	)


## Staleness is derived, never maintained — the round a sighting was taken is
## compared against the current round on read, so there is no invalidation hook
## at a round boundary that could be missed.
func test_a_remembered_sighting_expires_by_comparison_not_by_a_hook() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	for y in range(grid.rows):
		GridFixture.place_wall(grid, Vector2i(11, y))
	var hunter: Unit = _armed_unit(&"hunter", Vector2i(2, 8), 0)
	var hidden: Unit = _armed_unit(&"hidden", Vector2i(20, 8), 1)
	var state := CombatState.new(grid, [hunter, hidden])

	var view: WorldView = WorldView.full(state)
	view.restricted = true
	view.round_number = 5
	view.remembered[hidden.id] = {"cell": hidden.cell, "round_seen": 5}
	assert_has(view.units_visible_to(hunter), hidden, "a fresh sighting is usable")

	view.round_number = 5 + view.memory_rounds + 1

	assert_does_not_have(
		view.units_visible_to(hunter), hidden, "and an old one simply stops being returned"
	)


## The blackboard is a Trained-and-above capability, so batch plans sit on the
## observer-gated side rather than the free side. A Grunt reads nothing and plans
## for itself, which is correct behaviour for it rather than a degradation.
func test_the_team_blackboard_is_gated_on_tier() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var leader: Unit = _armed_unit(&"leader", Vector2i(2, 2), 0)
	var grunt: Unit = _armed_unit(&"grunt", Vector2i(3, 3), 0)
	var trained: Unit = _armed_unit(&"trained", Vector2i(4, 4), 0)
	var state := CombatState.new(grid, [leader, grunt, trained])
	for unit: Unit in state.units:
		unit.batch_id = 1
	grunt.intelligence_tier = &"GRUNT"
	trained.intelligence_tier = &"TRAINED"
	state.batch_plans.record(1, state.round_number, leader.id, Vector2i(9, 9))

	var view: WorldView = WorldView.full(state)
	assert_false(view.batch_plan_for(grunt).is_empty(), "unrestricted, every tier reads it")

	view.restricted = true

	assert_true(view.batch_plan_for(grunt).is_empty(), "a Grunt has no blackboard")
	assert_false(view.batch_plan_for(trained).is_empty(), "Trained does")


## Writing to the blackboard is gated exactly as reading it is — otherwise a
## Grunt could set a plan it could never read back.
func test_a_unit_without_blackboard_access_cannot_write_one_either() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var grunt: Unit = _armed_unit(&"grunt", Vector2i(3, 3), 0)
	grunt.batch_id = 1
	grunt.intelligence_tier = &"GRUNT"
	var state := CombatState.new(grid, [grunt])
	var view: WorldView = WorldView.full(state)
	view.restricted = true

	view.claim_batch_lead(grunt, Vector2i(9, 9))

	assert_true(state.batch_plans.for_batch(1, state.round_number).is_empty())


# --- flag off changes nothing ------------------------------------------------


func _action_sequence(state: CombatState, mission: MissionState, steps: int) -> Array[String]:
	var runner := BoutRunner.new(state, mission)
	var taken: Array[String] = []
	var i := 0
	while not runner.finished and i < steps:
		await runner.step()
		for event: LogEvent in runner.last_events:
			taken.append("%s@%d" % [event.kind, event.unit_id])
		i += 1
	return taken


func _bout(map_seed: int) -> Dictionary:
	var roster: Array[BoutRosterEntry] = []
	for i in range(2):
		var entry := BoutRosterEntry.new()
		entry.profile = DataLibrary.presets_pool()[i % DataLibrary.presets_pool().size()]
		roster.append(entry)
	return BoutSetup.build_bout(roster, roster, map_seed)


## The pass ships a doorway, not a behaviour change. `BoutRunner` builds the
## unrestricted view, so a seeded bout must produce exactly what it did before
## the seam existed.
func test_the_unrestricted_view_is_byte_identical_across_a_seeded_bout() -> void:
	var a: Dictionary = _bout(31337)
	assert_eq(a.get("error", ""), "", "sanity: the bout built")
	var expected: Array[String] = await _action_sequence(a.state, a.mission, 8)

	var b: Dictionary = _bout(31337)
	var actual: Array[String] = await _action_sequence(b.state, b.mission, 8)

	assert_eq(actual, expected)
	assert_gt(expected.size(), 0, "sanity: the bout actually did something")


## `dup()` is a TACTICS-time preview and does not carry batch plans — taskblock-43
## left that neither carried nor commented, and Pass C fixed the comment. This
## pins the behaviour the comment now describes.
func test_a_preview_clone_starts_with_no_batch_plans() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var unit: Unit = _armed_unit(&"unit", Vector2i(2, 2), 0)
	unit.batch_id = 1
	var state := CombatState.new(grid, [unit])
	state.batch_plans.record(1, state.round_number, unit.id, Vector2i(9, 9))

	var preview: CombatState = state.dup()

	assert_true(
		preview.batch_plans.for_batch(1, preview.round_number).is_empty(),
		"a throwaway clone must not answer 'who is leading this round'"
	)
	assert_false(
		state.batch_plans.for_batch(1, state.round_number).is_empty(), "and the real bout keeps its"
	)


func test_intelligence_tier_rides_through_dup() -> void:
	var unit: Unit = _armed_unit(&"unit", Vector2i(2, 2), 0)
	unit.intelligence_tier = &"ELITE"

	assert_eq(unit.dup().intelligence_tier, &"ELITE")
