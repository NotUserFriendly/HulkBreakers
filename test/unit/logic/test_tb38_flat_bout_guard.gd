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
##
## ## taskblock-46 Pass E: the planner is out of it, which is the whole point
##
## **This guard was re-pinned four times in two taskblocks and the fifth is where it
## stops.** The hashes were `1167294328` (tb38 Pass A) → `1554552115` (taskblock-45's
## planner swap) → `2102842205` (taskblock-46 Pass C, search verbs) → `239821190`
## (taskblock-46 Pass D, `Panic`) — every one of them a *deliberate* AI change, none
## of them a finding this guard could report.
##
## The reason was structural, not bad luck. The bout was two deliberately weaponless
## units who know of no enemy, which is precisely the state AI work keeps changing
## the behaviour of, so a guard written to assert "nothing changed flat play" had
## become an AI-behaviour change detector that went red whenever the AI changed on
## purpose. Its own previous note said the honest move was to narrow it to something
## with no planner in it rather than keep re-pinning; this is that.
##
## **The bout is now a scripted action queue.** Fixed moves, fixed facings, fixed
## turn ends, applied through the same `CombatState.resolve_until` the AI's own
## output goes through. What it still guards is everything under the planner —
## movement, per-cell facing, AP accounting, turn structure, the combat log's own
## shape and ordering — which is what a block with no business touching the AI would
## actually break. What it no longer guards is what the AI *decides*, and that was
## never something a hash could report usefully: a divergence said "the AI changed"
## and every reader already knew.
##
## The original rule stands undiluted for the new scope: **do not re-pin this to make
## a divergence disappear.** With no planner in it, a mismatch really is a bug again.
const GOLDEN_HASH: int = 511851792

## The same two units and the same flat board, driven by an authored queue instead
## of by a planner. Diagonals and reversals are in the script on purpose — a
## straight line down one row shares a coordinate at every step, and a facing bug
## that only shows on a diagonal survives that happily.
const SCRIPT: Array[Array] = [
	[0, Vector2i(2, 2)],
	[1, Vector2i(8, 3)],
	[0, Vector2i(4, 1)],
	[1, Vector2i(6, 5)],
	[0, Vector2i(3, 4)],
	[1, Vector2i(7, 2)],
]

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
	var state := CombatState.new(GridFixture.flat(12, 6), [a, b], MAP_SEED)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	var units: Array[Unit] = [a, b]
	var pathfinder := Pathfinder.new(state.grid, false)
	for step: Array in SCRIPT:
		var unit: Unit = units[int(step[0])]
		unit.ap = unit.max_ap
		state.force_current_unit(unit.id)
		var queue := ActionQueue.new(unit)
		var path: Array[Vector2i] = pathfinder.astar(unit.cell, step[1] as Vector2i)
		if not path.is_empty():
			queue.enqueue(MoveAction.new(unit, path), state)
		queue.enqueue(EndTurnAction.new(unit, mission), state)
		state.resolve_until(queue)
	return _reduce(sink.events)


func test_flat_bout_event_stream_matches_golden_hash() -> void:
	var reduced: String = _run_flat_bout()
	assert_eq(
		hash(reduced),
		GOLDEN_HASH,
		"flat-bout event stream diverged from its pinned baseline:\n%s" % reduced
	)


func test_flat_bout_is_itself_seed_deterministic() -> void:
	assert_eq(_run_flat_bout(), _run_flat_bout())


## **A hash over nothing is a hash that never goes red.** The scripted queue replaced
## a bout runner, and "the script silently enqueued no legal action" would leave this
## file green forever while guarding an empty string — the failure mode that made the
## old version worth narrowing in the first place, arriving from the other direction.
func test_the_scripted_bout_actually_produces_a_stream() -> void:
	var reduced: String = _run_flat_bout()

	var lines: PackedStringArray = reduced.split("\n")
	gut.p("scripted flat bout emitted %d event(s)" % lines.size())
	assert_gt(lines.size(), SCRIPT.size(), "at least one event per scripted step")
	assert_true(reduced.contains("move"), "the units actually moved")
	assert_true(reduced.contains("faced"), "and faced as they went")
	assert_true(reduced.contains("turn_end"), "and their turns ended")
