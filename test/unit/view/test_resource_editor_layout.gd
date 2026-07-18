extends GutTest

## taskblock-11 Pass B/D: layout and resize behavior. Godot's Container
## sizing is declarative (size flags + custom_minimum_size) and resolved
## by the engine on layout, so this asserts the DECLARATIONS that
## resize behavior is built from, the same way the rest of this codebase
## tests pure state rather than a rendered frame — no viewport resize,
## no awaited layout pass, nothing that could flake on timing.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## D: "resizing the tool does not resize the preview window" — fixed on
## BOTH axes, never EXPAND in either direction.
func test_preview_never_expands_on_either_axis() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_eq(scene.preview_container.custom_minimum_size, Vector2(220, 220))
	assert_false(
		bool(scene.preview_container.size_flags_horizontal & Control.SIZE_EXPAND),
		"the preview must never claim extra horizontal space"
	)
	assert_false(
		bool(scene.preview_container.size_flags_vertical & Control.SIZE_EXPAND),
		"the preview must never claim extra vertical space"
	)


## D: "it changes the height of the metadata window" — vertical EXPAND,
## but not horizontal (its width is whatever the fixed left column gives
## it, same as the preview above it).
func test_metadata_expands_vertically_but_not_horizontally() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_true(
		bool(scene.metadata_panel.size_flags_vertical & Control.SIZE_EXPAND),
		"metadata must grow/shrink vertically with the tool"
	)
	assert_false(
		bool(scene.metadata_panel.size_flags_horizontal & Control.SIZE_EXPAND),
		"metadata's own width must not itself claim extra space"
	)


## D: "it changes both height and width of the table" — EXPAND on both
## axes, so it takes all remaining space.
func test_table_expands_on_both_axes() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_true(bool(scene.table.size_flags_horizontal & Control.SIZE_EXPAND))
	assert_true(bool(scene.table.size_flags_vertical & Control.SIZE_EXPAND))


## The structural guarantee everything above depends on: the LEFT column
## itself (preview + metadata's shared parent) never expands horizontally
## — an HBoxContainer hands a non-expand child exactly its own minimum
## width and gives every remaining pixel to whatever sibling DOES expand
## (the right/table column).
func test_left_column_never_expands_horizontally_the_right_column_does() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_false(bool(scene.left_column.size_flags_horizontal & Control.SIZE_EXPAND))
	assert_true(bool(scene.right_column.size_flags_horizontal & Control.SIZE_EXPAND))


func test_preview_and_metadata_share_the_lefts_own_fixed_width() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_eq(
		scene.metadata_panel.custom_minimum_size.x, scene.preview_container.custom_minimum_size.x
	)


## B1: "the preview renders the selected definition via HitVolumeView" —
## the actual dispatch is taskblock-10 A's; this only proves the editor
## wires the right unit in.
func test_selecting_a_part_populates_the_preview() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	scene.selected_id = &"torso"
	scene._selected_resource = DataLibrary.get_part(&"torso")
	scene._refresh_preview()

	assert_not_null(scene.preview_view.unit)
	# The root is a throwaway matrix-hosting carrier (so Unit.is_downed()
	# reads false and the preview never renders lying down) — the part
	# itself is mounted a level below it, not the root.
	assert_not_null(scene.preview_view.unit.shell.find_part(&"torso"))


## B1: only Parts have spatial geometry — an ammo/material selection
## must never fabricate a fake preview.
func test_selecting_ammo_or_material_clears_the_preview() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	scene.selected_id = &"torso"
	scene._selected_resource = DataLibrary.get_part(&"torso")
	scene._refresh_preview()
	assert_not_null(scene.preview_view.unit)

	scene.set_current_type(DataLibrary.TYPE_AMMO)
	scene.selected_id = &"9mm_fmj"
	scene._selected_resource = DataLibrary.get_ammo(&"9mm_fmj")
	scene._refresh_preview()

	assert_null(scene.preview_view.unit)


## B1: "a toggle button to stop/start rotation."
func test_rotate_toggle_flips_the_rotating_flag() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	assert_true(scene.rotating, "rotation starts on")

	scene.rotate_button.button_pressed = false
	scene.rotate_button.toggled.emit(false)
	assert_false(scene.rotating)


func test_process_only_rotates_the_preview_pivot_while_rotating() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	scene.rotating = false
	var before: float = scene.preview_pivot.rotation.y
	scene._process(1.0)
	assert_eq(scene.preview_pivot.rotation.y, before, "toggled off must not spin the pivot")

	scene.rotating = true
	scene._process(1.0)
	assert_ne(scene.preview_pivot.rotation.y, before, "toggled on must spin the pivot")


## B: the top type-select bar switches which definitions the table (and
## Pass A's own load_data()) reads.
func test_type_bar_has_one_button_per_definition_type() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_eq(scene.type_bar.get_child_count(), 3)


func test_clicking_a_type_button_switches_current_type() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	for button: Button in scene.type_bar.get_children():
		if button.text == String(DataLibrary.TYPE_AMMO):
			button.pressed.emit()
	assert_eq(scene.current_type, DataLibrary.TYPE_AMMO)
