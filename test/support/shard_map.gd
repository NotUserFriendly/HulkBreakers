class_name ShardMap
extends RefCounted

## tb66 Pass E: **which shard runs which file, decided once and committed.**
##
## ## Committed, not computed at run time
##
## A gate that repacked itself each run would move corpus draws between runs and make the merged
## profile unreproducible — taskblock-65's third open question. Committing the assignment also
## removes work stealing, which has the same effect for the same reason. **Regenerate it with
## `tools/pack_shards.gd` when the profile moves**, and the diff is reviewable.
##
## **`SuiteOrder` is not in conflict and this must be said so it is not "fixed."** Failure-history
## ranking still operates *within* each shard, so a red shard still fails early. **Assignment is
## committed; ordering inside an assignment stays adaptive.** Both mechanisms survive untouched.
##
## ## Shard 0 is the corpus shard and it starts first
##
## Longest-processing-time-first. `BoutCorpus`'s draw is the makespan in every draw the model
## admits — **181–326 s typical, 425–767 s at the cap** (tb66 Pass A) — so it must never be waiting
## on a scheduler while short shards run. Everything else is packed to finish under it.
##
## ## Why eight shards and not sixteen
##
## **Derived, not assumed** (Pass E5). Non-corpus work is 972 s, so the makespan of the non-corpus
## half falls with the shard count — but only until it drops below the corpus shard, after which
## extra shards buy **nothing**, because the gate ends when the draw ends:
##
## | shards | non-corpus makespan | against a 181–326 s corpus shard |
## |---:|---:|---|
## | 6 | 163.3 s | at the knee |
## | **8** | **122.8 s** | one step of headroom |
## | 16 | 64.6 s | buys nothing the corpus shard does not already cost |
##
## Eight is the knee plus one step, so an unlucky packing or a newly expensive file does not
## immediately make the non-corpus half the wall. It also leaves more of a machine somebody else
## is using.
##
## ## Co-location is a cost, and it was priced rather than assumed
##
## Each process has its own `MapCorpus._cache`, so splitting a corpus's readers refills it in every
## shard that holds one. **The rule is co-locate when the fill cost exceeds the imbalance
## co-location creates** — and at eight shards both corpora fit with room to spare:
##
## | corpus | readers | co-located bin | fill paid once | verdict |
## |---|---:|---:|---:|---|
## | `BoutCorpus` | 3 | the draw itself | 181–326 s | **must** — it is the makespan |
## | `MapCorpus` 32×24 | 11 | 58.4 s | 11.2 s | co-locate; well under the 121.5 s target bin |
## | `MapCorpus` 40×30 | 3 | 30.7 s | 16.9 s | co-locate |
##
## **`ShardMerge` is what makes this checkable rather than argued**: a map that co-locates
## perfectly reports zero duplication, and the number it reports when it does not is the price.

## The committed assignment. Regenerate with `tools/pack_shards.gd`.
const MAP_PATH := "res://test/shard_map.json"

## Shard 0 holds every `SuiteTier.CORPUS_READERS` file and starts first.
const CORPUS_SHARD := 0

## What a file with no profile row is assumed to cost, in seconds (Pass E4).
##
## **A new file has no measurement and treating it as free is the failure mode** — it would land
## wherever the packer had room and could grow a tail nobody planned for. This is roughly the 90th
## percentile of per-file cost, so an unknown file is packed pessimistically and the worst case is a
## slightly under-filled bin rather than a shard that overruns the corpus shard.
const UNKNOWN_FILE_COST := 5.0


## The committed map as `{shard_index: [paths]}`, or empty if it has not been generated.
static func load_map() -> Dictionary:
	if not FileAccess.file_exists(MAP_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if not parsed is Dictionary:
		return {}
	return (parsed as Dictionary).get("shards", {})


## Which shard owns `path`, or -1 when the map does not mention it.
##
## **-1 is a real answer and callers must handle it**: a file added since the map was generated
## belongs to no shard, and silently dropping it would mean a green gate that never ran it — the
## same class of failure as a shard crashing quietly.
static func shard_for(path: String, shards: Dictionary = {}) -> int:
	var table: Dictionary = shards if not shards.is_empty() else load_map()
	for index: String in table:
		if path in (table[index] as Array):
			return int(index)
	return -1


## Every file the map assigns, across all shards — for checking nothing was dropped.
static func assigned_files(shards: Dictionary = {}) -> Array[String]:
	var table: Dictionary = shards if not shards.is_empty() else load_map()
	var out: Array[String] = []
	for index: String in table:
		for path: Variant in table[index]:
			out.append(String(path))
	return out
