class_name BoutCorpus
extends RefCounted

## taskblock-48 Pass C1: **one random sample of bouts, played once per suite run, read
## by everyone who needs outcomes.**
##
## `test_full_mission.gd` and `test_completion_sampler.gd` both drove
## `CompletionSampler` over the same kind of bout and each paid separately — together
## 57% of the suite. Almost none of that was needed twice: what most of those tests
## want is a set of *outcome records* to reason about, not the privilege of having
## generated them.
##
## ## The draw stays random, and that is the whole constraint
##
## `test_full_mission` seeds from the clock on purpose. taskblock-46 spent a pass
## establishing that, because the pinned window it replaced was measuring the
## pessimistic corner of the seed space and reporting it as *the* completion rate.
## **Sharing a fixed set of seeds would quietly undo that**, and the test would keep
## passing while measuring the wrong thing again.
##
## So the draw happens once here, from the clock, and the sample is shared. One random
## draw per run, played once, read by everyone: the sampling property survives and the
## cost is paid a single time.
##
## ## Records, never live state
##
## Every accessor hands back a deep copy. A test that mutated a cached `CombatState`
## would corrupt every later reader, and the failure would surface somewhere with no
## connection to its cause — the worst kind of shared-fixture bug. There is no accessor
## for a live board here at all; a test that needs one builds its own, which is what
## the eight other bout-building files already do and why they are not candidates for
## this.

## The played sample, or empty before the first read. `static` so it survives across
## test scripts within one process, which is the point — but it means a second process
## draws its own sample, and that is correct rather than a cache miss.
static var _sample: Dictionary = {}
## Which seeds the draw chose. Kept separately so `seeds()` works before anything has
## asked for the rows.
static var _seeds: Array[int] = []


## The sample, played on first call and cached after. **A deep copy every time**, so no
## caller can reach the cache.
## taskblock-50 Pass D: **it stops at the first completion instead of playing a fixed
## eight.** The draw is still clock-seeded, still random, still printed — what changed is
## how many of those seeds get played. At the measured rate that is usually one bout, and
## it is why every reader of this corpus became cheap at once rather than one file at a
## time.
##
## It also removed the reason the suite could not measure itself. The fixed sample made
## total turns swing 657 to 1305 between runs with no code change (`BR49.01`), which both
## flapped the work budget and made any other saving unmeasurable underneath it.
static func sample() -> Dictionary:
	if _sample.is_empty():
		var rng := RandomNumberGenerator.new()
		# From the clock, deliberately — see the note above. A fixed seed here would
		# rebuild the pinned window under a new name.
		rng.seed = int(Time.get_unix_time_from_system())
		_sample = await CompletionSampler.seeds_to_first_win(rng)
		_seeds = []
		for drawn: int in _sample.get("seeds", []):
			_seeds.append(int(drawn))
	return _sample.duplicate(true)


## The per-bout outcome records: `[{seed, outcome, outcome_name, turns, completed}, …]`.
static func rows() -> Array[Dictionary]:
	var played: Dictionary = await sample()
	var copied: Array[Dictionary] = []
	for row: Dictionary in played.get("rows", []):
		copied.append(row.duplicate(true))
	return copied


static func seeds() -> Array[int]:
	await sample()
	return _seeds.duplicate()


## Whether the corpus has already been played. Lets a test assert "this cost nothing"
## without triggering the very work it is checking for.
static func is_played() -> bool:
	return not _sample.is_empty()


## Canned outcome records, for the many tests that assert something about the *report*
## rather than about a bout.
##
## **These play nothing at all.** Escalation thresholds, the `ceil`-driven
## non-monotonicity, rate arithmetic and the shape of `describe`'s output are pure
## functions over records like these, and running real missions to feed them was the
## largest single waste in the suite.
static func canned_rows(completed: int, failed: int) -> Array[Dictionary]:
	var rows_out: Array[Dictionary] = []
	var next_seed := 0
	for i in range(completed):
		rows_out.append(_row(next_seed, Enums.MissionOutcome.EXTRACTED, 12))
		next_seed += 1
	for i in range(failed):
		rows_out.append(
			_row(next_seed, Enums.MissionOutcome.TERMINATED, CompletionSampler.TURN_CAP)
		)
		next_seed += 1
	return rows_out


## A canned sample dictionary in exactly the shape `CompletionSampler.run_seeds`
## returns, so `describe` and the escalation rules can be exercised against it.
static func canned_sample(completed: int, failed: int) -> Dictionary:
	var rows_in: Array[Dictionary] = canned_rows(completed, failed)
	var seed_list: Array[int] = []
	var tally: Dictionary = {}
	var turns_when_completed := 0
	for row: Dictionary in rows_in:
		seed_list.append(int(row["seed"]))
		var name: String = row["outcome_name"]
		tally[name] = int(tally.get(name, 0)) + 1
		if bool(row["completed"]):
			turns_when_completed += int(row["turns"])
	var counted: int = rows_in.size()
	return {
		"seeds": seed_list,
		"rows": rows_in,
		"completed": completed,
		"counted": counted,
		"rate": float(completed) / float(counted) if counted > 0 else 0.0,
		"mean_turns": float(turns_when_completed) / float(completed) if completed > 0 else 0.0,
		"tally": tally,
	}


## taskblock-59 Pass F: **`tier` joined the real record and this fixture had to follow.**
## `test_canned_records_match_the_shape_of_real_ones` caught it on the full gate, which is exactly
## what that test is for — a canned record that has drifted from the real one moves every test built
## on it onto a fiction. `&""` is the mixed roster, which is what a record from `run_seed`'s default
## path carries.
static func _row(map_seed: int, outcome: int, turns: int) -> Dictionary:
	return {
		"seed": map_seed,
		"tier": &"",
		"outcome": outcome,
		"outcome_name": Enums.MissionOutcome.keys()[outcome],
		"turns": turns,
		"completed": outcome == Enums.MissionOutcome.EXTRACTED,
	}
