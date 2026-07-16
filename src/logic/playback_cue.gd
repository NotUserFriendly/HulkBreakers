class_name PlaybackCue
extends RefCounted

## One entry in a resolution replay (docs/10 Phase 12.4): `event` verbatim
## from the combat log, plus when to play it, in seconds from the moment
## RESOLUTION's playback actually starts (after RESOLVE_LEAD_IN has
## already elapsed — see LogPlayback).

var time: float
var event: LogEvent


func _init(p_time: float = 0.0, p_event: LogEvent = null) -> void:
	time = p_time
	event = p_event
