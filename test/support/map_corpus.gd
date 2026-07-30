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

## Cached grids, keyed by `seed:width:rows`. `static` so it survives across scripts within
## one process, which is where the saving is — the two consumer files are separate scripts
## asking for the same maps.
static var _cache: Dictionary = {}

## How many maps were actually generated. Lets a test assert the cache is doing its job
## without re-deriving the count from wall-clock, the same way `BoutCorpus` is checked
## against `CombatState.bouts_built`.
static var generated: int = 0


static func _key(map_seed: int, width: int, rows: int) -> String:
	return "%d:%d:%d" % [map_seed, width, rows]


## The shared grid for this seed. **Read-only by contract — see the header.**
static func read(map_seed: int, width: int, rows: int) -> Grid:
	var key: String = _key(map_seed, width, rows)
	if not _cache.has(key):
		_cache[key] = MapGen.generate(map_seed, width, rows)
		generated += 1
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
	generated = 0
