class_name MaterialTable
extends Resource

## docs/03: "the material table is data, not a code constant." A material
## -> MaterialEntry lookup, plus the ricochet retention curve's endpoints —
## also explicitly called out as table tunables, not constants in code.

@export var entries: Dictionary = {}  # StringName -> MaterialEntry
## Retention at bend 0 (a graze that barely turns the path) and at
## max_bend_deg (a full reversal) — the lerp endpoints, named for what they
## mean rather than which is numerically bigger.
@export var retain_at_zero_bend: float = 0.90
@export var retain_at_max_bend: float = 0.25
@export var max_bend_deg: float = 180.0


## Unknown materials default to DT 0 / 30-degree deflect threshold — bare,
## unarmored — rather than erroring; authoring an entry is opt-in.
func get_entry(material: StringName) -> MaterialEntry:
	if entries.has(material):
		return entries[material]
	return MaterialEntry.new()


func set_entry(material: StringName, entry: MaterialEntry) -> void:
	entries[material] = entry


## docs/10 "material colours are DATA": the one place anything (world mesh,
## checkpoint dump) reads a material's colour — never a hardcoded DT
## threshold. An empty material (bare, unarmored) reads as its own entry's
## default grey via get_entry(), same fallback as DT.
func color_for(material: StringName) -> Color:
	return get_entry(material).color

## The docs/03/docs/10 reference table (taskblock-09 E: flat `dt` only,
## no material carries a `dt_curve` yet — migrating that is a later,
## explicit ask) now lives in `res://data/materials/*.tres` (taskblock-10
## Pass C) — `DataLibrary.material_table()` is the read path; this file no
## longer constructs it. Regenerated once by `tools/migrate_data.gd`.
