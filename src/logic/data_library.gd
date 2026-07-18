class_name DataLibrary
extends RefCounted

## taskblock-10 Pass B: "one registry, two sources, user wins." Built-in
## definitions ship under `res://data/<type>/`, read-only once exported;
## editor- and mod-authored `.tres` live under `user://data/<type>/` and
## OVERRIDE a matching id — the split a modder (or the Resource Editor,
## taskblock-11) needs with no further architecture. Nothing outside this
## file (and migration/test fixtures) may construct a definition directly
## — everything asks `DataLibrary`.

const BUILTIN_ROOT := "res://data"
const USER_ROOT := "user://data"

static var _parts: Dictionary = {}  # StringName -> Part
static var _ammo: Dictionary = {}  # StringName -> AmmoDef
static var _materials: Dictionary = {}  # StringName -> MaterialEntry
## Every row rejected by `DataValidator`, named (`ValidationError`) — a
## bad file is dropped from the registry, never left to vanish silently.
static var _errors: Array[ValidationError] = []
static var _loaded: bool = false


## Loads `res://data/` then `user://data/` (a matching id overrides the
## built-in), validating every row through `DataValidator` on the way in.
## `builtin_root`/`user_root` are overridable so tests can point this at
## fixture directories instead of the real game data.
static func load_all(builtin_root: String = BUILTIN_ROOT, user_root: String = USER_ROOT) -> void:
	# Set BEFORE loading: DataValidator's own cross-reference checks
	# (a part's `material`) call back into DataLibrary.get_material()
	# mid-load, and ensure_loaded() must not re-enter load_all().
	_loaded = true
	_parts.clear()
	_ammo.clear()
	_materials.clear()
	_errors.clear()
	# Materials first: Part validation cross-references material ids.
	_load_dir(builtin_root + "/materials", _materials)
	_load_dir(user_root + "/materials", _materials)
	_load_dir(builtin_root + "/parts", _parts)
	_load_dir(user_root + "/parts", _parts)
	_load_dir(builtin_root + "/ammo", _ammo)
	_load_dir(user_root + "/ammo", _ammo)


static func _load_dir(path: String, into: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			_load_file(path + "/" + file_name, file_name, into)
		file_name = dir.get_next()
	dir.list_dir_end()


static func _load_file(full_path: String, file_name: String, into: Dictionary) -> void:
	if not ResourceLoader.exists(full_path):
		_errors.append(ValidationError.new(StringName(file_name), &"resource", "failed to load"))
		return
	var resource: Resource = ResourceLoader.load(full_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		_errors.append(ValidationError.new(StringName(file_name), &"resource", "failed to load"))
		return
	var row_errors: Array[ValidationError] = DataValidator.validate(resource)
	if not row_errors.is_empty():
		_errors.append_array(row_errors)
		return
	into[resource.get("id")] = resource


static func _ensure_loaded() -> void:
	if not _loaded:
		load_all()


static func get_part(id: StringName) -> Part:
	_ensure_loaded()
	return _parts.get(id)


static func get_ammo(id: StringName) -> AmmoDef:
	_ensure_loaded()
	return _ammo.get(id)


static func get_material(id: StringName) -> MaterialEntry:
	_ensure_loaded()
	return _materials.get(id)


## Every loaded part template, for callers that used to read
## `DeepStrike.default_part_pool()`'s full array.
static func parts_pool() -> Array[Part]:
	_ensure_loaded()
	var pool: Array[Part] = []
	for part: Part in _parts.values():
		pool.append(part)
	return pool


## Every loaded material, aggregated into the shape callers that used to
## read `MaterialTable.default_table()` expect. The table-level curve
## endpoints (`retain_at_zero_bend` etc.) stay `MaterialTable`'s own
## defaults — pipeline tunables, not per-material rows.
static func material_table() -> MaterialTable:
	_ensure_loaded()
	var table := MaterialTable.new()
	for id: StringName in _materials:
		table.set_entry(id, _materials[id])
	return table


## Every row rejected on the last `load_all()` — named, never silent.
static func errors() -> Array[ValidationError]:
	return _errors


## Test-only: forces the next `get_part`/`get_ammo`/`get_material`/
## `parts_pool`/`material_table` call to reload from scratch, and drops
## whatever's currently cached. Production code never calls this — the
## registry is loaded once and stays put for the process's lifetime.
static func reset() -> void:
	_loaded = false
	_parts.clear()
	_ammo.clear()
	_materials.clear()
	_errors.clear()
