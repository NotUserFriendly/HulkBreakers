extends GutTest

## taskblock-55 Pass E: **the preview takes a seed and rolls the declarations**, which makes it
## the determinism test as well as the authoring tool.
##
## Reloading with the same seed reproduces a section exactly; reloading with a different one
## produces a different example of the same section. A drift in the roll order then stops being
## something only a test could catch and becomes something the author sees.
##
## The named demo sections in `data/sections/` are the fixtures, deliberately — they are what an
## author actually opens, so a rule that holds for a hand-built fixture and not for shipped
## content would be a rule nobody could rely on.


func _section(file_name: String) -> SectionFile:
	var section := load("res://data/sections/%s.tres" % file_name) as SectionFile
	assert_not_null(section, "the authored section '%s' is on disk" % file_name)
	return section


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Every field item on a previewed board, as `"part_id@cell"`, sorted — the comparable shape of
## "what did this roll actually produce".
func _fingerprint(grid: Grid) -> Array[String]:
	var found: Array[String] = []
	for cell: Vector2i in grid.field_items:
		for item: Variant in grid.field_items[cell]:
			found.append("%s@%s" % [item.id, cell])
	found.sort()
	return found


# --- determinism -----------------------------------------------------------------------------


## **The same seed previews identically twice.** The load-bearing one: without it the seed means
## nothing and every other assertion here is measuring noise.
func test_the_same_seed_previews_identically_twice() -> void:
	var section: SectionFile = _section("pump_room")
	if section == null:
		return
	var once: Dictionary = SectionSerializer.to_grid(section, _rng(4242))
	var twice: Dictionary = SectionSerializer.to_grid(section, _rng(4242))
	assert_eq(once.get("error", ""), "", "it builds")
	assert_eq(twice.get("error", ""), "", "both times")

	var first: Array[String] = _fingerprint(once["grid"])
	var second: Array[String] = _fingerprint(twice["grid"])
	gut.p("seed 4242 -> %s" % str(first))
	assert_eq(first, second, "same seed, same example, always")


## **Different seeds differ.** Without this the test above would also pass against a roll that had
## quietly stopped rolling — an empty board is identical to itself too.
func test_different_seeds_produce_different_examples() -> void:
	var section: SectionFile = _section("pump_room")
	if section == null:
		return
	# Swept rather than compared once: any two individual seeds can legitimately agree, and a
	# single unlucky pair would make this test flap.
	var seen: Dictionary = {}
	for seed_value: int in range(20):
		seen[str(_fingerprint(SectionSerializer.to_grid(section, _rng(seed_value))["grid"]))] = true
	gut.p("20 seeds produced %d distinct examples" % seen.size())
	assert_gt(seen.size(), 1, "the seed genuinely selects between examples")


## **An unrolled preview is the authored skeleton alone.** The default stays what every caller
## predating this pass got, so a section opened without a seed shows what was authored rather than
## one arbitrary example of it.
func test_a_preview_with_no_seed_rolls_nothing() -> void:
	var section: SectionFile = _section("pump_room")
	if section == null:
		return
	var result: Dictionary = SectionSerializer.to_grid(section)
	assert_eq(
		_fingerprint(result["grid"]),
		[] as Array[String],
		"no generator, no roll -- the authored skeleton and nothing else"
	)


# --- a preview contains only what the declarations permit -------------------------------------


## **A preview contains only things the section's declarations permit**, and **the clutter cap
## holds.** `pump_room` offers four clutter cells against a cap of two, so a cap that did nothing
## would show up here as three or four.
func test_a_preview_holds_only_permitted_clutter_and_respects_the_cap() -> void:
	var section: SectionFile = _section("pump_room")
	if section == null:
		return
	var offered: Array[StringName] = []
	for spawn: SectionSpawn in section.spawns:
		if spawn.kind == SectionSpawn.KIND_CLUTTER and not offered.has(spawn.tag):
			offered.append(spawn.tag)

	# Swept across seeds, because a cap is only proven by the rolls that would have exceeded it.
	var most := 0
	for seed_value: int in range(40):
		var grid: Grid = SectionSerializer.to_grid(section, _rng(seed_value))["grid"]
		var count := 0
		for cell: Vector2i in grid.field_items:
			for item: Variant in grid.field_items[cell]:
				assert_true(offered.has(item.id), "%s was never offered by this section" % item.id)
				count += 1
		most = maxi(most, count)
	gut.p(
		(
			"across 40 seeds the fullest preview held %d clutter items (cap %d)"
			% [most, section.maximum_clutter]
		)
	)
	assert_lte(most, section.maximum_clutter, "never more than its cap")
	# **The cap must actually be reached**, or the assertion above is satisfied by a section that
	# produces nothing. A first draft of this fixture tagged its clutter `barrel`, which no part
	# answers to — every one was skipped, the fullest preview held one item against a cap of two,
	# and this test passed while proving nothing at all.
	assert_eq(
		most,
		section.maximum_clutter,
		"and some seed reaches it -- otherwise the cap is never the thing being tested"
	)


## **A banned clutter item never appears.** Banned here is `barrel_pallet`, which `pump_room`
## genuinely **offers** — the shipped ban (`goo_barrel`) is never offered by any cell, and a ban on
## something nothing offers is satisfied by doing nothing at all. An earlier draft of this test
## banned a tag the fixture had stopped offering and passed while proving exactly that nothing.
func test_a_banned_clutter_item_never_appears() -> void:
	var section: SectionFile = _section("pump_room")
	if section == null:
		return
	var banned: SectionFile = section.duplicate()
	banned.spawns = section.spawns.duplicate()
	banned.banned_clutter = [&"barrel_pallet"]
	banned.maximum_clutter = -1

	var barrels := 0
	var others := 0
	for seed_value: int in range(40):
		for entry: String in _fingerprint(
			SectionSerializer.to_grid(banned, _rng(seed_value))["grid"]
		):
			if entry.begins_with("barrel_pallet@"):
				barrels += 1
			else:
				others += 1
	gut.p("40 seeds with 'barrel_pallet' banned: %d pallets, %d other items" % [barrels, others])
	assert_eq(barrels, 0, "a banned tag never lands")
	assert_gt(others, 0, "and the ban did not simply switch clutter off")


## **Adding a ban does not shift every later cell's *draw*.** Every candidate draws even when it
## cannot land, so a seed keeps meaning the same thing as a section is edited; without that,
## banning one tag silently re-rolls the whole room.
##
## **The cap is measured separately, and deliberately, because it does couple cells.** Writing this
## test the obvious way — ban a tag, expect only that tag to vanish — failed: with `maximum_clutter`
## at 2, banning the pallet freed a cap slot and `metal_scraps` appeared that had previously been
## capped out. That is the cap behaving correctly as a **budget** rather than the draw order
## drifting, and the two are worth being able to tell apart. The cap is lifted here so this test
## measures the draw order alone.
func test_a_ban_does_not_disturb_the_draw_order_for_other_cells() -> void:
	var section: SectionFile = _section("pump_room")
	if section == null:
		return
	var uncapped: SectionFile = section.duplicate()
	uncapped.spawns = section.spawns.duplicate()
	uncapped.maximum_clutter = -1
	var banned: SectionFile = uncapped.duplicate()
	banned.spawns = section.spawns.duplicate()
	banned.banned_clutter = [&"barrel_pallet"]

	# **Seed 4242 specifically, because it is a seed that produces a pallet.** A seed that produced
	# none would show "nothing was removed and nothing moved", which is equally true of a ban that
	# does not work at all.
	var plain: Array[String] = _fingerprint(SectionSerializer.to_grid(uncapped, _rng(4242))["grid"])
	var after: Array[String] = _fingerprint(SectionSerializer.to_grid(banned, _rng(4242))["grid"])
	var survivors: Array[String] = plain.filter(
		func(entry: String) -> bool: return not entry.begins_with("barrel_pallet@")
	)
	gut.p("before ban %s\nafter ban  %s" % [str(plain), str(after)])
	assert_lt(survivors.size(), plain.size(), "sanity: this seed did produce a pallet to ban")
	assert_gt(survivors.size(), 0, "and something else besides, which must survive untouched")
	assert_eq(after, survivors, "the pallets vanish and nothing else moves")


# --- the garrison, and rooms ------------------------------------------------------------------


## **A garrison that can fail.** `pump_room` offers three spawner cells at 0.6 against a minimum
## of three, so most seeds produce none and some produce all three — never one or two.
func test_the_garrison_is_all_or_nothing_across_seeds() -> void:
	var section: SectionFile = _section("pump_room")
	if section == null:
		return
	var counts: Dictionary = {}
	for seed_value: int in range(60):
		var size: int = SectionRoller.roll(section, _rng(seed_value))["garrison"].size()
		counts[size] = int(counts.get(size, 0)) + 1
	gut.p("garrison sizes across 60 seeds: %s" % str(counts))
	for size: int in counts:
		assert_true(
			size == 0 or size >= section.minimum_garrison,
			"a garrison of %d is neither empty nor up to strength" % size
		)
	assert_true(counts.has(0), "the roll genuinely fails sometimes")


## **An assembled two-section map rolls both sections' declarations.** Loading an assembly must
## populate every section the same way a single preview does, or a stitched board would be
## systematically emptier than its parts.
func test_an_assembled_two_section_map_rolls_both_sections() -> void:
	var north: SectionFile = _section("grand_hold_north")
	var pump: SectionFile = _section("pump_room")
	if north == null or pump == null:
		return

	var rng: RandomNumberGenerator = _rng(31)
	var north_rolled: Array[MapPlacement] = SectionSerializer.rolled_placements(north, rng)
	var pump_rolled: Array[MapPlacement] = SectionSerializer.rolled_placements(pump, rng)
	gut.p("north rolled %d, pump rolled %d" % [north_rolled.size(), pump_rolled.size()])
	# `grand_hold_north` declares no spawns at all, so the assertion that matters is that the
	# section which DOES declare them still rolls after another section has drawn from the same
	# generator — a shared RNG advanced by the first must not starve the second.
	assert_eq(north_rolled.size(), 0, "a section declaring nothing rolls nothing")
	assert_gt(pump_rolled.size(), 0, "and the one declaring clutter still rolls it")


## **Two sections rolling from one generator is order-dependent and reproducible.** The same pair
## in the same order against the same seed produces the same board twice — which is what makes an
## assembled map reproducible rather than merely each section individually.
func test_an_assembly_reproduces_exactly_for_one_seed() -> void:
	var pump: SectionFile = _section("pump_room")
	var reactor: SectionFile = _section("reactor_walk")
	if pump == null or reactor == null:
		return

	var first: Array[String] = []
	var second: Array[String] = []
	for target: Array in [first, second]:
		var rng: RandomNumberGenerator = _rng(77)
		for section: SectionFile in [pump, reactor]:
			for placement: MapPlacement in SectionSerializer.rolled_placements(section, rng):
				target.append("%s@%s" % [placement.part_id, placement.cell])
	gut.p("assembly at seed 77 -> %s" % str(first))
	# **Non-empty first.** Two empty assemblies match each other perfectly, so without this the
	# test would pass against a roll that had stopped rolling — which is exactly what it did on
	# the first draft of these fixtures.
	assert_gt(first.size(), 0, "the assembly actually produced something to reproduce")
	assert_eq(first, second, "one seed, one assembled board, every time")


# --- the demo sections are what they claim to be ----------------------------------------------


## Every authored section round-trips and is well-formed. The vocabulary fixtures are held to the
## same bar taskblock-54's format fixtures already were.
func test_every_authored_section_is_well_formed() -> void:
	var entries: Array[Dictionary] = SectionCatalog.entries()
	assert_gt(entries.size(), 10, "the demo sections are on disk and catalogued")
	for entry: Dictionary in entries:
		var section := load(entry["path"]) as SectionFile
		assert_not_null(section, "%s loads" % entry["path"])
		if section == null:
			continue
		assert_eq(
			SectionSerializer.describe_problems(section),
			[] as Array[String],
			"%s is well-formed" % entry["name"]
		)


## **The demo pair that must refuse.** `hull_breach_lip` asserts as exterior the space `pump_room`
## asserts as interior, and the refusal names both — the vocabulary's own conflict, in shipped
## content rather than in a fixture.
func test_the_authored_interior_and_exterior_sections_refuse_each_other() -> void:
	var pump: SectionFile = _section("pump_room")
	var breach: SectionFile = _section("hull_breach_lip")
	if pump == null or breach == null:
		return
	var problems: Array[String] = ClaimResolver.describe_conflicts(
		pump, Vector2i.ZERO, breach, Vector2i.ZERO
	)
	gut.p("\n".join(problems))
	assert_gt(problems.size(), 0, "inside and outside cannot both be true")
	assert_true(problems[0].contains("Pump Room"), "and both are named")
	assert_true(problems[0].contains("Hull Breach Lip"))


## **The authored stacked pair stacks**, through an `up` edge, and the upper deck lands on the
## lower section's ceiling.
func test_the_authored_stacked_pair_stacks() -> void:
	var lower: SectionFile = _section("coolant_stack_lower")
	var upper: SectionFile = _section("coolant_stack_upper")
	if lower == null or upper == null:
		return

	var verdict: Dictionary = SectionSerializer.can_join(lower, SectionEdge.SIDE_UP, upper)
	assert_true(verdict.ok, "they stack: %s" % verdict.reason)
	var result: Dictionary = SectionSerializer.stitch(lower, SectionEdge.SIDE_UP, upper)
	assert_eq(result.get("error", ""), "", "and the stacked board builds")
	var grid: Grid = result.get("grid")
	if grid == null:
		return
	var heights: Array[float] = []
	for surface: Surface in grid.surfaces_at(Vector2i(1, 1)):
		heights.append(surface.height)
	heights.sort()
	gut.p("the shared cell holds decks at %s" % str(heights))
	assert_eq(heights.size(), 2, "one footprint, two decks")
	assert_gt(heights[1], heights[0], "and the upper one is above the lower")


## **The authored room-in-two-sections rolls one encounter.** `grand_hold_south` declares
## `is_room = false`, so crossing the seam inside the hold triggers nothing.
func test_the_authored_grand_hold_rolls_one_encounter() -> void:
	var north: SectionFile = _section("grand_hold_north")
	var south: SectionFile = _section("grand_hold_south")
	if north == null or south == null:
		return
	var rooms: Array[Dictionary] = SectionRoller.roll_encounters([north, south], _rng(5))
	gut.p("rooms: %s" % str(rooms))
	assert_eq(rooms.size(), 1, "one hold, one encounter, however many sections built it")
	assert_eq((rooms[0]["sections"] as Array[int]).size(), 2, "and it spans both halves")


## **The authored door pair resolves to the smaller opening**, by intersection rather than by any
## comparison. `blast_door_narrow` expanded its own entry claim, which is the invitation; the wide
## door's claim is larger, and what survives is the region both permit.
func test_the_authored_doors_resolve_to_the_shared_opening() -> void:
	var narrow: SectionFile = _section("blast_door_narrow")
	var wide: SectionFile = _section("blast_door_wide")
	if narrow == null or wide == null:
		return

	var narrow_entry: SectionClaim = narrow.claims[0]
	var wide_entry: SectionClaim = wide.claims[0]
	var shared: AABB = ClaimResolver.entry_intersection(
		narrow_entry, Vector2i.ZERO, wide_entry, Vector2i(3, 0)
	)
	gut.p(
		(
			"narrow %s\nwide %s\nshared %s"
			% [narrow_entry.aabb(), wide_entry.aabb(Vector3(3, 0, 0)), shared]
		)
	)
	assert_true(shared.has_volume(), "the two doors meet")
	assert_almost_eq(
		shared.size.y,
		minf(narrow_entry.box.size.y, wide_entry.box.size.y),
		0.0001,
		"the shared opening is the smaller one's height -- geometry, not a ranking"
	)
