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


## taskblock-22 Pass D: `origin_x/y` default to the attacker's OWN cell —
## a shot's first (and, in most of these tests, only) hop, matching
## `_muzzle_point(attacker)` exactly, so every existing single-hop
## assertion stays valid unchanged. A ricochet hop passes its own real
## origin explicitly instead (see `_ricochet_impact_event` below).
func _impact_event(
	attacker: Unit, target: Unit, part_id: StringName, origin: Vector2 = Vector2.INF
) -> LogEvent:
	var real_origin: Vector2 = (
		Vector2(attacker.cell.x, attacker.cell.y) if origin == Vector2.INF else origin
	)
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
				"origin_x": real_origin.x,
				"origin_y": real_origin.y,
			},
			"PENETRATE on %s" % part_id
		)
	)


## A no-target hit (clutter, a wall, the void) — target_unit_id stays -1,
## and this is the one case `hit_x/y` (not a target's own composed mesh
## position) actually gets read.
func _clutter_impact_event(attacker: Unit, hit: Vector2, origin: Vector2 = Vector2.INF) -> LogEvent:
	var real_origin: Vector2 = (
		Vector2(attacker.cell.x, attacker.cell.y) if origin == Vector2.INF else origin
	)
	return (
		LogEvent
		. new(
			0,
			Enums.Phase.RESOLUTION,
			attacker.id,
			&"impact",
			{
				"outcome": Enums.Outcome.STOP_DEAD,
				"part": &"crate",
				"target_unit_id": -1,
				"damage": 5.0,
				"bypassed_armor": false,
				"is_crit": false,
				"is_double_crit": false,
				"origin_x": real_origin.x,
				"origin_y": real_origin.y,
				"hit_x": hit.x,
				"hit_y": hit.y,
			},
			"STOP_DEAD on crate"
		)
	)


func test_play_impact_spawns_a_tracer_for_an_impact_event() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	assert_eq(player._tracers.get_child_count(), 0)

	player._play_impact(_impact_event(built.attacker, built.target, &"root"))

	assert_eq(player._tracers.get_child_count(), 1)


## "Draw new raycasts over top tracers" — the live/still-fading shot must
## outrank every already-retired one via render_priority (not left to
## camera-distance sort order, which can't be trusted when two tracers
## share a similar line of fire).
func test_a_live_tracer_is_drawn_at_the_live_render_priority() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	player.bullet_ms = 10000.0
	player.tracer_count = 3

	player._play_impact(_impact_event(built.attacker, built.target, &"root"))

	var tracer: MeshInstance3D = player._tracers.get_child(0)
	var material: StandardMaterial3D = (tracer.mesh as BoxMesh).material
	assert_eq(material.render_priority, ResolutionPlayer.TRACER_LIVE_RENDER_PRIORITY)


## "A dark, faint red" — the color/alpha a live shot actually fades TO and
## persists at, not the live flash's own bright color, and it must drop
## out of the live render-priority tier once retired. Checks the shape of
## `TRACER_DULL_COLOR` (a red hue, and translucent — never the live
## flash's own bright, opaque color) rather than hand-duplicating its
## exact numbers, which already live in the one constant this reads.
func test_a_retired_tracer_is_translucent_red_and_drops_to_the_retired_priority() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	player.bullet_ms = 10.0
	player.speed = 1000.0
	player.tracer_count = 3

	await player._play_impact(_impact_event(built.attacker, built.target, &"root"))

	var tracer: MeshInstance3D = player._tracer_ring[0]
	var material: StandardMaterial3D = (tracer.mesh as BoxMesh).material
	var color: Color = material.albedo_color
	assert_eq(color, ResolutionPlayer.TRACER_DULL_COLOR)
	assert_lt(color.a, 1.0, "must be translucent, not opaque")
	assert_gt(color.r, 0.0, "a red hue")
	assert_almost_eq(color.g, 0.0, 0.0001, "a red hue, not a mix with green")
	assert_almost_eq(color.b, 0.0, 0.0001, "a red hue, not a mix with blue")
	assert_lt(
		color.r, ResolutionPlayer.TRACER_COLOR.r, "darker than the live flash's own bright color"
	)
	assert_eq(material.render_priority, ResolutionPlayer.TRACER_RETIRED_RENDER_PRIORITY)


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


## taskblock-22 Pass D: "never skip a shot for lack of a target unit — a
## shot into clutter, cover, a wall, or a teammate draws its ray." A hit
## with no target Unit (target_unit_id == -1) now draws its tracer to the
## hop's own logged hit_x/y instead of being silently dropped.
func test_play_impact_with_no_target_unit_still_draws_a_tracer_to_the_hit_point() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker

	player._play_impact(_clutter_impact_event(attacker, Vector2(5.0, 3.0)))

	assert_eq(player._tracers.get_child_count(), 1)
	var tracer: MeshInstance3D = player._tracers.get_child(0)
	var expected_from: Vector3 = player._muzzle_point(attacker)
	var expected_to := (
		Vector3(5.0, ResolutionPlayer.TRACER_MUZZLE_HEIGHT, 3.0) * UnitGeometry.CELL_SIZE
	)
	assert_almost_eq(tracer.position.x, (expected_from.x + expected_to.x) * 0.5, 0.0001)
	assert_almost_eq(tracer.position.z, (expected_from.z + expected_to.z) * 0.5, 0.0001)


## taskblock-22 Pass D: the actual bug this pass fixes — a ricochet hop's
## own tracer must originate from where THAT bounce actually started
## (open air, wherever the previous hop deflected from), never from the
## shooter's own body regardless of how many times the round already
## bounced.
func test_play_impact_draws_a_ricochet_hop_from_its_own_real_origin_not_the_shooter() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	var target: Unit = built.target
	var bounce_point := Vector2(6.0, 1.0)

	player._play_impact(_impact_event(attacker, target, &"root", bounce_point))

	var tracer: MeshInstance3D = player._tracers.get_child(0)
	var expected_from := (
		Vector3(bounce_point.x, ResolutionPlayer.TRACER_MUZZLE_HEIGHT, bounce_point.y)
		* UnitGeometry.CELL_SIZE
	)
	var expected_to: Vector3 = player._impact_point(target, &"root")
	assert_almost_eq(tracer.position.x, (expected_from.x + expected_to.x) * 0.5, 0.0001)
	assert_almost_eq(tracer.position.z, (expected_from.z + expected_to.z) * 0.5, 0.0001)
	var shooter_from: Vector3 = player._muzzle_point(attacker)
	assert_ne(
		expected_from,
		shooter_from,
		"sanity: the bounce point must actually differ from the shooter's own muzzle"
	)


## taskblock-21 Pass F: mirrors `ShotResolution._log_miss`'s own data shape
## (`end_x`/`end_y`, cell-space coordinates) — never a fixture the view
## side invents independently of what the logic side actually logs.
func _miss_event(attacker: Unit, end_x: float, end_y: float) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		attacker.id,
		&"miss",
		{"end_x": end_x, "end_y": end_y},
		"missed — ray continues to (%.1f, %.1f)" % [end_x, end_y]
	)


## taskblock-21 Pass F: "every fired shot draws its ray, hit or miss" —
## same tracer path an impact uses, just terminating at the miss's own
## logged void endpoint instead of a struck part.
func test_play_miss_spawns_a_tracer_along_its_own_logged_endpoint() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	assert_eq(player._tracers.get_child_count(), 0)

	player._play_miss(_miss_event(attacker, 7.0, 2.0))

	assert_eq(player._tracers.get_child_count(), 1)
	var tracer: MeshInstance3D = player._tracers.get_child(0)
	var expected_from: Vector3 = player._muzzle_point(attacker)
	var expected_to := (
		Vector3(7.0, ResolutionPlayer.TRACER_MUZZLE_HEIGHT, 2.0) * UnitGeometry.CELL_SIZE
	)
	assert_almost_eq(tracer.position.x, (expected_from.x + expected_to.x) * 0.5, 0.0001)
	assert_almost_eq(tracer.position.z, (expected_from.z + expected_to.z) * 0.5, 0.0001)


## `_play_event`'s own dispatch, not a second, parallel switch — proves
## `&"miss"` is really wired into the same `match` `&"impact"` already is.
func test_play_event_dispatches_a_miss_event_to_play_miss() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker

	player._play_event(_miss_event(attacker, 7.0, 2.0))

	assert_eq(player._tracers.get_child_count(), 1)


func test_play_miss_with_an_unknown_attacker_does_not_crash_or_spawn_a_tracer() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player

	var event := LogEvent.new(
		0, Enums.Phase.RESOLUTION, 999, &"miss", {"end_x": 7.0, "end_y": 2.0}, "unknown shooter"
	)
	player._play_miss(event)

	assert_eq(player._tracers.get_child_count(), 0)


## taskblock-21 Pass F: the inter-shot break must separate ANY run of
## impact/miss, not just back-to-back impacts — a burst that lands a hit
## then a miss (or the reverse) must still pace evenly.
func test_inter_shot_break_separates_a_miss_from_a_following_impact() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	var target: Unit = built.target
	player.slide_ms = 0.0
	player.bullet_ms = 0.0
	player.tracer_count = 0
	player.speed = 1000.0

	var events: Array[LogEvent] = [
		_miss_event(attacker, 7.0, 2.0), _impact_event(attacker, target, &"root")
	]
	await player.play(events)

	assert_eq(player._tracers.get_child_count(), 0, "both shots must have fully retired (count 0)")


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


## taskblock-19 Pass J: "no logic lives only in the viewed path" — the
## real, load-bearing half of that claim is that playback never mutates
## `CombatState` at all, it only reads it and nudges VIEW nodes
## (`view.basis`/`view.position`). Proven directly: a unit's own
## already-resolved real fields (cell/orientation/ap/hp — exactly what
## resolve_until() would have set for real before play() ever runs) must
## be byte-identical after replaying a move+face turn back as animation.
func test_playback_never_mutates_the_real_combat_states_own_unit_fields() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	attacker.cell = Vector2i(2, 0)
	attacker.orientation = PI / 2.0
	attacker.ap = 3
	var before_cell: Vector2i = attacker.cell
	var before_orientation: float = attacker.orientation
	var before_ap: int = attacker.ap
	var before_hp: int = attacker.shell.root.hp

	player._play_slide(_move_event(attacker, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]))
	player._play_facing(_faced_event(attacker, PI / 2.0))

	assert_eq(attacker.cell, before_cell)
	assert_almost_eq(attacker.orientation, before_orientation, 0.0001)
	assert_eq(attacker.ap, before_ap)
	assert_eq(attacker.shell.root.hp, before_hp)


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


## A real, reported bug — a deeper root cause of "jump to target then
## back, then slide": a unit whose own turn was `[faced(X), move,
## faced(Y final)]` (turn to face X, walk, turn to face Y) used to have
## its FIRST faced(X) event read `_display_orientation.get(id, X)` — X
## itself, the fallback, since nothing had ever WRITTEN the dict yet —
## and silently, instantly "snap" with no visible transition at all (its
## own "from" trivially equalled its own target). The SLIDE that followed
## then read that same now-stale dict value and rendered the WHOLE walk
## turned to X, producing a sudden, simultaneous position-and-rotation
## pop the instant the slide started. _prime() must never let a facing
## event's own fallback default become the value everything downstream
## reads — it must seed the unit's own current (final) orientation up
## front, regardless of what any individual event's own target happens to
## be.
func test_prime_never_uses_a_facing_events_own_target_as_its_fallback_default() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	attacker.orientation = 2.5
	var events: Array[LogEvent] = [_faced_event(attacker, 1.0)]

	player._prime(events)

	assert_almost_eq(
		player._display_orientation[attacker.id],
		2.5,
		0.0001,
		"priming must default to the unit's own current orientation, never the event's own target"
	)


## taskblock-21 Pass G: a second, narrower priming bug in the same family
## as the one above — a unit's FIRST-EVER animated turn whose FIRST move
## needed no preceding faced event at all (it already happened to be
## facing that way, e.g. straight off a fresh spawn orientation) BUT whose
## SAME turn re-faces again LATER (an attack, a step-out's own return leg)
## used to prime `_display_orientation` from `unit.orientation` — by
## `_prime()`'s own call time, resolution has already fully finished, so
## that's the turn's FINAL orientation, not what the unit was actually
## facing during the move nobody logged a `faced` event for. `_play_slide`
## then read that same wrong, too-late value for its whole traversal,
## visibly sliding the unit toward its move's real destination while
## facing wherever it ended up turning to LATER instead — "leaving the
## unit facing its prior direction while it slides." A move event exists
## here, so priming must derive the move's own actual direction
## (`orientation_toward(path[0], path[1])`) instead of falling through to
## the too-late `unit.orientation` — mirrors `_display_cell`'s own
## existing `path[0]` fix one function up, just for orientation.
func test_prime_derives_a_moves_own_direction_when_no_facing_event_preceded_it() -> void:
	var built: Dictionary = _setup_player()
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	assert_almost_eq(
		attacker.orientation, 0.0, 0.0001, "sanity: a fresh unit's own default orientation"
	)
	var start_cell: Vector2i = attacker.cell
	var moved_to := Vector2i(start_cell.x, start_cell.y + 1)
	var move_direction: float = FaceAction.orientation_toward(start_cell, moved_to)
	assert_almost_eq(
		move_direction,
		0.0,
		0.0001,
		"sanity: this move needs no re-face at all from the default orientation"
	)
	# Simulates the real post-resolution state: the SAME turn moved south
	# with no re-face, then fired east, re-facing again — attacker.orientation
	# is already the FINAL value by the time _prime() ever runs.
	attacker.orientation = PI / 2.0
	var events: Array[LogEvent] = [
		_move_event(attacker, [start_cell, moved_to]), _faced_event(attacker, PI / 2.0)
	]

	player._prime(events)

	assert_almost_eq(
		player._display_orientation[attacker.id],
		move_direction,
		0.0001,
		"must prime from the move's own direction, not the turn's later, unrelated final facing"
	)


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
