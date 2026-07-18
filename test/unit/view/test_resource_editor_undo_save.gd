extends GutTest

## taskblock-11 Pass C5/C6: undo/redo and save-and-validate, wired into
## the real scene.

const USER_ROOT := "user://test_resource_editor_undo_save"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all(DataLibrary.BUILTIN_ROOT, USER_ROOT)


func after_each() -> void:
	DataLibrary.reset()
	var absolute: String = ProjectSettings.globalize_path(USER_ROOT)
	var parts_dir: DirAccess = DirAccess.open(absolute + "/parts")
	if parts_dir != null:
		parts_dir.list_dir_begin()
		var file_name: String = parts_dir.get_next()
		while file_name != "":
			if not parts_dir.current_is_dir():
				parts_dir.remove(file_name)
			file_name = parts_dir.get_next()
		parts_dir.list_dir_end()
		DirAccess.remove_absolute(absolute + "/parts")
	DirAccess.remove_absolute(absolute)


func _torso_item(scene: ResourceEditorScene) -> TreeItem:
	for child: TreeItem in scene.table.get_root().get_children():
		if (child.get_metadata(0) as Part).id == &"torso":
			return child
	return null


func _select(scene: ResourceEditorScene, item: TreeItem) -> void:
	item.select(0)
	scene._on_item_selected()


## C5: "undo reverts the last edit."
func test_undo_reverts_a_committed_cell_edit() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var torso: TreeItem = _torso_item(scene)
	var part: Part = torso.get_metadata(0)
	var original_hp: int = part.hp

	torso.set_range(hp_column, 999.0)
	scene._apply_edit(torso, hp_column)
	assert_eq(part.hp, 999)

	scene.undo()
	assert_eq(part.hp, original_hp)


func test_redo_reapplies_after_undo() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var torso: TreeItem = _torso_item(scene)
	var part: Part = torso.get_metadata(0)

	torso.set_range(hp_column, 999.0)
	scene._apply_edit(torso, hp_column)
	scene.undo()
	scene.redo()

	assert_eq(part.hp, 999)


## C5: "must survive across... sort/filter changes (undo restores the
## VALUE, not the visual position)."
func test_edits_survive_a_sort_and_undo_still_works_afterward() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var torso: TreeItem = _torso_item(scene)
	var part: Part = torso.get_metadata(0)
	var original_hp: int = part.hp

	torso.set_range(hp_column, 999.0)
	scene._apply_edit(torso, hp_column)

	# A sort/filter change must not discard the in-progress edit — it
	# re-derives its rows from the SAME working set, not a fresh
	# DataLibrary fetch.
	scene._on_column_title_clicked(hp_column, MOUSE_BUTTON_LEFT)
	assert_eq(part.hp, 999, "sorting must not silently revert an unsaved edit")

	scene.undo()
	assert_eq(part.hp, original_hp)


func test_editing_a_socket_can_be_undone() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var torso: TreeItem = _torso_item(scene)
	var socket_row: TreeItem = torso.get_children()[0]
	var socket: Socket = socket_row.get_metadata(0)
	var original_hp: int = socket.joint_hp

	socket_row.set_range(2, 7.0)
	scene._apply_socket_edit(socket_row, 2)
	assert_eq(socket.joint_hp, 7)

	scene.undo()
	assert_eq(socket.joint_hp, original_hp)


func test_ctrl_z_triggers_undo() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var torso: TreeItem = _torso_item(scene)
	var part: Part = torso.get_metadata(0)
	var original_hp: int = part.hp
	torso.set_range(hp_column, 999.0)
	scene._apply_edit(torso, hp_column)

	var event := InputEventKey.new()
	event.keycode = KEY_Z
	event.ctrl_pressed = true
	event.pressed = true
	scene._unhandled_input(event)

	assert_eq(part.hp, original_hp)


func test_ctrl_shift_z_triggers_redo() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var torso: TreeItem = _torso_item(scene)
	var part: Part = torso.get_metadata(0)
	torso.set_range(hp_column, 999.0)
	scene._apply_edit(torso, hp_column)
	scene.undo()

	var event := InputEventKey.new()
	event.keycode = KEY_Z
	event.ctrl_pressed = true
	event.shift_pressed = true
	event.pressed = true
	scene._unhandled_input(event)

	assert_eq(part.hp, 999)


## C6: "an invalid row flags with its named error rather than writing a
## broken file."
func test_save_button_reports_a_named_error_for_an_invalid_edit() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var torso: TreeItem = _torso_item(scene)
	_select(scene, torso)
	scene._selected_resource.failure_mode = &"NOT_A_REAL_MODE"

	scene._on_save_pressed()

	assert_true(scene.save_status.text.contains("failure_mode"))
	assert_false(ResourceLoader.exists(USER_ROOT + "/parts/torso.tres"))


## C6: "a valid save round-trips through DataLibrary."
func test_save_button_writes_a_valid_edit_and_it_round_trips() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var torso: TreeItem = _torso_item(scene)
	_select(scene, torso)
	torso.set_range(hp_column, 42.0)
	scene._apply_edit(torso, hp_column)

	scene._on_save_pressed()

	assert_true(scene.save_status.text.contains("torso"))
	assert_eq(DataLibrary.get_part(&"torso").hp, 42)
	assert_eq(DataLibrary.source_of(DataLibrary.TYPE_PARTS, &"torso"), &"user")


func test_save_with_nothing_selected_reports_status_without_crashing() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	scene._on_save_pressed()

	assert_true(scene.save_status.text.length() > 0)


## The type-select bar stays exactly the three type buttons — save
## controls live in their own row, not mixed into it.
func test_type_bar_only_has_the_three_type_buttons() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_eq(scene.type_bar.get_child_count(), 3)
