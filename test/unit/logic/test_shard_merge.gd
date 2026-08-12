extends GutTest

## tb66 Pass D1 — **the duplication a sharded gate creates, and that subtracting it restores the
## unsharded numbers.**
##
## `maps` and `floods` are gated counters and every shard has its own `MapCorpus._cache`, so a
## corpus split across shards is refilled in each of them. tb66 Pass A measured that at **+18 maps
## and +36 floods** on six files. This file is what keeps the subtraction honest.
##
## **Nothing here builds a bout or mounts a scene**, so it runs on every rung.


func after_each() -> void:
	MapCorpus.forget_ledger()


## The shape of a shard's report: which keys it filled, and what each cost.
func _fills(keys: Array, maps_each: int = 1, floods_each: int = 3) -> Dictionary:
	var out: Dictionary = {}
	for key: String in keys:
		out[key] = {"maps": maps_each, "floods": floods_each}
	return out


## **Zero when nothing is split — the property that makes this a diagnostic and not just a fudge.**
## A shard map that keeps every reader of a corpus together duplicates nothing, and the subtraction
## must then be a no-op rather than a correction that quietly moves the budget.
func test_a_shard_map_that_splits_nothing_duplicates_nothing() -> void:
	var shards: Array = [_fills(["4242:32:24", "9:32:24"]), _fills(["7:40:30"])]

	var duplicated: Dictionary = ShardMerge.duplication(shards)

	assert_eq(duplicated["maps"], 0, "disjoint shards share no keys, so nothing is refilled")
	assert_eq(duplicated["floods"], 0)


## And the price when it is split. **Everything past the first fill of a key is duplication**;
## which shard is charged as "first" is arbitrary and must not matter, since shards finish out of
## order.
func test_a_key_filled_in_three_shards_is_charged_twice() -> void:
	var shards: Array = [
		_fills(["4242:32:24"]), _fills(["4242:32:24"]), _fills(["4242:32:24", "1:40:30"])
	]

	var duplicated: Dictionary = ShardMerge.duplication(shards)

	gut.p("three shards filling one key: %s" % duplicated)
	assert_eq(duplicated["maps"], 2, "three fills of one board is two more than one process does")
	assert_eq(duplicated["floods"], 6, "and the floods that generation ran go with them")


## **Order-independence, asserted rather than assumed.** Shards finish in whatever order the
## scheduler gives, so a merge that depended on arrival order would make the gated total depend on
## timing — which is exactly the property `SuiteBudget` exists to protect.
func test_the_answer_does_not_depend_on_which_shard_reports_first() -> void:
	var a: Dictionary = _fills(["4242:32:24", "9:32:24"])
	var b: Dictionary = _fills(["4242:32:24"], 1, 11)

	var forward: Dictionary = ShardMerge.duplication([a, b])
	var backward: Dictionary = ShardMerge.duplication([b, a])

	assert_eq(forward["maps"], backward["maps"], "set union is order-independent and must stay so")
	gut.p("forward %s, backward %s" % [forward, backward])


## **Only `maps` and `floods` move.** A bout, a turn, a plan and a UI build happen once regardless
## of which shard runs them — which is what Pass A measured when nine of eleven counters summed
## exactly. A subtraction that touched them would be inventing a correction for work that was never
## duplicated.
func test_only_the_two_counters_a_duplicated_generation_moves_are_adjusted() -> void:
	var totals: Dictionary = {"bouts": 5, "turns": 16, "maps": 260, "floods": 703, "ui_builds": 93}
	var shards: Array = [_fills(["a", "b"]), _fills(["a", "b"])]

	var controlled: Dictionary = ShardMerge.controlled_totals(totals, shards)

	assert_eq(controlled["maps"], 258, "two duplicated fills come off maps")
	assert_eq(controlled["floods"], 697, "and their floods come off floods")
	for untouched: String in ["bouts", "turns", "ui_builds"]:
		assert_eq(
			controlled[untouched],
			totals[untouched],
			"%s is not moved by a duplicated generation and must not be adjusted" % untouched
		)


## **The real thing, measured rather than modelled.** Two independent `MapCorpus` caches — which is
## exactly what two processes have — asked for an overlapping keyspace. The recorded fills must
## account for the difference between what the two of them generated and what one would have.
##
## `forget_ledger()` between them is the honest simulation of a process boundary: a fresh cache, and
## a fresh `fills` record to report. **Plain `forget()` is deliberately not enough here** — since
## `BR66.01` it keeps the ledger, which is right for every other caller and wrong for this one,
## whose whole subject is what two *separate* processes each reported.
func test_two_caches_over_an_overlapping_keyspace_report_their_own_duplication() -> void:
	MapCorpus.forget_ledger()
	for map_seed: int in [1, 2, 3]:
		MapCorpus.read(map_seed, 12, 10)
	var shard_a: Dictionary = MapCorpus.fills.duplicate(true)
	var generated_a: int = MapCorpus.generated

	MapCorpus.forget_ledger()
	for map_seed: int in [2, 3, 4]:
		MapCorpus.read(map_seed, 12, 10)
	var shard_b: Dictionary = MapCorpus.fills.duplicate(true)
	var generated_b: int = MapCorpus.generated

	var duplicated: Dictionary = ShardMerge.duplication([shard_a, shard_b])
	var distinct: int = generated_a + generated_b - int(duplicated["maps"])

	gut.p(
		(
			"shard A generated %d, shard B %d, duplicated %d -> %d distinct boards"
			% [generated_a, generated_b, int(duplicated["maps"]), distinct]
		)
	)
	assert_eq(generated_a + generated_b, 6, "two caches over overlapping keys generate six")
	assert_eq(int(duplicated["maps"]), 2, "seeds 2 and 3 were built twice")
	assert_eq(distinct, 4, "and one process would have built four — which is the controlled number")
	assert_gt(int(duplicated["floods"]), 0, "the duplicated fills ran real floods, and they count")
