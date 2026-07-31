extends GutTest

## taskblock-51: the performance readout panel and how it is wired.
##
## The behaviours here are the ones the supervisor specified, and each is easy to get
## subtly wrong in a way that only shows up mid-session: a readout that dies when you close
## the panel that offered it, a profiler that costs frames, a log dump that fires when
## nobody asked for one.


func _panel() -> PerfPanel:
	var panel := PerfPanel.new()
	add_child_autofree(panel)
	return panel


func _feed(panel: PerfPanel, fps: float, seconds: float) -> void:
	var frames: int = int(fps * seconds)
	for i in range(frames):
		panel._process(1.0 / fps)


## **It samples every frame but redraws on the rolling tick.** A readout that rebuilt its
## text 160 times a second would be measuring its own overhead, which is the failure mode
## that makes profilers untrustworthy.
func test_it_redraws_on_the_tick_not_every_frame() -> void:
	var panel: PerfPanel = _panel()
	panel._process(1.0 / 60.0)
	var early: String = panel.readout_text()

	_feed(panel, 60.0, PerfStats.ROLLING_WINDOW_SECONDS + 0.1)

	assert_ne(panel.readout_text(), early, "the tick refreshed it")
	assert_true(panel.readout_text().contains("rolling"), "and the rolling figure is shown")


## All four figures the supervisor asked for, on one surface.
func test_it_shows_the_four_figures() -> void:
	var panel: PerfPanel = _panel()
	_feed(panel, 120.0, 3.0)

	var text: String = panel.readout_text()
	for figure: String in ["instant", "rolling", "1% low", "avg less top 1%"]:
		assert_true(text.contains(figure), "the readout shows %s: %s" % [figure, text])
	assert_true(text.contains("reporting"), "and states its own coverage")


## **The dump is opt-in and fires on the rolling cadence**, which is what was asked for —
## not on every frame, and not unless the box is ticked.
func test_the_log_dump_is_opt_in_and_fires_on_the_tick() -> void:
	var panel: PerfPanel = _panel()
	var ticks: Array[int] = [0]
	panel.stats_ticked.connect(func(_snapshot: Dictionary) -> void: ticks[0] += 1)

	_feed(panel, 60.0, PerfStats.ROLLING_WINDOW_SECONDS * 2.0 + 0.1)
	assert_eq(ticks[0], 0, "nothing is logged while the box is unticked")

	panel.set_log_dumps(true)
	_feed(panel, 60.0, PerfStats.ROLLING_WINDOW_SECONDS + 0.1)

	assert_eq(ticks[0], 1, "one dump per window once it is ticked")


func test_reset_clears_the_readout() -> void:
	var panel: PerfPanel = _panel()
	_feed(panel, 10.0, 3.0)
	assert_true(panel.stats.sample_count() > 0)

	panel.reset_stats()

	assert_eq(panel.stats.sample_count(), 0)
	assert_true(panel.readout_text().contains("--"), "and the figures go back to unavailable")


## **The panel must not eat clicks.** It sits over the board in a corner, and a readout that
## swallowed input would be a new bug shipped alongside a diagnostic — the exact trade
## `BR30.05` and `BR34.02` were both filed for.
func test_it_never_takes_the_mouse() -> void:
	assert_eq(_panel().mouse_filter, Control.MOUSE_FILTER_IGNORE)


# --- the wiring, which is where the supervisor's requirement lives -------------------


func _overlay_with_debug() -> SquadControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.new_battle(1)
	battle.set_overlay(SquadControlOverlay.new())
	return battle.overlay as SquadControlOverlay


## **Closing the debug panel must not close the readout.** Stated plainly by the supervisor
## and easy to implement backwards by parenting one to the other.
func test_the_readout_survives_the_debug_panel_closing() -> void:
	if not OS.is_debug_build():
		assert_true(true, "the panels are debug-gated; nothing to check in a release build")
		return
	var overlay: SquadControlOverlay = _overlay_with_debug()
	assert_not_null(overlay.perf_panel, "the overlay owns a readout")

	overlay.debug_panel.set_ui_element_shown(DebugUiElements.PERF_PANEL, true)
	assert_true(overlay.perf_panel.visible, "the toggle shows it")

	overlay.debug_panel.visible = false

	assert_true(overlay.perf_panel.visible, "and it stays up when the debug panel goes away")


## It is offered wherever the debug panel is — the supervisor's "it's under debug, it should
## show wherever debug shows because it's tied to it".
func test_the_spectator_view_has_one_too() -> void:
	if not OS.is_debug_build():
		assert_true(true)
		return
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.new_battle(1)
	battle.set_overlay(SpectatorOverlay.new())

	assert_not_null((battle.overlay as SpectatorOverlay).perf_panel)


## The panel emits, the overlay writes — so the dump lands in the real combat log rather
## than the panel reaching into a `CombatState` itself.
func test_a_tick_reaches_the_real_combat_log() -> void:
	if not OS.is_debug_build():
		assert_true(true)
		return
	var overlay: SquadControlOverlay = _overlay_with_debug()
	var sink := MemorySink.new()
	overlay.battle.combat_state.combat_log.add_sink(sink)

	overlay.perf_panel.set_log_dumps(true)
	_feed(overlay.perf_panel, 60.0, PerfStats.ROLLING_WINDOW_SECONDS + 0.1)

	var dumps: Array[LogEvent] = sink.events_of_kind(&"fps_dump")
	assert_eq(dumps.size(), 1, "one dump reached the log")
	assert_true(dumps[0].text.begins_with("perf:"), "carrying the readout: %s" % dumps[0].text)
	assert_true(dumps[0].data.has("one_percent_low"), "and the figures as data, not only prose")
