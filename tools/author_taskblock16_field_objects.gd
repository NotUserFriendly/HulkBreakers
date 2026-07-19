extends SceneTree

## taskblock-16 Pass B: one-time authoring pass — writes every field-object
## Part as `.tres` into `res://data/parts/`, same convention as
## `tools/migrate_data.gd`/`tools/author_taskblock13_guns.gd`. Run once via
## `godot --headless -s res://tools/author_taskblock16_field_objects.gd`;
## kept afterward as a record.
##
## The first five are a straight migration of `field_objects.gd`'s own
## hardcoded factories (now deleted) — same ids, same fields, unchanged.
## The last three (`pillar`, `forklift`, `barrel_pallet`) are new: the
## missing covers taskblock-04 specced but this codebase never built.
## Every hp/mass/salvage_yield number below is a flagged placeholder
## (CLAUDE.md: never invent balance numbers and present them as design),
## loosely matched to the existing five's own scale.


func _initialize() -> void:
	var dir: String = "res://data/parts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var count := 0
	for part: Part in _field_objects():
		var path: String = "%s/%s.tres" % [dir, part.id]
		var err: Error = ResourceSaver.save(part, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	print("Wrote %d field objects." % count)
	quit()


func _field_objects() -> Array[Part]:
	return [
		_scrap_pile(),
		_goo_barrel(),
		_crate(),
		_twisted_sheet_metal(),
		_metal_scraps(),
		_pillar(),
		_forklift(),
		_barrel_pallet(),
	]


func _scrap_pile() -> Part:
	var part := Part.new()
	part.id = &"scrap_pile"
	part.display_name = "Scrap Pile"
	part.material = &"steel"
	part.hp = 6
	part.max_hp = 6
	part.volume = [Box.new(Vector3(0.0, 0.4, 0.0), Vector3(0.9, 0.8, 0.9))]
	part.salvage_yield = {&"metals": 4}
	return part


## docs/03/taskblock-09 A3: failure_mode == DETONATE ("cook-off") is the
## entire "explodes on failure" mechanic, already built. `attaches_to`
## (new for taskblock-16 Pass B) is what lets a barrel plug into
## `barrel_pallet`'s own BARREL_SLOT sockets — it never had one before
## because nothing ever attached it to anything.
func _goo_barrel() -> Part:
	var part := Part.new()
	part.id = &"goo_barrel"
	part.display_name = "Goo Barrel"
	part.attaches_to = [&"BARREL_SLOT"]
	part.material = &"reactive"
	part.hp = 3
	part.max_hp = 3
	part.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.5, 1.0, 0.5))]
	part.render_primitive = &"CYLINDER"
	part.render_scale = Vector3(0.5, 1.0, 0.5)
	part.tags = [&"VOLATILE"]
	part.failure_mode = &"DETONATE"
	part.detonate_damage = 12.0
	part.detonate_radius = 2.0
	part.salvage_yield = {&"reactives": 2}
	return part


func _crate() -> Part:
	var part := Part.new()
	part.id = &"crate"
	part.display_name = "Crate"
	part.material = &"hull_plate"
	part.hp = 3
	part.max_hp = 3
	part.volume = [Box.new(Vector3(0.0, 0.35, 0.0), Vector3(0.7, 0.7, 0.7))]
	part.salvage_yield = {&"organics": 3}
	return part


func _twisted_sheet_metal() -> Part:
	var part := Part.new()
	part.id = &"twisted_sheet_metal"
	part.display_name = "Twisted Sheet Metal"
	part.material = &"sheet_steel"
	part.hp = 1
	part.max_hp = 1
	part.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.1))]
	part.salvage_yield = {&"metals": 2}
	return part


func _metal_scraps() -> Part:
	var part := Part.new()
	part.id = &"metal_scraps"
	part.display_name = "Metal Scraps"
	part.material = &"steel"
	part.hp = 1
	part.max_hp = 1
	part.volume = [Box.new(Vector3.ZERO, Vector3(0.25, 0.25, 0.1))]
	part.salvage_yield = {&"metals": 3}
	return part


## taskblock-16 B1: "the plain non-interactable cover — tall, masks
## torso, just blocks." Taller than map_gen's own old FULL_COVER_HEIGHT
## (1.60) so it masks torso AND head, the tallest cover in the set —
## height (not a scalar) is what gives it "full cover" now.
func _pillar() -> Part:
	var part := Part.new()
	part.id = &"pillar"
	part.display_name = "Steel Pillar"
	part.material = &"steel"
	part.hp = 10
	part.max_hp = 10
	part.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.8, 0.6))]
	part.salvage_yield = {&"metals": 5}
	return part


## taskblock-16 B1: "a shell with no matrix docked, carrying a
## battery/POWER socket — cover that's also a lootable/usable object.
## Special actions still a flagged seam; the socket is what's specced."
## No MATRIX socket at all (Part.hosts_matrix() reads sockets directly —
## simply never declaring one is the whole mechanism, no extra flag).
## The POWER socket starts empty, same convention every weapon GRIP/
## armor ARMOR socket on a fresh template already follows — occupying it
## with a real battery part is a real follow-up, not invented here.
func _forklift() -> Part:
	var part := Part.new()
	part.id = &"forklift"
	part.display_name = "Forklift"
	part.material = &"steel"
	part.hp = 8
	part.max_hp = 8
	part.volume = [Box.new(Vector3(0.0, 0.55, 0.0), Vector3(0.9, 1.1, 1.4))]
	part.sockets = [Socket.new(&"POWER", Transform3D.IDENTITY, &"battery")]
	part.salvage_yield = {&"metals": 6}
	return part


## taskblock-16 B1: "generates with 0-4 goo_barrels on it (seeded) — a
## container-ish cover whose contents vary." Four pre-declared, empty
## BARREL_SLOT sockets (never `contents` — `BodyProjector` only ever
## walks `sockets`, taskblock-16's own research: an item in `contents` is
## invisible to the shot plane and could never be shot/cooked-off).
## MapGen (Pass B/C) rolls 0-4 and calls `PartGraph.attach` at placement
## time — this template ships empty, same "attachment happens at
## assembly/generation time in code" convention every socketed template
## in this codebase already follows.
func _barrel_pallet() -> Part:
	var part := Part.new()
	part.id = &"barrel_pallet"
	part.display_name = "Barrel Pallet"
	part.material = &"hull_plate"
	part.hp = 5
	part.max_hp = 5
	part.volume = [Box.new(Vector3(0.0, 0.15, 0.0), Vector3(1.0, 0.3, 1.0))]
	part.sockets = [
		Socket.new(&"BARREL_SLOT", Transform3D.IDENTITY, &"slot_0"),
		Socket.new(&"BARREL_SLOT", Transform3D.IDENTITY, &"slot_1"),
		Socket.new(&"BARREL_SLOT", Transform3D.IDENTITY, &"slot_2"),
		Socket.new(&"BARREL_SLOT", Transform3D.IDENTITY, &"slot_3"),
	]
	part.salvage_yield = {&"organics": 2}
	return part
