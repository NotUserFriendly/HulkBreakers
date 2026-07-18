extends SceneTree

## taskblock-14 Pass A1: one-time authoring pass — writes the starter bot
## profiles (a base + one variant, "enough to run a 2 Laborers vs 2
## Laborers w/ Battery Mods bout") as `.tres` into `res://data/presets/`,
## same convention as `tools/migrate_data.gd`/`tools/author_taskblock13_guns.gd`.
## Run once via `godot --headless -s res://tools/author_taskblock14_presets.gd`;
## kept afterward as a record.
##
## The variant is a full, standalone copy (A1: "not a diff over a base")
## — today it's mechanically identical to the base (no real "battery"
## part exists yet to actually differentiate it), distinguished only by
## `preset_name`/`variant_label`. That's expected: a designer edits the
## COPY once a real mechanical difference exists to author; this pass
## only proves the profile_family/variant grouping itself works.


func _initialize() -> void:
	var dir: String = "res://data/presets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var count := 0
	for preset: BotPreset in _presets():
		var path: String = "%s/%s.tres" % [dir, preset.preset_name]
		var err: Error = ResourceSaver.save(preset, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	print("Wrote %d presets." % count)
	quit()


func _presets() -> Array[BotPreset]:
	var base := BotPreset.new(
		"a_brand_laborer",
		ShellTemplates.DEFAULT_ID,
		DeepStrike.default_loadout(),
		&"IDLE",
		&"a_brand_laborer",
		""
	)

	var variant := BotPreset.new(
		"a_brand_laborer_battery_mods",
		ShellTemplates.DEFAULT_ID,
		DeepStrike.default_loadout(),
		&"IDLE",
		&"a_brand_laborer",
		"Battery Mods"
	)

	return [base, variant]
