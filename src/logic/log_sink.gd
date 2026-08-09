class_name LogSink
extends RefCounted

## Base for pluggable combat-log destinations (docs/09). Never hardcode a
## destination in CombatLog itself — add a new LogSink subclass instead.


func emit(_event: LogEvent) -> void:
	pass


## taskblock-41 Pass B: the opt-out seam. Engine and script errors now ride
## the same stream as combat events — "conflated on purpose, separable on
## demand" — so a sink that only wants the game's own events can decline the
## diagnostics without a second stream existing to subscribe to. Default true:
## every pre-existing sink keeps receiving everything, unchanged.
##
## Checked by `CombatLog.emit()`, never by the sink itself, so declining an
## event costs the sink nothing and can't be forgotten halfway through an
## `emit()` implementation.
func wants(_event: LogEvent) -> bool:
	return true


## `BR51.16`: whether `CombatLog.add_sink` should replay its retained history into this sink so a
## late arrival is up to date.
##
## **Default false, and the default is the important half.** Replay is wrong for almost every sink
## here: `FileSink` would write every past line a second time, and a `MemorySink` capturing one
## turn's events for playback would swallow the whole bout instead. The one consumer that needs it
## is a UI panel rebuilt mid-bout — `HierarchicalUiSink` — because the panel is a *view of* the
## stream and the stream did not restart just because the overlay did.
##
## Declared on the sink and checked by `CombatLog`, the same shape as `wants()` above and for the
## same reason: it is one override rather than something every attach site has to remember.
func wants_replay() -> bool:
	return false
