class_name SectionCatalog
extends RefCounted

## taskblock-54 Pass D: **every authored section on disk, by name** — the same shape
## `MapCatalog` has, deliberately.
##
## The taskblock asks to *"mirror that shape rather than inventing a second one"*, and the reason
## is the one this project keeps applying: two catalogues answering the same question in two ways
## is where they drift. Scanned on demand so `DebugVerbs.all()` picks up a section dropped into
## `data/sections/` with no code edit; sorted by **filename** so two machines offer the dropdown
## in the same order (a raw directory walk is filesystem-dependent).
##
## It is a separate class rather than a parameter on `MapCatalog` because the two return
## different resource types and a caller that asked for a map and got a section would find out at
## the point of use. One small duplicated scan is cheaper than that.

const SECTIONS_DIR := "res://data/sections"


## `[{"name": StringName, "path": String}]`, sorted by **file name**.
##
## Sorted by filename rather than by display name for the same reason `DataLibrary._load_dir`
## is: a raw `dir.get_next()` order is filesystem-dependent, so two machines could offer the
## same dropdown in different orders. Sorting on the thing that is stable on disk makes the
## order a pure function of the data.
##
## A map whose `section_name` is blank falls back to its filename — a nameless entry in a picker is
## worse than an ugly one, and silently skipping it would hide the file entirely.
static func entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(SECTIONS_DIR):
		return found
	var dir: DirAccess = DirAccess.open(SECTIONS_DIR)
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
		var path: String = "%s/%s" % [SECTIONS_DIR, name]
		var section := load(path) as SectionFile
		if section == null:
			continue
		var label: String = (
			section.section_name if section.section_name != "" else name.trim_suffix(".tres")
		)
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
