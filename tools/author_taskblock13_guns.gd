extends SceneTree

## taskblock-13 Pass A: one-time authoring pass — writes the four
## placeholder guns (Chaingun, Pump Shotgun, Auto Shotgun, Sniper Rifle)
## from the taskblock's own reference table as `.tres` into
## `res://data/parts/`, same convention as `tools/migrate_data.gd`. Run
## once via `godot --headless -s res://tools/author_taskblock13_guns.gd`;
## kept afterward as a historical record of exactly what was authored and
## why, same posture as `migrate_data.gd` itself.
##
## Every field NOT named in the taskblock's own table (hp/mass/ap_cost/
## damage/crit_chance/weapon_max_range/scatter rings) is a flagged
## placeholder, loosely modeled on the archetype (chaingun = light per-
## round damage/high volume, shotgun = short range, sniper = high single-
## shot damage/long range) — not tuned balance. Ask before treating any of
## these as final.


func _initialize() -> void:
	var dir: String = "res://data/parts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var count := 0
	for part: Part in _guns():
		var path: String = "%s/%s.tres" % [dir, part.id]
		var err: Error = ResourceSaver.save(part, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	print("Wrote %d guns." % count)
	quit()


func _base_weapon(id: StringName, display_name: String) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.display_name = display_name
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.material = &"steel"
	return weapon


func _guns() -> Array[Part]:
	var chaingun: Part = _base_weapon(&"chaingun", "Chaingun")
	chaingun.hp = 6
	chaingun.max_hp = 6
	chaingun.mass = 8.0
	chaingun.volume = [Box.new(Vector3(0.0, 0.0, 0.4), Vector3(0.15, 0.15, 0.9))]
	chaingun.damage = 2.0
	chaingun.ap_cost = 2
	chaingun.weapon_max_range = 8.0
	chaingun.scatter = [Ring.new(0.15, 1.0), Ring.new(0.6, 2.0)]
	chaingun.provides_actions = [&"burst"]
	chaingun.weapon_def = WeaponDef.new()
	chaingun.weapon_def.damage_multiplier = 0.8
	chaingun.weapon_def.mechanical_accuracy = 0.8
	chaingun.weapon_def.barrel_length = 0.6
	chaingun.weapon_def.burst_size = 12
	chaingun.weapon_def.effective_range = 8.0
	chaingun.weapon_def.accepts_family = &"556x45"
	chaingun.weapon_def.max_case_length = 0.56

	var pump_shotgun: Part = _base_weapon(&"pump_shotgun", "Pump Shotgun")
	pump_shotgun.hp = 4
	pump_shotgun.max_hp = 4
	pump_shotgun.mass = 3.5
	pump_shotgun.volume = [Box.new(Vector3(0.0, 0.0, 0.3), Vector3(0.12, 0.15, 0.7))]
	pump_shotgun.damage = 3.0
	pump_shotgun.ap_cost = 1
	pump_shotgun.weapon_max_range = 4.0
	pump_shotgun.scatter = [Ring.new(0.1, 1.0)]
	pump_shotgun.provides_actions = [&"shoot"]
	pump_shotgun.weapon_def = WeaponDef.new()
	pump_shotgun.weapon_def.damage_multiplier = 1.0
	pump_shotgun.weapon_def.mechanical_accuracy = 0.85
	pump_shotgun.weapon_def.barrel_length = 0.5
	pump_shotgun.weapon_def.effective_range = 4.0
	pump_shotgun.weapon_def.accepts_family = &"12GA"
	pump_shotgun.weapon_def.max_case_length = 0.7

	var auto_shotgun: Part = _base_weapon(&"auto_shotgun", "Auto Shotgun")
	auto_shotgun.hp = 5
	auto_shotgun.max_hp = 5
	auto_shotgun.mass = 4.5
	auto_shotgun.volume = [Box.new(Vector3(0.0, 0.0, 0.3), Vector3(0.14, 0.16, 0.65))]
	auto_shotgun.damage = 3.0
	auto_shotgun.ap_cost = 1
	auto_shotgun.weapon_max_range = 4.0
	auto_shotgun.scatter = [Ring.new(0.1, 1.0)]
	auto_shotgun.provides_actions = [&"shoot", &"burst"]
	auto_shotgun.weapon_def = WeaponDef.new()
	auto_shotgun.weapon_def.damage_multiplier = 0.9
	auto_shotgun.weapon_def.mechanical_accuracy = 0.9
	auto_shotgun.weapon_def.barrel_length = 0.55
	auto_shotgun.weapon_def.burst_size = 3
	auto_shotgun.weapon_def.effective_range = 4.0
	auto_shotgun.weapon_def.accepts_family = &"12GA"
	auto_shotgun.weapon_def.max_case_length = 0.7

	var sniper_rifle: Part = _base_weapon(&"sniper_rifle", "Sniper Rifle")
	sniper_rifle.hp = 5
	sniper_rifle.max_hp = 5
	sniper_rifle.mass = 5.0
	sniper_rifle.volume = [Box.new(Vector3(0.0, 0.0, 0.5), Vector3(0.1, 0.12, 1.1))]
	sniper_rifle.damage = 10.0
	sniper_rifle.ap_cost = 2
	sniper_rifle.weapon_max_range = 20.0
	sniper_rifle.crit_chance = 0.2
	sniper_rifle.scatter = [Ring.new(0.03, 1.0)]
	sniper_rifle.provides_actions = [&"shoot"]
	sniper_rifle.weapon_def = WeaponDef.new()
	sniper_rifle.weapon_def.damage_multiplier = 1.1
	sniper_rifle.weapon_def.mechanical_accuracy = 0.95
	sniper_rifle.weapon_def.barrel_length = 1.1
	sniper_rifle.weapon_def.effective_range = 20.0
	sniper_rifle.weapon_def.accepts_family = &"762x51"
	sniper_rifle.weapon_def.max_case_length = 0.71

	return [chaingun, pump_shotgun, auto_shotgun, sniper_rifle]
