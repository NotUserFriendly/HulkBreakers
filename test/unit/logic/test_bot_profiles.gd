extends GutTest

## taskblock-14 Pass A: named bot profiles + full-copy variants, spawned
## through the real BodyAssembler (no parallel path).

const TEST_USER_ROOT := "user://test_bot_profiles"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all(DataLibrary.BUILTIN_ROOT, TEST_USER_ROOT)


func after_each() -> void:
	DataLibrary.reset()
	_remove_dir_recursive(TEST_USER_ROOT)


func _remove_dir_recursive(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	var dir: DirAccess = DirAccess.open(absolute)
	if dir == null:
		return
	var presets_dir: DirAccess = DirAccess.open(absolute + "/presets")
	if presets_dir != null:
		presets_dir.list_dir_begin()
		var file_name: String = presets_dir.get_next()
		while file_name != "":
			if not presets_dir.current_is_dir():
				presets_dir.remove(file_name)
			file_name = presets_dir.get_next()
		presets_dir.list_dir_end()
		DirAccess.remove_absolute(absolute + "/presets")
	DirAccess.remove_absolute(absolute)


func _ids_of(unit: Unit) -> Array[StringName]:
	var ids: Array[StringName] = []
	for part: Part in unit.shell.all_parts():
		ids.append(part.id)
	return ids


## "a profile round-trips (.tres -> load -> assemble -> structurally
## identical)."
func test_a_profile_round_trips_through_datalibrary_save_and_load() -> void:
	var preset := BotPreset.new(
		"test_profile", ShellTemplates.DEFAULT_ID, DeepStrike.default_loadout()
	)
	var original: Unit = DeepStrike.assemble_from_preset(preset, Matrix.new(), Vector2i.ZERO)

	assert_eq(DataLibrary.save(DataLibrary.TYPE_PRESETS, preset), [] as Array[ValidationError])
	DataLibrary.reset()
	DataLibrary.load_all(DataLibrary.BUILTIN_ROOT, TEST_USER_ROOT)
	var loaded: BotPreset = DataLibrary.get_preset(&"test_profile")
	assert_not_null(loaded)
	var rebuilt: Unit = DeepStrike.assemble_from_preset(loaded, Matrix.new(), Vector2i.ZERO)

	assert_eq(_ids_of(rebuilt), _ids_of(original))


## "a variant is a full standalone preset sharing only profile_family
## with its base."
func test_a_variant_is_a_full_standalone_preset_sharing_only_its_family() -> void:
	var base := BotPreset.new(
		"laborer", ShellTemplates.DEFAULT_ID, DeepStrike.default_loadout(), &"IDLE", &"laborer", ""
	)
	var variant := BotPreset.new(
		"laborer_battery_mods",
		ShellTemplates.DEFAULT_ID,
		DeepStrike.default_loadout(),
		&"IDLE",
		&"laborer",
		"Battery Mods"
	)

	assert_eq(base.profile_family, variant.profile_family)
	assert_ne(base.preset_name, variant.preset_name)
	assert_eq(base.variant_label, "")
	assert_eq(variant.variant_label, "Battery Mods")
	# Not the same object, not a reference into the base at all.
	assert_ne(base, variant)
	assert_ne(base.loadout, variant.loadout)


## "editing the base does not propagate to variants (they're copies)."
func test_editing_the_base_leaves_the_variant_unchanged() -> void:
	var base := BotPreset.new("laborer", ShellTemplates.DEFAULT_ID, DeepStrike.default_loadout())
	var variant: BotPreset = base.duplicate(true)
	variant.preset_name = "laborer_battery_mods"
	variant.variant_label = "Battery Mods"

	base.loadout.entries[&"GRIP_L"] = &"rifle"

	assert_eq(
		variant.loadout.entries[&"GRIP_L"], &"pistol", "the variant's own copy must be untouched"
	)


## "spawning a profile builds through BodyAssembler" — same posture as
## test_builder_controller.gd's own assemble tests: a real, living Unit
## with a real hosted matrix, not a stand-in.
func test_spawning_a_profile_builds_through_body_assembler() -> void:
	var preset := BotPreset.new(
		"test_profile", ShellTemplates.DEFAULT_ID, DeepStrike.default_loadout()
	)
	var matrix := Matrix.new()
	matrix.id = &"test_matrix"

	var unit: Unit = DeepStrike.assemble_from_preset(preset, matrix, Vector2i(2, 3), 1)

	assert_not_null(unit)
	assert_eq(unit.cell, Vector2i(2, 3))
	assert_eq(unit.squad_id, 1)
	assert_not_null(unit.shell.root.hosted_matrix)
	assert_eq(DeepStrike.validate_assembly(unit), [] as Array[String])


## An unresolvable template_id is refused, not crashed — the runtime
## mirror of DataValidator's own authoring-time check.
func test_an_unknown_template_id_returns_null_not_a_crash() -> void:
	var preset := BotPreset.new("broken", &"not_a_real_template")

	var unit: Unit = DeepStrike.assemble_from_preset(preset, Matrix.new(), Vector2i.ZERO)

	assert_null(unit)


## "the reference profiles load and assemble" — the real, shipped
## a_brand_laborer base + Battery Mods variant.
func test_the_reference_profiles_load_and_assemble() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()

	var base: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	var variant: BotPreset = DataLibrary.get_preset(&"a_brand_laborer_battery_mods")
	assert_not_null(base)
	assert_not_null(variant)
	assert_eq(base.profile_family, &"a_brand_laborer")
	assert_eq(variant.profile_family, &"a_brand_laborer")
	assert_eq(variant.variant_label, "Battery Mods")

	var base_unit: Unit = DeepStrike.assemble_from_preset(base, Matrix.new(), Vector2i.ZERO)
	var variant_unit: Unit = DeepStrike.assemble_from_preset(variant, Matrix.new(), Vector2i.ZERO)
	assert_not_null(base_unit)
	assert_not_null(variant_unit)
	assert_eq(DeepStrike.validate_assembly(base_unit), [] as Array[String])
	assert_eq(DeepStrike.validate_assembly(variant_unit), [] as Array[String])

	DataLibrary.reset()
