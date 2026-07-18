extends GutTest

## id shrinks to exactly its own content; display_name sizes to its own
## longest value (with a floor), so it never truncates.

const BUILTIN_ROOT := "user://test_column_widths_builtin"
const USER_ROOT := "user://test_column_widths_user"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _remove_dir_recursive(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
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


## Loads a fresh scene against ONLY the given part (an isolated fixture,
## not the real reference-humanoid pool) — the pool's own ids/names vary
## too widely in length to cleanly demonstrate "shrinks below the shared
## default" or "widens past the floor" one at a time.
func _scene_with_only(part: Part) -> ResourceEditorScene:
	DataLibrary.reset()
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)
	assert_eq(DataLibrary.save(DataLibrary.TYPE_PARTS, part), [] as Array[ValidationError])
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	scene.set_current_type(DataLibrary.TYPE_PARTS)
	return scene


func test_id_column_shrinks_below_the_shared_default_for_a_short_id() -> void:
	var part := Part.new()
	part.id = &"a"
	var scene: ResourceEditorScene = _scene_with_only(part)
	var id_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"id")

	assert_lt(scene.table.get_column_width(id_column), scene.COLUMN_MIN_WIDTH)

	_remove_dir_recursive(USER_ROOT)


## id must still fit its own widest actual value plus the header (at its
## widest possible sort-symbol form) — shrunk, not clipped — proven here
## against the real reference-humanoid pool, whose longest id
## (plate_large_sheet_steel) is itself wider than the shared default.
func test_id_column_still_fits_its_own_longest_value() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)
	var id_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(&"id")

	var font: Font = scene.table.get_theme_default_font()
	var font_size: int = scene.table.get_theme_default_font_size()
	var widest_value: float = 0.0
	for part: Part in DataLibrary.parts_pool():
		widest_value = maxf(
			widest_value,
			font.get_string_size(String(part.id), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)

	assert_true(scene.table.get_column_width(id_column) >= widest_value)


func test_display_name_column_is_at_least_the_floor_width_when_empty() -> void:
	var part := Part.new()
	part.id = &"a"
	var scene: ResourceEditorScene = _scene_with_only(part)
	var name_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(
		&"display_name"
	)

	assert_true(scene.table.get_column_width(name_column) >= scene.DISPLAY_NAME_MIN_WIDTH)

	_remove_dir_recursive(USER_ROOT)


## A type with no display_name column at all (materials) must not error.
func test_switching_to_a_type_with_no_display_name_column_is_safe() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	scene.set_current_type(DataLibrary.TYPE_MATERIALS)

	assert_false(ResourceEditorColumns.columns_for(DataLibrary.TYPE_MATERIALS).has(&"display_name"))
	assert_eq(
		scene.table.columns, ResourceEditorColumns.columns_for(DataLibrary.TYPE_MATERIALS).size()
	)


## A long display_name (once authored) widens the column past the floor
## to keep the whole name visible.
func test_a_long_display_name_widens_the_column_past_the_floor() -> void:
	var long_name := "A Deliberately Very Long Display Name For Width Testing"
	var part := Part.new()
	part.id = &"long_name_part"
	part.display_name = long_name
	var scene: ResourceEditorScene = _scene_with_only(part)
	var name_column: int = ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS).find(
		&"display_name"
	)
	var font: Font = scene.table.get_theme_default_font()
	var font_size: int = scene.table.get_theme_default_font_size()
	var name_width: float = (
		font.get_string_size(long_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	)

	assert_true(scene.table.get_column_width(name_column) > name_width)

	_remove_dir_recursive(USER_ROOT)
