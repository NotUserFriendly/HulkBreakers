extends GutTest

## taskblock-22 Pass F: the "UI sink gets a tree" — rendering/wiring only.
## LogFold's own classification/folding rules are covered headlessly in
## test/unit/logic/test_log_fold.gd; this file is about the RichTextLabel
## BBCode render, click-to-expand, and the `lines` compatibility surface.


func _event(kind: StringName, unit_id: int = 0, data: Dictionary = {}) -> LogEvent:
	return LogEvent.new(0, Enums.Phase.RESOLUTION, unit_id, kind, data, str(kind))


func test_lines_mirrors_one_summary_string_per_top_level_group() -> void:
	var sink := HierarchicalUiSink.new()
	sink.emit(_event(&"turn_start"))
	sink.emit(_event(&"miss"))
	sink.emit(_event(&"miss"))

	assert_eq(sink.lines.size(), 2, "turn_start is its own row; both misses fold into one attack")


func test_emit_mirrors_into_an_attached_label() -> void:
	var label := RichTextLabel.new()
	var sink := HierarchicalUiSink.new(label)
	sink.emit(_event(&"turn_start", 0, {}))

	assert_true(label.bbcode_enabled)
	assert_true(label.text.find("turn_start") != -1)
	label.queue_free()


## A group with no drillable detail (nothing beyond its own single event)
## renders as plain text — no [url] wrapper for something that can't
## expand into anything new.
func test_a_single_event_admin_row_is_not_clickable() -> void:
	var label := RichTextLabel.new()
	var sink := HierarchicalUiSink.new(label)
	sink.emit(_event(&"turn_start"))

	assert_true(label.text.find("[url=") == -1, "nothing to expand, so nothing should be a link")
	label.queue_free()


## An attack group (always has at least one detail line to drill into)
## renders collapsed by default and expands on the simulated meta_clicked
## a real click on its own [url=...] region would fire.
func test_clicking_an_attack_summary_expands_its_detail_then_collapses_again() -> void:
	var label := RichTextLabel.new()
	var sink := HierarchicalUiSink.new(label)
	sink.emit(_event(&"miss"))
	assert_true(label.text.find("Miss") == -1, "collapsed by default — detail not shown yet")

	var group: LogFoldGroup = sink.fold.groups[0]
	var meta: String = "group_%d" % group.get_instance_id()
	sink._on_meta_clicked(meta)
	assert_true(label.text.find("Miss") != -1, "expanded — the Miss detail line is now visible")

	sink._on_meta_clicked(meta)
	assert_true(label.text.find("Miss") == -1, "clicked again — collapsed back")
	label.queue_free()


## F2: "the file sink still gets every event" — same cross-sink parity
## guarantee test_file_sink.gd already proves for the flat UISink, now for
## the folding sink: a FileSink registered alongside a HierarchicalUiSink
## on the same CombatLog gets one line per raw event, never fewer.
func test_filesink_receives_every_event_regardless_of_folding() -> void:
	const TEST_PATH := "user://test_hierarchical_ui_sink.log"
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

	var log := CombatLog.new()
	var fold_sink := HierarchicalUiSink.new()
	var file_sink := FileSink.new(TEST_PATH)
	log.add_sink(fold_sink)
	log.add_sink(file_sink)

	log.emit(_event(&"miss"))
	log.emit(_event(&"miss"))
	log.emit(_event(&"miss"))
	log.emit(_event(&"turn_start"))
	file_sink.close()

	var file := FileAccess.open(TEST_PATH, FileAccess.READ)
	var file_line_count: int = file.get_as_text().split("\n", false).size()
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

	assert_eq(file_line_count, 4, "one file line per raw event, unaffected by folding")
	assert_eq(sink_event_total(fold_sink), 4, "the fold itself also accounts for every event")


func sink_event_total(sink: HierarchicalUiSink) -> int:
	var total := 0
	for group: LogFoldGroup in sink.fold.groups:
		total += group.events.size()
	return total
