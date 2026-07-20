class_name BotPreset
extends Resource

## docs/10 taskblock05 G5: "presets feed everything — the battle scene's
## squad setup, DeepStrike's pool, test fixtures. One format, one path."
## A thin, saveable snapshot of what the builder needs to reassemble a
## unit through BodyAssembler — template + loadout + pose, addressed by
## id (StringName), never a serialized Unit itself: assembling fresh from
## the same template+loadout every load is what "structurally identical"
## (the round-trip test) actually proves.

const PRESET_DIR := "user://presets"

@export var preset_name: String = ""
@export var template_id: StringName = ShellTemplates.DEFAULT_ID
@export var loadout: Loadout = Loadout.new()
@export var pose_id: StringName = &"IDLE"
## taskblock-14 Pass A1: organisation/display only, never inheritance — a
## variant is a full, standalone `BotPreset` (a real copy, produced by
## copying the base and editing the copy), not a diff over one. Editing
## the base does NOT propagate to a variant that happens to share its
## `profile_family`; that's an intended consequence at this scale, not a
## bug — a diff/override model is a later concern if bot counts explode.
## `&""` groups nothing; two presets share a family purely by both
## authoring the same StringName.
@export var profile_family: StringName = &""
## "" for the base profile of a family; "Battery Mods" etc. for a variant
## — display-only, never consulted by assembly.
@export var variant_label: String = ""
## taskblock-28 Pass B: what this preset's own units carry and how they
## self-arm at bout setup (`KitEquipper`) — null (the default) means "no
## kit," the unchanged pre-existing behavior every preset authored before
## this field existed keeps: already armed via `loadout` alone, nothing
## equips itself. Resolved as a step AFTER assembly, never inside
## `BodyAssembler` itself — `loadout` is structural fill, `kit` is what
## gets carried and then moved into place.
@export var kit: Kit = null


func _init(
	p_preset_name: String = "",
	p_template_id: StringName = ShellTemplates.DEFAULT_ID,
	p_loadout: Loadout = null,
	p_pose_id: StringName = &"IDLE",
	p_profile_family: StringName = &"",
	p_variant_label: String = "",
	p_kit: Kit = null
) -> void:
	preset_name = p_preset_name
	template_id = p_template_id
	loadout = p_loadout if p_loadout != null else Loadout.new()
	pose_id = p_pose_id
	profile_family = p_profile_family
	variant_label = p_variant_label
	kit = p_kit


static func _path_for(preset_name: String) -> String:
	return "%s/%s.tres" % [PRESET_DIR, preset_name]


## Free — it's already a Resource (docs/10 taskblock05 G5).
static func save(preset: BotPreset) -> Error:
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	return ResourceSaver.save(preset, _path_for(preset.preset_name))


static func load_preset(preset_name: String) -> BotPreset:
	var path: String = _path_for(preset_name)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as BotPreset


static func delete(preset_name: String) -> void:
	var dir: DirAccess = DirAccess.open(PRESET_DIR)
	if dir != null:
		dir.remove(preset_name + ".tres")


## Every saved preset's own name, for a UI dropdown to list.
static func list_names() -> Array[String]:
	var names: Array[String] = []
	var dir: DirAccess = DirAccess.open(PRESET_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			names.append(file_name.trim_suffix(".tres"))
		file_name = dir.get_next()
	return names
