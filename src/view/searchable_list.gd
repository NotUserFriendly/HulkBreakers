class_name SearchableList
extends PanelContainer

## taskblock-57 Pass G1: **a centred, searchable list of things you can pick one of.**
##
## The taskblock asks for it by name for the editor's *"Place Items"* button — *"a centred,
## searchable list of every part placeable on a tile"* — and the editor's `Load` button wants the
## identical surface over the map and section catalogs. **One widget, two callers**: a second
## searchable list written a fortnight later is exactly the shape this project keeps deleting.
##
## ## It decides nothing
##
## Which entries exist is the caller's answer; **which of them match a query is
## `SearchFilter.matching`'s**, in logic, so the search rule is testable without a screen. This
## class builds a `LineEdit`, a scrolling column of `Button`s, and emits an id when one is pressed.
##
## ## Why a `Button` per row rather than an `ItemList`
##
## `ItemList` reports a selected index, so every caller would have to keep a parallel array to map
## the index back to an id — and that array is what goes stale the first time filtering reorders the
## rows. A button that carries its own id in the `pressed` binding cannot disagree with itself.
##
## `visible = false` until `open()`, and it closes on a pick or on `close()`. It never dismisses
## itself on a click elsewhere: the board behind it is the thing an editor click authors on, so
## swallowing that click into "close the dialog" would author nothing and look like a dropped input.

## Emitted when a row is pressed, carrying that row's id. The list closes first, so a handler is
## free to open another one.
signal chosen(id: StringName)

## Room for a title, a search box and roughly a dozen rows before it scrolls. A starting position
## the supervisor's tuning pass owns, not a decision.
const PANEL_SIZE := Vector2(520, 520)

var title_label: Label = null
var search_field: LineEdit = null
## The column the rows live in. Public so a test reads back what is actually offered rather than
## re-deriving it from the filter it already trusts.
var results: VBoxContainer = null
## The rows currently shown, in order. Rebuilt on every keystroke.
var rows: Array[Button] = []

var _entries: Array[StringName] = []


func _init() -> void:
	visible = false
	custom_minimum_size = PANEL_SIZE
	# A modal list is a real target: it must swallow the click that presses a row, or the same click
	# reaches the board underneath and authors a placement where the dialog was.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var column := VBoxContainer.new()
	add_child(column)

	title_label = Label.new()
	column.add_child(title_label)

	search_field = LineEdit.new()
	search_field.placeholder_text = "search"
	search_field.text_changed.connect(apply_filter)
	column.add_child(search_field)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	results = VBoxContainer.new()
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(results)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	column.add_child(close_button)


## Shows `entries` under `title`, unfiltered, with the search box cleared and focused.
##
## **Cleared deliberately**: a list that reopens still holding the last query shows a narrowed set
## the author did not ask for, and the empty state is the one that proves "offers every placeable
## part".
func open(title: String, entries: Array[StringName]) -> void:
	_entries = entries.duplicate()
	title_label.text = title
	search_field.text = ""
	apply_filter("")
	visible = true
	# `grab_focus` needs a real tree; a stand-alone list is still perfectly usable without it.
	if is_inside_tree():
		search_field.grab_focus()


## Closes, and **gives keyboard focus back**. A hidden `LineEdit` keeps focus until something takes
## it, so a closed list went on swallowing every letter the player typed at the board — half of the
## review's *"intercepting 'b' key presses without typing anywhere"*.
func close() -> void:
	visible = false
	if is_inside_tree() and search_field.has_focus():
		search_field.release_focus()


## Rebuilds the rows from `SearchFilter`'s answer. Cheap enough per keystroke: the largest list
## this serves is the parts pool, and rebuilding beats diffing a set that reorders.
##
## **`remove_child` before `queue_free`, and that is the whole of a real defect.** `queue_free` is
## deferred to the end of the frame, so the old rows were still children — and still drawn — while
## the filtered ones were appended after them. Typing `barrel` into a four-entry list left five rows
## on screen: the whole unfiltered list, plus the match. **Reported as "filtered lists aren't
## filtering", which is exactly what it looked like.**
##
## The test that should have caught it read `shown_ids()`, which reports the `rows` array — the
## module's own bookkeeping, which was correct throughout. Nothing asked the container what it was
## actually showing. It does now.
func apply_filter(query: String) -> void:
	for row: Button in rows:
		results.remove_child(row)
		row.queue_free()
	rows.clear()
	for id: StringName in SearchFilter.matching(_entries, query):
		var row := Button.new()
		row.text = String(id)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.pressed.connect(_on_row_pressed.bind(id))
		results.add_child(row)
		rows.append(row)


## The ids currently offered, for a caller or a test that wants the answer rather than the widgets.
func shown_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for row: Button in rows:
		ids.append(StringName(row.text))
	return ids


## Closes before emitting, so a handler that opens a second list is not immediately hidden by this
## one's own teardown.
func _on_row_pressed(id: StringName) -> void:
	close()
	chosen.emit(id)
