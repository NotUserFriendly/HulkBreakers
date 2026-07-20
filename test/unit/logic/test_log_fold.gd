extends GutTest

## taskblock-22 Pass F: "action-level summary by default, drill down for
## detail — nothing filtered away, folded and drillable." Direct,
## synthetic LogEvents wherever the classification itself is under test
## (exact control over the sequence); real actions through a real
## CombatState wherever the taskblock's own F2 promise — "the underlying
## LogEvent stream is unchanged" — is what's actually being proven.


func _impact(
	unit_id: int,
	outcome: Enums.Outcome,
	part: StringName,
	target_unit_id: int = -1,
	damage: float = 1.0,
	bypassed: bool = false
) -> LogEvent:
	return (
		LogEvent
		. new(
			0,
			Enums.Phase.RESOLUTION,
			unit_id,
			&"impact",
			{
				"outcome": outcome,
				"part": part,
				"target_unit_id": target_unit_id,
				"damage": damage,
				"bypassed_armor": bypassed,
			},
			"%s on %s" % [Enums.Outcome.keys()[outcome], part]
		)
	)


func _miss(unit_id: int) -> LogEvent:
	return LogEvent.new(
		0, Enums.Phase.RESOLUTION, unit_id, &"miss", {"end_x": 5.0, "end_y": 0.0}, "missed"
	)


func _faced(unit_id: int, reason: StringName) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		unit_id,
		&"faced",
		{"direction": 0.0, "cost": 0.0, "reason": reason},
		"faced (%s)" % reason
	)


func _move(unit_id: int, path: Array[Vector2i], destination: Vector2i) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.RESOLUTION,
		unit_id,
		&"move",
		{"path": path, "destination": destination},
		"moved to %s" % destination
	)


func _cascade(unit_id: int, kind: StringName, data: Dictionary = {}) -> LogEvent:
	return LogEvent.new(0, Enums.Phase.RESOLUTION, unit_id, kind, data, str(kind))


func _admin(kind: StringName, text: String) -> LogEvent:
	return LogEvent.new(0, Enums.Phase.RESOLUTION, -1, kind, {}, text)


## F1: "a summary line per action" with the correct hit/miss count.
func test_attack_summary_has_the_correct_hit_and_miss_count() -> void:
	var fold := LogFold.new()
	fold.ingest(_impact(0, Enums.Outcome.STOP_DEAD, &"torso", 2, 1.0))
	fold.ingest(_miss(0))
	fold.ingest(_miss(0))
	var group: LogFoldGroup = fold.ingest(_miss(0))

	assert_eq(group.kind, &"attack")
	assert_eq(group.hits, 1)
	assert_eq(group.misses, 3)
	assert_true(group.summary.contains("1 hits"))
	assert_true(group.summary.contains("3 miss"))


## F1: "fold identical adjacent results with a count" — 3x Miss, not
## three lines.
func test_identical_adjacent_results_fold_with_a_count() -> void:
	var fold := LogFold.new()
	fold.ingest(_miss(0))
	fold.ingest(_miss(0))
	var group: LogFoldGroup = fold.ingest(_miss(0))

	assert_eq(group.detail_lines(), ["3× Miss"])


## Non-adjacent identical results must NOT fold across a distinguishing
## hit in between — folding is adjacency-only, never a global tally.
func test_non_adjacent_identical_results_do_not_fold_together() -> void:
	var fold := LogFold.new()
	fold.ingest(_miss(0))
	fold.ingest(_impact(0, Enums.Outcome.DEFLECT, &"plate", -1, 2.0))
	var group: LogFoldGroup = fold.ingest(_miss(0))

	var lines: Array[String] = group.detail_lines()
	assert_eq(lines.size(), 3, "Miss, Hit, Miss — never folded across the Hit between them")
	assert_eq(lines[0], "Miss")
	assert_eq(lines[2], "Miss")


## F1: "Unit 0 moved 4 tiles (-> 3,7) instead of four move-logs + four
## face-logs" — a curved path's interleaved faced/move/faced/move run
## (MoveAction.apply_stepwise's own documented shape) folds to ONE group.
func test_a_curved_move_folds_every_leg_into_one_group() -> void:
	var fold := LogFold.new()
	fold.ingest(_faced(0, &"free_with_move"))
	fold.ingest(_move(0, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], Vector2i(2, 0)))
	fold.ingest(_faced(0, &"free_with_move"))
	var group: LogFoldGroup = fold.ingest(
		_move(0, [Vector2i(2, 0), Vector2i(2, 1)], Vector2i(2, 1))
	)

	assert_eq(group.kind, &"move")
	assert_eq(fold.groups.size(), 1, "one group, not four move/face lines")
	assert_true(group.summary.contains("moved 3 tile"))
	assert_true(group.summary.contains("2, 1"))


## F1/F2: "expanding shows every underlying event" — nothing is filtered
## away, only folded for the default view.
func test_expanding_a_group_shows_every_underlying_event() -> void:
	var fold := LogFold.new()
	var a := _faced(0, &"free_with_move")
	var b := _move(0, [Vector2i(0, 0), Vector2i(1, 0)], Vector2i(1, 0))
	fold.ingest(a)
	var group: LogFoldGroup = fold.ingest(b)

	assert_eq(group.events, [a, b])
	assert_eq(group.detail_lines().size(), 2, "both the faced and the move are drillable")


## A cascade event (part_mangled, ...) attaches to its own Hit line
## instead of adding a second line for the same impact.
func test_a_cascade_event_appends_to_its_own_hit_line_not_a_new_one() -> void:
	var fold := LogFold.new()
	fold.ingest(_impact(0, Enums.Outcome.STOP_DEAD, &"plate", 2, 4.0))
	var group: LogFoldGroup = fold.ingest(_cascade(0, &"part_mangled", {"part": &"plate"}))

	var lines: Array[String] = group.detail_lines()
	assert_eq(lines.size(), 1, "still one line for this one hit")
	assert_true(lines[0].contains("mangled"))
	assert_eq(group.events.size(), 2, "the cascade event itself is still recorded, undropped")


## A standalone, player-queued FaceAction (manual_first/manual_free) is
## its own one-line group, never merged into an attack or move group.
func test_a_standalone_face_action_is_its_own_group() -> void:
	var fold := LogFold.new()
	fold.ingest(_impact(0, Enums.Outcome.PENETRATE, &"torso", 1, 3.0))
	var group: LogFoldGroup = fold.ingest(_faced(0, &"manual_first"))

	assert_eq(group.kind, &"face")
	assert_eq(fold.groups.size(), 2, "the attack and the standalone face are separate rows")


## Any event kind the folder doesn't specifically recognize (turn_start,
## and anything authored later) still shows up, verbatim, as its own
## admin row — never silently dropped.
func test_an_unrecognized_event_kind_still_gets_its_own_row() -> void:
	var fold := LogFold.new()
	var event := _admin(&"turn_start", "Turn 3 — unit 2")
	var group: LogFoldGroup = fold.ingest(event)

	assert_eq(group.kind, &"admin")
	assert_eq(group.summary, event._to_string())


## A burst's own weapon name (from &"burst_fired") drives the summary
## label; a plain (non-burst) attack has no weapon in the event data at
## all and falls back to a generic label rather than guessing.
func test_burst_fired_names_the_weapon_a_plain_attack_does_not() -> void:
	var fold := LogFold.new()
	var burst_group: LogFoldGroup = fold.ingest(
		LogEvent.new(
			0,
			Enums.Phase.RESOLUTION,
			0,
			&"burst_fired",
			{"weapon": &"unauthored_weapon_id", "round_count": 3},
			"burst"
		)
	)
	assert_true(burst_group.summary.contains("Burst"))

	var plain_fold := LogFold.new()
	var plain_group: LogFoldGroup = plain_fold.ingest(_miss(0))
	assert_true(plain_group.summary.contains("Attack"))


## "unit N down" — derived from the live CombatState (LogFold.state),
## never a new LogEvent kind, so it must gracefully omit when no state is
## given, and appear once the target's own alive flag actually flips.
func test_unit_down_suffix_only_appears_with_a_live_state_and_a_dead_target() -> void:
	var root := Part.new()
	root.id = &"root"
	root.hp = 1
	root.max_hp = 1
	var target := Unit.new(Matrix.new(), Shell.new(root), Vector2i(1, 0), 1)
	var shooter := Unit.new(Matrix.new(), Shell.new(root.duplicate(true)), Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [shooter, target])

	var stateless_fold := LogFold.new()
	var stateless_group: LogFoldGroup = stateless_fold.ingest(
		_impact(0, Enums.Outcome.STOP_DEAD, &"root", target.id, 1.0)
	)
	assert_false(stateless_group.summary.contains("down"), "no state given, no down suffix")

	var live_fold := LogFold.new(state)
	live_fold.ingest(_impact(0, Enums.Outcome.STOP_DEAD, &"root", target.id, 1.0))
	state.kill_unit(target)
	var live_group: LogFoldGroup = live_fold.ingest(_miss(0))
	assert_true(live_group.summary.contains("unit %d down" % target.id))


## F2: "don't lose determinism" — folding is a rendering-time VIEW; the
## underlying stream every other sink sees (MemorySink here, standing in
## for FileSink's own identical guarantee, see test_hierarchical_ui_sink.gd)
## is exactly as many events as the real action actually emitted, whether
## or not a HierarchicalUiSink is also attached.
func test_folding_never_changes_what_other_sinks_on_the_same_log_receive() -> void:
	var root := Part.new()
	root.id = &"root"
	root.hp = 10
	root.max_hp = 10
	var mover := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [mover])
	var memory_sink := MemorySink.new()
	var fold_sink := HierarchicalUiSink.new(null, state)
	state.combat_log.add_sink(memory_sink)
	state.combat_log.add_sink(fold_sink)

	# A curved path — down, then right — the exact "spam" case F1 exists
	# to fold, forcing multiple faced/move pairs in the raw stream.
	var path: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)
	]
	MoveAction.new(mover, path).apply(state)

	var raw_count: int = memory_sink.events.size()
	assert_gt(raw_count, 1, "sanity: a curved path really does emit more than one raw event")

	var folded_event_total := 0
	for group: LogFoldGroup in fold_sink.fold.groups:
		folded_event_total += group.events.size()
	assert_eq(
		folded_event_total,
		raw_count,
		"every raw event the MemorySink saw must also be accounted for inside the fold"
	)
	assert_eq(
		fold_sink.fold.groups.size(), 1, "the whole curved path still folds into one move group"
	)
