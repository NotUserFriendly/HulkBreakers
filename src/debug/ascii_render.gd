class_name AsciiRender
extends RefCounted

## ASCII dumps of spatial state — CC's eyes (CLAUDE.md / docs/09). Every
## spatial rule must be verifiable by printing one of these into a test log.

const CHAR_WALL := "#"
const CHAR_OPEN := "."
const CHAR_SPAWN_A := "a"
const CHAR_SPAWN_B := "b"
const CHAR_HALF_COVER := "o"
const CHAR_FULL_COVER := "O"
const CHAR_IMPACT := "*"
const CHAR_GAP := "."
const CHAR_UNKNOWN := "?"


## Renders a Grid as a text block, one row per line, one char per cell.
## `occupants` optionally maps Vector2i -> a single display character that
## overrides terrain/cover at that cell (e.g. unit markers).
static func grid_to_text(grid: Grid, occupants: Dictionary = {}) -> String:
	var lines: Array[String] = []
	for y in range(grid.height):
		var row := ""
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if occupants.has(cell):
				row += str(occupants[cell])
			else:
				row += _terrain_char(grid, cell)
		lines.append(row)
	return "\n".join(lines)


static func _terrain_char(grid: Grid, cell: Vector2i) -> String:
	var terrain: int = grid.get_terrain(cell)
	match terrain:
		Enums.TerrainType.WALL:
			return CHAR_WALL
		Enums.TerrainType.SPAWN_A:
			return CHAR_SPAWN_A
		Enums.TerrainType.SPAWN_B:
			return CHAR_SPAWN_B
		_:
			var cover: float = grid.get_cover_value(cell)
			if cover >= 1.0:
				return CHAR_FULL_COVER
			if cover > 0.0:
				return CHAR_HALF_COVER
			return CHAR_OPEN


## Renders a depth-sorted "shot plane" — any Array of objects exposing
## `rect: Rect2`, `depth: float`, `part` (duck-typed; works for the real
## Region class from Phase 3 or a test fixture) — as a text grid spanning
## `width` x `height` view-space cells. Frontmost (lowest depth) region wins
## each cell, matching ShotPlane.resolve_projectile/resolve_ray's semantics.
static func plane_to_text(plane: Array, width: int, height: int) -> String:
	var cells: Array[String] = []
	cells.resize(width * height)
	cells.fill(CHAR_GAP)
	var depths: Array[float] = []
	depths.resize(width * height)
	depths.fill(INF)

	for region: Variant in plane:
		var rect: Rect2 = region.rect
		var depth: float = region.depth
		var glyph: String = _part_glyph(region.part)
		var x_start: int = maxi(int(rect.position.x), 0)
		var y_start: int = maxi(int(rect.position.y), 0)
		var x_end: int = mini(int(rect.position.x + rect.size.x), width)
		var y_end: int = mini(int(rect.position.y + rect.size.y), height)
		for y in range(y_start, y_end):
			for x in range(x_start, x_end):
				var idx: int = y * width + x
				if depth < depths[idx]:
					depths[idx] = depth
					cells[idx] = glyph

	var lines: Array[String] = []
	for y in range(height):
		var row := ""
		for x in range(width):
			row += cells[y * width + x]
		lines.append(row)
	return "\n".join(lines)


static func _part_glyph(part: Variant) -> String:
	if part == null:
		return CHAR_GAP
	var glyph_name: String = ""
	if "display_name" in part and part.display_name != "":
		glyph_name = part.display_name
	elif "id" in part:
		glyph_name = String(part.id)
	if glyph_name.is_empty():
		return CHAR_UNKNOWN
	return glyph_name.substr(0, 1).to_upper()


## Shot planes (docs/02) are naturally authored around the line of fire
## (x == 0), which plane_to_text would clip since it only draws
## non-negative coordinates. Returns shifted Region copies — never mutates
## `plane` — so a dump can be recentred into positive space for display
## without touching the coordinates anything else resolves against.
static func recenter(plane: Array, dx: float, dy: float = 0.0) -> Array:
	var shifted: Array = []
	for region: Variant in plane:
		shifted.append(
			Region.new(
				Rect2(region.rect.position + Vector2(dx, dy), region.rect.size),
				region.depth,
				region.part,
				region.surface_normal
			)
		)
	return shifted


## Overlays impact markers onto an already-rendered text block (from
## grid_to_text or plane_to_text), replacing whatever glyph sits at each
## impact point with `*` — for diffable before/after dumps of a seeded burst.
static func overlay_impacts(text: String, impacts: Array[Vector2i]) -> String:
	var lines: PackedStringArray = text.split("\n")
	for point: Vector2i in impacts:
		if point.y < 0 or point.y >= lines.size():
			continue
		var line: String = lines[point.y]
		if point.x < 0 or point.x >= line.length():
			continue
		lines[point.y] = line.substr(0, point.x) + CHAR_IMPACT + line.substr(point.x + 1)
	return "\n".join(lines)
