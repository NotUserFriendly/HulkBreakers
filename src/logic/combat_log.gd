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
## **Per `CombatState`, and that is what makes the replay semantics fall out correctly rather than
## needing a rule.** A mid-bout overlay swap keeps the same state and therefore the same history, so
## a rebuilt panel gets its rows back; a new bout builds a new `CombatState` with a new `CombatLog`
## whose history is empty, so the panel is empty because there is genuinely nothing to show.
var _history: Array[LogEvent] = []


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
	for event: LogEvent in _history:
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
	if _history.size() > MAX_HISTORY * 2:
		_history = _history.slice(_history.size() - MAX_HISTORY)


## The retained events, oldest first — read by tests and by anything that needs to know how far
## back a re-attached sink can be brought. Never mutated through this: it hands back the real array
## and callers are expected to read it.
func history() -> Array[LogEvent]:
	return _history
