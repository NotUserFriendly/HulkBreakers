extends GutTest

## docs/09 taskblock03 Pass B: "one stream, many sinks — never two
## streams." A UISink and a FileSink registered on the same CombatLog must
## receive event-for-event identical streams; nothing about wiring one
## changes what the other gets.

const TEST_PATH := "user://test_file_sink.log"


func _event(kind: StringName, text: String) -> LogEvent:
	return LogEvent.new(0, Enums.Phase.RESOLUTION, 1, kind, {}, text)


func _file_line_count(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	var lines: PackedStringArray = file.get_as_text().split("\n", false)
	file.close()
	return lines.size()


func after_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_uisink_and_filesink_receive_an_equal_line_count_event_for_event() -> void:
	var log := CombatLog.new()
	var ui_sink := UISink.new()
	var file_sink := FileSink.new(TEST_PATH)
	log.add_sink(ui_sink)
	log.add_sink(file_sink)

	log.emit(_event(&"move", "unit 1 moved"))
	log.emit(_event(&"impact", "PENETRATE on torso"))
	log.emit(_event(&"turn_end", "unit 1 ended turn"))
	file_sink.close()

	assert_eq(ui_sink.lines.size(), 3)
	assert_eq(_file_line_count(TEST_PATH), 3)
	assert_eq(
		ui_sink.lines.size(), _file_line_count(TEST_PATH), "event for event, not just a count"
	)


func test_removing_one_sink_does_not_change_what_the_other_receives() -> void:
	var log := CombatLog.new()
	var ui_sink := UISink.new()
	var file_sink := FileSink.new(TEST_PATH)
	log.add_sink(ui_sink)
	log.add_sink(file_sink)

	log.emit(_event(&"move", "first"))
	log.remove_sink(file_sink)
	log.emit(_event(&"move", "second"))
	file_sink.close()

	assert_eq(
		ui_sink.lines.size(), 2, "the UISink kept receiving events after FileSink was removed"
	)
	assert_eq(_file_line_count(TEST_PATH), 1, "the FileSink stopped exactly where it was removed")


func test_removing_the_other_sink_does_not_change_what_filesink_receives() -> void:
	var log := CombatLog.new()
	var ui_sink := UISink.new()
	var file_sink := FileSink.new(TEST_PATH)
	log.add_sink(ui_sink)
	log.add_sink(file_sink)

	log.emit(_event(&"move", "first"))
	log.remove_sink(ui_sink)
	log.emit(_event(&"move", "second"))
	file_sink.close()

	assert_eq(ui_sink.lines.size(), 1, "the UISink stopped exactly where it was removed")
	assert_eq(_file_line_count(TEST_PATH), 2, "the FileSink kept receiving events regardless")
