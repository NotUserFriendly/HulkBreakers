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
