class_name WatchedRunOverlay
extends SpectatorOverlay

## taskblock-47 Pass D: **a `SpectatorOverlay` that plays a seed list in order.**
##
## Extends the spectator rather than replacing it, so a watched bout has exactly the
## controls a normal bout has — play, step, speed, inspect, the debug panel, all of
## it. That is the point: "watch the seed the test failed on" only helps if what you
## get is a real bout and not a cut-down viewer that behaves differently in some way
## you find out about later.
##
## Everything it adds is two labels and an end-of-bout hook. **The sequencing lives in
## `WatchedRun`**, in logic, because CC cannot see the screen and "the seeds played in
## the order given" has to be answerable in a headless test.
##
## ## Why it does not record anything
##
## `CompletionSampler.build_for_seed(map_seed)` needs nothing but the seed, so each
## bout is rebuilt rather than replayed from a capture. There is no artifact to keep
## in sync with the game, and a watched seed cannot drift from the headless one that
## reported it — `test_watched_run.gd` asserts that rather than assuming it.

## The run being watched. Assigned before `setup`, so the first bout is already loaded
## by the time anything draws.
var run: WatchedRun = null

var _criteria_label: Label = null
var _table_label: Label = null


## Loads `map_seed`'s bout into `battle` and returns whether it built. The one place
## a seed becomes a board, so the watched path cannot diverge from the headless one.
static func load_seed(battle: BattleScene, map_seed: int) -> bool:
	var built: Dictionary = CompletionSampler.build_for_seed(map_seed)
	if built.get("error", "") != "":
		return false
	battle.load_battle(built["state"], built["mission"])
	return true


func setup(p_battle: BattleScene) -> void:
	super.setup(p_battle)
	if run == null:
		run = WatchedRun.new()

	# Deliberately plain `Label`s stacked above the spectator's own controls: this is
	# a debug surface and the information is the product, not the presentation.
	_criteria_label = Label.new()
	_criteria_label.text = "\n".join(WatchedRun.describe_criteria(CompletionSampler.TURN_CAP, 0.35))
	add_child(_criteria_label)

	_table_label = Label.new()
	add_child(_table_label)
	_refresh_table()


## Redrawn every time a row changes rather than only at the end. **The 15-of-20 case
## is the whole point** — the pattern is visible around seed 5 and the run can be
## killed there, which a table that only appears when everything has finished cannot
## support.
func _refresh_table() -> void:
	if _table_label == null or run == null:
		return
	_table_label.text = "\n".join(run.describe_table())


## Called when the bout on screen reaches a terminal state. Records the outcome, then
## loads the next seed — or stops, when the list is done.
func on_bout_finished() -> void:
	if run == null or run.is_done():
		return
	var mission: MissionState = battle.mission
	var turns: int = runner.turns_taken if runner != null else 0
	run.record(StringName(Enums.MissionOutcome.keys()[mission.outcome]), turns)
	_refresh_table()
	_advance()


## Abandon the bout on screen and move to the next seed.
func skip_current() -> void:
	if run == null or run.is_done():
		return
	run.skip()
	_refresh_table()
	_advance()


## Re-load the previous seed and watch it again — the "wait, what happened there" case,
## which is most of why anyone watches.
func rewatch_previous() -> void:
	if run == null:
		return
	run.rewatch_previous()
	_refresh_table()
	_advance()


## End the run where it stands, keeping the table. The bout on screen is left alone
## rather than torn down, so stopping to look at something does not remove the thing
## being looked at.
func stop_run() -> void:
	if run == null:
		return
	run.stop()
	playing = false
	_refresh_table()


func _advance() -> void:
	playing = false
	if run.is_done():
		return
	if not load_seed(battle, run.current_seed()):
		# A seed that cannot build is not a bout that failed — skip it and say so in
		# the table rather than stalling the run on it.
		run.skip()
		_refresh_table()
		_advance()
		return
	super.setup(battle)
	_refresh_table()
