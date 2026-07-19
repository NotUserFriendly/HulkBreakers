extends GutTest

## taskblock-13 Pass F: "every placeholder gun box renders text on it
## stating what it is." Cosmetic only — never touches child count at the
## HitVolumeView root (the label nests under its own box's own
## MeshInstance3D, not as a sibling), so none of test_hit_volume_view.gd's
## own exact-count assertions are affected.


## A genuinely piloted unit (a docked matrix, same convention as
## test_hit_volume_view.gd's own _piloted_torso()) — Unit.is_downed()
## reads false, so refresh() draws its facing wedge, keeping child
## indices [marker, wedge, box] stable and matching that file's own.
func _unit_with(part: Part) -> Unit:
	part.sockets.append(Socket.new(&"MATRIX"))
	part.dock_matrix(Matrix.new())
	return Unit.new(part.hosted_matrix, Shell.new(part), Vector2i(0, 0))


func _weapon_part(display_name: String) -> Part:
	var part := Part.new()
	part.id = &"chaingun"
	part.display_name = display_name
	part.hp = 6
	part.max_hp = 6
	part.volume = [Box.new(Vector3.ZERO, Vector3(0.15, 0.15, 0.9))]
	part.weapon_def = WeaponDef.new()
	return part


func _non_weapon_part() -> Part:
	var part := Part.new()
	part.id = &"torso"
	part.display_name = "Torso"
	part.hp = 10
	part.max_hp = 10
	part.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))]
	return part


func _label_of(instance: MeshInstance3D) -> Label3D:
	for child: Node in instance.get_children():
		if child is Label3D:
			return child
	return null


func test_a_weapon_boxs_mesh_instance_carries_its_display_name_as_a_label() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(_unit_with(_weapon_part("Chaingun")), DataLibrary.material_table())

	var box_instance: MeshInstance3D = view.get_child(2)  # marker + wedge + box
	var label: Label3D = _label_of(box_instance)

	assert_not_null(label, "a weapon's own placeholder box must carry a label")
	assert_eq(label.text, "Chaingun")


func test_a_non_weapon_part_gets_no_label_at_all() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(_unit_with(_non_weapon_part()), DataLibrary.material_table())

	var box_instance: MeshInstance3D = view.get_child(2)

	assert_null(_label_of(box_instance))


## A weapon Part with no authored display_name (nothing to show) gets no
## label either — never an empty floating tag.
func test_a_weapon_with_no_display_name_gets_no_label() -> void:
	var part := _weapon_part("")
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(_unit_with(part), DataLibrary.material_table())

	var box_instance: MeshInstance3D = view.get_child(2)

	assert_null(_label_of(box_instance))


## Adding the label never changes HitVolumeView's own top-level child
## count — it nests inside the box's own MeshInstance3D, not as a sibling.
func test_the_label_never_changes_the_views_own_top_level_child_count() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(_unit_with(_weapon_part("Chaingun")), DataLibrary.material_table())

	assert_eq(view.get_child_count(), 3, "team marker + facing wedge + one part box, unchanged")


## Non-BOX placeholders (render_primitive != BOX) get the same label,
## riding the primitive's own instance instead of a box's.
func test_a_non_box_primitive_weapon_also_carries_its_label() -> void:
	var part := _weapon_part("Sniper Rifle")
	part.render_primitive = &"CYLINDER"
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(_unit_with(part), DataLibrary.material_table())

	var primitive_instance: MeshInstance3D = view.get_child(2)
	var label: Label3D = _label_of(primitive_instance)

	assert_not_null(label)
	assert_eq(label.text, "Sniper Rifle")


## taskblock-19 Pass I3: "printed on the side of the weapon... not a
## floating billboard." A box weapon's own label must be a real surface
## decal now — never billboarded, never ignoring depth.
func test_a_box_weapons_label_no_longer_billboards() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(_unit_with(_weapon_part("Chaingun")), DataLibrary.material_table())

	var box_instance: MeshInstance3D = view.get_child(2)
	var label: Label3D = _label_of(box_instance)

	assert_eq(label.billboard, BaseMaterial3D.BILLBOARD_DISABLED)
	assert_false(label.no_depth_test)


## The non-box (primitive) fallback path has no box face to print on —
## it must keep the OLD billboard behavior verbatim, never worse than
## before this pass.
func test_a_non_box_primitive_weapons_label_still_billboards() -> void:
	var part := _weapon_part("Sniper Rifle")
	part.render_primitive = &"CYLINDER"
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(_unit_with(part), DataLibrary.material_table())

	var primitive_instance: MeshInstance3D = view.get_child(2)
	var label: Label3D = _label_of(primitive_instance)

	assert_eq(label.billboard, BaseMaterial3D.BILLBOARD_ENABLED)
	assert_true(label.no_depth_test)


## "Scaled to fit the weapon's box face" — a bigger box must produce a
## bigger label, read back from the real node (CLAUDE.md: never trust
## the formula on paper alone).
func test_a_bigger_weapon_box_produces_a_bigger_label() -> void:
	var small := _weapon_part("Small Gun")
	small.volume = [Box.new(Vector3.ZERO, Vector3(0.05, 0.05, 0.3))]
	var big := _weapon_part("Big Gun")
	big.volume = [Box.new(Vector3.ZERO, Vector3(0.2, 0.2, 1.2))]

	var small_view := HitVolumeView.new()
	add_child_autofree(small_view)
	small_view.setup(_unit_with(small), DataLibrary.material_table())
	var big_view := HitVolumeView.new()
	add_child_autofree(big_view)
	big_view.setup(_unit_with(big), DataLibrary.material_table())

	var small_label: Label3D = _label_of(small_view.get_child(2))
	var big_label: Label3D = _label_of(big_view.get_child(2))

	assert_gt(big_label.pixel_size, small_label.pixel_size)


## "Printed on the side of the weapon" — for a long, thin gun (longest
## along Z, the barrel axis), the largest face is the side (height x
## length), so the label's own outward normal (basis.z, an unbillboarded
## Label3D's own readable-face direction) must point along local X, and
## it must sit flush against that face, not centered in the box.
func test_a_long_thin_weapons_label_sits_on_its_side_face() -> void:
	var part := _weapon_part("Sniper Rifle")
	part.volume = [Box.new(Vector3.ZERO, Vector3(0.1, 0.12, 1.1))]
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(_unit_with(part), DataLibrary.material_table())

	var label: Label3D = _label_of(view.get_child(2))

	assert_almost_eq(absf(label.basis.z.x), 1.0, 0.0001, "outward normal along local X")
	assert_almost_eq(label.basis.z.y, 0.0, 0.0001)
	assert_almost_eq(label.basis.z.z, 0.0, 0.0001)
	assert_almost_eq(
		absf(label.position.x),
		0.05 + HitVolumeView.WEAPON_LABEL_SURFACE_OFFSET,
		0.0001,
		"flush against the face"
	)
	assert_almost_eq(label.position.y, 0.0, 0.0001)
	assert_almost_eq(label.position.z, 0.0, 0.0001)


## The other two face orientations, proven the same way — a box longest
## along X (side face is top/bottom, XZ) and one longest along Y-ish
## with X/Y dominant (side face is front/back, XY). Exhaustive over all
## three branches of the largest-face pick, not just the common gun shape.
func test_the_largest_face_pick_covers_all_three_axis_pairs() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)

	# Longest along X: XZ (0.1) ties XY (0.1), both beat YZ (0.01) — the
	# tie resolves to XZ, outward along local Y (top/bottom face).
	var x_long := _weapon_part("X Long")
	x_long.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 0.1, 0.1))]
	view.setup(_unit_with(x_long), DataLibrary.material_table())
	var label_a: Label3D = _label_of(view.get_child(2))
	assert_almost_eq(absf(label_a.basis.z.y), 1.0, 0.0001, "outward along local Y")

	# XY clearly dominant (0.9) over XZ (0.1) and YZ (0.09) — outward
	# along local Z (front/back face).
	var flat := _weapon_part("Flat")
	flat.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 0.9, 0.1))]
	view.setup(_unit_with(flat), DataLibrary.material_table())
	var label_b: Label3D = _label_of(view.get_child(2))
	assert_almost_eq(absf(label_b.basis.z.z), 1.0, 0.0001, "outward along local Z")


## The Resource Editor's own bare-assembly preview (taskblock-11/12) goes
## through the same box/primitive dispatch — a weapon previewed there
## picks up its label too, for free.
func test_show_assembly_also_labels_a_previewed_weapon() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)

	view.show_assembly(_weapon_part("Chaingun"), DataLibrary.material_table(), Color.BLUE)

	var box_instance: MeshInstance3D = view.get_child(1)  # marker disc + one part box
	var label: Label3D = _label_of(box_instance)
	assert_not_null(label)
	assert_eq(label.text, "Chaingun")
