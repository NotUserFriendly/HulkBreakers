class_name WatchedRunPanel
extends VBoxContainer

## taskblock-48 Pass B1: **what `WatchedRunOverlay` was, as a panel.**
##
## taskblock-47 Pass D made it a fifth `SpectatorOverlay` subclass. The reasoning was
## sound in isolation — a watched bout should have every control a normal bout has —
## and it is the same reasoning that produced the hierarchy `PLAN.md`'s *One view,
## toggleable modules* exists to dissolve. Subclassing to reuse a toolbar is how you
## get five overlays.
##
## **The precedent was already in the tree**: `CombatLogPanel` is a `VBoxContainer`
## that both `SpectatorOverlay` and `SquadControlOverlay` instantiate, and it survives
## every overlay argument untouched because it never joined the hierarchy. This does
## the same, so a watched bout gets its controls by being hosted *by* an overlay
## rather than by being one.
##
## The sequencing stays in `WatchedRun`, which is logic and headless-testable. What is
## here is two labels and the hook that advances the run when a bout ends.
##
## ## taskblock-48 Pass B2: it replays failures too, and that is not a second mode
##
## `SuiteRun` reports which tests failed; `ReplayCatalog` asks each one's script
## whether it can rebuild what it built. The ones that can become `ReplayHandle`s and
## go into the same `WatchedRun` a seed list does — **one replayer, one set of
## controls**, because two would be two code paths deciding the same thing.
##
## A replay rebuilds the fixture; it does not re-run the test. The headless run already
## established the reason and the result. What was missing is what the test *built*.

## Emitted after a new seed's bout is loaded, so the host overlay can re-bind to the
## board it now has. **The panel does not reach into its host** — that would be the
## coupling this move exists to remove, wearing a different shape.
signal seed_loaded(map_seed: int)
## Emitted when the last seed has been watched or the run is stopped.
signal run_finished

var run: WatchedRun = null
var battle: BattleScene = null
## Set by the host before `on_bout_finished`, since the runner belongs to the overlay.
var turns_taken: int = 0

var _criteria_label: Label = null
var _table_label: Label = null


## Loads whatever `handle` rebuilds into `battle`. **The one place a handle becomes a
## board**, so a replayed fixture cannot diverge from the one its test built.
static func load_handle(target: BattleScene, handle: ReplayHandle) -> bool:
	if handle == null:
		return false
	var built: Dictionary = handle.build()
	if built.is_empty():
		return false
	target.load_battle(built["state"], built["mission"])
	return true


## Offers the first few replayable failures from a finished run. Returns how many it
## queued, so the caller can say "3 of 11 failures can be replayed" rather than letting
## a capped list read as though the rest had nothing to show.
func offer_failures(suite: SuiteRun, limit: int = ReplayCatalog.DEFAULT_LIMIT) -> int:
	if suite == null:
		return 0
	var handles: Array[ReplayHandle] = ReplayCatalog.handles_for(suite.failures(), limit)
	if handles.is_empty():
		return 0
	bind(battle, WatchedRun.of_handles(handles))
	_advance_to_first()
	return handles.size()


## Loads whatever the run is currently pointing at, without recording anything — the
## entry point, where `_advance()` is the step *after* a result.
func _advance_to_first() -> void:
	if run == null or run.is_done() or battle == null:
		return
	var built: Dictionary = run.current().build()
	if built.is_empty():
		run.skip()
		refresh()
		_advance()
		return
	battle.load_battle(built["state"], built["mission"])
	refresh()
	seed_loaded.emit(run.current_seed())


func bind(p_battle: BattleScene, p_run: WatchedRun) -> void:
	battle = p_battle
	run = p_run if p_run != null else WatchedRun.new()

	if _criteria_label == null:
		# Deliberately plain `Label`s: this is a debug surface and the information is
		# the product, not the presentation.
		_criteria_label = Label.new()
		add_child(_criteria_label)
		_table_label = Label.new()
		add_child(_table_label)
	_criteria_label.text = "\n".join(WatchedRun.describe_criteria(CompletionSampler.TURN_CAP, 0.35))
	refresh()


## Redrawn every time a row changes rather than only at the end. **The 15-of-20 case is
## the whole point** — the pattern is visible around seed 5 and the run can be killed
## there, which a table that only appears when everything has finished cannot support.
func refresh() -> void:
	if _table_label == null or run == null:
		return
	_table_label.text = "\n".join(run.describe_table())


## Called when the bout on screen reaches a terminal state.
func on_bout_finished() -> void:
	if run == null or run.is_done() or battle == null:
		return
	# Turns come from the host's runner, which is the only thing that counts them —
	# `MissionState` records the outcome, never how long it took.
	run.record(StringName(Enums.MissionOutcome.keys()[battle.mission.outcome]), turns_taken)
	refresh()
	_advance()


func skip_current() -> void:
	if run == null or run.is_done():
		return
	run.skip()
	refresh()
	_advance()


## The "wait, what happened there" case, which is most of why anyone watches.
func rewatch_previous() -> void:
	if run == null:
		return
	run.rewatch_previous()
	refresh()
	_advance()


## Ends the run where it stands, keeping the table. The bout on screen is left alone
## rather than torn down, so stopping to look at something does not remove the thing
## being looked at.
func stop_run() -> void:
	if run == null:
		return
	run.stop()
	refresh()
	run_finished.emit()


func _advance() -> void:
	if run.is_done():
		run_finished.emit()
		return
	if not load_handle(battle, run.current()):
		# A seed that cannot build is not a bout that failed — skip it and say so in
		# the table rather than stalling the run on it.
		run.skip()
		refresh()
		_advance()
		return
	refresh()
	seed_loaded.emit(run.current_seed())
