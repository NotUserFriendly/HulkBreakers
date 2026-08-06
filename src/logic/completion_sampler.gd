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

## **The cap on `seeds_to_first_win`, derived rather than picked.**
##
## No win inside this many seeds is the failure. At the measured 0.72 completion rate a
## run of nine straight losses has probability 0.28^9 — about **one run in 180 000**, so
## the gate is not going to cry wolf. It is deliberately a *collapse* detector: at a rate
## of 0.20 it fails about one run in seven, at 0.10 about one in three, and a mild
## regression it will not fail at all.
##
## **That is the design, not a gap.** The reported number is the signal — 1 is healthy, 4
## is worth a look, 9 is a problem — and a threshold on a small integer count is exactly
## what put `MIN_COMPLETION_RATE` a fraction of one seed from red and got it lowered
## twice. The cap only catches an AI that has stopped finishing missions at all.
const FIRST_WIN_CAP := 9

## taskblock-59 Pass E: **the roster is mixed across intelligence tiers, and it used to be one
## labourer against another.**
##
## Every completion figure this project has ever recorded was an all-`TRAINED` figure, because
## `Unit.intelligence_tier` defaulted to `TRAINED` and nothing set it. With tiers authored on the
## combat-tester presets, the bout the gate measures contains three of them — and that is the
## supervisor's call over the alternative of tiering the labourers, which would have made the
## measured bout a walkover between one unit that can shoot and one that cannot.
##
## **Every recorded seed changes meaning**, and that is stated rather than absorbed: a number from
## before this pass and a number after it are not comparable, whatever the seed. Nothing on disk
## pins one — `BoutCorpus` draws from the clock — so there is no artifact to regenerate, only past
## report figures to distrust.
const MIXED_ROSTER: Array[StringName] = [
	&"combat_tester_chaingun",
	&"combat_tester_pump_shotgun",
	&"combat_tester_sniper_rifle",
]

## How many times `sample()` has fallen below its floor since the process started.
## Diagnostics only; never read by a decision.
static var escalations: int = 0


## **The bout a seed names.** Rosters and presets are constants, so the seed alone is
## a complete reproduction handle — which is what taskblock-47 Pass D's watched run is
## built on rather than any recorded artifact.
##
## Split out of `run_seed` for exactly that reason: the watched path and the headless
## path must build the *same* bout from the same seed, and two call sites assembling
## the same roster by hand is how they would stop doing that.
static func build_for_seed(map_seed: int) -> Dictionary:
	return build_roster(MIXED_ROSTER, MIXED_ROSTER, map_seed)


## **One tier against itself**, for the per-tier breakdown Pass F reports.
##
## *"A single number across a mixed roster hides which row moved it."* So the mixed figure is what
## the gate uses and this is what the report is built from — the same map, the same roster size,
## the same everything except what the units are capable of thinking.
##
## The tier is applied over the preset rather than by picking presets that carry it, so every tier
## fights with the identical weapons and the difference measured is the intelligence and nothing
## else.
static func build_at_tier(tier: StringName, map_seed: int) -> Dictionary:
	return build_roster(MIXED_ROSTER, MIXED_ROSTER, map_seed, tier)


## The shared builder. `tier` of `&""` leaves every preset's own authored tier alone.
static func build_roster(
	names_a: Array[StringName], names_b: Array[StringName], map_seed: int, tier: StringName = &""
) -> Dictionary:
	var roster_a: Array[BoutRosterEntry] = _roster(names_a, tier)
	var roster_b: Array[BoutRosterEntry] = _roster(names_b, tier)
	if roster_a.size() != names_a.size() or roster_b.size() != names_b.size():
		return {"error": "presets not loaded"}
	return BoutSetup.build_bout(roster_a, roster_b, map_seed)


## **Copies the preset before overriding its tier.** `DataLibrary.get_preset` hands back the
## registry's own resource, and writing a tier onto it would leave every later bout in the process
## fighting at whichever tier was measured last — the kind of shared-fixture bug that surfaces
## nowhere near its cause.
static func _roster(names: Array[StringName], tier: StringName) -> Array[BoutRosterEntry]:
	var built: Array[BoutRosterEntry] = []
	for name: StringName in names:
		var preset: BotPreset = DataLibrary.get_preset(name)
		if preset == null:
			continue
		if tier != &"":
			preset = preset.duplicate(true)
			preset.intelligence_tier = tier
		built.append(BoutRosterEntry.new(preset, &"aggressive"))
	return built


## One bout. Returns the outcome name and the turns it took, or an empty dictionary
## when the bout could not even be built.
## **`cap` bounds the horizon, it does not change the seed.** A caller asking a question
## that is true at any horizon — "does this replay identically?" — can bound it and pay
## for a few turns instead of a whole mission. That is not the same move as picking a
## seed whose map happens to be cheap, which would quietly make the fixture
## unrepresentative; the map is whatever the seed says, the run just stops earlier.
## taskblock-59 Pass F: `tier` of `&""` plays the mixed roster; a named tier plays the same roster
## with every unit held at it. **One runner, both questions** — a second play loop for the per-tier
## breakdown is how the mixed figure and the per-tier figures would start disagreeing about what a
## completion is.
static func run_seed(map_seed: int, cap: int = TURN_CAP, tier: StringName = &"") -> Dictionary:
	var built: Dictionary = (
		build_at_tier(tier, map_seed) if tier != &"" else build_for_seed(map_seed)
	)
	if built.get("error", "") != "":
		return {}
	var runner := BoutRunner.new(built["state"], built["mission"], cap)
	await runner.run_to_completion()
	var outcome: int = built["mission"].outcome
	return {
		"seed": map_seed,
		"tier": tier,
		"outcome": outcome,
		"outcome_name": Enums.MissionOutcome.keys()[outcome],
		"turns": runner.turns_taken,
		"completed": outcome == Enums.MissionOutcome.EXTRACTED,
	}


## Runs `seeds` and summarises. `rows` carries every per-seed outcome, because the
## aggregate is what hid which seeds mattered — `BR45.03`'s whole lesson.
static func run_seeds(seeds: Array[int], cap: int = TURN_CAP, tier: StringName = &"") -> Dictionary:
	var rows: Array[Dictionary] = []
	var completed := 0
	var turns_when_completed := 0
	var tally: Dictionary = {}
	for map_seed: int in seeds:
		var row: Dictionary = await run_seed(map_seed, cap, tier)
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
		"tier": tier,
		"rows": rows,
		"completed": completed,
		"counted": counted,
		"rate": float(completed) / float(counted) if counted > 0 else 0.0,
		"mean_turns": float(turns_when_completed) / float(completed) if completed > 0 else 0.0,
		"tally": tally,
	}


## **Play seeds until one of them completes, and report how many it took.**
##
## taskblock-50 Pass D. This replaces a fixed-size sample as the suite's completion
## check, and the shape is the point: **cost scales inversely with health.** At a healthy
## rate the common case stops on the first or second seed — one bout instead of eight —
## and when the AI regresses the measurement gets more expensive, so the suite spends
## time exactly when something is wrong.
##
## Draws lazily: a seed is only drawn once the previous one has lost, so a healthy run
## never even generates the maps it did not need.
static func seeds_to_first_win(
	rng: RandomNumberGenerator, cap: int = FIRST_WIN_CAP, space: int = 10000
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var drawn: Array[int] = []
	var tally: Dictionary = {}
	while drawn.size() < cap:
		var candidate: int = rng.randi_range(0, space - 1)
		if drawn.has(candidate):
			continue
		drawn.append(candidate)
		var row: Dictionary = await run_seed(candidate)
		if row.is_empty():
			continue
		rows.append(row)
		var outcome_name: String = row["outcome_name"]
		tally[outcome_name] = int(tally.get(outcome_name, 0)) + 1
		if bool(row["completed"]):
			break
	var won: bool = not rows.is_empty() and bool(rows[rows.size() - 1]["completed"])
	return {
		"seeds": drawn,
		"rows": rows,
		"seeds_played": rows.size(),
		"won": won,
		"winning_seed": int(rows[rows.size() - 1]["seed"]) if won else -1,
		"cap": cap,
		"tally": tally,
	}


## One line per seed played, then the verdict. Same shape as `describe` — a header, a row
## each, a summary — so a reader of either report is reading the same thing.
static func describe_first_win(result: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("seeds drawn: %s" % [result.get("seeds", [])])
	for row: Dictionary in result.get("rows", []):
		lines.append(
			"  seed %d: %s in %d turns" % [int(row["seed"]), row["outcome_name"], int(row["turns"])]
		)
	if bool(result.get("won", false)):
		lines.append(
			(
				"first completion on seed %d after %d seed(s) — cap %d"
				% [int(result["winning_seed"]), int(result["seeds_played"]), int(result["cap"])]
			)
		)
	else:
		lines.append(
			"no completion in %d seed(s) — at the cap" % [int(result.get("seeds_played", 0))]
		)
	return lines


## `SAMPLE_SEEDS` seeds drawn from `rng`. **The caller owns the RNG** — logic never
## calls `randi()` itself (CLAUDE.md), so whether a run varies is the caller's
## decision: a test seeds from the clock to walk the space, a reproduction seeds
## from a recorded number to replay one.
##
## Draws without replacement, so a sample of ten is ten distinct maps rather than
## eight maps and a coincidence.
## **`count` is a tunable, not a rule.** It defaults to `SAMPLE_SEEDS`, which is what a
## real measurement wants; a caller that only needs to see the *shape* of a report — a
## test of the reporting path, or an in-game spot check — passes a smaller number and
## pays for one mission instead of eight. The seed count never changes what `describe`
## emits, only how many rows it emits.
static func sample(
	rng: RandomNumberGenerator, space: int = 10000, count: int = SAMPLE_SEEDS
) -> Dictionary:
	return await run_seeds(draw_seeds(rng, space, count))


## The draw on its own, without playing anything.
##
## **Split out so the draw can be tested without a hundred seconds of bouts.**
## Whether a sample repeats a seed, or replays identically for a given RNG, is a
## question about this function alone — running ten missions to answer it made the
## suite twice as slow for no extra confidence.
static func draw_seeds(
	rng: RandomNumberGenerator, space: int = 10000, count: int = SAMPLE_SEEDS
) -> Array[int]:
	var drawn: Array[int] = []
	while drawn.size() < count:
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


## **The per-tier breakdown Pass F reports, plus the mixed figure, over one seed window.**
##
## *"Report per tier and for the mixed bout. A single number across a mixed roster hides which row
## moved it."* So this returns one row per entry of `tiers` and one for the mixed roster, all over
## the **same seeds** — a per-tier figure taken on a different window would be comparing maps as
## much as intelligence.
##
## `tiers` is the caller's list rather than a constant here, because `intelligence_tier` is an open
## vocabulary and this file has no business declaring which ones exist.
static func per_tier(
	tiers: Array[StringName], seeds: Array[int], cap: int = TURN_CAP
) -> Array[Dictionary]:
	var reported: Array[Dictionary] = []
	for tier: StringName in tiers:
		reported.append(await run_seeds(seeds, cap, tier))
	reported.append(await run_seeds(seeds, cap))
	return reported


## One line per row of `per_tier`. **The mixed row is labelled `mixed`**, not left blank, because a
## blank cell in a report reads as a number nobody took.
static func describe_per_tier(rows: Array[Dictionary]) -> Array[String]:
	var lines: Array[String] = ["tier      completed  rate   mean turns  outcomes"]
	for row: Dictionary in rows:
		var tier: String = String(row.get("tier", &""))
		(
			lines
			. append(
				(
					"%-9s %4d/%-4d  %5.1f%%  %10.1f  %s"
					% [
						tier if tier != "" else "mixed",
						int(row.get("completed", 0)),
						int(row.get("counted", 0)),
						float(row.get("rate", 0.0)) * 100.0,
						float(row.get("mean_turns", 0.0)),
						str(row.get("tally", {})),
					]
				)
			)
		)
	return lines
