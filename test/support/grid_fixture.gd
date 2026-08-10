class_name GridFixture
extends RefCounted

## taskblock-39 Pass C: a real placement-model fixture builder for tests —
## every cell this builds carries an actual placed `Surface` via
## `GridPlacement`, the SAME call `MapGen._emit` makes, so a test exercises
## the real surface-based `Pathfinder`/`UnitGeometry` formula gameplay
## itself uses, unconditionally (taskblock-39 Pass D: the legacy
## migration bridge this used to route non-fixture grids through instead
## is retired outright).
##
## States intent, not syntax: "this cell is walkable at level 2" is
## `place_floor(grid, cell, 2.0)`, not a raw terrain/level poke a reader
## has to reverse-engineer, and the one thing every migrated fixture in
## this taskblock goes through instead of hand-rolling its own.


## A grid entirely floored at `level` (world height `level *
## UnitGeometry.LEVEL_HEIGHT`) — the common "flat room" starting point
## almost every fixture wants before it authors anything unusual.
static func flat(width: int, rows: int, level: float = 0.0) -> Grid:
	var grid := Grid.new(width, rows)
	for y in range(rows):
		for x in range(width):
			place_floor(grid, Vector2i(x, y), level)
	return grid


## Places (or re-places) a plain `ship_floor` surface at `cell`, at
## `level` (level-equivalents — the same unit `Grid.level` used to hold)
## with optional `facing` — walkable ground, nothing more. Clears
## whatever surface was already there first: the same clear-and-re-place
## idempotence `MapGen._emit` relies on, so a fixture can freely re-author
## a cell it already floored.
static func place_floor(
	grid: Grid, cell: Vector2i, level: float = 0.0, facing: float = 0.0
) -> void:
	grid.clear_surfaces(cell)
	var height: float = level * UnitGeometry.LEVEL_HEIGHT
	GridPlacement.place(grid, cell, DataLibrary.get_part(&"ship_floor"), height, facing)


## Places a single COSMETIC ramp cell at `cell` — `level` is this cell's own lower endpoint,
## `facing` the direction of ascent.
##
## **tb60 Pass A: this places content, not machinery.** The generator no longer authors ramps
## at all (it builds stairs out of `place_floor` at fractional levels, and a fixture wanting
## a stair does the same), and a ramp-tagged surface buys a mover nothing the geometry has
## not already earned. What this still does is place a real part with the sloped
## `RampGeometry` profile — which is what the rendering and picking tests that call it
## actually want, and why it survives rather than being deleted with the subsystem.
static func place_ramp(grid: Grid, cell: Vector2i, level: float, facing: float = 0.0) -> void:
	grid.clear_surfaces(cell)
	var height: float = level * UnitGeometry.LEVEL_HEIGHT + RampGeometry.STANDING_OFFSET
	GridPlacement.place(grid, cell, DataLibrary.get_part(&"ramp"), height, facing)


## taskblock-52 Pass A: a fully enclosed room — every cell floored, the whole
## perimeter carrying a real `wall` blocker. The geometry `BR34.05`'s standing
## rule is stated against ("a shot fired in here must hit something"), and the
## room `SeamSweep` measures, so the plane and the ray chain are always swept
## through the identical board rather than through two hand-built ones.
##
## The walls cell exactly: `wall`'s own box is a full 1.0-wide cell cube, so
## adjacent perimeter cells' boxes share a face with no gap between them. **Any
## empty this room produces is a defect in the resolver, never a hole in the
## fixture** — which is what makes it a usable measuring instrument at all.
static func enclosed_room(width: int, rows: int, level: float = 0.0) -> Grid:
	var grid: Grid = flat(width, rows, level)
	for x in range(width):
		place_wall(grid, Vector2i(x, 0), level)
		place_wall(grid, Vector2i(x, rows - 1), level)
	for y in range(rows):
		place_wall(grid, Vector2i(0, y), level)
		place_wall(grid, Vector2i(width - 1, y), level)
	return grid


## tb31 Pass C's settled wall model, verbatim (`MapGen._finalize_walls_
## and_empty`'s own "exposed wall" branch): ordinary floored ground
## carrying a real, destructible `wall` Part blocker — NOT an unfloored/unwalkable cell.
## taskblock-58 Pass C: it no longer also raises an opacity flag, because there is no longer one
## to raise; the `wall` Part's own box is what stops sight. A destroyed wall (hp <= 0)
## already reads as passable everywhere `Pathfinder`/`ShotPlane` check
## hp, so this makes no separate "destroyed" variant; a test wanting one
## destroys the same Part this returns.
static func place_wall(grid: Grid, cell: Vector2i, level: float = 0.0) -> Part:
	place_floor(grid, cell, level)
	var wall: Part = DataLibrary.get_part(&"wall")
	grid.place_blocker(cell, wall)
	return wall
