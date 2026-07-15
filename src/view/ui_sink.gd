class_name UISink
extends LogSink

## docs/09: the rolling combat-log panel, as a pluggable CombatLog sink
## (docs/09's own table names this as Phase 10's job). Keeps the last
## MAX_LINES events as rendered text in `lines` — testable headlessly with
## no scene tree — and mirrors them into `label` if one is attached.

const MAX_LINES := 200

var lines: Array[String] = []
var label: RichTextLabel = null


func _init(p_label: RichTextLabel = null) -> void:
	label = p_label


func emit(event: LogEvent) -> void:
	lines.append(event._to_string())
	if lines.size() > MAX_LINES:
		lines.pop_front()
	if label != null:
		label.bbcode_enabled = false
		label.text = "\n".join(lines)
