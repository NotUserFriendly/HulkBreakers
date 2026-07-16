extends GutTest

## docs/10 "material colours are DATA": colour lives on MaterialEntry
## alongside dt, looked up through MaterialTable.color_for — never a
## hardcoded DT-threshold function.


func test_color_for_returns_the_entrys_authored_color() -> void:
	var table := MaterialTable.new()
	table.set_entry(&"steel", MaterialEntry.new(6.0, 30.0, Color("#8C949C")))
	assert_eq(table.color_for(&"steel"), Color("#8C949C"))


func test_color_for_an_unknown_material_falls_back_to_the_default_entrys_color() -> void:
	var table := MaterialTable.new()
	assert_eq(table.color_for(&"nonexistent"), MaterialEntry.new().color)


func test_default_table_yields_a_distinct_color_per_material() -> void:
	var table := MaterialTable.default_table()
	var seen: Array[Color] = []
	for material_id: StringName in table.entries.keys():
		var color: Color = table.color_for(material_id)
		assert_false(
			seen.has(color), "material %s must not share a color with another" % material_id
		)
		seen.append(color)
	assert_true(seen.size() >= 3, "the pool must yield at least 3 distinct colors (docs/10a)")


func test_default_table_covers_the_reference_humanoids_materials_and_cover() -> void:
	var table := MaterialTable.default_table()
	for material_id: StringName in [
		&"flesh",
		&"artificial_muscle",
		&"artificial_bone",
		&"sheet_steel",
		&"steel",
		&"ceramic",
		&"reactive",
		&"hull_plate",
	]:
		assert_true(table.entries.has(material_id), "missing reference material: %s" % material_id)


func test_no_default_entry_uses_the_unknown_material_fallback_color() -> void:
	var table := MaterialTable.default_table()
	var fallback: Color = MaterialEntry.new().color
	for material_id: StringName in table.entries.keys():
		assert_ne(
			table.color_for(material_id),
			fallback,
			(
				"material %s must have a real authored color, not the unknown-material default"
				% material_id
			)
		)
