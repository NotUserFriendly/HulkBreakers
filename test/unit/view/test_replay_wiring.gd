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

const PROBE_ENV := "HB_FORCE_TEST_FAILURE"


## taskblock-47 Pass C: this file builds bouts — replaying a handle rebuilds a real
## fixture — so the fast gate skips it. Untyped to match GUT's own signature.
func should_skip_script():
	return SuiteTier.skip_if_fast()


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
##
## **Written with GUT's colour codes in it, because the real feed has them.** The first
## version of this used clean lines, every prefix test in `failures()` matched, and the
## parser passed while being unable to read a single real run — GUT emits
## `\u001b[0m- test_name`. Input tidier than reality is worse than no test.
func _failed_run() -> SuiteRun:
	var esc := char(27)
	var run := SuiteRun.new()
	run.ingest(
		(
			(
				"%s[33m= Run Summary\n"
				+ "%s[0m%s[4m\n"
				+ "res://test/unit/logic/test_replay_handle.gd\n"
				+ "%s[0m- test_a_handle_rebuilds_the_fixture_its_test_built\n"
				+ "%s[31m    [Failed]:  %s[0mdeliberate\n"
				+ "Passing Tests      1\nFailing Tests         1\n"
				+ "%s=1\n"
			)
			% [esc, esc, esc, esc, esc, esc, SuiteRun.EXIT_MARKER]
		)
	)
	return run


## The parser must read the coloured feed, and must not report one failed test three
## times because GUT names it more than once after the summary header.
func test_failures_are_parsed_from_coloured_output_and_deduplicated() -> void:
	var failures: Array[Dictionary] = _failed_run().failures()

	gut.p("parsed: %s" % [failures])
	assert_eq(failures.size(), 1, "one failed test, reported once")
	assert_eq(String(failures[0]["script"]), "res://test/unit/logic/test_replay_handle.gd", "named")
	assert_false(String(failures[0]["test"]).contains(char(27)), "with no escape codes left in")


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


## **Launching a run clears the board, and that is the visible connection.**
##
## Without it the window keeps showing whatever bout was already loaded, so a replay
## that works and a replay that does nothing look identical — which is precisely what
## could not be told apart from the window. An empty board is an unambiguous "this is
## not the old bout".
func test_launching_a_run_clears_the_board() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.suite_run_panel == null:
		assert_true(true)
		return
	var before: Grid = overlay.battle.combat_state.grid
	var floored_before := 0
	for y in range(before.rows):
		for x in range(before.width):
			if Surface.first_walkable(before.surfaces_at(Vector2i(x, y))) != null:
				floored_before += 1
	assert_gt(floored_before, 0, "sanity: the board started with floor on it")

	overlay.suite_run_panel.clear_board()

	var after: Grid = overlay.battle.combat_state.grid
	var floored_after := 0
	for y in range(after.rows):
		for x in range(after.width):
			if Surface.first_walkable(after.surfaces_at(Vector2i(x, y))) != null:
				floored_after += 1
	gut.p("floored cells %d -> %d" % [floored_before, floored_after])
	assert_eq(floored_after, 0, "the cleared board has no walkable floor left")
	assert_eq(overlay.battle.combat_state.units.size(), 0, "and no units")


## **The force-fail toggle is passed to the child, never set on this process.**
## `OS.set_environment` is process-wide, and taskblock-47 already had one test switch
## the fast gate off for every file GUT had not reached by clearing a variable it set.
func test_forcing_a_failure_does_not_touch_this_process_environment() -> void:
	var before: String = OS.get_environment(PROBE_ENV)
	var run := SuiteRun.new()
	run.force_failure = true

	run.start(&"full", "test_exit_code_probe.gd")
	# The shell writes its group id once it runs; asking immediately gets -1.
	await get_tree().create_timer(2.0).timeout
	var group: int = run.process_group()
	run.kill()

	assert_eq(OS.get_environment(PROBE_ENV), before, "this process's environment is untouched")
	assert_gt(group, 0, "sanity: the run really launched")


## End to end, through the real script: the toggle makes a run fail, and that failure
## is one the replay can offer. This is the path that could not be demonstrated from
## the window without knowing a variable name.
func test_the_toggle_produces_a_failing_run_with_something_to_replay() -> void:
	var run := SuiteRun.new()
	run.force_failure = true
	run.start(&"full", "test_exit_code_probe.gd")
	var deadline: int = Time.get_ticks_msec() + 180000
	while not run.finished and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.2).timeout
		run.poll()
	run.poll()

	gut.p(run.status_line())
	assert_true(run.finished, "the forced run finished")
	assert_false(run.passed(), "and it failed, which is the point of the toggle")
	assert_gt(run.failures().size(), 0, "with a named failure the replay can be offered")


## **The demonstration path, end to end.** Force a failure, run the real script, and
## the failure that comes back must be one the replay can offer as a playing bout.
##
## This is the gap the toggle shipped with: `test_exit_code_probe.gd` is the only test
## that fails on demand, and it had no visual form — so ticking the box produced "1
## failure, none with a visual form" and no bout, leaving the replay exactly as
## unverifiable as before. Asserted here so the toggle and the handle cannot drift
## apart again.
func test_forcing_a_failure_yields_a_replayable_bout() -> void:
	var run := SuiteRun.new()
	run.force_failure = true
	run.start(&"full", "test_exit_code_probe.gd")
	var deadline: int = Time.get_ticks_msec() + 180000
	while not run.finished and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.2).timeout
		run.poll()
	run.poll()
	assert_true(run.finished, "the forced run finished")
	assert_false(run.passed(), "and failed")

	var handles: Array[ReplayHandle] = ReplayCatalog.handles_for(run.failures())

	gut.p("failures %s -> %d handle(s)" % [run.failures(), handles.size()])
	assert_gt(handles.size(), 0, "the forced failure has something to replay")
	var built: Dictionary = handles[0].build()
	assert_false(built.is_empty(), "and it rebuilds a real fixture")
	var state: CombatState = built["state"]
	# A bout with units in it, so there is something to watch move — a bare map would
	# render correctly and answer nothing about whether playback works.
	assert_gt(state.units.size(), 0, "with units on the board, not just terrain")


## **The checkbox actually reaches the run.** Tested from the control, not from the
## flag it sets.
##
## Everything about `force_failure` was proven by setting `SuiteRun.force_failure`
## directly — the same shape of gap that left the whole replay path unwired: the
## mechanism verified, the thing a person touches not. The run is killed immediately,
## so the nested gate dies during the lint step and never reaches an engine.
func test_the_force_failure_checkbox_reaches_the_launched_run() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.suite_run_panel == null:
		assert_true(true)
		return
	var panel: SuiteRunPanel = overlay.suite_run_panel

	panel.set_force_failure(false)
	panel._start(&"full")
	var without: bool = panel.run.force_failure
	panel._stop()

	panel.set_force_failure(true)
	panel._start(&"full")
	var with_flag: bool = panel.run.force_failure
	panel._stop()

	gut.p("checkbox off -> %s, on -> %s" % [without, with_flag])
	assert_false(without, "unticked launches an ordinary run")
	assert_true(with_flag, "ticked launches a forced one")


## And the flag becomes a real prefix on the child's command rather than a field
## nothing reads. Asserted through the command `start` builds, since that is the only
## thing the child ever sees.
func test_a_forced_run_prefixes_the_variable_onto_the_child_command() -> void:
	var ambient: String = OS.get_environment(PROBE_ENV)
	var forced := SuiteRun.new()
	forced.force_failure = true
	forced.start(&"full", "test_exit_code_probe.gd")
	await get_tree().create_timer(1.0).timeout
	var group: int = forced.process_group()
	forced.kill()

	assert_gt(group, 0, "the forced run launched")
	# **Unchanged, not empty.** Asserting empty assumed nobody was exercising this
	# feature while the suite ran — and the panel's own toggle runs the whole gate
	# under the variable, so it failed exactly when someone used the thing it tests.
	# The claim is that `start()` does not touch the environment, and that is true
	# whatever the ambient value happens to be.
	assert_eq(OS.get_environment(PROBE_ENV), ambient, "start() left the environment alone")


## **The panel says whether the flag was applied.** "The checkbox does not work" and
## "the checkbox worked and the run passed anyway" look identical without this, which
## is why the report of a forced run passing 20/20 could not be diagnosed from what
## was on screen.
func test_a_forced_run_says_so_and_shows_its_command() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.suite_run_panel == null:
		assert_true(true)
		return
	var panel: SuiteRunPanel = overlay.suite_run_panel

	panel.set_force_failure(true)
	panel._start(&"fast")
	var header: String = panel.run.status_line()
	var command: String = panel.run.launched_command
	var first_line: String = panel.run.lines[0]
	panel._stop()

	gut.p("%s\n%s" % [header, first_line])
	assert_true(header.contains("forced failure"), "the header states the flag was applied")
	assert_true(command.contains("HB_FORCE_TEST_FAILURE=1"), "and the command carries it")
	assert_true(command.contains("fast"), "against the rung that was clicked")
	assert_true(first_line.begins_with("$ "), "the feed opens with the command that ran")


## And an ordinary run says nothing about forcing, so the note means something when it
## does appear.
func test_an_ordinary_run_does_not_claim_to_be_forced() -> void:
	var overlay: SpectatorOverlay = _spectator()
	if overlay.suite_run_panel == null:
		assert_true(true)
		return
	var panel: SuiteRunPanel = overlay.suite_run_panel

	panel.set_force_failure(false)
	panel._start(&"fast")
	var header: String = panel.run.status_line()
	var command: String = panel.run.launched_command
	panel._stop()

	assert_false(header.contains("forced"), "no note on an ordinary run")
	assert_false(command.contains("HB_FORCE_TEST_FAILURE"), "and no prefix either")
