extends SceneTree

## taskblock-17 Pass E: one-time authoring pass — rewrites the ricochet-
## stress plates as real, standalone, angled/curved geometry, and adds
## thigh-sized parts. Run once via
## `godot --headless -s res://tools/author_taskblock17_plates.gd`; kept
## afterward as a record, same convention as every other
## `tools/author_taskblockNN_*.gd`.
##
## `Box` has no orientation of its own (docs/02, taskblock-13 G) — every
## box within one Part's own `volume` array shares that Part's local
## axes, so a genuinely angled or curved SURFACE (a face with a different
## normal than its neighbor) can only come from a SEPARATE child Part
## mounted through a rotated Socket (`Socket.transform`'s own `Basis`,
## composed by `BodyProjector._project_tree`), never from stacking more
## boxes into one flat `volume` list. taskblock-13 G's own wedge/cylinder
## plates were deliberately left as single flat boxes for exactly this
## reason, relying on an EXTERNAL disposable test rig
## (`test_ricochet_stress.gd`) to mount several of them at a spread of
## socket rotations. taskblock-17's own complaint — "build the actual
## wedge silhouette, not a flat plate on an angled socket" — is about
## that rig living OUTSIDE the plate, not about rotated sockets being the
## wrong mechanism: the fix here is the SAME rotated-socket mechanism,
## just baked into the plate's own definition, so mounting ONE part
## (`wedge_plate_shallow`, etc.) gives the real angled/curved shape for
## free, standalone and shippable, no rig required.


func _wedge_face(size: Vector3, hp: int, id: StringName) -> Part:
	var part := Part.new()
	part.id = id
	part.material = &"steel"
	part.hp = hp
	part.max_hp = hp
	part.mangles_into = &"metal_scraps"
	part.volume = [Box.new(Vector3.ZERO, size)]
	return part


## `tilt_deg`: each face's own rotation away from dead-ahead (+Z, docs/02
## WORLD_FORWARD) — the angle a shot arriving straight on actually
## strikes the face at. 30 degrees is the taskblock's own stated number
## ("two of the prism's angles ~30 degrees... a shallow point that
## deflects rather than stops") — not a coincidence that it sits right at
## DamageResolver's own default DEFLECT-vs-STOP_DEAD incidence threshold
## (docs/03): 30 degrees is the SHALLOWEST tilt that still reliably tips
## a hit into deflecting rather than stopping dead, which is exactly what
## "shallow point" describes. `wedge_plate_steep` gets a visibly steeper
## 45 degrees — flagged, not tuned; no second number is specified, so
## this is the simplest faithful "clearly steeper than shallow" step.
func _wedge(
	id: StringName, display_name: String, hp: int, mass: float, face_size: Vector3, tilt_deg: float
) -> Part:
	var root := Part.new()
	root.id = id
	root.display_name = display_name
	root.attaches_to = [&"ARMOR"]
	root.material = &"steel"
	# docs/10: "hp > 0 with no volume, cannot appear in the shot plane" is
	# a real DeepStrike.validate_assembly violation, not a stray lint
	# nag — a living part with no geometry genuinely can't ever be hit.
	# The root here is a pure two-socket hub, all its real geometry (and
	# so all its real survivability) lives in the two face children below
	# — 0/0 here is the honest reflection of that, not a placeholder.
	root.hp = 0
	root.max_hp = 0
	root.mass = mass
	root.mangles_into = &"metal_scraps"

	var half_hp: int = maxi(1, int(round(float(hp) / 2.0)))
	var tilt: float = deg_to_rad(tilt_deg)
	var lateral: float = face_size.x * 0.5

	var left: Part = _wedge_face(face_size, half_hp, StringName("%s_face_l" % id))
	var right: Part = _wedge_face(face_size, half_hp, StringName("%s_face_r" % id))

	var left_socket := Socket.new(
		&"WEDGE_FACE", Transform3D(Basis(Vector3.UP, tilt), Vector3(-lateral, 0.0, 0.0)), &"left"
	)
	left_socket.occupant = left
	var right_socket := Socket.new(
		&"WEDGE_FACE", Transform3D(Basis(Vector3.UP, -tilt), Vector3(lateral, 0.0, 0.0)), &"right"
	)
	right_socket.occupant = right

	root.sockets = [left_socket, right_socket]
	return root


## "Make it a half-cylinder — the curved face outward, flat face against
## the host... multi-box approximation of a half-cylinder (curved outer
## face -> varied normals across it — taskblock-13 G's own >60 degree
## normal spread still applies)." `FACET_COUNT` flat facets, evenly
## spread across a 180-degree arc (a true half — the flat diametral cut
## sits against the host, the convex arc faces outward), each one its
## own rotated child Part exactly like a wedge's two faces, just more of
## them. 5 facets spans a full 180 degrees of normal spread end to end
## (far past the >60 degree bar) while staying a small, cheap part tree.
func _half_cylinder(
	id: StringName, display_name: String, hp: int, mass: float, facet_size: Vector3, radius: float
) -> Part:
	const FACET_COUNT := 5
	const ARC_DEGREES := 180.0

	var root := Part.new()
	root.id = id
	root.display_name = display_name
	root.attaches_to = [&"ARMOR"]
	root.material = &"steel"
	# Same reasoning as `_wedge`'s own root: a living part with no volume
	# fails DeepStrike.validate_assembly for real (it can never appear in
	# the shot plane) — the root is a pure facet hub, 0/0 here is honest,
	# not a placeholder. Every facet child carries its own real hp.
	root.hp = 0
	root.max_hp = 0
	root.mass = mass
	root.mangles_into = &"metal_scraps"

	var facet_hp: int = maxi(1, int(round(float(hp) / float(FACET_COUNT))))
	var sockets: Array[Socket] = []
	for i in range(FACET_COUNT):
		var t: float = float(i) / float(FACET_COUNT - 1)  # 0.0 .. 1.0 across the arc
		var angle_deg: float = -ARC_DEGREES * 0.5 + ARC_DEGREES * t
		var angle: float = deg_to_rad(angle_deg)
		# Each facet sits on the arc of `radius`, facing straight outward
		# along its own radius — the same "rotate, then offset along the
		# rotated frame's own forward" composition a wedge face uses, just
		# swept around a full semicircle instead of a single V. Z ranges
		# from `radius` at the center facet (angle 0 -> the apex, the
		# farthest point OUT from the host) down to exactly 0 at the two
		# end facets (angle +/-90 -> flush with the mounting socket
		# itself) — never negative, i.e. never behind the mounting point
		# and into the host. `cos(angle) * radius` alone (NOT minus
		# radius) is what keeps it in that 0..radius range; the first
		# version of this authoring pass had the sign backwards (apex
		# flush, edges receding to -radius, INTO the host — exactly the
		# clipping bug this pass exists to fix) and was caught before
		# ever shipping, via a live probe reading the real projected
		# geometry back rather than trusting the formula on paper.
		var facet: Part = _half_cylinder_facet(
			facet_size, facet_hp, StringName("%s_facet_%d" % [id, i])
		)
		var offset := Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)
		var socket := Socket.new(
			&"HALF_CYLINDER_FACET",
			Transform3D(Basis(Vector3.UP, angle), offset),
			StringName("facet_%d" % i)
		)
		socket.occupant = facet
		sockets.append(socket)

	root.sockets = sockets
	return root


func _half_cylinder_facet(size: Vector3, hp: int, id: StringName) -> Part:
	var part := Part.new()
	part.id = id
	part.material = &"steel"
	part.hp = hp
	part.max_hp = hp
	part.mangles_into = &"metal_scraps"
	part.volume = [Box.new(Vector3.ZERO, size)]
	return part


## "Add parts sized for thighs (between torso and the small limb
## parts)." `torso` is (0.5, 0.7, 0.28); `leg`/`arm` are (0.16, 0.9, 0.16)
## / (0.14, 0.34, 0.14) — a thigh sits between those: wider than a full
## leg segment (a real thigh is chunkier than a shin) but nowhere near
## torso-scale, and shorter than the leg's own full length since it's
## only the upper segment. `HIP`-attachable, matching `leg`'s own
## attachment point (the plate tests need a real, realistically-sized
## surface to mount a plate on, not a new limb-tier assembly wired into
## the reference humanoid — that's a separate, much larger change this
## pass doesn't ask for).
func _thigh() -> Part:
	var part := Part.new()
	part.id = &"thigh"
	part.display_name = "Thigh"
	part.attaches_to = [&"HIP"]
	part.material = &"artificial_bone"
	part.hp = 8
	part.max_hp = 8
	part.mass = 9.0
	part.volume = [Box.new(Vector3(0.0, -0.22, 0.0), Vector3(0.24, 0.44, 0.24))]
	var armor := Socket.new(&"ARMOR", Transform3D(Basis(), Vector3(0.0, -0.22, 0.13)), &"ARMOR")
	part.sockets = [armor]
	return part


func _initialize() -> void:
	var dir: String = "res://data/parts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var wedge_shallow: Part = _wedge(
		&"wedge_plate_shallow", "Wedge Plate (Shallow)", 4, 1.2, Vector3(0.2, 0.3, 0.04), 30.0
	)
	var wedge_steep: Part = _wedge(
		&"wedge_plate_steep", "Wedge Plate (Steep)", 5, 1.6, Vector3(0.22, 0.32, 0.05), 45.0
	)
	var wedge_torso: Part = _wedge(
		&"wedge_plate_torso", "Wedge Plate (Torso)", 10, 3.0, Vector3(0.4, 0.6, 0.06), 30.0
	)
	var half_cylinder: Part = _half_cylinder(
		&"half_cylinder_plate", "Half-Cylinder Plate", 4, 1.0, Vector3(0.14, 0.3, 0.05), 0.16
	)
	var thigh: Part = _thigh()

	var parts: Array[Part] = [wedge_shallow, wedge_steep, wedge_torso, half_cylinder, thigh]
	var count := 0
	for part: Part in parts:
		var path: String = "%s/%s.tres" % [dir, part.id]
		var err: Error = ResourceSaver.save(part, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	print("Wrote %d plates/parts." % count)

	# cylinder_plate_segment is retired outright — renamed/replaced by
	# half_cylinder_plate above.
	var old_path: String = "%s/cylinder_plate_segment.tres" % dir
	if FileAccess.file_exists(old_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
		print("Removed retired cylinder_plate_segment.tres")

	quit()
