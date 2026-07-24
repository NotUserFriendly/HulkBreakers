class_name GridFixture
extends RefCounted

## taskblock-39 Pass C: a real placement-model fixture builder for tests —
## every cell this builds carries an actual placed `Surface` via
## `GridPlacement`, the SAME call `MapGen._emit` makes, so a fixture Grid
## is never `GridLegacyBridge.is_legacy` and a test exercises the real
## surface-based `Pathfinder`/`UnitGeometry` formula gameplay itself uses
## — never the bridge's now migration-only fallback.
##
## States intent, not syntax: "this cell is walkable at level 2" is
## `place_floor(grid, cell, 2.0)`, not a `grid.set_level`/`set_terrain`
## poke a reader has to reverse-engineer, and the one thing every migrated
## fixture in this taskblock goes through instead of hand-rolling its own.


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


## Places a single ramp TILE at `cell` — `level` is this tile's own LOWER
## endpoint (docs/PLAN.md's settled height model, same convention
## `MapGen._stamp_ramp_pair` uses), `facing` the direction of ascent. This
## builds ONE tile's surface, the same primitive the real two-tile
## MapGen profile is stamped from — a fixture wanting that full profile
## calls this twice, once per tile, at the two levels it authors.
static func place_ramp(grid: Grid, cell: Vector2i, level: float, facing: float = 0.0) -> void:
	grid.clear_surfaces(cell)
	var height: float = level * UnitGeometry.LEVEL_HEIGHT + RampGeometry.STANDING_OFFSET
	GridPlacement.place(grid, cell, DataLibrary.get_part(&"ramp"), height, facing)


## tb31 Pass C's settled wall model, verbatim (`MapGen._finalize_walls_
## and_void`'s own "exposed wall" branch): ordinary floored ground
## carrying a real, destructible `wall` Part blocker, with opacity raised
## to 1.0 — NOT an unfloored/unwalkable cell. A destroyed wall (hp <= 0)
## already reads as passable everywhere `Pathfinder`/`ShotPlane` check
## hp, so this makes no separate "destroyed" variant; a test wanting one
## destroys the same Part this returns.
static func place_wall(grid: Grid, cell: Vector2i, level: float = 0.0) -> Part:
	place_floor(grid, cell, level)
	grid.set_opacity(cell, 1.0)
	var wall: Part = DataLibrary.get_part(&"wall")
	grid.blockers[cell] = wall
	return wall
