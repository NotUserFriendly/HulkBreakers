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
const COLUMN_MIN_WIDTH := 90
## C1: the sort symbol's own placeholder — reserving the SAME width when
## a column isn't sorted keeps every header's own width constant whether
## or not it currently carries a real "#▲"-style symbol. Without this, a
## header visibly grows/shrinks (and every column after it visibly
## shifts) the moment a sort toggles on or off.
const SORT_SYMBOL_PLACEHOLDER := "··"
## B1: "the preview is what the game will render." Only `torso` (the
## reference humanoid's actual ROOT) carries its own baked-in world
## elevation (docs/01's ROOT_ELEVATION) — every other part's own volume
## is authored relative to wherever ITS socket would normally place it,
## so a bare pistol or plate previewed alone renders down near world
## origin while torso renders up around y=1.5. No single fixed camera
## frames both, so the camera re-centers on whatever actually rendered
## (`_frame_preview_camera`) instead of a guessed constant target — this
## is only the FALLBACK for the empty case (nothing selected yet).
const PREVIEW_CAMERA_TARGET := Vector3.ZERO
## Camera DIRECTION relative to whatever it's currently framing — the
## distance along it scales with the framed geometry's own size
## (`_frame_preview_camera`), so a small pistol and a big torso both
## read as reasonably "zoomed in" instead of one dwarfing the frame and
## the other vanishing into it.
const PREVIEW_CAMERA_DIRECTION := Vector3(0.0, 0.4, 0.8)
## Tuned against the reference torso's own bounding radius (~0.45m) to
## match the framing already confirmed to look right there.
const PREVIEW_CAMERA_DISTANCE_FACTOR := 2.0
const PREVIEW_CAMERA_MIN_RADIUS := 0.15
const PREVIEW_PIVOT_Y_OFFSET := 0.25
## C4: nested child-row column sets — a socket's own [socket_type, id,
## joint_hp] (the taskblock's own worked example) and a dt_curve point's
## own [thickness, dt] (its other one). Both fit inside whatever column
## count the parent definition type happens to have.
const SOCKET_COLUMNS: Array[StringName] = [&"socket_type", &"id", &"joint_hp"]
const CURVE_COLUMNS: Array[StringName] = [&"thickness", &"dt"]

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
var preview_camera: Camera3D
var rotate_button: Button
var metadata_panel: RichTextLabel
var filter_row: HBoxContainer
var table: Tree
var save_button: Button
var save_status: Label

var rotating: bool = true
## C5: "an edit stack of cell changes."
var edit_stack := ResourceEditStack.new()

## C1: the column currently sorted on (&"" = load order) and its
## direction.
var sort_column: StringName = &""
var sort_ascending: bool = true
## C2: column -> substring, only non-empty entries filter.
var filters: Dictionary = {}
## column -> its own LineEdit, rebuilt only when `current_type` changes
## (never mid-keystroke — see `_rebuild_columns_and_filters`).
var filter_fields: Dictionary = {}

## The LIVE resource instance the table's own rows are editing — never
## re-fetched from `DataLibrary` by id once selected (that would return
## a FRESH, unedited duplicate; `DataLibrary.get_part`/`resources_of_type`
## always hand back copies, taskblock-10 B). Preview/metadata/save all
## read this directly so an in-progress, unsaved edit shows up
## immediately everywhere, not just in the table cell itself.
var _selected_resource: Resource = null
## The table's own current rows, in display order — index i's resource is
## whatever `table`'s i'th (post-root) TreeItem shows. Selection/edit
## handlers key off `TreeItem.get_metadata(0)` directly instead, but this
## stays for anything that wants the whole displayed set (C4's hover, a
## future "select all").
var _row_resources: Array[Resource] = []
## C5: "must survive across... sort/filter changes." A STABLE working
## set, fetched from `DataLibrary` exactly once per type-switch — never
## re-fetched by `_refresh_table_rows` itself, which would hand back
## fresh, UNEDITED duplicates (taskblock-10 B: every `DataLibrary` getter
## always duplicates) and silently discard every in-progress edit on the
## very next sort click or filter keystroke. Reset only on
## `set_current_type` or after a successful `save()` (which re-syncs this
## one row from `DataLibrary`'s own now-updated cache).
var _working_resources: Dictionary = {}


func _ready() -> void:
	theme_root = self
	theme = HulkTheme.build()
	# NOT set_anchors_preset(): that call preserves the control's CURRENT
	# screen rect by solving for new offsets around the new anchors — a
	# no-op-looking fill only when called on a node that has no parent
	# YET (BattleScene/BuilderScene's theme_root pattern: anchors set
	# before add_child). Called here, in this scene's OWN _ready(), self
	# is already parented at the real viewport size, so that formula
	# computes a large NEGATIVE offset (offset_right = -viewport_width)
	# to keep the control pinned at its pre-anchor (0,0) rect — the
	# window resize this scene exists to prove never took effect at all.
	# set_anchors_AND_offsets_preset() forces the offsets to zero
	# unconditionally, actually filling the parent now.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root_layout := HBoxContainer.new()
	root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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


## C5: "working undo on Ctrl+Z (and redo on Ctrl+Shift+Z)."
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key_event: InputEventKey = event
	if not key_event.ctrl_pressed or key_event.keycode != KEY_Z:
		return
	if key_event.shift_pressed:
		redo()
	else:
		undo()
	get_viewport().set_input_as_handled()


## Reverts the last edit and rebuilds the table from the now-current
## resource state — a full rebuild, not a hunt for the exact TreeItem
## that made the edit, because C5 explicitly does NOT promise the undone
## row is even still visible under the current sort/filter.
func undo() -> void:
	var edit: ResourceEdit = edit_stack.undo()
	if edit == null:
		return
	_refresh_table_rows()
	_refresh_preview()
	_refresh_metadata()


func redo() -> void:
	var edit: ResourceEdit = edit_stack.redo()
	if edit == null:
		return
	_refresh_table_rows()
	_refresh_preview()
	_refresh_metadata()


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

	preview_camera = Camera3D.new()
	# `look_at()` needs a live tree to resolve a Node3D's global transform
	# against — must run AFTER `add_child`, not before (a Camera3D not
	# yet inside the SceneTree fails an internal engine check here).
	preview_viewport.add_child(preview_camera)
	preview_camera.position = PREVIEW_CAMERA_TARGET + PREVIEW_CAMERA_DIRECTION
	preview_camera.look_at(PREVIEW_CAMERA_TARGET, Vector3.UP)

	preview_pivot = Node3D.new()
	# HitVolumeView always draws its own ground team-marker disc at the
	# unit's own cell origin (y≈0) alongside the part — raising the WHOLE
	# pivot lifts both together, but also lifts the disc mostly out of
	# frame (the camera target sits above it, per PREVIEW_CAMERA_TARGET)
	# instead of sharing the same visual space as the part and z-fighting
	# with whatever of its geometry sits low.
	preview_pivot.position.y = PREVIEW_PIVOT_Y_OFFSET
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

	var save_bar := HBoxContainer.new()
	right_column.add_child(save_bar)
	save_button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	save_bar.add_child(save_button)

	save_status = Label.new()
	save_bar.add_child(save_status)

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
	table.custom_popup_edited.connect(_on_custom_popup_edited)
	table.gui_input.connect(_on_table_gui_input)
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


## C6: "edits validate through DataValidator on save; an invalid row
## flags with its named error rather than writing a broken file." Saves
## the currently SELECTED definition — the one the preview/metadata
## panel are already showing.
func _on_save_pressed() -> void:
	if _selected_resource == null:
		save_status.text = "nothing selected"
		return
	var errors: Array[ValidationError] = save_resource(_selected_resource)
	if errors.is_empty():
		save_status.text = "saved %s" % selected_id
	else:
		# C6: "an invalid row flags with its NAMED error" — the field it
		# came from, not just the free-text message.
		save_status.text = "INVALID %s.%s: %s" % [selected_id, errors[0].field, errors[0].message]


func set_current_type(type_key: StringName) -> void:
	current_type = type_key
	selected_id = &""
	_selected_resource = null
	sort_column = &""
	sort_ascending = true
	filters.clear()
	edit_stack.clear()
	_working_resources = load_data()
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
		# Only the LAST column claims leftover width — every earlier one
		# is a fixed, genuinely user-draggable width. Godot's Tree keeps
		# recomputing an `expand=true` column's width from its stretch
		# ratio on every layout pass, which fights (and silently
		# reverts) a manual header-boundary drag; a non-expand column's
		# width is exactly what the user last set it to.
		table.set_column_expand(i, i == columns.size() - 1)
		table.set_column_custom_minimum_width(i, COLUMN_MIN_WIDTH)

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
		var symbol: String = SORT_SYMBOL_PLACEHOLDER
		if column == sort_column:
			var kind_symbol: String = (
				"#" if ResourceEditorColumns.is_numeric(current_type, column) else "A"
			)
			var direction_symbol: String = "▲" if sort_ascending else "▼"
			symbol = "%s%s" % [kind_symbol, direction_symbol]
		table.set_column_title(i, "%s %s" % [column, symbol])


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
	_row_resources = ResourceEditorRows.build(
		_working_resources, filters, sort_column, sort_ascending
	)

	table.clear()
	var root_item: TreeItem = table.create_item()
	for row: Resource in _row_resources:
		var item: TreeItem = _add_row_item(row, root_item, columns)
		# C4/table intro: "expand the row, edit the scalar" — sockets and
		# dt_curve are the two concrete nested cases this taskblock names
		# (a socket's joint_hp, a curve point's dt), not a generic walk
		# over every Array field every Resource type happens to export.
		if row is Part:
			_add_socket_rows(row as Part, item)
		elif row is MaterialEntry:
			_add_curve_rows(row as MaterialEntry, item)
		# Sub-items start collapsed — expanding is an explicit ask, not
		# the default state of a table with 20+ rows, most of which have
		# children.
		if item.get_child_count() > 0:
			item.collapsed = true


func _add_row_item(
	resource: Resource, parent_item: TreeItem, columns: Array[StringName]
) -> TreeItem:
	var item: TreeItem = table.create_item(parent_item)
	item.set_metadata(0, resource)
	item.set_meta(&"row_kind", &"top_level")
	for i in range(columns.size()):
		var column: StringName = columns[i]
		var value: Variant = resource.get(column)
		if not ResourceEditorColumns.is_editable(column):
			item.set_text(i, str(value))
			continue
		if ResourceEditorColumns.is_numeric(current_type, column):
			item.set_cell_mode(i, TreeItem.CELL_MODE_RANGE)
			var is_int: bool = typeof(value) == TYPE_INT
			item.set_range_config(i, -999999.0, 999999.0, 1.0 if is_int else 0.01)
			item.set_range(i, float(value))
		elif ResourceEditorColumns.is_dropdown(current_type, column):
			# C3: a StringName field (material/failure_mode/stack_type/
			# render_primitive, ...) edits through a suggestion popup
			# only, never free text — steering away from a typo the
			# validator would just reject anyway. set_cell_mode() MUST
			# run before set_text() — changing cell mode clears whatever
			# text was already there, so a CUSTOM cell set up in the
			# other order shows the popup arrow with no value at all.
			item.set_cell_mode(i, TreeItem.CELL_MODE_CUSTOM)
			item.set_text(i, str(value))
		else:
			item.set_cell_mode(i, TreeItem.CELL_MODE_STRING)
			item.set_text(i, str(value))
		item.set_editable(i, true)
	return item


func _add_socket_rows(part: Part, parent_item: TreeItem) -> void:
	for socket: Socket in part.sockets:
		var item: TreeItem = table.create_item(parent_item)
		item.set_meta(&"row_kind", &"socket")
		item.set_metadata(0, socket)
		item.set_text(0, str(socket.socket_type))
		item.set_cell_mode(0, TreeItem.CELL_MODE_STRING)
		item.set_editable(0, true)
		item.set_text(1, str(socket.id))
		item.set_cell_mode(1, TreeItem.CELL_MODE_STRING)
		item.set_editable(1, true)
		item.set_text(2, str(socket.joint_hp))
		item.set_cell_mode(2, TreeItem.CELL_MODE_RANGE)
		item.set_range_config(2, 0.0, 999.0, 1.0)
		item.set_range(2, float(socket.joint_hp))
		item.set_editable(2, true)


func _add_curve_rows(material: MaterialEntry, parent_item: TreeItem) -> void:
	for i in range(material.dt_curve.size()):
		var point: Vector2 = material.dt_curve[i]
		var item: TreeItem = table.create_item(parent_item)
		item.set_meta(&"row_kind", &"dt_curve_point")
		item.set_metadata(0, material)
		item.set_meta(&"curve_index", i)
		_set_curve_cell(item, 0, point.x)
		_set_curve_cell(item, 1, point.y)


func _set_curve_cell(item: TreeItem, column: int, value: float) -> void:
	item.set_text(column, str(value))
	item.set_cell_mode(column, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(column, -999999.0, 999999.0, 0.01)
	item.set_range(column, value)
	item.set_editable(column, true)


## C3: "a dropdown compiled from the other values in that column"
## (the fallback) — "for fields backed by a real vocabulary... pull
## from DataLibrary" (the enhancement, `ResourceEditorColumns.
## vocabulary_for`). Returns whichever applies.
func _dropdown_options_for(column: StringName) -> Array[String]:
	var closed: Array[StringName] = ResourceEditorColumns.vocabulary_for(current_type, column)
	if not closed.is_empty():
		var options: Array[String] = []
		for value: StringName in closed:
			options.append(String(value))
		return options
	return ResourceEditorRows.distinct_values(_row_resources, column)


## The popup's own arrow was clicked (`Tree.custom_popup_edited`) —
## builds a fresh `PopupMenu` from `_dropdown_options_for` and shows it
## at the cell's own custom-button rect.
func _on_custom_popup_edited(_arrow_clicked: bool) -> void:
	var item: TreeItem = table.get_edited()
	var column: int = table.get_edited_column()
	if item == null:
		return
	var columns: Array[StringName] = ResourceEditorColumns.columns_for(current_type)
	if column < 0 or column >= columns.size():
		return
	var field: StringName = columns[column]

	var menu := PopupMenu.new()
	add_child(menu)
	for option: String in _dropdown_options_for(field):
		menu.add_item(option)
	menu.id_pressed.connect(
		func(id: int) -> void: _apply_dropdown_choice(item, column, menu.get_item_text(id))
	)
	menu.close_requested.connect(menu.queue_free)
	menu.id_pressed.connect(menu.queue_free, CONNECT_DEFERRED)
	var rect: Rect2 = table.get_custom_popup_rect()
	menu.popup(Rect2i(rect.position, rect.size))


## Applies a chosen dropdown value straight to the resource — split out
## from `_apply_edit` (Tree's `get_range`/`get_text` cell readback)
## because a `CELL_MODE_CUSTOM` cell was never actually edited through
## Tree's own inline editor; the value comes from the popup menu instead.
func _apply_dropdown_choice(item: TreeItem, column: int, value: String) -> void:
	var resource: Resource = item.get_metadata(0)
	if resource == null:
		return
	var columns: Array[StringName] = ResourceEditorColumns.columns_for(current_type)
	if column < 0 or column >= columns.size():
		return
	var field: StringName = columns[column]
	var old_value: Variant = resource.get(field)
	var new_value: StringName = StringName(value)
	if new_value == old_value:
		return
	resource.set(field, new_value)
	edit_stack.record(resource, field, old_value, new_value)
	item.set_text(column, value)


func _on_item_selected() -> void:
	var item: TreeItem = table.get_selected()
	if item == null:
		return
	# A socket/dt_curve-point child row's own metadata(0) is a Socket or
	# MaterialEntry, never the top-level definition — selecting one must
	# not repoint the preview/metadata/save target at it.
	if item.get_meta(&"row_kind", &"top_level") != &"top_level":
		return
	var resource: Resource = item.get_metadata(0)
	if resource == null:
		return
	_selected_resource = resource
	selected_id = resource.get(&"id")
	_refresh_preview()
	_refresh_metadata()


## A cell just committed a new value (Tree's own inline STRING/RANGE
## editor) — dispatches on `row_kind` (set once, per row, at build time)
## since a socket row and a dt_curve-point row don't write back to a
## top-level Resource field the same way `_apply_edit` does. Split from
## `_apply_edit`/`_apply_socket_edit`/`_apply_curve_edit` only so a test
## can drive those directly without going through Tree's own internal
## get_edited()/get_edited_column() tracking, which only reflects reality
## after Tree's own real (non-headless) inline editor UI has run.
func _on_item_edited() -> void:
	var item: TreeItem = table.get_edited()
	var column: int = table.get_edited_column()
	if item == null:
		return
	match item.get_meta(&"row_kind", &"top_level"):
		&"socket":
			_apply_socket_edit(item, column)
		&"dt_curve_point":
			_apply_curve_edit(item, column)
		_:
			_apply_edit(item, column)


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
	if new_value == old_value:
		return
	resource.set(field, new_value)
	edit_stack.record(resource, field, old_value, new_value)
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


## C4: a socket child row's own edit — `Socket` is itself a `Resource`
## (exported `socket_type`/`id`/`joint_hp`), so this is `_apply_edit`'s
## same shape, just keyed off `SOCKET_COLUMNS` instead of a top-level
## definition type's own column list.
func _apply_socket_edit(item: TreeItem, column: int) -> void:
	var socket: Socket = item.get_metadata(0)
	if socket == null or column < 0 or column >= SOCKET_COLUMNS.size():
		return
	var field: StringName = SOCKET_COLUMNS[column]
	if field == &"joint_hp":
		var old_hp: int = socket.joint_hp
		var new_hp: int = int(item.get_range(column))
		if new_hp == old_hp:
			return
		socket.joint_hp = new_hp
		edit_stack.record(socket, field, old_hp, new_hp)
		item.set_text(column, str(new_hp))
	else:
		var old_value: StringName = socket.get(field)
		var new_value: StringName = StringName(item.get_text(column))
		if new_value == old_value:
			return
		socket.set(field, new_value)
		edit_stack.record(socket, field, old_value, new_value)


## C4: a dt_curve-point child row's own edit. `dt_curve` is
## `Array[Vector2]` — a point isn't a `Resource` with settable fields, so
## this reads the whole `Vector2`, replaces the edited axis, and writes
## the WHOLE point back into the array (Vector2 is a value type; there's
## no in-place `.x =` on an array element).
func _apply_curve_edit(item: TreeItem, column: int) -> void:
	var material: MaterialEntry = item.get_metadata(0)
	var index: int = item.get_meta(&"curve_index", -1)
	if material == null or index < 0 or index >= material.dt_curve.size():
		return
	if column < 0 or column >= CURVE_COLUMNS.size():
		return
	var point: Vector2 = material.dt_curve[index]
	var old_value: float = point.x if column == 0 else point.y
	var new_value: float = item.get_range(column)
	if new_value == old_value:
		return
	var setter := func(value: float) -> void:
		var current: Vector2 = material.dt_curve[index]
		if column == 0:
			current.x = value
		else:
			current.y = value
		material.dt_curve[index] = current
	setter.call(new_value)
	edit_stack.record(
		material,
		StringName("dt_curve[%d].%s" % [index, "x" if column == 0 else "y"]),
		old_value,
		new_value,
		setter
	)
	item.set_text(column, str(new_value))


## B2: "filename, resource type, file size, source (res:// built-in vs
## user:// override), validation status."
func _refresh_metadata() -> void:
	if selected_id == &"" or _selected_resource == null:
		metadata_panel.text = ""
		return
	# Source is looked up by the id it was LOADED under — a save moves an
	# id from builtin to user (DataLibrary.save's own contract), and an
	# in-progress, unsaved `id` edit is deliberately not possible at all
	# (id is never editable, ResourceEditorColumns.is_editable).
	var source: StringName = DataLibrary.source_of(current_type, selected_id)
	var errors: Array[ValidationError] = DataValidator.validate(_selected_resource)
	var status: String = "valid" if errors.is_empty() else "INVALID: %s" % errors[0].message
	metadata_panel.text = (
		"[b]%s[/b]\ntype: %s\nsource: %s\nstatus: %s"
		% [selected_id, current_type, source if source != &"" else &"unknown", status]
	)


## C4: "hovering a sockets or volume cell in the table renders its
## expansion into this metadata panel" — "the socket list with their
## joint_hp, the curve's points... so you can read structure without
## leaving the table." Reuses the gui_input + get_item_at_position hover
## convention `InventoryPanel`/`QueuePanel` already establish (Tree has
## no native per-item hover signal).
func _on_table_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	var item: TreeItem = table.get_item_at_position((event as InputEventMouseMotion).position)
	_refresh_hover_metadata(item)


func _refresh_hover_metadata(item: TreeItem) -> void:
	if item == null or item.get_meta(&"row_kind", &"top_level") != &"top_level":
		_refresh_metadata()
		return
	var resource: Resource = item.get_metadata(0)
	var summary: String = _hover_summary_for(resource) if resource != null else ""
	if summary == "":
		_refresh_metadata()
		return
	metadata_panel.text = summary


## The actual expansion text — split out so a test can assert its
## content directly without simulating real mouse motion.
func _hover_summary_for(resource: Resource) -> String:
	if resource is Part:
		var part: Part = resource
		# volume boxes are GEOMETRY (table intro: "a box position...
		# view-only, hover-preview in metadata") — never a child row like
		# sockets/dt_curve, but still one of C4's own three named
		# examples ("sockets, volume, dt_curve") for this summary.
		var sections: Array[String] = []
		var sockets: String = _socket_summary(part)
		if sockets != "":
			sections.append(sockets)
		var volume: String = _volume_summary(part)
		if volume != "":
			sections.append(volume)
		return "\n\n".join(sections)
	if resource is MaterialEntry:
		return _curve_summary(resource as MaterialEntry)
	return ""


func _socket_summary(part: Part) -> String:
	if part.sockets.is_empty():
		return ""
	var lines: Array[String] = ["[b]%s sockets[/b]" % part.id]
	for socket: Socket in part.sockets:
		lines.append(
			(
				"· %s [%s] joint_hp %d/%d"
				% [socket.socket_type, socket.id, socket.joint_hp, socket.joint_hp_max]
			)
		)
	return "\n".join(lines)


## C4's own third named example ("sockets, volume, dt_curve") — view-only
## geometry (table intro: "a box position... hover-preview in metadata;
## gizmo stays in the Inspector, out of scope"), never an editable child
## row the way sockets/dt_curve points are.
func _volume_summary(part: Part) -> String:
	if part.volume.is_empty():
		return ""
	var lines: Array[String] = ["[b]%s volume[/b]" % part.id]
	for box: Box in part.volume:
		lines.append("· center %s size %s" % [box.center, box.size])
	return "\n".join(lines)


func _curve_summary(material: MaterialEntry) -> String:
	if material.dt_curve.is_empty():
		return ""
	var lines: Array[String] = ["[b]%s dt_curve[/b]" % material.id]
	for point: Vector2 in material.dt_curve:
		lines.append("· thickness %.2f -> dt %.2f" % [point.x, point.y])
	return "\n".join(lines)


## Renders the selected definition via `HitVolumeView`'s own mesh/
## primitive dispatch (taskblock-10 A) — B1: "the preview is what the
## game will render, not a mock." Only `Part`s have spatial geometry at
## all (no `volume`/`sockets` on `AmmoDef`/`MaterialEntry`); an ammo or
## material selection clears the preview rather than faking one.
func _refresh_preview() -> void:
	if current_type != DataLibrary.TYPE_PARTS or _selected_resource == null:
		preview_view.unit = null
		preview_view.refresh()
		return
	# The LIVE (possibly unsaved-edited) instance, not a fresh
	# DataLibrary duplicate — B1's "the preview is what the game will
	# render" extends to a still-being-tuned value too.
	var part: Part = _selected_resource as Part
	# Unit.is_downed() (docs/10 taskblock03 G) is true whenever NOTHING in
	# the shell hosts a docked matrix — true for nearly every previewed
	# part (a plate, a weapon, even torso/head on their own, since
	# nothing here ever docks one), and HitVolumeView then renders the
	# whole thing through Poses.down(): a 90° rotation around the root
	# socket that swaps the part's own "up" for "forward". A preview
	# pane showing every part lying on its side is not "what the game
	# will render" for a standing unit. Fixed by mounting `part` under a
	# throwaway, invisible (empty volume, never drawn) carrier that DOES
	# host a docked matrix — `is_downed()` reads false, the down-pose
	# never applies, and the carrier itself contributes nothing to what's
	# drawn. Direct socket assignment (not PartGraph.attach) deliberately
	# skips attaches_to matching: this mount is cosmetic scaffolding, not
	# a real attachment `part`'s own data should ever reflect.
	var carrier := Part.new()
	carrier.sockets = [Socket.new(&"MATRIX")]
	carrier.dock_matrix(Matrix.new())
	var mount := Socket.new(&"__preview_mount", Transform3D.IDENTITY)
	mount.occupant = part
	carrier.sockets.append(mount)
	var unit := Unit.new(carrier.hosted_matrix, Shell.new(carrier), Vector2i.ZERO)
	preview_view.setup(unit, DataLibrary.material_table())
	_frame_preview_camera()


## Re-centers the camera on whatever `preview_view` actually just drew,
## at a distance scaled to its own bounding size — see
## PREVIEW_CAMERA_TARGET's own comment for why a single fixed target
## can't work across every part's own authored volume.
func _frame_preview_camera() -> void:
	var combined: AABB
	var has_any := false
	# `preview_view.get_children()` also includes the team-marker disc
	# and facing wedge — always at the unit's own cell origin, never
	# where the part itself sits — which would pull the frame back down
	# toward y≈0 for an elevated part like torso. `_meshes_by_part` is
	# HitVolumeView's own record of exactly the geometry a PART actually
	# owns (docs/10 taskblock05 C: built for hover-highlighting, but the
	# exact same "which meshes are the part's own" answer this needs).
	for meshes: Array in preview_view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			var world_aabb: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
			combined = world_aabb if not has_any else combined.merge(world_aabb)
			has_any = true
	var center: Vector3 = combined.get_center() if has_any else PREVIEW_CAMERA_TARGET
	var radius: float = (
		maxf(combined.size.length() / 2.0, PREVIEW_CAMERA_MIN_RADIUS) if has_any else 0.5
	)
	preview_camera.position = (
		center + PREVIEW_CAMERA_DIRECTION * radius * PREVIEW_CAMERA_DISTANCE_FACTOR
	)
	preview_camera.look_at(center, Vector3.UP)
