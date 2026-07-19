class_name MapGen
extends RefCounted

## Seeded BSP dungeon generator: recursively splits the map into leaf
## rectangles, carves a room in each leaf, and connects sibling rooms with
## L-shaped corridors as the recursion unwinds — this guarantees every room
## (and therefore both spawn zones) sits in one connected component.

## taskblock-16 Pass C: "too cramped — no room to maneuver or use cover."
## Rooms >= 7 on their min dimension; MIN_CHILD_SIZE keeps a split child
## room-sized (its own `+ 2` for the 1-cell border `_carve_room` always
## leaves); MIN_LEAF_SIZE keeps the same buffer over MIN_CHILD_SIZE the
## old 8-vs-5 pair had (a margin, not a hard requirement — only
## MIN_LEAF_SIZE >= MIN_CHILD_SIZE is load-bearing, for `_split_and_carve`
## to hand both children a valid size).
const MIN_ROOM_SIZE: int = 7
const MIN_CHILD_SIZE: int = MIN_ROOM_SIZE + 2
const MIN_LEAF_SIZE: int = MIN_CHILD_SIZE + 3

## taskblock-16 Pass C: corridors were a single carved cell wide — too
## cramped for movement or cover once rooms are actually spacious. Each
## corridor rolls its own width in this range (seeded), same "obvious
## knob" convention as room sizing.
const CORRIDOR_WIDTH_MIN: int = 3
const CORRIDOR_WIDTH_MAX: int = 5

const COVER_PROBABILITY: float = 0.18
## taskblock-16 Pass B2: the reference humanoid's own torso/head boundary
## (docs/01) — no longer a placement height (the object's own real volume
## IS its height now), kept only as the debug ASCII dump's own full/half
## glyph threshold (`AsciiRender._blocker_height`).
const FULL_COVER_HEIGHT: float = 1.60
## taskblock-16 Pass B1: "all cover objects (old three + new three) are
## field-object part-trees at a cell" — a flagged, uniformly-weighted
## pick among every real cover part this codebase has (never a design
## decision). `barrel_pallet` gets its own extra generation step
## (`_roll_barrels`) once picked — every other id is placed as-is.
const COVER_IDS: Array[StringName] = [
	&"scrap_pile", &"goo_barrel", &"crate", &"pillar", &"forklift", &"barrel_pallet"
]
## "generates with 0-4 goo_barrels on it (seeded)."
const BARREL_PALLET_MAX_BARRELS: int = 4

const SPAWN_ZONE_SIZE: int = 2


static func generate(map_seed: int, width: int, height: int) -> Grid:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed

	var grid := Grid.new(width, height)
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			grid.set_terrain(cell, Enums.TerrainType.WALL)
			grid.set_opacity(cell, 1.0)

	var rooms: Array[Rect2i] = []
	_split_and_carve(grid, Rect2i(Vector2i.ZERO, Vector2i(width, height)), rng, rooms)

	_scatter_cover(grid, rng)

	var spawn_cells: Array = _place_spawn_zones(grid, rooms)
	_ensure_spawns_connected(grid, spawn_cells[0], spawn_cells[1], rng)

	return grid


static func _split_and_carve(
	grid: Grid, rect: Rect2i, rng: RandomNumberGenerator, rooms: Array[Rect2i]
) -> Vector2i:
	var can_split_x: bool = rect.size.x >= MIN_LEAF_SIZE * 2
	var can_split_y: bool = rect.size.y >= MIN_LEAF_SIZE * 2

	if not can_split_x and not can_split_y:
		return _carve_room(grid, rect, rng, rooms)

	var split_x: bool
	if can_split_x and can_split_y:
		split_x = rng.randf() < 0.5
	else:
		split_x = can_split_x

	var child_a: Rect2i
	var child_b: Rect2i
	if split_x:
		@warning_ignore("integer_division")
		var lo: int = maxi(MIN_CHILD_SIZE, rect.size.x / 3)
		@warning_ignore("integer_division")
		var hi: int = mini(rect.size.x - MIN_CHILD_SIZE, rect.size.x * 2 / 3)
		if hi < lo:
			hi = lo
		var offset: int = rng.randi_range(lo, hi)
		var split_at: int = rect.position.x + offset
		child_a = Rect2i(rect.position, Vector2i(offset, rect.size.y))
		child_b = Rect2i(
			Vector2i(split_at, rect.position.y), Vector2i(rect.size.x - offset, rect.size.y)
		)
	else:
		@warning_ignore("integer_division")
		var lo_y: int = maxi(MIN_CHILD_SIZE, rect.size.y / 3)
		@warning_ignore("integer_division")
		var hi_y: int = mini(rect.size.y - MIN_CHILD_SIZE, rect.size.y * 2 / 3)
		if hi_y < lo_y:
			hi_y = lo_y
		var offset_y: int = rng.randi_range(lo_y, hi_y)
		var split_at_y: int = rect.position.y + offset_y
		child_a = Rect2i(rect.position, Vector2i(rect.size.x, offset_y))
		child_b = Rect2i(
			Vector2i(rect.position.x, split_at_y), Vector2i(rect.size.x, rect.size.y - offset_y)
		)

	var point_a: Vector2i = _split_and_carve(grid, child_a, rng, rooms)
	var point_b: Vector2i = _split_and_carve(grid, child_b, rng, rooms)
	_carve_corridor(grid, point_a, point_b, rng)
	return point_a


static func _carve_room(
	grid: Grid, leaf: Rect2i, rng: RandomNumberGenerator, rooms: Array[Rect2i]
) -> Vector2i:
	var max_w: int = maxi(MIN_ROOM_SIZE, leaf.size.x - 2)
	var max_h: int = maxi(MIN_ROOM_SIZE, leaf.size.y - 2)
	var room_w: int = mini(rng.randi_range(MIN_ROOM_SIZE, max_w), leaf.size.x - 2)
	var room_h: int = mini(rng.randi_range(MIN_ROOM_SIZE, max_h), leaf.size.y - 2)
	room_w = maxi(room_w, 1)
	room_h = maxi(room_h, 1)

	var max_offset_x: int = maxi(leaf.size.x - 2 - room_w, 0)
	var max_offset_y: int = maxi(leaf.size.y - 2 - room_h, 0)
	var offset_x: int = rng.randi_range(0, max_offset_x)
	var offset_y: int = rng.randi_range(0, max_offset_y)

	var room := Rect2i(
		leaf.position + Vector2i(1 + offset_x, 1 + offset_y), Vector2i(room_w, room_h)
	)

	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			_set_open(grid, Vector2i(x, y))

	rooms.append(room)
	@warning_ignore("integer_division")
	return room.position + room.size / 2


static func _carve_corridor(
	grid: Grid, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator
) -> void:
	var mid: Vector2i = Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	var width: int = rng.randi_range(CORRIDOR_WIDTH_MIN, CORRIDOR_WIDTH_MAX)
	_carve_straight(grid, a, mid, width)
	_carve_straight(grid, mid, b, width)


## taskblock-16 Pass C: carves a band `width` cells thick, centered on the
## a->b line, instead of the single-cell line the name still describes —
## widened perpendicular to the direction of travel so a straight run
## reads as one corridor, not `width` parallel ones.
static func _carve_straight(grid: Grid, a: Vector2i, b: Vector2i, width: int) -> void:
	@warning_ignore("integer_division")
	var behind: int = width / 2
	var ahead: int = width - 1 - behind
	if a.x == b.x:
		var y_start: int = mini(a.y, b.y)
		var y_end: int = maxi(a.y, b.y)
		for y in range(y_start, y_end + 1):
			for x in range(a.x - behind, a.x + ahead + 1):
				_set_open(grid, Vector2i(x, y))
	else:
		var x_start: int = mini(a.x, b.x)
		var x_end: int = maxi(a.x, b.x)
		for x in range(x_start, x_end + 1):
			for y in range(a.y - behind, a.y + ahead + 1):
				_set_open(grid, Vector2i(x, y))


## taskblock-16 Pass B: also clears any blocker already sitting at `cell`
## — harmless during the main carve (nothing's in `blockers` yet at that
## point), but load-bearing for `_ensure_spawns_connected`'s own forced-
## corridor fallback, which runs AFTER `_scatter_cover`: forcing a cell
## open but leaving a blocker sitting in it would still leave that "fix"
## corridor impassable (`Pathfinder.move_cost` now checks `blockers`
## too), defeating the whole safety net.
static func _set_open(grid: Grid, cell: Vector2i) -> void:
	if not grid.in_bounds(cell):
		return
	grid.set_terrain(cell, Enums.TerrainType.OPEN)
	grid.set_opacity(cell, 0.0)
	grid.blockers.erase(cell)


## taskblock-16 Pass B: cover used to be a single synthetic, permanent,
## non-destructible box driving a numeric `cover_value` alongside it —
## the "two-parallel-systems" B2 retired. Every scattered cell now gets a
## REAL field object (`_make_cover`, below): destructible, salvageable,
## lootable exactly like any other Part, already blocking movement
## (`Pathfinder.move_cost`) and projecting into the shot plane
## (`ShotPlane.build` already reads every `grid.blockers` entry) the
## instant it's placed here — no further wiring needed.
static func _scatter_cover(grid: Grid, rng: RandomNumberGenerator) -> void:
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) != Enums.TerrainType.OPEN:
				continue
			if rng.randf() < COVER_PROBABILITY:
				grid.blockers[cell] = _make_cover(rng)


static func _make_cover(rng: RandomNumberGenerator) -> Part:
	var id: StringName = COVER_IDS[rng.randi() % COVER_IDS.size()]
	var part: Part = DataLibrary.get_part(id)
	if id == &"barrel_pallet":
		_roll_barrels(part, rng)
	return part


## "A barrel_pallet generates with 0-4 goo_barrels on it (seeded)" — each
## real `goo_barrel` attached through `PartGraph.attach` (never
## `Part.contents` — only `sockets` project into the shot plane, so only
## an attached barrel can ever actually be shot and cooked off).
static func _roll_barrels(pallet: Part, rng: RandomNumberGenerator) -> void:
	var count: int = rng.randi_range(0, BARREL_PALLET_MAX_BARRELS)
	for i in range(count):
		var socket: Socket = PartGraph.find_free_socket(pallet, &"BARREL_SLOT")
		if socket == null:
			break
		PartGraph.attach(DataLibrary.get_part(&"goo_barrel"), pallet, socket)


## Picks the two carved rooms whose centers are farthest apart (Chebyshev) and
## tags a small zone in each with SPAWN_A / SPAWN_B. Returns [cell_a, cell_b],
## one representative cell per zone.
##
## `_split_and_carve` only splits a leaf when BOTH its dimensions clear
## `MIN_LEAF_SIZE * 2` — a grid smaller than that (e.g. a 12x10 fixture,
## taskblock-16/17's own single-room regression before both real callers'
## default sizes were fixed) never clears that bar, so it always carves
## exactly one room. When `best_a` and
## `best_b` land on the very same room (single room, or every room tied at
## distance 0), marking SPAWN_B into it the normal way would silently
## overwrite every SPAWN_A cell just written — one squad would spawn
## nowhere in the grid at all, and its caller would have to fall back to a
## coordinate no longer guaranteed to be inside carved-open ground (this was
## a real, reproduced bug: BattleScene's own hardcoded fallback landed a
## unit on a WALL cell for several seeds before this fix). Split into two
## non-overlapping corners of that one room instead.
static func _place_spawn_zones(grid: Grid, rooms: Array[Rect2i]) -> Array:
	var best_a: Rect2i = rooms[0]
	var best_b: Rect2i = rooms[1] if rooms.size() > 1 else rooms[0]
	var best_dist: int = -1
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			@warning_ignore("integer_division")
			var center_i: Vector2i = rooms[i].position + rooms[i].size / 2
			@warning_ignore("integer_division")
			var center_j: Vector2i = rooms[j].position + rooms[j].size / 2
			var d: int = Grid.distance_chebyshev(center_i, center_j)
			if d > best_dist:
				best_dist = d
				best_a = rooms[i]
				best_b = rooms[j]

	if best_a == best_b:
		var cell_a: Vector2i = _mark_zone(grid, best_a, Enums.TerrainType.SPAWN_A)
		var cell_b: Vector2i = _mark_zone(grid, _far_corner(best_a), Enums.TerrainType.SPAWN_B)
		return [cell_a, cell_b]

	var cell_a: Vector2i = _mark_zone(grid, best_a, Enums.TerrainType.SPAWN_A)
	var cell_b: Vector2i = _mark_zone(grid, best_b, Enums.TerrainType.SPAWN_B)
	return [cell_a, cell_b]


## The room's own bottom-right SPAWN_ZONE_SIZE-ish corner, as a room-shaped
## Rect2i `_mark_zone` can mark directly — guaranteed a different position
## than `room.position` itself since MIN_ROOM_SIZE is always bigger than
## a 2x2 zone in at least one axis.
static func _far_corner(room: Rect2i) -> Rect2i:
	var w: int = mini(SPAWN_ZONE_SIZE, room.size.x)
	var h: int = mini(SPAWN_ZONE_SIZE, room.size.y)
	return Rect2i(room.position + room.size - Vector2i(w, h), Vector2i(w, h))


## taskblock-16 Pass B: `_scatter_cover` runs BEFORE spawn zones are
## marked (it only ever sees plain OPEN cells) — a scattered blocker can
## land on a cell that becomes a spawn zone a moment later. Harmless
## while blockers were purely cosmetic, but now that they actually block
## movement (`Pathfinder.move_cost`), a leftover blocker on a spawn cell
## would make it unwalkable, or worse, plant a unit inside real,
## occupied geometry at turn 0. Clearing any blocker here — the one
## place every spawn cell is already visited — keeps spawn zones
## guaranteed clear without a second full-grid pass.
static func _mark_zone(grid: Grid, room: Rect2i, terrain_code: int) -> Vector2i:
	var w: int = mini(SPAWN_ZONE_SIZE, room.size.x)
	var h: int = mini(SPAWN_ZONE_SIZE, room.size.y)
	for y in range(room.position.y, room.position.y + h):
		for x in range(room.position.x, room.position.x + w):
			var cell := Vector2i(x, y)
			grid.set_terrain(cell, terrain_code)
			grid.blockers.erase(cell)
	return room.position


## Safety net: BSP corridor-carving already guarantees connectivity, but if a
## future change ever breaks that invariant, force a direct corridor rather
## than silently shipping an unwinnable map.
##
## taskblock-16 Pass B: this used to spin up its own unseeded
## `RandomNumberGenerator` — harmless while the fallback almost never
## triggered, but movement-blocking cover (`Pathfinder.move_cost` now
## checks `blockers`) trips it far more often, which turned that unseeded
## generator into real, visible non-determinism (`same seed, two calls,
## two different maps`). Reuses the caller's already-seeded `rng` instead.
##
## taskblock-16 Pass C: `_carve_corridor` runs straight through `a` and
## `b` themselves — the spawn cells, not just their surroundings — and
## `_set_open` stamps every cell it touches back to plain OPEN. Wider
## (3-5 cell) corridors make the forced fallback trigger far more often
## (bigger rooms leave less slack for the BSP's own corridors to land
## cleanly) than it used to, which turned "the fallback occasionally
## reruns over a spawn cell" from a one-cell coincidence into "the
## fallback reliably erases the SPAWN_A/SPAWN_B tag it was supposed to
## reconnect a path *to*" (test failure: "spawn zone A must exist" with
## zero SPAWN_A cells left anywhere in the grid). Snapshot every
## SPAWN_A/SPAWN_B cell first and re-stamp them after carving — the
## fallback's whole job is reconnecting those zones, never relabeling
## them.
static func _ensure_spawns_connected(
	grid: Grid, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator
) -> void:
	var pf := Pathfinder.new(grid, {Enums.TerrainType.WALL: -1.0})
	if pf.astar(a, b).is_empty():
		var spawn_a_cells: Array[Vector2i] = _find_terrain_cells(grid, Enums.TerrainType.SPAWN_A)
		var spawn_b_cells: Array[Vector2i] = _find_terrain_cells(grid, Enums.TerrainType.SPAWN_B)
		_carve_corridor(grid, a, b, rng)
		for cell: Vector2i in spawn_a_cells:
			grid.set_terrain(cell, Enums.TerrainType.SPAWN_A)
		for cell: Vector2i in spawn_b_cells:
			grid.set_terrain(cell, Enums.TerrainType.SPAWN_B)


static func _find_terrain_cells(grid: Grid, terrain_code: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain_code:
				result.append(cell)
	return result
