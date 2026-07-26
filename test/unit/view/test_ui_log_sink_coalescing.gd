extends GutTest

## taskblock-41 Pass A: render is decoupled from emit — `emit()` updates the
## model and marks dirty, the label draw happens at most once per frame.
## This file pins the property that makes Pass D's deliberate verbosity
## affordable: **render cost stops scaling with event count**. Both sinks get
## the same treatment, so both are covered here rather than only the one
## BR27.09 originally named.
##
## The equivalence assertions are the load-bearing ones. A render count alone
## would pass just as happily against a sink that coalesced by dropping
## events, so every count test is paired with "and the output is what N
## sequential renders would have produced."

## `HierarchicalUiSink` embeds `group.get_instance_id()` in its own
## `[url=group_%d]` metas, so two separate sink instances never produce
## byte-identical BBCode even when their content is identical. Object
## identity is not content — normalised out before comparing. Instance ids
## are routinely NEGATIVE, so the sign is part of the pattern; without it
## this normalises nothing and the comparison fails on identity alone.
const GROUP_ID_PATTERN := "group_-?[0-9]+"


func _event(kind: StringName, text: String = "") -> LogEvent:
	return LogEvent.new(0, Enums.Phase.RESOLUTION, 0, kind, {}, text if text != "" else str(kind))


func _normalised(text: String) -> String:
	var regex := RegEx.new()
	regex.compile(GROUP_ID_PATTERN)
	return regex.sub(text, "group_N", true)


# --- UISink -----------------------------------------------------------------


func test_ui_sink_renders_once_no_matter_how_many_events_landed_in_the_frame() -> void:
	var label := RichTextLabel.new()
	var sink := UISink.new(label)
	for i in range(29):  # BR27.09's own measured peak-turn event count
		sink.emit(_event(&"test_event", "event_%d" % i))

	assert_true(sink.is_dirty(), "29 events arrived and nothing has drawn them yet")
	assert_true(sink.render_if_dirty(), "the first tick of the frame renders")
	assert_false(sink.is_dirty(), "and clears the flag")
	assert_false(sink.render_if_dirty(), "a second tick with no new events renders nothing")
	label.queue_free()


func test_ui_sink_coalesced_output_is_identical_to_rendering_after_every_event() -> void:
	var per_event_label := RichTextLabel.new()
	var per_event := UISink.new(per_event_label)
	var coalesced_label := RichTextLabel.new()
	var coalesced := UISink.new(coalesced_label)

	for i in range(29):
		var event: LogEvent = _event(&"test_event", "event_%d" % i)
		per_event.emit(event)
		per_event.render_if_dirty()  # the pre-taskblock-41 behaviour, one render per event
		coalesced.emit(event)
	coalesced.render_if_dirty()  # ...against one render for the whole frame

	assert_eq(coalesced_label.text, per_event_label.text)
	assert_eq(coalesced.lines, per_event.lines)
	per_event_label.queue_free()
	coalesced_label.queue_free()


## `lines` is the whole headless surface — every existing assertion in
## test_ui_sink.gd/test_battle_scene.gd reads it with no scene tree at all.
## Coalescing defers the DRAW, never the model, so `lines` must be correct
## the instant emit() returns and must never need a render to catch up.
func test_ui_sink_lines_are_current_before_any_render_happens() -> void:
	var sink := UISink.new()
	sink.emit(_event(&"test_event", "first"))
	sink.emit(_event(&"test_event", "second"))

	assert_eq(sink.lines.size(), 2, "the model is updated on emit, not on render")
	assert_true(sink.lines[1].find("second") != -1)


func test_ui_sink_still_trims_to_max_lines_under_coalescing() -> void:
	var label := RichTextLabel.new()
	var sink := UISink.new(label)
	for i in range(UISink.MAX_LINES + 10):
		sink.emit(_event(&"test_event", "event_%d" % i))
	sink.render_if_dirty()

	assert_eq(sink.lines.size(), UISink.MAX_LINES, "trimming happens per emit, not per render")
	assert_true(label.text.find("event_9\n") == -1, "the oldest 10 rolled off before drawing")
	assert_true(label.text.find("event_10") != -1)
	assert_true(label.text.find("event_%d" % (UISink.MAX_LINES + 9)) != -1)
	label.queue_free()


# --- HierarchicalUiSink -----------------------------------------------------


func test_hierarchical_sink_renders_once_no_matter_how_many_events_landed() -> void:
	var label := RichTextLabel.new()
	var sink := HierarchicalUiSink.new(label)
	for _i in range(29):
		sink.emit(_event(&"miss"))

	assert_true(sink.is_dirty())
	assert_true(sink.render_if_dirty(), "one render for the whole batch")
	assert_false(sink.render_if_dirty(), "nothing new arrived, so nothing redraws")
	label.queue_free()


## The case BR27.09's own prescribed `append_text` fix could not have
## handled: these 29 events fold into ONE group whose summary is REWRITTEN
## each time, so there is no new line to append — and coalescing still has
## to land on exactly the text the per-event path produced.
func test_hierarchical_coalesced_output_is_identical_to_rendering_after_every_event() -> void:
	var per_event_label := RichTextLabel.new()
	var per_event := HierarchicalUiSink.new(per_event_label)
	var coalesced_label := RichTextLabel.new()
	var coalesced := HierarchicalUiSink.new(coalesced_label)

	var kinds: Array[StringName] = [&"turn_start", &"miss", &"miss", &"miss", &"turn_start"]
	for kind: StringName in kinds:
		per_event.emit(_event(kind))
		per_event.render_if_dirty()
		coalesced.emit(_event(kind))
	coalesced.render_if_dirty()

	assert_eq(_normalised(coalesced_label.text), _normalised(per_event_label.text))
	assert_eq(coalesced.lines, per_event.lines)
	per_event_label.queue_free()
	coalesced_label.queue_free()


func test_hierarchical_lines_are_current_before_any_render_happens() -> void:
	var sink := HierarchicalUiSink.new()
	sink.emit(_event(&"turn_start"))
	sink.emit(_event(&"miss"))
	sink.emit(_event(&"miss"))

	assert_eq(sink.lines.size(), 2, "turn_start is its own row; both misses fold into one attack")


## "Expand/collapse re-renders promptly — a dirty flag clearing on frame
## boundaries must not make clicks feel dropped." A click is direct
## manipulation; it renders on the spot, without waiting for a tick.
func test_expand_collapse_renders_immediately_without_waiting_for_a_frame_tick() -> void:
	var label := RichTextLabel.new()
	var sink := HierarchicalUiSink.new(label)
	sink.emit(_event(&"miss"))
	sink.render_if_dirty()
	assert_true(label.text.find("Miss") == -1, "collapsed by default")

	var meta: String = "group_%d" % sink.fold.groups[0].get_instance_id()
	sink._on_meta_clicked(meta)
	assert_true(label.text.find("Miss") != -1, "expanded on the click itself, no tick needed")
	assert_false(sink.is_dirty(), "and left nothing pending for the next frame")

	sink._on_meta_clicked(meta)
	assert_true(label.text.find("Miss") == -1, "collapsed again, still immediately")
	label.queue_free()


## A click landing in the same frame as new events must not lose either the
## events or the expansion — the immediate render draws the current model,
## which already includes whatever emit() ingested a moment earlier.
func test_a_click_in_the_same_frame_as_new_events_draws_both() -> void:
	var label := RichTextLabel.new()
	var sink := HierarchicalUiSink.new(label)
	sink.emit(_event(&"miss"))
	sink.render_if_dirty()
	var meta: String = "group_%d" % sink.fold.groups[0].get_instance_id()

	sink.emit(_event(&"turn_start"))
	sink._on_meta_clicked(meta)

	assert_true(label.text.find("Miss") != -1, "the expansion the click asked for")
	assert_true(label.text.find("turn_start") != -1, "and the event that arrived just before it")
	label.queue_free()
