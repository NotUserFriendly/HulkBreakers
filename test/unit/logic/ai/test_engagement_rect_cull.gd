extends GutTest

## taskblock-43 Pass B: `_pick_engagement_position` scores the reachable cells
## inside a rectangle spanned by the acting unit and its target, instead of every
## cell `Pathfinder.reachable` returns.
##
## **Unlike Pass A this is NOT identical output**, so there is no equivalence
## test to write here and the acceptance is behavioural instead: the full-mission
## completion canary holds (`test_full_mission.gd`), and the rate at which the
## chosen cell actually changes is measured over a seed sweep by
## `tools/bench_ai_planning.gd` and reported rather than asserted — a rate
## pinned by a handful of in-suite bouts would be noise wearing a threshold.
##
## What IS pinned here is the geometry, and specifically the two ways the cull
## could be quietly wrong while every behavioural check still passed: losing the
## unit's own cell (several branches in `_plan_ranged` are gated on
## `best_cell == unit.cell`), and losing the cells BEHIND a long-range unit that
## wants to back off — the asymmetric pad's whole reason to exist.


## Copied from test_unit_ai_engagement_lof.gd's own fixture rather than shared:
## the ranges below are what these cases are about, so they are authored here
## where a reader can see them.
func _armed_unit(
	id: StringName,
	cell: Vector2i,
	squad_id: int,
	min_range: float = 0.0,
	effective_range: float = 0.0
) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var weapon := Part.new()
	weapon.id = StringName("%s_gun" % id)
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = 1
	weapon.provides_actions = [&"shoot"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 20.0
	weapon.weapon_def.min_range = min_range
	weapon.weapon_def.effective_range = effective_range
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


## The block's own stated risk: "an optimisation quietly shoves long-range units
## into knife fights." A unit inside its weapon's minimum range wants to walk
## AWAY, and those cells sit behind it — outside a box drawn between it and the
## target, in the direction a symmetric pad is thinnest.
##
## Asserted on the SCORE of the two choices rather than on cell equality. Cell
## equality was the first version of this test and it failed for a reason worth
## recording: on open ground a whole arc of cells sits at exactly the standoff
## distance and therefore scores identically, so which one wins is decided by
## iteration order, and dropping any one of them changes the cell without
## changing the decision at all. Pinning the cell would have pinned that
## accident. What the pad actually has to guarantee — and what this asserts — is
## that the culled set still contains a cell as good as the best the full search
## could find. The distance assert keeps it from passing vacuously by proving the
## unit really is backing off rather than standing still.
func test_a_unit_inside_its_minimum_range_still_chooses_a_cell_behind_itself() -> void:
	var grid: Grid = GridFixture.flat(30, 24)
	var shooter: Unit = _armed_unit(&"marksman", Vector2i(16, 12), 0, 6.0, 8.0)
	var enemy: Unit = _armed_unit(&"target", Vector2i(18, 12), 1)
	var state := CombatState.new(grid, [shooter, enemy])
	var weapon: Part = shooter.shell.find_part(&"marksman_gun")

	var pf := Pathfinder.new(grid, shooter.shell.can_climb())
	var reachable: Array[Vector2i] = pf.reachable(shooter.cell, 8.0)
	var culled: Array[Vector2i] = EngagementRect.cull(
		shooter, enemy, UnitAI._target_distance(weapon, UnitAI.MARKSMAN_PREFERRED_RANGE), reachable
	)

	var full_choice: Vector2i = UnitAI._pick_engagement_position(
		shooter, enemy, state, UnitAI.MARKSMAN_PREFERRED_RANGE, false, weapon, reachable, true, {}
	)
	var culled_choice: Vector2i = UnitAI._pick_engagement_position(
		shooter, enemy, state, UnitAI.MARKSMAN_PREFERRED_RANGE, false, weapon, culled, true, {}
	)

	var full_score: float = UnitAI._engagement_score(
		full_choice, enemy, state, shooter, UnitAI.MARKSMAN_PREFERRED_RANGE, false, weapon
	)
	var culled_score: float = UnitAI._engagement_score(
		culled_choice, enemy, state, shooter, UnitAI.MARKSMAN_PREFERRED_RANGE, false, weapon
	)

	assert_almost_eq(
		culled_score, full_score, 0.0001, "the far-side pad kept a cell as good as the best one"
	)
	assert_gt(
		Grid.distance_chebyshev(culled_choice, enemy.cell),
		Grid.distance_chebyshev(shooter.cell, enemy.cell),
		"sanity: it is genuinely backing off, so the score match above is not vacuous"
	)


## `_pick_engagement_position` seeds `best_cell` with it, and `_plan_ranged`
## gates its step-out fallback on `best_cell == unit.cell` — losing it would
## break both silently.
func test_the_units_own_cell_survives_a_reachable_set_that_never_held_it() -> void:
	var grid: Grid = GridFixture.flat(30, 24)
	var shooter: Unit = _armed_unit(&"shooter", Vector2i(4, 4), 0)
	var enemy: Unit = _armed_unit(&"target", Vector2i(20, 18), 1)
	var weapon: Part = shooter.shell.find_part(&"shooter_gun")

	# Deliberately omits the unit's own cell — a direct caller's arbitrary set,
	# which is the only way this guard can ever be reached in practice.
	var reachable: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 6)]
	var culled: Array[Vector2i] = EngagementRect.cull(
		shooter, enemy, UnitAI._target_distance(weapon, 0), reachable
	)

	assert_true(culled.has(shooter.cell), "the standing fallback is always a candidate")


## The rect is drawn as a corner-to-corner box, so nothing on the straight walk
## between the two units can fall outside it — the case a naive "cells near the
## target" filter would get wrong on a diagonal.
func test_a_diagonally_distant_target_keeps_the_whole_direct_approach() -> void:
	var grid: Grid = GridFixture.flat(30, 24)
	var shooter: Unit = _armed_unit(&"shooter", Vector2i(2, 2), 0)
	var enemy: Unit = _armed_unit(&"target", Vector2i(24, 20), 1)
	var weapon: Part = shooter.shell.find_part(&"shooter_gun")

	var approach: Array[Vector2i] = Grid.line(shooter.cell, enemy.cell)
	var culled: Array[Vector2i] = EngagementRect.cull(
		shooter, enemy, UnitAI._target_distance(weapon, 0), approach
	)

	for cell: Vector2i in approach:
		assert_true(culled.has(cell), "the direct approach cell %s survives" % cell)


## Without this the tests above pass just as well for a cull that discards
## nothing at all — the same reason Pass A needed its skip-count assertion.
func test_the_cull_actually_discards_cells_off_to_the_side() -> void:
	var grid: Grid = GridFixture.flat(40, 40)
	var shooter: Unit = _armed_unit(&"shooter", Vector2i(20, 20), 0)
	var enemy: Unit = _armed_unit(&"target", Vector2i(26, 20), 1)
	var weapon: Part = shooter.shell.find_part(&"shooter_gun")

	# `preferred_range` 0 and no authored effective_range, so the far-side pad is
	# zero and only the lateral pad applies: y is kept within +/-2 of the shared
	# row, and x within [18, 28].
	var sideways := Vector2i(20, 30)
	var behind := Vector2i(14, 20)
	var reachable: Array[Vector2i] = [shooter.cell, sideways, behind, Vector2i(23, 21)]
	var culled: Array[Vector2i] = EngagementRect.cull(
		shooter, enemy, UnitAI._target_distance(weapon, 0), reachable
	)

	assert_false(culled.has(sideways), "10 cells off the axis is outside the lateral pad")
	assert_false(culled.has(behind), "with no preferred range there is no far-side pad to keep it")
	assert_true(culled.has(Vector2i(23, 21)), "a cell between the two, one off the line, is kept")


## The same cell as above, kept once the unit actually has a standoff to fall
## back to — the pad is a function of `_target_distance`, so a MARKSMAN and an
## AGGRESSIVE unit standing in the same place get different rectangles.
func test_the_far_side_pad_scales_with_the_units_own_preferred_range() -> void:
	var grid: Grid = GridFixture.flat(40, 40)
	var shooter: Unit = _armed_unit(&"shooter", Vector2i(20, 20), 0)
	var enemy: Unit = _armed_unit(&"target", Vector2i(26, 20), 1)
	var weapon: Part = shooter.shell.find_part(&"shooter_gun")

	var behind := Vector2i(14, 20)
	var reachable: Array[Vector2i] = [shooter.cell, behind]

	var aggressive: Array[Vector2i] = EngagementRect.cull(
		shooter,
		enemy,
		UnitAI._target_distance(weapon, UnitAI.AGGRESSIVE_PREFERRED_RANGE),
		reachable
	)
	var marksman: Array[Vector2i] = EngagementRect.cull(
		shooter, enemy, UnitAI._target_distance(weapon, UnitAI.MARKSMAN_PREFERRED_RANGE), reachable
	)

	assert_false(aggressive.has(behind), "AGGRESSIVE's own 0 leaves the far side unpadded")
	assert_true(marksman.has(behind), "MARKSMAN's own 7 reaches 6 cells behind the unit")


## An axis the two units share has no "away" direction along it at all, so it
## takes the lateral pad and nothing more — the degenerate case a per-axis sign
## has to get right rather than accidentally padding both ends.
func test_a_shared_axis_gets_only_the_lateral_pad() -> void:
	var grid: Grid = GridFixture.flat(40, 40)
	var shooter: Unit = _armed_unit(&"shooter", Vector2i(20, 20), 0)
	var enemy: Unit = _armed_unit(&"target", Vector2i(20, 26), 1)
	var weapon: Part = shooter.shell.find_part(&"shooter_gun")

	# x is shared, so the whole standoff pad goes into -y (behind the shooter).
	var far_along_x := Vector2i(26, 20)
	var behind := Vector2i(20, 15)
	var reachable: Array[Vector2i] = [shooter.cell, far_along_x, behind]
	var culled: Array[Vector2i] = EngagementRect.cull(
		shooter, enemy, UnitAI._target_distance(weapon, UnitAI.MARKSMAN_PREFERRED_RANGE), reachable
	)

	assert_false(culled.has(far_along_x), "the shared axis is lateral, padded by 2 and no more")
	assert_true(culled.has(behind), "the standoff pad extends away along the axis that has one")
