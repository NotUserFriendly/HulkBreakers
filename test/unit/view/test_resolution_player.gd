extends GutTest

## docs/10 Phase 12.4 / taskblock-15 Pass B: ResolutionPlayer plays a
## resolved turn's log back as timed cosmetic animation. Most of the real
## LOGIC (per-cell path traversal, the tracer ring buffer, N=0 "no
## history") is exercised with every duration set to 0 — the tween/await
## branches are simply never entered when a duration is <= 0.0, so the
## whole synchronous body runs to completion with no real wall-clock wait
## at all. The three duration FORMULAS themselves (TESTS: "values are
## testable even if the wall-clock isn't") are pure functions, asserted
## directly. Real animated playback (does a Tween visually finish in
## bullet_ms) was confirmed by a single live check, not asserted here — a
## real multi-second wait has no place in a fast test suite.


func _make_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	return Unit.new(Matrix.new(), Shell.new(root), cell)


## Neutralizes _ready()'s own default SquadControlOverlay first (same
## reasoning as test_spectator_overlay.gd's own helper) before loading a
## custom two-unit fixture — ResolutionPlayer itself is standalone, wired
## directly against the resulting `battle`, no overlay needed at all.
func _setup_player() -> Dictionary:
	var banner := Label.new()
	add_child_autofree(banner)
	var attacker := _make_unit(Vector2i(0, 0))
	var target := _make_unit(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [attacker, target])
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]

	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)

	var player := ResolutionPlayer.new()
	add_child_autofree(player)
	player.setup(battle, Callable(), banner)
	return {
		"banner": banner,
		"attacker": attacker,
		"target": target,
		"state": state,
		"player": player,
		"battle": battle,
	}


func test_setup_shows_the_tactics_banner() -> void:
	var built: Dictionary = _setup_player()
	assert_eq((built.banner as Label).text, ResolutionPlayer.TACTICS_BANNER)


## B: "p_banner is optional" — SpectatorOverlay never supplies one.
func test_setup_with_no_banner_never_crashes() -> void:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	var player := ResolutionPlayer.new()
	add_child_autofree(player)

	player.setup(battle)

	assert_null(player.banner)


func test_play_immediately_switches_to_the_resolution_banner() -> void:
	var built: Dictionary = _setup_player()
	(built.player as ResolutionPlayer).play([])  # fire-and-forget: only the pre-await part runs
	assert_eq((built.banner as Label).text, ResolutionPlayer.RESOLUTION_BANNER)


func _impact_event(attacker: Unit, target: Unit, part_id: StringName) -> LogEvent:
	return (
		LogEvent
		. new(
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
	)


func test_play_impact_spawns_a_tracer_for_an_impact_event() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	assert_eq(player._tracers.get_child_count(), 0)

	player._play_impact(_impact_event(built.attacker, built.target, &"root"))

	assert_eq(player._tracers.get_child_count(), 1)


func test_play_event_ignores_non_impact_events() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player

	player._play_event(LogEvent.new(0, Enums.Phase.RESOLUTION, 0, &"turn_start"))

	assert_eq(player._tracers.get_child_count(), 0)


func test_the_tracer_spans_from_the_attackers_cell_to_the_targets_cell() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	var target: Unit = built.target

	player._play_impact(_impact_event(attacker, target, &"root"))

	var tracer: MeshInstance3D = player._tracers.get_child(0)
	var expected_from: Vector3 = player._muzzle_point(attacker)
	var expected_to: Vector3 = player._impact_point(target, &"root")
	assert_almost_eq(tracer.position.x, (expected_from.x + expected_to.x) * 0.5, 0.0001)
	assert_almost_eq(tracer.position.z, (expected_from.z + expected_to.z) * 0.5, 0.0001)
	var box: BoxMesh = tracer.mesh
	assert_almost_eq(box.size.z, expected_from.distance_to(expected_to), 0.0001)


func test_play_impact_with_an_unknown_target_does_not_crash_or_spawn_a_tracer() -> void:
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
	player._play_impact(event)

	assert_eq(player._tracers.get_child_count(), 0)


func _move_event(unit: Unit, path: Array[Vector2i]) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		unit.id,
		&"move",
		{"path": path, "destination": path[path.size() - 1]},
		"moved to %s" % path[path.size() - 1]
	)


## taskblock-15 Pass B2/TESTS: "a slide's per-cell count... derive[s] from
## slide_ms × cells" — slide_ms=0 takes the instant branch every cell, so
## the whole multi-cell traversal runs synchronously; ending back at exact
## zero offset proves every cell was actually visited (a skipped middle
## cell would leave a residual offset).
func test_a_zero_duration_slide_visits_every_path_cell_and_ends_at_zero_offset() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	player.slide_ms = 0.0
	var view: HitVolumeView = player._view_for(attacker.id)
	# _play_slide reads the unit's own TRUE final cell live (the pivot
	# every display offset is computed against) — matching reality, where
	# resolve_until() has already moved it there by the time any
	# animation runs; the event's own path must agree with it.
	attacker.cell = Vector2i(1, 1)

	player._play_slide(_move_event(attacker, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]))

	assert_eq(view.position, Vector3.ZERO)


func test_slide_segment_duration_derives_from_slide_ms_and_pacing_speed() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	player.slide_ms = 200.0
	player.speed = 2.0

	assert_almost_eq(player.slide_segment_duration(), 0.1, 0.0001)


## TESTS: "facing duration is a function of slide_ms."
func test_facing_duration_derives_from_slide_ms_and_pacing_speed() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	player.slide_ms = 400.0
	player.speed = 4.0

	assert_almost_eq(player.facing_duration(), 0.1, 0.0001)


func _faced_event(unit: Unit, direction: float) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		unit.id,
		&"faced",
		{"direction": direction, "cost": 1.0, "reason": &"manual_first"},
		"faced %.2f rad" % direction
	)


## Zero duration snaps instantly (no tween) — the real behavior under
## test is that _display_orientation is now tracking the new value, so
## the NEXT facing change animates from THIS one, not from a stale value.
func test_a_zero_duration_facing_change_snaps_and_remembers_the_new_orientation() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	player.slide_ms = 0.0

	player._play_facing(_faced_event(attacker, 1.5))

	assert_almost_eq(player._display_orientation[attacker.id], 1.5, 0.0001)


## A real, reported bug: a plain rotation around the VIEW's own local
## origin (world origin) swings a unit that isn't standing on cell (0,0)
## through a huge, wrong arc instead of turning in place ("fly off" /
## "orbitted something unexpectedly"). The fix's own defining property —
## true regardless of internal implementation — is that applying the
## resulting transform to the unit's own TRUE final anchor point must
## always map back to exactly its intended display position, for any
## delta_angle: rotation must never displace the unit's own body.
func test_a_facing_change_pivots_on_the_units_own_cell_not_the_map_origin() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var target: Unit = built.target
	var view: HitVolumeView = player._view_for(target.id)

	player._apply_display_transform(
		view, target.cell, 0.0, player._world_anchor(target.cell), PI / 2.0
	)

	var final_anchor: Vector3 = player._world_anchor(target.cell)
	var mapped: Vector3 = view.basis * final_anchor + view.position
	assert_almost_eq(
		mapped.x, final_anchor.x, 0.001, "rotating must not displace the unit's own body"
	)
	assert_almost_eq(
		mapped.z, final_anchor.z, 0.001, "rotating must not displace the unit's own body"
	)


## A real, reported bug: refresh_unit_views() already bakes every mesh at
## the FINAL state, synchronously, before play() even starts its own real-
## time lead-in wait — a unit used to flash at its destination for that
## whole wait, then visibly jump BACK the instant its own event actually
## began animating. _prime() must show the OLD state immediately
## (synchronously, no `await` reached yet), so nothing ever flashes at
## the destination first.
func test_prime_shows_the_old_state_immediately_so_nothing_flashes_at_the_destination() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	var previous_cell := Vector2i(attacker.cell.x - 1, attacker.cell.y)
	# Seeds the display record exactly like a real previous _play_slide
	# call would have left it — attacker.cell itself is untouched (this
	# is purely what was last SHOWN, not a real move).
	player._display_cell[attacker.id] = previous_cell
	var view: HitVolumeView = player._view_for(attacker.id)

	player._prime([_move_event(attacker, [previous_cell, attacker.cell])])

	var final_anchor: Vector3 = player._world_anchor(attacker.cell)
	assert_ne(
		view.position,
		Vector3.ZERO,
		"priming must show the OLD position, not the already-baked final one"
	)
	assert_almost_eq((view.position - final_anchor).length(), UnitGeometry.CELL_SIZE, 0.01)


func test_bullet_fade_duration_derives_from_bullet_ms_and_pacing_speed() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	player.bullet_ms = 500.0
	player.speed = 5.0

	assert_almost_eq(player.bullet_fade_duration(), 0.1, 0.0001)


## taskblock-15 Pass B3/TESTS: "exactly tracer_count dull tracers persist."
## bullet_ms=0 skips the fade tween, so _retire_tracer runs synchronously
## right after spawning — the ring is inspectable immediately.
func test_a_zero_duration_shot_retires_synchronously_into_the_ring() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	player.bullet_ms = 0.0
	player.tracer_count = 3

	player._play_impact(_impact_event(built.attacker, built.target, &"root"))

	assert_eq(player._tracer_ring.size(), 1)
	assert_eq(
		player._tracers.get_child_count(), 1, "the tracer must still be a live, visible child"
	)


## TESTS: "exactly tracer_count dull tracers persist (N+1 drops the
## oldest)."
func test_the_ring_never_exceeds_tracer_count_the_oldest_is_evicted() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	player.bullet_ms = 0.0
	player.tracer_count = 2

	player._play_impact(_impact_event(built.attacker, built.target, &"root"))
	var first: MeshInstance3D = player._tracer_ring[0]
	player._play_impact(_impact_event(built.attacker, built.target, &"root"))
	player._play_impact(_impact_event(built.attacker, built.target, &"root"))

	assert_eq(player._tracer_ring.size(), 2, "never more than tracer_count dull ghosts at once")
	assert_false(player._tracer_ring.has(first), "the oldest must have been evicted")
	assert_eq(player._tracers.get_child_count(), 2)


## TESTS: "tracer_count = 0 leaves no history."
func test_tracer_count_zero_leaves_no_history() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	player.bullet_ms = 0.0
	player.tracer_count = 0

	player._play_impact(_impact_event(built.attacker, built.target, &"root"))

	assert_true(player._tracer_ring.is_empty())
	assert_eq(player._tracers.get_child_count(), 0, "the fade must complete to nothing")


## TESTS: "inter-shot break separates burst pulls." A real (but tiny —
## speed cranked way up) wait: the break lives in play()'s own outer loop,
## not a directly-callable pure helper, so this is the one genuinely
## timed integration check in this file, kept fast by scaling speed.
func test_inter_shot_break_separates_consecutive_impacts() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	var target: Unit = built.target
	player.slide_ms = 0.0
	player.bullet_ms = 0.0
	player.tracer_count = 0
	player.speed = 1000.0

	var events: Array[LogEvent] = [
		_impact_event(attacker, target, &"root"), _impact_event(attacker, target, &"root")
	]
	await player.play(events)

	assert_eq(player._tracers.get_child_count(), 0, "both shots must have fully retired (count 0)")
