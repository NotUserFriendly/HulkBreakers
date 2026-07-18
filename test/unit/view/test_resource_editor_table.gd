extends GutTest

## taskblock-11 Pass C1/C2: table headers (sort) and per-column filters.
## Real res:// data (this is the launched tool, not a fixture-root test).


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _row_ids(scene: ResourceEditorScene) -> Array[StringName]:
	var ids: Array[StringName] = []
	var item: TreeItem = scene.table.get_root()
	if item == null:
		return ids
	for child: TreeItem in item.get_children():
		var resource: Resource = child.get_metadata(0)
		ids.append(resource.get(&"id"))
	return ids


func test_table_has_one_column_per_declared_column() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_eq(scene.table.columns, ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).size())


func test_table_starts_with_every_part_row_present() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_true(_row_ids(scene).has(&"torso"))
	assert_true(_row_ids(scene).has(&"pistol"))


## C1: "click cycles sort modes: none -> ascending -> descending -> none."
func test_clicking_a_header_cycles_through_sort_modes() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")

	scene._on_column_title_clicked(hp_column, MOUSE_BUTTON_LEFT)
	assert_eq(scene.sort_column, &"hp")
	assert_true(scene.sort_ascending)

	scene._on_column_title_clicked(hp_column, MOUSE_BUTTON_LEFT)
	assert_eq(scene.sort_column, &"hp")
	assert_false(scene.sort_ascending)

	scene._on_column_title_clicked(hp_column, MOUSE_BUTTON_LEFT)
	assert_eq(scene.sort_column, &"")


func test_ascending_sort_actually_orders_the_rows() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	scene._on_column_title_clicked(hp_column, MOUSE_BUTTON_LEFT)

	var ids: Array[StringName] = _row_ids(scene)
	var previous_hp: int = -1
	for id: StringName in ids:
		var hp: int = DataLibrary.get_part(id).hp
		assert_true(hp >= previous_hp, "rows must be non-decreasing by hp")
		previous_hp = hp


## C1: "a symbol showing current type (alpha/numeric) and direction."
func test_sorted_column_title_carries_a_direction_symbol() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")

	scene._on_column_title_clicked(hp_column, MOUSE_BUTTON_LEFT)
	assert_true(scene.table.get_column_title(hp_column).contains("▲"))

	scene._on_column_title_clicked(hp_column, MOUSE_BUTTON_LEFT)
	assert_true(scene.table.get_column_title(hp_column).contains("▼"))


## The placeholder is ALWAYS present (reserving the same width whether or
## not a column is sorted) — only the real "#▲"-style symbol is
## conditional on being the active sort column.
func test_unsorted_columns_carry_the_placeholder_not_a_real_symbol() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var mass_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"mass")

	scene._on_column_title_clicked(hp_column, MOUSE_BUTTON_LEFT)
	assert_eq(
		scene.table.get_column_title(mass_column),
		"mass %s" % ResourceEditorScene.SORT_SYMBOL_PLACEHOLDER
	)
	assert_false(scene.table.get_column_title(mass_column).contains("▲"))
	assert_false(scene.table.get_column_title(mass_column).contains("▼"))


## C2: "a filter input under each column header... rows update live."
func test_typing_a_filter_narrows_the_visible_rows() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var id_field: LineEdit = scene.filter_fields[&"id"]

	id_field.text = "pistol"
	id_field.text_changed.emit("pistol")

	assert_eq(_row_ids(scene), [&"pistol"] as Array[StringName])


## C2: "filters combine (AND across columns)."
func test_filters_combine_across_columns() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var material_field: LineEdit = scene.filter_fields[&"material"]
	var id_field: LineEdit = scene.filter_fields[&"id"]

	material_field.text = "steel"
	material_field.text_changed.emit("steel")
	id_field.text = "plate"
	id_field.text_changed.emit("plate")

	for id: StringName in _row_ids(scene):
		assert_true(String(id).contains("plate"))
		assert_true(String(DataLibrary.get_part(id).material).contains("steel"))


func test_clearing_a_filter_restores_the_rows() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var id_field: LineEdit = scene.filter_fields[&"id"]
	id_field.text = "pistol"
	id_field.text_changed.emit("pistol")
	var narrowed: int = _row_ids(scene).size()

	id_field.text = ""
	id_field.text_changed.emit("")

	assert_gt(_row_ids(scene).size(), narrowed)


## Switching type rebuilds the filter row's own fields for the new
## column set, and never carries a stale filter across types.
func test_switching_type_rebuilds_filter_fields_and_clears_filters() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var id_field: LineEdit = scene.filter_fields[&"id"]
	id_field.text = "pistol"
	id_field.text_changed.emit("pistol")

	scene.set_current_type(DataLibrary.TYPE_AMMO)

	assert_true(scene.filter_fields.has(&"projectile_num"))
	assert_false(scene.filter_fields.has(&"material"))
	assert_true(scene.filters.is_empty())


## Selecting a row updates `selected_id` and the metadata panel (B2).
func test_selecting_a_row_populates_metadata() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var root: TreeItem = scene.table.get_root()
	var torso_item: TreeItem = null
	for child: TreeItem in root.get_children():
		if (child.get_metadata(0) as Resource).get(&"id") == &"torso":
			torso_item = child
	torso_item.select(0)
	scene._on_item_selected()

	assert_eq(scene.selected_id, &"torso")
	assert_true(scene.metadata_panel.text.contains("torso"))
	assert_true(scene.metadata_panel.text.contains("builtin"))


## Editing an int cell coerces back to int and applies to the resource.
func test_editing_an_int_cell_applies_to_the_resource() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var hp_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"hp")
	var root: TreeItem = scene.table.get_root()
	var torso_item: TreeItem = null
	for child: TreeItem in root.get_children():
		if (child.get_metadata(0) as Resource).get(&"id") == &"torso":
			torso_item = child
	var resource: Part = torso_item.get_metadata(0)
	var original_hp: int = resource.hp

	torso_item.set_range(hp_column, 999.0)
	scene._apply_edit(torso_item, hp_column)

	assert_ne(resource.hp, original_hp)
	assert_eq(resource.hp, 999)
	assert_typeof(resource.hp, TYPE_INT)


## id is never editable — no matter the type.
func test_id_column_is_never_set_editable() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var root: TreeItem = scene.table.get_root()
	var any_item: TreeItem = root.get_children()[0]
	assert_false(any_item.is_editable(0))
