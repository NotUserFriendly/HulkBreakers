extends GutTest

## taskblock-42 Pass C (BR27.09 cost #3): "the turn-start power recompute
## re-walks the same unchanged part graph 5-6 times."
##
## Confirmed by instrumenting `PartGraph.walk` before changing anything: exactly
## **five** full socket-tree walks per turn start — `recharge_batteries`,
## `has_power_system`, `max_ap_for` (three internally), `discharge_batteries`
## and `mp_per_ap`, each walking independently. The entry's estimate was right.
##
## The fix threads one pre-walked list through all of them. **Explicit threading
## rather than a per-turn cache, deliberately**: a cache would need invalidating
## on every structural change to the part tree, and a stale power reading is a
## silent wrong number rather than a crash. There is no state here to go stale.


func _unit(cell: Vector2i = Vector2i(1, 1)) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, 0)


## The values are the acceptance, not the walk count — a faster turn start that
## computed different numbers would be a regression, not an optimisation.
func test_threading_a_prewalked_list_gives_identical_power_numbers() -> void:
	var unit: Unit = _unit()
	var operable: Array[Part] = unit.shell.operable_parts()

	assert_almost_eq(
		PowerResolver.surplus(unit, operable), PowerResolver.surplus(unit), 0.0001, "surplus"
	)
	assert_eq(PowerResolver.max_ap_for(unit, operable), PowerResolver.max_ap_for(unit), "max_ap")
	assert_almost_eq(
		PowerResolver.reactor_power(unit.shell, operable),
		PowerResolver.reactor_power(unit.shell),
		0.0001
	)
	assert_almost_eq(
		PowerResolver.consumer_power(unit.shell, operable),
		PowerResolver.consumer_power(unit.shell),
		0.0001
	)
	assert_almost_eq(unit.mp_per_ap(operable), unit.mp_per_ap(), 0.0001, "mp_per_ap")


## `Shell.operable_from` must agree exactly with `operable_parts()` — it is the
## one thing that lets a single walk feed every consumer, so a divergence here
## would quietly change what every power number is computed over.
func test_operable_from_agrees_with_operable_parts() -> void:
	var unit: Unit = _unit()
	assert_eq(Shell.operable_from(unit.shell.all_parts()), unit.shell.operable_parts())


## The filter is real, not a pass-through: a destroyed part and a wound-disabled
## one must both drop out, which is what `operable_parts()` has always meant.
func test_operable_from_drops_destroyed_parts() -> void:
	var unit: Unit = _unit()
	var all_parts: Array[Part] = unit.shell.all_parts()
	var victim: Part = null
	for part: Part in all_parts:
		if part != unit.shell.root:
			victim = part
			break
	victim.hp = 0

	var operable: Array[Part] = Shell.operable_from(all_parts)
	assert_false(victim in operable, "a destroyed part is not operable")
	assert_eq(operable, unit.shell.operable_parts(), "and it still agrees with the real call")


## No state is cached, so a structural change between turns cannot be read
## stale — the walk is simply taken again. This is the acceptance "cache
## invalidates on any structural change", satisfied by there being no cache to
## invalidate.
func test_a_structural_change_between_turns_is_seen_immediately() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var a: Unit = _unit(Vector2i(1, 1))
	var b: Unit = _unit(Vector2i(5, 5))
	var state := CombatState.new(grid, [a, b])
	state.assign_all_to_human()
	var before: int = a.shell.operable_parts().size()

	for part: Part in a.shell.all_parts():
		if part != a.shell.root:
			part.hp = 0

	assert_lt(
		a.shell.operable_parts().size(),
		before,
		"the very next read reflects the destroyed parts — nothing was remembered"
	)
	# And the numbers turn start computes from that list follow it, rather than
	# reporting whatever the last turn happened to see.
	var operable: Array[Part] = a.shell.operable_parts()
	assert_eq(
		PowerResolver.max_ap_for(a, operable),
		PowerResolver.max_ap_for(a),
		"threaded and unthreaded agree on the CURRENT tree, not a remembered one"
	)
