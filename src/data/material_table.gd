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


## The docs/03 reference table (DT values only — deflect_threshold_deg is
## not specified per material there, so every entry uses MaterialEntry's
## documented 30-degree default until a designer tunes otherwise).
static func default_table() -> MaterialTable:
	var table := MaterialTable.new()
	table.set_entry(&"flesh", MaterialEntry.new(0.0))
	table.set_entry(&"artificial_muscle", MaterialEntry.new(1.0))
	table.set_entry(&"artificial_bone", MaterialEntry.new(2.0))
	table.set_entry(&"sheet_steel", MaterialEntry.new(3.0))
	table.set_entry(&"steel", MaterialEntry.new(6.0))
	table.set_entry(&"ceramic_composite", MaterialEntry.new(9.0))
	table.set_entry(&"reactive", MaterialEntry.new(12.0))
	return table
