class_name EditorCoordsModule
extends ViewModule

## taskblock-57 Pass G2: **the coordinate readout, in the slot the unit resources use.**
##
## The taskblock: *"A coordinate readout replaces Unit Resources in editor mode — **same slot,
## different module**. Cell, height, and a truncated name of what is there. Detail is the
## inspector's job."*
##
## ## This is the module Pass C's split was for
##
## `ActionBarModule`'s own header recorded the reason the AP/MP pips became their own module rather
## than staying welded inside the bar: *"G2 replaces this exact surface with a coordinate readout in
## editor mode — same slot, different module — and two modules cannot share a slot if one of them is
## welded inside a third."* This is that module, and it cost a `preferred_slot()` and nothing else.
## Neither mode knows the other exists; each declares the one it wants.
##
## ## Truncated, deliberately
##
## *"Detail is the inspector's job."* A cell can hold a stack of placements and the readout is one
## line above a bar — so it names the topmost one, cut to a fixed width. An author who wants the
## whole story clicks and reads Inspect, which is a panel with room for it.
##
## Display: it reads the cursor and draws it. It queues nothing and authors nothing.

## How wide a part id may read before it is cut. A starting position the supervisor's tuning pass
## owns, not a decision.
const NAME_WIDTH := 18

## Shown when the cursor is off the board. **Present and empty rather than absent** — the same rule
## the AP/MP rows follow in the module this replaces, and for the same reason: a surface that
## vanishes reads as broken.
const OFF_BOARD := "cell --"

## The column the readout lives in, so a later editor resource is a row rather than a re-layout —
## the same shape `UnitResourcesModule` keeps for the same reason.
var column: VBoxContainer = null
var cell_label: Label = null
var content_label: Label = null

## The cell last reported under the cursor, or null. Public so a test reads what the module thinks
## rather than parsing its own label back.
var cell: Variant = null


func module_id() -> StringName:
	return &"editor_coords"


## Above the bar, from its left edge — **the same slot `unit_resources` declares**, which is the
## whole of what "same slot, different module" means. The editor mode declares this one and not
## that one; nothing chooses between them at runtime.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_BAR_TOP_LEFT


func _mount() -> void:
	var slot: Control = context.slot(preferred_slot(), null)
	column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if slot != null:
		slot.add_child(column)
	else:
		add_child(column)

	cell_label = _line(HulkTheme.HIGHLIGHT)
	content_label = _line(HulkTheme.DIM)
	refresh()


## Follows whichever module reports the cursor. **`board_inspect` already owns the motion handler,
## the camera and the ray**, so this reads its answer rather than casting a second ray per frame.
## A context without one leaves the readout at its off-board state, which is the stand-alone case.
func link() -> void:
	var picking: ViewModule = context.module(&"board_inspect")
	if picking != null:
		(picking as BoardInspectModule).hovered_cell.connect(show_cell)
	refresh()


## The cursor moved to `p_cell`, or off the board when it is null.
func show_cell(p_cell: Variant) -> void:
	cell = p_cell
	refresh()


func refresh() -> void:
	if cell_label == null:
		return
	if cell == null:
		cell_label.text = OFF_BOARD
		content_label.text = ""
		return
	var at: Vector2i = cell as Vector2i
	cell_label.text = "cell (%d,%d)  h %.1f" % [at.x, at.y, height_at(at)]
	content_label.text = truncated(name_at(at))


## The elevation of `cell` on the live board. **Read off the grid the editor is drawing**, not
## recomputed from the model: `EditorModule.refresh()` swaps the authored board in on every edit, so
## the grid IS the model rendered, and asking it is asking what the author can see.
func height_at(at: Vector2i) -> float:
	var grid: Grid = _grid()
	if grid == null:
		return 0.0
	return UnitGeometry.true_height_for_cell(at, grid)


## The topmost placement's part id at `cell`, or `""` for an empty one. **From the editor's own
## model**, because that is what the author is editing — a cell they have just placed on and not yet
## redrawn should read as placed.
func name_at(at: Vector2i) -> StringName:
	var editor: EditorModule = (
		context.module(&"editor") as EditorModule if context != null else null
	)
	if editor == null:
		return &""
	var here: Array[MapPlacement] = editor.controller.placements_at(at)
	if here.is_empty():
		return &""
	return here[here.size() - 1].part_id


## `id` cut to `NAME_WIDTH`, with an ellipsis when it was cut. An empty id reads as "empty" rather
## than as a blank line — a cell with nothing on it is an answer, not a missing one.
static func truncated(id: StringName) -> String:
	var text: String = String(id)
	if text == "":
		return "empty"
	if text.length() <= NAME_WIDTH:
		return text
	return "%s…" % text.substr(0, NAME_WIDTH)


## Hidden as a whole, so a collapse takes the column and not one row of it. Meaningless today — this
## slot rides the bar rather than pinning to an edge — but a mode that re-slots it somewhere pinned
## gets working behaviour rather than a flag that does nothing.
func _on_collapsed(value: bool) -> void:
	if column != null:
		column.visible = not value


func _grid() -> Grid:
	if context == null or context.battle == null or context.battle.combat_state == null:
		return null
	return context.battle.combat_state.grid


func _line(color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	column.add_child(label)
	return label
