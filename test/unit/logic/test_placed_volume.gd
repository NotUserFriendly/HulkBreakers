extends GutTest

## taskblock-58 Pass F: **a part authored at a size that is not its own, and the hp that follows.**
##
## *"HP scales by volume... this keeps a big wall meaningfully tougher than a small one without
## authoring a number per size."* Linear, on the supervisor's call — *"diminishing returns on more
## mass is the opposite of how armor works in real life."*


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## **The default wall is unchanged to the hitpoint**, which is what made it safe to turn volume
## scaling on at all. `hp_per_volume` was chosen to reproduce the authored number rather than to be
## a round figure.
func test_the_authored_wall_keeps_its_own_hp_at_its_own_size() -> void:
	var wall: Part = DataLibrary.get_part(&"wall")
	var natural: Vector3 = PlacedVolume.natural_size(wall)
	gut.p(
		(
			"  wall is %s = %.2f m3 at %.1f hp/m3"
			% [natural, PlacedVolume.cubic_volume(wall, Vector3.ZERO), wall.hp_per_volume]
		)
	)

	assert_gt(wall.hp_per_volume, 0.0, "the wall opted into volume-scaled hp")
	assert_eq(
		PlacedVolume.hp_for(wall, Vector3.ZERO),
		wall.hp,
		"an unsized wall must be exactly the wall the content authors"
	)


## **THE PASS'S OWN LINE**: a resized wall's hp is proportional to its volume.
func test_a_resized_walls_hp_is_proportional_to_its_volume() -> void:
	var wall: Part = DataLibrary.get_part(&"wall")
	var natural: Vector3 = PlacedVolume.natural_size(wall)

	var doubled: Vector3 = Vector3(natural.x * 2.0, natural.y, natural.z)
	var halved: Vector3 = Vector3(natural.x * 0.5, natural.y, natural.z)

	var base: int = PlacedVolume.hp_for(wall, Vector3.ZERO)
	gut.p(
		(
			"  %d hp at %s, %d at doubled, %d at halved"
			% [base, natural, PlacedVolume.hp_for(wall, doubled), PlacedVolume.hp_for(wall, halved)]
		)
	)

	assert_eq(PlacedVolume.hp_for(wall, doubled), base * 2, "twice the wall is twice the hp")
	assert_eq(PlacedVolume.hp_for(wall, halved), base / 2, "and half is half — linear, not curved")


## The taskblock's own example, end to end: a 3 x 3 x 0.5 wall is one part with one hp number.
func test_the_three_by_three_by_half_wall_is_one_part() -> void:
	var wall: Part = DataLibrary.get_part(&"wall")
	var size := Vector3(3.0, 3.0, 0.5)

	var boxes: Array[Box] = PlacedVolume.boxes_for(wall, size)
	var volume: float = PlacedVolume.cubic_volume(wall, size)
	gut.p(
		(
			"  3x3x0.5 -> %d box(es), %.2f m3, %d hp"
			% [boxes.size(), volume, PlacedVolume.hp_for(wall, size)]
		)
	)

	assert_eq(boxes.size(), wall.volume.size(), "resizing must not multiply the boxes")
	assert_almost_eq(volume, 4.5, 0.0001, "3 x 3 x 0.5")
	assert_eq(
		PlacedVolume.hp_for(wall, size),
		int(round(4.5 * wall.hp_per_volume)),
		"one part, one hp number, derived from the size the author gave it"
	)


## Scaling is about the box's own centre, so a resized wall stays where it was placed rather than
## drifting off its cell.
func test_resizing_scales_about_the_parts_own_extent() -> void:
	var wall: Part = DataLibrary.get_part(&"wall")
	var natural: Vector3 = PlacedVolume.natural_size(wall)
	var doubled: Array[Box] = PlacedVolume.boxes_for(wall, natural * 2.0)

	assert_eq(doubled.size(), wall.volume.size())
	for i in range(doubled.size()):
		assert_almost_eq(
			doubled[i].size.x, wall.volume[i].size.x * 2.0, 0.0001, "the box really doubled"
		)
		assert_almost_eq(
			doubled[i].center.y,
			wall.volume[i].center.y * 2.0,
			0.0001,
			"and its centre moved with it rather than staying put"
		)


## **Opt-in, and the default is off.** A part that authors no density keeps its hp at any size, so
## turning this on rebalanced nothing that had not asked for it.
func test_a_part_with_no_density_keeps_its_authored_hp_at_any_size() -> void:
	var plain := Part.new()
	plain.id = &"plain"
	plain.hp = 17
	plain.max_hp = 17
	plain.volume = [Box.new(Vector3.ZERO, Vector3.ONE)]

	assert_eq(plain.hp_per_volume, 0.0, "the default is off")
	assert_eq(PlacedVolume.hp_for(plain, Vector3.ZERO), 17)
	assert_eq(PlacedVolume.hp_for(plain, Vector3(4.0, 4.0, 4.0)), 17, "size changed nothing")


## An unsized placement is the part exactly as authored — the case every map written before this
## takes, and the reason `Vector3.ZERO` rather than `Vector3.ONE` means "its own".
func test_an_unsized_placement_is_the_part_untouched() -> void:
	var wall: Part = DataLibrary.get_part(&"wall")
	assert_same(
		PlacedVolume.boxes_for(wall, Vector3.ZERO),
		wall.volume,
		"an unsized part must hand back its own boxes, not copies of them"
	)


## A part thin enough to round to nothing is still something you have to destroy.
func test_hp_floors_at_one_rather_than_arriving_broken() -> void:
	var wall: Part = DataLibrary.get_part(&"wall")
	assert_eq(PlacedVolume.hp_for(wall, Vector3(0.001, 0.001, 0.001)), 1)


## Several boxes around a gap do not get credit for the gap — the volume is the boxes, not the
## bounding extent. A shield with an eyehole is `docs/02`'s own example of why.
func test_volume_sums_the_boxes_rather_than_bounding_them() -> void:
	var split := Part.new()
	split.id = &"split"
	split.hp_per_volume = 10.0
	split.volume = [
		Box.new(Vector3(-1.0, 0.0, 0.0), Vector3.ONE),
		Box.new(Vector3(1.0, 0.0, 0.0), Vector3.ONE),
	]

	assert_almost_eq(
		PlacedVolume.cubic_volume(split, Vector3.ZERO),
		2.0,
		0.0001,
		"two boxes, not the 3-wide span"
	)
	assert_almost_eq(PlacedVolume.natural_size(split).x, 3.0, 0.0001, "though its extent IS 3 wide")


## **THE PASS'S OWN LINE**: a 3 x 3 x 0.5 wall destroyed leaves a hole of its own size.
##
## Asserted end to end, against a board built through the real loader — a sized placement becomes a
## part whose `volume` *is* the scaled boxes, so what is drawn, marched, derived and destroyed is
## the real size with nothing downstream knowing anything special about it.
func test_a_sized_wall_reaches_the_board_at_that_size_and_leaves_a_hole_of_it() -> void:
	var map := MapFile.new()
	map.map_name = "sized"
	map.width = 8
	map.rows = 8
	for y in range(8):
		for x in range(8):
			map.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor")
			)
	map.placements.append(
		MapPlacement.new(
			Vector2i(3, 3), MapPlacement.KIND_BLOCKER, &"wall", 0.0, 0.0, Vector3(3.0, 3.0, 0.5)
		)
	)

	var loaded: Dictionary = MapSerializer.to_grid(map)
	assert_eq(loaded.get("error", ""), "", "the sized map must load")
	var grid: Grid = loaded["grid"]
	var placed: Part = grid.blocker_part_at(Vector2i(3, 3))

	var extent: Vector3 = PlacedVolume.natural_size(placed)
	gut.p("  the placed wall is %s at %d hp" % [extent, placed.hp])
	assert_almost_eq(extent.x, 3.0, 0.0001, "three cells across")
	assert_almost_eq(extent.y, 3.0, 0.0001, "three tall")
	assert_almost_eq(extent.z, 0.5, 0.0001, "half a cell thick")
	assert_eq(placed.hp, int(round(4.5 * DataLibrary.get_part(&"wall").hp_per_volume)))
	assert_eq(placed.hp, placed.max_hp, "and it arrives intact rather than pre-damaged")

	# **The hole is its own size**: sight is geometry, so what the wall blocks while it stands and
	# stops blocking when it dies is exactly the volume the author gave it.
	#
	# **Asked of the march, not of `SightSpans`, and that is a finding rather than a convenience.**
	# A 0.5-thick wall does not *fully cover* its cell, and Pass C's span table deliberately only
	# counts a box that does — a partial cover fails open, because the field must never report "no
	# line" where one exists. So a thin resized wall blocks sight in the real march and does not
	# register in the field's conservative pre-filter. That is the safe direction and it is the
	# first content that actually exercises it; see this file's own note and the changelog.
	assert_false(
		LoS.has_los(grid, Vector2i(1, 3), Vector2i(6, 3)), "the sized wall blocks the sight line"
	)
	placed.hp = 0
	assert_true(
		LoS.has_los(grid, Vector2i(1, 3), Vector2i(6, 3)),
		"and destroying it leaves a hole where it was"
	)


## An unsized placement is the authored part, unchanged — no scaled boxes, no recomputed hp.
##
## **Not asserted as object identity**, which was the first attempt and was wrong about the
## codebase: `DataLibrary.get_part` already returns a fresh `duplicate(true)` on every call, so
## every placement has its own copy regardless. What `_sized` guarantees is that it does not
## duplicate a *second* time and does not touch what it was given.
func test_an_unsized_placement_is_the_authored_part_unchanged() -> void:
	var map := MapFile.new()
	map.width = 4
	map.rows = 4
	map.placements.append(MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_BLOCKER, &"wall"))

	var loaded: Dictionary = MapSerializer.to_grid(map)
	assert_eq(loaded.get("error", ""), "")
	var placed: Part = (loaded["grid"] as Grid).blocker_part_at(Vector2i(1, 1))
	var authored: Part = DataLibrary.get_part(&"wall")

	assert_eq(placed.hp, authored.hp, "its hp is the authored one, not a recomputed one")
	assert_eq(placed.volume.size(), authored.volume.size())
	assert_almost_eq(
		PlacedVolume.natural_size(placed).distance_to(PlacedVolume.natural_size(authored)),
		0.0,
		0.0001,
		"and its boxes are the authored ones"
	)
