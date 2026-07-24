extends GutTest

## taskblock-38 (docs/taskblock38.md): "capture a seeded FLAT bout (all
## level 0, no ramps) and diff its event stream after every pass. It must
## stay byte-identical throughout — nothing here changes flat play.
## Divergence is the finding; do not re-seed to make it green."
##
## A small, deliberately weaponless two-unit AI-vs-AI bout on a bare
## (already flat-by-construction — `Grid._init` fills `level` with 0.0 and
## `terrain` with OPEN everywhere) Grid, run to its turn cap, reduced to a
## comparable string and hashed. GOLDEN_HASH was captured against this
## taskblock's own Pass A baseline, before any pass changes real behavior —
## it must never be edited to make a later pass's divergence disappear; a
## mismatch means some pass touched flat play, which this whole taskblock
## promises not to.
const GOLDEN_HASH: int = 1167294328

const TURN_CAP: int = 30
const MAP_SEED: int = 20260724


func _make_unit(id_hint: String, cell: Vector2i, squad: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id_hint)
	torso.hp = 10
	torso.max_hp = 10
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func _reduce(events: Array[LogEvent]) -> String:
	var rows: Array[String] = []
	for event: LogEvent in events:
		rows.append(
			"%d|%s|%d|%s|%s" % [event.turn, event.phase, event.unit_id, event.kind, event.text]
		)
	return "\n".join(rows)


func _run_flat_bout() -> String:
	var a: Unit = _make_unit("a", Vector2i(1, 1), 0)
	var b: Unit = _make_unit("b", Vector2i(9, 4), 1)
	var state := CombatState.new(Grid.new(12, 6), [a, b], MAP_SEED)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	BoutRunner.new(state, mission, TURN_CAP).run_to_completion()
	return _reduce(sink.events)


func test_flat_bout_event_stream_matches_golden_hash() -> void:
	var reduced: String = _run_flat_bout()
	assert_eq(
		hash(reduced),
		GOLDEN_HASH,
		"flat-bout event stream diverged from the tb38 Pass A baseline:\n%s" % reduced
	)


func test_flat_bout_is_itself_seed_deterministic() -> void:
	assert_eq(_run_flat_bout(), _run_flat_bout())
