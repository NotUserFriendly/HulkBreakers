class_name ResourceEditorScene
extends Control

## taskblock-11: a standalone tool for viewing and tuning every game
## definition — parts, ammo, materials. Named for what it does: it edits
## Godot Resources.
##
## Pass A: a SEPARATE scene, its own PROCESS — launched as its own
## instance of the game executable (`godot --path . <this scene>`), not a
## Godot `EditorPlugin` (a plugin is stripped from exports and can never
## ship to players; this can). It reads and writes `.tres` through the
## SAME `DataLibrary`/`DataValidator` the game uses — editor output and
## game input are identical by construction, the bot-builder discipline
## (use the real system, never a parallel one) applies here too. Writes
## go to `user://data/` only; `res://data/` is read-only once exported.
## No live hot-reload: the running GAME picks up a save on its own next
## boot/sim run (`DataLibrary._loaded` isn't touched by anything here) —
## that's the requested workflow, not a limitation.
##
## Pass B/D: layout. The LEFT column (preview + rotate toggle + metadata)
## never changes WIDTH on a tool resize — it's simply never given the
## EXPAND size flag, so the root HBoxContainer always shrinks it to its
## own minimum and hands every remaining pixel to the table. Within that
## column, the preview alone is also denied the VERTICAL expand flag (so
## it stays its own fixed `PREVIEW_SIZE` regardless of window height)
## while the metadata panel IS given it (so it alone grows/shrinks with
## the window). The table gets EXPAND on both axes.

const PREVIEW_SIZE := 220
const METADATA_MIN_HEIGHT := 160
## radians/sec — B1: "slowly rotating."
const ROTATE_SPEED := 0.5

var current_type: StringName = DataLibrary.TYPE_PARTS
var selected_id: StringName = &""
var theme_root: Control

var left_column: VBoxContainer
var right_column: VBoxContainer
var type_bar: HBoxContainer
var preview_container: SubViewportContainer
var preview_viewport: SubViewport
var preview_pivot: Node3D
var preview_view: HitVolumeView
var rotate_button: Button
var metadata_panel: RichTextLabel
var filter_row: HBoxContainer
var table: Tree

var rotating: bool = true

## C1: the column currently sorted on (&"" = load order) and its
## direction.
var sort_column: StringName = &""
var sort_ascending: bool = true
## C2: column -> substring, only non-empty entries filter.
var filters: Dictionary = {}
## column -> its own LineEdit, rebuilt only when `current_type` changes
## (never mid-keystroke — see `_rebuild_columns_and_filters`).
var filter_fields: Dictionary = {}
## The table's own current rows, in display order — index i's resource is
## whatever `table`'s i'th (post-root) TreeItem shows. Selection/edit
## handlers key off `TreeItem.get_metadata(0)` directly instead, but this
## stays for anything that wants the whole displayed set (C4's hover, a
## future "select all").
var _row_resources: Array[Resource] = []


func _ready() -> void:
	theme_root = self
	theme = HulkTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root_layout := HBoxContainer.new()
	root_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_layout)

	left_column = VBoxContainer.new()
	# Never EXPAND — an HBoxContainer hands every non-expand child exactly
	# its own minimum width, so this column (and everything fixed-width
	# inside it) can never be stretched by a tool resize.
	left_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	root_layout.add_child(left_column)

	_build_preview(left_column)
	_build_metadata(left_column)
	_build_table_column(root_layout)

	set_current_type(current_type)


func _process(delta: float) -> void:
	if rotating and preview_pivot != null:
		preview_pivot.rotate_y(ROTATE_SPEED * delta)


func _build_preview(parent: Control) -> void:
	preview_container = SubViewportContainer.new()
	preview_container.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	# Fixed on BOTH axes (D: "resizing the tool never changes the
	# preview") — no EXPAND flag in either direction.
	preview_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preview_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	preview_container.stretch = true
	parent.add_child(preview_container)

	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
	preview_container.add_child(preview_viewport)

	preview_viewport.add_child(WorldPalette.world_environment())
	preview_viewport.add_child(WorldPalette.directional_light())

	var camera := Camera3D.new()
	# `look_at()` needs a live tree to resolve a Node3D's global transform
	# against — must run AFTER `add_child`, not before (a Camera3D not
	# yet inside the SceneTree fails an internal engine check here).
	preview_viewport.add_child(camera)
	camera.position = Vector3(0.0, 1.0, 2.2)
	camera.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)

	preview_pivot = Node3D.new()
	preview_viewport.add_child(preview_pivot)

	preview_view = HitVolumeView.new()
	preview_pivot.add_child(preview_view)

	rotate_button = Button.new()
	rotate_button.text = "⟳ rotate"
	rotate_button.toggle_mode = true
	rotate_button.button_pressed = true
	rotate_button.toggled.connect(_on_rotate_toggled)
	parent.add_child(rotate_button)


func _on_rotate_toggled(pressed: bool) -> void:
	rotating = pressed


func _build_metadata(parent: Control) -> void:
	metadata_panel = RichTextLabel.new()
	metadata_panel.custom_minimum_size = Vector2(PREVIEW_SIZE, METADATA_MIN_HEIGHT)
	# The one field in this column that DOES grow/shrink vertically with
	# the tool (D) — width stays whatever the fixed left column already
	# settled on.
	metadata_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	metadata_panel.size_flags_horizontal = Control.SIZE_FILL
	metadata_panel.bbcode_enabled = true
	metadata_panel.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	metadata_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(metadata_panel)


func _build_table_column(parent: Control) -> void:
	right_column = VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(right_column)

	type_bar = HBoxContainer.new()
	right_column.add_child(type_bar)
	for type_key: StringName in [
		DataLibrary.TYPE_PARTS, DataLibrary.TYPE_AMMO, DataLibrary.TYPE_MATERIALS
	]:
		var button := Button.new()
		button.text = String(type_key)
		button.pressed.connect(set_current_type.bind(type_key))
		type_bar.add_child(button)

	filter_row = HBoxContainer.new()
	right_column.add_child(filter_row)

	table = Tree.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.hide_root = true
	table.column_titles_visible = true
	table.column_title_clicked.connect(_on_column_title_clicked)
	table.item_edited.connect(_on_item_edited)
	table.item_selected.connect(_on_item_selected)
	right_column.add_child(table)


## Pass A TEST: "the editor loads via DataLibrary." Every definition of
## `current_type`, id -> resource — the same call the table (Pass C)
## re-reads on a type switch.
func load_data() -> Dictionary:
	return DataLibrary.resources_of_type(current_type)


## Pass A TEST: "saving writes a valid `.tres` to `user://data/`; a saved
## file reloads identically." A thin pass-through to `DataLibrary.save` —
## the editor never writes a `.tres` any other way.
func save_resource(resource: Resource) -> Array[ValidationError]:
	return DataLibrary.save(current_type, resource)


func set_current_type(type_key: StringName) -> void:
	current_type = type_key
	selected_id = &""
	sort_column = &""
	sort_ascending = true
	filters.clear()
	_rebuild_columns_and_filters()
	_refresh_table_rows()
	_refresh_preview()
	_refresh_metadata()


## C1: headers, column count/widths, and the filter row's own LineEdits
## — rebuilt only when the column SET changes (a type switch), never on
## every filter keystroke or sort click (that would destroy the LineEdit
## the user is actively typing into).
func _rebuild_columns_and_filters() -> void:
	var columns: Array[StringName] = ResourceEditorColumns.columns_for(current_type)
	table.columns = columns.size()
	for i in range(columns.size()):
		table.set_column_expand(i, true)
		table.set_column_custom_minimum_width(i, 90)

	for child: Node in filter_row.get_children():
		filter_row.remove_child(child)
		child.queue_free()
	filter_fields.clear()
	for column: StringName in columns:
		var field := LineEdit.new()
		field.placeholder_text = "filter %s" % column
		field.custom_minimum_size = Vector2(90, 0)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.text_changed.connect(_on_filter_text_changed.bind(column))
		filter_row.add_child(field)
		filter_fields[column] = field

	_refresh_column_titles()


## C1: "a symbol showing current type (alpha/numeric) and direction" —
## only the active sort column carries one. Split from
## `_rebuild_columns_and_filters` because a sort click needs to update
## titles WITHOUT touching the filter LineEdits.
func _refresh_column_titles() -> void:
	var columns: Array[StringName] = ResourceEditorColumns.columns_for(current_type)
	for i in range(columns.size()):
		var column: StringName = columns[i]
		var title: String = String(column)
		if column == sort_column:
			var kind_symbol: String = (
				"#" if ResourceEditorColumns.is_numeric(current_type, column) else "A"
			)
			var direction_symbol: String = "▲" if sort_ascending else "▼"
			title = "%s %s%s" % [title, kind_symbol, direction_symbol]
		table.set_column_title(i, title)


## C1: "click cycles sort modes: none -> ascending -> descending -> none."
func _on_column_title_clicked(column: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var columns: Array[StringName] = ResourceEditorColumns.columns_for(current_type)
	if column < 0 or column >= columns.size():
		return
	var clicked: StringName = columns[column]
	if sort_column != clicked:
		sort_column = clicked
		sort_ascending = true
	elif sort_ascending:
		sort_ascending = false
	else:
		sort_column = &""
		sort_ascending = true
	_refresh_column_titles()
	_refresh_table_rows()


## C2: "a filter input under each column header... rows update live."
func _on_filter_text_changed(new_text: String, column: StringName) -> void:
	if new_text.strip_edges() == "":
		filters.erase(column)
	else:
		filters[column] = new_text
	_refresh_table_rows()


## Rebuilds the Tree's actual rows from `DataLibrary`, sorted/filtered
## through `ResourceEditorRows` — never touches `filter_row`'s own
## widgets (`_rebuild_columns_and_filters`'s job), so this is safe to
## call on every sort/filter/data change without losing focus or cursor
## position in whatever LineEdit the user is typing into.
func _refresh_table_rows() -> void:
	var columns: Array[StringName] = ResourceEditorColumns.columns_for(current_type)
	var resources: Dictionary = DataLibrary.resources_of_type(current_type)
	_row_resources = ResourceEditorRows.build(resources, filters, sort_column, sort_ascending)

	table.clear()
	var root_item: TreeItem = table.create_item()
	for row: Resource in _row_resources:
		_add_row_item(row, root_item, columns)


func _add_row_item(
	resource: Resource, parent_item: TreeItem, columns: Array[StringName]
) -> TreeItem:
	var item: TreeItem = table.create_item(parent_item)
	item.set_metadata(0, resource)
	for i in range(columns.size()):
		var column: StringName = columns[i]
		var value: Variant = resource.get(column)
		item.set_text(i, str(value))
		if not ResourceEditorColumns.is_editable(column):
			continue
		if ResourceEditorColumns.is_numeric(current_type, column):
			item.set_cell_mode(i, TreeItem.CELL_MODE_RANGE)
			var is_int: bool = typeof(value) == TYPE_INT
			item.set_range_config(i, -999999.0, 999999.0, 1.0 if is_int else 0.01)
			item.set_range(i, float(value))
		else:
			item.set_cell_mode(i, TreeItem.CELL_MODE_STRING)
		item.set_editable(i, true)
	return item


func _on_item_selected() -> void:
	var item: TreeItem = table.get_selected()
	if item == null:
		return
	var resource: Resource = item.get_metadata(0)
	if resource == null:
		return
	selected_id = resource.get(&"id")
	_refresh_preview()
	_refresh_metadata()


## A cell just committed a new value (Tree's own inline STRING/RANGE
## editor) — split from `_apply_edit` only so a test can drive the
## latter directly without going through Tree's own internal
## get_edited()/get_edited_column() tracking, which only reflects reality
## after Tree's own real (non-headless) inline editor UI has run.
func _on_item_edited() -> void:
	_apply_edit(table.get_edited(), table.get_edited_column())


## Reads the new value back off `item`'s `column` cell, coerces it to the
## field's real type, and applies it to the resource the row's own
## metadata names.
func _apply_edit(item: TreeItem, column: int) -> void:
	if item == null:
		return
	var resource: Resource = item.get_metadata(0)
	if resource == null:
		return
	var columns: Array[StringName] = ResourceEditorColumns.columns_for(current_type)
	if column < 0 or column >= columns.size():
		return
	var field: StringName = columns[column]
	if not ResourceEditorColumns.is_editable(field):
		return
	var old_value: Variant = resource.get(field)
	var new_value: Variant = _coerce(old_value, item, column)
	resource.set(field, new_value)
	item.set_text(column, str(new_value))


## Matches the edited cell's new text/range back to `old_value`'s own
## Variant type — Tree's inline editors are string- or float-typed only,
## never StringName/int, so every cell commit needs this on the way back
## in.
func _coerce(old_value: Variant, item: TreeItem, column: int) -> Variant:
	match typeof(old_value):
		TYPE_INT:
			return int(item.get_range(column))
		TYPE_FLOAT:
			return item.get_range(column)
		TYPE_STRING_NAME:
			return StringName(item.get_text(column))
		_:
			return item.get_text(column)


## B2: "filename, resource type, file size, source (res:// built-in vs
## user:// override), validation status."
func _refresh_metadata() -> void:
	if selected_id == &"":
		metadata_panel.text = ""
		return
	var source: StringName = DataLibrary.source_of(current_type, selected_id)
	var resource: Resource = DataLibrary.resources_of_type(current_type).get(selected_id)
	var errors: Array[ValidationError] = (
		DataValidator.validate(resource) if resource != null else []
	)
	var status: String = "valid" if errors.is_empty() else "INVALID: %s" % errors[0].message
	metadata_panel.text = (
		"[b]%s[/b]\ntype: %s\nsource: %s\nstatus: %s"
		% [selected_id, current_type, source if source != &"" else &"unknown", status]
	)


## Renders the selected definition via `HitVolumeView`'s own mesh/
## primitive dispatch (taskblock-10 A) — B1: "the preview is what the
## game will render, not a mock." Only `Part`s have spatial geometry at
## all (no `volume`/`sockets` on `AmmoDef`/`MaterialEntry`); an ammo or
## material selection clears the preview rather than faking one.
func _refresh_preview() -> void:
	if current_type != DataLibrary.TYPE_PARTS or selected_id == &"":
		preview_view.unit = null
		preview_view.refresh()
		return
	var part: Part = DataLibrary.get_part(selected_id)
	if part == null:
		preview_view.unit = null
		preview_view.refresh()
		return
	var unit := Unit.new(Matrix.new(), Shell.new(part), Vector2i.ZERO)
	preview_view.setup(unit, DataLibrary.material_table())
