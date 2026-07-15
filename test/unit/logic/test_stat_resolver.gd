extends GutTest


func _make_part(stat_mods: Dictionary, label: String = "") -> Part:
	var p := Part.new()
	p.display_name = label
	p.stat_mods = stat_mods
	return p


func test_resolve_combines_part_perk_and_ammo_sources_and_names_all_three() -> void:
	var part := _make_part({&"damage": 5.0}, "Chaingun")
	var perk_source := ModSource.new("Spin Up", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, 2.0)
	var ammo_source := ModSource.new(
		"Incendiary Rounds", Enums.ModSourceKind.AMMO, Enums.ModOp.ADD, 1.0
	)

	var context := ResolverContext.new()
	context.parts = [part]
	context.extra_sources = [perk_source, ammo_source]

	var result: StatValue = StatResolver.resolve(&"damage", context)

	assert_eq(result.base, 0.0)
	assert_eq(result.current, 8.0)  # 0 base + 5 (part) + 2 (perk) + 1 (ammo)
	assert_eq(result.sources.size(), 3)

	var kinds: Array[Enums.ModSourceKind] = []
	var names: Array[String] = []
	for source: ModSource in result.sources:
		kinds.append(source.source_kind)
		names.append(source.source_name)
	assert_has(kinds, Enums.ModSourceKind.PART)
	assert_has(kinds, Enums.ModSourceKind.PERK)
	assert_has(kinds, Enums.ModSourceKind.AMMO)
	assert_has(names, "Chaingun")
	assert_has(names, "Spin Up")
	assert_has(names, "Incendiary Rounds")


func test_resolve_is_pure_and_deterministic() -> void:
	var part := _make_part({&"recoil": 3.0})
	var context := ResolverContext.new()
	context.base = 10.0
	context.parts = [part]

	var a: StatValue = StatResolver.resolve(&"recoil", context)
	var b: StatValue = StatResolver.resolve(&"recoil", context)
	assert_eq(a.current, b.current)
	assert_eq(a.current, 13.0)


func test_multiply_op() -> void:
	var context := ResolverContext.new()
	context.base = 10.0
	context.extra_sources = [
		ModSource.new("Suppression", Enums.ModSourceKind.STATUS, Enums.ModOp.MULTIPLY, 1.5)
	]
	assert_almost_eq(StatResolver.resolve(&"scatter_radius", context).current, 15.0, 0.0001)


func test_override_op() -> void:
	var context := ResolverContext.new()
	context.base = 10.0
	context.extra_sources = [
		ModSource.new("Jammed", Enums.ModSourceKind.STATUS, Enums.ModOp.OVERRIDE, 0.0)
	]
	assert_eq(StatResolver.resolve(&"burst", context).current, 0.0)


func test_ops_apply_in_order() -> void:
	var context := ResolverContext.new()
	context.base = 10.0
	context.extra_sources = [
		ModSource.new("A", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, 5.0),  # 10 + 5 = 15
		ModSource.new("B", Enums.ModSourceKind.STATUS, Enums.ModOp.MULTIPLY, 2.0),  # 15 * 2 = 30
	]
	assert_almost_eq(StatResolver.resolve(&"whatever", context).current, 30.0, 0.0001)


func test_stat_value_changed_is_false_with_no_sources() -> void:
	var context := ResolverContext.new()
	context.base = 5.0
	assert_false(StatResolver.resolve(&"whatever", context).changed())


func test_stat_value_changed_is_false_when_sources_net_to_zero_change() -> void:
	var context := ResolverContext.new()
	context.base = 5.0
	context.extra_sources = [
		ModSource.new("A", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, 3.0),
		ModSource.new("B", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, -3.0),
	]
	assert_false(StatResolver.resolve(&"whatever", context).changed())


func test_gather_part_sources_ignores_parts_without_the_stat() -> void:
	var relevant := _make_part({&"damage": 4.0})
	var irrelevant := _make_part({&"mass": 1.0})
	var sources: Array[ModSource] = StatResolver.gather_part_sources(
		&"damage", [relevant, irrelevant]
	)
	assert_eq(sources.size(), 1)
	assert_eq(sources[0].delta, 4.0)


## Phase 2's hard rule (docs/08): "nothing outside the resolver computes a
## final stat." Literal grep test — no .gd file other than stat_resolver.gd
## (which legitimately reads it to build sources) and part.gd (which just
## declares the field) may reference Part.stat_mods.
func test_stat_mods_is_only_read_by_the_resolver() -> void:
	var allowed_files: Array[String] = ["stat_resolver.gd", "part.gd"]
	var offending: Array[String] = []
	_scan_dir("res://src", allowed_files, offending)
	assert_eq(
		offending, [] as Array[String], "stat_mods read outside the resolver: %s" % [offending]
	)


func _scan_dir(path: String, allowed_files: Array[String], offending: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full_path, allowed_files, offending)
		elif entry.ends_with(".gd") and not allowed_files.has(entry):
			var text: String = FileAccess.get_file_as_string(full_path)
			if text.contains("stat_mods"):
				offending.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
