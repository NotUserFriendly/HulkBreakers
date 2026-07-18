extends GutTest

## taskblock-07 Pass F1: THE one tooltip renderer — visible/hidden state
## and the `changed` -> BBCode highlight it's responsible for.
##
## taskblock-08 Pass D2: nothing shows instantly anymore — every `show_data()`
## that would reveal new content starts a delay clock instead
## (`HOVER_DELAY_SEC`), advanced here the same way CameraRig's own tween
## tests advance a tween (`custom_step`): a direct, explicit call to
## `_process(delta)`, never a real wall-clock wait.


func _view() -> TooltipView:
	var view := TooltipView.new()
	add_child_autofree(view)
	return view


## Advances the view's own hover-delay clock past HOVER_DELAY_SEC so a
## pending show_data() call actually reveals.
func _reveal(view: TooltipView) -> void:
	view._process(TooltipView.HOVER_DELAY_SEC + 0.001)


func test_show_data_does_not_appear_before_the_delay_elapses() -> void:
	var view: TooltipView = _view()

	view.show_data(TooltipData.new("torso"), Vector2(50, 50))

	assert_false(view.visible, "taskblock-08 D2: nothing shows instantly")


func test_show_data_appears_once_the_delay_elapses() -> void:
	var view: TooltipView = _view()
	var data := TooltipData.new("torso")
	data.add_row("condition", "8/10")

	view.show_data(data, Vector2(50, 50))
	_reveal(view)

	assert_true(view.visible)
	assert_true(view._label.text.contains("torso"))
	assert_true(view._label.text.contains("8/10"))


func test_moving_off_before_the_delay_elapses_means_it_never_appears() -> void:
	var view: TooltipView = _view()
	view.show_data(TooltipData.new("torso"), Vector2(50, 50))
	view._process(TooltipView.HOVER_DELAY_SEC * 0.5)  # dwelling, but not there yet

	view.hide_tooltip()  # moved off before the delay elapsed
	_reveal(view)  # even if time keeps passing, there's nothing left pending

	assert_false(view.visible)


func test_hide_tooltip_makes_the_view_invisible() -> void:
	var view: TooltipView = _view()
	view.show_data(TooltipData.new("torso"), Vector2(50, 50))
	_reveal(view)
	assert_true(view.visible)

	view.hide_tooltip()

	assert_false(view.visible)


func test_an_empty_tooltip_data_hides_rather_than_shows_an_empty_box() -> void:
	var view: TooltipView = _view()
	view.show_data(TooltipData.new("torso"), Vector2(50, 50))
	_reveal(view)

	view.show_data(TooltipData.new(), Vector2(60, 60))

	assert_false(view.visible)


## docs/08: "changed values still highlight" — HulkTheme.HIGHLIGHT's own
## hex, and only on the row flagged changed, never the whole line.
func test_a_changed_row_gets_the_highlight_color_and_an_unchanged_one_does_not() -> void:
	var view: TooltipView = _view()
	var data := TooltipData.new("arm")
	data.add_row("condition", "3/6", true)
	data.add_row("mass", "2.0", false)

	view.show_data(data, Vector2(0, 0))
	_reveal(view)

	var highlight_hex: String = HulkTheme.HIGHLIGHT.to_html(false)
	assert_true(view._label.text.contains("[color=#%s]3/6[/color]" % highlight_hex))
	assert_false(view._label.text.contains("[color=#%s]2.0[/color]" % highlight_hex))


## taskblock-08 D1/TESTS: "the tooltip position tracks the cursor while
## shown" — a repeated show_data() call with the SAME content (the
## inventory tooltip's own per-motion-event pattern) repositions the
## already-revealed tooltip, it does not restart the delay or the content.
func test_the_tooltip_position_tracks_the_cursor_while_shown() -> void:
	var view: TooltipView = _view()
	# The default headless test viewport is tiny (64x64) — far smaller
	# than MIN_WIDTH (220) alone, so _reposition()'s own edge-clamping
	# would collapse any two cursor positions to the same clamped corner
	# regardless of input, masking the very thing this test checks. A
	# realistically-sized viewport is what a live game actually has.
	view.get_viewport().size = Vector2i(1920, 1080)
	var data := TooltipData.new("torso")
	data.add_row("condition", "8/10")
	view.show_data(data, Vector2(50, 50))
	_reveal(view)
	var first_position: Vector2 = view.global_position

	view.show_data(data, Vector2(300, 300))

	assert_true(view.visible, "must still be showing — a repeat call, not a new hover")
	assert_ne(view.global_position, first_position, "must have followed the cursor")


## taskblock-08 D1/D2: a repeated show_data() call for the SAME pending
## (not-yet-revealed) hover must not restart the delay clock — otherwise
## continuous cursor motion within one target could delay it forever.
func test_repeated_calls_for_the_same_pending_hover_do_not_restart_the_delay() -> void:
	var view: TooltipView = _view()
	var data := TooltipData.new("torso")

	view.show_data(data, Vector2(50, 50))
	view._process(TooltipView.HOVER_DELAY_SEC * 0.9)
	view.show_data(data, Vector2(52, 51))  # cursor drifted slightly, same target
	view._process(TooltipView.HOVER_DELAY_SEC * 0.2)  # combined elapsed now exceeds the delay

	assert_true(view.visible, "the delay must have kept counting, not restarted at the second call")


## A genuinely different hover target DOES restart the delay clock —
## otherwise flicking the cursor across several targets inside one delay
## window would incorrectly reveal the last one immediately.
func test_a_new_hover_target_restarts_the_delay() -> void:
	var view: TooltipView = _view()
	var first := TooltipData.new("torso")
	var second := TooltipData.new("arm")

	view.show_data(first, Vector2(50, 50))
	view._process(TooltipView.HOVER_DELAY_SEC * 0.9)
	view.show_data(second, Vector2(52, 51))  # a different target — resets the clock
	view._process(TooltipView.HOVER_DELAY_SEC * 0.2)  # not enough time for THIS target yet

	assert_false(view.visible)
