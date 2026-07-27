class_name AiPlanningBench
extends RefCounted

## taskblock-43: the per-pass measuring instrument the AI work is judged against.
##
## taskblock-35 demonstrated that a single end-of-block number lets a regrowth
## hide, so every pass reports its own figure. `FpsDumpSink` gives the
## turn-boundary hitch a live build feels; this gives the number underneath it —
## **milliseconds inside `UnitAI.plan_turn` per AI step** — headless and
## repeatable, which the live dump is not.
##
## It also answers taskblock-43 Pass B's behavioural acceptance: **how often does
## culling the candidate rectangle change the chosen cell?** At every AI decision
## it scores the full reachable set AND the culled one from the same state and
## compares, which is the honest per-decision rate rather than a
## whole-trajectory diff that would conflate one early divergence with many.
##
## ## taskblock-44 Pass A: why the body lives here and not in the entry point
##
## **An exported build cannot be driven by `-s res://...` — the flag is
## tools-only and an export template ignores it**, booting its main scene
## instead. Confirmed directly rather than assumed: `-s` naming a NONEXISTENT
## script produces the identical crash, so the argument was never read at all.
## The release measurement therefore needs a main-scene entry point, while the
## debug one keeps using `-s`.
##
## Two entry points, then — but **one implementation**, because a bench whose
## debug and release paths could drift measures nothing:
##
##     tools/bench_ai_planning.gd   SceneTree, for `-s` under the editor binary
##     tools/bench_main.gd          Node, the `bench`-feature main scene
##
## `SEEDS`/`STEPS_PER_SEED` below are the knobs; keep them fixed when comparing
## two builds or the numbers mean nothing.

const SEEDS: Array[int] = [31337, 4242, 90210, 1, 777]
const STEPS_PER_SEED := 12
const SQUAD_SIZE := 3
## The Pass B comparison scores every decision TWICE, which is real work on the
## same process. It sits outside the timed region, but a timing run and a
## rate-measuring run are still not the same experiment — take the ms figure
## with this off, the difference rate with it on, and never quote both from one
## run. `--compare` / `--no-compare` on the command line override it.
const COMPARE_CANDIDATE_SETS := true


func run(argv: PackedStringArray) -> void:
	var compare: bool = COMPARE_CANDIDATE_SETS
	if argv.has("--no-compare"):
		compare = false
	elif argv.has("--compare"):
		compare = true
	# tb43 Pass D: `--batched` puts every unit of squad 1 into one batch, leaving
	# squad 0 independent, so a single run measures a leader's turn, a follower's
	# turn and an unbatched turn against the same maps and the same seeds. The
	# pass's acceptance is "a follower is dramatically cheaper than a leader", and
	# comparing across two separate runs would compare different trajectories.
	var batched: bool = argv.has("--batched")
	var profile: bool = argv.has("--profile")
	var profile_totals: Dictionary = {
		"turns": 0,
		"reachable": 0,
		"field_build": 0,
		"any_lof_scan": 0,
		"engagement_search": 0,
		"nearest_enemy": 0
	}
	var total_steps := 0
	var total_usec := 0
	var decisions := 0
	var differing := 0
	var full_candidates := 0
	var culled_candidates := 0
	# role -> [steps, usec]
	var by_role: Dictionary = {"independent": [0, 0], "leader": [0, 0], "follower": [0, 0]}
	var branches: Dictionary = {}

	for map_seed: int in SEEDS:
		var built: Dictionary = _bout(map_seed)
		if built.get("error", "") != "":
			print("seed %d: %s" % [map_seed, built["error"]])
			continue
		var state: CombatState = built["state"]
		var mission: MissionState = built["mission"]
		if batched:
			for unit: Unit in state.units:
				if unit.squad_id == 1:
					unit.batch_id = 1
		var runner := BoutRunner.new(state, mission)
		var sink := MemorySink.new()
		state.combat_log.add_sink(sink)

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
			# Read BEFORE the step: afterwards this unit has claimed the lead and
			# would read as a leader whichever role it actually played.
			var role: String = _role_of(unit, state)
			if profile:
				_profile_turn(unit, state, profile_totals)

			var started: int = Time.get_ticks_usec()
			runner.step()
			var spent: int = Time.get_ticks_usec() - started
			total_usec += spent
			total_steps += 1
			(by_role[role] as Array)[0] += 1
			(by_role[role] as Array)[1] += spent
			step += 1
		for event: LogEvent in sink.events:
			if event.kind == &"ai_decision":
				var branch: StringName = event.data["branch"]
				branches[branch] = int(branches.get(branch, 0)) + 1

	print("=== tb43 AI planning bench ===")
	# tb44 Pass A: the numbers below say which build produced them, first line,
	# every run. taskblock-43's report had to explain at length why its figures
	# were not continuous with the historical series; that should never need
	# explaining again.
	print("%s" % BuildIdentity.describe())
	if not BuildIdentity.is_representative_of_play():
		print("  ^ NOT an exported release build — carries GDScript debug per-line overhead")
	print("seeds            : %s" % str(SEEDS))
	print("steps per seed   : %d, squad size %d" % [STEPS_PER_SEED, SQUAD_SIZE])
	print("AI steps timed   : %d" % total_steps)
	if total_steps > 0:
		print("ms per AI step   : %.1f" % (float(total_usec) / float(total_steps) / 1000.0))
	print("candidates skipped by the Pass A early-out: %d" % UnitAI.candidates_skipped)
	if batched:
		print("--- Pass D: cost per turn by batch role ---")
		for role: String in ["independent", "leader", "follower"]:
			var bucket: Array = by_role[role]
			if int(bucket[0]) == 0:
				print("%-12s: no turns" % role)
				continue
			print(
				(
					"%-12s: %5.1f ms over %d turns"
					% [role, float(bucket[1]) / float(bucket[0]) / 1000.0, bucket[0]]
				)
			)
	if profile and int(profile_totals["turns"]) > 0:
		print("--- where a turn's time goes (mean per turn) ---")
		var turns: float = float(profile_totals["turns"])
		for key: String in [
			"reachable", "field_build", "any_lof_scan", "engagement_search", "nearest_enemy"
		]:
			print("%-18s: %6.1f ms" % [key, float(profile_totals[key]) / turns / 1000.0])
	print("--- which branch _plan_ranged took ---")
	for branch: StringName in branches:
		print("%-20s: %d" % [branch, branches[branch]])
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


## `--profile`: where a repositioning turn's time actually goes, by re-running
## `_plan_ranged`'s own prologue piece by piece against the same state and timing
## each. Added when Pass D's leader-vs-follower gap came out at 5% instead of the
## order of magnitude the block expected — the answer being that the positional
## search is not the whole cost of a turn, and everything before it is paid by
## leader and follower alike.
func _profile_turn(unit: Unit, state: CombatState, totals: Dictionary) -> void:
	if unit == null or not unit.alive or unit.shutdown:
		return
	var enemy: Unit = UnitAI._nearest_living_enemy(unit, state)
	if enemy == null:
		return
	var weapon_id: StringName = UnitAI._find_weapon_id(unit)
	var weapon: Part = unit.shell.find_part(weapon_id) if weapon_id != &"" else null
	var playstyle: StringName = unit.matrix.playstyle if unit.matrix != null else &"AGGRESSIVE"
	var preferred_range: int = _preferred_range_for(playstyle)
	var weight_cover: bool = playstyle in [&"COVER_SEEKER", &"TURTLE"]

	var mark: int = Time.get_ticks_usec()
	var pf := Pathfinder.new(state.grid, unit.shell.can_climb())
	var reachable: Array[Vector2i] = pf.reachable(unit.cell, unit.mp_per_ap() * unit.ap)
	if not reachable.has(unit.cell):
		reachable.append(unit.cell)
	totals["reachable"] += Time.get_ticks_usec() - mark

	# tb44 Pass B: the field is built once per target per turn and then shared, so
	# it is timed as its own line rather than folded into the scan it replaces.
	# Without this the profile would keep reporting the pre-inversion path and
	# quietly claim the pass changed nothing.
	mark = Time.get_ticks_usec()
	var field: VisibilityField = VisibilityField.build(state, enemy.cell)
	totals["field_build"] += Time.get_ticks_usec() - mark

	var lof_cache: Dictionary = {}
	mark = Time.get_ticks_usec()
	UnitAI._any_reachable_has_lof(unit, enemy, state, reachable, weapon, lof_cache, field)
	totals["any_lof_scan"] += Time.get_ticks_usec() - mark

	var culled: Array[Vector2i] = EngagementRect.cull(
		unit, enemy, UnitAI._target_distance(weapon, preferred_range), reachable
	)
	mark = Time.get_ticks_usec()
	UnitAI._pick_engagement_position(
		unit, enemy, state, preferred_range, weight_cover, weapon, culled, true, lof_cache, field
	)
	totals["engagement_search"] += Time.get_ticks_usec() - mark

	mark = Time.get_ticks_usec()
	UnitAI._nearest_living_enemy(unit, state)
	totals["nearest_enemy"] += Time.get_ticks_usec() - mark
	totals["turns"] += 1


## Which part this unit is about to play in its batch, read BEFORE its turn
## runs: independent, the leader that will claim this round, or a follower that
## will read a plan someone already recorded.
func _role_of(unit: Unit, state: CombatState) -> String:
	if unit == null or unit.batch_id == 0:
		return "independent"
	if state.batch_plans.plan_to_follow(unit, state.round_number).is_empty():
		return "leader"
	return "follower"


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
