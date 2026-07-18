extends SceneTree

## taskblock-10 Pass C: one-time migration — walks
## DeepStrike.default_part_pool() and MaterialTable.default_table() and
## emits a `.tres` per definition into `res://data/parts/` and
## `res://data/materials/`, reproducing today's hardcoded game exactly so
## it can diverge from there. Run once via
## `godot --headless -s res://tools/migrate_data.gd`; the hardcoded
## generators it reads from are deleted in the same pass that lands this
## tool's output, so re-running it after that point has nothing left to
## walk.


func _initialize() -> void:
	var parts_written: int = _migrate_parts()
	var materials_written: int = _migrate_materials()
	print("Wrote %d parts, %d materials." % [parts_written, materials_written])
	quit()


func _migrate_parts() -> int:
	var dir: String = "res://data/parts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var count: int = 0
	for part: Part in DeepStrike.default_part_pool():
		var path: String = "%s/%s.tres" % [dir, part.id]
		var err: Error = ResourceSaver.save(part, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	return count


func _migrate_materials() -> int:
	var dir: String = "res://data/materials"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var table: MaterialTable = MaterialTable.default_table()
	var count: int = 0
	for id: StringName in table.entries:
		var entry: MaterialEntry = table.entries[id]
		entry.id = id
		var path: String = "%s/%s.tres" % [dir, id]
		var err: Error = ResourceSaver.save(entry, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	return count
