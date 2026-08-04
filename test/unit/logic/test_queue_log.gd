extends GutTest

## taskblock-57 Pass D — **queueing is legible in the combat log.**
##
## This is the *replacement* half of a retirement, and the taskblock puts it in its own
## stop-and-report list: *"A retirement loses coverage — particularly `queue_panel`'s confirmation
## role. The log entries are the replacement and must land first."* So these assertions exist before
## the panel goes, not after.
##
## The four shapes the taskblock names, verbatim:
##
##     unit 0 queued a move to (0,0,1)
##     unit 0 queued action: burst
##     unit 0 cancelled move
##     unit 0 cancelled action: burst

## A bout with a `MemorySink` on its log, so the event stream is readable. `CombatLog` fans out to
## sinks and keeps nothing itself, which is the right shape for it and means a test that wants the
## stream has to attach somewhere to hear it.
var _sink: MemorySink = null


func _state() -> CombatState:
	var grid: Grid = GridFixture.flat(12, 10)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	state.assign_all_to_human()
	_sink = MemorySink.new()
	state.combat_log.add_sink(_sink)
	return state


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## Every line the log has been handed, newest last.
func _lines(_state_unused: CombatState) -> Array[String]:
	var out: Array[String] = []
	for event: LogEvent in _sink.events:
		out.append(event.text)
	return out


func _queue_lines(_state_unused: CombatState) -> Array[String]:
	var out: Array[String] = []
	for event: LogEvent in _sink.events:
		if event.kind == QueueLog.QUEUED or event.kind == QueueLog.CANCELLED:
			out.append(event.text)
	return out


## Reachable cells that are not the one the unit already stands on.
func _elsewhere(selection: SelectionController, state: CombatState) -> Array[Vector2i]:
	var here: Vector2i = state.units[0].cell
	return selection.reachable_cells().filter(func(c: Vector2i) -> bool: return c != here)


# ---------------------------------------------------------------- on queue


## **THE ACCEPTANCE, first half**: the queuing log entries appear on queue.
func test_queueing_a_move_says_where_it_is_going() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	var target: Vector2i = _elsewhere(selection, state)[0]

	assert_true(selection.queue_move(target), "sanity: the move was accepted")

	var lines: Array[String] = _queue_lines(state)
	gut.p("queue lines: %s" % str(lines))
	assert_eq(lines.size(), 1, "one confirmation per accepted click")
	# **The destination is the point.** "queued a move" without a cell fails at the one thing this
	# line exists for: you clicked a cell and want to know which cell it heard.
	assert_true(
		lines[0].contains("(%d,%d)" % [target.x, target.y]),
		"the line must name the cell that was clicked: %s" % lines[0]
	)
	assert_true(lines[0].begins_with("unit %d queued" % state.units[0].id))


## An action names itself rather than reading as a bare "queued something".
func test_queueing_a_non_move_action_names_the_action() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])

	# End Turn rather than Hold: Hold has its own legality gate and is refused for a fresh unit,
	# which would make this test measure the refusal path instead of the naming.
	assert_true(selection.queue_end_turn(), "sanity: ending a turn is always queueable")

	var lines: Array[String] = _queue_lines(state)
	gut.p("queue lines: %s" % str(lines))
	assert_eq(lines.size(), 1)
	assert_true(lines[0].contains("action:"), "a non-move says 'action: <what>': %s" % lines[0])


## **A refused click must not be confirmed.** A confirmation for something the queue rejected is
## worse than no confirmation at all: it says the queue holds an action it does not.
func test_a_rejected_action_produces_no_confirmation() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	state.units[0].ap = 0
	state.units[0].mp = 0.0

	# Somewhere it cannot reach with no MP at all.
	var refused: bool = selection.queue_move(Vector2i(9, 8))

	assert_false(refused, "sanity: the fixture must actually be refused, or this proves nothing")
	assert_true(_queue_lines(state).is_empty(), "nothing landed, so nothing was confirmed")


# ---------------------------------------------------------------- on cancel


## **THE ACCEPTANCE, second half**: the entries appear on cancel too.
func test_undoing_the_last_action_logs_a_cancellation() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	var target: Vector2i = _elsewhere(selection, state)[0]
	selection.queue_move(target)

	assert_true(selection.undo_last(), "sanity: there was something to undo")

	var lines: Array[String] = _queue_lines(state)
	gut.p("queue lines: %s" % str(lines))
	assert_eq(lines.size(), 2, "one for the queue, one for the cancellation")
	assert_true(lines[1].contains("cancelled"), "the second line is the cancellation")
	assert_true(lines[1].contains("move"), "and it says what was cancelled: %s" % lines[1])


## Undoing nothing logs nothing — the empty-queue RMB case, which deselects rather than cancelling.
func test_undoing_an_empty_queue_logs_nothing() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])

	assert_false(selection.undo_last())
	assert_true(_queue_lines(state).is_empty())


## Reset Turn drops everything, so it says so once per action rather than emptying in silence.
func test_resetting_the_turn_cancels_every_queued_action() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	var reachable: Array[Vector2i] = _elsewhere(selection, state)
	selection.queue_move(reachable[0])
	selection.queue_move(reachable[1])
	var queued: int = _queue_lines(state).size()

	selection.reset_turn()

	var cancels: int = _queue_lines(state).size() - queued
	gut.p("queued %d, cancelled %d" % [queued, cancels])
	assert_eq(cancels, queued, "every queued action must be accounted for")


# ---------------------------------------------------------------- and they fold


## **THE ACCEPTANCE, third part**: *"and fold together."* Five queued legs must be one row that
## opens into five, not five rows pushing the fight off the top of the panel.
func test_consecutive_queue_entries_fold_into_one_drillable_row() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	var fold := LogFold.new(state)
	var reachable: Array[Vector2i] = _elsewhere(selection, state)

	var queued: int = 0
	for i in range(3):
		if selection.queue_move(reachable[i]):
			queued += 1
	assert_gt(queued, 1, "sanity: more than one queue line, or folding proves nothing")
	for event: LogEvent in _sink.events:
		if event.kind == QueueLog.QUEUED:
			fold.ingest(event)

	gut.p("groups: %d for %d queued events" % [fold.groups.size(), queued])
	assert_eq(fold.groups.size(), 1, "a run of queue lines is ONE row")
	assert_eq(
		fold.groups[0].detail_lines().size(),
		queued,
		"and every one of them is still drillable underneath it"
	)


## The two kinds are separate rows. A run of queues followed by a run of cancels is two things that
## happened, and folding them together would say one.
func test_queues_and_cancels_do_not_fold_into_each_other() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	var fold := LogFold.new(state)
	var reachable: Array[Vector2i] = _elsewhere(selection, state)
	selection.queue_move(reachable[0])
	selection.queue_move(reachable[1])
	selection.undo_last()

	for event: LogEvent in _sink.events:
		if event.kind == QueueLog.QUEUED or event.kind == QueueLog.CANCELLED:
			fold.ingest(event)

	assert_eq(fold.groups.size(), 2, "queues fold with queues, cancels with cancels")


# ---------------------------------------------------------------- one path in


## **No parallel systems.** Every player-queued action goes through `SelectionController.enqueue`,
## which is what makes one confirmation line cover nine former call sites. A direct
## `current_queue().enqueue` would queue the action and log nothing — asserted here so a future
## caller taking the short cut fails a test rather than silently losing the confirmation.
func test_reaching_past_the_one_path_is_what_loses_the_confirmation() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	var unit: Unit = state.units[0]
	var pf := Pathfinder.new(state.grid, unit.shell.can_climb())
	var path: Array[Vector2i] = pf.astar(unit.cell, Vector2i(3, 2))

	assert_true(
		selection.current_queue().enqueue(MoveAction.new(unit, path), state),
		"sanity: the raw enqueue was accepted, so silence means silence and not refusal"
	)
	assert_true(_queue_lines(state).is_empty(), "the raw queue does not log -- that is the point")

	# **A second state, not a second call on this one.** The first move already spent the MP, so
	# re-queueing the same path here would be refused and the missing line would prove nothing.
	var fresh: CombatState = _state()
	var other := SelectionController.new(fresh)
	other.select(fresh.units[0])
	assert_true(other.enqueue(MoveAction.new(fresh.units[0], path)), "sanity: accepted")
	assert_eq(_queue_lines(fresh).size(), 1, "the one path does log")


## The lines are TACTICS-phase, which is what they describe. A queue confirmation filed under
## RESOLUTION would be claiming something resolved.
func test_the_entries_are_filed_under_tactics() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	selection.queue_end_turn()

	for event: LogEvent in _sink.events:
		if event.kind == QueueLog.QUEUED:
			assert_eq(event.phase, Enums.Phase.TACTICS, "queueing happens in TACTICS")
			return
	fail_test("no queue event was emitted at all")


## Sanity that the whole file is not measuring an empty log.
func test_the_fixture_produces_a_real_log() -> void:
	var state: CombatState = _state()
	var selection := SelectionController.new(state)
	selection.select(state.units[0])
	selection.queue_end_turn()
	assert_false(_lines(state).is_empty(), "the fixture's log must actually receive events")
