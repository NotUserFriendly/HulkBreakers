extends GutTest

## docs/10 Phase 12.4: ResolutionPlayer is a thin shell over LogPlayback —
## the timing math itself is covered headlessly in test_log_playback.gd.
## The synchronous part (banner flips the instant play() starts, a cue
## spawns its tracer) is asserted directly, without awaiting the full
## RESOLVE_LEAD_IN + tail — a real multi-second wait has no place in a fast
## test suite, and the eventual unlock is exactly `tactics.unlock_input()`,
## already covered directly in test_tactics_controller.gd.


func _make_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	return Unit.new(Matrix.new(), Frame.new(root), cell)


func _setup_player() -> Dictionary:
	var banner := Label.new()
	var attacker := _make_unit(Vector2i(0, 0))
	var target := _make_unit(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [attacker, target])
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
	return {
		"banner": banner, "attacker": attacker, "target": target, "state": state, "player": player
	}


func test_setup_shows_the_tactics_banner() -> void:
	var built: Dictionary = _setup_player()
	assert_eq((built.banner as Label).text, ResolutionPlayer.TACTICS_BANNER)


func test_play_immediately_switches_to_the_resolution_banner() -> void:
	var built: Dictionary = _setup_player()
	(built.player as ResolutionPlayer).play([])  # fire-and-forget: only the pre-await part runs
	assert_eq((built.banner as Label).text, ResolutionPlayer.RESOLUTION_BANNER)


func _impact_event(attacker: Unit, target: Unit, part_id: StringName) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		attacker.id,
		&"impact",
		{
			"outcome": Enums.Outcome.PENETRATE,
			"part": part_id,
			"target_unit_id": target.id,
			"damage": 5.0,
			"bypassed_armor": false,
			"is_crit": false,
			"is_double_crit": false,
		},
		"PENETRATE on %s" % part_id
	)


func test_play_cue_spawns_a_tracer_for_an_impact_event() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	assert_eq(player._tracers.get_child_count(), 0)

	player._play_cue(_impact_event(built.attacker, built.target, &"root"))

	assert_eq(player._tracers.get_child_count(), 1)


func test_play_cue_ignores_non_impact_events() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player

	player._play_cue(LogEvent.new(0, Enums.Phase.RESOLUTION, 0, &"turn_start"))

	assert_eq(player._tracers.get_child_count(), 0)


func test_the_tracer_spans_from_the_attackers_cell_to_the_targets_cell() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	var target: Unit = built.target

	player._play_cue(_impact_event(attacker, target, &"root"))

	var tracer: MeshInstance3D = player._tracers.get_child(0)
	var expected_from: Vector3 = player._muzzle_point(attacker)
	var expected_to: Vector3 = player._impact_point(target, &"root")
	assert_almost_eq(tracer.position.x, (expected_from.x + expected_to.x) * 0.5, 0.0001)
	assert_almost_eq(tracer.position.z, (expected_from.z + expected_to.z) * 0.5, 0.0001)
	var box: BoxMesh = tracer.mesh
	assert_almost_eq(box.size.z, expected_from.distance_to(expected_to), 0.0001)


func test_play_cue_with_an_unknown_target_does_not_crash_or_spawn_a_tracer() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker

	var event := LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		attacker.id,
		&"impact",
		{"part": &"root", "target_unit_id": -1},
		"impact with no known target"
	)
	player._play_cue(event)

	assert_eq(player._tracers.get_child_count(), 0)
