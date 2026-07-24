extends GutTest

## taskblock-37 Pass E: "the view reads unit.level" — split out of
## test_resolution_player.gd purely to stay under gdlint's max-public-
## methods (same convention test_hit_volume_view_render_primitive.gd/
## _weapon_labels.gd/_mesh_scene.gd already use). Same fixture/setup shape
## as that file's own `_setup_player`, just with a grid the test can raise
## BEFORE `CombatState.new` syncs `Unit.level`/`Unit.height` from it.


func _make_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	return Unit.new(Matrix.new(), Shell.new(root), cell)


func _setup_player(grid: Grid) -> Dictionary:
	var attacker := _make_unit(Vector2i(0, 0))
	var target := _make_unit(Vector2i(3, 0))
	var state := CombatState.new(grid, [attacker, target])
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]

	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)

	var player := ResolutionPlayer.new()
	add_child_autofree(player)
	player.setup(battle)
	return {"attacker": attacker, "target": target, "state": state, "player": player}


## taskblock-37 Pass E: mirrors `ClimbAction`/`HopDownAction`'s own logged
## `"path"` shape — the whole point being that `ResolutionPlayer` needs no
## dedicated vertical-slide code, just to route these two kinds through
## the same `_play_slide` a `move` event already uses.
func _climbed_event(unit: Unit, path: Array[Vector2i]) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		unit.id,
		&"climbed",
		{"cell": path[path.size() - 1], "rise": 1.0, "cost": 4.0, "path": path},
		"climbed to %s" % path[path.size() - 1]
	)


func _hopped_down_event(unit: Unit, path: Array[Vector2i]) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		unit.id,
		&"hopped_down",
		{"cell": path[path.size() - 1], "cost": 1.0, "path": path},
		"hopped down to %s" % path[path.size() - 1]
	)


## taskblock-37 Pass E: `_world_anchor` used to hardcode `y == 0.0` —
## every slide/turn pivot assumed world ground level regardless of the
## cell's own real elevation. Now delegates to the same canonical height
## source (`UnitGeometry.true_height_for_cell`) `UnitGeometry.placements`
## itself already uses to bake a unit's real mesh position, so "the
## anchor a slide pivots/ends on" and "where the body actually is" can
## never drift apart.
func test_world_anchor_reads_the_cells_own_real_height() -> void:
	var grid := Grid.new(10, 10)
	grid.set_level(Vector2i(3, 4), 2)
	var built: Dictionary = _setup_player(grid)
	var player: ResolutionPlayer = built.player

	var anchor: Vector3 = player._world_anchor(Vector2i(3, 4))

	assert_almost_eq(
		anchor.y,
		UnitGeometry.true_height_for_cell(Vector2i(3, 4), grid),
		0.0001,
		"the anchor's own height must come from the same source real placements use"
	)
	assert_almost_eq(anchor.x, 3.0 * UnitGeometry.CELL_SIZE, 0.0001)
	assert_almost_eq(anchor.z, 4.0 * UnitGeometry.CELL_SIZE, 0.0001)


## taskblock-37 Pass E: `ClimbAction`/`HopDownAction` log the same `path`
## shape a `move` event does specifically so `_play_event` can route both
## through the exact same `_play_slide` — proven directly: a zero-duration
## climb visits every path cell and ends flush, same invariant
## test_resolution_player.gd's own plain-move test uses, now exercised
## through a real `&"climbed"` event kind instead of a hand-called
## `_play_slide`.
func test_a_zero_duration_climb_event_plays_as_a_real_slide() -> void:
	var grid := Grid.new(10, 10)
	grid.set_level(Vector2i(1, 1), 1)
	var built: Dictionary = _setup_player(grid)
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	player.slide_ms = 0.0
	var view: HitVolumeView = player._view_for(attacker.id)
	attacker.cell = Vector2i(1, 1)
	attacker.level = grid.get_level(attacker.cell)
	attacker.height = UnitGeometry.true_height_for_cell(attacker.cell, grid)

	player._play_event(_climbed_event(attacker, [Vector2i(0, 0), Vector2i(1, 1)]))

	assert_eq(
		view.position, Vector3.ZERO, "a real climbed event must reach _play_slide, not fall through"
	)


## Same proof for `hopped_down`, the mirror action.
func test_a_zero_duration_hop_down_event_plays_as_a_real_slide() -> void:
	var grid := Grid.new(10, 10)
	grid.set_level(Vector2i(0, 0), 1)
	var built: Dictionary = _setup_player(grid)
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	player.slide_ms = 0.0
	var view: HitVolumeView = player._view_for(attacker.id)
	attacker.cell = Vector2i(1, 1)
	attacker.level = grid.get_level(attacker.cell)
	attacker.height = UnitGeometry.true_height_for_cell(attacker.cell, grid)

	player._play_event(_hopped_down_event(attacker, [Vector2i(0, 0), Vector2i(1, 1)]))

	assert_eq(
		view.position,
		Vector3.ZERO,
		"a real hopped_down event must reach _play_slide, not fall through"
	)


## taskblock-37 Pass E: mirrors test_resolution_player.gd's own
## `test_prime_shows_the_old_state_immediately`, through a real climb
## instead of a real move — `_prime` must treat `climbed`/`hopped_down`
## as priming-relevant too, or a climbing unit's own display record never
## seeds to its real pre-climb position and the vertical slide has
## nothing to animate FROM. Asserts only the Y component: a
## `Basis(Vector3.UP, angle)` rotation (whatever facing change also
## primed) never changes a vector's own Y, so this isolates the height
## claim specifically from any incidental X/Z turn.
func test_priming_a_climb_shows_the_old_height_not_the_already_baked_final_one() -> void:
	var grid := Grid.new(10, 10)
	grid.set_level(Vector2i(1, 1), 2)
	var built: Dictionary = _setup_player(grid)
	var player: ResolutionPlayer = built.player
	var attacker: Unit = built.attacker
	attacker.cell = Vector2i(1, 1)
	attacker.level = grid.get_level(attacker.cell)
	attacker.height = UnitGeometry.true_height_for_cell(attacker.cell, grid)
	var view: HitVolumeView = player._view_for(attacker.id)

	player._prime([_climbed_event(attacker, [Vector2i(0, 0), attacker.cell])])

	assert_almost_eq(
		view.position.y,
		-2.0 * UnitGeometry.LEVEL_HEIGHT,
		0.01,
		"priming a climb must show the OLD (pre-climb) height, not the already-baked final one"
	)
