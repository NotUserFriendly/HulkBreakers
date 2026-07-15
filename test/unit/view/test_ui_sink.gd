extends GutTest

## docs/09: the rolling combat-log panel, as a pluggable CombatLog sink.


func _event(text: String) -> LogEvent:
	return LogEvent.new(0, Enums.Phase.RESOLUTION, 0, &"test_event", {}, text)


func test_emit_appends_rendered_lines() -> void:
	var sink := UISink.new()
	sink.emit(_event("first"))
	sink.emit(_event("second"))
	assert_eq(sink.lines.size(), 2)
	assert_true(sink.lines[0].find("first") != -1)
	assert_true(sink.lines[1].find("second") != -1)


func test_emit_caps_at_max_lines_dropping_the_oldest() -> void:
	var sink := UISink.new()
	for i in range(UISink.MAX_LINES + 10):
		sink.emit(_event("event_%d" % i))
	assert_eq(sink.lines.size(), UISink.MAX_LINES)
	assert_true(sink.lines[0].find("event_10") != -1, "the oldest 10 events must have rolled off")
	assert_true(sink.lines[-1].find("event_%d" % (UISink.MAX_LINES + 9)) != -1)


func test_emit_mirrors_into_an_attached_label() -> void:
	var label := RichTextLabel.new()
	var sink := UISink.new(label)
	sink.emit(_event("hello"))
	assert_true(label.text.find("hello") != -1)
	label.queue_free()


func test_combat_log_can_use_it_as_a_normal_sink() -> void:
	var sink := UISink.new()
	var log := CombatLog.new()
	log.add_sink(sink)
	log.emit(_event("wired through the real dispatcher"))
	assert_eq(sink.lines.size(), 1)
