class_name CombatLog
extends RefCounted

## Structured, rolling combat log (docs/09). A real game feature and, equally,
## CC's and the human's monitoring channel — one event stream, many sinks.
## Every projectile, deflection, ricochet, penetration, cook-off, abort
## reason, and matrix ejection must emit an event here: if it changed the
## world, it belongs in the log.

var _sinks: Array[LogSink] = []


func add_sink(sink: LogSink) -> void:
	_sinks.append(sink)


## docs/10 Phase 12.4: a temporary sink (e.g. a MemorySink capturing one
## turn's events for playback) must not linger collecting every event for
## the rest of the battle — a no-op if `sink` was never added.
func remove_sink(sink: LogSink) -> void:
	_sinks.erase(sink)


func emit(event: LogEvent) -> void:
	for sink: LogSink in _sinks:
		sink.emit(event)
