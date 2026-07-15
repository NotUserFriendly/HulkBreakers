class_name DescriptionBuilder
extends RefCounted

## Renders resolved stats to text — never hand-written (docs/08). A weapon
## has no description string; the tooltip is a render of the resolved stat
## block, so it can never drift from the number the damage calculation uses.


## `entries` is an ordered Array of {label: String, value: StatValue} —
## ordered because display order matters and Dictionary iteration order
## isn't a contract worth leaning on for player-facing text. Changed values
## (StatValue.changed()) are bracketed.
static func render(entries: Array) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in entries:
		var label: String = entry.get("label", "")
		var value: StatValue = entry.value
		var number_text: String = _format_number(value.current)
		if value.changed():
			number_text = "[%s]" % number_text
		parts.append("%s: %s" % [label, number_text] if label != "" else number_text)
	return ", ".join(parts)


## Which entries changed and by what — the drill-down behind a highlighted
## number (docs/08: "highlighting a number reveals its sources").
static func drill_down(entry_value: StatValue) -> Array[String]:
	var lines: Array[String] = []
	for source: ModSource in entry_value.sources:
		var op_text: String
		match source.op:
			Enums.ModOp.ADD:
				var sign: String = "+" if source.delta >= 0.0 else ""
				op_text = "%s%s" % [sign, source.delta]
			Enums.ModOp.MULTIPLY:
				op_text = "x%s" % source.delta
			Enums.ModOp.OVERRIDE:
				op_text = "-> %s" % source.delta
		lines.append(
			(
				"%s (%s): %s"
				% [source.source_name, Enums.ModSourceKind.keys()[source.source_kind], op_text]
			)
		)
	return lines


static func _format_number(n: float) -> String:
	if is_equal_approx(n, roundf(n)):
		return str(int(round(n)))
	return str(n)
