extends GutTest

## taskblock-41 Pass B: engine and script errors on the SAME stream as combat
## events. Almost everything here drives `EngineErrorTap.report()` directly
## rather than raising a real error, deliberately: `OS.add_logger` is
## process-global, so a test that installs a tap and then raises errors would
## capture every OTHER test's engine errors for as long as it stayed
## installed. Exactly one test below does the real install round-trip, and it
## uninstalls in the same function.


class DiagnosticFreeSink:
	extends LogSink

	## The concrete "I only want the game's own events" filter — authored by
	## the test, not shipped as a class nobody asked for (CLAUDE.md: if a
	## test needs a concrete list, the test authors it as a fixture).
	var events: Array[LogEvent] = []

	func wants(event: LogEvent) -> bool:
		return not event.is_diagnostic()

	func emit(event: LogEvent) -> void:
		events.append(event)


func _combat_event(text: String) -> LogEvent:
	return LogEvent.new(3, Enums.Phase.RESOLUTION, 7, &"impact", {}, text)


func _tap_on(log: CombatLog) -> EngineErrorTap:
	var tap := EngineErrorTap.new()
	tap.watch(log)
	return tap


func test_a_diagnostic_lands_in_the_stream_ordered_against_surrounding_events() -> void:
	var log := CombatLog.new()
	var memory := MemorySink.new()
	log.add_sink(memory)
	var tap: EngineErrorTap = _tap_on(log)

	log.emit(_combat_event("before"))
	tap.report(Logger.ERROR_TYPE_ERROR, "resolve", "res://src/logic/x.gd", 12, "boom", "")
	log.emit(_combat_event("after"))

	assert_eq(memory.events.size(), 3, "one stream — the diagnostic is not a separate log")
	assert_eq(memory.events[0].text, "before")
	assert_true(memory.events[1].is_diagnostic(), "and it sits exactly where it happened")
	assert_eq(memory.events[2].text, "after")


func test_every_logger_error_type_maps_to_its_own_severity() -> void:
	var expected: Dictionary = {
		Logger.ERROR_TYPE_ERROR: &"error",
		Logger.ERROR_TYPE_WARNING: &"warning",
		Logger.ERROR_TYPE_SCRIPT: &"script",
		Logger.ERROR_TYPE_SHADER: &"shader",
	}
	var tap := EngineErrorTap.new()
	for error_type: int in expected:
		var event: LogEvent = tap.build_event(error_type, "fn", "res://a.gd", 1, "code", "why")
		assert_eq(event.data["severity"], expected[error_type])


## A `push_error` puts its message in `code` with an empty `rationale`; an
## engine `ERR_FAIL_COND_MSG` puts the failed condition in `code` and the
## human sentence in `rationale`. The rendered text prefers the human half —
## and neither half is ever dropped from `data`.
func test_text_prefers_the_rationale_but_data_keeps_both_halves() -> void:
	var tap := EngineErrorTap.new()

	var pushed: LogEvent = tap.build_event(
		Logger.ERROR_TYPE_ERROR, "push_error", "variant_utility.cpp", 1023, "no ammo left", ""
	)
	assert_true(
		pushed.text.find("no ammo left") != -1, "falls back to code when rationale is empty"
	)

	var engine_error: LogEvent = tap.build_event(
		Logger.ERROR_TYPE_ERROR,
		"load",
		"core_bind.cpp",
		82,
		'Condition "err != OK" is true.',
		"Error loading resource: 'res://missing.tres'."
	)
	assert_true(engine_error.text.find("Error loading resource") != -1, "prefers the human half")
	assert_eq(engine_error.data["code"], 'Condition "err != OK" is true.', "and keeps the other")
	assert_eq(engine_error.data["rationale"], "Error loading resource: 'res://missing.tres'.")


func test_a_diagnostic_is_stamped_with_the_watched_battles_turn_and_phase() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	state.round_number = 4
	state.is_resolving = true
	var tap := EngineErrorTap.new()
	tap.watch(state.combat_log, state)

	var event: LogEvent = tap.build_event(Logger.ERROR_TYPE_SCRIPT, "fn", "res://a.gd", 9, "c", "")
	assert_eq(event.turn, 4)
	assert_eq(event.phase, Enums.Phase.RESOLUTION)
	assert_eq(event.unit_id, state.current_unit().id)


func test_with_no_state_it_still_logs_just_without_the_stamping() -> void:
	var log := CombatLog.new()
	var memory := MemorySink.new()
	log.add_sink(memory)
	var tap: EngineErrorTap = _tap_on(log)

	tap.report(Logger.ERROR_TYPE_ERROR, "fn", "res://a.gd", 3, "still logged", "")

	assert_eq(memory.events.size(), 1)
	assert_eq(memory.events[0].unit_id, -1, "no state to stamp from, so no unit claimed")


func test_a_sink_can_decline_diagnostics_while_still_taking_combat_events() -> void:
	var log := CombatLog.new()
	var everything := MemorySink.new()
	var game_only := DiagnosticFreeSink.new()
	log.add_sink(everything)
	log.add_sink(game_only)
	var tap: EngineErrorTap = _tap_on(log)

	log.emit(_combat_event("a real hit"))
	tap.report(Logger.ERROR_TYPE_WARNING, "fn", "res://a.gd", 1, "noise", "")

	assert_eq(everything.events.size(), 2, "the stream itself carries both")
	assert_eq(game_only.events.size(), 1, "the filtering sink took only the combat event")
	assert_eq(game_only.events[0].text, "a real hit")


## docs/09's own sink table, unchanged: none of these three knows what a
## diagnostic is, and none of them needs to.
func test_memory_file_and_stdout_sinks_all_carry_diagnostics_without_special_casing() -> void:
	const TEST_PATH := "user://test_engine_error_tap.log"
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

	var log := CombatLog.new()
	var memory := MemorySink.new()
	var file := FileSink.new(TEST_PATH)
	log.add_sink(memory)
	log.add_sink(file)
	log.add_sink(StdoutSink.new())
	var tap: EngineErrorTap = _tap_on(log)

	tap.report(
		Logger.ERROR_TYPE_SCRIPT, "plan_turn", "res://src/logic/ai/some_script.gd", 412, "x", ""
	)
	file.close()

	assert_eq(memory.events_of_kind(LogEvent.DIAGNOSTIC_KIND).size(), 1)
	var handle := FileAccess.open(TEST_PATH, FileAccess.READ)
	var contents: String = handle.get_as_text()
	handle.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	assert_true(contents.find("some_script.gd:412") != -1, "the file sink wrote it verbatim")


## An error raised while a sink is handling an error would re-enter the tap
## forever. A dropped nested diagnostic is the correct failure.
func test_an_error_raised_while_emitting_does_not_recurse() -> void:
	var log := CombatLog.new()
	var memory := MemorySink.new()
	var tap: EngineErrorTap = _tap_on(log)
	var reentrant := ReentrantSink.new()
	reentrant.tap = tap
	log.add_sink(reentrant)
	log.add_sink(memory)

	tap.report(Logger.ERROR_TYPE_ERROR, "fn", "res://a.gd", 1, "outer", "")

	assert_eq(memory.events.size(), 1, "the nested diagnostic was dropped, not stacked")
	assert_true(reentrant.re_entered, "and the nested attempt really did happen")


class ReentrantSink:
	extends LogSink

	var tap: EngineErrorTap
	var re_entered := false

	func emit(_event: LogEvent) -> void:
		if re_entered:
			return
		re_entered = true
		# Exactly what an erroring sink would do to the tap mid-emit.
		tap.report(Logger.ERROR_TYPE_ERROR, "fn", "res://a.gd", 2, "nested", "")


## The one test that touches the process-global registration, so the mapping
## tests above never have to. Installs, raises a REAL `push_error`, and
## uninstalls in the same function.
func test_a_real_push_error_is_captured_once_installed_and_never_after_removal() -> void:
	var log := CombatLog.new()
	var memory := MemorySink.new()
	log.add_sink(memory)
	var tap: EngineErrorTap = _tap_on(log)

	tap.install()
	assert_true(tap.is_installed())
	tap.install()  # idempotent — a second registration would double every error
	push_error("taskblock-41 Pass B: deliberate, expected error from a test")
	tap.uninstall()
	push_error("taskblock-41 Pass B: deliberate, expected error AFTER uninstall")

	# Both `push_error`s above are deliberate. GUT installs its own `Logger`
	# (`addons/gut/error_tracker.gd`) and fails any test that raises an
	# unhandled engine error, so they are claimed here explicitly — which
	# also independently confirms two loggers coexist on one process, the
	# assumption `EngineErrorTap` is built on.
	assert_push_error_count(2, "both raised on purpose")

	var diagnostics: Array[LogEvent] = memory.events_of_kind(LogEvent.DIAGNOSTIC_KIND)
	assert_eq(diagnostics.size(), 1, "captured exactly once while installed, not after")
	assert_true(diagnostics[0].text.find("deliberate, expected error from a test") != -1)
	assert_eq(diagnostics[0].data["severity"], &"error")
	assert_false(tap.is_installed())
