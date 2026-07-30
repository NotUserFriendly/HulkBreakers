extends GutTest

## taskblock-48 Pass C1: the shared bout corpus.
##
## ## The property that matters
##
## **It plays its bouts once per suite run.** Paying twice is the exact failure this
## exists to remove, so it is asserted against the bout counter rather than trusted to
## the `if _sample.is_empty()` guard — a cache that silently misses looks identical to
## one that works, except in the profile nobody reads until the suite has doubled.
##
## ## Deliberately no way to clear the cache
##
## An earlier draft had a `forget()` for testing. It is gone: any test calling it makes
## the *next* reader re-play eight missions, which reintroduces the duplicated cost
## while appearing to test against it. Caching is asserted by measuring that a second
## read is free, which needs no reset.


## taskblock-47 Pass C: this file reads the corpus, which builds bouts on first touch.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


# --- played once ------------------------------------------------------------------


## **A second read must cost nothing.** Measured on `CombatState.bouts_built`, the same
## counter the suite budget gates on, so "free" here means the same thing it means
## there.
func test_reading_the_corpus_twice_plays_no_extra_bouts() -> void:
	var first: Array[Dictionary] = await BoutCorpus.rows()
	assert_true(BoutCorpus.is_played(), "the first read played it")
	# taskblock-50 Pass D: **one record per seed actually played**, which is no longer a
	# fixed eight — the corpus stops at the first completion, so a healthy run records
	# one. Asserted against the sample's own count rather than a constant, because the
	# whole point of the change is that the count varies with the AI's health.
	assert_eq(
		first.size(), int((await BoutCorpus.sample())["seeds_played"]), "one record per seed played"
	)
	var after_first: int = CombatState.bouts_built

	var second: Array[Dictionary] = await BoutCorpus.rows()
	var third: Dictionary = await BoutCorpus.sample()

	gut.p(
		(
			"bouts after first read %d, after two more reads %d"
			% [after_first, CombatState.bouts_built]
		)
	)
	assert_eq(CombatState.bouts_built, after_first, "re-reading the corpus played nothing")
	assert_eq(second.size(), first.size(), "and returned the same records")
	assert_eq(int(third["seeds_played"]), first.size())


## The draw keeps the property taskblock-46 spent a pass establishing: distinct seeds,
## drawn at random, not a pinned window wearing a new name.
##
## taskblock-50 Pass D: it draws lazily now — a seed is only drawn once the previous one
## has lost — so the count is however many it took, capped. Distinctness is the property
## that matters and it is unchanged; a fixed size never was the point.
func test_the_corpus_draws_distinct_seeds() -> void:
	var seeds: Array[int] = await BoutCorpus.seeds()

	assert_gt(seeds.size(), 0, "it drew something")
	assert_true(seeds.size() <= CompletionSampler.FIRST_WIN_CAP, "and never past the cap")
	var seen: Dictionary = {}
	for map_seed: int in seeds:
		assert_false(seen.has(map_seed), "seed %d drawn twice" % map_seed)
		seen[map_seed] = true


# --- nobody can reach the cache ----------------------------------------------------


## **A test cannot corrupt another's view of a cached result.** Mutating a shared
## fixture surfaces as a failure somewhere with no connection to its cause, which is
## the worst kind of shared-state bug — so every accessor hands back a deep copy.
func test_one_reader_cannot_mutate_another_readers_records() -> void:
	var mine: Array[Dictionary] = await BoutCorpus.rows()
	assert_gt(mine.size(), 0, "sanity: there are records to tamper with")
	var original_outcome: StringName = StringName(mine[0]["outcome_name"])

	mine[0]["outcome_name"] = "TAMPERED"
	mine[0]["turns"] = -999
	mine.clear()

	var theirs: Array[Dictionary] = await BoutCorpus.rows()
	assert_gt(theirs.size(), 0, "the array was a copy")
	assert_eq(
		StringName(theirs[0]["outcome_name"]), original_outcome, "and so were the records in it"
	)
	assert_ne(int(theirs[0]["turns"]), -999)


## The same for the whole sample dictionary, since `test_full_mission` reads that rather
## than the rows.
func test_the_sample_dictionary_is_a_copy_too() -> void:
	var mine: Dictionary = await BoutCorpus.sample()
	var original_played: int = int(mine["seeds_played"])

	mine["seeds_played"] = -1
	(mine["rows"] as Array).clear()

	var theirs: Dictionary = await BoutCorpus.sample()
	assert_eq(int(theirs["seeds_played"]), original_played, "the count survived")
	assert_gt((theirs["rows"] as Array).size(), 0, "so did the rows")


# --- the canned records ------------------------------------------------------------


## The canned records must be the same shape as real ones, or a test that passes against
## them proves nothing about the report it will really be given.
func test_canned_records_match_the_shape_of_real_ones() -> void:
	var real: Array[Dictionary] = await BoutCorpus.rows()
	var canned: Array[Dictionary] = BoutCorpus.canned_rows(2, 1)

	assert_eq(canned.size(), 3)
	var real_keys: Array = real[0].keys()
	real_keys.sort()
	var canned_keys: Array = canned[0].keys()
	canned_keys.sort()
	assert_eq(canned_keys, real_keys, "a canned record carries exactly the real fields")


## And a canned sample must satisfy the arithmetic `describe` and the escalation rules
## read off it — otherwise stubbing moves the tests onto a fiction.
func test_a_canned_sample_is_internally_consistent() -> void:
	var report: Dictionary = BoutCorpus.canned_sample(3, 1)

	assert_eq(int(report["counted"]), 4)
	assert_eq(int(report["completed"]), 3)
	assert_almost_eq(float(report["rate"]), 0.75, 0.0001)
	assert_eq((report["seeds"] as Array).size(), 4)
	assert_eq(int(report["tally"]["EXTRACTED"]), 3)
	assert_eq(int(report["tally"]["TERMINATED"]), 1)
	# Plays nothing — the whole point of the canned path.
	var before: int = CombatState.bouts_built
	BoutCorpus.canned_sample(50, 50)
	assert_eq(CombatState.bouts_built, before, "canned records play no bouts")
