class_name EditorBarModule
extends BarModule

## taskblock-57 Pass G1: **the editor's bar — labelled buttons, not squares.**
##
## The taskblock: *"Editor — labelled buttons, not squares. 'Place Items' opens a centred,
## searchable list of every part placeable on a tile; tiles and claims get their own buttons. Also
## holds save, load, run-a-bout, and undo."*
##
## ## Two rows, because the two things are different questions
##
## | row | what it answers |
## |---|---|
## | tools | what does a click on the board mean |
## | file | what do I do with the board I have |
##
## ## The tool buttons are generated, never listed
##
## `EditorTools.TOOLS` is the vocabulary and every entry gets a button, so a tenth verb added to
## that list grows a button the day it is added — the standing "content is data, not a code edit"
## rule applied to the authoring surface. **The labels come from the ids** (`Sight Blocking`,
## `Spawn A`) rather than from a table, for the same reason.
##
## **`place` is the exception, and it is three buttons rather than one.** Placing needs a *kind* as
## well as a part, so there is one button per `MapPlacement` kind — each opens the same searchable
## list and each sets its own kind. That is what the taskblock's *"tiles get their own button"*
## means concretely, and `PLACEMENT_LABELS` is what makes `field_item` read as *Place Items* rather
## than as its id.
##
## **The third one is `Cover`, and it is not in the taskblock's sentence.** It is here because the
## editor could author blockers before this pass and the stop-and-report rule is that a re-slotting
## must not silently lose a verb. Naming two of the three kinds and dropping the third would have
## deleted every wall and barrel an author can place.
##
## ## The list is one widget with two callers
##
## `Place Items` searches the parts pool; `Load` searches the map and section catalogs. Both are a
## centred, searchable list of ids, so both are `SearchableList` — a second one written later is
## the shape this project keeps deleting.
##
## ## It decides nothing
##
## Every button is one assignment onto `EditorModule`'s own state, or one call into a verb that
## module already had. The routing from a tool to `EditorController` is unchanged and still lives
## one layer down, in logic, where it is tested with no scene at all.
##
## Display: it authors a board and drives no unit's turn — the same classification `EditorModule`
## carries, and for the same reason.

## What a placement kind is called on a button. **An open table with a derived fallback**: a kind
## nobody named here reads as its own id, capitalised, rather than not appearing.
## taskblock-58 Pass D: **tool id -> what the button says.** The three placement-kind labels this
## replaced were `Tiles` / `Cover` / `Place Items`, which named what was being placed; these name
## the click, which is what the reorganisation is for. Absent ids fall back to the id capitalised,
## so an eighth tool still gets a readable button rather than none.
const TOOL_LABELS: Dictionary = {
	&"select": "Select",
	&"place_terrain": "Terrain",
	&"scale": "Scale",
	&"delete": "Delete",
	&"place_map_thing": "Map Thing",
	&"place_big_part": "Big Part",
	&"place_part": "Part",
}

const PLACEMENT_LABELS: Dictionary = {
	MapPlacement.KIND_SURFACE: "Tiles",
	MapPlacement.KIND_BLOCKER: "Cover",
	MapPlacement.KIND_FIELD_ITEM: "Place Items",
}

## The file verbs, in the order the taskblock lists them, as `label -> method on EditorModule`.
## Named here rather than generated because they are not a vocabulary — they are four fixed things
## an editor does, and `EditorModule` has exactly one method for each.
const FILE_BUTTONS: Array = [
	["Undo", &"undo"],
	["Save as Map", &"save_as_map"],
	["Save as Section", &"save_as_section"],
	["Run Test Bout", &"run_test_bout"],
]

## Tool id -> its button, so the highlight can find one and a test can press one.
var tool_buttons: Dictionary = {}
## Label -> button, for the file row.
var file_buttons: Dictionary = {}
var load_button: Button = null

## taskblock-58 Pass E: **`PartsListModule`'s widget, reached through it.** A property rather than a
## field, so the many existing readers — the bar's own handlers and every test that inspects what
## was offered — keep the name they had while the widget itself lives in the Inspect slot.
var list: SearchableList:
	get:
		var parts: PartsListModule = _parts_list()
		return parts.list if parts != null else null

## Which place tool the next pick from `list` arms, or `&""` when the list is picking a board to
## load. **Set by the button that opened the list**, which is the whole of how one widget serves two
## callers without either of them growing a mode flag.
var _pending_tool: StringName = &""


func module_id() -> StringName:
	return &"editor_bar"


## taskblock-57 Pass G2: **the bar carries the current tool's highlight.**
##
## *"Current tool shows on the cursor — a small icon of what is being placed — **or** is carried by
## the action bar's own highlight. Either is fine; neither is not."*
##
## The bar's highlight is the option taken, for a stated reason rather than a preference: a cursor
## icon is a `Control` following the mouse over a 3D board, which is a new surface with its own
## z-order and hit-testing questions, where the buttons that set the tool are already on screen and
## already know which of them was pressed. **The player's bar already highlights its armed action
## the same way** (`ActionBar.refresh` modulates the armed box), so this is one idiom, not two.
##
## Driven off `tool_changed` rather than polled, so a tool set by a pick from the parts list — or by
## anything else — highlights identically to one set by pressing the button.
## taskblock-58 Pass E: **the pick is connected here rather than where the list is built**, because
## the list is no longer built here — `PartsListModule` owns the widget and this bar is one of its
## two callers. `link()` is the right seam for it: it runs once every module in the mode exists,
## which is exactly the condition for reaching another module's widget at all.
func link() -> void:
	var editor: EditorModule = _editor()
	if editor != null:
		editor.tool_changed.connect(_on_tool_changed)
		_on_tool_changed(editor.active_tool)
	var parts: PartsListModule = _parts_list()
	if parts != null and parts.list != null and not parts.list.chosen.is_connected(_on_list_chosen):
		parts.list.chosen.connect(_on_list_chosen)


## Highlights whichever button arms `tool`, and dims the rest.
##
## taskblock-58 Pass D: **one lit button, because there is one armed tool.** This used to also light
## a placement-kind button whenever `place` was armed, since `place` had no button of its own.
func _on_tool_changed(tool: StringName) -> void:
	for id: StringName in tool_buttons:
		_light(tool_buttons[id] as Button, id == tool)


func _light(button: Button, lit: bool) -> void:
	button.modulate = HulkTheme.HIGHLIGHT if lit else HulkTheme.FOREGROUND


func _fill_bar(column: VBoxContainer) -> void:
	var tools := HBoxContainer.new()
	tools.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(tools)

	# taskblock-58 Pass D: **one button per tool, and no special case.** The three placement-kind
	# buttons that used to sit here were `place`'s stand-ins — a single unqualified "Place" would
	# have authored with whichever kind was last used. The three placing verbs are real tools now,
	# so the row is generated straight off the vocabulary with nothing skipped.
	for tool: StringName in EditorTools.TOOLS:
		tool_buttons[tool] = _button(tools, _label_for(tool), _on_tool_pressed.bind(tool))

	var files := HBoxContainer.new()
	files.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(files)

	for entry: Array in FILE_BUTTONS:
		var label: String = entry[0]
		var verb: StringName = entry[1]
		file_buttons[label] = _button(files, label, _on_file_pressed.bind(verb))
	load_button = _button(files, "Load", _on_load_pressed)


## taskblock-58 Pass E: **the list is `PartsListModule`'s now, and this bar borrows it.**
##
## It used to be built here and parented to `ui_root`, centred, because the bar is 96 px tall and
## the panel is 520 — a child of the bar would have drawn off the bottom of the display. The
## taskblock puts it in the Inspect slot instead, so the widget moved to a module that can claim
## one. **One widget, two callers still**: the place verbs and Load open the same list.
##
## Null when the mode declares no `parts_list`, which is every mode but the editor. A bar with no
## list simply cannot open one, the same degradation `link()` already takes for the picker.
func _parts_list() -> PartsListModule:
	return context.module(&"parts_list") as PartsListModule if context != null else null


## Arming a tool, and — for the three that put a part down — opening the list of what it can put.
##
## taskblock-58 Pass D: **the tool is armed either way**, which is the difference from the old kind
## buttons. Those opened a list and armed nothing until a pick was made; a Place tool is a tool, so
## pressing it selects it, and the list is how you say *which* part rather than *whether* to place.
func _on_tool_pressed(tool: StringName) -> void:
	var editor: EditorModule = _editor()
	if editor == null:
		return
	editor.active_tool = tool
	if not EditorTools.is_place_tool(tool):
		return
	var parts: PartsListModule = _parts_list()
	if parts == null:
		return
	_pending_tool = tool
	parts.open(
		"%s — pick a part" % _label_for(tool),
		EditorTools.part_ids_for(tool, editor.placeable_part_ids())
	)


## A board to load, by catalog name. Maps and sections share a namespace from the author's point of
## view — they picked a board, not a schema — which is exactly what `EditorModule.open` already
## assumes on the way in.
func _on_load_pressed() -> void:
	var parts: PartsListModule = _parts_list()
	if parts == null:
		return
	_pending_tool = &""
	var boards: Array[StringName] = MapCatalog.names()
	boards.append_array(SectionCatalog.names())
	parts.open("Load a board", boards)


func _on_list_chosen(id: StringName) -> void:
	var editor: EditorModule = _editor()
	if editor == null:
		return
	if _pending_tool == &"":
		editor.open(String(id))
		return
	editor.selected_part = id
	editor.selected_kind = EditorTools.kind_for(_pending_tool, id)
	if editor.selected_kind == MapPlacement.KIND_SURFACE:
		editor.last_surface_part = id
	editor.active_tool = _pending_tool


## The file verbs, called by name. **Every one of them already existed on `EditorModule`** — this
## row is where they are reachable from, not where they are implemented.
func _on_file_pressed(verb: StringName) -> void:
	var editor: EditorModule = _editor()
	if editor != null:
		editor.call(verb)


func _label_for(tool: StringName) -> String:
	return TOOL_LABELS.get(tool, String(tool).capitalize())


func _button(parent: Control, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _editor() -> EditorModule:
	return context.module(&"editor") as EditorModule if context != null else null
