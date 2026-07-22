class_name QueuePanel
extends Node

## BR27.08: this used to be a `Tree` — click a row to set a stop marker,
## then press a separate global "Resolve to Here" button. A real click's
## `item_selected` signal never fired reliably in the live game despite
## checking out in every headless reproduction tried (including a real
## `InputEventMouseButton` pushed through a real `Viewport` against the
## real, correctly-sized production `Tree`) — the root cause was never
## conclusively identified. Rebuilt on primitives with no such history in
## this codebase: each queued action is its own row (`HBoxContainer` of
## `Label`s) carrying its own real `Button` that resolves the queue
## through exactly that point on press — no marker state, no `Tree`, no
## separate global button. Mirrors `GenerateBoutOverlay._rebuild_team()`/
## `_entry_row()`'s own established convention (clear every child, rebuild
## one row per array entry from scratch, each row's own controls bound to
## that row's index via `.bind()`) rather than inventing a new shape.
##
## `TacticsController.resolve_to_marker(index)` already takes a plain,
## direct index into the same queue order `SelectionController.
## queue_entries()` iterates to build these rows — no translation layer
## needed. Its own out-of-range guard means a button bound to a since-
## shrunk queue's index silently no-ops rather than misbehaving, and since
## `refresh()` destroys and rebuilds every row (button included) on every
## `selection_changed`, a stale bound index is structurally impossible.

const AP_WIDTH := 50
const MP_WIDTH := 60
const RESOLVE_BUTTON_TEXT := "Resolve"

var tactics: TacticsController
var rows_container: VBoxContainer
var tooltip_view: TooltipView


func setup(
	p_tactics: TacticsController, p_rows_container: VBoxContainer, p_tooltip_view: TooltipView
) -> void:
	tactics = p_tactics
	rows_container = p_rows_container
	tooltip_view = p_tooltip_view
	tactics.selection_changed.connect(refresh)
	refresh()


## Full clear-and-rebuild, no incremental patching — the same convention
## `GenerateBoutOverlay._rebuild_team()`/`BoardView.build()` already use,
## and what makes a stale bound row index structurally impossible here.
func refresh() -> void:
	for child: Node in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()

	var unit: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
	var entries: Array[Dictionary] = [] as Array[Dictionary]
	if unit != null:
		entries = tactics.selection.queue_entries()

	for i in range(entries.size()):
		rows_container.add_child(_entry_row(entries[i], i))


## One row per queued entry: What (expands) / AP / MP labels, plus its own
## "Resolve" button bound directly to this row's own queue index — a
## single click resolves the queue through exactly this point, no separate
## select-then-press step. Hover shows the same `TooltipBuilder.
## for_queue_entry()` data the old Tree's per-row hover did, now driven by
## plain `mouse_entered`/`mouse_exited` (the same convention `ApMpPipRow`'s
## containers already use) instead of manual `Tree` hit-testing.
func _entry_row(entry: Dictionary, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var what_label := Label.new()
	what_label.text = String(entry.get("describe", ""))
	what_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(what_label)

	var ap_label := Label.new()
	ap_label.text = str(entry.get("ap", 0))
	ap_label.custom_minimum_size = Vector2(AP_WIDTH, 0)
	row.add_child(ap_label)

	var mp_label := Label.new()
	mp_label.text = "%.1f" % (entry.get("mp", 0.0) as float)
	mp_label.custom_minimum_size = Vector2(MP_WIDTH, 0)
	row.add_child(mp_label)

	var resolve_button := Button.new()
	resolve_button.text = RESOLVE_BUTTON_TEXT
	resolve_button.pressed.connect(_on_resolve_pressed.bind(index))
	row.add_child(resolve_button)

	row.mouse_entered.connect(_on_row_entered.bind(entry))
	row.mouse_exited.connect(_on_row_exited)

	return row


func _on_resolve_pressed(index: int) -> void:
	if tactics != null:
		tactics.resolve_to_marker(index)


func _on_row_entered(entry: Dictionary) -> void:
	if tooltip_view == null:
		return
	tooltip_view.show_data(
		TooltipBuilder.for_queue_entry(entry), rows_container.get_viewport().get_mouse_position()
	)


func _on_row_exited() -> void:
	if tooltip_view != null:
		tooltip_view.hide_tooltip()
