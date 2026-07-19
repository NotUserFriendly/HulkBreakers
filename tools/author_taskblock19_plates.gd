extends SceneTree

## taskblock-19 Pass G: one-time authoring pass — fixes the two tb17
## plate-geometry leftovers. Run once via
## `godot --headless -s res://tools/author_taskblock19_plates.gd`; kept
## afterward as a record, same convention as every other
## `tools/author_taskblockNN_*.gd`.
##
## G1 — the wedge was logically inverted. `_wedge()` mounted its LEFT
## face (x=-lateral) rotated by +tilt and its RIGHT face (x=+lateral) by
## -tilt. Working the rotation through (Godot's right-handed Y-up axis-
## angle: rotating local +Z by +tilt around +Y tilts it toward +X) shows
## that assignment tilts BOTH faces' own outward normals TOWARD the
## centerline — a "<" opening toward the attacker (concave, collects
## fire) instead of a ">" pointing AT the attacker (convex, deflects).
## The fix is exactly the swap: left gets -tilt, right gets +tilt, so
## each face's normal tilts AWAY from center (and forward), giving the
## point a real forward-facing apex. No compensating rotation anywhere
## else in the tree — the wedge's own two socket transforms are simply
## correct now.
##
## G2 — half-cylinder resize: "~half its current width and depth, taller
## (thigh height), more facets." The half-cylinder's overall silhouette
## width (=2*radius) and depth (=radius, how far it projects off the
## mount) are BOTH governed by one number — radius — so halving radius
## alone halves both dimensions at once. facet_size.y rises to match the
## real thigh part's own full height (0.44, `_thigh()`,
## tools/author_taskblock17_plates.gd). facet_size.x (each facet's own
## chord width) shrinks to match the smaller radius and the higher facet
## count (more, narrower facets covering less arc apiece) — flagged,
## scaled from the same proportion tb17's own authored value kept over
## its computed chord length, not re-derived from scratch. FACET_COUNT
## 5 -> 9 doubles the normal spread's resolution across the same 180
## degrees.


func _wedge_face(size: Vector3, hp: int, id: StringName) -> Part:
	var part := Part.new()
	part.id = id
	part.material = &"steel"
	part.hp = hp
	part.max_hp = hp
	part.mangles_into = &"metal_scraps"
	part.volume = [Box.new(Vector3.ZERO, size)]
	return part


func _wedge(
	id: StringName, display_name: String, hp: int, mass: float, face_size: Vector3, tilt_deg: float
) -> Part:
	var root := Part.new()
	root.id = id
	root.display_name = display_name
	root.attaches_to = [&"ARMOR"]
	root.material = &"steel"
	root.hp = 0
	root.max_hp = 0
	root.mass = mass
	root.mangles_into = &"metal_scraps"

	var half_hp: int = maxi(1, int(round(float(hp) / 2.0)))
	var tilt: float = deg_to_rad(tilt_deg)
	var lateral: float = face_size.x * 0.5

	var left: Part = _wedge_face(face_size, half_hp, StringName("%s_face_l" % id))
	var right: Part = _wedge_face(face_size, half_hp, StringName("%s_face_r" % id))

	# taskblock-19 Pass G1: the fix — left tilts toward -X (away from
	# center), right toward +X (away from center), so both faces' own
	# forward normals point outward AND forward, meeting at a real apex
	# facing the incoming shot instead of receding from it.
	var left_socket := Socket.new(
		&"WEDGE_FACE", Transform3D(Basis(Vector3.UP, -tilt), Vector3(-lateral, 0.0, 0.0)), &"left"
	)
	left_socket.occupant = left
	var right_socket := Socket.new(
		&"WEDGE_FACE", Transform3D(Basis(Vector3.UP, tilt), Vector3(lateral, 0.0, 0.0)), &"right"
	)
	right_socket.occupant = right

	root.sockets = [left_socket, right_socket]
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


func _half_cylinder(
	id: StringName, display_name: String, hp: int, mass: float, facet_size: Vector3, radius: float
) -> Part:
	const FACET_COUNT := 9
	const ARC_DEGREES := 180.0

	var root := Part.new()
	root.id = id
	root.display_name = display_name
	root.attaches_to = [&"ARMOR"]
	root.material = &"steel"
	root.hp = 0
	root.max_hp = 0
	root.mass = mass
	root.mangles_into = &"metal_scraps"

	var facet_hp: int = maxi(1, int(round(float(hp) / float(FACET_COUNT))))
	var sockets: Array[Socket] = []
	for i in range(FACET_COUNT):
		var t: float = float(i) / float(FACET_COUNT - 1)
		var angle_deg: float = -ARC_DEGREES * 0.5 + ARC_DEGREES * t
		var angle: float = deg_to_rad(angle_deg)
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


func _initialize() -> void:
	var dir: String = "res://data/parts"

	var wedge_shallow: Part = _wedge(
		&"wedge_plate_shallow", "Wedge Plate (Shallow)", 4, 1.2, Vector3(0.2, 0.3, 0.04), 30.0
	)
	var wedge_steep: Part = _wedge(
		&"wedge_plate_steep", "Wedge Plate (Steep)", 5, 1.6, Vector3(0.22, 0.32, 0.05), 45.0
	)
	var wedge_torso: Part = _wedge(
		&"wedge_plate_torso", "Wedge Plate (Torso)", 10, 3.0, Vector3(0.4, 0.6, 0.06), 30.0
	)
	# taskblock-19 Pass G2: radius 0.16 -> 0.08 (half the overall width
	# AND depth in one number); facet_size.y 0.3 -> 0.44 (thigh height);
	# facet_size.x 0.14 -> 0.05, scaled down with the smaller radius and
	# the higher facet count.
	var half_cylinder: Part = _half_cylinder(
		&"half_cylinder_plate", "Half-Cylinder Plate", 4, 1.0, Vector3(0.05, 0.44, 0.05), 0.08
	)

	var parts: Array[Part] = [wedge_shallow, wedge_steep, wedge_torso, half_cylinder]
	var count := 0
	for part: Part in parts:
		var path: String = "%s/%s.tres" % [dir, part.id]
		var err: Error = ResourceSaver.save(part, path)
		if err != OK:
			push_error("Failed to save %s: %s" % [path, err])
			continue
		count += 1
	print("Rebuilt %d plates." % count)
	quit()
