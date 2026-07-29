class_name AiPlanningBench
extends RefCounted

## taskblock-43: the per-pass measuring instrument the AI work is judged against.
##
## taskblock-35 demonstrated that a single end-of-block number lets a regrowth
## hide, so every pass reports its own figure. `FpsDumpSink` gives the
## turn-boundary hitch a live build feels; this gives the number underneath it —
## **milliseconds inside one unit's plan** — headless and repeatable, which the
## live dump is not.
##
## ## taskblock-45 Pass E: what this used to measure, and does not any more
##
## Most of this file was instrumentation for the engagement-score planner: a
## per-turn breakdown of its prologue, a full-versus-culled candidate comparison
## driven by its scorer, and a census of which of its branches ran. **All of it
## called functions that no longer exist**, and it went with the planner. What is
## left is the measurement that outlives any one planner — how long a plan takes,
## and how much geometry it builds.
##
## Both numbers now come from `AiPlanner`'s own counters rather than from timing
## `BoutRunner.step()` from outside, which mixed planning cost with damage
## resolution. That is better instrumentation and it is also the only kind that
## could have survived the planner swap, since it measures the seam rather than
## the implementation.
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
##
##     godot --headless --path . -s res://tools/bench_ai_planning.gd
##     godot --headless --path . -s res://tools/bench_ai_planning.gd -- --full
##     ./tools/bench_release.sh

const SEEDS: Array[int] = [31337, 4242, 90210, 1, 777]
const STEPS_PER_SEED := 12
const SQUAD_SIZE := 3
## taskblock-45 Pass D: the completion half of the report, matched to
## `test_full_mission.gd`'s own harness — same seed count and same order of turn
## cap, so the rate the bench reports and the rate `MIN_COMPLETION_RATE` gates on
## are answers to the same question.
const MISSION_SEEDS := 12
const MISSION_TURN_CAP := 100


func run(argv: PackedStringArray) -> void:
	if argv.has("--full") or argv.has("--head-to-head"):
		await _full_report()
		return
	await _single()


## The ordinary run: the planner over the 3v3 combat bout, which is the
## configuration the historical series has always used.
func _single() -> void:
	var metrics: Dictionary = await _measure_combat()
	print("=== AI planning bench ===")
	# tb44 Pass A: the numbers below say which build produced them, first line,
	# every run. taskblock-43's report had to explain at length why its figures
	# were not continuous with the historical series; that should never need
	# explaining again.
	print("%s" % BuildIdentity.describe())
	if not BuildIdentity.is_representative_of_play():
		print("  ^ NOT an exported release build — carries GDScript debug per-line overhead")
	print("seeds            : %s" % str(SEEDS))
	print("steps per seed   : %d, squad size %d" % [STEPS_PER_SEED, SQUAD_SIZE])
	print("plans timed      : %d" % AiPlanner.plans)
	print("ms per AI step   : %.1f" % float(metrics["ms_per_plan"]))
	print("ShotPlane per plan: %.1f" % float(metrics["planes_per_plan"]))
	print("candidates scored: %d" % UtilityPlanner.candidates_scored)
	print("turns with no positive-utility action: %d" % UtilityPlanner.empty_decisions)


## taskblock-45 Pass D: **the four rows the planner swap was decided on.**
##
## It ran as a head-to-head while both planners were alive; Pass E deleted the
## loser and it now reports one column. The comparison itself is recorded in
## `docs/SUPERSEDED.md` and in `AiPlanner`'s own doc comment. What stays useful is
## the SHAPE — completion rate, turns to complete, plan cost and geometry per turn,
## in one place, over a bout configured so completion is a question that can be
## asked at all. The next planner change finds an instrument waiting rather than
## one to rebuild, which is the whole lesson of BR45.02.
func _full_report() -> void:
	var mission: Dictionary = await _measure_mission()
	var combat: Dictionary = await _measure_combat()

	print("=== AI planning bench — full report ===")
	print("%s" % BuildIdentity.describe())
	if not BuildIdentity.is_representative_of_play():
		print("  ^ NOT an exported release build — carries GDScript debug per-line overhead.")
		print("    The release figure is the one that describes the game: tools/bench_release.sh")
	print("")
	print("--- completion, over the mission-shaped bout ---")
	print(
		(
			"%d seeds, 1v1 aggressive, turn cap %d, completion == EXTRACTED"
			% [MISSION_SEEDS, MISSION_TURN_CAP]
		)
	)
	print("completion rate           : %.0f%%" % (float(mission["completion_rate"]) * 100.0))
	print("turns to complete         : %.1f" % float(mission["turns_to_complete"]))
	print("per-unit plan cost (ms)   : %.2f" % float(mission["ms_per_plan"]))
	print("ShotPlane builds per turn : %.1f" % float(mission["planes_per_plan"]))
	print("outcomes                  : %s" % _outcomes_of(mission))
	print("")
	print("--- planning cost, over the 3v3 combat bout ---")
	print("seeds %s, squad size %d, %d steps each" % [str(SEEDS), SQUAD_SIZE, STEPS_PER_SEED])
	print("This configuration has no objective or extraction zone, so it never")
	print("EXTRACTS and completion is not a question it can answer — which is why")
	print("the rows above come from the other bout. It is the heavier planning load")
	print("of the two, so it is the honest place to read cost from.")
	print("per-unit plan cost (ms)   : %.2f" % float(combat["ms_per_plan"]))
	print("ShotPlane builds per turn : %.1f" % float(combat["planes_per_plan"]))
	print("")
	# `ms per AI step` is the historical series' own line and tools/bench_release.sh
	# greps for it to compute the debug/release ratio.
	print("ms per AI step   : %.1f" % float(combat["ms_per_plan"]))


## The completion question, asked exactly the way `test_full_mission.gd` asks it —
## same presets, same 1v1 shape, same `EXTRACTED`-means-completed definition, same
## order of turn cap. **Not a second opinion about what completion means.** A bench
## that measured it its own way could report a healthy rate while the real floor
## test went red, which would make the report worse than useless.
func _measure_mission() -> Dictionary:
	AiPlanner.reset_diagnostics()
	var profile_a: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	var profile_b: BotPreset = DataLibrary.get_preset(&"a_brand_laborer_battery_mods")
	var completed := 0
	var attempted := 0
	var turns_when_completed := 0
	# **Which way the other bouts ended, not just how many.** A completion rate
	# alone cannot tell "the squad died" from "the squad never finished", and those
	# want completely different responses — the first is a combat problem, the
	# second a pathing or objective one. taskblock-45 Pass D turned on exactly that
	# distinction: every failure under the new planner was TERMINATED, none
	# STRANDED, which is what made the drop a finishing problem rather than a
	# fighting one.
	var outcomes: Dictionary = {}

	for map_seed in range(MISSION_SEEDS):
		var built: Dictionary = BoutSetup.build_bout(
			[BoutRosterEntry.new(profile_a, &"aggressive")] as Array[BoutRosterEntry],
			[BoutRosterEntry.new(profile_b, &"aggressive")] as Array[BoutRosterEntry],
			map_seed
		)
		if built.get("error", "") != "":
			print("seed %d: %s" % [map_seed, built["error"]])
			continue
		attempted += 1
		var runner := BoutRunner.new(built["state"], built["mission"], MISSION_TURN_CAP)
		await runner.run_to_completion()
		var outcome: int = built["mission"].outcome
		var outcome_name: String = Enums.MissionOutcome.keys()[outcome]
		outcomes[outcome_name] = int(outcomes.get(outcome_name, 0)) + 1
		if outcome == Enums.MissionOutcome.EXTRACTED:
			completed += 1
			turns_when_completed += runner.turns_taken

	var summary: Dictionary = _summarize(completed, attempted, turns_when_completed)
	summary["outcomes"] = outcomes
	return summary


## The cost question, over the heavier 3v3 mixed-profile bout the historical
## series has always used. Runs a fixed number of steps rather than to a
## conclusion, so two runs are compared over the same amount of work.
func _measure_combat() -> Dictionary:
	AiPlanner.reset_diagnostics()
	UtilityPlanner.candidates_scored = 0
	UtilityPlanner.empty_decisions = 0

	for map_seed: int in SEEDS:
		var built: Dictionary = _bout(map_seed)
		if built.get("error", "") != "":
			print("seed %d: %s" % [map_seed, built["error"]])
			continue
		var runner := BoutRunner.new(built["state"], built["mission"])
		var step := 0
		while not runner.finished and step < STEPS_PER_SEED:
			await runner.step()
			step += 1

	return _summarize(0, 0, 0)


func _summarize(completed: int, attempted: int, turns_when_completed: int) -> Dictionary:
	var plans: int = AiPlanner.plans
	return {
		"completion_rate": float(completed) / float(attempted) if attempted > 0 else 0.0,
		"turns_to_complete":
		float(turns_when_completed) / float(completed) if completed > 0 else 0.0,
		"ms_per_plan": float(AiPlanner.plan_usec) / float(plans) / 1000.0 if plans > 0 else 0.0,
		"planes_per_plan": float(AiPlanner.plan_shot_planes) / float(plans) if plans > 0 else 0.0,
	}


func _outcomes_of(metrics: Dictionary) -> String:
	var parts: PackedStringArray = []
	var outcomes: Dictionary = metrics.get("outcomes", {})
	for outcome_name: String in outcomes:
		parts.append("%s %d" % [outcome_name, outcomes[outcome_name]])
	return " ".join(parts)


func _bout(map_seed: int) -> Dictionary:
	var pool: Array[BotPreset] = DataLibrary.presets_pool()
	# taskblock-46 Pass E: read straight off the authored profiles rather than a
	# vocabulary that named them indirectly, so a new profile widens the mix here
	# without a second edit.
	var profile_ids: Array[StringName] = []
	for profile: UtilityProfile in DataLibrary.utility_profiles_pool():
		profile_ids.append(profile.id)
	var roster_a: Array[BoutRosterEntry] = []
	var roster_b: Array[BoutRosterEntry] = []
	for i in range(SQUAD_SIZE):
		var a := BoutRosterEntry.new()
		a.profile = pool[i % pool.size()]
		a.ai_profile = profile_ids[i % profile_ids.size()]
		roster_a.append(a)
		var b := BoutRosterEntry.new()
		b.profile = pool[(i + 1) % pool.size()]
		b.ai_profile = profile_ids[(i + 2) % profile_ids.size()]
		roster_b.append(b)
	return BoutSetup.build_bout(roster_a, roster_b, map_seed)
