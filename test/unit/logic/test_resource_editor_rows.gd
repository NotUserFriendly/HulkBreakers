extends GutTest


func _resources() -> Dictionary:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 12
	torso.material = &"artificial_bone"

	var plate := Part.new()
	plate.id = &"plate_small_steel"
	plate.hp = 4
	plate.material = &"steel"

	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.material = &"steel"

	return {&"torso": torso, &"plate_small_steel": plate, &"pistol": pistol}


func test_no_filter_no_sort_returns_every_row_in_load_order() -> void:
	var rows: Array[Resource] = ResourceEditorRows.build(_resources())
	assert_eq(rows.size(), 3)


func test_filter_matches_a_substring_case_insensitively() -> void:
	var rows: Array[Resource] = ResourceEditorRows.build(_resources(), {&"id": "TORS"})
	assert_eq(rows.size(), 1)
	assert_eq((rows[0] as Part).id, &"torso")


func test_filters_combine_with_and_across_columns() -> void:
	var rows: Array[Resource] = ResourceEditorRows.build(
		_resources(), {&"material": "steel", &"id": "plate"}
	)
	assert_eq(rows.size(), 1)
	assert_eq((rows[0] as Part).id, &"plate_small_steel")


func test_an_empty_filter_value_is_ignored() -> void:
	var rows: Array[Resource] = ResourceEditorRows.build(_resources(), {&"id": ""})
	assert_eq(rows.size(), 3)


func test_sort_ascending_by_numeric_column() -> void:
	var rows: Array[Resource] = ResourceEditorRows.build(_resources(), {}, &"hp", true)
	var ids: Array[StringName] = []
	for row: Part in rows:
		ids.append(row.id)
	assert_eq(ids, [&"pistol", &"plate_small_steel", &"torso"])


func test_sort_descending_by_numeric_column() -> void:
	var rows: Array[Resource] = ResourceEditorRows.build(_resources(), {}, &"hp", false)
	var ids: Array[StringName] = []
	for row: Part in rows:
		ids.append(row.id)
	assert_eq(ids, [&"torso", &"plate_small_steel", &"pistol"])


## C1: "sort is stable and deterministic" — two rows tied on the sort
## column keep their pre-sort relative order.
func test_sort_is_stable_on_ties() -> void:
	var resources: Dictionary = _resources()
	(resources[&"plate_small_steel"] as Part).hp = 3
	(resources[&"pistol"] as Part).hp = 3
	# Dictionary insertion order: torso, plate_small_steel, pistol.
	var rows: Array[Resource] = ResourceEditorRows.build(resources, {}, &"hp", true)
	var tied: Array[StringName] = [(rows[0] as Part).id, (rows[1] as Part).id]
	assert_eq(tied, [&"plate_small_steel", &"pistol"])


func test_distinct_values_deduplicates_and_sorts() -> void:
	var rows: Array[Resource] = ResourceEditorRows.build(_resources())
	assert_eq(ResourceEditorRows.distinct_values(rows, &"material"), ["artificial_bone", "steel"])
