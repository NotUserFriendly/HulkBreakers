class_name LogPlayback
extends RefCounted

## docs/10 Phase 12.4: `resolve_turn()` is atomic and already emits a
## complete, deterministic event stream (docs/09) — the view REPLAYS that
## log, it never drives the simulation. This maps the recorded
## `Array[LogEvent]` to an ordered `Array[PlaybackCue]`; the Node layer just
## runs the cues at the times given. All timings are constants, here, once.

## Wait before the first cue plays, banner already up and input locked.
const RESOLVE_LEAD_IN := 1.0
## Extra gap after the last cue before the TACTICS banner returns and input
## unlocks.
const RESOLVE_TAIL := 1.0
## Consecutive projectiles (impacts) fan out by this much so a burst reads
## as a burst, not one simultaneous cue.
const PROJECTILE_STAGGER := 0.04

## Event kinds treated as projectiles for staggering purposes. Everything
## else in the stream plays at whatever time the stream has already reached
## — only a run of projectile impacts needs the fan-out.
const PROJECTILE_KINDS: Array[StringName] = [&"impact"]


## `events` in log order (docs/09 guarantees RESOLUTION emits them in the
## order they actually happened) -> one cue per event, timestamped from the
## start of playback (i.e. already past RESOLVE_LEAD_IN — a Node adds that
## as its own initial wait, not baked into these times).
static func build(events: Array[LogEvent]) -> Array[PlaybackCue]:
	var cues: Array[PlaybackCue] = []
	var t := 0.0
	for event: LogEvent in events:
		cues.append(PlaybackCue.new(t, event))
		if event.kind in PROJECTILE_KINDS:
			t += PROJECTILE_STAGGER
	return cues


## Total wall-clock time a full playback takes: lead-in, every cue, and the
## tail — what a Node waits before it's safe to unlock input and return to
## TACTICS. Empty streams still take lead-in + tail (a banner flash even
## when nothing happened is more honest than an instant snap-back).
static func total_duration(events: Array[LogEvent]) -> float:
	var cues: Array[PlaybackCue] = build(events)
	var last_cue_time: float = cues[-1].time if not cues.is_empty() else 0.0
	return RESOLVE_LEAD_IN + last_cue_time + RESOLVE_TAIL


## taskblock-19 Pass I2: "something on turn advance is blocking the main
## thread." `BattleScene.refresh_unit_views()` used to unconditionally
## rebuild EVERY unit's entire view every turn, even the units a normal
## turn never touches — this is the real, precise signal that lets a
## caller refresh only the ones a turn's own events actually named,
## instead. Every unit_id an event mentions, whether as the actor
## (`unit_id`) or a hit's own separate target (`data.target_unit_id` —
## docs/09: "a ricochet can tag a third party, never assumed to be the
## shooter's own original target").
static func affected_unit_ids(events: Array[LogEvent]) -> Array[int]:
	var ids: Dictionary = {}
	for event: LogEvent in events:
		ids[event.unit_id] = true
		var target_id: int = int(event.data.get("target_unit_id", -1))
		if target_id >= 0:
			ids[target_id] = true
	var result: Array[int] = []
	result.assign(ids.keys())
	return result
