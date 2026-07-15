extends GutTest

## docs/07: merchant_pool and hulk_pool are mostly exclusive with a
## deliberate small overlap.


func _ids(parts: Array[Part]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for part: Part in parts:
		ids.append(part.id)
	return ids


func _rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


func test_pools_are_mostly_exclusive() -> void:
	var merchant_ids: Array[StringName] = _ids(LootTable.merchant_only_pool())
	var hulk_ids: Array[StringName] = _ids(LootTable.hulk_only_pool())
	for id: StringName in merchant_ids:
		assert_false(hulk_ids.has(id), "%s must not appear in both exclusive pools" % id)


func test_overlap_designs_appear_in_both_full_pools() -> void:
	var overlap_ids: Array[StringName] = _ids(LootTable.overlap_pool())
	assert_true(overlap_ids.size() > 0, "there must be at least one deliberate overlap design")

	var merchant_ids: Array[StringName] = _ids(LootTable.merchant_pool())
	var hulk_ids: Array[StringName] = _ids(LootTable.hulk_pool())
	for id: StringName in overlap_ids:
		assert_true(merchant_ids.has(id), "%s must be sellable by a merchant too" % id)
		assert_true(hulk_ids.has(id), "%s must be findable on a hulk too" % id)


func test_the_overlap_stays_small_relative_to_each_pool() -> void:
	var overlap_size: int = LootTable.overlap_pool().size()
	assert_true(
		overlap_size < LootTable.merchant_only_pool().size(),
		"the overlap is a seasoning, not a merge"
	)
	assert_true(overlap_size < LootTable.hulk_only_pool().size())


func test_draw_from_merchant_tags_an_overlap_item_standard() -> void:
	var overlap_id: StringName = LootTable.overlap_pool()[0].id
	var rng := _rng(1)
	var item: Part
	for i in range(50):  # draw until the overlap item comes up
		item = LootTable.draw(LootTable.MERCHANT_SOURCE, rng)
		if item.id == overlap_id:
			break
	assert_eq(item.id, overlap_id)
	assert_eq(item.variant_tag, &"standard")


func test_draw_from_hulk_tags_an_overlap_item_original_pattern_or_prototype() -> void:
	var overlap_id: StringName = LootTable.overlap_pool()[0].id
	var rng := _rng(1)
	var item: Part
	for i in range(50):
		item = LootTable.draw(LootTable.HULK_SOURCE, rng)
		if item.id == overlap_id:
			break
	assert_eq(item.id, overlap_id)
	assert_true(item.variant_tag == &"original_pattern" or item.variant_tag == &"prototype")


func test_draw_leaves_non_overlap_items_untagged() -> void:
	var rng := _rng(2)
	var exclusive_id: StringName = LootTable.merchant_only_pool()[0].id
	var item: Part
	for i in range(50):
		item = LootTable.draw(LootTable.MERCHANT_SOURCE, rng)
		if item.id == exclusive_id:
			break
	assert_eq(item.id, exclusive_id)
	assert_eq(item.variant_tag, &"")


func test_draw_is_deterministic_from_the_same_seed() -> void:
	var a: Array[StringName] = []
	var rng_a := _rng(99)
	for i in range(10):
		a.append(LootTable.draw(LootTable.HULK_SOURCE, rng_a).id)

	var b: Array[StringName] = []
	var rng_b := _rng(99)
	for i in range(10):
		b.append(LootTable.draw(LootTable.HULK_SOURCE, rng_b).id)

	assert_eq(a, b)
