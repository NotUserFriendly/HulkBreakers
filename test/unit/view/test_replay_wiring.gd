extends GutTest

## taskblock-48 Pass B2 follow-up: **the replay path is actually reachable from the
## running game.**
##
## Every piece of it shipped tested and none of it was connected. `offer_failures`,
## `bind` and `on_bout_finished` had **zero callers in `src/`** — the panels were
## mounted, held `run = null` and `battle = null`, and did nothing. The supervisor saw
## a text feed and a board that never changed, and was right to ask.
##
## `docs/11` names this exactly: *a tier or restriction that does nothing passes every
## test asserting what it should do.* The B2 tests call the logic directly and prove it
## works **when called**. Not one of them asserted it gets called, and the taskblock's
## own test list did not ask for that either.
##
## So these assert the wiring and nothing else: that the overlay binds the panel, that
## a finished run reaches it, that a loaded fixture reaches the board, and that a
## finished bout advances the run. The mechanism is already covered elsewhere.

const PROBE_ENV := "HULK_FORCE_TEST_FAILURE"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _spectator() -> SpectatorOverlay:
	var grid: Grid = GridFixture.flat(12, 10)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	state.assign_rest_to_ai([] as Array[int])
	var mission := MissionState.new(RunState.new(), state)
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, mission)
	battle.set_overlay(SpectatorOverlay.new())
	return battle.overlay as SpectatorOverlay


## A `SuiteRun` that has "finished" with one replayable failure, without running
## anything. `ingest` is the seam that exists so verdict handling can be exercised
## without a subprocess.
func _failed_run() -> SuiteRun:
	var run := SuiteRun.new()
	run.ingest(
		(
			(
				"= Run Summary\n"
				+ "res://test/unit/logic/test_replay_handle.gd\n"
				+ "- test_a_handle_rebuilds_the_fixture_its_test_built\n"
				+ "Passing Tests      1\nFailing Tests         1\n"
				+ "%s=1\n"
			)
			% SuiteRun.EXIT_MARKER
		)
	)
	return run


# --- the wiring ---------------------------------------------------------------------


## **The panel is bound to the battle at setup.** Unbound it can never load anything,
## which is precisely the state it shipped in.
func test_the_overlay_binds_the_replay_panel_to_the_battle() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.watched_run_panel == null:
		gut.p("debug panels not built (release build)")
		assert_true(true)
		return

	assert_not_null(overlay.watched_run_panel.battle, "the panel knows which battle to load into")
	assert_eq(overlay.watched_run_panel.battle, overlay.battle, "and it is this overlay's")


## **A finished run reaches the replay panel.** The connection is the thing that was
## missing; the offer itself is covered by `test_replay_handle.gd`.
func test_a_failed_run_offers_its_replayable_failures() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.watched_run_panel == null:
		assert_true(true)
		return
	var before: Grid = overlay.battle.combat_state.grid

	overlay.suite_run_panel.run = _failed_run()
	overlay.suite_run_panel.run_completed.emit(overlay.suite_run_panel.run)

	var run: WatchedRun = overlay.watched_run_panel.run
	assert_not_null(run, "the replay panel was handed a run")
	assert_gt(run.items.size(), 0, "with at least one handle in it")
	# **The board actually changed.** This is what the supervisor could not see: a
	# panel that queued handles and never loaded one looks identical to no panel.
	assert_ne(overlay.battle.combat_state.grid, before, "and the board is the replayed one")


## A green run must put nothing on screen. An offer after every passing run would be
## noise, and noise is what gets a debug surface switched off.
func test_a_passing_run_offers_nothing() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.watched_run_panel == null:
		assert_true(true)
		return
	var passing := SuiteRun.new()
	passing.ingest("Passing Tests      10\nFailing Tests         0\n%s=0\n" % SuiteRun.EXIT_MARKER)

	overlay.suite_run_panel.run = passing
	overlay.suite_run_panel.run_completed.emit(passing)

	# The panel is bound at setup and therefore always holds a run object; what a green
	# run must not do is put anything IN it.
	assert_true(
		overlay.watched_run_panel.run == null or overlay.watched_run_panel.run.items.is_empty(),
		"nothing queued for a green run"
	)


## **A finished bout advances the run.** Without this the panel loads one fixture and
## stops, which reads as "the replay is broken" rather than "nobody told it the bout
## ended".
func test_a_finished_bout_advances_the_replay_run() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.watched_run_panel == null:
		assert_true(true)
		return
	overlay.watched_run_panel.bind(overlay.battle, WatchedRun.of([4, 9] as Array[int]))
	overlay.watched_run_panel.turns_taken = 7
	var first: int = overlay.watched_run_panel.run.current_seed()

	overlay.watched_run_panel.on_bout_finished()

	var run: WatchedRun = overlay.watched_run_panel.run
	assert_eq(run.results.size(), 1, "the finished bout was recorded")
	assert_eq(int(run.results[first]["turns"]), 7, "with the runner's own turn count")
	assert_ne(run.current_seed(), first, "and the run moved on")


## The spectator starts the replayed bout playing. A loaded board with nothing driving
## it is a still image — which, with the missing wiring above, is exactly what there
## was to look at.
func test_the_spectator_starts_a_replayed_bout_playing() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.watched_run_panel == null:
		assert_true(true)
		return
	overlay.resolution_player.slide_ms = 0.0
	overlay.resolution_player.bullet_ms = 0.0
	overlay.resolution_player.tracer_count = 0

	overlay._on_replay_loaded(0)

	assert_true(overlay.playing, "the replayed bout is running, not sitting there")
	overlay.pause()
