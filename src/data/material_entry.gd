class_name MaterialEntry
extends Resource

## One row of the material table (docs/03). Armor is not more hitpoints —
## a part's `material` looks up its DT and deflection behavior here, so new
## materials are authored as data, never a code edit.

## Flat DT — read directly only when `dt_curve` is empty (every material
## authored before taskblock-09 E, and any deliberately thickness-
## independent material). Once a curve is authored, `dt_at()` is the real
## read path; this field stops mattering for combat but stays as the
## no-curve fallback.
## taskblock-10 Pass C: every material becomes its own `.tres`, so it needs
## to name itself — this row no longer only exists as a Dictionary key on
## `MaterialTable`. Empty for any entry built directly (tests, the unknown-
## material fallback below) rather than through `DataLibrary`.
@export var id: StringName = &""
@export var dt: float = 0.0
## taskblock-09 E: [(thickness, dt), ...], ascending by thickness — DT as
## a lookup table, not a formula, because composite/ablative/reactive
## armor has no clean formula and this game only ever authors a handful of
## thicknesses per material. Empty (the default) means "use the flat `dt`
## field instead," so no material needs migrating until someone actually
## wants it thickness-sensitive. To make a material tougher, edit its
## rows here — that's the entire knob, no code change.
@export var dt_curve: Array[Vector2] = []
## Incidence now spans the full 0-90 degrees (BodyProjector projects one
## face per visible side, docs/02) so this is a real tunable across that
## whole range. 30 is a flagged placeholder, not a design decision — ask
## before changing it.
@export var deflect_threshold_deg: float = 30.0
## Reserved: docs/03 names this field but specifies no formula for it yet.
## Storage only — do not derive ricochet behavior from it without asking.
@export var ricochet_bias: float = 0.0
@export var tags: Array[StringName] = []
## docs/10 "material colours are DATA": the mesh albedo for anything made of
## this material, world-rendered lit (never HulkTheme, which is UI-only).
## A neutral mid-grey default reads as "unknown material" rather than
## silently matching some other material's colour.
@export var color: Color = Color(0.5, 0.5, 0.5)


func _init(
	p_dt: float = 0.0, p_deflect_threshold_deg: float = 30.0, p_color: Color = Color(0.5, 0.5, 0.5)
) -> void:
	dt = p_dt
	deflect_threshold_deg = p_deflect_threshold_deg
	color = p_color


## taskblock-09 E: the DT this material actually offers at `thickness` —
## linearly interpolated between authored points, clamped to the nearest
## endpoint outside the authored range (never extrapolated: a 2-point
## curve extrapolated past its ends is how you get DT 900). Falls back to
## the flat `dt` field when no curve is authored, so nothing needs
## migrating until someone actually wants it thickness-sensitive.
func dt_at(thickness: float) -> float:
	if dt_curve.is_empty():
		return dt
	if thickness <= dt_curve[0].x:
		return dt_curve[0].y
	if thickness >= dt_curve[-1].x:
		return dt_curve[-1].y
	for i in range(1, dt_curve.size()):
		var point: Vector2 = dt_curve[i]
		if thickness <= point.x:
			var prev: Vector2 = dt_curve[i - 1]
			var t: float = (thickness - prev.x) / (point.x - prev.x)
			return lerp(prev.y, point.y, t)
	return dt_curve[-1].y
