extends GutTest

## taskblock-29 Pass A: the injection channel — boundary-only, logged.
## Pass B's own verbs get their own test file; this one exercises the
## shared `_guard`/`_log_injection` machinery through `force_current_unit`,
## the one verb Pass A itself ships.


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_can_inject_is_true_outside_resolution() -> void:
	var state := CombatState.new(Grid.new(5, 5))
	var injector := BoutInjector.new(state)

	assert_true(injector.can_inject())


func test_can_inject_is_false_while_resolving() -> void:
	var state := CombatState.new(Grid.new(5, 5))
	var injector := BoutInjector.new(state)

	state.is_resolving = true

	assert_false(injector.can_inject())


func test_a_verb_mutates_and_logs_at_a_step_boundary() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var injector := BoutInjector.new(state)

	var ok: bool = injector.force_current_unit(b)

	assert_true(ok)
	assert_eq(state.current_unit(), b)
	var events: Array[LogEvent] = sink.events_of_kind(&"inject")
	assert_eq(events.size(), 1, "every injection must emit exactly one &\"inject\" event")
	assert_eq(events[0].data.get("verb"), &"force_current_unit")


## The TESTS bar this taskblock names literally: "a mid-resolution
## injection attempt is rejected."
func test_a_mid_resolution_injection_attempt_is_rejected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var injector := BoutInjector.new(state)
	state.is_resolving = true

	var ok: bool = injector.force_current_unit(b)

	assert_false(ok)
	assert_push_error("mid-resolution")
	assert_ne(state.current_unit(), b, "a rejected injection must never mutate anything")
	assert_eq(
		sink.events_of_kind(&"inject").size(), 0, "a rejected injection must never log anything"
	)
	assert_false(state.was_injected, "a rejected injection must never flip the determinism flag")


func test_a_rejected_injection_is_a_true_noop_never_marks_the_bout_injected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)
	state.is_resolving = true

	injector.force_current_unit(a)

	assert_push_error("mid-resolution")
	assert_false(state.was_injected)


func test_a_successful_injection_marks_the_bout_as_injected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	var injector := BoutInjector.new(state)
	assert_false(state.was_injected, "sanity: a fresh bout is never pre-marked")

	injector.force_current_unit(b)

	assert_true(state.was_injected)
