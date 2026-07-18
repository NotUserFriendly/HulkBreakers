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
