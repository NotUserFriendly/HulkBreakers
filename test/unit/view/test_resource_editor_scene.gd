extends GutTest

## taskblock-11 Pass A: "a separate scene, its own process." Real
## `res://data`/`user://data` (this is a launched TOOL, not a fixture-root
## test) — reset before/after so a prior test's isolated roots never leak
## in, and this test's own real-data reads never leak out.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## TEST: "the editor loads via DataLibrary."
func test_ready_loads_data_via_data_library() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	assert_eq(scene.current_type, DataLibrary.TYPE_PARTS)
	var rows: Dictionary = scene.load_data()
	assert_true(rows.has(&"torso"), "the real reference-humanoid pool must be reachable")


func test_set_current_type_switches_which_definitions_load() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	scene.set_current_type(DataLibrary.TYPE_AMMO)
	var rows: Dictionary = scene.load_data()
	assert_true(rows.has(&"9mm_fmj"))
	assert_false(rows.has(&"torso"))


## TEST: "saving writes a valid `.tres` to `user://data/`; a saved file
## reloads identically."
func test_save_resource_round_trips_through_data_library() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	var part := Part.new()
	part.id = &"editor_test_part"
	part.hp = 9
	part.max_hp = 9

	var errors: Array[ValidationError] = scene.save_resource(part)
	assert_eq(errors, [] as Array[ValidationError])
	assert_eq(DataLibrary.get_part(&"editor_test_part").hp, 9)
	assert_eq(DataLibrary.source_of(DataLibrary.TYPE_PARTS, &"editor_test_part"), &"user")

	var path: String = DataLibrary.USER_ROOT + "/parts/editor_test_part.tres"
	assert_true(ResourceLoader.exists(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_save_resource_rejects_an_invalid_definition() -> void:
	var scene := ResourceEditorScene.new()
	add_child_autofree(scene)

	var part := Part.new()
	part.id = &"editor_test_bad_part"
	part.failure_mode = &"NOT_A_REAL_MODE"

	var errors: Array[ValidationError] = scene.save_resource(part)
	assert_eq(errors.size(), 1)
	assert_eq(errors[0].field, &"failure_mode")
	assert_null(DataLibrary.get_part(&"editor_test_bad_part"))


## TEST: "the editor never calls `EditorInterface` or any editor-only
## API" — the tripwire that would make this a non-shipping plugin.
func test_the_editor_never_touches_editor_only_apis() -> void:
	var offending: Array[String] = []
	_scan_dir("res://src/resource_editor", offending)
	assert_eq(offending, [] as Array[String])


func _scan_dir(path: String, offending: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full_path, offending)
		elif entry.ends_with(".gd"):
			# Code usage only — this file's own doc comments legitimately
			# NAME EditorPlugin/EditorInterface while explaining why
			# neither is used, which a bare substring match can't tell
			# apart from an actual call.
			for line: String in FileAccess.get_file_as_string(full_path).split("\n"):
				var code: String = line.split("#")[0]
				if code.contains("EditorInterface") or code.contains("EditorPlugin"):
					offending.append(full_path)
					break
		entry = dir.get_next()
	dir.list_dir_end()
