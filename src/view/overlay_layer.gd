class_name OverlayLayer
extends Node2D

## Draws reachable-move highlight, cover markers, and the last hit result —
## all programmer-primitive shapes on top of GridView's tiles.

const TILE_PX := GridView.TILE_PX
const COLOR_REACHABLE := Color(0.2, 0.9, 0.3, 0.35)
const COLOR_ATTACK_RANGE := Color(0.9, 0.2, 0.2, 0.25)
const COLOR_HALF_COVER := Color(0.9, 0.75, 0.1)
const COLOR_FULL_COVER := Color(0.9, 0.45, 0.05)

var grid: Grid
var reachable_cells: Array[Vector2i] = []
var attack_range_cells: Array[Vector2i] = []
var last_hit_cell: Vector2i = Vector2i(-1, -1)
var last_hit_label: String = ""


func _draw() -> void:
	if grid == null:
		return

	for cell: Vector2i in reachable_cells:
		draw_rect(_cell_rect(cell), COLOR_REACHABLE)
	for cell: Vector2i in attack_range_cells:
		draw_rect(_cell_rect(cell), COLOR_ATTACK_RANGE)

	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var cover: float = grid.get_cover_value(cell)
			if cover <= 0.0:
				continue
			var color: Color = COLOR_FULL_COVER if cover >= 1.0 else COLOR_HALF_COVER
			var center: Vector2 = _cell_center(cell)
			draw_circle(center, 4.0, color)

	if last_hit_cell.x >= 0 and not last_hit_label.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			_cell_center(last_hit_cell) + Vector2(-TILE_PX / 2.0, -TILE_PX / 2.0 - 4.0),
			last_hit_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12
		)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell.x * TILE_PX, cell.y * TILE_PX), Vector2(TILE_PX, TILE_PX))


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_PX + TILE_PX / 2.0, cell.y * TILE_PX + TILE_PX / 2.0)


func set_grid(p_grid: Grid) -> void:
	grid = p_grid
	queue_redraw()


func set_reachable(cells: Array[Vector2i]) -> void:
	reachable_cells = cells
	queue_redraw()


func set_attack_range(cells: Array[Vector2i]) -> void:
	attack_range_cells = cells
	queue_redraw()


func show_hit(cell: Vector2i, label: String) -> void:
	last_hit_cell = cell
	last_hit_label = label
	queue_redraw()


func clear_selection_overlays() -> void:
	reachable_cells = []
	attack_range_cells = []
	queue_redraw()
