extends GutTest

## taskblock-44 Pass D: a unit's turn becomes something you can watch instead of
## something you endure.
##
## taskblock-42 Pass D already yielded *between* `BoutRunner.step()` calls and it
## did not help, because one step is the entire think. The yield has to land
## **inside** one unit's plan, and the tests below are about exactly that
## distinction — a yield count taken across a single `plan_turn` call, not across
## a bout.
##
## The other half is that a visible "thinking" state which never ends is WORSE
## than a freeze: the player waits longer before concluding something is wrong.
## So the budget is not decoration, and it has its own cases here.


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
	weapon.weapon_def.max_range = 15.0
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


## Open ground with the enemy inside the defensive profile's reach, so the unit takes the
## repositioning path and there is a real candidate scan to slice.
func _field() -> Dictionary:
	var grid: Grid = GridFixture.flat(30, 24)
	var actor: Unit = _armed_unit(&"actor", Vector2i(5, 5), 0)
	var enemy: Unit = _armed_unit(&"enemy", Vector2i(8, 6), 1)
	var state := CombatState.new(grid, [actor, enemy])
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
	state.force_current_unit(actor.id)
	return {"state": state, "actor": actor, "enemy": enemy}


# --- the yield happens DURING one unit's plan --------------------------------


## The load-bearing one. A pacer carrying a real signal must suspend **more than
## once inside a single `plan_turn` call** — that is precisely what taskblock-42
## Pass D's between-units yield could not do, and the reason this pass exists.
func test_a_single_units_plan_yields_more_than_once_while_it_runs() -> void:
	var field: Dictionary = _field()
	var pacer := PlanPacer.new()
	pacer.frame_signal = get_tree().process_frame
	pacer.chunk = 1
	# A frame per candidate genuinely outruns the default budget — that is the
	# budget doing its job, not a defect — so this case buys enough headroom to
	# measure the yielding rather than the abort.
	pacer.budget_msec = 1000 * 60

	await AiPlanner.plan_turn(
		field["actor"], WorldView.full(field["state"]), null, &"defensive", pacer
	)

	assert_gt(pacer.yields, 1, "the main thread was handed back repeatedly DURING one plan")
	assert_false(pacer.aborted, "and it finished on its own rather than being cut off")


## Frames genuinely elapse while the plan runs — the yields are real suspensions,
## not a counter being incremented.
func test_real_frames_pass_while_one_unit_plans() -> void:
	var field: Dictionary = _field()
	var pacer := PlanPacer.new()
	pacer.frame_signal = get_tree().process_frame
	pacer.chunk = 1
	pacer.budget_msec = 1000 * 60
	# Counted off the real signal rather than a frame counter: this asserts the
	# tree actually ticked DURING the plan, which is the claim, and it holds
	# headless where a drawn-frame counter would not.
	var frames := [0]
	var tick: Callable = func() -> void: frames[0] += 1
	get_tree().process_frame.connect(tick)

	await AiPlanner.plan_turn(
		field["actor"], WorldView.full(field["state"]), null, &"defensive", pacer
	)
	get_tree().process_frame.disconnect(tick)

	assert_gt(frames[0], 0, "the tree kept running while the unit thought")


## No pacer means no suspension at all, which is what keeps every headless test
## and the whole existing suite behaving exactly as before.
func test_a_headless_plan_never_suspends() -> void:
	var field: Dictionary = _field()
	var pacer := PlanPacer.new()  # deliberately no frame_signal
	pacer.chunk = 1

	await AiPlanner.plan_turn(
		field["actor"], WorldView.full(field["state"]), null, &"defensive", pacer
	)

	assert_eq(pacer.yields, 0, "nobody is watching, so nothing yields")


# --- the budget guarantees the turn ends -------------------------------------


## **A thinking state that never ends is worse than a freeze.** Past the budget
## the scan stops where it is and the unit acts on its best cell so far.
func test_an_overrun_budget_ends_the_scan_rather_than_extending_it() -> void:
	var field: Dictionary = _field()
	var pacer := PlanPacer.new()
	pacer.budget_msec = 0  # already overrun on the first candidate

	var queue: ActionQueue = await AiPlanner.plan_turn(
		field["actor"], WorldView.full(field["state"]), null, &"defensive", pacer
	)

	assert_true(pacer.aborted, "the budget fired")
	assert_gt(queue.actions.size(), 0, "and the unit still produced a real turn")


## Aborting is safe at any iteration, because candidates are only ever APPENDED to
## the scored list — so `UtilityScorer.best_index` over a cut-off scan returns the
## best of what was actually scored, which is a legitimate answer at every point
## rather than a partial one.
##
## taskblock-45 Pass E: this used to assert the retired planner's own version of
## the property — an incumbent seeded with the unit's own cell and replaced only on
## a strict improvement. The property survived the planner; the mechanism did not.
func test_an_aborted_scan_still_returns_a_usable_turn() -> void:
	var field: Dictionary = _field()
	var pacer := PlanPacer.new()
	pacer.budget_msec = 0
	pacer.frame_signal = get_tree().process_frame

	var queue: ActionQueue = await AiPlanner.plan_turn(
		field["actor"], WorldView.full(field["state"]), null, &"defensive", pacer
	)

	assert_true(pacer.aborted, "cut off on the first candidate")
	assert_gt(queue.actions.size(), 0, "and the turn still ends rather than hanging")


func test_the_budget_latches_so_it_reports_the_same_answer_twice() -> void:
	var pacer := PlanPacer.new()
	pacer.budget_msec = 0
	pacer.begin()

	assert_true(pacer.should_abort())
	assert_true(pacer.should_abort(), "latched, so a repeated ask is stable")


# --- the label names the unit ------------------------------------------------


## **"Unit 2 is thinking…", never "Thinking…".** Once named enemies exist, the
## difference between a mook's turn and a boss's turn reads as character rather
## than as lag.
func test_the_label_names_the_acting_unit() -> void:
	var grid: Grid = GridFixture.flat(10, 10)
	var unit: Unit = _armed_unit(&"actor", Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])

	var label: String = PlanPacer.thinking_label(state.units[0])

	assert_true(label.ends_with("is thinking…"))
	assert_ne(label, "is thinking…", "it names something")
	assert_false(label.begins_with("is thinking"), "the name comes first")


## A matrix with a real display name is used in preference to the bare unit id —
## the same fallback convention `InspectPanel` already follows.
func test_the_label_prefers_a_real_display_name() -> void:
	var unit: Unit = _armed_unit(&"actor", Vector2i(2, 2), 0)
	unit.id = 7
	unit.matrix.display_name = "Sergeant Vole"

	assert_eq(PlanPacer.thinking_label(unit), "Sergeant Vole is thinking…")


func test_the_label_falls_back_to_the_unit_id() -> void:
	var unit: Unit = _armed_unit(&"actor", Vector2i(2, 2), 0)
	unit.id = 2
	unit.matrix.display_name = ""
	unit.matrix.id = &""

	assert_eq(PlanPacer.thinking_label(unit), "Unit 2 is thinking…")


func test_no_unit_means_no_label() -> void:
	assert_eq(PlanPacer.thinking_label(null), "")


# --- frame boundaries must not change decisions ------------------------------


func _action_sequence(
	state: CombatState, mission: MissionState, steps: int, pacer: PlanPacer
) -> Array[String]:
	var runner := BoutRunner.new(state, mission)
	runner.pacer = pacer
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


## **The acceptance for the whole pass.** Slicing is a pacing device; where the
## frame boundaries land must not be observable in the sim. A generous budget is
## used deliberately so this measures the effect of yielding, not of aborting —
## an abort genuinely does change the choice, which is the trade the budget makes
## and is covered separately above.
func test_a_seeded_bout_is_identical_with_and_without_slicing() -> void:
	var plain: Dictionary = _bout(31337)
	assert_eq(plain.get("error", ""), "", "sanity: the bout built")
	var expected: Array[String] = await _action_sequence(plain.state, plain.mission, 6, null)

	var sliced_pacer := PlanPacer.new()
	sliced_pacer.frame_signal = get_tree().process_frame
	sliced_pacer.chunk = 3
	sliced_pacer.budget_msec = 1000 * 60
	var sliced: Dictionary = _bout(31337)
	var actual: Array[String] = await _action_sequence(
		sliced.state, sliced.mission, 6, sliced_pacer
	)

	assert_eq(actual, expected, "frame boundaries must not change decisions")
	assert_gt(sliced_pacer.yields, 0, "and the sliced run really did yield")
