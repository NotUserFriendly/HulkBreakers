extends SceneTree

## taskblock-43: the per-pass measuring instrument this block is written around.
##
## taskblock-35 demonstrated that a single end-of-block number lets a regrowth
## hide, so every pass here reports its own figure. `FpsDumpSink` gives the
## turn-boundary hitch a live build feels; this gives the number underneath it —
## **milliseconds inside `UnitAI.plan_turn` per AI step** — headless and
## repeatable, which the live dump is not.
##
## It also answers Pass B's own behavioural acceptance: **how often does culling
## the candidate rectangle change the chosen cell?** At every AI decision it
## scores the full reachable set AND the culled one from the same state and
## compares, which is the honest per-decision rate rather than a
## whole-trajectory diff that would conflate one early divergence with many.
##
##     godot --headless --path . -s res://tools/bench_ai_planning.gd
##
## `SEEDS`/`STEPS_PER_SEED` below are the knobs; keep them fixed when comparing
## two builds or the number means nothing.

const SEEDS: Array[int] = [31337, 4242, 90210, 1, 777]
const STEPS_PER_SEED := 12
const SQUAD_SIZE := 3
## The Pass B comparison scores every decision TWICE, which is real work on the
## same process. It sits outside the timed region, but a timing run and a
## rate-measuring run are still not the same experiment — take the ms figure
## with this off, the difference rate with it on, and never quote both from one
## run. `--compare` / `--no-compare` on the command line override it.
const COMPARE_CANDIDATE_SETS := true


func _init() -> void:
	var compare: bool = COMPARE_CANDIDATE_SETS
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.has("--no-compare"):
		compare = false
	elif argv.has("--compare"):
		compare = true
	var total_steps := 0
	var total_usec := 0
	var decisions := 0
	var differing := 0
	var full_candidates := 0
	var culled_candidates := 0

	for map_seed: int in SEEDS:
		var built: Dictionary = _bout(map_seed)
		if built.get("error", "") != "":
			print("seed %d: %s" % [map_seed, built["error"]])
			continue
		var state: CombatState = built["state"]
		var mission: MissionState = built["mission"]
		var runner := BoutRunner.new(state, mission)

		var step := 0
		while not runner.finished and step < STEPS_PER_SEED:
			var unit: Unit = state.current_unit()
			var sample: Dictionary = _compare_candidate_sets(unit, state) if compare else {}
			if not sample.is_empty():
				decisions += 1
				full_candidates += int(sample["full_count"])
				culled_candidates += int(sample["culled_count"])
				if sample["full_cell"] != sample["culled_cell"]:
					differing += 1

			var started: int = Time.get_ticks_usec()
			runner.step()
			total_usec += Time.get_ticks_usec() - started
			total_steps += 1
			step += 1

	print("=== tb43 AI planning bench ===")
	print("seeds            : %s" % str(SEEDS))
	print("AI steps timed   : %d" % total_steps)
	if total_steps > 0:
		print("ms per AI step   : %.1f" % (float(total_usec) / float(total_steps) / 1000.0))
	print("candidates skipped by the Pass A early-out: %d" % UnitAI.candidates_skipped)
	print("--- Pass B: culled rectangle vs. full reachable ---")
	print("decisions sampled: %d" % decisions)
	if decisions > 0:
		print(
			(
				"chosen cell differs: %d (%.1f%%)"
				% [differing, 100.0 * float(differing) / float(decisions)]
			)
		)
		print(
			(
				"mean candidates  : %.1f full -> %.1f culled"
				% [
					float(full_candidates) / float(decisions),
					float(culled_candidates) / float(decisions),
				]
			)
		)
		if full_candidates > 0:
			print(
				(
					"candidate set retained: %.1f%%"
					% (100.0 * float(culled_candidates) / float(full_candidates))
				)
			)
	quit()


## Both choices from ONE state, at the point in `_plan_ranged` where the cull is
## actually applied. Empty when this unit isn't in a position to make a
## positional decision at all (dead, unarmed, no living enemy), so those turns
## don't dilute the rate.
func _compare_candidate_sets(unit: Unit, state: CombatState) -> Dictionary:
	if unit == null or not unit.alive or unit.shutdown:
		return {}
	var enemy: Unit = UnitAI._nearest_living_enemy(unit, state)
	if enemy == null:
		return {}
	var weapon_id: StringName = UnitAI._find_weapon_id(unit)
	var weapon: Part = unit.shell.find_part(weapon_id) if weapon_id != &"" else null

	var playstyle: StringName = unit.matrix.playstyle if unit.matrix != null else &"AGGRESSIVE"
	var preferred_range: int = _preferred_range_for(playstyle)
	var weight_cover: bool = playstyle in [&"COVER_SEEKER", &"TURTLE"]

	var pf := Pathfinder.new(state.grid, unit.shell.can_climb())
	var reachable: Array[Vector2i] = pf.reachable(unit.cell, unit.mp_per_ap() * unit.ap)
	if not reachable.has(unit.cell):
		reachable.append(unit.cell)
	var culled: Array[Vector2i] = EngagementRect.cull(
		unit, enemy, UnitAI._target_distance(weapon, preferred_range), reachable
	)

	var full_cell: Vector2i = UnitAI._pick_engagement_position(
		unit, enemy, state, preferred_range, weight_cover, weapon, reachable, true, {}
	)
	var culled_cell: Vector2i = UnitAI._pick_engagement_position(
		unit, enemy, state, preferred_range, weight_cover, weapon, culled, true, {}
	)
	return {
		"full_cell": full_cell,
		"culled_cell": culled_cell,
		"full_count": reachable.size(),
		"culled_count": culled.size(),
	}


## The bench authors its own copy of the playstyle table deliberately
## (CLAUDE.md: "if a test needs a concrete list, the test authors it as a
## fixture") — reading it back out of the planner would make the bench agree
## with the planner by construction even if the planner were wrong.
func _preferred_range_for(playstyle: StringName) -> int:
	match playstyle:
		&"SKIRMISHER", &"COVER_SEEKER", &"TURTLE":
			return UnitAI.SKIRMISHER_PREFERRED_RANGE
		&"MARKSMAN":
			return UnitAI.MARKSMAN_PREFERRED_RANGE
		_:
			return UnitAI.AGGRESSIVE_PREFERRED_RANGE


func _bout(map_seed: int) -> Dictionary:
	var pool: Array[BotPreset] = DataLibrary.presets_pool()
	var roster_a: Array[BoutRosterEntry] = []
	var roster_b: Array[BoutRosterEntry] = []
	for i in range(SQUAD_SIZE):
		var a := BoutRosterEntry.new()
		a.profile = pool[i % pool.size()]
		a.playstyle = UnitAI.PLAYSTYLES[i % UnitAI.PLAYSTYLES.size()]
		roster_a.append(a)
		var b := BoutRosterEntry.new()
		b.profile = pool[(i + 1) % pool.size()]
		b.playstyle = UnitAI.PLAYSTYLES[(i + 2) % UnitAI.PLAYSTYLES.size()]
		roster_b.append(b)
	return BoutSetup.build_bout(roster_a, roster_b, map_seed)
