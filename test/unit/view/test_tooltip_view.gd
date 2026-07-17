extends GutTest

## taskblock-07 Pass F1: THE one tooltip renderer — visible/hidden state
## and the `changed` -> BBCode highlight it's responsible for.


func _view() -> TooltipView:
	var view := TooltipView.new()
	add_child_autofree(view)
	return view


func test_show_data_makes_the_view_visible_with_its_content() -> void:
	var view: TooltipView = _view()
	var data := TooltipData.new("torso")
	data.add_row("condition", "8/10")

	view.show_data(data, Vector2(50, 50))

	assert_true(view.visible)
	assert_true(view._label.text.contains("torso"))
	assert_true(view._label.text.contains("8/10"))


func test_hide_tooltip_makes_the_view_invisible() -> void:
	var view: TooltipView = _view()
	view.show_data(TooltipData.new("torso"), Vector2(50, 50))
	assert_true(view.visible)

	view.hide_tooltip()

	assert_false(view.visible)


func test_an_empty_tooltip_data_hides_rather_than_shows_an_empty_box() -> void:
	var view: TooltipView = _view()
	view.show_data(TooltipData.new("torso"), Vector2(50, 50))

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

	var highlight_hex: String = HulkTheme.HIGHLIGHT.to_html(false)
	assert_true(view._label.text.contains("[color=#%s]3/6[/color]" % highlight_hex))
	assert_false(view._label.text.contains("[color=#%s]2.0[/color]" % highlight_hex))
