extends GutTest

## docs/10 Phase 12.4: the view replays resolve_turn()'s recorded log; it
## never drives the simulation. LogPlayback is the pure mapping from
## Array[LogEvent] to an ordered, timestamped cue list.


func _event(kind: StringName) -> LogEvent:
	return LogEvent.new(0, Enums.Phase.RESOLUTION, 0, kind, {}, kind)


func test_a_known_event_stream_maps_to_the_expected_cue_list_with_expected_offsets() -> void:
	var events: Array[LogEvent] = [
		_event(&"turn_start"),
		_event(&"move"),
		_event(&"impact"),
		_event(&"impact"),
		_event(&"impact"),
		_event(&"part_destroyed"),
		_event(&"turn_end"),
	]

	var cues: Array[PlaybackCue] = LogPlayback.build(events)

	assert_eq(cues.size(), events.size(), "one cue per event, none dropped or merged")
	assert_eq(cues[0].time, 0.0, "turn_start")
	assert_eq(cues[1].time, 0.0, "move — not a projectile, no stagger yet")
	assert_eq(cues[2].time, 0.0, "the first impact plays immediately")
	assert_almost_eq(cues[3].time, LogPlayback.PROJECTILE_STAGGER, 0.0001, "second impact staggers")
	assert_almost_eq(
		cues[4].time, LogPlayback.PROJECTILE_STAGGER * 2.0, 0.0001, "third impact staggers again"
	)
	# part_destroyed isn't a projectile: it lands wherever the stream has
	# already reached, right after the third impact's own stagger step.
	assert_almost_eq(cues[5].time, LogPlayback.PROJECTILE_STAGGER * 3.0, 0.0001)
	assert_almost_eq(cues[6].time, LogPlayback.PROJECTILE_STAGGER * 3.0, 0.0001)

	for i in range(events.size()):
		assert_eq(cues[i].event, events[i], "cues must carry the original events, not copies")


func test_replaying_the_same_stream_twice_produces_an_identical_cue_list() -> void:
	var events: Array[LogEvent] = [
		_event(&"impact"), _event(&"impact"), _event(&"detonate"), _event(&"impact")
	]

	var first: Array[PlaybackCue] = LogPlayback.build(events)
	var second: Array[PlaybackCue] = LogPlayback.build(events)

	assert_eq(first.size(), second.size())
	for i in range(first.size()):
		assert_eq(first[i].time, second[i].time)
		assert_eq(first[i].event, second[i].event)


func test_total_duration_covers_lead_in_every_cue_and_the_tail() -> void:
	var events: Array[LogEvent] = [_event(&"impact"), _event(&"impact"), _event(&"impact")]
	var expected: float = (
		LogPlayback.RESOLVE_LEAD_IN
		+ LogPlayback.PROJECTILE_STAGGER * 2.0
		+ LogPlayback.RESOLVE_TAIL
	)
	assert_almost_eq(LogPlayback.total_duration(events), expected, 0.0001)


func test_total_duration_of_an_empty_stream_is_still_lead_in_plus_tail() -> void:
	assert_almost_eq(
		LogPlayback.total_duration([]),
		LogPlayback.RESOLVE_LEAD_IN + LogPlayback.RESOLVE_TAIL,
		0.0001
	)


## taskblock-19 Pass I2: "which units did this turn's events actually
## name" — every event's own actor (unit_id), plus a hit's own separate
## target (data.target_unit_id — a ricochet can tag a third party, never
## assumed to be the actor's own target).
func test_affected_unit_ids_collects_actors_and_impact_targets() -> void:
	var events: Array[LogEvent] = [
		LogEvent.new(0, Enums.Phase.RESOLUTION, 5, &"move", {}, ""),
		LogEvent.new(0, Enums.Phase.RESOLUTION, 5, &"impact", {"target_unit_id": 9}, ""),
		LogEvent.new(0, Enums.Phase.RESOLUTION, 5, &"impact", {"target_unit_id": 12}, ""),
	]

	var ids: Array[int] = LogPlayback.affected_unit_ids(events)

	assert_eq(ids.size(), 3)
	assert_true(5 in ids)
	assert_true(9 in ids)
	assert_true(12 in ids)


func test_affected_unit_ids_never_includes_the_no_unit_sentinel() -> void:
	var events: Array[LogEvent] = [
		LogEvent.new(0, Enums.Phase.RESOLUTION, 5, &"impact", {"target_unit_id": -1}, ""),
	]

	var ids: Array[int] = LogPlayback.affected_unit_ids(events)

	assert_eq(ids, [5], "-1 (cover/terrain, no real unit) must never appear")


func test_affected_unit_ids_deduplicates() -> void:
	var events: Array[LogEvent] = [
		LogEvent.new(0, Enums.Phase.RESOLUTION, 5, &"move", {}, ""),
		LogEvent.new(0, Enums.Phase.RESOLUTION, 5, &"faced", {}, ""),
	]

	assert_eq(LogPlayback.affected_unit_ids(events), [5])


func test_affected_unit_ids_of_an_empty_stream_is_empty() -> void:
	assert_eq(LogPlayback.affected_unit_ids([]), [] as Array[int])
