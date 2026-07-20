class_name HierarchicalUiSink
extends LogSink

## taskblock-22 Pass F: "the UI sink gets a tree" — a hierarchical VIEW of
## the same flat LogEvent stream FileSink/MemorySink still get untouched
## (F2: folding is presentation only). Wraps LogFold (the actual
## grouping/folding logic, fully headless-testable, see log_fold.gd) and
## renders it into `label` as clickable BBCode: each row defaults to
## `Unit 0 · Chaingun Burst · 8 hits, 4 miss` (F1's summary line), click
## to expand its own per-result detail (already fold-compressed — "3×
## Miss," never three separate lines), click again to collapse.
##
## `lines` mirrors UISink's own compatibility surface (one string per
## top-level group's current summary, in order) for anything that only
## wants the flat view — same shape test_battle_scene.gd's existing
## session-start assertions already read.

var fold: LogFold
var label: RichTextLabel = null
## One string per top-level group's current summary, in order — rebuilt
## alongside the BBCode render on every emit(), same "always a real
## stored array" shape as UISink.lines, not a computed property.
var lines: Array[String] = []
var _expanded: Dictionary = {}


func _init(p_label: RichTextLabel = null, p_state: CombatState = null) -> void:
	fold = LogFold.new(p_state)
	label = p_label
	if label != null:
		label.bbcode_enabled = true
		label.meta_clicked.connect(_on_meta_clicked)


func emit(event: LogEvent) -> void:
	fold.ingest(event)
	_render()


func _on_meta_clicked(meta: Variant) -> void:
	if meta is String and (meta as String).begins_with("group_"):
		var id: int = int((meta as String).trim_prefix("group_"))
		_expanded[id] = not _expanded.get(id, false)
		_render()


func _render() -> void:
	lines.clear()
	for group: LogFoldGroup in fold.groups:
		lines.append(group.summary)
	if label == null:
		return
	var out := PackedStringArray()
	for group: LogFoldGroup in fold.groups:
		var id: int = group.get_instance_id()
		var detail: Array[String] = group.detail_lines()
		if detail.is_empty():
			out.append(group.summary.xml_escape())
			continue
		var expanded: bool = _expanded.get(id, false)
		var marker: String = "▾ " if expanded else "▸ "
		out.append("[url=group_%d]%s%s[/url]" % [id, marker, group.summary.xml_escape()])
		if expanded:
			for j in range(detail.size()):
				var branch: String = "└ " if j == detail.size() - 1 else "├ "
				out.append("    %s%s" % [branch, detail[j].xml_escape()])
	label.text = "\n".join(out)
