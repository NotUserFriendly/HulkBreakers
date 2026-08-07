class_name MapGenScratch
extends RefCounted

## taskblock-39 Pass B: `MapGen`'s own private carving scratch — never
## `Grid`'s public API. BSP carving legitimately re-visits the same cell
## many times (splitting rooms, re-cutting corridors, repair passes, the
## emergency fallback corridor), which `Grid.surfaces`'s own attachment
## grammar correctly refuses a second `GROUND` placement onto. Carving
## here, with no grammar involved at all, and emitting real surfaces once
## from the finished result, is what actually resolves that tension
## instead of contorting the carver to satisfy a grammar it shouldn't be
## talking to yet (`MapGen._emit`'s own doc comment has the full picture).
##
## taskblock-39 Pass D: `CellKind` is this class's own local terrain
## representation, never `Grid`'s now-retired `TerrainType` — carving's
## own scratch-only concept of "not yet carved" (`UNCARVED`, the old
## `WALL`-as-default-marker) and "buried, permanently unreachable"
## (`EMPTY`, renamed from the old terrain model's own physical-absence
## value, taskblock-39 Pass D) never needs to be expressed as a
## `Grid`-facing type at all; only `_emit`'s own final sweep ever turns a
## scratch reading
## into a real placed `Surface`.
##
## Mirrors the subset of `Grid`'s own shape carving actually needs — never
## `opacity`/`blockers`/`surfaces`/`occupant_id`, none of which this
## taskblock's own scope touches; those stay direct `Grid` writes
## throughout generation, unaffected by this split.
## tb60 Pass A: **`RAMP` is gone.** A stair is now a run of ordinary `OPEN` cells at
## fractional `level` values, and `level` was already a float — so the thing that used to
## need its own cell kind needs no representation at all beyond the height it already had.
## That is the whole shape of the ramp retirement in one enum: the special case was never
## carrying information the general case lacked.
enum CellKind {
	UNCARVED,
	OPEN,
	EMPTY,
}

var width: int
var rows: int
var terrain: Array[int] = []
var level: Array[float] = []


func _init(p_width: int, p_rows: int) -> void:
	width = p_width
	rows = p_rows
	var count := width * rows
	terrain.resize(count)
	level.resize(count)
	terrain.fill(CellKind.UNCARVED)
	level.fill(0.0)


func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < rows


func get_terrain(cell: Vector2i) -> int:
	return terrain[_index(cell)]


func set_terrain(cell: Vector2i, value: int) -> void:
	terrain[_index(cell)] = value


func get_level(cell: Vector2i) -> float:
	return level[_index(cell)]


func set_level(cell: Vector2i, value: float) -> void:
	level[_index(cell)] = value


## A throwaway real `Grid` mirroring this scratch's own terrain/level —
## `Pathfinder`'s connectivity floods are already correct and tested;
## rebuilding that logic a second time against scratch directly would be
## exactly the "two paths that could disagree" CLAUDE.md's own
## no-parallel-systems rule warns about.
##
## taskblock-39 Pass C: `Pathfinder` reads surfaces only now, no legacy
## fallback — so a mid-generation reachability check over a still-forming
## map needs a temporary grid that actually CARRIES real surfaces, not
## just a terrain/level mirror. Every OPEN/RAMP scratch cell gets a real
## `place_surface` placement (the same formula `MapGen._emit` authors the
## real map with); every WALL cell (not yet carved, at this point in
## generation) gets none, reading correctly as unwalkable — the same
## outcome the old `{WALL: -1.0}` terrain cost achieved, just via a real
## placed-or-not surface instead of a terrain-code lookup.
##
## `blockers` is an explicit optional pass-through, not scratch's own
## state (this class's own doc comment above is clear that scratch never
## tracks it) — `Pathfinder._base_cost` reads `_grid.blockers` directly,
## so a reachability flood taken AFTER `_scatter_cover` without them would
## silently treat every scattered cover cell as open ground, missing
## exactly the "cover seals off a raised room's only approach" case
## `_repair_stranded_elevation`'s own doc comment describes. Callers
## running before cover exists simply omit it.
func as_temporary_grid(blockers: Dictionary = {}) -> Grid:
	var temp := Grid.new(width, rows)
	for y in range(rows):
		for x in range(width):
			var cell := Vector2i(x, y)
			if get_terrain(cell) == CellKind.OPEN:
				place_surface(temp, cell, get_level(cell))
	temp.blockers = blockers.duplicate()
	return temp


## The one formula that turns a scratch level reading into a real placed `Surface` — shared
## between this throwaway-grid builder and `MapGen._emit`'s own real, final authoring pass,
## so the two can never quietly drift apart into two formulas deciding the same height.
##
## tb60 Pass A: **one part id and one height formula, where there used to be two of each.**
## The terrain kind and the facing are both gone from the signature: every generated surface
## is a `ship_floor` at its own level, and a stair is a run of them at fractional levels. The
## `RampGeometry.STANDING_OFFSET` fudge — a ramp cell resting a quarter-level above its own
## authored height, so that "the level" and "the height you stand at" meant different things
## for exactly one cell kind — goes with it. A cell's height is now simply its height.
static func place_surface(grid: Grid, cell: Vector2i, cell_level: float) -> void:
	GridPlacement.place(
		grid, cell, DataLibrary.get_part(&"ship_floor"), cell_level * UnitGeometry.LEVEL_HEIGHT
	)
