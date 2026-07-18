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
var table: Tree

var rotating: bool = true


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

	table = Tree.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.hide_root = true
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
	load_data()
	_refresh_preview()


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
