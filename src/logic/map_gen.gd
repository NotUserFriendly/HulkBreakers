class_name MapGen
extends RefCounted

## Seeded BSP dungeon generator: recursively splits the map into leaf
## rectangles, carves a room in each leaf, and connects sibling rooms with
## L-shaped corridors as the recursion unwinds — this guarantees every room
## (and therefore both spawn zones) sits in one connected component.

const MIN_LEAF_SIZE: int = 8
const MIN_ROOM_SIZE: int = 3
const MIN_CHILD_SIZE: int = MIN_ROOM_SIZE + 2

const COVER_PROBABILITY: float = 0.18
const FULL_COVER_CHANCE: float = 0.35
const HALF_COVER_VALUE: float = 0.5
const FULL_COVER_VALUE: float = 1.0

const SPAWN_ZONE_SIZE: int = 2


static func generate(seed: int, width: int, height: int) -> Grid:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

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
	_ensure_spawns_connected(grid, spawn_cells[0], spawn_cells[1])

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
		var lo: int = maxi(MIN_CHILD_SIZE, rect.size.x / 3)
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
		var lo_y: int = maxi(MIN_CHILD_SIZE, rect.size.y / 3)
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
	return room.position + room.size / 2


static func _carve_corridor(
	grid: Grid, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator
) -> void:
	var mid: Vector2i = Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_carve_straight(grid, a, mid)
	_carve_straight(grid, mid, b)


static func _carve_straight(grid: Grid, a: Vector2i, b: Vector2i) -> void:
	if a.x == b.x:
		var y_start: int = mini(a.y, b.y)
		var y_end: int = maxi(a.y, b.y)
		for y in range(y_start, y_end + 1):
			_set_open(grid, Vector2i(a.x, y))
	else:
		var x_start: int = mini(a.x, b.x)
		var x_end: int = maxi(a.x, b.x)
		for x in range(x_start, x_end + 1):
			_set_open(grid, Vector2i(x, a.y))


static func _set_open(grid: Grid, cell: Vector2i) -> void:
	if not grid.in_bounds(cell):
		return
	grid.set_terrain(cell, Enums.TerrainType.OPEN)
	grid.set_opacity(cell, 0.0)


static func _scatter_cover(grid: Grid, rng: RandomNumberGenerator) -> void:
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) != Enums.TerrainType.OPEN:
				continue
			if rng.randf() < COVER_PROBABILITY:
				var value: float = (
					FULL_COVER_VALUE if rng.randf() < FULL_COVER_CHANCE else HALF_COVER_VALUE
				)
				grid.set_cover_value(cell, value)
				# Terrain-scattered cover is permanent (never destructible).
				var cover_object := Part.new()
				cover_object.id = &"terrain_cover"
				cover_object.is_destructible = false
				grid.blockers[cell] = cover_object


## Picks the two carved rooms whose centers are farthest apart (Chebyshev) and
## tags a small zone in each with SPAWN_A / SPAWN_B. Returns [cell_a, cell_b],
## one representative cell per zone.
static func _place_spawn_zones(grid: Grid, rooms: Array[Rect2i]) -> Array:
	var best_a: Rect2i = rooms[0]
	var best_b: Rect2i = rooms[1] if rooms.size() > 1 else rooms[0]
	var best_dist: int = -1
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var center_i: Vector2i = rooms[i].position + rooms[i].size / 2
			var center_j: Vector2i = rooms[j].position + rooms[j].size / 2
			var d: int = Grid.distance_chebyshev(center_i, center_j)
			if d > best_dist:
				best_dist = d
				best_a = rooms[i]
				best_b = rooms[j]

	var cell_a: Vector2i = _mark_zone(grid, best_a, Enums.TerrainType.SPAWN_A)
	var cell_b: Vector2i = _mark_zone(grid, best_b, Enums.TerrainType.SPAWN_B)
	return [cell_a, cell_b]


static func _mark_zone(grid: Grid, room: Rect2i, terrain_code: int) -> Vector2i:
	var w: int = mini(SPAWN_ZONE_SIZE, room.size.x)
	var h: int = mini(SPAWN_ZONE_SIZE, room.size.y)
	for y in range(room.position.y, room.position.y + h):
		for x in range(room.position.x, room.position.x + w):
			grid.set_terrain(Vector2i(x, y), terrain_code)
	return room.position


## Safety net: BSP corridor-carving already guarantees connectivity, but if a
## future change ever breaks that invariant, force a direct corridor rather
## than silently shipping an unwinnable map.
static func _ensure_spawns_connected(grid: Grid, a: Vector2i, b: Vector2i) -> void:
	var pf := Pathfinder.new(grid, {Enums.TerrainType.WALL: -1.0})
	if pf.astar(a, b).is_empty():
		var rng := RandomNumberGenerator.new()
		_carve_corridor(grid, a, b, rng)
