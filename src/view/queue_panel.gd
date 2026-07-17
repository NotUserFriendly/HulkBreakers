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
var tooltip_view: TooltipView
var _marker_index: int = -1
## docs/09 taskblock07 Pass B3: the OTHER half of "derived, not
## event-driven" — how many entries the queue actually has right now, kept
## alongside `_marker_index` so `_update_resolve_button()` never needs a
## click to have just happened to know whether the current marker is
## still valid.
var _entry_count: int = 0
## taskblock-07 Pass F1: this queue's own rows, kept for hover lookup —
## `item.get_metadata(COL_WHAT)` already stores each row's index into this
## same array (see refresh()), so a hovered TreeItem resolves straight
## back to its own entry.
var _current_entries: Array[Dictionary] = []


func setup(
	p_tactics: TacticsController,
	p_tree: Tree,
	p_resolve_button: Button,
	p_tooltip_view: TooltipView
) -> void:
	tactics = p_tactics
	tree = p_tree
	resolve_button = p_resolve_button
	tooltip_view = p_tooltip_view
	tree.columns = 3
	tree.column_titles_visible = true
	tree.hide_root = true
	# docs/09 taskblock07 Pass B3: SELECT_ROW, not the SELECT_SINGLE
	# default — a click anywhere on a queued entry's row selects it, not
	# only a click precisely on the Queued column's own cell.
	tree.select_mode = Tree.SELECT_ROW
	tree.set_column_title(COL_WHAT, "Queued")
	tree.set_column_title(COL_AP, "AP")
	tree.set_column_title(COL_MP, "MP")
	tree.set_column_expand(COL_WHAT, true)
	tree.set_column_expand(COL_AP, false)
	tree.set_column_custom_minimum_width(COL_AP, COL_AP_WIDTH)
	tree.set_column_expand(COL_MP, false)
	tree.set_column_custom_minimum_width(COL_MP, COL_MP_WIDTH)
	tree.item_selected.connect(_on_item_selected)
	tree.gui_input.connect(_on_tree_gui_input)
	tree.mouse_exited.connect(
		func() -> void:
			if tooltip_view != null:
				tooltip_view.hide_tooltip()
	)
	resolve_button.pressed.connect(_on_resolve_pressed)
	tactics.selection_changed.connect(refresh)
	refresh()


## taskblock-07 Pass F1: "queue entries" are named as a hoverable surface —
## same gui_input-based per-row hover InventoryPanel already uses (a Tree
## has no native per-item hover signal).
func _on_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion) or tooltip_view == null:
		return
	var motion := event as InputEventMouseMotion
	var item: TreeItem = tree.get_item_at_position(motion.position)
	var index: Variant = item.get_metadata(COL_WHAT) if item != null else null
	if not (index is int) or index < 0 or index >= _current_entries.size():
		tooltip_view.hide_tooltip()
		return
	var data: TooltipData = TooltipBuilder.for_queue_entry(_current_entries[index])
	tooltip_view.show_data(data, tree.get_viewport().get_mouse_position())


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


## docs/09 taskblock07 Pass B3: the marker survives a refresh that doesn't
## invalidate it — only cleared when it's now out of range (the unit was
## deselected, or the marked entry itself is gone). Previously this reset
## _marker_index to -1 UNCONDITIONALLY on every single queue change,
## which undid _on_item_selected()'s own enable the instant it happened —
## refresh() runs on every selection_changed, and clicking a row itself
## triggers one.
func refresh() -> void:
	tree.clear()
	var unit: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
	var entries: Array[Dictionary] = [] as Array[Dictionary]
	if unit != null:
		entries = tactics.selection.queue_entries()
	_entry_count = entries.size()
	_current_entries = entries
	if unit == null or _marker_index >= _entry_count:
		_marker_index = -1

	if unit != null:
		var root: TreeItem = tree.create_item()
		for i in range(entries.size()):
			var entry: Dictionary = entries[i]
			var item: TreeItem = tree.create_item(root)
			item.set_metadata(COL_WHAT, i)
			item.set_text(COL_WHAT, entry["describe"])
			item.set_text(COL_AP, str(entry["ap"]))
			item.set_text(COL_MP, "%.1f" % (entry["mp"] as float))
			if i == _marker_index:
				# Keeps the Tree's own visual selection in sync with the
				# marker that survived this refresh — without this, the
				# rebuild above (tree.clear() wipes every TreeItem,
				# selection included) would leave the marker enabled but
				# invisible.
				item.select(COL_WHAT)

	_update_resolve_button()


## docs/09 taskblock07 Pass B3: "the button's enabled state must be
## derived, not event-driven — it is enabled iff the selected unit has at
## least one queued action and a valid marker." A pure function of
## (_entry_count, _marker_index), recomputed here every time either could
## have changed — never left standing from whatever a past click set it
## to.
func _update_resolve_button() -> void:
	if resolve_button != null:
		resolve_button.disabled = (
			_entry_count == 0 or _marker_index < 0 or _marker_index >= _entry_count
		)
