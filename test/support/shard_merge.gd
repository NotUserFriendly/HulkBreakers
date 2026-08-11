class_name ShardMerge
extends RefCounted

## tb66 Pass D1: **the duplication a sharded gate creates, as a subtractable quantity.**
##
## ## The problem this exists for
##
## `maps` and `floods` are gated counters (`SuiteBudget.GATED`). Every shard is a separate process
## with its own `MapCorpus._cache`, so a corpus split across shards is **refilled in each of them**
## — measured at tb66 Pass A as **+18 maps and +36 floods** from splitting three 32x24 readers
## across six shards. That inflation is not drift, and leaving it unhandled is bad in both
## directions: baseline the budget unsharded and every sharded gate reports growth that did not
## happen; baseline it sharded and **changing the shard map silently moves a budget**, which makes
## scheduling visible to the drift guard.
##
## ## Why the fills are keyed rather than counted
##
## **A count cannot be deduplicated.** Two shards each reporting *"I filled 50 boards"* cannot tell
## the gate whether the suite built 50 distinct boards or 100. Two shards reporting *which keys*
## they filled can, and the answer is set arithmetic: the duplication is everything past the first
## fill of each key.
##
## ## Why this is a quantity and not an exemption
##
## taskblock-65 Pass F tried to exempt a *file* from the `turns` gate and the suite's own guard
## refused it — an exemption is a hole in the gate. The resolution recorded in `SuiteBudget` is
## *"the uncontrolled thing is a quantity, not a file, and it is now subtracted as one."*
## Duplicated fills are the same shape: they are work the suite genuinely did, caused entirely by
## how it was scheduled, and the honest treatment is to name the amount and subtract it rather than
## to stop looking at the counter.
##
## **The subtracted quantity is also the affinity score.** A shard map that keeps every corpus
## reader together duplicates nothing and this returns zero; one that scatters them returns the
## price. So Pass E's co-location rule becomes checkable rather than argued — which is the thing
## Pass A could observe but not act on, because a counter cannot be both the gate and the
## diagnostic.


## Per-shard fill records — each is `MapCorpus.fills`, `key -> {"maps": int, "floods": int}`.
## Returns `{"maps": int, "floods": int}`: the work that would not have happened in one process.
##
## **First fill of a key is free; every later one is duplication.** Which shard is charged as
## "first" is arbitrary and does not matter — only the count past one does, and set union is
## order-independent, so this is stable however the shards finish.
static func duplication(shard_fills: Array) -> Dictionary:
	var seen: Dictionary = {}
	var duplicated: Dictionary = {"maps": 0, "floods": 0}
	for fills: Dictionary in shard_fills:
		for key: String in fills:
			var cost: Dictionary = fills[key]
			if seen.has(key):
				duplicated["maps"] += int(cost.get("maps", 0))
				duplicated["floods"] += int(cost.get("floods", 0))
			else:
				seen[key] = true
	return duplicated


## Summed shard totals with the duplication taken out, ready for `SuiteBudget.violations`.
##
## **Only `maps` and `floods` are adjusted**, because those are the only counters a duplicated
## generation moves. A bout, a turn, a plan and a UI build all happen exactly once regardless of
## which shard runs them — that is what A1 measured when nine of eleven counters summed exactly.
static func controlled_totals(totals: Dictionary, shard_fills: Array) -> Dictionary:
	var adjusted: Dictionary = totals.duplicate(true)
	var duplicated: Dictionary = duplication(shard_fills)
	for counter: String in ["maps", "floods"]:
		adjusted[counter] = int(adjusted.get(counter, 0)) - int(duplicated[counter])
	return adjusted
