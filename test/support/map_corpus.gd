class_name MapCorpus
extends RefCounted

## taskblock-50 Pass E2: **generated maps, once per process, for the sweeps that only read
## them.**
##
## `test_map_gen.gd` and `test_map_gen_raised_rooms.gd` between them ran **fourteen
## independent seed sweeps** over the same seed range at the same dimensions —
## regenerating roughly **650 maps** to ask fourteen different questions about **fifty**.
## Map generation is the whole cost of both files (38.9 s, zero bouts), and almost all of
## it was the same fifty maps over and over.
##
## ## `read` shares; `copy` does not
##
## Every sweep in both files was checked before this was built: they read `blockers`,
## `surfaces`, `opacity` and `spawn_marker`, and **not one of them mutates the grid.** So
## `read()` hands back the cached `Grid` itself, with no copy, and the saving is the whole
## generation rather than the difference between generating and duplicating.
##
## That is a shared mutable object, which is the hazard `BoutCorpus` refuses to take on —
## so the escape hatch is here rather than absent. **A test that needs to change a map
## calls `copy()`**, which returns a full `Grid.dup()`; a test that changed a `read()` grid
## would corrupt every later reader and the failure would surface somewhere unrelated. If
## you are unsure which you need, `copy()` is correct and costs a duplication.
##
## ## What must never come from here
##
## **A test comparing two generations of the same seed must call `MapGen.generate` twice
## itself.** `test_generate_is_seed_deterministic` and
## `test_barrel_pallet_barrel_count_is_deterministic_and_in_range` do exactly that, and
## routing them through `read()` would hand them the *same object twice* — the comparison
## would pass unconditionally and the suite would have lost its only check that generation
## is reproducible. Those two sites are deliberately left calling the generator direct.
##
## ## What it costs, and which files hold out (tb65 Pass A)
##
## **A generation is not cheap and its price is the board size**, measured on this machine
## rather than estimated: **224 ms at 32x24, 337 ms at 40x30, 96 ms at 24x18.** A warm
## `read()` is free — 40 cold reads cost 7.99 s, the same 40 read again cost nothing, and
## `generated` stayed at the number of distinct keys. **Sharing works across scripts**, since
## GUT runs the whole suite in one process and `_cache` is `static`.
##
## **The keyspace this corpus already holds**, and therefore what a new reader gets for free:
##
## | keys | filled by |
## |---|---|
## | seeds 0-49 @ **32x24** | `test_map_gen.gd`, `test_map_gen_raised_rooms.gd` (0-39) |
## | seeds 0-49 @ **40x30** | `test_map_gen_reachability.gd` |
## | seeds 0-49 @ 12x10 | `test_map_gen.gd` |
## | seed 11 @ 32x24 | the three aim probes |
##
## **Which file pays for a given cold fill depends on run order and the total does not** —
## `run_tests.sh` reorders scripts by failure history, so a per-file second count moves
## between runs while the number of distinct boards generated does not. Compare the
## generation count, not the attribution.
##
## ## The holdouts, and the reason each one holds
##
## Every remaining direct `MapGen.generate` in the suite was surveyed. Three answers:
##
## - **Deliberate, and it must stay.** `test_map_gen.gd`'s two determinism sites, per the
##   section above. `test_determinism_check.gd` builds its own generator lambda because it is
##   testing the determinism harness itself.
## - **A board nobody else wants.** `test_generated_board_sight_sweep.gd` (seed 642296523 @
##   40x30) and `test_sight_geometry.gd` (seed 4242 @ 24x18) each hold a key no other file
##   asks for. They still read the corpus — a file asking for one board three times is the
##   same waste at a smaller scale — but the corpus widens by one key for each, and **the
##   saving is under a second in both cases: generation is 3% of the sweep file's 33.9 s and
##   the rest is the LoS work.** Named here so nobody re-derives it as a promising target.
## - **A board the corpus already holds, regenerated anyway.** This was the whole finding.
##
## **The measured saving, per file, at the sizes above:**
##
## | file | boards it regenerates | gen | cost | after | saved |
## |---|---|---:|---:|---:|---:|
## | `test_generation_heights.gd` | 0-29 @ 40x30, **swept 4x** | 120 | 40.4 s | 0 | **40.4 s** |
## | `test_vertical_routes.gd` | 0-39 @ 40x30 | 40 | 13.5 s | 0 | **13.5 s** |
## | `test_mag_lift.gd` | 8 seeds @ 32x24, swept 2x | 16 | 3.6 s | 2 | **3.1 s** |
## | `test_map_navigability.gd` | `GATE_SEEDS` @ 32x24 | 12 | 2.7 s | 0 | **2.7 s** |
## | `test_step_height.gd` | 32x24, post-Pass-B | 8 | 1.8 s | 2 | **1.3 s** |
## | the four cost probes | seed 4242 @ 32x24, one each | 4 | 0.9 s | 1 | **0.7 s** |
##
## `test_generation_heights.gd` is the case that makes the point: **generation was 96% of a
## 42.5 s file**, its thirty boards were already sitting in this cache, and it regenerated all
## of them four times over.
##
## **Two of those files are not `MapGen.generate`'s most-called sites and were found by
## measurement rather than by counting call sites.** A file calling the generator once inside
## a forty-seed loop looks cheaper in a grep than one calling it seven times at top level.
##
## ## What is left calling the generator directly, and why (tb65 Pass C)
##
## Pass C pointed **ten files** here. Everything still calling `MapGen.generate` in `test/`
## does so for one of three stated reasons, and none of them is *"it was written before the
## corpus"*:
##
## | file | why it holds out |
## |---|---|
## | `test_map_gen.gd` | its two determinism sites — the section above |
## | `test_determinism_check.gd` | it builds a generator lambda to test the determinism *harness* |
## | `test_map_generation_baseline.gd` | five seeds at 28x16, a size nothing else reads |
## | `test_map_serializer.gd` | a fresh board per test, which is what a round-trip needs |
## | `test_map_gen_reachability.gd` | reads here already; listed because it is what fills 40x30 |
##
## **Two keys were added to serve the retrofit** — seed 642296523 @ 40x30 and 4242 @ 24x18 —
## each read by exactly one file. That is worth under a second each and was done anyway,
## because a file asking for one board three times is the same waste at a smaller scale.

## Cached grids, keyed by `seed:width:rows`. `static` so it survives across scripts within
## one process, which is where the saving is — the two consumer files are separate scripts
## asking for the same maps.
static var _cache: Dictionary = {}

## How many maps were actually generated. Lets a test assert the cache is doing its job
## without re-deriving the count from wall-clock, the same way `BoutCorpus` is checked
## against `CombatState.bouts_built`.
static var generated: int = 0

## tb66 Pass D1: **what each fill cost, keyed** — so a sharded gate can subtract its
## own duplication.
##
## Every process gets its own `_cache`, so a corpus split across shards is refilled in each of
## them. Measured at tb66 Pass A on six files: splitting three 32x24 readers cost **+18 maps and
## +36 floods**, and **both counters are gated** — so without this, a sharded gate reports
## inflation that is not drift, or the budget is baselined under one shard map and silently moves
## when the map changes.
##
## **The precedent is exact and it is in `SuiteBudget` already.** taskblock-65 Pass F hit this
## shape with the corpus draw contaminating `turns` and settled it as *"the uncontrolled thing is
## a quantity, not a file, and it is now subtracted as one."* A duplicated fill is a quantity too.
##
## **Keyed rather than counted, because a count cannot be deduplicated.** Two shards each
## reporting "I filled 50 boards" cannot tell the gate whether that is 50 boards or 100; two
## shards reporting *which* keys they filled can. `ShardMerge.duplication` takes the union.
##
## **`floods` is recorded per fill rather than derived**, because generation runs floods
## internally (`_repair_stranded_elevation`, `guarantee_navigability`) and the number per board
## is not constant — it depends on how much repair a seed needs.
##
## **This also resolves a tension in Pass A's own finding.** Pass A observed, correctly, that
## `maps` inflation measures how badly a shard map splits corpora — a perfect affinity map
## inflates by zero. But **a counter cannot be both the gate and the diagnostic**, which is what
## Pass F untangled for `turns`. Subtracting gives both: the gated total stays controlled, and the
## subtracted quantity *is* the affinity score.
static var fills: Dictionary = {}


static func _key(map_seed: int, width: int, rows: int) -> String:
	return "%d:%d:%d" % [map_seed, width, rows]


## The shared grid for this seed. **Read-only by contract — see the header.**
static func read(map_seed: int, width: int, rows: int) -> Grid:
	var key: String = _key(map_seed, width, rows)
	if not _cache.has(key):
		# tb66 Pass D1: the fill's own cost, bracketed. `floods` is sampled rather than assumed
		# because generation runs its own repair floods and the number varies by how much repair
		# a seed needs.
		var floods_before: int = Pathfinder.floods
		_cache[key] = MapGen.generate(map_seed, width, rows)
		generated += 1
		fills[key] = {"maps": 1, "floods": Pathfinder.floods - floods_before}
	return _cache[key]


## A private copy of the same map, safe to mutate.
static func copy(map_seed: int, width: int, rows: int) -> Grid:
	return read(map_seed, width, rows).dup()


## Drops the cache. **For the corpus's own tests only** — a consumer calling this makes
## the next reader regenerate everything, reintroducing the cost while appearing to guard
## against it. `BoutCorpus` omits its equivalent entirely for that reason; this one needs
## it because "a second read generates nothing" is not assertable without a first read to
## compare against, and the counter alone cannot distinguish a cold cache from a warm one.
static func forget() -> void:
	_cache.clear()
	fills.clear()
	generated = 0
