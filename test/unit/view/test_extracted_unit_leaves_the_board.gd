extends GutTest

## taskblock-64 Pass G — **`BR63.03`: an extracted unit is gone from the board, from targeting,
## and from the turn order.**
##
## The entry asks whether the unit is *also* still targetable and still taking turns, *"which
## would make it a gameplay defect rather than a drawing one."* **It was both**, and the first
## reading of this file said otherwise — targeting and cell occupancy did already exclude it, so
## "the model is fine, only the view is wrong" looked right until the turn-order case was
## actually run and reached the extracted unit.
##
## **Two independent causes, and the gameplay one is a reopened bug:**
##
## - `MissionState.extract_unit` set `alive = false` and cleared the cell **by hand** — the two
##   lines `CombatState.kill_unit` runs under a comment calling itself *"the one place a unit's
##   alive flag flips to false"*. It did not copy the third thing that function does: advance the
##   turn when the departing unit is the current one. So `_current_unit_id` pointed at someone who
##   had gone home and the turn never ended — **`BR51.04`/`BR51.05` reintroduced through a second
##   door**, selection included, since `SelectionController.select` requires
##   `unit == current_unit()`.
## - The view drew it because **every other way a unit stops participating destroys geometry**. A
##   killed unit's parts drop to `hp <= 0` and `BodyProjector.projects` refuses them, so it empties
##   out box by box with no view rule at all. Extraction destroys nothing, so `refresh()` faithfully
##   rebuilt a whole intact body.
##
## The model claims are asserted here beside the drawing one **on purpose** — the turn-order one is
## what caught the half nobody had looked at.


func _unit(id_hint: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id_hint)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.6, 1.0, 0.6))]
	var link := Matrix.new()
	link.id = StringName("%s_link" % id_hint)
	torso.hosted_matrix = link
	return Unit.new(link, Shell.new(torso), cell, squad_id)


func _mission(units: Array[Unit]) -> MissionState:
	var state := CombatState.new(GridFixture.flat(10, 10), units, 5)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(0, 0)]
	return mission


# --- the model, which the entry suspected and which is already correct --------


func test_an_extracted_unit_is_gone_from_the_turn_order() -> void:
	var leaver: Unit = _unit(&"leaver", Vector2i(2, 2), 0)
	var stayer: Unit = _unit(&"stayer", Vector2i(6, 6), 1)
	var mission: MissionState = _mission([leaver, stayer] as Array[Unit])

	mission.extract_unit(leaver)

	var seen_ids: Array[int] = []
	for _i in range(6):
		var current: Unit = mission.combat_state.current_unit()
		if current != null and not seen_ids.has(current.id):
			seen_ids.append(current.id)
		mission.combat_state.advance_turn()

	gut.p("  units reached by the turn order: %s" % str(seen_ids))
	assert_false(seen_ids.has(leaver.id), "an extracted unit must not be handed a turn")
	assert_true(seen_ids.has(stayer.id), "and the one still there must be, or this proves nothing")


func test_an_extracted_unit_is_gone_from_targeting() -> void:
	var leaver: Unit = _unit(&"leaver", Vector2i(2, 2), 0)
	var mission: MissionState = _mission([leaver] as Array[Unit])
	var state: CombatState = mission.combat_state
	var from := Vector3(-4.0, 0.5, 2.0)
	var direction := Vector3(1.0, 0.0, 0.0)

	var before: RayHit = RayCaster.cast(state, from, direction)
	assert_not_null(before, "the fixture is aimed at the unit while it is still standing there")

	mission.extract_unit(leaver)

	var after: RayHit = RayCaster.cast(state, from, direction)
	gut.p("  ray hit before extraction: %s, after: %s" % [before != null, after != null])
	assert_null(after, "a unit that has left the board is not something a round can meet")


func test_an_extracted_unit_no_longer_occupies_its_cell() -> void:
	var leaver: Unit = _unit(&"leaver", Vector2i(2, 2), 0)
	var mission: MissionState = _mission([leaver] as Array[Unit])
	assert_eq(
		mission.combat_state.grid.get_occupant_id(Vector2i(2, 2)), leaver.id, "standing there"
	)

	mission.extract_unit(leaver)

	assert_ne(
		mission.combat_state.grid.get_occupant_id(Vector2i(2, 2)),
		leaver.id,
		"and the cell is free once it has gone"
	)


# --- the drawing half, which is the actual defect ----------------------------


## **The defect.** Read off the real node's child count rather than a flag, because "is it drawn"
## is a question about the scene tree and a boolean would be a second opinion about it.
func test_an_extracted_units_view_draws_nothing() -> void:
	var leaver: Unit = _unit(&"leaver", Vector2i(2, 2), 0)
	var mission: MissionState = _mission([leaver] as Array[Unit])

	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(leaver, mission.combat_state.material_table)
	var drawn_before: int = view.get_child_count()
	gut.p("  child nodes while standing on the board: %d" % drawn_before)
	assert_gt(drawn_before, 0, "it is drawn to begin with, or the case below is vacuous")

	mission.extract_unit(leaver)
	view.refresh()

	gut.p("  child nodes after extracting: %d" % view.get_child_count())
	assert_eq(view.get_child_count(), 0, "a unit that has gone home is drawn as nothing")


## The cheap transform-only path must not keep it on screen either — an extracted unit's parts are
## all intact, so `refresh_transforms` would otherwise happily reuse the whole subtree.
func test_the_transform_only_path_refuses_an_extracted_unit() -> void:
	var leaver: Unit = _unit(&"leaver", Vector2i(2, 2), 0)
	var mission: MissionState = _mission([leaver] as Array[Unit])

	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(leaver, mission.combat_state.material_table)
	assert_true(view.refresh_transforms(), "the cheap path works while the unit is on the board")

	mission.extract_unit(leaver)

	assert_false(
		view.refresh_transforms(),
		"and refuses once it has left, so the caller falls through to a full rebuild"
	)


## **An inert shell is not an extracted one.** A unit whose matrix was ejected is `alive == false`
## with every part intact and is still lying on the floor — keying the rule on `alive` would erase
## wreckage the player can still shoot and strip.
func test_a_dead_but_unextracted_unit_is_still_drawn() -> void:
	var wreck: Unit = _unit(&"wreck", Vector2i(2, 2), 0)
	var mission: MissionState = _mission([wreck] as Array[Unit])

	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(wreck, mission.combat_state.material_table)

	wreck.alive = false
	view.refresh()

	gut.p("  child nodes for a dead-but-present unit: %d" % view.get_child_count())
	assert_gt(
		view.get_child_count(),
		0,
		"a shell with no matrix is still physically there and must keep drawing"
	)
