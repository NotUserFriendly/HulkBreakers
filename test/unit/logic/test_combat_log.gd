extends GutTest


func test_memory_sink_collects_events() -> void:
	var log := CombatLog.new()
	var sink := MemorySink.new()
	log.add_sink(sink)

	var event := LogEvent.new(
		1, Enums.Phase.RESOLUTION, 3, &"shot_fired", {"target": 7}, "unit 3 fired at unit 7"
	)
	log.emit(event)

	assert_eq(sink.events.size(), 1)
	assert_eq(sink.events[0], event)


func test_events_of_kind_filters() -> void:
	var sink := MemorySink.new()
	sink.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 1, &"shot_fired"))
	sink.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 1, &"deflection"))
	sink.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 1, &"shot_fired"))

	var shots: Array[LogEvent] = sink.events_of_kind(&"shot_fired")
	assert_eq(shots.size(), 2)


func test_log_dispatches_to_multiple_sinks() -> void:
	var log := CombatLog.new()
	var sink_a := MemorySink.new()
	var sink_b := MemorySink.new()
	log.add_sink(sink_a)
	log.add_sink(sink_b)

	log.emit(LogEvent.new(1, Enums.Phase.TACTICS, 0, &"queued"))

	assert_eq(sink_a.events.size(), 1)
	assert_eq(sink_b.events.size(), 1)


func test_log_event_to_string_is_readable() -> void:
	var event := LogEvent.new(
		2, Enums.Phase.RESOLUTION, 5, &"penetration", {}, "round penetrates plate"
	)
	var text: String = event._to_string()
	assert_true(text.contains("T2"))
	assert_true(text.contains("RESOLUTION"))
	assert_true(text.contains("unit 5"))
	assert_true(text.contains("penetration"))
	assert_true(text.contains("round penetrates plate"))


func test_file_sink_writes_and_appends_line() -> void:
	var path := "user://tmp_test_combat_log.log"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var sink := FileSink.new(path)
	sink.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"shot_fired", {}, "test line"))
	sink.close()

	assert_true(FileAccess.file_exists(path))
	var contents: String = FileAccess.get_file_as_string(path)
	assert_true(contents.contains("test line"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Phase 0 acceptance: "a FileSink log appears at out/combat.log" — a real,
## reviewable artifact of running the suite, left behind on purpose (unlike
## the hermetic test above).
func test_file_sink_default_path_produces_out_combat_log() -> void:
	var sink := FileSink.new()
	sink.emit(
		LogEvent.new(0, Enums.Phase.RESOLUTION, 0, &"suite_run", {}, "run_tests.sh wrote this")
	)
	sink.close()

	assert_true(FileAccess.file_exists("res://out/combat.log"))
