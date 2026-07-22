class_name AimTarget
extends RefCounted

## tb32 Pass C: what the aim/dartboard UI is currently pointed at —
## either a live Unit (today's whole-body target, unchanged behavior) or
## a struck Part anchored to a cell (wall/cover/downed object/field item
## — `PartPicker`'s new HitKind.PART). `cell` is always populated so every
## existing `target.cell` read keeps working unchanged regardless of
## which kind this is; `unit`/`part` are the type-specific payload,
## exactly one of them ever non-null.

var unit: Unit = null
var part: Part = null
var cell: Vector2i


static func for_unit(u: Unit) -> AimTarget:
	var target := AimTarget.new()
	target.unit = u
	target.cell = u.cell
	return target


static func for_part(p: Part, at_cell: Vector2i) -> AimTarget:
	var target := AimTarget.new()
	target.part = p
	target.cell = at_cell
	return target
