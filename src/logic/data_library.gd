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

## taskblock-11 Pass A: the generic type-key vocabulary the Resource
## Editor switches over — open StringNames, not an enum (CLAUDE.md: a new
## definition TYPE is still a code change, same as today, but nothing
## about the editor's own table/save code needs one).
const TYPE_PARTS := &"parts"
const TYPE_AMMO := &"ammo"
const TYPE_MATERIALS := &"materials"
## taskblock-14 Pass A1: reference bot profiles as real, shipped content
## — distinct from `BotPreset.save`/`load_preset` (`user://presets/`, the
## player's own builder-authored saves, untouched by this). A `.tres`
## under `res://data/presets/` (or a `user://data/presets/` override) is
## a designer-authored profile a bout can spawn, addressed by
## `BotPreset.preset_name` the same way every other type is addressed by
## `id` — `resource.get("id")` below reads `preset_name` for this type
## only (see `_load_file`'s own id lookup).
const TYPE_PRESETS := &"presets"

static var _parts: Dictionary = {}  # StringName -> Part
static var _ammo: Dictionary = {}  # StringName -> AmmoDef
static var _materials: Dictionary = {}  # StringName -> MaterialEntry
static var _presets: Dictionary = {}  # StringName -> BotPreset
## "type:id" -> &"builtin" | &"user" (taskblock-11 B2: "source (res://
## built-in vs user:// override)"). Not derivable from `_parts`/`_ammo`/
## `_materials` alone once a `user://` row has overridden a built-in one
## — both share the same in-memory slot by then.
static var _sources: Dictionary = {}
## Every row rejected by `DataValidator`, named (`ValidationError`) — a
## bad file is dropped from the registry, never left to vanish silently.
static var _errors: Array[ValidationError] = []
static var _loaded: bool = false
## The `user_root` the last `load_all()` was actually called with —
## `save()` must write into THIS root, never the bare `USER_ROOT`
## constant, or a test (or any future non-default caller) pointed at a
## fixture root would have its saves silently escape to the real
## `user://data/`.
static var _active_user_root: String = USER_ROOT


## Loads `res://data/` then `user://data/` (a matching id overrides the
## built-in), validating every row through `DataValidator` on the way in.
## `builtin_root`/`user_root` are overridable so tests can point this at
## fixture directories instead of the real game data.
static func load_all(builtin_root: String = BUILTIN_ROOT, user_root: String = USER_ROOT) -> void:
	# Set BEFORE loading: DataValidator's own cross-reference checks
	# (a part's `material`) call back into DataLibrary.get_material()
	# mid-load, and ensure_loaded() must not re-enter load_all().
	_loaded = true
	_active_user_root = user_root
	_parts.clear()
	_ammo.clear()
	_materials.clear()
	_presets.clear()
	_sources.clear()
	_errors.clear()
	# Materials first: Part validation cross-references material ids.
	_load_dir(builtin_root + "/materials", _materials, TYPE_MATERIALS, &"builtin")
	_load_dir(user_root + "/materials", _materials, TYPE_MATERIALS, &"user")
	_load_dir(builtin_root + "/parts", _parts, TYPE_PARTS, &"builtin")
	_load_dir(user_root + "/parts", _parts, TYPE_PARTS, &"user")
	_load_dir(builtin_root + "/ammo", _ammo, TYPE_AMMO, &"builtin")
	_load_dir(user_root + "/ammo", _ammo, TYPE_AMMO, &"user")
	_load_dir(builtin_root + "/presets", _presets, TYPE_PRESETS, &"builtin")
	_load_dir(user_root + "/presets", _presets, TYPE_PRESETS, &"user")


## docs/00 (determinism: "same seed = same battle, always"): a raw
## `dir.get_next()` walk order is filesystem-dependent, not
## content-derived — the same `.tres` set could load in a different
## order on a different machine and shift every downstream RNG draw that
## consumes `parts_pool()` (`DeepStrike.assemble_random`'s candidate
## lists included). Sorted alphabetically by filename so load order is a
## pure function of the data itself.
static func _load_dir(
	path: String, into: Dictionary, type_key: StringName, source: StringName
) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()
	for sorted_name: String in file_names:
		_load_file(path + "/" + sorted_name, sorted_name, into, type_key, source)


static func _load_file(
	full_path: String, file_name: String, into: Dictionary, type_key: StringName, source: StringName
) -> void:
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
	# BotPreset predates this pipeline and keys itself by `preset_name`
	# (String — it doubles as the `user://presets/` save filename), never
	# `id` (StringName) like every other type here — the one exception to
	# an otherwise-uniform id lookup.
	var id: StringName = (
		StringName(resource.preset_name) if resource is BotPreset else resource.get("id")
	)
	into[id] = resource
	_sources["%s:%s" % [type_key, id]] = source


static func _ensure_loaded() -> void:
	if not _loaded:
		load_all()


## A fresh duplicate every call — `_parts` holds the one canonical
## instance per id (loaded once), but every existing pool convention
## (`assemble_random`, `reference_humanoid_pool`, ...) already assumes a
## pool draw is safe to mutate independently, the same guarantee
## `DeepStrike.default_part_pool()` gave by building brand-new instances
## on every call. Returning the cached instance directly would let one
## caller's mutation bleed into every other caller/test sharing the same
## process.
static func get_part(id: StringName) -> Part:
	_ensure_loaded()
	var part: Part = _parts.get(id)
	return part.duplicate(true) if part != null else null


static func get_ammo(id: StringName) -> AmmoDef:
	_ensure_loaded()
	var ammo: AmmoDef = _ammo.get(id)
	return ammo.duplicate(true) if ammo != null else null


static func get_material(id: StringName) -> MaterialEntry:
	_ensure_loaded()
	var material: MaterialEntry = _materials.get(id)
	return material.duplicate(true) if material != null else null


static func get_preset(id: StringName) -> BotPreset:
	_ensure_loaded()
	var preset: BotPreset = _presets.get(id)
	return preset.duplicate(true) if preset != null else null


## Every loaded reference profile — for a bout-setup menu's own dropdown
## (taskblock-14 Pass D), grouped by `profile_family` client-side.
static func presets_pool() -> Array[BotPreset]:
	_ensure_loaded()
	var pool: Array[BotPreset] = []
	for preset: BotPreset in _presets.values():
		pool.append(preset.duplicate(true))
	return pool


## Every loaded part template, for callers that used to read
## `DeepStrike.default_part_pool()`'s full array — fresh duplicates, same
## reasoning as `get_part`.
static func parts_pool() -> Array[Part]:
	_ensure_loaded()
	var pool: Array[Part] = []
	for part: Part in _parts.values():
		pool.append(part.duplicate(true))
	return pool


## Every loaded material, aggregated into the shape callers that used to
## read `MaterialTable.default_table()` expect. The table-level curve
## endpoints (`retain_at_zero_bend` etc.) stay `MaterialTable`'s own
## defaults — pipeline tunables, not per-material rows. Fresh duplicates,
## same reasoning as `get_part`.
static func material_table() -> MaterialTable:
	_ensure_loaded()
	var table := MaterialTable.new()
	for id: StringName in _materials:
		table.set_entry(id, (_materials[id] as MaterialEntry).duplicate(true))
	return table


## Every row rejected on the last `load_all()` — named, never silent.
static func errors() -> Array[ValidationError]:
	return _errors


## taskblock-11 Pass A: the Resource Editor's own generic entry point —
## every loaded definition of one type, fresh duplicates, id -> resource.
## `get_part`/`get_ammo`/`get_material`/`parts_pool`/`material_table`
## stay as the typed convenience callers already use; this is the
## type-agnostic one a table that switches between parts/ammo/materials
## needs.
static func resources_of_type(type_key: StringName) -> Dictionary:
	_ensure_loaded()
	var source: Dictionary = _dict_for(type_key)
	var result: Dictionary = {}
	for id: StringName in source:
		result[id] = (source[id] as Resource).duplicate(true)
	return result


## &"builtin" | &"user" | &"" (unknown id). taskblock-11 B2: "source
## (res:// built-in vs user:// override)."
static func source_of(type_key: StringName, id: StringName) -> StringName:
	_ensure_loaded()
	return _sources.get("%s:%s" % [type_key, id], &"")


## taskblock-11 Pass A: "saving writes a valid .tres to user://data/."
## Validated through the SAME `DataValidator` `load_all()` uses — an
## invalid resource is rejected with its named errors and nothing is
## written, never a broken file on disk. A successful save updates the
## in-memory registry too (so the editor's own next read sees it — the
## GAME picking it up is still next-boot-only, `_loaded` isn't reset).
static func save(type_key: StringName, resource: Resource) -> Array[ValidationError]:
	var validation_errors: Array[ValidationError] = DataValidator.validate(resource)
	if not validation_errors.is_empty():
		return validation_errors
	var type_dir: String = _dir_name_for(type_key)
	var id: StringName = (
		StringName(resource.preset_name) if resource is BotPreset else resource.get("id")
	)
	if type_dir == "":
		return [ValidationError.new(id, &"type", "unknown definition type")]
	_ensure_loaded()
	var dir: String = _active_user_root + "/" + type_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path: String = "%s/%s.tres" % [dir, id]
	var err: Error = ResourceSaver.save(resource, path)
	if err != OK:
		return [ValidationError.new(id, &"resource", "failed to save: error %d" % err)]
	_dict_for(type_key)[id] = resource
	_sources["%s:%s" % [type_key, id]] = &"user"
	return []


static func _dict_for(type_key: StringName) -> Dictionary:
	match type_key:
		TYPE_PARTS:
			return _parts
		TYPE_AMMO:
			return _ammo
		TYPE_MATERIALS:
			return _materials
		TYPE_PRESETS:
			return _presets
		_:
			return {}


static func _dir_name_for(type_key: StringName) -> String:
	match type_key:
		TYPE_PARTS:
			return "parts"
		TYPE_AMMO:
			return "ammo"
		TYPE_MATERIALS:
			return "materials"
		TYPE_PRESETS:
			return "presets"
		_:
			return ""


## Test-only: forces the next `get_part`/`get_ammo`/`get_material`/
## `parts_pool`/`material_table` call to reload from scratch, and drops
## whatever's currently cached. Production code never calls this — the
## registry is loaded once and stays put for the process's lifetime.
static func reset() -> void:
	_loaded = false
	_active_user_root = USER_ROOT
	_parts.clear()
	_ammo.clear()
	_materials.clear()
	_presets.clear()
	_sources.clear()
	_errors.clear()
