class_name Grid
extends RefCounted

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]

var width: int
## taskblock-36 Pass D: renamed from `height` in the same commit that adds
## `level` below — `height` meaning "row count" and a cell's own real
## elevation coexisting under similar names is exactly the trap CLAUDE.md
## warns about; `Region.depth` already means "distance along the shot
## ray," so `depth` was never a candidate either.
var rows: int

## taskblock-39 Pass D: holds `Enums.SpawnMarker` values only — a game
## marker (which squad starts where), never a physical fact. Every
## physical fact a cell can carry (walkable ground, a ramp, a wall,
## empty space) is expressed by placement now (`surfaces`/`blockers`
## below); the old dense `TerrainType` array this used to be (the
## field's own old name was `terrain`, with four retired values — see
## docs/SUPERSEDED.md) is retired outright, along with `Grid.level`.
var spawn_marker: Array[int] = []
var occupant_id: Array[int] = []
## Vector2i -> Part; a field object (cover, scrap, a barrel, ...) sitting
## at this cell. taskblock-16 Pass B2: the ONE source of truth for "is
## this cell covered" — the old `cover_value` scalar is retired (it never
## fed hit resolution, LoS, or AI decisions to begin with; only a tooltip
## line and a debug dump read it). Object geometry — height, via
## `BodyProjector`/`ShotPlane` projection — is what "half vs full cover"
## falls out of now, not a stored number. Also blocks movement
## (`Pathfinder.move_cost`) — a unit can no longer stand inside cover.
var blockers: Dictionary = {}
var field_items: Dictionary = {}  # Vector2i -> Array[Part|Matrix]; loose items lying on the ground

## taskblock-58 Pass B: **the store.** Every placed surface, in placement order, each one
## carrying its own `cell`.
##
## Until this pass the store was `surfaces: Dictionary[Vector2i, Array[Surface]]` and a
## placement's position was its dictionary *key* — so a floor could not exist except as
## something a cell held, and moving one meant delete-and-re-add. That is the inversion: a
## placement has a position, and the cell lookup becomes an index over it.
##
## **Read it through `placements()`.** The five callers that used to walk `surfaces` all wanted
## "every placed surface" and had to reach it a cell at a time; they now get a flat walk with no
## per-cell dictionary lookup, which is why `RayCaster` came out of this pass slightly cheaper
## rather than slightly dearer.
var _placements: Array[Surface] = []

## The index, `Vector2i -> Array[Surface]`, derived from `_placements` and never authored
## directly. Kept because `surfaces_at()` is a per-query call on hot paths (`Pathfinder`,
## `UnitGeometry.true_height_for_cell`) and a scan of the store would turn an O(1) lookup into
## an O(placements) one. Per-cell order matches placement order, which `MapFile` relies on.
var _by_cell: Dictionary = {}


func _init(p_width: int, p_rows: int) -> void:
	width = p_width
	rows = p_rows
	var count := width * rows
	spawn_marker.resize(count)
	occupant_id.resize(count)
	spawn_marker.fill(Enums.SpawnMarker.NONE)
	occupant_id.fill(-1)


func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < rows


func get_spawn_marker(cell: Vector2i) -> int:
	return spawn_marker[_index(cell)]


func set_spawn_marker(cell: Vector2i, value: int) -> void:
	spawn_marker[_index(cell)] = value


func get_occupant_id(cell: Vector2i) -> int:
	return occupant_id[_index(cell)]


func set_occupant_id(cell: Vector2i, value: int) -> void:
	occupant_id[_index(cell)] = value


## A fully independent copy for TACTICS-time speculative previews (docs/09).
## Dictionary.duplicate(true) only deep-copies nested containers, not the
## Part/Matrix objects they hold, so blockers and field_items are rebuilt
## with their own values individually duplicated — a preview attack that
## destroys cover must never touch the real Part.
func dup() -> Grid:
	var cloned := Grid.new(width, rows)
	cloned.spawn_marker = spawn_marker.duplicate()
	cloned.occupant_id = occupant_id.duplicate()
	for cell: Vector2i in blockers:
		cloned.blockers[cell] = (blockers[cell] as Part).duplicate(true)
	for cell: Vector2i in field_items:
		var cloned_items: Array = []
		for item: Variant in field_items[cell]:
			cloned_items.append(item.duplicate(true))
		cloned.field_items[cell] = cloned_items
	# taskblock-58 Pass B: **walked in store order**, so the clone's own store and index come out
	# in the same order this one is in — a preview whose surfaces_at() returned a cell's surfaces
	# in a different order than the real grid would be a preview of a different board.
	for surface: Surface in _placements:
		cloned.add_surface(
			surface.cell, Surface.new(surface.part.duplicate(true), surface.height, surface.facing)
		)
	return cloned


## tb35 Pass C: reverse lookup — the cell holding `part` as its own
## `blockers` entry, or null if it isn't (or is no longer) one. O(blocker
## count); only meant for a destroyed-blocker's own rare cleanup (see
## `DamageResolver.resolve_destruction_consequences`'s own doc comment),
## never a per-frame path.
func cell_of_blocker(part: Part) -> Variant:
	for cell: Vector2i in blockers:
		if blockers[cell] == part:
			return cell
	return null


## The first loose Part or Matrix at `cell` whose id matches, or null.
## Actions resolve a targeted ground item this way rather than holding a
## bare reference across states (docs/09): a preview's field_items are
## independently cloned.
func find_field_item(cell: Vector2i, item_id: StringName) -> Variant:
	if not field_items.has(cell):
		return null
	for item: Variant in field_items[cell]:
		if item.id == item_id:
			return item
	return null


## tb32 Pass C: the blocker at `cell`, or (if none) the first loose Part
## among its field_items — "something physical, but not a unit" a
## HitKind.PART target resolves to at RESOLUTION time (`AttackAction`/
## `BurstAction`), same "resolve fresh from state, never a bare cached
## reference" convention `find_field_item` already follows (docs/09: a
## preview's blockers/field_items are independently cloned). A loose
## Matrix never qualifies — nothing to draw real geometry from, so
## nothing for a shot to strike.
func shootable_part_at(cell: Vector2i) -> Part:
	if blockers.has(cell):
		return blockers[cell]
	if field_items.has(cell):
		for item: Variant in field_items[cell]:
			if item is Part:
				return item
	return null


## taskblock-38 Pass A: `surfaces.get(cell, [])`, typed — every reader gets
## a real (possibly empty) `Array[Surface]` rather than checking `has()`
## itself first.
##
## taskblock-58 Pass B: an **index** lookup now rather than the store itself. The contract is
## unchanged and deliberately so — this is the accessor thirty-one call sites already go
## through, which is what made the inversion cheap.
func surfaces_at(cell: Vector2i) -> Array[Surface]:
	if _by_cell.has(cell):
		return _by_cell[cell]
	return []


## **Every placement on this grid, in placement order.** taskblock-58 Pass B.
##
## The five callers that used to iterate `grid.surfaces` all wanted exactly this and had to
## assemble it a cell at a time. Returned live rather than copied: `RayCaster` walks it on every
## cast, and allocating a fresh array per ray is the kind of cost that only shows up in a
## profile. Treat it as read-only — `add_surface`/`move_placement`/`clear_surfaces` are the
## writers, because each of them has an index to keep in step.
func placements() -> Array[Surface]:
	return _placements


## The cells holding at least one placement. For a caller that genuinely counts *cells* rather
## than placements — one cell can hold several, so `placements().size()` is a different number
## and quietly substituting it is how a stat starts meaning something else.
func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_by_cell.keys())
	return cells


## taskblock-58 Pass B: **the one writer of `Surface.cell`.** The grid places a surface, so the
## grid is what says where it is; a caller setting the field itself could leave the placement and
## the index disagreeing, which is the only way an index can be wrong.
func add_surface(cell: Vector2i, surface: Surface) -> void:
	surface.cell = cell
	_placements.append(surface)
	if not _by_cell.has(cell):
		_by_cell[cell] = [] as Array[Surface]
	(_by_cell[cell] as Array[Surface]).append(surface)


## Moves an already-placed surface to `to_cell`, updating the index.
##
## taskblock-58 Pass B: **the thing the old storage could not do.** A position that was a
## dictionary key could only be changed by deleting the entry and adding it back, which is a
## different object as far as anything holding a reference is concerned. Now the placement is the
## same object at a new position and the index follows it. No-ops on a surface this grid does not
## hold, rather than inserting one it never placed.
func move_placement(surface: Surface, to_cell: Vector2i) -> bool:
	if not _placements.has(surface):
		return false
	if surface.cell == to_cell:
		return true
	_erase_from_index(surface)
	surface.cell = to_cell
	if not _by_cell.has(to_cell):
		_by_cell[to_cell] = [] as Array[Surface]
	(_by_cell[to_cell] as Array[Surface]).append(surface)
	return true


## taskblock-39 Pass B: the idempotent-carving seam — `MapGen._place_floor`
## clears a cell's own surfaces before re-placing, so a re-carved corridor
## or a repair pass can touch the same cell twice without `GridPlacement`'s
## attachment grammar correctly refusing a second `GROUND` placement.
##
## taskblock-58 Pass B: the early return is load-bearing rather than tidiness. `GridFixture.
## flat()` clears every cell before placing it, so the overwhelmingly common call is against a
## cell holding nothing — and without the guard each one would scan the whole store.
func clear_surfaces(cell: Vector2i) -> void:
	if not _by_cell.has(cell):
		return
	var removed: Array[Surface] = _by_cell[cell]
	_by_cell.erase(cell)
	var kept: Array[Surface] = []
	for surface: Surface in _placements:
		if not removed.has(surface):
			kept.append(surface)
	_placements = kept


func _erase_from_index(surface: Surface) -> void:
	if not _by_cell.has(surface.cell):
		return
	var at_cell: Array[Surface] = _by_cell[surface.cell]
	at_cell.erase(surface)
	if at_cell.is_empty():
		_by_cell.erase(surface.cell)


func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset: Vector2i in NEIGHBOR_OFFSETS:
		var n: Vector2i = cell + offset
		if in_bounds(n):
			result.append(n)
	return result


static func distance_chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func distance_manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Supercover line: every cell the segment a→b geometrically touches, including
## both cells bordering an exact lattice-corner crossing (never a diagonal skip
## through a corner gap). Symmetric: line(b, a) is line(a, b) reversed.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [a]
	var dx: int = b.x - a.x
	var dy: int = b.y - a.y
	var nx: int = absi(dx)
	var ny: int = absi(dy)
	var sign_x: int = 1 if dx > 0 else -1
	var sign_y: int = 1 if dy > 0 else -1

	var x: int = a.x
	var y: int = a.y
	var ix: int = 0
	var iy: int = 0

	while ix < nx or iy < ny:
		var decision: int = (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if decision == 0:
			result.append(Vector2i(x + sign_x, y))
			result.append(Vector2i(x, y + sign_y))
			x += sign_x
			y += sign_y
			result.append(Vector2i(x, y))
			ix += 1
			iy += 1
		elif decision < 0:
			x += sign_x
			result.append(Vector2i(x, y))
			ix += 1
		else:
			y += sign_y
			result.append(Vector2i(x, y))
			iy += 1
	return result
