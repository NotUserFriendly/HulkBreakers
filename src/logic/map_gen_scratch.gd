class_name MapGenScratch
extends RefCounted

## taskblock-39 Pass B: `MapGen`'s own private carving scratch — never
## `Grid`'s public `terrain`/`level` API. BSP carving legitimately
## re-visits the same cell many times (splitting rooms, re-cutting
## corridors, repair passes, the emergency fallback corridor), which
## `Grid.surfaces`'s own attachment grammar correctly refuses a second
## `GROUND` placement onto. Carving here, with no grammar involved at all,
## and emitting real surfaces once from the finished result, is what
## actually resolves that tension instead of contorting the carver to
## satisfy a grammar it shouldn't be talking to yet (`MapGen._emit`'s own
## doc comment has the full picture).
##
## Mirrors the subset of `Grid`'s own shape carving actually needs — never
## `opacity`/`blockers`/`surfaces`/`occupant_id`, none of which this
## taskblock's own scope touches; those stay direct `Grid` writes
## throughout generation, unaffected by this split.

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
	terrain.fill(Enums.TerrainType.WALL)
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
## `Pathfinder`'s connectivity floods are already correct, tested, and
## instrumented (`GridLegacyBridge`); rebuilding that logic a second time
## against scratch directly would be exactly the "two paths that could
## disagree" CLAUDE.md's own no-parallel-systems rule warns about. This
## mirror carries no surfaces at all, so `GridLegacyBridge.is_legacy`
## correctly reads it as legacy and routes through the pre-placement
## terrain/level formula — precisely what a mid-generation reachability
## check over a still-forming map wants.
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
	temp.terrain = terrain.duplicate()
	temp.level = level.duplicate()
	temp.blockers = blockers.duplicate()
	return temp
