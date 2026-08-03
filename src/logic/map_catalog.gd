class_name MapCatalog
extends RefCounted

## taskblock-53: **every authored map on disk, by name.** The debug panel's map loader used a
## typed text box, which meant knowing a `res://` path by heart before you could load anything.
##
## ## Why this is not a `DataLibrary` pool
##
## `DataLibrary._load_dir` keys everything it loads on the resource's own `id` `StringName`.
## A `MapFile` has a human `map_name` and no `id`, because a map is named for a person to pick
## it out of a list rather than for code to look it up — so it would have to grow a second
## identifier purely to fit the loader. A directory scan is what this actually needs.
##
## ## Scanned on demand, which is what makes the dropdown auto-populate
##
## `DebugVerbs.all()` rebuilds its spec list every time the panel is opened, so a map dropped
## into `data/maps/` appears the next time you open the panel — **no code edit to add a map**,
## which is the same rule `docs/PLAN.md` applies to socket types and profiles. The cost is one
## directory listing per panel build, never per frame.

const MAPS_DIR := "res://data/maps"


## `[{"name": StringName, "path": String}]`, sorted by **file name**.
##
## Sorted by filename rather than by display name for the same reason `DataLibrary._load_dir`
## is: a raw `dir.get_next()` order is filesystem-dependent, so two machines could offer the
## same dropdown in different orders. Sorting on the thing that is stable on disk makes the
## order a pure function of the data.
##
## A map whose `map_name` is blank falls back to its filename — a nameless entry in a picker is
## worse than an ugly one, and silently skipping it would hide the file entirely.
static func entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		return found
	var dir: DirAccess = DirAccess.open(MAPS_DIR)
	if dir == null:
		return found

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# `.tres` files are exported as `.tres.remap` in a release build; `trim_suffix` on the
		# import suffix is how the rest of this codebase spells "the authored name".
		var authored: String = file_name.trim_suffix(".remap")
		if authored.ends_with(".tres") and not file_names.has(authored):
			file_names.append(authored)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()

	for name: String in file_names:
		var path: String = "%s/%s" % [MAPS_DIR, name]
		var map := load(path) as MapFile
		if map == null:
			continue
		var label: String = map.map_name if map.map_name != "" else name.trim_suffix(".tres")
		found.append({"name": StringName(label), "path": path})
	return found


## Just the names, for a dropdown's own option list.
static func names() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Dictionary in entries():
		out.append(entry["name"])
	return out


## The `res://` path a display name stands for, or `""` if nothing on disk carries it.
##
## **Two maps sharing a name resolve to the first by filename order.** That is a content
## problem an author can see in the dropdown, not something to fail a load over — and picking
## deterministically is what stops it behaving differently on two machines.
static func path_for(name: StringName) -> String:
	for entry: Dictionary in entries():
		if entry["name"] == name:
			return entry["path"]
	return ""
