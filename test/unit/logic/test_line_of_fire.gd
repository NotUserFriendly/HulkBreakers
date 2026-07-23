extends GutTest

## tb33 Pass A: `LineOfFire` answers a different question than `LoS` — "would
## a shot from here actually hit the target," resolved against the same
## `ShotPlane` a real `AttackAction` fires through, not a second approximation
## of the geometry. These tests exercise the predicate directly; the AI-level
## consumers (fire gate, engagement scorer, approach fallback) have their own
## coverage in `test/unit/logic/ai/`.


func _standing_unit(id: StringName, half_width: float, cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(half_width * 2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func test_has_clear_line_of_fire_is_true_with_nothing_in_the_way() -> void:
	var grid := Grid.new(5, 6)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])

	assert_true(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))


## Same wall-part fixture `test_shot_plane.gd`'s own
## `test_a_wall_part_between_shooter_and_target_blocks_the_shot` uses (BR30.10:
## a real MapGen wall is a `grid.blockers` Part, not just opaque terrain).
func test_has_clear_line_of_fire_is_false_when_a_wall_blocks_the_shot() -> void:
	var grid := Grid.new(5, 6)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])
	grid.blockers[Vector2i(2, 2)] = DataLibrary.get_part(&"wall")

	assert_false(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))


## The predicate must never disagree with the real `ShotPlane`'s own resolved
## first hit — read the actual plane back, don't re-derive the ray math
## (docs/00's own standing rule for spatial systems, applied to a boolean
## predicate instead of a screen-space transform).
func test_has_clear_line_of_fire_matches_the_real_shotplanes_own_first_hit() -> void:
	var grid := Grid.new(5, 6)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])
	grid.blockers[Vector2i(2, 2)] = DataLibrary.get_part(&"wall")

	var direction := Vector2(target.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(
		Vector2(shooter.cell.x, shooter.cell.y), direction.normalized(), state
	)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target)
	var real_hit: Region = ShotPlane.resolve_projectile(plane, aim_point, shooter.shell.all_parts())

	assert_eq(
		LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state),
		real_hit != null and real_hit.body == target,
		"the predicate must agree with the real plane's own first hit, wall included"
	)
	assert_eq(real_hit.part.id, &"wall", "sanity: the real plane really does resolve to the wall")


## Regression: with nothing but open terrain, LOF and LOS must agree exactly
## (they're the same claim once no cover geometry is involved) — the AI's
## swap from LOS to LOF must not change behavior in the common open-field case.
func test_open_field_line_of_fire_matches_line_of_sight() -> void:
	var grid := Grid.new(10, 10)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(0, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(9, 9))
	var state := CombatState.new(grid, [shooter, target])

	assert_eq(
		LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state),
		LoS.has_los(grid, shooter.cell, target.cell)
	)


## tb35 Pass B (BR34.06/BR27.02): reconstructs the logged failure — a real
## target straight ahead, plus a wall several cells BEHIND the shooter
## (present in the plane on purpose, `ShotPlane.build`'s own doc comment).
## Unfloored, the rearward wall's negative depth sorted first and won every
## time; `_first_hit_excluding`'s floor must resolve forward instead.
func test_first_hit_never_resolves_to_a_wall_behind_the_shooter() -> void:
	var grid := Grid.new(10, 10)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(5, 5))
	var target := _standing_unit(&"target", 0.5, Vector2i(5, 9))
	var state := CombatState.new(grid, [shooter, target])
	grid.blockers[Vector2i(5, 1)] = DataLibrary.get_part(&"wall")

	var hit: Region = LineOfFire.first_hit(shooter, target, shooter.cell, state)

	assert_not_null(hit, "a wall behind the shooter must never eclipse a real forward target")
	assert_eq(hit.body, target)
	assert_true(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))


## tb35 Pass B (BR34.06): `approach_path` gives up once nothing is within its
## own weapon-range-plus-margin cap; `closing_path` is the fallback for a
## unit that starts genuinely far from any LOF cell — real A* toward the
## enemy, no LOF requirement, so it still makes progress instead of holding.
func test_closing_path_makes_progress_toward_a_far_off_enemy() -> void:
	var grid := Grid.new(30, 5)
	var unit := _standing_unit(&"unit", 0.5, Vector2i(0, 2))
	var enemy := _standing_unit(&"enemy", 0.5, Vector2i(29, 2))
	var state := CombatState.new(grid, [unit, enemy])
	var pf := Pathfinder.new(state.grid, state.terrain_costs)

	var path: Array[Vector2i] = LineOfFire.closing_path(unit, enemy, state, pf, 5.0)

	assert_gte(path.size(), 2, "must queue at least one real step")
	var end_cell: Vector2i = path[path.size() - 1]
	assert_lt(
		Grid.distance_chebyshev(end_cell, enemy.cell),
		Grid.distance_chebyshev(unit.cell, enemy.cell),
		"the truncated path must actually close distance"
	)


## Real A* routes around an obstacle rather than getting stuck the instant
## no reachable cell reduces raw distance further — the exact BR32.10
## concave/U-shaped-wall freeze a greedy per-turn distance scorer hits.
func test_closing_path_routes_around_a_concave_wall_instead_of_freezing() -> void:
	var grid := Grid.new(12, 12)
	for y in range(10):
		grid.set_terrain(Vector2i(5, y), Enums.TerrainType.WALL)
		grid.blockers[Vector2i(5, y)] = DataLibrary.get_part(&"wall")
	var unit := _standing_unit(&"unit", 0.5, Vector2i(0, 0))
	var enemy := _standing_unit(&"enemy", 0.5, Vector2i(9, 0))
	var state := CombatState.new(grid, [unit, enemy])
	var pf := Pathfinder.new(state.grid, state.terrain_costs)

	var path: Array[Vector2i] = LineOfFire.closing_path(unit, enemy, state, pf, 20.0)

	assert_gte(
		path.size(), 2, "a route around the wall's own gap (y=10-11) exists and must be found"
	)
