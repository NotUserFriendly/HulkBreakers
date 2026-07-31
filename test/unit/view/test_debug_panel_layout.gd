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
	# taskblock-51: the performance readout is checked here too. It shipped anchored to the
	# right edge but *positioned* in parent space, which put it at x = -16 — hard against
	# the left edge with only its right-hand sliver on screen. A panel that is off screen is
	# not a panel, and nothing here would have caught it.
	overlay.perf_panel.visible = true
	await get_tree().process_frame
	for panel: Control in [overlay.suite_run_panel, overlay.watched_run_panel, overlay.perf_panel]:
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
	# taskblock-51: the performance readout is checked here too. It shipped anchored to the
	# right edge but *positioned* in parent space, which put it at x = -16 — hard against
	# the left edge with only its right-hand sliver on screen. A panel that is off screen is
	# not a panel, and nothing here would have caught it.
	overlay.perf_panel.visible = true
	await get_tree().process_frame
	for panel: Control in [overlay.suite_run_panel, overlay.watched_run_panel, overlay.perf_panel]:
		assert_true(
			screen.intersects(panel.get_global_rect()),
			(
				"%s is off screen — viewport %s, panel %s"
				% [panel.name, screen, panel.get_global_rect()]
			)
		)


## **Pinned width, asserted against content that would otherwise change it.**
##
## GUT prints everything from `* test_x` to a full `res://` path to a wrapped
## assertion message, so a panel sized to its content jumped on every poll. Fed a line
## far longer than the panel, the width must not move — which is a claim about
## `clip_text` and `custom_minimum_size` together, and neither alone would hold it.
func test_the_run_panel_keeps_its_width_whatever_the_feed_says() -> void:
	var overlay: SpectatorOverlay = _overlay()
	if overlay.suite_run_panel == null:
		assert_true(true)
		return
	var panel: SuiteRunPanel = overlay.suite_run_panel
	await get_tree().process_frame
	var empty_width: float = panel.get_global_rect().size.x

	panel.run = SuiteRun.new()
	panel.run.ingest(
		(
			"res://test/unit/logic/ai/test_something_with_a_very_long_name_indeed.gd\n"
			+ "    [Failed]: "
			+ "x".repeat(400)
			+ "\n"
		)
	)
	panel._refresh()
	await get_tree().process_frame
	await get_tree().process_frame

	var loaded_width: float = panel.get_global_rect().size.x
	gut.p("width empty %.0f, with a 400-char line %.0f" % [empty_width, loaded_width])
	assert_almost_eq(loaded_width, empty_width, 1.0, "the feed must not widen the panel")
	assert_almost_eq(
		loaded_width, SuiteRunPanel.PANEL_WIDTH, 1.0, "and it sits at the pinned width"
	)


## The background is a real drawn surface, not a transparent container. Asserted
## against the same alpha `CombatLogPanel` uses, so the two cannot silently diverge
## into "one has a background and one does not".
func test_the_run_panel_draws_a_background_like_the_combat_log() -> void:
	var overlay: SpectatorOverlay = _overlay()
	if overlay.suite_run_panel == null:
		assert_true(true)
		return

	var body: PanelContainer = overlay.suite_run_panel._body
	assert_not_null(body, "the panel has a body to draw on")
	var style: StyleBox = body.get_theme_stylebox("panel")
	assert_true(style is StyleBoxFlat, "and a real stylebox rather than the default")
	var flat: StyleBoxFlat = style
	gut.p("background %s" % flat.bg_color)
	assert_gt(flat.bg_color.a, 0.5, "opaque enough to read text over the board")
	assert_almost_eq(
		flat.bg_color.a, CombatLogPanel.BACKGROUND_ALPHA, 0.001, "same alpha as the combat log"
	)


# --- taskblock-51: the run panels are spectator-only for the hunt ---------------------


func _player_overlay() -> SquadControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.new_battle(1)
	battle.set_overlay(SquadControlOverlay.new())
	return battle.overlay as SquadControlOverlay


## **Asserted in both directions, because one direction is vacuous on its own.**
##
## "The player view has no run panel" passes just as well if the panels stopped mounting
## anywhere at all — which would silently remove the whole run surface rather than move
## it. So the spectator's is checked in the same test, and the flag that decides is read
## rather than assumed: flipping `SHOW_IN_PLAYER_VIEW` back without touching this fails
## loudly instead of quietly restoring a panel nobody asked back yet.
func test_the_run_panels_are_spectator_only_while_the_hunt_runs() -> void:
	if not OS.is_debug_build():
		assert_true(true, "the panels are debug-gated; nothing to split in a release build")
		return

	var spectator: SpectatorOverlay = _overlay()
	var player: SquadControlOverlay = _player_overlay()

	assert_eq(
		SuiteRunPanel.SHOW_IN_PLAYER_VIEW,
		false,
		"the hunt wants the player view clear — flip this and this test with it"
	)
	assert_null(player.suite_run_panel, "the player view carries no run panel during the hunt")
	assert_null(player.watched_run_panel, "nor a replay panel")
	assert_not_null(spectator.suite_run_panel, "and the spectator still has one to run from")


## The inject panel is a hunting tool, not a test surface, and must survive the split —
## it is how the supervisor forces a detonation or kills a shell to reproduce with.
func test_the_player_views_inject_panel_survives_the_split() -> void:
	if not OS.is_debug_build():
		assert_true(true)
		return

	assert_not_null(_player_overlay().debug_panel, "the player view keeps its inject panel")


## **`intersects` is too weak to catch what actually shipped.** The readout was anchored to
## the right edge but *positioned* in parent space, which placed it at x = -16 — the
## supervisor saw it "on the left edge of the display, with only a bit of the right side
## visible". A rect at x = -16 still intersects the screen, so the existing check would
## have passed it.
##
## This asserts the readout is wholly on screen, which is the property that was violated.
func test_the_performance_readout_is_wholly_on_screen() -> void:
	var overlay: SpectatorOverlay = _overlay()
	if overlay.perf_panel == null:
		assert_true(true, "debug-gated; nothing to place in a release build")
		return
	overlay.perf_panel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame

	var screen: Vector2 = get_tree().root.get_visible_rect().size
	var rect: Rect2 = overlay.perf_panel.get_global_rect()

	gut.p("readout at %s in a %s viewport" % [rect, screen])
	# **The width is the assertion that matters.** The first broken version sat at x = -16;
	# the second spanned the whole 1904-pixel screen from x = 0 — and "left edge on screen,
	# right edge on screen" passed for that one. A readout the width of the display is not
	# a panel.
	assert_almost_eq(
		rect.size.x,
		PerfPanel.PANEL_WIDTH,
		2.0,
		"the readout is its own width, not the width of the screen"
	)
	assert_true(rect.position.x >= 0.0, "its left edge is on screen, not off to the left")
	assert_true(rect.position.y >= 0.0, "and its top edge is too")
	assert_true(
		rect.position.x + rect.size.x <= screen.x + 1.0, "and it does not run off the right either"
	)


## It belongs to the right of the centred debug panel, which is where the supervisor asked
## for it — not overlapping it.
func test_the_readout_sits_clear_of_the_debug_panel() -> void:
	var overlay: SpectatorOverlay = _overlay()
	if overlay.perf_panel == null or overlay.debug_panel == null:
		assert_true(true)
		return
	overlay.perf_panel.visible = true
	overlay.debug_panel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame

	var readout: Rect2 = overlay.perf_panel.get_global_rect()
	var debug: Rect2 = overlay.debug_panel.get_global_rect()

	assert_true(
		readout.position.x >= debug.position.x,
		"the readout is to the right of the debug panel: readout %s, debug %s" % [readout, debug]
	)


## **Read the readout's body back, not the outer Control.** The outer node is a bare
## `Control` sized (420, 0) by design; if the panel inside it never took a height, nothing
## renders and the toggle looks like it does nothing at all.
func test_the_readout_body_has_a_real_height() -> void:
	var readout := PerfPanel.new()
	add_child_autofree(readout)
	await get_tree().process_frame

	var body: Control = readout._body
	gut.p("readout body at %s" % body.get_global_rect())
	assert_true(body.get_global_rect().size.y > 0.0, "the readout has drawn height")
	assert_almost_eq(body.get_global_rect().size.x, PerfPanel.PANEL_WIDTH, 2.0)
