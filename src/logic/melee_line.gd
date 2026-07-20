class_name MeleeLine
extends RefCounted

## taskblock-25 Pass C (docs/PLAN.md "Phase M — Melee"): a slash's own
## payload shape — "a line (horizontal/45°/vertical) — hits everything
## along it; length = weapon's slash_length... the slash is N adjacent
## point-resolutions along a line." `Region.rect`'s own axes are (lateral
## offset, real world height) since taskblock-23, so a `&"vertical"` line
## spreads along the SAME real-height axis every other 3D-aware system
## already reads — "a vertical slash uses the 3D plane to spread up/down a
## body" falls out of that axis choice for free, no special code.

## A flagged, tunable placeholder (docs/PLAN.md's own posture on unspecified
## numbers) — how far apart consecutive sample points sit along the line,
## never a design decision.
const SAMPLE_SPACING := 0.25


## `length` adjacent points along `orientation`'s own axis, centered on
## `aim_point`. `orientation`: `&"horizontal"` (lateral), `&"vertical"`
## (real height), `&"diagonal"` (45°, both axes) — an open StringName
## (CLAUDE.md: content, not an engine state), so a future orientation is
## one more `match` arm. Falls back to `&"horizontal"` for anything else,
## never crashes or silently drops the swing. `length <= 0.0` returns just
## `aim_point` itself — a swing with no authored `slash_length` is a
## single point, same as a stab.
static func sample(aim_point: Vector2, length: float, orientation: StringName) -> Array[Vector2]:
	if length <= 0.0:
		return [aim_point]
	var axis: Vector2 = _axis_for(orientation)
	var count: int = maxi(1, int(round(length / SAMPLE_SPACING))) + 1
	var half: float = length * 0.5
	var points: Array[Vector2] = []
	for i in range(count):
		var t: float = (float(i) / float(count - 1)) if count > 1 else 0.5
		var offset: float = lerp(-half, half, t)
		points.append(aim_point + axis * offset)
	return points


static func _axis_for(orientation: StringName) -> Vector2:
	match orientation:
		&"vertical":
			return Vector2(0.0, 1.0)
		&"diagonal":
			return Vector2(1.0, 1.0).normalized()
		_:
			return Vector2(1.0, 0.0)
