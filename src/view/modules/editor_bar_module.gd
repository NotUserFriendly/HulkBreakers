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
## `EditorModule.TOOLS` is the vocabulary and every entry gets a button, so a tenth verb added to
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
## Placement kind -> its button. `place` has one per kind; see the class note.
var kind_buttons: Dictionary = {}
## Label -> button, for the file row.
var file_buttons: Dictionary = {}
var load_button: Button = null

## The one centred, searchable list, shared by `Place Items` and `Load`. Public so a test reads
## back what it offers instead of re-deriving it.
var list: SearchableList = null

## Which kind the next pick from `list` becomes, or `&""` when the list is picking a board to load.
## **Set by the button that opened the list**, which is the whole of how one widget serves two
## callers without either of them growing a mode flag.
var _pending_kind: StringName = &""


func module_id() -> StringName:
	return &"editor_bar"


func _fill_bar(column: VBoxContainer) -> void:
	var tools := HBoxContainer.new()
	tools.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(tools)

	for kind: StringName in EditorModule.PLACEMENT_KINDS:
		kind_buttons[kind] = _button(
			tools, _label_for_kind(kind), _on_place_kind_pressed.bind(kind)
		)

	for tool: StringName in EditorModule.TOOLS:
		# `place` is the three kind buttons above; a single unqualified "Place" would author with
		# whichever kind was last used, which is the kind of hidden state an editor cannot afford.
		if tool == &"place":
			continue
		tool_buttons[tool] = _button(tools, String(tool).capitalize(), _on_tool_pressed.bind(tool))

	var files := HBoxContainer.new()
	files.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(files)

	for entry: Array in FILE_BUTTONS:
		var label: String = entry[0]
		var verb: StringName = entry[1]
		file_buttons[label] = _button(files, label, _on_file_pressed.bind(verb))
	load_button = _button(files, "Load", _on_load_pressed)

	_build_list()


## The searchable list, centred on the surface rather than inside the bar. **Parented to `ui_root`,
## not to the bar** — the bar is 96 px tall at the bottom of the screen and this is a 520 px panel;
## a child of the bar would be drawn off the bottom of the display.
func _build_list() -> void:
	list = SearchableList.new()
	list.chosen.connect(_on_list_chosen)
	var root: Control = context.ui_root if context != null else null
	if root == null:
		# The stand-alone case taskblock-56 Pass C's acceptance requires: the list is real and can
		# still be opened and read back; it simply has nowhere of its own to be drawn.
		add_child(list)
		return
	root.add_child(list)
	list.set_anchors_preset(Control.PRESET_CENTER)
	list.grow_horizontal = Control.GROW_DIRECTION_BOTH
	list.grow_vertical = Control.GROW_DIRECTION_BOTH
	list.position = root.size * 0.5 - SearchableList.PANEL_SIZE * 0.5


## Opens the parts list for `kind`. The pick is what actually arms the tool — opening the list
## changes nothing, so an author who opens it and closes it again has not silently switched tools.
func _on_place_kind_pressed(kind: StringName) -> void:
	var editor: EditorModule = _editor()
	if editor == null:
		return
	_pending_kind = kind
	list.open("%s — place on a tile" % _label_for_kind(kind), editor.placeable_part_ids())


func _on_tool_pressed(tool: StringName) -> void:
	var editor: EditorModule = _editor()
	if editor != null:
		editor.active_tool = tool


## A board to load, by catalog name. Maps and sections share a namespace from the author's point of
## view — they picked a board, not a schema — which is exactly what `EditorModule.open` already
## assumes on the way in.
func _on_load_pressed() -> void:
	_pending_kind = &""
	var boards: Array[StringName] = MapCatalog.names()
	boards.append_array(SectionCatalog.names())
	list.open("Load a board", boards)


func _on_list_chosen(id: StringName) -> void:
	var editor: EditorModule = _editor()
	if editor == null:
		return
	if _pending_kind == &"":
		editor.open(String(id))
		return
	editor.selected_part = id
	editor.selected_kind = _pending_kind
	editor.active_tool = &"place"


## The file verbs, called by name. **Every one of them already existed on `EditorModule`** — this
## row is where they are reachable from, not where they are implemented.
func _on_file_pressed(verb: StringName) -> void:
	var editor: EditorModule = _editor()
	if editor != null:
		editor.call(verb)


func _label_for_kind(kind: StringName) -> String:
	return PLACEMENT_LABELS.get(kind, String(kind).capitalize())


func _button(parent: Control, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _editor() -> EditorModule:
	return context.module(&"editor") as EditorModule if context != null else null
