class_name LogSink
extends RefCounted

## Base for pluggable combat-log destinations (docs/09). Never hardcode a
## destination in CombatLog itself — add a new LogSink subclass instead.


func emit(_event: LogEvent) -> void:
	pass
