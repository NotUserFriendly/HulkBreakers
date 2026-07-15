extends GutTest

## docs/08: the tooltip is a render of the resolved stat block. Changed
## values are highlighted, never hand-written.


func test_to_bbcode_wraps_bracketed_changed_values() -> void:
	var text := "5 Damage, [14] projectile burst, recoil [8]"
	var bbcode: String = StatBlockView.to_bbcode(text)
	var expected_color: String = HulkTheme.HIGHLIGHT.to_html(false)

	assert_eq(
		bbcode,
		(
			"5 Damage, [color=#%s]14[/color] projectile burst, recoil [color=#%s]8[/color]"
			% [expected_color, expected_color]
		)
	)


func test_to_bbcode_leaves_unbracketed_text_untouched() -> void:
	assert_eq(StatBlockView.to_bbcode("5 Damage, 10 burst"), "5 Damage, 10 burst")


## docs/08's own worked example: "5 Damage, [14] projectile burst" — the
## unmodified damage stays plain, the Spin-Up'd burst count highlights.
func test_render_marks_only_the_changed_entry_matching_docs_worked_example() -> void:
	var damage := StatValue.new(5.0, 5.0, [])
	var burst := StatValue.new(
		10.0, 14.0, [ModSource.new("Spin Up", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, 4.0)]
	)
	var entries: Array = [{"label": "", "value": damage}, {"label": "", "value": burst}]

	var label := RichTextLabel.new()
	StatBlockView.render(entries, label)

	var color: String = HulkTheme.HIGHLIGHT.to_html(false)
	assert_eq(label.text, "5, [color=#%s]14[/color]" % color)
	label.queue_free()


func test_render_drill_down_lists_each_source() -> void:
	var value := StatValue.new(
		10.0, 14.0, [ModSource.new("Spin Up", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, 4.0)]
	)
	var label := RichTextLabel.new()
	StatBlockView.render_drill_down(value, label)
	assert_eq(label.text, "- Spin Up (PERK): +4.0")
	label.queue_free()


func test_render_drill_down_shows_unmodified_for_an_unchanged_stat() -> void:
	var value := StatValue.new(5.0, 5.0, [])
	var label := RichTextLabel.new()
	StatBlockView.render_drill_down(value, label)
	assert_eq(label.text, "(unmodified)")
	label.queue_free()
