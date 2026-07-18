class_name ResourceEditorColumns
extends RefCounted

## taskblock-11 Pass C: the table's own column set per definition type —
## hand-declared, not full reflection over `get_property_list()`. Every
## resource type's exported fields split cleanly into "the flat scalars
## worth a column" and "everything else" (nested arrays, runtime-only
## fields, geometry); a generic reflection walk would surface all of it
## indiscriminately and this taskblock's own C rule ("scalar, however
## nested, is editable; geometry stays view-only") already says WHICH
## fields matter, not "however many a script happens to export." A new
## column is one more row here, same posture as `DataValidator`'s own
## per-type checks — "if a test needs a concrete list, the test authors
## it as a fixture" applies just as well to this list.
##
## `id` is deliberately NEVER editable, on every type — editing it would
## silently rename what file a save writes to (`DataLibrary.save` keys
## the `.tres` filename off `resource.id`), a file-identity operation
## this tool was never asked to support, not a value tweak.

const ID_COLUMN := &"id"


## Ordered column names for `type_key`'s own table — column 0 is always
## `id`.
static func columns_for(type_key: StringName) -> Array[StringName]:
	match type_key:
		DataLibrary.TYPE_PARTS:
			return [
				&"id",
				&"display_name",
				&"hp",
				&"mass",
				&"material",
				&"failure_mode",
				&"joint_hp",
				&"bonus_pen",
				&"damage",
				&"ap_cost",
				&"render_primitive",
			]
		DataLibrary.TYPE_AMMO:
			return [
				&"id",
				&"display_name",
				&"damage",
				&"bonus_pen",
				&"projectile_num",
				&"stack_type",
				&"stacks_inflicted",
				&"ideal_barrel_length",
			]
		DataLibrary.TYPE_MATERIALS:
			return [&"id", &"dt", &"deflect_threshold_deg", &"ricochet_bias"]
		_:
			return []


static func is_editable(column: StringName) -> bool:
	return column != ID_COLUMN


## True for int/float columns — C1's "a symbol showing current type
## (alpha/numeric)." Checked against a bare `Resource.new()` of the
## right type rather than hand-duplicating a type table here; the field
## itself already knows what it is.
static func is_numeric(type_key: StringName, column: StringName) -> bool:
	var sample: Resource = _sample(type_key)
	if sample == null:
		return false
	var value: Variant = sample.get(column)
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## taskblock-11 Pass C3: "offer a dropdown compiled from the other values
## in that column." A `StringName` field is an identifier/closed-ish
## value (`material`, `failure_mode`, `stack_type`, `render_primitive`)
## — exactly C3's own worked examples — where a dropdown steers away from
## typos; a plain `String` field (`display_name`) is freeform prose with
## no meaningful "other values" to suggest, and stays a normal free-text
## cell. `id` is excluded even though it's a StringName — never editable
## at all (see `is_editable`), so it never gets a dropdown either.
static func is_dropdown(type_key: StringName, column: StringName) -> bool:
	if column == ID_COLUMN:
		return false
	var sample: Resource = _sample(type_key)
	if sample == null:
		return false
	return typeof(sample.get(column)) == TYPE_STRING_NAME


## The closed vocabulary a column is backed by, if any (taskblock-11 C3:
## "for fields backed by a real vocabulary... pull from DataLibrary, not
## just the column"). Empty means "no closed vocabulary" — the caller
## falls back to whatever distinct values already exist in that column.
static func vocabulary_for(type_key: StringName, column: StringName) -> Array[StringName]:
	if type_key == DataLibrary.TYPE_PARTS and column == &"material":
		var ids: Array[StringName] = []
		for id: StringName in DataLibrary.resources_of_type(DataLibrary.TYPE_MATERIALS):
			ids.append(id)
		return ids
	if type_key == DataLibrary.TYPE_PARTS and column == &"failure_mode":
		return DataValidator.FAILURE_MODES
	if type_key == DataLibrary.TYPE_PARTS and column == &"render_primitive":
		return DataValidator.RENDER_PRIMITIVES
	if type_key == DataLibrary.TYPE_AMMO and column == &"stack_type":
		return DataValidator.STACK_TYPES
	return []


static func _sample(type_key: StringName) -> Resource:
	match type_key:
		DataLibrary.TYPE_PARTS:
			return Part.new()
		DataLibrary.TYPE_AMMO:
			return AmmoDef.new()
		DataLibrary.TYPE_MATERIALS:
			return MaterialEntry.new()
		_:
			return null
