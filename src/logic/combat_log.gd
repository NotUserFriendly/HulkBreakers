class_name CombatLog
extends RefCounted

## Structured, rolling combat log (docs/09). A real game feature and, equally,
## CC's and the human's monitoring channel — one event stream, many sinks.
## Every projectile, deflection, ricochet, penetration, cook-off, abort
## reason, and matrix ejection must emit an event here: if it changed the
## world, it belongs in the log.

## `BR51.16`: how many past events this log keeps so a sink attaching late can be brought up to
## date. **Flagged, not designed.**
##
## The consumer that needs it is the combat-log panel, which folds events into at most
## `LogFold.MAX_GROUPS` (200) rows, and `UiLogSink`'s own measurement puts a real 3v3 bout at 9.9
## events per turn. 2000 is comfortably more than enough to refill a full panel and small enough
## that a bout's worth costs nothing worth measuring. **It is a number nobody chose from design**,
## so it is named here rather than buried, and moving it changes only how far back a re-attached
## panel can see.
const MAX_HISTORY := 2000

var _sinks: Array[LogSink] = []
## Every event emitted on this log, oldest first, trimmed to roughly `MAX_HISTORY`.
##
## **Per `CombatState`, which is what scopes a replay to one bout without anyone writing a rule
## about bouts.** A mid-bout overlay swap keeps the same state and therefore the same history, so a
## rebuilt panel gets its rows back; a new bout builds a new `CombatState` with a new `CombatLog`,
## and there is simply nothing of the old one here to replay.
##
## What a panel *shows* across a bout boundary is a separate question this does not answer: the
## panel accumulates, because `CombatLogModule.attach_to` does not clear the fold. See its note.
var _history: Array[LogEvent] = []
## How far into `_history` a replay starts — **"what a panel would have seen"**, set once, by the
## first replay-wanting sink to attach.
##
## `BR51.16`: without this, replay hands a freshly-mounted panel events emitted **before any panel
## existed**. `CombatState.new` logs its own construction (`unit_assembled`, `build_step`) and
## `BattleScene.load_battle` attaches the panel's sink only afterwards, deliberately — so those
## events were never the panel's to show, and replaying them put board-build noise ahead of the
## `bout_start` header the log is supposed to open with. That is a real readability regression and
## `test_battle_scene.gd` caught it.
##
## One integer, and no rule about event kinds: the first panel to attach sets the floor at wherever
## history already stood, so it replays nothing and sees exactly what it always saw. Every panel
## after it — the ones an overlay swap builds mid-bout — replays from that same floor and is
## brought up to date with its predecessor. **-1 means no replay-wanting sink has attached yet.**
var _replay_floor: int = -1


## Attaches `sink`, and brings it up to date if it asked to be.
##
## **`BR51.16`: replay is opt-in via `LogSink.wants_replay`, defaulting false**, because most sinks
## must not have it. `FileSink` would write every past line a second time; a `MemorySink` capturing
## one turn's events for playback would swallow the whole bout. The one consumer that genuinely
## needs it is a UI panel rebuilt mid-bout, which is what this entry is about.
##
## Replay runs through the same `wants()` filter `emit` does, so a sink that declines diagnostics
## declines them in history exactly as it would live — one stream, one filter, no second path.
func add_sink(sink: LogSink) -> void:
	_sinks.append(sink)
	if not sink.wants_replay():
		return
	if _replay_floor < 0:
		# The first panel on this log. It saw nothing before now and must not start seeing it.
		_replay_floor = _history.size()
		return
	for i: int in range(mini(_replay_floor, _history.size()), _history.size()):
		var event: LogEvent = _history[i]
		if sink.wants(event):
			sink.emit(event)


## docs/10 Phase 12.4: a temporary sink (e.g. a MemorySink capturing one
## turn's events for playback) must not linger collecting every event for
## the rest of the battle — a no-op if `sink` was never added.
func remove_sink(sink: LogSink) -> void:
	_sinks.erase(sink)


## taskblock-41 Pass B: `wants()` is checked here rather than inside each
## sink, so declining a kind is one override rather than a guard every
## `emit()` implementation has to remember. Still ONE stream — a sink that
## declines diagnostics is filtering a shared stream, not subscribing to a
## different one (docs/09: never two streams).
func emit(event: LogEvent) -> void:
	_remember(event)
	for sink: LogSink in _sinks:
		if sink.wants(event):
			sink.emit(event)


## `BR51.16`: appends to the replay history, trimmed in batches.
##
## **Batched rather than `pop_front()` per event, deliberately.** A Godot `Array` is contiguous, so
## popping the front of a full 2000-entry history shifts every remaining element on *every* event
## for the rest of the bout. Letting it grow to twice the bound and slicing once amortises that to
## nothing, at the cost of the history sometimes holding up to `MAX_HISTORY * 2`. Since the bound
## is a flagged tunable rather than a contract, overshooting it between trims costs nothing —
## whereas a per-event memmove is exactly the kind of quiet cost `BR27.09` was filed about.
func _remember(event: LogEvent) -> void:
	_history.append(event)
	if _history.size() <= MAX_HISTORY * 2:
		return
	var dropped: int = _history.size() - MAX_HISTORY
	_history = _history.slice(dropped)
	# **The floor is an index, so trimming has to move it.** Left alone it would drift forward
	# through the surviving history and a re-attached panel would silently lose its oldest rows —
	# a bug that only shows up in a bout long enough to trim, which is the worst kind to leave.
	if _replay_floor > 0:
		_replay_floor = maxi(_replay_floor - dropped, 0)


## The retained events, oldest first — read by tests and by anything that needs to know how far
## back a re-attached sink can be brought. Never mutated through this: it hands back the real array
## and callers are expected to read it.
func history() -> Array[LogEvent]:
	return _history
