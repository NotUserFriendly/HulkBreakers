class_name UnitMarker
extends Node2D

## A unit as a flat-colored circle + HP bar. Programmer-primitive visuals only.

const RADIUS := 9.0
const COLOR_SQUAD_A := Color(0.15, 0.35, 0.95)
const COLOR_SQUAD_B := Color(0.9, 0.2, 0.2)
const COLOR_DEAD := Color(0.35, 0.35, 0.35)
const COLOR_SELECTED_RING := Color(1.0, 0.9, 0.1)

var unit: Unit
var selected: bool = false


func setup(p_unit: Unit) -> void:
	unit = p_unit


func _draw() -> void:
	if unit == null:
		return

	var body_color: Color = COLOR_DEAD
	if unit.alive:
		body_color = COLOR_SQUAD_A if unit.squad_id == 0 else COLOR_SQUAD_B

	if selected:
		draw_circle(Vector2.ZERO, RADIUS + 3.0, COLOR_SELECTED_RING)
	draw_circle(Vector2.ZERO, RADIUS, body_color)

	var hp_frac: float = _hp_fraction()
	var bar_w := 20.0
	var bar_h := 3.0
	var bar_origin := Vector2(-bar_w / 2.0, -RADIUS - 8.0)
	draw_rect(Rect2(bar_origin, Vector2(bar_w, bar_h)), Color(0.2, 0.2, 0.2))
	draw_rect(
		Rect2(bar_origin, Vector2(bar_w * hp_frac, bar_h)),
		Color(0.2, 0.9, 0.2).lerp(Color(0.9, 0.2, 0.2), 1.0 - hp_frac)
	)


func _hp_fraction() -> float:
	var total := 0
	var max_total := 0
	for part: Part in unit.chassis.slots.values():
		total += part.hp
		max_total += part.max_hp
	if max_total <= 0:
		return 0.0
	return float(total) / float(max_total)


func refresh() -> void:
	queue_redraw()
