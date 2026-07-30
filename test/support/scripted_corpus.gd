class_name ScriptedCorpus
extends RefCounted

## taskblock-50 Pass C: **a bout the game could really produce, driven by an authored
## queue instead of by the planner.**
##
## ## Two corpora, two questions
##
## | corpus | subject | driven by |
## |---|---|---|
## | `BoutCorpus` | the AI's behaviour | random seeds, real planning |
## | **this one** | everything under the AI | one preset board, fixed actions |
##
## `BoutCorpus` plays AI-driven missions, which is right where the AI is the subject and
## wrong for the ~133 files that build a board by hand *precisely to keep the planner
## out*. Those files get the real resolution path here — two-phase turns, the action
## queue, the combat log, per-tile facing, AP accounting — with the AI removed as a
## failure mode rather than worked around.
##
## ## Why a real board rather than a hand-placed one
##
## A hand-built fixture is not free: it drifts. A test that assembles two bare torsos on
## a bare grid passes against a board the game cannot produce, and keeps passing after the
## real thing has changed shape underneath it. That is the audit's third outcome —
## *hand-built is quietly wrong* — and it is the one worth finding.
##
## So the board comes through `BoutSetup.build_bout`: real presets, real assembly, a real
## generated map. What is removed is only the decision-making.
##
## ## No planner, and it is asserted rather than intended
##
## Both squads are set to `HUMAN`, so nothing auto-resolves and `AIPlanner.plans` must not
## move while a script runs. **A scripted corpus that quietly plans is the failure mode**
## — it would be slower than the thing it replaced while claiming to be the cheap option,
## and its determinism would silently depend on the AI it was built to exclude.
## `test_scripted_corpus.gd` pins that in both directions.
##
## ## Records and fresh boards, unlike `BoutCorpus`
##
## `BoutCorpus` deliberately hands out records only, because replaying its missions is
## what costs. A scripted bout is cheap — no planning — so `fresh()` hands back a live
## board every time and there is no cache to corrupt. That difference is the reason these
## are two classes rather than one with a flag.

## Fixed, so every reader gets the same board. Changing it re-pins nothing automatically —
## a test that hashes a stream off this corpus has to be re-measured deliberately.
const MAP_SEED := 20260730

## Two a side: enough for facing, adjacency and opportunity attacks to be reachable,
## small enough that a scripted turn is cheap.
const SQUAD_SIZE := 2


## A live board built the way the game builds one, with nobody driving it.
##
## Returns `{state, mission, error}`. The error is passed through rather than asserted
## here: a fixture that fails to build should redden the test that asked for it, naming
## the reason, not trip an assertion inside a shared helper where the message loses its
## caller.
static func fresh(map_seed: int = MAP_SEED) -> Dictionary:
	var roster: Array[BoutRosterEntry] = []
	var presets: Array = DataLibrary.presets_pool()
	if presets.is_empty():
		return {"error": "no presets loaded — call DataLibrary.load_all() first"}
	for i in range(SQUAD_SIZE):
		var entry := BoutRosterEntry.new()
		entry.profile = presets[i % presets.size()]
		roster.append(entry)
	var built: Dictionary = BoutSetup.build_bout(roster, roster, map_seed)
	if String(built.get("error", "")) != "":
		return built
	var state: CombatState = built["state"]
	# **Both squads human, so nothing plans.** `BoutSetup` leaves controllers unassigned;
	# an overlay or a runner picking this board up would otherwise start planning for it.
	state.assign_all_to_human()
	return built


## Every living unit on the board, in turn order — the handle a script needs.
static func units(state: CombatState) -> Array[Unit]:
	var out: Array[Unit] = []
	for unit: Unit in state.units:
		if unit.alive:
			out.append(unit)
	return out


## Drive a board with an authored script and return the events it produced.
##
## Each step is `[unit_index, destination]`. The unit is made current and given a full
## turn's AP, a path is solved with the ordinary `Pathfinder`, and the move and turn-end
## go through `CombatState.resolve_until` — the same call the AI's own output goes
## through, which is what makes this a real resolution rather than a simulation of one.
##
## A step whose path cannot be solved still ends the unit's turn, so a script that asks
## for an unreachable cell produces a short stream rather than a stuck one. The caller
## sees it as missing `move` events, which is a readable failure.
static func drive(built: Dictionary, steps: Array[Array]) -> Array[LogEvent]:
	var state: CombatState = built["state"]
	var mission: MissionState = built["mission"]
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	var roster: Array[Unit] = units(state)
	var pathfinder := Pathfinder.new(state.grid, false)
	for step: Array in steps:
		var index: int = int(step[0])
		if index < 0 or index >= roster.size():
			continue
		var unit: Unit = roster[index]
		if not unit.alive:
			continue
		unit.ap = unit.max_ap
		state.force_current_unit(unit.id)
		var queue := ActionQueue.new(unit)
		var path: Array[Vector2i] = pathfinder.astar(unit.cell, step[1] as Vector2i)
		if not path.is_empty():
			queue.enqueue(MoveAction.new(unit, path), state)
		queue.enqueue(EndTurnAction.new(unit, mission), state)
		state.resolve_until(queue)

	state.combat_log.remove_sink(sink)
	return sink.events


## The stream reduced to a comparable string — the same shape the flat-bout guard uses,
## so a test that wants to pin a scripted stream has one way to do it rather than its own.
static func reduce(events: Array[LogEvent]) -> String:
	var rows: Array[String] = []
	for event: LogEvent in events:
		rows.append(
			"%d|%s|%d|%s|%s" % [event.turn, event.phase, event.unit_id, event.kind, event.text]
		)
	return "\n".join(rows)
