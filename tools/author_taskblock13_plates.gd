extends SceneTree

## taskblock-13 Pass G: one-time authoring pass — writes the wedge and
## cylinder ricochet-stress-test plates as `.tres` into `res://data/parts/`,
## same convention as `tools/migrate_data.gd`/`tools/author_taskblock13_guns.gd`.
## Run once via `godot --headless -s res://tools/author_taskblock13_plates.gd`;
## kept afterward as a record.
##
## `Box` has no orientation field of its own (docs/02: PART-local space,
## always axis-aligned) — a genuinely angled/curved face can only come
## from the SOCKET that mounts a plate, never the plate's own volume. So
## "wedge" and "cylinder" here are both simple flat plates; the actual
## stress rig (a hosting part with several ARMOR sockets at a spread of
## rotations) lives in test_ricochet_stress.gd as a fixture, not shipped
## content — no existing precedent in this codebase ships a purpose-built
## test rig as real game data (see docs comment on `Box`/`Socket`).


func _initialize() -> void:
	var dir: String = "res://data/parts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var count := 0
	for part: Part in _plates():
		var path: String = "%s/%s.tres" % [dir, part.id]
		var err: Error = ResourceSaver.save(part, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	print("Wrote %d plates." % count)
	quit()


func _plate(id: StringName, display_name: String, hp: int, mass: float, size: Vector3) -> Part:
	var part := Part.new()
	part.id = id
	part.display_name = display_name
	part.attaches_to = [&"ARMOR"]
	part.material = &"steel"
	part.hp = hp
	part.max_hp = hp
	part.mass = mass
	part.mangles_into = &"metal_scraps"
	part.volume = [Box.new(Vector3.ZERO, size)]
	return part


func _plates() -> Array[Part]:
	# Two sizes, both meant to be mounted through a range of differently-
	# rotated ARMOR sockets (the actual "wedge" arrangement) — flagged
	# placeholder hp/mass, loosely matching the existing plate_small/
	# plate_medium archetypes.
	var wedge_shallow: Part = _plate(
		&"wedge_plate_shallow", "Wedge Plate (Shallow)", 4, 1.2, Vector3(0.2, 0.3, 0.04)
	)
	var wedge_steep: Part = _plate(
		&"wedge_plate_steep", "Wedge Plate (Steep)", 5, 1.6, Vector3(0.22, 0.32, 0.05)
	)

	# render_primitive is cosmetic only (docs/09: never hit-tested) — the
	# actual varied normals come from mounting several of these through a
	# ring of rotated sockets, same as the wedge plates above.
	var cylinder_segment: Part = _plate(
		&"cylinder_plate_segment", "Cylinder Plate Segment", 4, 1.0, Vector3(0.18, 0.3, 0.04)
	)
	cylinder_segment.render_primitive = &"CYLINDER"
	cylinder_segment.render_scale = Vector3(0.18, 0.3, 0.3)

	return [wedge_shallow, wedge_steep, cylinder_segment]
