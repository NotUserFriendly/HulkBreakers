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
var height: int

var terrain: Array[int] = []
var opacity: Array[float] = []
var cover_value: Array[float] = []
var occupant_id: Array[int] = []
var blockers: Dictionary = {}  # Vector2i -> Part; the object backing a cover_value > 0 cell, if any
var field_items: Dictionary = {}  # Vector2i -> Array[Part|Matrix]; loose items lying on the ground


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	var count := width * height
	terrain.resize(count)
	opacity.resize(count)
	cover_value.resize(count)
	occupant_id.resize(count)
	terrain.fill(0)
	opacity.fill(0.0)
	cover_value.fill(0.0)
	occupant_id.fill(-1)


func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func get_terrain(cell: Vector2i) -> int:
	return terrain[_index(cell)]


func set_terrain(cell: Vector2i, value: int) -> void:
	terrain[_index(cell)] = value


func get_opacity(cell: Vector2i) -> float:
	return opacity[_index(cell)]


func set_opacity(cell: Vector2i, value: float) -> void:
	opacity[_index(cell)] = value


func get_cover_value(cell: Vector2i) -> float:
	return cover_value[_index(cell)]


func set_cover_value(cell: Vector2i, value: float) -> void:
	cover_value[_index(cell)] = value


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
	var cloned := Grid.new(width, height)
	cloned.terrain = terrain.duplicate()
	cloned.opacity = opacity.duplicate()
	cloned.cover_value = cover_value.duplicate()
	cloned.occupant_id = occupant_id.duplicate()
	for cell: Vector2i in blockers:
		cloned.blockers[cell] = (blockers[cell] as Part).duplicate(true)
	for cell: Vector2i in field_items:
		var cloned_items: Array = []
		for item: Variant in field_items[cell]:
			cloned_items.append(item.duplicate(true))
		cloned.field_items[cell] = cloned_items
	return cloned


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
