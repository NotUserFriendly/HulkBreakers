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

var terrain: Array[int] = []
var opacity: Array[float] = []
var occupant_id: Array[int] = []
## taskblock-36 Pass D: a cell's own elevation — 0 (ground level)
## everywhere on a fresh `MapGen` map, one whole number per `Grid.
## UnitGeometry.LEVEL_HEIGHT` step. `UnitGeometry` reads a unit's own
## cached `Unit.level` (synced from this at `CombatState.add_unit`) rather
## than this array directly — neither `UnitGeometry` nor `BodyProjector`
## otherwise touch the grid at all.
## taskblock-37 Pass E follow-up (supervisor): widened from a discrete
## `int` to a real `float` — genuinely arbitrary elevation (a gentle
## rise, a curb, anything finer than a whole level or a ramp's own fixed
## +0.5), not just whole levels plus the one ramp half-step. Every
## consumer that used to compare/subtract these as whole level COUNTS
## (`Pathfinder`'s climb/hop-down caps, `ClimbAction`/`HopDownAction`'s
## own rise math) already worked in continuous world-height terms or was
## updated to — nothing here assumes an integer anymore.
var level: Array[float] = []
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
## taskblock-38 Pass A: Vector2i -> Array[Surface] — the placement model's
## own store (a cell's ordered set of placed surfaces: floor, raised floor,
## ramp, catwalk, ...). Inert this pass: `terrain`/`level` stay
## authoritative and nothing reads this yet (see `GridPlacement`).
var surfaces: Dictionary = {}


func _init(p_width: int, p_rows: int) -> void:
	width = p_width
	rows = p_rows
	var count := width * rows
	terrain.resize(count)
	opacity.resize(count)
	occupant_id.resize(count)
	level.resize(count)
	terrain.fill(0)
	opacity.fill(0.0)
	occupant_id.fill(-1)
	level.fill(0.0)


func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < rows


func get_terrain(cell: Vector2i) -> int:
	return terrain[_index(cell)]


func set_terrain(cell: Vector2i, value: int) -> void:
	terrain[_index(cell)] = value


func get_opacity(cell: Vector2i) -> float:
	return opacity[_index(cell)]


func set_opacity(cell: Vector2i, value: float) -> void:
	opacity[_index(cell)] = value


func get_occupant_id(cell: Vector2i) -> int:
	return occupant_id[_index(cell)]


func set_occupant_id(cell: Vector2i, value: int) -> void:
	occupant_id[_index(cell)] = value


func get_level(cell: Vector2i) -> float:
	return level[_index(cell)]


func set_level(cell: Vector2i, value: float) -> void:
	level[_index(cell)] = value


## A fully independent copy for TACTICS-time speculative previews (docs/09).
## Dictionary.duplicate(true) only deep-copies nested containers, not the
## Part/Matrix objects they hold, so blockers and field_items are rebuilt
## with their own values individually duplicated — a preview attack that
## destroys cover must never touch the real Part.
func dup() -> Grid:
	var cloned := Grid.new(width, rows)
	cloned.terrain = terrain.duplicate()
	cloned.opacity = opacity.duplicate()
	cloned.occupant_id = occupant_id.duplicate()
	cloned.level = level.duplicate()
	for cell: Vector2i in blockers:
		cloned.blockers[cell] = (blockers[cell] as Part).duplicate(true)
	for cell: Vector2i in field_items:
		var cloned_items: Array = []
		for item: Variant in field_items[cell]:
			cloned_items.append(item.duplicate(true))
		cloned.field_items[cell] = cloned_items
	for cell: Vector2i in surfaces:
		var cloned_surfaces: Array[Surface] = []
		for surface: Surface in surfaces[cell]:
			cloned_surfaces.append(
				Surface.new(surface.part.duplicate(true), surface.height, surface.facing)
			)
		cloned.surfaces[cell] = cloned_surfaces
	return cloned


## tb35 Pass C: reverse lookup — the cell holding `part` as its own
## `blockers` entry, or null if it isn't (or is no longer) one. O(blocker
## count); only meant for a destroyed-blocker's own rare cleanup (see
## `DamageResolver._resolve_destruction_consequences`'s own doc comment),
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
func surfaces_at(cell: Vector2i) -> Array[Surface]:
	if surfaces.has(cell):
		return surfaces[cell]
	return []


func add_surface(cell: Vector2i, surface: Surface) -> void:
	if not surfaces.has(cell):
		surfaces[cell] = [] as Array[Surface]
	(surfaces[cell] as Array[Surface]).append(surface)


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
