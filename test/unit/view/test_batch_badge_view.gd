extends GutTest

## taskblock-43 Pass C: the board indicator for batched units — "without this the
## next pass is unverifiable by eye."
##
## The split under test: `BatchPlan.badge_for` decides WHAT the badge says (a
## pure string, tested headlessly in `test_batch_plumbing.gd`, because CC cannot
## see the screen), and this side only draws whatever string it is handed. So
## these cases are about the node — that it appears, disappears, survives a
## rebuild, and lands in the same place on both refresh paths — never about the
## text's meaning.


func _piloted_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	torso.sockets = [Socket.new(&"MATRIX")]
	torso.dock_matrix(Matrix.new())
	return Unit.new(torso.hosted_matrix, Shell.new(torso), cell, squad)


func _view_for(unit: Unit) -> HitVolumeView:
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	return view


func _badges(view: HitVolumeView) -> Array[Label3D]:
	var found: Array[Label3D] = []
	for child: Node in view.get_children():
		if child is Label3D:
			found.append(child as Label3D)
	return found


## The overwhelmingly common case, and the one that must look exactly as it did
## before this pass existed.
func test_an_unbatched_unit_draws_no_badge_node_at_all() -> void:
	var view: HitVolumeView = _view_for(_piloted_unit(Vector2i(1, 1)))
	var before: int = view.get_child_count()

	view.set_batch_badge("")

	assert_eq(_badges(view).size(), 0)
	assert_eq(view.get_child_count(), before, "an empty badge adds nothing")


func test_a_badge_draws_the_text_it_was_handed() -> void:
	var view: HitVolumeView = _view_for(_piloted_unit(Vector2i(1, 1)))

	view.set_batch_badge("B2*")

	var badges: Array[Label3D] = _badges(view)
	assert_eq(badges.size(), 1)
	assert_eq(badges[0].text, "B2*")


func test_clearing_the_badge_removes_the_node() -> void:
	var view: HitVolumeView = _view_for(_piloted_unit(Vector2i(1, 1)))
	view.set_batch_badge("B2")

	view.set_batch_badge("")

	assert_eq(_badges(view).size(), 0)


## `refresh()` tears down every child, so without deliberate restoration a badge
## would silently vanish the first time its unit took damage — reading as "this
## unit left its batch" rather than as a redraw.
func test_the_badge_survives_a_full_rebuild() -> void:
	var unit: Unit = _piloted_unit(Vector2i(1, 1))
	var view: HitVolumeView = _view_for(unit)
	view.set_batch_badge("B4")

	view.refresh()

	var badges: Array[Label3D] = _badges(view)
	assert_eq(badges.size(), 1, "still exactly one")
	assert_eq(badges[0].text, "B4")


func test_the_badge_follows_the_unit_on_a_cheap_refresh() -> void:
	var unit: Unit = _piloted_unit(Vector2i(1, 1))
	var view: HitVolumeView = _view_for(unit)
	view.set_batch_badge("B4")
	var before: Vector3 = _badges(view)[0].position

	unit.cell = Vector2i(6, 2)
	assert_true(view.refresh_transforms(), "sanity: the cheap path ran")

	var after: Vector3 = _badges(view)[0].position
	assert_ne(after, before, "the badge carries a world transform like the ground markers")
	assert_almost_eq(after.x, 6.0 * UnitGeometry.CELL_SIZE, 0.001)
	assert_almost_eq(after.z, 2.0 * UnitGeometry.CELL_SIZE, 0.001)


## The reason `_rebuild_batch_badge` bothers with `move_child` at all: the cheap
## refresh appends, the full rebuild inserts, and `test_hit_volume_view_refresh`
## pins that the two paths leave an identical node list. A badge landing at a
## different index in each would break that identity without changing anything a
## viewer could see.
func test_both_refresh_paths_place_the_badge_at_the_same_index() -> void:
	var moved: Unit = _piloted_unit(Vector2i(1, 1))
	var cheap: HitVolumeView = _view_for(moved)
	cheap.set_batch_badge("B4")
	moved.cell = Vector2i(6, 2)
	assert_true(cheap.refresh_transforms())

	var full: HitVolumeView = _view_for(_piloted_unit(Vector2i(6, 2)))
	full.set_batch_badge("B4")

	assert_eq(
		_child_class_names(cheap), _child_class_names(full), "same node kinds in the same order"
	)


func _child_class_names(view: HitVolumeView) -> Array[String]:
	var names: Array[String] = []
	for child: Node in view.get_children():
		names.append(child.get_class())
	return names


## End to end through the real scene: a batch assigned by the debug verb shows up
## on the board without anything else having to be told about it.
func test_the_scene_pushes_badges_for_whatever_the_state_says() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var state: CombatState = scene.combat_state
	var first: Unit = state.units[0]
	BoutInjector.new(state).set_batch(first, 3)
	state.batch_plans.record(3, state.round_number, first.id, first.cell)

	scene.apply_batch_badges()

	for view: HitVolumeView in scene.unit_views:
		var badges: Array[Label3D] = _badges(view)
		if view.unit == first:
			assert_eq(badges.size(), 1, "the batched unit is badged")
			assert_eq(badges[0].text, "B3*", "and it is the one leading")
		else:
			assert_eq(badges.size(), 0, "every other unit is independent and unmarked")
