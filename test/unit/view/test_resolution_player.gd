extends GutTest

## docs/10 Phase 12.4: ResolutionPlayer is a thin shell over LogPlayback —
## the timing math itself is covered headlessly in test_log_playback.gd.
## Only the synchronous part (banner flips the instant play() starts) is
## asserted here without awaiting the full RESOLVE_LEAD_IN + tail — a real
## multi-second wait has no place in a fast test suite, and the eventual
## unlock is exactly `tactics.unlock_input()`, already covered directly in
## test_tactics_controller.gd.


func _make_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Frame.new(root), cell)


func test_setup_shows_the_tactics_banner() -> void:
	var banner := Label.new()
	var state := CombatState.new(Grid.new(5, 5), [_make_unit(Vector2i(0, 0))])
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(banner)
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)

	var player := ResolutionPlayer.new()
	add_child_autofree(player)
	player.setup(banner, controller)

	assert_eq(banner.text, ResolutionPlayer.TACTICS_BANNER)


func test_play_immediately_switches_to_the_resolution_banner() -> void:
	var banner := Label.new()
	var state := CombatState.new(Grid.new(5, 5), [_make_unit(Vector2i(0, 0))])
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(banner)
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)

	var player := ResolutionPlayer.new()
	add_child_autofree(player)
	player.setup(banner, controller)

	player.play([])  # fire-and-forget: only the pre-await portion runs synchronously

	assert_eq(banner.text, ResolutionPlayer.RESOLUTION_BANNER)
