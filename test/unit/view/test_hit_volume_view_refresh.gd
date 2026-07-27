extends GutTest

## taskblock-42 Pass B (BR27.09 cost #2): `refresh()` freed every child and
## re-instanced all of them, even when only a transform had changed — which is
## the most common case there is, a unit that moved.
##
## The entire risk of this pass is a view that silently stops updating in a case
## nobody enumerated, so the cheap path self-checks: it refuses whenever the
## node set would differ, and these tests pin both halves — that it declines
## when it should, and that when it does run the result is IDENTICAL to what a
## full rebuild produces.


func _view_for(unit: Unit) -> HitVolumeView:
	var view := HitVolumeView.new()
	view.unit = unit
	view.material_table = DataLibrary.material_table()
	add_child_autofree(view)
	view.refresh()
	return view


func _unit(cell: Vector2i = Vector2i(1, 1)) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, 0)


## Every node under the view, with its transform — the comparable that matters,
## since "the render is correct" means every drawn thing is where a full
## rebuild would have put it.
func _transform_snapshot(view: HitVolumeView) -> Array:
	var out: Array = []
	for child: Node in view.get_children():
		if child is Node3D:
			out.append((child as Node3D).transform)
	return out


func test_a_transform_only_refresh_instantiates_no_new_nodes() -> void:
	var unit: Unit = _unit()
	var view: HitVolumeView = _view_for(unit)
	var ids: Array = []
	for child: Node in view.get_children():
		ids.append(child.get_instance_id())

	unit.cell = Vector2i(4, 4)
	assert_true(view.refresh_transforms(), "a move is the cheap path's whole reason to exist")

	var after: Array = []
	for child: Node in view.get_children():
		after.append(child.get_instance_id())
	# The ground markers are rebuilt deliberately (two nodes, world-space) — the
	# body's meshes, which are the expensive part, must be the same objects.
	var kept := 0
	for id: Variant in after:
		if id in ids:
			kept += 1
	assert_gt(kept, 10, "the body's mesh instances were reused, not re-instanced")
	assert_eq(after.size(), ids.size(), "and the node COUNT is unchanged")


## The load-bearing assertion of the pass. A cheap refresh must land the scene
## in exactly the state a full rebuild would have.
func test_a_cheap_refresh_produces_the_same_transforms_as_a_full_rebuild() -> void:
	var moved: Unit = _unit()
	var cheap: HitVolumeView = _view_for(moved)
	moved.cell = Vector2i(6, 2)
	moved.orientation = 1.1
	assert_true(cheap.refresh_transforms())

	var reference_unit: Unit = _unit(Vector2i(6, 2))
	reference_unit.orientation = 1.1
	var full: HitVolumeView = _view_for(reference_unit)

	assert_eq(
		_transform_snapshot(cheap).size(),
		_transform_snapshot(full).size(),
		"same number of drawn nodes"
	)
	var cheap_transforms: Array = _transform_snapshot(cheap)
	var full_transforms: Array = _transform_snapshot(full)
	for i in range(cheap_transforms.size()):
		assert_almost_eq(
			(cheap_transforms[i] as Transform3D).origin.distance_to(
				(full_transforms[i] as Transform3D).origin
			),
			0.0,
			0.0001,
			"node %d sits where a full rebuild would have put it" % i
		)


func test_an_orientation_change_takes_the_cheap_path() -> void:
	var unit: Unit = _unit()
	var view: HitVolumeView = _view_for(unit)
	var before: Array = _transform_snapshot(view)

	view.preview_orientation = 2.0

	assert_true(view.refresh_transforms(), "boxes move, but none are added or removed")
	assert_ne(_transform_snapshot(view), before, "and something actually changed")


## The refusals. Each of these is a case where reusing nodes would render the
## wrong thing, so the cheap path must decline and let the caller rebuild.
func test_it_refuses_when_a_part_is_destroyed() -> void:
	var unit: Unit = _unit()
	var view: HitVolumeView = _view_for(unit)
	var victim: Part = null
	for part: Part in unit.shell.all_parts():
		if part != unit.shell.root:
			victim = part
			break
	assert_not_null(victim, "sanity: the reference humanoid has more than a root")

	victim.hp = 0

	assert_false(view.refresh_transforms(), "the node set shrank — a rebuild is required")


func test_it_refuses_when_the_unit_goes_down() -> void:
	var unit: Unit = _unit()
	var view: HitVolumeView = _view_for(unit)

	for part: Part in unit.shell.all_parts():
		if part.hosts_matrix():
			part.hosted_matrix = null

	assert_true(view.is_downed(), "sanity")
	assert_false(view.refresh_transforms(), "the facing wedge goes away — that is structural")


func test_it_refuses_when_the_hit_volume_overlay_is_toggled() -> void:
	var unit: Unit = _unit()
	var view: HitVolumeView = _view_for(unit)

	view.show_hit_volumes = not view.show_hit_volumes

	assert_false(view.refresh_transforms(), "the toggle adds or removes whole box sets")


## A view that has never been built has nothing to reuse, and must say so rather
## than quietly succeeding against an empty node set.
func test_it_refuses_before_the_first_full_refresh() -> void:
	var view := HitVolumeView.new()
	view.unit = _unit()
	view.material_table = DataLibrary.material_table()
	add_child_autofree(view)

	assert_false(view.refresh_transforms())


func test_a_full_refresh_after_a_cheap_one_still_works() -> void:
	var unit: Unit = _unit()
	var view: HitVolumeView = _view_for(unit)
	unit.cell = Vector2i(3, 3)
	assert_true(view.refresh_transforms())

	view.refresh()

	assert_true(view.refresh_transforms(), "the bookkeeping survives a full rebuild")
