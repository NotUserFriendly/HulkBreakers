class_name BoardPicker
extends RefCounted

## Pure ground-plane math (docs/10): given a ray in world space, the grid
## cell it points at, or null if the ray never crosses the board (looking
## above the horizon, or parallel to it). The Node supplies the ray —
## `Camera3D.project_ray_origin`/`project_ray_normal` need a live viewport
## to mean anything — everything after that is plain, headless-testable
## arithmetic, no SceneTree required.
##
## taskblock-37 Pass E follow-up (supervisor bug report: "mousing over a
## cell requires you to mouse over the base of the terrain, not the top"):
## this used to intersect a single fixed y == 0 plane unconditionally —
## correct before terrain terraced, wrong the moment a cell's own real
## top face (`UnitGeometry.true_height_for_cell`) moved above or below
## world 0. An optional `grid` param resolves against the REAL terrain
## instead: which cell a ray lands on depends on the terrain's own height
## there, and that height depends on which cell you're over — solved by
## iterative refinement (guess a height, find where the ray crosses it,
## look up that cell's own real height, repeat) rather than a single
## closed-form solve, since the surface is a stepped heightfield, not one
## plane. `grid` defaults to null, preserving the original flat-plane
## behavior for every caller that never had elevation to worry about.
const MAX_HEIGHT_ITERATIONS := 4


static func cell_at_ray(from: Vector3, dir: Vector3, grid: Grid = null) -> Variant:
	var hit: Variant = _resolve(from, dir, grid)
	return (hit as Dictionary)["cell"] if hit != null else null


## docs/10 taskblock03 D1: the ray parameter `t` where a ray crosses the
## board's own real terrain, or null if it never does — split out from
## cell_at_ray so a caller (TacticsController) can compare this distance
## against UnitPicker's own hit distance to decide "nearest hit wins"
## between clicking a tile and clicking a unit's body.
static func plane_hit_t(from: Vector3, dir: Vector3, grid: Grid = null) -> Variant:
	var hit: Variant = _resolve(from, dir, grid)
	return (hit as Dictionary)["t"] if hit != null else null


## Bounded, not looped forever: a stepped board only has as many distinct
## heights as it has raised areas, so this converges in a couple of passes
## for any camera angle this game's tactical/orbit rig produces; capped so
## a ray skimming exactly along a riser boundary (oscillating between two
## neighboring cells' own heights) still terminates instead of spinning.
static func _resolve(from: Vector3, dir: Vector3, grid: Grid) -> Variant:
	if is_zero_approx(dir.y):
		return null
	var height := 0.0
	var cell := Vector2i.ZERO
	var has_cell := false
	for i in range(MAX_HEIGHT_ITERATIONS):
		var t: float = (height - from.y) / dir.y
		if t < 0.0:
			return null
		var world: Vector3 = from + dir * t
		var candidate := Vector2i(
			roundi(world.x / UnitGeometry.CELL_SIZE), roundi(world.z / UnitGeometry.CELL_SIZE)
		)
		if has_cell and candidate == cell:
			break
		cell = candidate
		has_cell = true
		height = (
			UnitGeometry.true_height_for_cell(cell, grid)
			if grid != null and grid.in_bounds(cell)
			else 0.0
		)
	var final_t: float = (height - from.y) / dir.y
	if final_t < 0.0:
		return null
	return {"cell": cell, "t": final_t}
