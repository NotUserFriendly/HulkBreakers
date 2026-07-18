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


## The docs/03 reference table (DT values) plus docs/10's reference colour
## table (deflect_threshold_deg isn't specified per material in either, so
## every entry uses MaterialEntry's documented 30-degree default until a
## designer tunes otherwise). Colours are mostly neutral on purpose — they
## leave the blue/red team overlay maximum room to read — and broadly rise
## in value with DT, so armor tier is a secondary at-a-glance cue.
##
## taskblock-09 E: every entry here stays on its flat `dt` — none of these
## carry a `dt_curve` yet. The taskblock's own steel/ceramic numbers are an
## illustration of the FORMAT, not authored balance data; giving these
## real curves means picking real thickness breakpoints per material, an
## actual design pass this taskblock doesn't hand down. `dt_at()` and the
## thickness pipeline are proven by test_material_entry.gd's own
## dedicated fixtures instead — migrating this table is a later, explicit
## ask.
static func default_table() -> MaterialTable:
	var table := MaterialTable.new()
	table.set_entry(&"flesh", MaterialEntry.new(0.0, 30.0, Color("#C98A7A")))
	table.set_entry(&"artificial_muscle", MaterialEntry.new(1.0, 30.0, Color("#7A3B33")))
	table.set_entry(&"artificial_bone", MaterialEntry.new(2.0, 30.0, Color("#D8CFB4")))
	table.set_entry(&"sheet_steel", MaterialEntry.new(3.0, 30.0, Color("#6E7276")))
	table.set_entry(&"steel", MaterialEntry.new(6.0, 30.0, Color("#8C949C")))
	table.set_entry(&"ceramic", MaterialEntry.new(9.0, 30.0, Color("#C6C9C2")))
	table.set_entry(&"reactive", MaterialEntry.new(12.0, 30.0, Color("#C9A227")))
	# Cover as a material row (docs/10), not a renderer special-case. DT is a
	# flagged placeholder — docs/10 pins the colour, not a hardness — ask
	# before tuning.
	table.set_entry(&"hull_plate", MaterialEntry.new(3.0, 30.0, Color("#6B4A2F")))
	return table
