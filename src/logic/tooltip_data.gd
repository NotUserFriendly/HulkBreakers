class_name TooltipData
extends RefCounted

## taskblock-07 Pass F1: "the tooltip you get hovering a part in the
## inventory becomes THE detail mechanism." One shape, for every hoverable
## surface (parts, action bar boxes, tiles, units, field objects, queue
## entries, AP/MP pips) — TooltipBuilder is the "whatever provides detail
## implements this" the taskblock names; GDScript has no real interface to
## enforce polymorphism across such unrelated types (a Part Resource, a
## tile's plain Dictionary, an ActionDef), so one builder module with one
## function per hoverable kind, uniformly returning TooltipData, is what
## actually delivers "everything hoverable provides it" here — not a
## method scattered across otherwise-unrelated data classes.
##
## `rows`: Array[Dictionary] of {label: String, value: String, changed:
## bool} — `changed` is pre-computed by the builder (docs/08's own
## StatValue.changed() shape, generalized to any "this differs from its
## own baseline" row, not only a StatResolver-resolved stat), never
## re-derived by the renderer.

var title: String
var rows: Array[Dictionary]
var footer: String


func _init(p_title: String = "", p_rows: Array[Dictionary] = [], p_footer: String = "") -> void:
	title = p_title
	rows = p_rows.duplicate()
	footer = p_footer


func add_row(label: String, value: String, changed: bool = false) -> void:
	rows.append({"label": label, "value": value, "changed": changed})
