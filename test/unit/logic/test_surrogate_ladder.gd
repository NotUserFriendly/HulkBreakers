extends GutTest

## docs/04 taskblock03 Pass A: the surrogate ladder is a DAG, not a line —
## BRAIN_ONLY -> SPINAL -> {PERIPHERAL, TORSIC} -> FULL. PERIPHERAL and
## TORSIC are mutually exclusive branches, never neighbouring rungs.


func _tier(id: StringName, ladder: Array[SurrogateTier]) -> SurrogateTier:
	for tier: SurrogateTier in ladder:
		if tier.id == id:
			return tier
	fail_test("no tier %s in ladder" % id)
	return null


func test_default_ladder_has_the_expected_ids() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var ids: Array[StringName] = []
	for tier: SurrogateTier in ladder:
		ids.append(tier.id)
	assert_eq(ids, [&"FULL", &"PERIPHERAL", &"TORSIC", &"SPINAL", &"BRAIN_ONLY"])


func test_peripheral_and_torsic_are_mutually_exclusive_branches() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var peripheral_reach: Array[StringName] = SurrogateLadder.derive_attaches_to(
		_tier(&"PERIPHERAL", ladder), ladder
	)
	var torsic_reach: Array[StringName] = SurrogateLadder.derive_attaches_to(
		_tier(&"TORSIC", ladder), ladder
	)

	assert_does_not_have(
		peripheral_reach, &"SURROGATE_TORSIC", "a PERIPHERAL surrogate must not fit a TORSIC cavity"
	)
	assert_does_not_have(
		torsic_reach, &"SURROGATE_PERIPHERAL", "a TORSIC surrogate must not fit a PERIPHERAL cavity"
	)


func test_both_branches_fit_the_full_cavity() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var peripheral_reach: Array[StringName] = SurrogateLadder.derive_attaches_to(
		_tier(&"PERIPHERAL", ladder), ladder
	)
	var torsic_reach: Array[StringName] = SurrogateLadder.derive_attaches_to(
		_tier(&"TORSIC", ladder), ladder
	)

	assert_has(peripheral_reach, &"SURROGATE_FULL")
	assert_has(torsic_reach, &"SURROGATE_FULL")


func test_spinal_docks_in_either_branch_and_full() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var spinal_reach: Array[StringName] = SurrogateLadder.derive_attaches_to(
		_tier(&"SPINAL", ladder), ladder
	)

	assert_has(spinal_reach, &"SURROGATE_SPINAL")
	assert_has(spinal_reach, &"SURROGATE_PERIPHERAL")
	assert_has(spinal_reach, &"SURROGATE_TORSIC")
	assert_has(spinal_reach, &"SURROGATE_FULL")


func test_brain_only_reaches_every_socket_type() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var reach: Array[StringName] = SurrogateLadder.derive_attaches_to(
		_tier(&"BRAIN_ONLY", ladder), ladder
	)

	assert_eq(reach.size(), 5, "the smallest surrogate fits every cavity there is")


func test_full_only_fits_its_own_cavity() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var reach: Array[StringName] = SurrogateLadder.derive_attaches_to(
		_tier(&"FULL", ladder), ladder
	)

	assert_eq(reach, [&"SURROGATE_FULL"])


func test_demote_from_spinal_and_below_is_unambiguous() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()

	assert_eq(SurrogateLadder.demote(_tier(&"PERIPHERAL", ladder), ladder).id, &"SPINAL")
	assert_eq(SurrogateLadder.demote(_tier(&"TORSIC", ladder), ladder).id, &"SPINAL")
	assert_eq(SurrogateLadder.demote(_tier(&"SPINAL", ladder), ladder).id, &"BRAIN_ONLY")


func test_demote_holds_at_the_bottom_a_bare_matrix_is_the_floor() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var bottom: SurrogateTier = _tier(&"BRAIN_ONLY", ladder)

	assert_eq(SurrogateLadder.demote(bottom, ladder), bottom)


## docs/04 taskblock03 Pass A2: demoting FULL is genuinely ambiguous (both
## PERIPHERAL and TORSIC promote there) — deliberately NOT resolved by an
## invented rule. This only pins down that the flagged placeholder is
## deterministic (same input, same output) and pushes a warning, not that
## the specific branch it picks is "correct" design.
func test_demote_from_full_is_deterministic_and_flags_the_ambiguity() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	var full: SurrogateTier = _tier(&"FULL", ladder)

	var first: SurrogateTier = SurrogateLadder.demote(full, ladder)
	var second: SurrogateTier = SurrogateLadder.demote(full, ladder)

	assert_eq(first, second, "the placeholder tie-break must be deterministic")
	assert_true(
		first.id == &"PERIPHERAL" or first.id == &"TORSIC",
		"must land on one of the two real branches, never invent a third"
	)


func test_a_ladder_with_an_inserted_branch_needs_no_code_change() -> void:
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	# A new tier grafted between SPINAL and PERIPHERAL, purely as data —
	# proving a new branch slots in without touching derive_attaches_to's
	# or demote()'s own logic.
	var spinal: SurrogateTier = _tier(&"SPINAL", ladder)
	var peripheral: SurrogateTier = _tier(&"PERIPHERAL", ladder)
	spinal.promotes_to.erase(&"PERIPHERAL")
	spinal.promotes_to.append(&"PARTIAL_LIMB")
	peripheral.promotes_to = [&"FULL"]
	ladder.append(
		SurrogateTier.new(
			&"PARTIAL_LIMB", "One arm, badly", [&"PERIPHERAL"], &"SURROGATE_PARTIAL_LIMB", []
		)
	)

	var reach: Array[StringName] = SurrogateLadder.derive_attaches_to(spinal, ladder)
	assert_has(reach, &"SURROGATE_PARTIAL_LIMB")
	assert_has(reach, &"SURROGATE_PERIPHERAL")

	assert_eq(SurrogateLadder.demote(peripheral, ladder).id, &"PARTIAL_LIMB")
