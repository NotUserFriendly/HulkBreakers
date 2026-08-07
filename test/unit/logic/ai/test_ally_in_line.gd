extends GutTest

## tb61 Pass A (`BR52.10`): **an AI unit does not shoot through its own squadmate.**
##
## Reproduced from a real bout before this landed: unit 4 at `(20,5)` and unit 3 at `(19,5)` are
## squadmates in a line; unit 4 fired a twelve-round chaingun burst at `(12,3)` and **eight
## consecutive pulls resolved on unit 3**, destroying its torso and ejecting its matrix on turn
## zero. One AI unit removed a third of its own squad before anything else moved.
##
## **The geometry was never wrong.** Every one of those impacts logged `origin == hit` at zero
## distance, because a chaingun's muzzle tip sits 0.85 forward of the grip and the ally's body
## boxes start half a cell away — the ray legitimately began inside the ally. **The decision to
## fire is what was wrong.**
##
## **A regression, not a gap that was always there.** The retired branch planner refused this and
## logged `held: ally_in_line`; `BR35.05` records a real bout doing so. The check went with the
## planner in the taskblock-45 rewrite and nothing replaced it: `_lof_possible` was a
## `VisibilityField` test, so it saw terrain and opacity and no units at all.


func _unit(cell: Vector2i, squad: int) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 20
	torso.max_hp = 20
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.8, 1.0, 0.4))]
	# Ids are assigned by `CombatState.add_unit`; nothing here reads one.
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## Shooter, ally and enemy in a straight line: shooter at x=20, ally at x=19, enemy at x=12,
## which is `BR52.10`'s own geometry with the row flattened.
func _context(with_ally: bool) -> UtilityContext:
	var grid := GridFixture.flat(24, 12)
	var shooter: Unit = _unit(Vector2i(20, 5), 0)
	var enemy: Unit = _unit(Vector2i(12, 5), 1)
	var units: Array[Unit] = [shooter, enemy]
	if with_ally:
		units.append(_unit(Vector2i(19, 5), 0))
	var state := CombatState.new(grid, units)
	return UtilityContext.build(shooter, WorldView.full(state))


## **The claim, stated as the thing the player saw.** With a squadmate between the shooter and
## its target, the line of fire is not possible from that cell — and because `line_of_fire` is a
## consideration on `shoot.tres` and `UtilityScorer`'s product model preserves a zero at every
## `n`, that is a veto on shooting from there rather than a discount.
func test_a_squadmate_in_the_line_blocks_the_line_of_fire() -> void:
	var clear: UtilityContext = _context(false)
	var blocked: UtilityContext = _context(true)

	var clear_inputs: Dictionary = clear.inputs_for(Vector2i(20, 5))
	var blocked_inputs: Dictionary = blocked.inputs_for(Vector2i(20, 5))
	gut.p(
		(
			"line_of_fire: no ally %.1f, ally at (19,5) %.1f"
			% [
				float(clear_inputs[UtilityContext.INPUT_LINE_OF_FIRE]),
				float(blocked_inputs[UtilityContext.INPUT_LINE_OF_FIRE])
			]
		)
	)

	assert_almost_eq(
		float(clear_inputs[UtilityContext.INPUT_LINE_OF_FIRE]),
		1.0,
		0.0001,
		"sanity: with nothing in the way the line of fire is open"
	)
	assert_almost_eq(
		float(blocked_inputs[UtilityContext.INPUT_LINE_OF_FIRE]),
		0.0,
		0.0001,
		"a squadmate standing in the line closes it — this is the assertion BR52.10 needed"
	)


## And the predicate agrees, because both read one function. `hold_position.tres` preconditions on
## `lof_blocked`, so a unit that cannot shoot past its own squad has somewhere to go.
func test_the_blocked_predicate_agrees_with_the_input() -> void:
	var blocked: UtilityContext = _context(true)
	var predicates: Dictionary = blocked.predicates_for(Vector2i(20, 5))

	assert_true(
		bool(predicates[UtilityContext.PRED_LOF_BLOCKED]),
		"lof_blocked must be true when an ally is in the way, or hold_position cannot fire"
	)
	assert_false(bool(predicates[UtilityContext.PRED_LOF_POSSIBLE]))


## **An ENEMY in the line does not block it**, which is the boundary that keeps this from being a
## blanket "any unit in the way" rule. Shooting through an enemy to reach another is a legitimate
## thing the plane and the ray both model, and `docs/02`'s layered-targets section is explicit
## that a round threading past one target into another is the same code path.
func test_an_enemy_in_the_line_does_not_block_it() -> void:
	var grid := GridFixture.flat(24, 12)
	var shooter: Unit = _unit(Vector2i(20, 5), 0)
	var blocker: Unit = _unit(Vector2i(19, 5), 1)
	var enemy: Unit = _unit(Vector2i(12, 5), 1)
	var state := CombatState.new(grid, [shooter, blocker, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(shooter, WorldView.full(state))

	var inputs: Dictionary = context.inputs_for(Vector2i(20, 5))
	assert_almost_eq(
		float(inputs[UtilityContext.INPUT_LINE_OF_FIRE]),
		1.0,
		0.0001,
		"an enemy in the way is a target, not an obstruction — only squadmates close the line"
	)


## **A squadmate off the line does not block it**, so this is a line test and not "an ally exists
## somewhere". Without this the fix would read as correct while vetoing every shot on any board
## with two friendly units on it.
func test_a_squadmate_beside_the_line_does_not_block_it() -> void:
	var grid := GridFixture.flat(24, 12)
	var shooter: Unit = _unit(Vector2i(20, 5), 0)
	var ally: Unit = _unit(Vector2i(19, 9), 0)
	var enemy: Unit = _unit(Vector2i(12, 5), 1)
	var state := CombatState.new(grid, [shooter, ally, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(shooter, WorldView.full(state))

	var inputs: Dictionary = context.inputs_for(Vector2i(20, 5))
	assert_almost_eq(
		float(inputs[UtilityContext.INPUT_LINE_OF_FIRE]),
		1.0,
		0.0001,
		"an ally four rows off the firing line is not in it"
	)


## **A dead squadmate does not block it.** A downed shell is scenery a round goes through, and
## treating a corpse as a reason not to shoot would make a squad wipe itself into paralysis.
func test_a_dead_squadmate_does_not_block_the_line() -> void:
	var grid := GridFixture.flat(24, 12)
	var shooter: Unit = _unit(Vector2i(20, 5), 0)
	var corpse: Unit = _unit(Vector2i(19, 5), 0)
	corpse.alive = false
	var enemy: Unit = _unit(Vector2i(12, 5), 1)
	var state := CombatState.new(grid, [shooter, corpse, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(shooter, WorldView.full(state))

	var inputs: Dictionary = context.inputs_for(Vector2i(20, 5))
	assert_almost_eq(
		float(inputs[UtilityContext.INPUT_LINE_OF_FIRE]), 1.0, 0.0001, "a corpse is not cover"
	)
