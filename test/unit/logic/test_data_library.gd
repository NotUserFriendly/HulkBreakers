extends GutTest

## taskblock-10 Pass B: "one registry, two sources, user wins." Both roots
## point at throwaway `user://` directories (never the real
## `res://data`/`user://data` the game itself reads) so this test proves
## the override CONTRACT without touching real game data or the
## filesystem-write restrictions `res://` carries at export time.

const BUILTIN_ROOT := "user://test_data_library_builtin"
const USER_ROOT := "user://test_data_library_user"


func before_each() -> void:
	DataLibrary.reset()


func after_each() -> void:
	DataLibrary.reset()
	_remove_dir_recursive(BUILTIN_ROOT)
	_remove_dir_recursive(USER_ROOT)


func _remove_dir_recursive(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	var dir: DirAccess = DirAccess.open(absolute)
	if dir == null:
		return
	for sub: String in ["parts", "ammo", "materials"]:
		var sub_dir: DirAccess = DirAccess.open(absolute + "/" + sub)
		if sub_dir == null:
			continue
		sub_dir.list_dir_begin()
		var file_name: String = sub_dir.get_next()
		while file_name != "":
			if not sub_dir.current_is_dir():
				sub_dir.remove(file_name)
			file_name = sub_dir.get_next()
		sub_dir.list_dir_end()
		DirAccess.remove_absolute(absolute + "/" + sub)
	DirAccess.remove_absolute(absolute)


func _save_part(root: String, id: StringName, hp: int) -> void:
	var dir: String = root + "/parts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var part := Part.new()
	part.id = id
	part.hp = hp
	part.max_hp = hp
	assert_eq(ResourceSaver.save(part, dir + "/" + String(id) + ".tres"), OK)


func _save_invalid_part(root: String, file_name: String) -> void:
	var dir: String = root + "/parts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var part := Part.new()
	part.id = &"bad_part"
	part.failure_mode = &"NOT_A_REAL_MODE"
	assert_eq(ResourceSaver.save(part, dir + "/" + file_name), OK)


## TEST: "a built-in part loads."
func test_a_builtin_part_loads() -> void:
	_save_part(BUILTIN_ROOT, &"torso", 12)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	var loaded: Part = DataLibrary.get_part(&"torso")
	assert_not_null(loaded)
	assert_eq(loaded.hp, 12)


## TEST: "a user:// file with the same id overrides it."
func test_a_user_file_with_the_same_id_overrides_the_builtin() -> void:
	_save_part(BUILTIN_ROOT, &"torso", 12)
	_save_part(USER_ROOT, &"torso", 999)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	assert_eq(DataLibrary.get_part(&"torso").hp, 999)


## TEST: "a user://-only id loads."
func test_a_user_only_id_loads() -> void:
	_save_part(USER_ROOT, &"scrap_pistol", 3)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	var loaded: Part = DataLibrary.get_part(&"scrap_pistol")
	assert_not_null(loaded)
	assert_eq(loaded.hp, 3)


## TEST: "an invalid file is rejected by name and does not silently
## vanish."
func test_an_invalid_file_is_rejected_by_name_not_silently_dropped() -> void:
	_save_invalid_part(BUILTIN_ROOT, "bad_part.tres")
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	assert_null(DataLibrary.get_part(&"bad_part"))
	var errors: Array[ValidationError] = DataLibrary.errors()
	assert_eq(errors.size(), 1)
	assert_eq(errors[0].resource_id, &"bad_part")
	assert_eq(errors[0].field, &"failure_mode")


## TEST: "DataLibrary is the only source of definitions" — a lookup for
## an id nobody authored comes back null, never a crash or a fabricated
## default.
func test_an_unknown_id_returns_null_not_a_crash() -> void:
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)
	assert_null(DataLibrary.get_part(&"does_not_exist"))
	assert_null(DataLibrary.get_ammo(&"does_not_exist"))
	assert_null(DataLibrary.get_material(&"does_not_exist"))


func test_parts_pool_returns_every_loaded_part() -> void:
	_save_part(BUILTIN_ROOT, &"torso", 12)
	_save_part(BUILTIN_ROOT, &"head", 6)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	var pool: Array[Part] = DataLibrary.parts_pool()
	assert_eq(pool.size(), 2)


func test_material_table_aggregates_every_loaded_material() -> void:
	var dir: String = BUILTIN_ROOT + "/materials"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var steel := MaterialEntry.new(6.0, 30.0, Color("#8C949C"))
	steel.id = &"steel"
	assert_eq(ResourceSaver.save(steel, dir + "/steel.tres"), OK)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	var table: MaterialTable = DataLibrary.material_table()
	assert_eq(table.get_entry(&"steel").dt, 6.0)


## taskblock-11 Pass A: the type-agnostic entry point the editor's table
## switches over.
func test_resources_of_type_returns_every_loaded_definition_of_that_type() -> void:
	_save_part(BUILTIN_ROOT, &"torso", 12)
	_save_part(BUILTIN_ROOT, &"head", 6)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	var parts: Dictionary = DataLibrary.resources_of_type(DataLibrary.TYPE_PARTS)
	assert_eq(parts.size(), 2)
	assert_true(parts.has(&"torso"))
	assert_eq((parts[&"torso"] as Part).hp, 12)


func test_resources_of_type_returns_fresh_duplicates() -> void:
	_save_part(BUILTIN_ROOT, &"torso", 12)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	var first: Dictionary = DataLibrary.resources_of_type(DataLibrary.TYPE_PARTS)
	(first[&"torso"] as Part).hp = 999
	var second: Dictionary = DataLibrary.resources_of_type(DataLibrary.TYPE_PARTS)
	assert_eq((second[&"torso"] as Part).hp, 12, "mutating one caller's copy must not leak")


## taskblock-11 B2: "source (res:// built-in vs user:// override)."
func test_source_of_reports_builtin_and_user_and_override_correctly() -> void:
	_save_part(BUILTIN_ROOT, &"torso", 12)
	_save_part(USER_ROOT, &"scrap_pistol", 3)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	assert_eq(DataLibrary.source_of(DataLibrary.TYPE_PARTS, &"torso"), &"builtin")
	assert_eq(DataLibrary.source_of(DataLibrary.TYPE_PARTS, &"scrap_pistol"), &"user")
	assert_eq(DataLibrary.source_of(DataLibrary.TYPE_PARTS, &"does_not_exist"), &"")


func test_source_of_an_overridden_id_reports_user() -> void:
	_save_part(BUILTIN_ROOT, &"torso", 12)
	_save_part(USER_ROOT, &"torso", 999)
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)

	assert_eq(DataLibrary.source_of(DataLibrary.TYPE_PARTS, &"torso"), &"user")


## TEST: "saving writes a valid .tres to user://data/; a saved file
## reloads identically."
func test_save_writes_a_valid_tres_to_the_user_root() -> void:
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)
	var part := Part.new()
	part.id = &"custom_plate"
	part.hp = 7
	part.max_hp = 7

	var errors: Array[ValidationError] = DataLibrary.save(DataLibrary.TYPE_PARTS, part)
	assert_eq(errors, [] as Array[ValidationError])

	var path: String = USER_ROOT + "/parts/custom_plate.tres"
	assert_true(ResourceLoader.exists(path))
	var reloaded: Part = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(reloaded.id, &"custom_plate")
	assert_eq(reloaded.hp, 7)

	assert_eq(DataLibrary.get_part(&"custom_plate").hp, 7, "the in-memory registry must see it too")
	assert_eq(DataLibrary.source_of(DataLibrary.TYPE_PARTS, &"custom_plate"), &"user")


func test_save_rejects_an_invalid_resource_without_writing_a_file() -> void:
	DataLibrary.load_all(BUILTIN_ROOT, USER_ROOT)
	var part := Part.new()
	part.id = &"bad_plate"
	part.failure_mode = &"NOT_A_REAL_MODE"

	var errors: Array[ValidationError] = DataLibrary.save(DataLibrary.TYPE_PARTS, part)
	assert_eq(errors.size(), 1)
	assert_eq(errors[0].field, &"failure_mode")
	assert_false(ResourceLoader.exists(USER_ROOT + "/parts/bad_plate.tres"))
	assert_null(DataLibrary.get_part(&"bad_plate"))
