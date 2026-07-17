class_name QueuePanel
extends Node

## docs/10 taskblock06 G2: "an in-turn, ordered list of the selected unit's
## queued actions: each entry: what, its cost, the running AP/MP total
## after it — click an entry -> set the stop marker there — Resolve to
## Here button -> resolve_until(marker)." Pure presentation: every row's
## text/ap/mp already comes from SelectionController.queue_entries() (the
## exact replay resolve_to_marker() itself uses to actually resolve) — this
## only turns them into Tree rows and forwards the click. The stop marker
## itself is UI-local (`_marker_index`), not state TacticsController has to
## carry (docs/10 taskblock06 G1's own resolve_to_marker() doc comment) —
## refresh() always clears it, so a marker can never point at a queue that
## has since changed out from under it.

const COL_WHAT := 0
const COL_AP := 1
const COL_MP := 2
const COL_AP_WIDTH := 50
const COL_MP_WIDTH := 60

var tactics: TacticsController
var tree: Tree
var resolve_button: Button
var _marker_index: int = -1


func setup(p_tactics: TacticsController, p_tree: Tree, p_resolve_button: Button) -> void:
	tactics = p_tactics
	tree = p_tree
	resolve_button = p_resolve_button
	tree.columns = 3
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.set_column_title(COL_WHAT, "Queued")
	tree.set_column_title(COL_AP, "AP")
	tree.set_column_title(COL_MP, "MP")
	tree.set_column_expand(COL_WHAT, true)
	tree.set_column_expand(COL_AP, false)
	tree.set_column_custom_minimum_width(COL_AP, COL_AP_WIDTH)
	tree.set_column_expand(COL_MP, false)
	tree.set_column_custom_minimum_width(COL_MP, COL_MP_WIDTH)
	tree.item_selected.connect(_on_item_selected)
	resolve_button.pressed.connect(_on_resolve_pressed)
	tactics.selection_changed.connect(refresh)
	refresh()


func _on_item_selected() -> void:
	var item: TreeItem = tree.get_selected()
	var index: Variant = item.get_metadata(COL_WHAT) if item != null else null
	_marker_index = index if index is int else -1
	_update_resolve_button()


## docs/10 taskblock06 G1: "resolve_until with a player-placed stop marker
## instead of an interrupt." resolve_to_marker() itself emits
## selection_changed (via _refresh_overlay()), which refresh() below is
## already listening to — no separate redraw call needed here.
func _on_resolve_pressed() -> void:
	if tactics == null or _marker_index < 0:
		return
	tactics.resolve_to_marker(_marker_index)


func refresh() -> void:
	tree.clear()
	_marker_index = -1
	_update_resolve_button()
	var unit: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
	if unit == null:
		return

	var entries: Array[Dictionary] = tactics.selection.queue_entries()
	var root: TreeItem = tree.create_item()
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var item: TreeItem = tree.create_item(root)
		item.set_metadata(COL_WHAT, i)
		item.set_text(COL_WHAT, entry["describe"])
		item.set_text(COL_AP, str(entry["ap"]))
		item.set_text(COL_MP, "%.1f" % (entry["mp"] as float))


func _update_resolve_button() -> void:
	if resolve_button != null:
		resolve_button.disabled = _marker_index < 0
