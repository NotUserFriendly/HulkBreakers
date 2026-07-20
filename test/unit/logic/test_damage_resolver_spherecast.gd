extends GutTest

## taskblock-25 Pass D (docs/PLAN.md "Phase M — Melee"): the same
## gap-threading claim test_shot_plane.gd proves at the `resolve_projectile`
## level, proven again through the real `DamageResolver.resolve_shot` path
## `StabAction` actually calls — a real two-blocker gap in a real grid, not
## a hand-built plane.


func _wall(id: StringName) -> Part:
	var wall := Part.new()
	wall.id = id
	wall.material = &"steel"
	wall.hp = 30
	wall.max_hp = 30
	wall.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.9, 1.0, 0.6))]
	return wall


## Two blockers one cell apart leave a real 0.1-wide gap between their own
## projected boxes, centered at world lateral x=0.5 (worked out from
## ShotPlane's own `_offset` math — see the fixture's own comment below).
func _gapped_grid() -> Grid:
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(4, 5)] = _wall(&"left_wall")
	grid.blockers[Vector2i(5, 5)] = _wall(&"right_wall")
	return grid


func test_a_point_stab_falls_through_the_gap_and_hits_nothing() -> void:
	var state := CombatState.new(_gapped_grid())
	var table := DataLibrary.material_table()
	var origin := Vector2(5, 0)
	var direction := Vector2(0, 1)
	# x=0.5, the gap's own center (right_wall spans -0.45..0.45, left_wall
	# spans 0.55..1.45).
	var point := Vector2(0.5, 0.5)

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, point, 5.0, 0.0, state, table, RandomNumberGenerator.new()
	)

	assert_eq(results.size(), 0, "a point-radius stab must fall clean through the gap")


func test_a_wide_stab_cannot_thread_the_same_gap() -> void:
	var state := CombatState.new(_gapped_grid())
	var table := DataLibrary.material_table()
	var origin := Vector2(5, 0)
	var direction := Vector2(0, 1)
	var point := Vector2(0.5, 0.5)

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin,
		direction,
		point,
		5.0,
		0.0,
		state,
		table,
		RandomNumberGenerator.new(),
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		[],
		0.0,
		0.0,
		0.0,
		DamageResolver.DEFLECT_MODE_SLIDE,
		0.08
	)

	assert_gt(results.size(), 0, "a disc wider than the gap must catch on one of the walls")


func test_a_narrow_stab_still_threads_the_same_gap() -> void:
	var state := CombatState.new(_gapped_grid())
	var table := DataLibrary.material_table()
	var origin := Vector2(5, 0)
	var direction := Vector2(0, 1)
	var point := Vector2(0.5, 0.5)

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin,
		direction,
		point,
		5.0,
		0.0,
		state,
		table,
		RandomNumberGenerator.new(),
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		[],
		0.0,
		0.0,
		0.0,
		DamageResolver.DEFLECT_MODE_SLIDE,
		0.03
	)

	assert_eq(results.size(), 0, "a stiletto-width disc must still fit through the same gap")
