extends GutTest

## taskblock-11 Pass C4: "however deeply nested (a socket's joint_hp, a
## curve point's dt) is editable" — expandable child rows — plus the
## hover-preview into the metadata panel.

const USER_ROOT := "user://test_resource_editor_nested_rows"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all(DataLibrary.BUILTIN_ROOT, USER_ROOT)


func after_each() -> void:
	DataLibrary.reset()
	_remove_dir_recursive(USER_ROOT)


func _remove_dir_recursive(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	var materials_dir: DirAccess = DirAccess.open(absolute + "/materials")
	if materials_dir != null:
		materials_dir.list_dir_begin()
		var file_name: String = materials_dir.get_next()
		while file_name != "":
			if not materials_dir.current_is_dir():
				materials_dir.remove(file_name)
			file_name = materials_dir.get_next()
		materials_dir.list_dir_end()
		DirAccess.remove_absolute(absolute + "/materials")
	DirAccess.remove_absolute(absolute)


func _torso_item(scene: ResourceEditorScene) -> TreeItem:
	for child: TreeItem in scene.table.get_root().get_children():
		if (child.get_metadata(0) as Part).id == &"torso":
			return child
	return null


## "expand the row, edit the scalar" — a socket's own type/id/joint_hp,
## all as sibling child rows under the part's own row.
func test_a_parts_row_has_one_child_per_socket() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var torso: TreeItem = _torso_item(scene)
	var torso_part: Part = torso.get_metadata(0)

	assert_eq(torso.get_children().size(), torso_part.sockets.size())


func test_socket_child_row_shows_type_id_and_joint_hp() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var torso: TreeItem = _torso_item(scene)
	var first_socket: Socket = torso.get_children()[0].get_metadata(0)
	var row: TreeItem = torso.get_children()[0]

	assert_eq(row.get_text(0), str(first_socket.socket_type))
	assert_eq(row.get_text(1), str(first_socket.id))
	assert_eq(row.get_text(2), str(first_socket.joint_hp))


## C4: "a socket's joint_hp" is editable.
func test_editing_a_sockets_joint_hp_applies_to_the_socket() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var torso: TreeItem = _torso_item(scene)
	var row: TreeItem = torso.get_children()[0]
	var socket: Socket = row.get_metadata(0)

	row.set_text(2, "5")
	scene._apply_socket_edit(row, 2)

	assert_eq(socket.joint_hp, 5)


func test_editing_a_sockets_type_applies_as_a_stringname() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var torso: TreeItem = _torso_item(scene)
	var row: TreeItem = torso.get_children()[0]
	var socket: Socket = row.get_metadata(0)

	row.set_text(0, "RENAMED_TYPE")
	scene._apply_socket_edit(row, 0)

	assert_eq(socket.socket_type, &"RENAMED_TYPE")


func _material_with_curve() -> MaterialEntry:
	var material := MaterialEntry.new()
	material.id = &"layered_test_material"
	material.dt_curve = [Vector2(0.0, 3.0), Vector2(1.0, 6.0)]
	return material


func _material_item(scene: ResourceEditorScene, id: StringName) -> TreeItem:
	for child: TreeItem in scene.table.get_root().get_children():
		if (child.get_metadata(0) as MaterialEntry).id == id:
			return child
	return null


## C4: "a curve point's dt" — one child row per dt_curve point.
func test_a_materials_row_has_one_child_per_curve_point() -> void:
	assert_eq(
		DataLibrary.save(DataLibrary.TYPE_MATERIALS, _material_with_curve()),
		[] as Array[ValidationError]
	)
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	scene.set_current_type(DataLibrary.TYPE_MATERIALS)

	var item: TreeItem = _material_item(scene, &"layered_test_material")
	assert_eq(item.get_children().size(), 2)
	assert_eq(item.get_children()[0].get_text(0), "0.0")
	assert_eq(item.get_children()[0].get_text(1), "3.0")
	assert_eq(item.get_children()[1].get_text(0), "1.0")
	assert_eq(item.get_children()[1].get_text(1), "6.0")


func test_editing_a_curve_points_dt_applies_to_the_array() -> void:
	assert_eq(
		DataLibrary.save(DataLibrary.TYPE_MATERIALS, _material_with_curve()),
		[] as Array[ValidationError]
	)
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	scene.set_current_type(DataLibrary.TYPE_MATERIALS)
	var item: TreeItem = _material_item(scene, &"layered_test_material")
	var row: TreeItem = item.get_children()[0]
	var material: MaterialEntry = row.get_metadata(0)

	row.set_text(1, "4.5")
	scene._apply_curve_edit(row, 1)

	assert_eq(material.dt_curve[0], Vector2(0.0, 4.5))


func test_editing_a_curve_points_thickness_applies_to_the_array() -> void:
	assert_eq(
		DataLibrary.save(DataLibrary.TYPE_MATERIALS, _material_with_curve()),
		[] as Array[ValidationError]
	)
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	scene.set_current_type(DataLibrary.TYPE_MATERIALS)
	var item: TreeItem = _material_item(scene, &"layered_test_material")
	var row: TreeItem = item.get_children()[1]
	var material: MaterialEntry = row.get_metadata(0)

	row.set_text(0, "2")
	scene._apply_curve_edit(row, 0)

	assert_eq(material.dt_curve[1], Vector2(2.0, 6.0))


## C4: "the socket list with their joint_hp... so you can read structure
## without leaving the table."
func test_hover_summary_for_a_part_lists_its_sockets() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var torso: Part = DataLibrary.get_part(&"torso")

	var summary: String = scene._hover_summary_for(torso)
	assert_true(summary.contains("MATRIX"))
	assert_true(summary.contains("joint_hp"))


## "the curve's points" — a material with no curve authored has nothing
## to show (real reference materials today all have an empty dt_curve).
func test_hover_summary_for_a_material_with_no_curve_is_empty() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var steel: MaterialEntry = DataLibrary.get_material(&"steel")

	assert_eq(scene._hover_summary_for(steel), "")


func test_hover_summary_for_a_material_with_a_curve_lists_its_points() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	var summary: String = scene._hover_summary_for(_material_with_curve())
	assert_true(summary.contains("thickness 0.00"))
	assert_true(summary.contains("dt 3.00"))


## A leaf/sockets-and-fields-only part (no sockets, no curve) has no
## hover expansion at all.
func test_hover_summary_for_a_part_with_no_sockets_and_no_volume_is_empty() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var bare := Part.new()
	bare.id = &"bare_part"

	assert_eq(scene._hover_summary_for(bare), "")


## C4's own third named example: "sockets, volume, dt_curve" — a box
## position is view-only geometry (never an editable child row the way
## sockets/dt_curve points are), but still shows up in the hover
## expansion.
func test_hover_summary_for_a_part_lists_its_volume_boxes() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var pistol: Part = DataLibrary.get_part(&"pistol")

	var summary: String = scene._hover_summary_for(pistol)
	assert_true(summary.contains("volume"))
	assert_true(summary.contains(str(pistol.volume[0].center)))
	assert_true(summary.contains(str(pistol.volume[0].size)))


func test_refresh_hover_metadata_falls_back_to_selection_off_a_nested_row() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var torso: TreeItem = _torso_item(scene)
	torso.select(0)
	scene._on_item_selected()
	var socket_row: TreeItem = torso.get_children()[0]

	scene._refresh_hover_metadata(socket_row)

	assert_true(scene.metadata_panel.text.contains("torso"))
