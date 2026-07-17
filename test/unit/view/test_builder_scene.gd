extends GutTest

## docs/10 taskblock05 G: "BuilderController pure, BuilderScene thin" — the
## real coverage is test_builder_controller.gd; this only checks the scene
## actually wires up and redraws from it.


func test_ready_assembles_a_unit_and_populates_the_socket_tree() -> void:
	var scene := BuilderScene.new()
	add_child_autofree(scene)

	assert_not_null(scene.current_unit)
	assert_not_null(scene.socket_tree.get_root())


func test_ready_shows_validation_for_the_default_assembly() -> void:
	var scene := BuilderScene.new()
	add_child_autofree(scene)

	assert_true(scene.validation_label.text.contains("mass"))
	assert_true(scene.validation_label.text.contains("ram"))


## docs/10 taskblock05 G4: selecting an empty socket populates the picker
## with both legal and illegal (disabled) candidates.
func test_selecting_an_empty_socket_populates_the_picker() -> void:
	var scene := BuilderScene.new()
	add_child_autofree(scene)

	var hand_r: Part = scene.current_unit.shell.find_part(&"hand_r")
	var grip_r: Socket = PartGraph.find_socket(hand_r, &"GRIP_R")
	scene._selected_host = hand_r
	scene._selected_socket = grip_r
	scene._refresh_picker()

	assert_true(scene.picker_list.item_count > 0)


## docs/10 taskblock05 G4: clicking a legal entry attaches it, through the
## same controller.set_part() the taskblock's own tests already cover.
func test_picking_a_legal_part_attaches_it_and_refreshes() -> void:
	var scene := BuilderScene.new()
	add_child_autofree(scene)

	var hand_r: Part = scene.current_unit.shell.find_part(&"hand_r")
	var grip_r: Socket = PartGraph.find_socket(hand_r, &"GRIP_R")
	scene._selected_host = hand_r
	scene._selected_socket = grip_r
	scene._refresh_picker()

	var pistol_index := -1
	for i in range(scene.picker_list.item_count):
		if scene.picker_list.get_item_metadata(i) == &"pistol":
			pistol_index = i
	assert_true(pistol_index >= 0, "pistol must be a legal candidate for an empty GRIP")

	scene._on_picker_item_selected(pistol_index)

	assert_not_null(scene.current_unit.shell.find_part(&"pistol"))


func test_load_unit_reassembles_from_the_given_unit() -> void:
	var scene := BuilderScene.new()
	add_child_autofree(scene)
	var reference: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i.ZERO)

	scene.load_unit(reference)

	assert_not_null(scene.current_unit.shell.find_part(&"pistol"))
