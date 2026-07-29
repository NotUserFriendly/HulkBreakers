class_name CompletionSampler
extends RefCounted

## taskblock-46 Pass B: **can a mission be completed at all**, asked as a sample
## rather than as a fixed window.
##
## ## Why the pinned window had to go
##
## The harness this replaces asked seeds 0–11, every run, forever. Two problems,
## both of which bit:
##
## - **It was the pessimistic window.** Seeds 0–11 measured 41.7% while 12–23
##   measured 66.7% on the identical build — a 25-point spread the test could not
##   see, so its number read as *the* completion rate when it was one draw of
##   twelve.
## - **A threshold between two adjacent integers is a tripwire.** At 5/12 against a
##   0.35 floor it sat less than one seed from red, and the recorded response to a
##   flapping floor has twice been to lower the constant.
##
## Sampling fixes the first and escalation fixes the second.
##
## ## Sample to notice, escalate to measure
##
## `sample()` draws `SAMPLE_SEEDS` seeds at random and is deliberately **not**
## deterministic: over many runs it walks the whole seed space instead of
## re-asking the same twelve questions. It prints every seed it drew, which is what
## makes any run reproducible after the fact.
##
## A sample below the floor proves nothing on its own — even at a healthy rate a
## short draw dips by chance sometimes. So the sample only
## ever *notices*; `escalate()` runs a fixed seed list and is the measurement the
## verdict comes from. **Deterministic where the sampler is not**, so a failure is
## reproducible and a pass is not luck.
##
## ## Escalation frequency is itself the metric
##
## `escalation_probability()` gives the exact chance a sample dips below the floor
## at a given true rate. At a healthy rate that is near zero and escalation is
## rare; at a marginal rate it is common, and **a suite that escalates often is
## telling you the planner is marginal** regardless of what any single run
## concluded. That number is worth reading on its own — it is the one figure here
## that does not depend on which seeds happened to come up.

## Seeds drawn per sample. **Re-derived at taskblock-47 Pass C, not adjusted.**
##
## taskblock-46 sized this at 20 when the escalation ran inside `run_tests.sh`, so a
## sample that dipped cost the suite an extra ~330 s automatically and the only thing
## worth optimising was how rarely that happened. **The escalation is a manual command
## now** (`tools/probe_seeds.gd`), so an escalation costs a person deciding to run one
## rather than suite time, and the trade moves: the gate should be cheap and dipping
## should merely be informative.
##
## At the currently measured 0.56 completion rate against the 0.35 floor, ~12.2 s per
## seed:
##
## | n | demands | P(escalate) | ~1 run in | gate cost |
## |---|---|---|---|---|
## | 5 | 40.0% | 0.121 | 8 | 61 s |
## | 6 | 50.0% | 0.239 | 4 | 73 s |
## | **8** | **37.5%** | **0.079** | **13** | **98 s** |
## | 10 | 40.0% | 0.091 | 11 | 122 s |
## | 15 | 40.0% | 0.066 | 15 | 183 s |
## | 20 | 35.0% | 0.017 | 58 | 244 s |
##
## **8 costs 146 s less than 20 and still only asks for an escalation about one run in
## thirteen.** The non-monotonicity taskblock-46 found is worse here than it was there
## and is the reason this cannot be eyeballed: **n=6 is three times more likely to
## escalate than n=8 despite being smaller**, because the threshold is an integer count
## and `ceil(0.35 x 6) = 3` demands 50% where `ceil(0.35 x 8) = 3` demands 37.5%.
## Picking a round number here would have been actively worse than picking a bigger one.
const SAMPLE_SEEDS := 8
## The escalation's fixed seed list — `0` to `ESCALATION_SEEDS - 1`. Flagged, not
## tuned; it trades runtime against confidence and nothing else.
const ESCALATION_SEEDS := 100
## Matches `test_full_mission.gd`'s own cap, so the sampler and the floor it is
## checked against are answers to the same question.
const TURN_CAP := 100

## How many times `sample()` has fallen below its floor since the process started.
## Diagnostics only; never read by a decision.
static var escalations: int = 0


## One bout. Returns the outcome name and the turns it took, or an empty dictionary
## when the bout could not even be built.
static func run_seed(map_seed: int) -> Dictionary:
	var profile_a: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	var profile_b: BotPreset = DataLibrary.get_preset(&"a_brand_laborer_battery_mods")
	if profile_a == null or profile_b == null:
		return {}
	var built: Dictionary = BoutSetup.build_bout(
		[BoutRosterEntry.new(profile_a, &"AGGRESSIVE")] as Array[BoutRosterEntry],
		[BoutRosterEntry.new(profile_b, &"AGGRESSIVE")] as Array[BoutRosterEntry],
		map_seed
	)
	if built.get("error", "") != "":
		return {}
	var runner := BoutRunner.new(built["state"], built["mission"], TURN_CAP)
	await runner.run_to_completion()
	var outcome: int = built["mission"].outcome
	return {
		"seed": map_seed,
		"outcome": outcome,
		"outcome_name": Enums.MissionOutcome.keys()[outcome],
		"turns": runner.turns_taken,
		"completed": outcome == Enums.MissionOutcome.EXTRACTED,
	}


## Runs `seeds` and summarises. `rows` carries every per-seed outcome, because the
## aggregate is what hid which seeds mattered — `BR45.03`'s whole lesson.
static func run_seeds(seeds: Array[int]) -> Dictionary:
	var rows: Array[Dictionary] = []
	var completed := 0
	var turns_when_completed := 0
	var tally: Dictionary = {}
	for map_seed: int in seeds:
		var row: Dictionary = await run_seed(map_seed)
		if row.is_empty():
			continue
		rows.append(row)
		var name: String = row["outcome_name"]
		tally[name] = int(tally.get(name, 0)) + 1
		if bool(row["completed"]):
			completed += 1
			turns_when_completed += int(row["turns"])
	var counted: int = rows.size()
	return {
		"seeds": seeds,
		"rows": rows,
		"completed": completed,
		"counted": counted,
		"rate": float(completed) / float(counted) if counted > 0 else 0.0,
		"mean_turns": float(turns_when_completed) / float(completed) if completed > 0 else 0.0,
		"tally": tally,
	}


## `SAMPLE_SEEDS` seeds drawn from `rng`. **The caller owns the RNG** — logic never
## calls `randi()` itself (CLAUDE.md), so whether a run varies is the caller's
## decision: a test seeds from the clock to walk the space, a reproduction seeds
## from a recorded number to replay one.
##
## Draws without replacement, so a sample of ten is ten distinct maps rather than
## eight maps and a coincidence.
static func sample(rng: RandomNumberGenerator, space: int = 10000) -> Dictionary:
	return await run_seeds(draw_seeds(rng, space))


## The draw on its own, without playing anything.
##
## **Split out so the draw can be tested without a hundred seconds of bouts.**
## Whether a sample repeats a seed, or replays identically for a given RNG, is a
## question about this function alone — running ten missions to answer it made the
## suite twice as slow for no extra confidence.
static func draw_seeds(rng: RandomNumberGenerator, space: int = 10000) -> Array[int]:
	var drawn: Array[int] = []
	while drawn.size() < SAMPLE_SEEDS:
		var candidate: int = rng.randi_range(0, space - 1)
		if not drawn.has(candidate):
			drawn.append(candidate)
	return drawn


## The fixed, deterministic measurement. Same seeds every invocation, so two runs
## of this are byte-identical and a failure can be handed to someone else verbatim.
static func escalate() -> Dictionary:
	var seeds: Array[int] = []
	for i in range(ESCALATION_SEEDS):
		seeds.append(i)
	return await run_seeds(seeds)


## Whether a sample result warrants the deterministic escalation. One line, but its
## own function so the rule is pinned by a test that does not have to run a hundred
## bouts to check it.
static func should_escalate(rate: float, floor_rate: float) -> bool:
	return rate < floor_rate


## The exact probability that a sample of `SAMPLE_SEEDS` lands **below** `floor`
## when the true completion rate is `rate` — the binomial CDF, computed exactly
## rather than approximated, since the counts are tiny.
##
## This is what makes "how often does the suite escalate" a statement about the
## planner instead of about luck. Near zero means the floor is comfortable; a large
## value means the planner sits close enough to the floor that the sampler is
## effectively a coin toss, which is worth knowing even on a run that passed.
static func escalation_probability(rate: float, floor_rate: float) -> float:
	return escalation_probability_for(SAMPLE_SEEDS, rate, floor_rate)


## The same figure for an arbitrary sample size — what `SAMPLE_SEEDS` was chosen
## with, and what re-choosing it should be argued from.
static func escalation_probability_for(n: int, rate: float, floor_rate: float) -> float:
	var need: int = int(ceilf(floor_rate * float(n)))
	var total := 0.0
	for k in range(need):
		total += _binomial_pmf(n, k, rate)
	return clampf(total, 0.0, 1.0)


static func _binomial_pmf(n: int, k: int, p: float) -> float:
	return _choose(n, k) * pow(p, k) * pow(1.0 - p, n - k)


static func _choose(n: int, k: int) -> float:
	var result := 1.0
	for i in range(k):
		result *= float(n - i) / float(i + 1)
	return result


## The per-seed detail, as lines. **Shared by the headless test and the in-window
## view** so the two cannot report different things about the same run — the whole
## point of putting the sampler in logic rather than in either caller.
static func describe(result: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append(
		"seeds drawn: %s" % [str(result.get("seeds", [])).replace("[", "").replace("]", "")]
	)
	for row: Dictionary in result.get("rows", []) as Array[Dictionary]:
		lines.append("  seed %d: %s in %d turns" % [row["seed"], row["outcome_name"], row["turns"]])
	(
		lines
		. append(
			(
				"completion %d/%d (%.1f%%), mean %.1f turns to complete, %s"
				% [
					result.get("completed", 0),
					result.get("counted", 0),
					float(result.get("rate", 0.0)) * 100.0,
					float(result.get("mean_turns", 0.0)),
					str(result.get("tally", {})),
				]
			)
		)
	)
	return lines
