extends GutTest


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func test_id_is_the_first_column_for_every_type() -> void:
	for type_key: StringName in [
		DataLibrary.TYPE_PARTS, DataLibrary.TYPE_AMMO, DataLibrary.TYPE_MATERIALS
	]:
		assert_eq(ResourceEditorColumns.columns_for(type_key)[0], &"id")


## "id is deliberately never editable" — a save keys the filename off it.
func test_id_is_never_editable() -> void:
	assert_false(ResourceEditorColumns.is_editable(&"id"))


func test_every_other_declared_column_is_editable() -> void:
	for column: StringName in ResourceEditorColumns.columns_for(DataLibrary.TYPE_PARTS):
		if column == &"id":
			continue
		assert_true(ResourceEditorColumns.is_editable(column), "%s must be editable" % column)


func test_is_numeric_matches_the_fields_own_type() -> void:
	assert_true(ResourceEditorColumns.is_numeric(DataLibrary.TYPE_PARTS, &"hp"))
	assert_true(ResourceEditorColumns.is_numeric(DataLibrary.TYPE_PARTS, &"mass"))
	assert_false(ResourceEditorColumns.is_numeric(DataLibrary.TYPE_PARTS, &"material"))
	assert_false(ResourceEditorColumns.is_numeric(DataLibrary.TYPE_PARTS, &"id"))


## C3: "for fields backed by a real vocabulary (materials, socket types),
## pull from DataLibrary."
func test_material_vocabulary_pulls_from_data_library() -> void:
	var vocab: Array[StringName] = ResourceEditorColumns.vocabulary_for(
		DataLibrary.TYPE_PARTS, &"material"
	)
	assert_true(vocab.has(&"steel"))
	assert_true(vocab.has(&"artificial_bone"))


func test_failure_mode_vocabulary_matches_the_validators_own_closed_list() -> void:
	assert_eq(
		ResourceEditorColumns.vocabulary_for(DataLibrary.TYPE_PARTS, &"failure_mode"),
		DataValidator.FAILURE_MODES
	)


func test_stack_type_vocabulary_matches_the_validators_own_closed_list() -> void:
	assert_eq(
		ResourceEditorColumns.vocabulary_for(DataLibrary.TYPE_AMMO, &"stack_type"),
		DataValidator.STACK_TYPES
	)


func test_a_column_with_no_closed_vocabulary_returns_empty() -> void:
	assert_eq(
		ResourceEditorColumns.vocabulary_for(DataLibrary.TYPE_PARTS, &"hp"), [] as Array[StringName]
	)
