extends GutTest

## docs/04: "degradation is a ladder, not a health bar" — a Resource with a
## rank, not a hardcoded enum.


func test_default_ladder_is_ordered_full_to_brain_only() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var ids: Array[StringName] = []
	for tier: SurrogateTier in ladder:
		ids.append(tier.id)
	assert_eq(ids, [&"FULL", &"PERIPHERAL", &"TORSIC", &"SPINAL", &"BRAIN_ONLY"])

	for i in range(1, ladder.size()):
		assert_true(
			ladder[i].rank > ladder[i - 1].rank, "rank must strictly increase down the ladder"
		)


func test_demote_steps_exactly_one_rung() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var full: SurrogateTier = ladder[0]
	var demoted: SurrogateTier = SurrogateLadder.demote(full, ladder)
	assert_eq(demoted.id, &"PERIPHERAL")


func test_demote_holds_at_the_bottom_rung_a_bare_matrix_is_the_floor() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var bottom: SurrogateTier = ladder[ladder.size() - 1]
	var demoted: SurrogateTier = SurrogateLadder.demote(bottom, ladder)
	assert_eq(demoted, bottom)


func test_a_ladder_with_an_inserted_rung_needs_no_code_change() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	# Insert a new tier between TORSIC (rank 2) and SPINAL (rank 3) purely
	# as data — proving new tiers slot in without touching demote()'s logic.
	ladder.insert(3, SurrogateTier.new(&"PARTIAL_SPINAL", "Half the spine", 3))
	for i in range(4, ladder.size()):  # bump everything after the new rung, not the rung itself
		ladder[i].rank += 1

	var torsic: SurrogateTier = ladder[2]
	var demoted: SurrogateTier = SurrogateLadder.demote(torsic, ladder)
	assert_eq(demoted.id, &"PARTIAL_SPINAL")
