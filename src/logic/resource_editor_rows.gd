class_name ResourceEditorRows
extends RefCounted

## taskblock-11 Pass C: pure sort/filter over a `DataLibrary.resources_of_type`
## Dictionary — headless-testable, the same "the panel only draws what
## this hands it" split `InventoryRows`/`WeaponRows` already establish.
## The Tree/table itself never sorts or filters on its own.


## `filters`: column -> substring (case-insensitive), empty/missing means
## no filter on that column; every non-empty filter must match (AND
## across columns). `sort_column == &""` leaves the Dictionary's own
## (already-deterministic, taskblock-10: filename-sorted) load order.
## C1: "sort is stable and deterministic" — ties keep their PRE-sort
## relative order regardless of the underlying `sort_custom` engine
## implementation's own stability, by sorting (value, original index)
## pairs and breaking ties on index.
static func build(
	resources: Dictionary,
	filters: Dictionary = {},
	sort_column: StringName = &"",
	sort_ascending: bool = true
) -> Array[Resource]:
	var rows: Array[Resource] = []
	for id: StringName in resources:
		rows.append(resources[id])
	rows = _filtered(rows, filters)
	if sort_column != &"":
		rows = _sorted(rows, sort_column, sort_ascending)
	return rows


static func _filtered(rows: Array[Resource], filters: Dictionary) -> Array[Resource]:
	if filters.is_empty():
		return rows
	var out: Array[Resource] = []
	for row: Resource in rows:
		if _matches(row, filters):
			out.append(row)
	return out


static func _matches(row: Resource, filters: Dictionary) -> bool:
	for column: StringName in filters:
		var needle: String = String(filters[column]).to_lower().strip_edges()
		if needle == "":
			continue
		var haystack: String = String(row.get(column)).to_lower()
		if not haystack.contains(needle):
			return false
	return true


static func _sorted(rows: Array[Resource], column: StringName, ascending: bool) -> Array[Resource]:
	var indexed: Array = []
	for i in range(rows.size()):
		indexed.append([rows[i], i])
	indexed.sort_custom(
		func(a: Array, b: Array) -> bool:
			var a_value: Variant = (a[0] as Resource).get(column)
			var b_value: Variant = (b[0] as Resource).get(column)
			if a_value == b_value:
				return a[1] < b[1]
			if ascending:
				return a_value < b_value
			return a_value > b_value
	)
	var out: Array[Resource] = []
	for pair: Array in indexed:
		out.append(pair[0])
	return out


## Every distinct, non-empty value already present in `column` across
## `rows` — C3's fallback dropdown source for a column with no closed
## vocabulary, sorted for a stable, predictable menu.
static func distinct_values(rows: Array[Resource], column: StringName) -> Array[String]:
	var seen: Dictionary = {}
	for row: Resource in rows:
		var text: String = String(row.get(column))
		if text != "":
			seen[text] = true
	var values: Array[String] = []
	for value: String in seen:
		values.append(value)
	values.sort()
	return values
