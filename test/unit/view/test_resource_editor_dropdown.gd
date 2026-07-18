extends GutTest

## taskblock-11 Pass C3: "when editing a cell, offer a dropdown compiled
## from the other values in that column... for fields backed by a real
## vocabulary, pull from DataLibrary."


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _item_for(scene: ResourceEditorScene, id: StringName) -> TreeItem:
	for child: TreeItem in scene.table.get_root().get_children():
		if (child.get_metadata(0) as Resource).get(&"id") == id:
			return child
	return null


## material/failure_mode/stack_type/render_primitive are StringName
## fields — plain free text, same as every other column, PLUS a
## dropdown-arrow button as an aid alongside typing (never a replacement
## for it — a cell that only accepted a menu choice couldn't be "dumb").
func test_vocabulary_columns_stay_plain_string_mode_with_a_dropdown_button() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var item: TreeItem = _item_for(scene, &"torso")
	var material_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(
		&"material"
	)

	assert_eq(item.get_cell_mode(material_column), TreeItem.CELL_MODE_STRING)
	assert_eq(item.get_button_count(material_column), 1)


## A column with no closed/derived vocabulary at all never gets the
## dropdown button — display_name is prose, hp is numeric, neither is a
## StringName.
func test_non_dropdown_columns_have_no_button() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var item: TreeItem = _item_for(scene, &"torso")
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var name_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(
		&"display_name"
	)

	assert_eq(item.get_button_count(hp_column), 0)
	assert_eq(item.get_button_count(name_column), 0)


## display_name is a plain String — freeform prose, stays free-text.
func test_display_name_stays_plain_string_mode() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var item: TreeItem = _item_for(scene, &"torso")
	var name_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(
		&"display_name"
	)

	assert_eq(item.get_cell_mode(name_column), TreeItem.CELL_MODE_STRING)


## "for fields backed by a real vocabulary (materials...), pull from
## DataLibrary" — every real material id shows up, not just ones already
## used on-screen.
func test_material_dropdown_pulls_the_full_data_library_vocabulary() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	var options: Array[String] = scene._dropdown_options_for(&"material")
	assert_true(
		options.has("reactive"), "reactive has no reference-humanoid part but IS a material"
	)
	assert_true(options.has("steel"))


## "...its five options" — failure_mode's dropdown is DataValidator's own
## closed list, not whatever's merely visible in the current rows.
func test_failure_mode_dropdown_is_the_full_closed_vocabulary() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	var options: Array[String] = scene._dropdown_options_for(&"failure_mode")
	for mode: StringName in DataValidator.FAILURE_MODES:
		assert_true(options.has(String(mode)), "%s must be offered" % mode)


## "the burn/bleed set" — ammo's stack_type.
func test_stack_type_dropdown_matches_the_ammo_vocabulary() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	scene.set_current_type(DataLibrary.TYPE_AMMO)

	var options: Array[String] = scene._dropdown_options_for(&"stack_type")
	assert_true(options.has("BURN"))
	assert_true(options.has("BLEED"))


## `mangles_into` has no closed vocabulary declared — the dropdown falls
## back to whatever distinct values already exist in that column.
func test_a_column_with_no_closed_vocabulary_falls_back_to_column_values() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_eq(
		ResourceEditorColumns.vocabulary_for(DataLibrary.TYPE_PARTS, &"mangles_into"),
		[] as Array[StringName]
	)
	assert_eq(
		scene._dropdown_options_for(&"mangles_into"),
		ResourceEditorRows.distinct_values(scene._row_resources, &"mangles_into")
	)


## Choosing a dropdown option applies it to the resource and the cell.
func test_choosing_a_dropdown_option_applies_it() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var item: TreeItem = _item_for(scene, &"torso")
	var material_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(
		&"material"
	)
	var resource: Part = item.get_metadata(0)

	scene._apply_dropdown_choice(item, material_column, "reactive")

	assert_eq(resource.material, &"reactive")
	assert_eq(item.get_text(material_column), "reactive")
