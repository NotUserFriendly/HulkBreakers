extends GutTest

## taskblock-48 Pass B2.5: **the debug panels do not sit on top of `TopLeftControls`.**
##
## They were added as plain children of a full-rect overlay, which puts them at (0,0)
## — directly over the Inject / New Battle / Watch row. `PLAN.md` notes this is the
## third full-rect container to have a placement or input problem in that corner, so
## this is asserted rather than eyeballed once and forgotten.
##
## ## Read the real rects, do not re-derive them
##
## `docs/00`: build the actual node, apply the state, and read the geometry back out.
## A test that recomputed the anchors from the same constants the layout uses would
## agree with itself and with nothing on screen — which is exactly how the attack
## camera's yaw bug survived a full suite.
##
## ## What this cannot check, said plainly
##
## The taskblock asks for "any supported resolution". **Headless has no real window**:
## setting `root.size` or `content_scale_size` leaves every reported rect identical, so
## a loop over four resolutions measures one layout four times and presents it as four.
## A first attempt did exactly that, with an anti-vacuity assertion that counted the
## sizes it had *asked* for rather than the ones applied — vacuous twice over.
##
## So this checks the one viewport headless actually has, and **resolution variation
## remains uncovered**. Catching it needs a visual checkpoint, which is the tool this
## project already has for questions a no-op renderer cannot answer.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _overlay() -> SpectatorOverlay:
	var grid: Grid = GridFixture.flat(12, 10)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	# `BoutRunner` refuses a state with unassigned squads, and `SpectatorOverlay.setup`
	# builds one — a layout fixture still has to be a legal bout.
	state.assign_rest_to_ai([] as Array[int])
	var mission := MissionState.new(RunState.new(), state)
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)
	battle.set_overlay(SpectatorOverlay.new())
	return battle.overlay as SpectatorOverlay


func test_the_debug_panels_never_overlap_the_top_left_controls() -> void:
	var overlay: SpectatorOverlay = _overlay()
	if overlay.suite_run_panel == null:
		# The panels are gated on `OS.is_debug_build()`. In a release run there is
		# nothing to collide, and saying so beats a silent pass.
		gut.p("debug panels not built (release build) — nothing to check")
		assert_true(true)
		return

	# Bound so the panel has content and therefore a real rect — an empty container
	# collapses to zero size and would clear every obstacle by not existing.
	overlay.watched_run_panel.bind(overlay.battle, WatchedRun.of([1, 2] as Array[int]))
	var controls: Control = overlay.top_left_controls
	await get_tree().process_frame
	await get_tree().process_frame

	var row: Rect2 = controls.get_global_rect()
	# **The rects have to be real, or "no overlap" is free.** A zero-size container
	# clears every obstacle by not existing, which is how the first version of this
	# passed while the panels were parented to a `Node3D` and had no layout at all.
	assert_gt(row.size.x, 0.0, "sanity: the controls row has a real rect")
	for panel: Control in [overlay.suite_run_panel, overlay.watched_run_panel]:
		var rect: Rect2 = panel.get_global_rect()
		gut.p("%s — controls %s, panel %s" % [panel.name, row, rect])
		assert_gt(rect.size.x, 0.0, "%s has a real rect" % panel.name)
		assert_false(
			row.intersects(rect),
			"%s overlaps TopLeftControls — controls %s, panel %s" % [panel.name, row, rect]
		)


## The panels must still be **on screen**. Moving them out of the way by pushing them
## off the viewport would pass the test above and help nobody.
func test_the_debug_panels_stay_inside_the_viewport() -> void:
	var overlay: SpectatorOverlay = _overlay()
	if overlay.suite_run_panel == null:
		assert_true(true)
		return
	overlay.watched_run_panel.bind(overlay.battle, WatchedRun.of([1, 2] as Array[int]))
	await get_tree().process_frame
	await get_tree().process_frame

	var screen := Rect2(Vector2.ZERO, get_tree().root.get_visible_rect().size)
	for panel: Control in [overlay.suite_run_panel, overlay.watched_run_panel]:
		assert_true(
			screen.intersects(panel.get_global_rect()),
			(
				"%s is off screen — viewport %s, panel %s"
				% [panel.name, screen, panel.get_global_rect()]
			)
		)
