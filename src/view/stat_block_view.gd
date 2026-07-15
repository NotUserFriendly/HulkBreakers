class_name StatBlockView
extends RefCounted

## docs/08: "the description and the damage come from the same code."
## DescriptionBuilder already renders the resolved stat block as plain
## text with changed values bracketed (`[14]`); this is the thin layer on
## top that turns those brackets into BBCode highlighting for a
## RichTextLabel — no separate description is ever hand-written here.


## Renders `entries` (DescriptionBuilder's format) into `label` as BBCode,
## with every changed value colored HulkTheme.HIGHLIGHT.
static func render(entries: Array, label: RichTextLabel) -> void:
	label.bbcode_enabled = true
	label.text = to_bbcode(DescriptionBuilder.render(entries))


## Renders a drill-down (docs/08: "highlighting a number reveals its
## sources") as a plain bullet list into `label`.
static func render_drill_down(entry_value: StatValue, label: RichTextLabel) -> void:
	label.bbcode_enabled = true
	var lines: Array[String] = DescriptionBuilder.drill_down(entry_value)
	if lines.is_empty():
		label.text = "(unmodified)"
		return
	var bulleted: Array[String] = []
	for line: String in lines:
		bulleted.append("- %s" % line)
	label.text = "\n".join(bulleted)


## Converts DescriptionBuilder's `[N]` bracket markers into BBCode color
## tags using the theme's highlight color. A standalone, pure function —
## testable without constructing any Node.
static func to_bbcode(text: String) -> String:
	var color_hex: String = HulkTheme.HIGHLIGHT.to_html(false)
	var result := ""
	var i := 0
	while i < text.length():
		if text[i] == "[":
			var close: int = text.find("]", i)
			if close != -1:
				var inner: String = text.substr(i + 1, close - i - 1)
				result += "[color=#%s]%s[/color]" % [color_hex, inner]
				i = close + 1
				continue
		result += text[i]
		i += 1
	return result
