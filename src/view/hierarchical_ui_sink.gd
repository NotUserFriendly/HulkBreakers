class_name HierarchicalUiSink
extends UiLogSink

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
##
## taskblock-41 Pass A: the BBCode render into `label` is coalesced to at
## most once per frame (`UiLogSink`), which is why the old single `_render()`
## is now split in two. `_rebuild_lines()` is the cheap model update and
## still runs on EVERY `emit()` — `lines` must never lag the event stream,
## since it is the whole headless surface. `_render_label()` is the
## expensive BBCode build and waits for the frame tick. This sink is exactly
## why BR27.09's own prescribed `append_text` fix could not be taken: a new
## event routinely rewrites an existing group's summary rather than
## appending a row, so there is no correct incremental append here.

var fold: LogFold
## One string per top-level group's current summary, in order — rebuilt on
## every emit(), same "always a real stored array" shape as UISink.lines,
## not a computed property.
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
	_rebuild_lines()
	mark_dirty()


## Expand/collapse renders immediately rather than waiting for the frame
## tick — a click is direct manipulation, and a one-frame dirty flag would
## make it read as dropped. The fold model itself is untouched here; only
## which rows are drawn expanded changes, so there is nothing to rebuild.
func _on_meta_clicked(meta: Variant) -> void:
	if meta is String and (meta as String).begins_with("group_"):
		var id: int = int((meta as String).trim_prefix("group_"))
		_expanded[id] = not _expanded.get(id, false)
		render_now()


func _rebuild_lines() -> void:
	lines.clear()
	for group: LogFoldGroup in fold.groups:
		lines.append(group.summary)


func _render_label() -> void:
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
