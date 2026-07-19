extends SceneTree

## taskblock-19 Pass C: one-time authoring pass — the four real guns
## (`tools/author_taskblock13_guns.gd`) had `Part.weapon_max_range` and
## `WeaponDef.effective_range` authored to the SAME number (the exact dead-
## field duplication this pass exists to fix). `weapon_max_range` is gone;
## this loads each gun, keeps its `effective_range` as-is (that WAS the
## real, used legality cutoff before this pass), and adds a genuinely
## wider `max_range` (a degraded-accuracy band beyond it) plus, for the
## sniper only, a `min_range` (a marksman weapon that refuses a point-
## blank shot). Flagged placeholders — no balance numbers were specified
## beyond "wider than effective," ask before tuning. Run once via
## `godot --headless -s res://tools/author_taskblock19_ranges.gd`; kept
## afterward as a historical record, same posture as every other
## `tools/author_*.gd` one-time pass.

const RANGES := {
	&"chaingun": {"max_range": 12.0, "min_range": 0.0},
	&"pump_shotgun": {"max_range": 6.0, "min_range": 0.0},
	&"auto_shotgun": {"max_range": 6.0, "min_range": 0.0},
	&"sniper_rifle": {"max_range": 30.0, "min_range": 3.0},
}


func _initialize() -> void:
	var count := 0
	for id: StringName in RANGES.keys():
		var path: String = "res://data/parts/%s.tres" % id
		var part: Part = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if part == null or part.weapon_def == null:
			push_error("Failed to load gun with a WeaponDef: %s" % path)
			continue
		part.weapon_def.max_range = RANGES[id]["max_range"]
		part.weapon_def.min_range = RANGES[id]["min_range"]
		var err: Error = ResourceSaver.save(part, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	print("Updated ranges on %d guns." % count)
	quit()
