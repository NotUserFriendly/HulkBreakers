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


func _init(
	p_preset_name: String = "",
	p_template_id: StringName = ShellTemplates.DEFAULT_ID,
	p_loadout: Loadout = null,
	p_pose_id: StringName = &"IDLE"
) -> void:
	preset_name = p_preset_name
	template_id = p_template_id
	loadout = p_loadout if p_loadout != null else Loadout.new()
	pose_id = p_pose_id


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
