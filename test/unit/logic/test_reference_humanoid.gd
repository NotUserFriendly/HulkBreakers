extends GutTest

## docs/01 "The Reference Humanoid": body-shape-driven mechanics can't be
## tested against a shapeless body. These tests exercise the composed,
## deterministic skeleton DeepStrike.assemble_reference_humanoid() builds —
## every one of them is a geometry fact, not a design choice.


func _reference_unit(cell: Vector2i = Vector2i(0, 0)) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell)


func _pool_template(part_id: StringName) -> Part:
	for template: Part in DataLibrary.parts_pool():
		if template.id == part_id:
			return template
	fail_test("no pool template %s" % part_id)
	return null


func _world_corners(placement: BoxPlacement) -> Array[Vector3]:
	var half: Vector3 = placement.box.size * 0.5
	var center: Vector3 = placement.box.center
	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var local: Vector3 = center + Vector3(sx * half.x, sy * half.y, sz * half.z)
				corners.append(placement.transform * local)
	return corners


func _find(regions: Array[Region], part_id: StringName) -> Region:
	for region: Region in regions:
		if region.part.id == part_id:
			return region
	fail_test("no region for part %s" % part_id)
	return null


## BodyProjector.project() does not sort by depth — only ShotPlane.build()
## does, for a whole-CombatState plane. resolve_projectile() assumes a
## depth-sorted array (it returns the first containing region, nearest
## first), so any test resolving against a single-unit BodyProjector.project()
## plane must sort it first, same as ShotPlane.build() does internally.
func _sorted(regions: Array[Region]) -> Array[Region]:
	var copy: Array[Region] = regions.duplicate()
	copy.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)
	return copy


func test_no_living_part_extends_below_the_floor() -> void:
	var unit := _reference_unit()
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		for corner: Vector3 in _world_corners(placement):
			assert_true(
				corner.y >= -0.0001,
				"%s extends below the floor: y=%f" % [placement.part.id, corner.y]
			)


func test_feet_touch_the_floor() -> void:
	var unit := _reference_unit()
	var min_y := INF
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		for corner: Vector3 in _world_corners(placement):
			min_y = minf(min_y, corner.y)
	assert_almost_eq(min_y, 0.0, 0.01)


func test_head_is_the_highest_part_a_leg_is_the_lowest() -> void:
	var unit := _reference_unit()
	var top_id: StringName = &""
	var top_y := -INF
	var bottom_y := INF
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		for corner: Vector3 in _world_corners(placement):
			if corner.y > top_y:
				top_y = corner.y
				top_id = placement.part.id
			if corner.y < bottom_y:
				bottom_y = corner.y
	# head_cladding, not bare head: cladding hugs every face (docs/01
	# taskblock02 Pass C), so it's strictly the topmost geometry once it
	# exists. The lowest point is a legitimate tie between leg and
	# leg_cladding (leg_cladding's socket is deliberately shifted so its
	# sole stays flush with the floor rather than clipping through it) —
	# assert the height itself, not which part id happens to report it.
	assert_eq(top_id, &"head_cladding")
	assert_almost_eq(bottom_y, 0.0, 0.0001, "feet (and their cladding) touch the floor")


func test_arms_are_lateral_a_left_and_a_right_both_exist() -> void:
	var unit := _reference_unit()
	var saw_positive := false
	var saw_negative := false
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		if placement.part.id == &"arm":
			var world_x: float = (placement.transform * placement.box.center).x
			if world_x > 0.05:
				saw_positive = true
			elif world_x < -0.05:
				saw_negative = true
	assert_true(saw_positive and saw_negative, "both a left (-x) and right (+x) arm must exist")


func test_the_composed_body_fits_inside_one_cell_footprint() -> void:
	var unit := _reference_unit()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		for corner: Vector3 in _world_corners(placement):
			min_x = minf(min_x, corner.x)
			max_x = maxf(max_x, corner.x)
			min_z = minf(min_z, corner.z)
			max_z = maxf(max_z, corner.z)
	assert_true(
		max_x - min_x <= UnitGeometry.CELL_SIZE, "width %f exceeds one cell" % (max_x - min_x)
	)
	assert_true(
		max_z - min_z <= UnitGeometry.CELL_SIZE, "depth %f exceeds one cell" % (max_z - min_z)
	)


func test_a_plates_rect_overlaps_its_parents_and_sits_at_lower_depth_from_the_front() -> void:
	var unit := _reference_unit()
	var regions: Array[Region] = BodyProjector.project(unit, Vector3(0, 0.0, -1))
	var torso: Region = _find(regions, &"torso")
	var plate: Region = _find(regions, &"plate_large_steel")

	assert_true(plate.rect.intersects(torso.rect), "the plate must project over its parent")
	assert_lt(plate.depth, torso.depth, "the front plate must sit nearer the shooter")


## The load-bearing case (docs/01): the same shot resolves to the front
## plate head-on, and to the thin rear plate (or bare torso) once flanked —
## the front plate is never the frontmost hit once you're behind it, even
## though its own back face can still legitimately appear as an occluded
## region (BodyProjector projects per visible face, docs/02/03) rather than
## vanishing from the array outright.
func test_the_flank_test() -> void:
	var unit := _reference_unit()

	var front: Array[Region] = _sorted(BodyProjector.project(unit, Vector3(0, 0.0, -1)))
	var plate_rect: Rect2 = _find(front, &"plate_large_steel").rect
	# Off-center (docs/01a's own BACK-socket ammo rack sits directly behind
	# the spine, narrower than the plates either side of it) — aim through
	# the plate's own body, not through whatever else happens to share its
	# lateral center.
	var aim_point: Vector2 = plate_rect.get_center() + Vector2(0.15, 0.0)
	var front_hit: Region = ShotPlane.resolve_projectile(front, aim_point)
	assert_eq(front_hit.part.id, &"plate_large_steel")

	var back: Array[Region] = _sorted(BodyProjector.project(unit, Vector3(0, 0.0, 1)))
	var back_hit: Region = ShotPlane.resolve_projectile(back, aim_point)
	assert_true(
		back_hit.part.id == &"plate_large_sheet_steel" or back_hit.part.id == &"torso",
		"flanking must reach the thin rear plate or bare torso, got %s" % back_hit.part.id
	)


func test_ammo_rack_is_occluded_from_the_front_but_frontmost_from_behind() -> void:
	var unit := _reference_unit()

	var front: Array[Region] = BodyProjector.project(unit, Vector3(0, 0.0, -1))
	var front_rack: Region = _find(front, &"ammo_rack")
	var min_front_depth := INF
	for region: Region in front:
		min_front_depth = minf(min_front_depth, region.depth)
	assert_true(
		front_rack.depth > min_front_depth, "the rack must not be frontmost viewed from the front"
	)

	var back: Array[Region] = BodyProjector.project(unit, Vector3(0, 0.0, 1))
	var back_rack: Region = _find(back, &"ammo_rack")
	var min_back_depth := INF
	for region: Region in back:
		min_back_depth = minf(min_back_depth, region.depth)
	assert_almost_eq(
		back_rack.depth, min_back_depth, 0.0001, "the rack must be frontmost viewed from behind"
	)


func test_half_cover_masks_the_legs_but_not_the_head() -> void:
	var shooter_cell := Vector2i(5, 0)
	var cover_cell := Vector2i(5, 3)
	var target_cell := Vector2i(5, 6)

	# A generic waist-high blocker — its own fixture, not MapGen's own
	# placement constants (taskblock-16 Pass B2 retired the scalar those
	# used to back; this test is about ShotPlane projection, not about
	# what MapGen itself scatters, so it owns its own reasonable numbers).
	const HALF_COVER_HEIGHT: float = 0.90
	const HALF_COVER_FOOTPRINT: float = 0.8
	var cover := Part.new()
	cover.id = &"half_cover"
	cover.is_destructible = false
	cover.material = &"hull_plate"
	cover.volume = [
		Box.new(
			Vector3(0.0, HALF_COVER_HEIGHT * 0.5, 0.0),
			Vector3(HALF_COVER_FOOTPRINT, HALF_COVER_HEIGHT, HALF_COVER_FOOTPRINT)
		)
	]

	var grid := Grid.new(12, 12)
	grid.blockers[cover_cell] = cover
	var unit := _reference_unit(target_cell)
	var state := CombatState.new(grid, [unit])

	var origin := Vector2(shooter_cell.x, shooter_cell.y)
	var direction := Vector2(target_cell - shooter_cell).normalized()
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)

	print("\n=== half cover: masks legs, not the head ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 4))

	var leg_region: Region = _find(plane, &"leg")
	var leg_point: Vector2 = leg_region.rect.get_center()
	var leg_hit: Region = ShotPlane.resolve_projectile(plane, leg_point)
	assert_eq(leg_hit.part.id, &"half_cover", "half cover must mask the legs")

	# head_cladding, not bare "head" — cladding wraps every face, so the
	# bare head is never itself the frontmost thing anywhere in the plane
	# (docs/01 taskblock02 Pass C). Whichever head layer this point
	# actually resolves to (cladding or the front plate), it must not be
	# the cover.
	var head_region: Region = _find(plane, &"head_cladding")
	var head_point: Vector2 = head_region.rect.get_center()
	var head_hit: Region = ShotPlane.resolve_projectile(plane, head_point)
	assert_ne(
		head_hit.part.id, &"half_cover", "half cover must not reach high enough to mask the head"
	)


## taskblock-16 B1: tall cover ("steel pillar... masks torso") must reach
## up through the torso while still leaving the head exposed — the other
## half of the "low vs tall masks legs vs torso" claim from
## test_half_cover_masks_the_legs_but_not_the_head, above. Falls out of
## the same projection math the low case does; this just proves it at
## the height a real `pillar` actually ships with
## (`MapGen.FULL_COVER_HEIGHT`, the reference humanoid's own torso/head
## boundary).
func test_full_cover_masks_the_torso_but_not_the_head() -> void:
	var shooter_cell := Vector2i(5, 0)
	var cover_cell := Vector2i(5, 3)
	var target_cell := Vector2i(5, 6)

	const FULL_COVER_FOOTPRINT: float = 0.8
	var cover := Part.new()
	cover.id = &"full_cover"
	cover.is_destructible = false
	cover.material = &"steel"
	cover.volume = [
		Box.new(
			Vector3(0.0, MapGen.FULL_COVER_HEIGHT * 0.5, 0.0),
			Vector3(FULL_COVER_FOOTPRINT, MapGen.FULL_COVER_HEIGHT, FULL_COVER_FOOTPRINT)
		)
	]

	var grid := Grid.new(12, 12)
	grid.blockers[cover_cell] = cover
	var unit := _reference_unit(target_cell)
	var state := CombatState.new(grid, [unit])

	var origin := Vector2(shooter_cell.x, shooter_cell.y)
	var direction := Vector2(target_cell - shooter_cell).normalized()
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)

	print("\n=== full cover: masks the torso, not the head ===")
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 2.0), 4, 4))

	var torso_region: Region = _find(plane, &"torso")
	var torso_point: Vector2 = torso_region.rect.get_center()
	var torso_hit: Region = ShotPlane.resolve_projectile(plane, torso_point)
	assert_eq(torso_hit.part.id, &"full_cover", "full cover must mask the torso")

	var leg_region: Region = _find(plane, &"leg")
	var leg_point: Vector2 = leg_region.rect.get_center()
	var leg_hit: Region = ShotPlane.resolve_projectile(plane, leg_point)
	assert_eq(
		leg_hit.part.id, &"full_cover", "full cover taller than half cover must mask legs too"
	)

	var head_region: Region = _find(plane, &"head_cladding")
	var head_point: Vector2 = head_region.rect.get_center()
	var head_hit: Region = ShotPlane.resolve_projectile(plane, head_point)
	assert_ne(
		head_hit.part.id, &"full_cover", "full cover must not reach high enough to mask the head"
	)


## docs/01 taskblock02 Pass C: the full plate -> cladding -> bare gradient.
## A shot on the plated front face resolves plate first; destroying the
## plate exposes the cladding underneath, never the bare part directly;
## destroying the cladding too finally exposes the bare part.
func test_destroying_layers_progressively_exposes_cladding_then_the_bare_part() -> void:
	var unit := _reference_unit()
	var plate: Part = unit.shell.find_part(&"plate_large_steel")
	var cladding: Part = unit.shell.find_part(&"torso_cladding")

	var before: Array[Region] = _sorted(BodyProjector.project(unit, Vector3(0, 0.0, -1)))
	var aim_point: Vector2 = _find(before, &"plate_large_steel").rect.get_center()
	assert_eq(ShotPlane.resolve_projectile(before, aim_point).part.id, &"plate_large_steel")

	plate.hp = 0
	var after_plate: Array[Region] = _sorted(BodyProjector.project(unit, Vector3(0, 0.0, -1)))
	for region: Region in after_plate:
		assert_ne(region.part.id, &"plate_large_steel", "a destroyed plate must leave the plane")
	assert_eq(
		ShotPlane.resolve_projectile(after_plate, aim_point).part.id,
		&"torso_cladding",
		"a destroyed plate exposes cladding, never the bare part directly"
	)

	cladding.hp = 0
	var after_cladding: Array[Region] = _sorted(BodyProjector.project(unit, Vector3(0, 0.0, -1)))
	for region: Region in after_cladding:
		assert_ne(region.part.id, &"torso_cladding", "destroyed cladding must leave the plane too")
	# taskblock-09 D: the plate's own socket still holds it (a destroyed,
	# invisible part is still attached — Pass A never detaches on hp
	# alone), so its JOINT — not the bare torso — is what the plate/
	# cladding used to occlude and now don't. The gradient grew a real
	# fourth layer: plate -> cladding -> the plate's own joint -> torso.
	var armor_socket: Socket = PartGraph.find_owning_socket(unit.shell.root, plate)
	assert_eq(
		ShotPlane.resolve_projectile(after_cladding, aim_point).part.id,
		&"plate_large_steel_joint",
		"destroying the plate and its cladding exposes the plate's own joint, not the bare torso yet"
	)

	PartGraph.detach(armor_socket)
	var after_joint: Array[Region] = _sorted(BodyProjector.project(unit, Vector3(0, 0.0, -1)))
	assert_eq(
		ShotPlane.resolve_projectile(after_joint, aim_point).part.id,
		&"torso",
		"only once the joint's own occupant is gone does the bare torso finally show through"
	)


## The reverse of the plated case: a lateral face has no ARMOR socket at
## all (the reference humanoid's torso only declares FRONT/REAR), so a
## shot there must resolve to cladding — never a plate, since none covers
## that face; never straight to the bare part either, since cladding
## always wraps every face a plate doesn't stand off from. Isolated from
## the full reference humanoid (an arm hangs directly alongside the torso
## and would occlude a lateral shot at the whole-unit level — a real,
## correct consequence of body shape, just not what this test is about).
func test_a_shot_on_an_unplated_face_resolves_to_cladding_never_a_plate() -> void:
	var torso: Part = _pool_template(&"torso")
	var plate: Part = _pool_template(&"plate_large_steel")
	var cladding: Part = _pool_template(&"torso_cladding")
	PartGraph.attach(plate, torso, PartGraph.find_socket(torso, &"ARMOR_FRONT"))
	PartGraph.attach(cladding, torso, PartGraph.find_socket(torso, &"CLADDING"))
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))

	var side: Array[Region] = _sorted(BodyProjector.project(unit, Vector3(1, 0.0, 0)))
	var resolved: Region = _find(side, &"torso_cladding")

	assert_ne(resolved.part.id, &"plate_large_steel")
	assert_ne(resolved.part.id, &"torso")


## docs/01 taskblock02 Pass C: "plated face -> plate (dt 6) ... bare face
## -> cladding (dt 3) ... strip cladding -> base part (dt 2)" — the
## gradient itself, asserted explicitly against the material table rather
## than assumed from the parts that happen to use it.
func test_the_plate_cladding_bare_dt_gradient_is_6_3_2() -> void:
	var table := DataLibrary.material_table()
	assert_eq(table.get_entry(&"steel").dt, 6.0, "plated face: steel")
	assert_eq(table.get_entry(&"sheet_steel").dt, 3.0, "cladding: sheet_steel")
	assert_eq(table.get_entry(&"artificial_bone").dt, 2.0, "bare part: artificial_bone")

	var unit := _reference_unit()
	assert_eq(unit.shell.find_part(&"plate_large_steel").material, &"steel")
	assert_eq(unit.shell.find_part(&"torso_cladding").material, &"sheet_steel")
	assert_eq(unit.shell.root.material, &"artificial_bone")


func test_no_pool_part_has_an_empty_material() -> void:
	for template: Part in DataLibrary.parts_pool():
		assert_ne(template.material, &"", "%s must carry a real material (docs/10)" % template.id)


func test_the_pool_yields_at_least_three_distinct_colors() -> void:
	var table := DataLibrary.material_table()
	var colors: Array[Color] = []
	for template: Part in DataLibrary.parts_pool():
		var color: Color = table.color_for(template.material)
		if not colors.has(color):
			colors.append(color)
	assert_true(colors.size() >= 3, "the pool must read as more than one or two flat colors")


func test_validate_assembly_flags_an_empty_material_same_as_a_missing_volume() -> void:
	var unit := _reference_unit()
	var torso: Part = unit.shell.root
	torso.material = &""

	var violations: Array[String] = DeepStrike.validate_assembly(unit)
	var found := false
	for violation: String in violations:
		if violation.contains("material"):
			found = true
	assert_true(found, "an empty material must be a validate_assembly violation: %s" % violations)


## Combat Tester content: legs' own ARMOR socket used to share the bare
## "ARMOR" id with arm/forearm's — a flat Loadout couldn't otherwise
## address "both legs' armor" independently of the arms'.
## `DeepStrike.reference_humanoid_pool()` carves out a `LEG_ARMOR` id for
## exactly this, the same fix already established for `hand_l`/`hand_r`'s
## own `GRIP_L`/`GRIP_R`. This is a geometry-of-the-skeleton fact, not a
## loadout choice: true even for the plain default assembly.
func test_both_legs_own_armor_socket_is_independently_addressable_from_arms() -> void:
	var unit := _reference_unit()
	var arm: Part = unit.shell.find_part(&"arm")
	var forearm: Part = unit.shell.find_part(&"forearm")
	var legs: Array[Part] = []
	for part: Part in PartGraph.walk(unit.shell.root):
		if part.id == &"leg":
			legs.append(part)

	assert_eq(legs.size(), 2, "sanity: both legs must be present")
	for leg: Part in legs:
		var socket: Socket = PartGraph.find_socket(leg, &"LEG_ARMOR")
		assert_not_null(socket, "each leg's own armor socket must carry the LEG_ARMOR id")

	assert_not_null(
		PartGraph.find_socket(arm, &"ARMOR"), "the arm must keep the bare ARMOR id, unaffected"
	)
	assert_not_null(
		PartGraph.find_socket(forearm, &"ARMOR"),
		"the forearm must keep the bare ARMOR id, unaffected"
	)


## A Loadout keyed to LEG_ARMOR must reach BOTH legs (they share one
## renamed pool copy — no L/R distinction needed between two legs that
## always get the same plate) while leaving the arms on their own
## default armor entirely untouched.
func test_a_loadout_can_arm_both_legs_without_touching_the_arms() -> void:
	var loadout := Loadout.new({&"LEG_ARMOR": &"plate_large_steel"})
	var unit: Unit = BodyAssembler.assemble(
		DeepStrike.reference_humanoid_template(),
		loadout,
		DeepStrike.reference_humanoid_pool(),
		Matrix.new(),
		Vector2i(0, 0)
	)
	assert_not_null(unit)

	var leg_plate_count := 0
	var arm_plate_count := 0
	for part: Part in PartGraph.walk(unit.shell.root):
		if part.id == &"leg":
			var socket: Socket = PartGraph.find_socket(part, &"LEG_ARMOR")
			if socket.occupant != null and socket.occupant.id == &"plate_large_steel":
				leg_plate_count += 1
		elif part.id == &"arm":
			var socket: Socket = PartGraph.find_socket(part, &"ARMOR")
			if socket.occupant != null and socket.occupant.id == &"plate_small_steel":
				arm_plate_count += 1

	assert_eq(leg_plate_count, 2, "the loadout override must land on both legs")
	assert_eq(arm_plate_count, 2, "the arms must keep their own default plate, untouched")
