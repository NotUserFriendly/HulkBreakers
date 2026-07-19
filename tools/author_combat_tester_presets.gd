extends SceneTree

## One-time authoring pass — writes the "Combat Tester" bot presets as
## `.tres` into `res://data/presets/`. Run once via
## `godot --headless -s res://tools/author_combat_tester_presets.gd`; kept
## afterward as a record, same convention as every `tools/author_*.gd`.
##
## "All body parts, cladding everywhere" is already what
## `ShellTemplates.DEFAULT_ID` (the reference humanoid) gives for free
## with an empty loadout — every Mount in `DeepStrike.
## reference_humanoid_template()` has cladding on it by default. This
## preset's own loadout only needs to override the three things that
## actually differ from that default: chest armor (wedge, taskblock-17
## E1), both legs' armor (half-cylinder, taskblock-17 E2, addressed via
## the `LEG_ARMOR` socket id `DeepStrike.reference_humanoid_pool()`
## carves out specifically so a loadout can target "both legs" without
## also hitting the arms' own bare `ARMOR` socket id), and one weapon per
## variant.


func _loadout(weapon_id: StringName) -> Loadout:
	return (
		Loadout
		. new(
			{
				&"ARMOR_FRONT": &"wedge_plate_torso",
				&"LEG_ARMOR": &"half_cylinder_plate",
				&"GRIP_R": weapon_id,
			}
		)
	)


func _preset(preset_name: String, weapon_id: StringName, variant_label: String) -> BotPreset:
	return BotPreset.new(
		preset_name,
		ShellTemplates.DEFAULT_ID,
		_loadout(weapon_id),
		&"IDLE",
		&"combat_tester",
		variant_label
	)


func _initialize() -> void:
	var dir: String = "res://data/presets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var presets: Array[BotPreset] = [
		_preset("combat_tester_chaingun", &"chaingun", "Chaingun"),
		_preset("combat_tester_sniper_rifle", &"sniper_rifle", "Sniper Rifle"),
		_preset("combat_tester_pump_shotgun", &"pump_shotgun", "Pump Shotgun"),
	]

	var count := 0
	for preset: BotPreset in presets:
		var path: String = "%s/%s.tres" % [dir, preset.preset_name]
		var err: Error = ResourceSaver.save(preset, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	print("Wrote %d presets." % count)
	quit()
