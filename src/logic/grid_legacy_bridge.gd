class_name GridLegacyBridge
extends RefCounted

## taskblock-38 Pass D: "make the legacy path visible, and enumerate what
## depends on it" (docs/taskblock38.md) — NOT the retirement itself. Pass
## C's own fallback (a grid with no placed `Surface` anywhere derives its
## answer from the pre-placement `terrain`/`level` formula) is what keeps
## 17 production files and 36 test files working today; deleting
## `Grid.level` and the four terrain values means deleting that fallback,
## and that migration gets its own follow-up block (docs/PLAN.md: "Retire
## `Grid.level` and the legacy terrain values").
##
## This is the ONE seam all of it now routes through — replacing three
## separate `grid.surfaces.is_empty()` checks that used to live
## independently in `Pathfinder._base_cost`/`move_cost` and
## `UnitGeometry.true_height_for_cell`. Every hit is counted by CALLER,
## building the burn-down list this pass's own report commits ("which
## files, which call sites, how many hits each" — the next block's spec,
## derived rather than guessed, not assumed).
##
## Retired in its own follow-up block once `total_hits()` reads zero
## across the full suite — the real acceptance test for THAT block,
## stronger than a grep: it proves nothing still depends on the old
## model, including whatever a grep would miss.

## caller (String, e.g. "Pathfinder._base_cost") -> hit count. Static
## across the whole process, so one full suite run accumulates one real
## burn-down list — see `tools/legacy_grid_bridge_burndown.gd`, a GUT
## post-run hook that dumps this once every test has run.
static var _hits: Dictionary = {}


static func is_legacy(grid: Grid) -> bool:
	return grid.surfaces.is_empty()


static func hit_counts() -> Dictionary:
	return _hits.duplicate()


static func total_hits() -> int:
	var total := 0
	for count: int in _hits.values():
		total += count
	return total


static func reset() -> void:
	_hits.clear()


static func _record(caller: String) -> void:
	_hits[caller] = _hits.get(caller, 0) + 1


## The pre-placement per-cell terrain cost formula, verbatim (`Pathfinder`
## before this pass). `caller` identifies the call site for the burn-down
## list.
static func terrain_cost(
	grid: Grid, cell: Vector2i, terrain_costs: Dictionary, default_cost: float, caller: String
) -> float:
	_record(caller)
	var terrain: int = grid.get_terrain(cell)
	if terrain_costs.has(terrain):
		var cost: float = terrain_costs[terrain]
		return cost if cost >= 0.0 else -1.0
	return default_cost


## The pre-placement climb/hop-down/ramp cost formula, verbatim.
static func move_cost(
	grid: Grid, from: Vector2i, to: Vector2i, base: float, can_climb: bool, caller: String
) -> float:
	_record(caller)
	if (
		grid.get_terrain(from) == Enums.TerrainType.RAMP
		or grid.get_terrain(to) == Enums.TerrainType.RAMP
	):
		return base
	var level_delta: float = grid.get_level(to) - grid.get_level(from)
	if is_zero_approx(level_delta):
		return base
	if level_delta > 0.0:
		if not can_climb or level_delta > Pathfinder.MAX_CLIMB_LEVELS:
			return -1.0
		return Pathfinder.CLIMB_COST * (level_delta / UnitGeometry.LEVEL_HEIGHT)
	if -level_delta > Pathfinder.MAX_HOP_DOWN_LEVELS:
		return -1.0
	return Pathfinder.HOP_DOWN_COST


## The pre-placement height formula, verbatim (tb37's flat +0.5 ramp
## offset — Pass C's corrected +0.25 lives only in `MapGen`'s own surface
## authoring, which a legacy, unplaced grid never went through).
static func height_for_cell(grid: Grid, cell: Vector2i, caller: String) -> float:
	_record(caller)
	var height: float = grid.get_level(cell) * UnitGeometry.LEVEL_HEIGHT
	if grid.get_terrain(cell) == Enums.TerrainType.RAMP:
		height += UnitGeometry.LEVEL_HEIGHT * 0.5
	return height
