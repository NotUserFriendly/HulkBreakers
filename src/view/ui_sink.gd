class_name UISink
extends UiLogSink

## docs/09: the rolling combat-log panel, as a pluggable CombatLog sink
## (docs/09's own table names this as Phase 10's job). Keeps the last
## MAX_LINES events as rendered text in `lines` — testable headlessly with
## no scene tree — and mirrors them into `label` if one is attached.
##
## taskblock-41 Pass A: the mirror into `label` is coalesced to at most once
## per frame (`UiLogSink`); `lines` is still trimmed and appended on every
## `emit()`, so every existing headless assertion reads exactly what it
## always did. BR27.09's own prescribed fix for this sink — incremental
## `RichTextLabel.append_text` — genuinely does fit here (unlike
## `HierarchicalUiSink`) and is still worth taking on top, but only if it
## measures against the coalesced baseline rather than the old per-event one.

const MAX_LINES := 200

var lines: Array[String] = []


func _init(p_label: RichTextLabel = null) -> void:
	label = p_label


func emit(event: LogEvent) -> void:
	lines.append(event._to_string())
	if lines.size() > MAX_LINES:
		lines.pop_front()
	mark_dirty()


func _render_label() -> void:
	if label == null:
		return
	label.bbcode_enabled = false
	label.text = "\n".join(lines)
