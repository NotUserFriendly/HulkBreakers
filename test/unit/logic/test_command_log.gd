extends GutTest

## taskblock-41 Pass C: "what was sent" paired with "what happened". A verb
## that quietly returns false looks identical, from outside, to a verb that ran
## and had no effect — this pass makes the difference readable, with a REASON
## rather than a bare failure.


func _state() -> CombatState:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var other: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 1)
	return CombatState.new(grid, [unit, other])


func _sink_on(state: CombatState) -> MemorySink:
	var memory := MemorySink.new()
	state.combat_log.add_sink(memory)
	return memory


func _outcomes(memory: MemorySink) -> Array[LogEvent]:
	return memory.events_of_kind(CommandLog.OUTCOME_KIND)


func _commands(memory: MemorySink) -> Array[LogEvent]:
	return memory.events_of_kind(CommandLog.COMMAND_KIND)


# --- the pair itself ---------------------------------------------------------


func test_a_refused_injection_produces_a_paired_command_and_outcome_with_a_reason() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	var injector := BoutInjector.new(state)

	# Cell (2, 2) is occupied by the second unit — a genuine refusal.
	var ok: bool = injector.set_position(state.units[0], Vector2i(2, 2))

	assert_false(ok, "the verb still refuses")
	assert_eq(_commands(memory).size(), 1, "what was sent")
	assert_eq(_outcomes(memory).size(), 1, "what happened")
	var outcome: LogEvent = _outcomes(memory)[0]
	assert_false(outcome.data["accepted"])
	assert_eq(outcome.data["verb"], &"set_position")
	assert_eq(outcome.data["reason"], &"destination_occupied", "a REASON, not just a failure")
	assert_ne(outcome.data["reason"], &"", "an empty reason is the outcome this pass deletes")


func test_an_accepted_injection_also_produces_the_pair() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	var injector := BoutInjector.new(state)

	assert_true(injector.set_position(state.units[0], Vector2i(4, 4)))

	assert_eq(_commands(memory).size(), 1)
	var outcome: LogEvent = _outcomes(memory)[0]
	assert_true(outcome.data["accepted"], "success is an outcome too, not just an absence")
	assert_eq(outcome.data["reason"], &"", "nothing to explain when it worked")
	assert_eq(
		memory.events_of_kind(&"inject").size(),
		1,
		"the pre-existing rich inject event is untouched"
	)


func test_the_command_half_records_the_arguments_that_were_sent() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	var injector := BoutInjector.new(state)

	injector.set_part_hp(state.units[0], &"definitely_not_a_part", 5)

	var command: LogEvent = _commands(memory)[0]
	assert_eq(command.data["verb"], &"set_part_hp")
	assert_eq(command.data["part"], &"definitely_not_a_part", "reconstructable from the log alone")
	assert_eq(command.data["hp"], 5)
	assert_eq(_outcomes(memory)[0].data["reason"], &"no_such_part")


# --- previously-silent paths -------------------------------------------------


## Each of the verbs below returned a bare `false` before this pass, with no
## push_error and no log line — the genuinely silent ones the taskblock names
## as the real target. One test each rather than a table of lambdas: a failure
## names the verb that broke without decoding an index.
func _assert_only_refusal(memory: MemorySink, verb: StringName, reason: StringName) -> void:
	var outcomes: Array[LogEvent] = _outcomes(memory)
	assert_eq(outcomes.size(), 1, "%s logged exactly one outcome" % verb)
	if outcomes.is_empty():
		return
	assert_eq(outcomes[0].data["verb"], verb)
	assert_eq(outcomes[0].data["reason"], reason, "%s named its reason" % verb)


func test_clear_cover_on_an_empty_cell_now_says_why() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	BoutInjector.new(state).clear_cover(Vector2i(3, 3))
	_assert_only_refusal(memory, &"clear_cover", &"no_blocker_at_cell")


func test_place_cover_with_an_unknown_part_now_says_why() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	BoutInjector.new(state).place_cover(Vector2i(3, 3), &"nope", {})
	_assert_only_refusal(memory, &"place_cover", &"unknown_part_id")


func test_set_passable_off_the_grid_now_says_why() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	BoutInjector.new(state).set_passable(Vector2i(99, 99), false)
	_assert_only_refusal(memory, &"set_passable", &"out_of_bounds")


func test_set_cell_level_off_the_grid_now_says_why() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	BoutInjector.new(state).set_cell_level(Vector2i(99, 99), 1.0)
	_assert_only_refusal(memory, &"set_cell_level", &"out_of_bounds")


func test_remove_object_on_an_empty_cell_now_says_why() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	BoutInjector.new(state).remove_object({"kind": Enums.HitKind.CELL, "cell": Vector2i(3, 3)})
	_assert_only_refusal(memory, &"remove_object", &"nothing_at_cell")


func test_move_object_from_an_empty_cell_now_says_why() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	var target: Dictionary = {"kind": Enums.HitKind.CELL, "cell": Vector2i(3, 3)}
	BoutInjector.new(state).move_object(target, Vector2i(4, 4))
	_assert_only_refusal(memory, &"move_object", &"nothing_at_source")


## Three genuinely different failures used to collapse into one null inside
## `_attach`, so neither caller could report which.
func test_attach_part_distinguishes_an_unknown_part_from_an_unknown_socket() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	BoutInjector.new(state).attach_part(state.units[0], &"nope", &"SOCKET_MAIN", {})
	_assert_only_refusal(memory, &"attach_part", &"unknown_part_id")

	var other_state: CombatState = _state()
	var other_memory: MemorySink = _sink_on(other_state)
	var pool: Dictionary = DeepStrike.reference_humanoid_pool()
	var known_part: StringName = pool.keys()[0]
	BoutInjector.new(other_state).attach_part(
		other_state.units[0], known_part, &"NOT_A_REAL_SOCKET", pool
	)
	_assert_only_refusal(other_memory, &"attach_part", &"no_such_socket")


func test_killing_an_already_dead_unit_now_says_why() -> void:
	var state: CombatState = _state()
	state.kill_unit(state.units[1])
	var memory: MemorySink = _sink_on(state)
	BoutInjector.new(state).kill(state.units[1])
	_assert_only_refusal(memory, &"kill", &"already_dead")


# --- the two-phase distinction -----------------------------------------------


## "A command queued in TACTICS and a command refused at RESOLUTION are
## different events and should read differently."
func test_a_tactics_refusal_and_a_resolution_refusal_read_differently() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	var injector := BoutInjector.new(state)

	injector.clear_cover(Vector2i(3, 3))
	var tactics_refusal: LogEvent = _outcomes(memory)[0]

	state.is_resolving = true
	injector.clear_cover(Vector2i(3, 3))
	var resolution_refusal: LogEvent = _outcomes(memory)[1]
	state.is_resolving = false
	assert_push_error_count(1, "the mid-resolution guard raises its own error on purpose")

	assert_eq(tactics_refusal.phase, Enums.Phase.TACTICS)
	assert_eq(resolution_refusal.phase, Enums.Phase.RESOLUTION)
	assert_ne(tactics_refusal.text, resolution_refusal.text, "they must not read the same")
	assert_true(tactics_refusal.text.find(CommandLog.TACTICS_REFUSAL) != -1)
	assert_true(resolution_refusal.text.find(CommandLog.RESOLUTION_REFUSAL) != -1)
	assert_eq(
		resolution_refusal.data["reason"],
		&"mid_resolution",
		"and the resolution refusal names the phase gate as its reason"
	)


# --- the action path ---------------------------------------------------------


func test_try_apply_no_longer_refuses_silently() -> void:
	var state: CombatState = _state()
	var memory: MemorySink = _sink_on(state)
	# An EndTurnAction for a unit whose turn it is not — illegal, and before
	# this pass it returned false with nothing written anywhere.
	var not_their_turn := EndTurnAction.new(state.units[1])

	assert_false(state.try_apply(not_their_turn))

	var outcomes: Array[LogEvent] = _outcomes(memory)
	assert_eq(outcomes.size(), 1)
	assert_eq(outcomes[0].data["verb"], &"try_apply")
	assert_eq(outcomes[0].data["reason"], &"action_illegal")
	assert_ne(outcomes[0].data["action"], "", "and it names WHICH action was refused")


## The interrupted unit's refused action must be visible in the log, and every
## other unit's queue must be untouched — in the log as well as in state.
func test_the_pairing_survives_a_resolve_until_stop() -> void:
	var state: CombatState = _state()
	var mover: Unit = state.units[0]
	var blocker: Unit = state.units[1]
	var memory: MemorySink = _sink_on(state)

	# Walk straight into the cell the other unit is standing in: legal to
	# queue, illegal by the time it resolves.
	var queue := ActionQueue.new(mover)
	queue.actions.append(MoveAction.new(mover, [Vector2i(1, 1), Vector2i(2, 2)]))
	queue.actions.append(EndTurnAction.new(mover))
	mover.mp = 10.0
	mover.ap = 10

	var outcome: Dictionary = state.resolve_until(queue)

	assert_eq(outcome.kind, Enums.ResolveOutcome.STOPPED, "the queue really did stop")
	var stops: Array[LogEvent] = memory.events_of_kind(&"resolution_stopped")
	assert_eq(stops.size(), 1)
	assert_eq(stops[0].unit_id, mover.id, "attributed to the interrupted unit")
	assert_ne(stops[0].data["action"], "", "and it names the action that could not run")
	assert_true(
		stops[0].data["action"].find("Move") != -1, "which is the move, not the trailing end-turn"
	)
	# The other unit was never part of this queue and must not appear in any
	# outcome the stop produced.
	for event: LogEvent in _outcomes(memory):
		assert_ne(
			event.unit_id, blocker.id, "an unrelated unit's queue is untouched in the log too"
		)
	assert_true(blocker.alive)
	assert_eq(blocker.cell, Vector2i(2, 2), "and untouched in state")
