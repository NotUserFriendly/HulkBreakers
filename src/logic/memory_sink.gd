class_name MemorySink
extends LogSink

## Collects events in memory so tests can assert on the event stream.

var events: Array[LogEvent] = []


func emit(event: LogEvent) -> void:
	events.append(event)


func events_of_kind(kind: StringName) -> Array[LogEvent]:
	return events.filter(func(e: LogEvent) -> bool: return e.kind == kind)
