extends GutTest

## taskblock-63 Pass B — **a body's standing height derives from its legs.**
##
## Before this, `UnitGeometry.assembly_placements` pinned the root at the cell's
## floor and hung the legs down from the torso's own `HIP` socket. The socket
## transform lives on the torso and is shared, so **a longer leg put its foot below
## the floor plane** instead of raising the hip — which is why the first alternative
## leg (tb62 Pass A) was deleted rather than shipped, and why no leg whose length
## differed from `leg.tres`'s could be authored at all.
##
## **Two claims are pinned here and the second matters more than the first.** That a
## long leg raises the body is the feature; that **the default leg's behaviour is
## bit-for-bit unchanged** is the risk, because this touches the placement of every
## unit in the game. The reference humanoid's offset is asserted as an exact `0.0`
## rather than "small", so a future part that quietly drops a box below the foot
## plane reddens this rather than shifting every body in the game by a millimetre.
##
## **The bodies here are built from real authored parts** (`DataLibrary`'s own
## `torso.tres`, `leg.tres`, `long_leg.tres`), not from hand-rolled stand-ins — this
## is exactly the fixture question `PLAN`'s test-audit item is about, and a standing
## height measured against a one-box torso would prove nothing about the shell the
## game actually assembles.

## `torso.tres`'s own `HIP_L`/`HIP_R` height, and `leg.tres`'s own length. Read off
## the authored resources in `test_the_reference_leg_exactly_reaches_the_floor`
## rather than trusted from here — these are here to make the arithmetic in the
## expectations below legible, not to stand in for the data.
const REFERENCE_HIP_Y := 0.9
const REFERENCE_LEG_LENGTH := 0.9
## `long_leg.tres` is the reference leg scaled by 1.5 — 1.35 long, 0.6 step height,
## 9.0 mass. **One scale factor, applied to every number**, so nothing about it is a
## balance figure invented to look plausible: it exists to exercise the rule, and it
## says how it was derived rather than claiming to be tuned.
const LONG_LEG_LENGTH := 1.35
## What that leg must therefore lift the torso by: it hangs 1.35 from a hip socket
## 0.9 up, so 0.45 of it would be underground and the body rises by exactly that.
const LONG_LEG_OFFSET := 0.45


## A shell of `torso.tres` standing on two of `leg_part_id`, armoured on whatever
## ARMOR socket that leg authors. Deliberately a template rather than a `Loadout`
## override of the reference humanoid: that template mounts `leg_cladding` and a
## renamed `LEG_ARMOR` onto its legs, and a leg that authors neither would fail
## assembly outright — which is a real authoring fact about `long_leg.tres` and not
## something to paper over in a fixture.
func _biped(leg_part_id: StringName, cell: Vector2i = Vector2i.ZERO) -> Unit:
	return _mismatched_biped(leg_part_id, leg_part_id, cell)


## The same, with a different part on each hip. There is no joint anywhere in the
## body that could take up a difference in length — `torso.tres` has `HIP_L`/`HIP_R`
## and no hip *segment*, and a leg has no knee — so this is the shape the rule has to
## answer for rather than a shape it supports.
func _mismatched_biped(left_id: StringName, right_id: StringName, cell: Vector2i) -> Unit:
	var template := ShellTemplate.new(
		&"torso", [Mount.new(&"HIP_L", left_id), Mount.new(&"HIP_R", right_id)]
	)
	return BodyAssembler.assemble(
		template, Loadout.new({}), DeepStrike.reference_humanoid_pool(), Matrix.new(), cell
	)


## The lowest and highest world-Y any placed box corner reaches.
func _y_extent(placements: Array[BoxPlacement]) -> Vector2:
	var lowest := INF
	var highest := -INF
	for placement: BoxPlacement in placements:
		var half: Vector3 = placement.box.size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var local: Vector3 = (
						placement.box.center + Vector3(sx * half.x, sy * half.y, sz * half.z)
					)
					var world: Vector3 = placement.transform * local
					lowest = minf(lowest, world.y)
					highest = maxf(highest, world.y)
	return Vector2(lowest, highest)


## **A side elevation, because standing height is spatial and CC cannot see it.**
## One row per 0.1 world units, `#` wherever any placed box occupies that band, and
## the floor plane drawn as a real line so a foot through it is visible rather than
## inferred from a number. CLAUDE.md's rule: a spatial system without a dump is one
## nobody can verify.
func _elevation_dump(label: String, placements: Array[BoxPlacement]) -> String:
	const BAND := 0.1
	const LOWEST_BAND := -10  # -1.0 world units, well under any floor breach
	const HIGHEST_BAND := 26  # 2.6 world units, over the tallest body here
	var occupied: Dictionary = {}
	for placement: BoxPlacement in placements:
		var extent: Vector2 = _y_extent([placement] as Array[BoxPlacement])
		var from: int = floori(extent.x / BAND)
		var to: int = ceili(extent.y / BAND)
		for band in range(from, to):
			occupied[band] = true

	var lines: Array[String] = ["", "%s — side elevation, one row per %.1f units:" % [label, BAND]]
	for band in range(HIGHEST_BAND, LOWEST_BAND - 1, -1):
		var y: float = band * BAND
		var marker: String = "#" if occupied.has(band) else " "
		var floor_rule: String = "  <== FLOOR" if band == 0 else ""
		lines.append("  %+5.1f |%s|%s" % [y, marker, floor_rule])
	return "\n".join(lines)


## **The zero this whole pass rests on.** `leg.tres` hangs 0.9 from a hip socket 0.9
## above the torso's own origin, so the reference body's feet already rest exactly on
## the floor plane and the offset it gains is exactly nothing. If this is not zero,
## every unit in the game just moved.
func test_the_reference_leg_exactly_reaches_the_floor() -> void:
	var pool: Dictionary = DeepStrike.reference_humanoid_pool()
	var leg: Part = pool[&"leg"]
	var torso: Part = pool[&"torso"]

	var hip_y := -1.0
	for socket: Socket in torso.sockets:
		if socket.socket_type == UnitGeometry.LEG_SOCKET_TYPE:
			hip_y = socket.transform.origin.y
			break
	assert_almost_eq(hip_y, REFERENCE_HIP_Y, 0.0001, "torso.tres's own HIP socket height")

	var leg_bottom: float = leg.volume[0].center.y - leg.volume[0].size.y * 0.5
	assert_almost_eq(leg_bottom, -REFERENCE_LEG_LENGTH, 0.0001, "leg.tres's own length")
	assert_almost_eq(
		hip_y + leg_bottom, 0.0, 0.0001, "the reference foot rests on the floor, by authoring"
	)


## **The pin the taskblock asked for by name: this is a change to every existing
## unit's assembly and it must not move one.**
func test_the_default_leg_leaves_every_existing_body_exactly_where_it_was() -> void:
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(3, 4))

	assert_eq(
		UnitGeometry.standing_offset(unit.shell.root),
		0.0,
		"the reference humanoid gains no standing height — an exact zero, not a small one"
	)

	var extent: Vector2 = _y_extent(UnitGeometry.placements(unit))
	gut.p(_elevation_dump("reference humanoid (leg.tres)", UnitGeometry.placements(unit)))
	assert_almost_eq(extent.x, 0.0, 0.0001, "its lowest box corner is the floor plane itself")


## The feature. A longer leg raises the hip rather than burying the foot.
func test_a_longer_leg_stands_the_body_taller_with_its_feet_on_the_floor() -> void:
	var short: Unit = _biped(&"leg")
	var tall: Unit = _biped(&"long_leg")

	assert_almost_eq(
		UnitGeometry.standing_offset(tall.shell.root),
		LONG_LEG_OFFSET,
		0.0001,
		"long_leg.tres is %.2f long against a hip at %.2f" % [LONG_LEG_LENGTH, REFERENCE_HIP_Y]
	)

	var short_extent: Vector2 = _y_extent(UnitGeometry.placements(short))
	var tall_extent: Vector2 = _y_extent(UnitGeometry.placements(tall))
	gut.p(_elevation_dump("biped on leg.tres", UnitGeometry.placements(short)))
	gut.p(_elevation_dump("biped on long_leg.tres", UnitGeometry.placements(tall)))

	assert_almost_eq(tall_extent.x, 0.0, 0.0001, "the long leg's foot rests ON the floor plane")
	assert_almost_eq(
		tall_extent.y - short_extent.y,
		LONG_LEG_OFFSET,
		0.0001,
		"and the whole body above it rose by exactly the leg's extra length"
	)


## The elevation half: a raised cell adds to the standing height rather than
## replacing it. Both terms, since dropping either would still pass a test that only
## checked the body was "higher".
func test_standing_height_composes_with_the_cells_own_height() -> void:
	var tall: Unit = _biped(&"long_leg", Vector2i(2, 2))
	tall.height = 3.0

	var extent: Vector2 = _y_extent(UnitGeometry.placements(tall))

	assert_almost_eq(extent.x, 3.0, 0.0001, "feet rest on the raised cell's own floor, not on 0")


## **The case with nowhere to bend.** Not supported — `PLAN`'s *legs must match* item
## needs a hip segment or a knee and neither exists — so what is pinned is that the
## unsupported case still cannot put a foot through the floor.
func test_mismatched_legs_take_the_deeper_one_and_no_foot_passes_the_floor() -> void:
	var odd: Unit = _mismatched_biped(&"leg", &"long_leg", Vector2i.ZERO)

	assert_almost_eq(
		UnitGeometry.standing_offset(odd.shell.root),
		LONG_LEG_OFFSET,
		0.0001,
		"the DEEPER leg sets the height, so the shorter one dangles rather than sinking"
	)

	var extent: Vector2 = _y_extent(UnitGeometry.placements(odd))
	gut.p(_elevation_dump("mismatched: leg.tres + long_leg.tres", UnitGeometry.placements(odd)))
	assert_gte(extent.x, -0.0001, "nothing on a mismatched body reaches below the floor plane")


## Symmetry, and the reason the offset is not clamped at zero: "the feet rest on the
## floor" has to hold downward too, or a short leg leaves the body hovering.
func test_a_leg_shorter_than_its_hip_socket_lowers_the_body() -> void:
	var pool: Dictionary = DeepStrike.reference_humanoid_pool()
	var stub: Part = (pool[&"leg"] as Part).duplicate(true)
	stub.id = &"stub_leg"
	stub.volume = [Box.new(Vector3(0.0, -0.25, 0.0), Vector3(0.16, 0.5, 0.16))]
	stub.sockets = []
	pool[&"stub_leg"] = stub

	var unit: Unit = BodyAssembler.assemble(
		ShellTemplate.new(
			&"torso", [Mount.new(&"HIP_L", &"stub_leg"), Mount.new(&"HIP_R", &"stub_leg")]
		),
		Loadout.new({}),
		pool,
		Matrix.new(),
		Vector2i.ZERO
	)

	assert_almost_eq(
		UnitGeometry.standing_offset(unit.shell.root),
		-0.4,
		0.0001,
		"a 0.5 leg on a 0.9 hip sits the body 0.4 lower, rather than hovering on nothing"
	)


## A wall, a scrap pile, a dropped assembly, a legless ally in a seat: nothing here
## is claiming to stand, so nothing moves.
func test_a_body_with_no_legs_at_all_keeps_the_floor_it_always_had() -> void:
	var torso: Part = DeepStrike.reference_humanoid_pool()[&"torso"]

	assert_eq(
		UnitGeometry.standing_offset(torso), 0.0, "no leg socket occupied means no claim to stand"
	)
	assert_eq(
		UnitGeometry.standing_offset(null), 0.0, "and a bodiless shell answers rather than crashing"
	)


## A destroyed leg contributes no boxes to `_walk`, so it must contribute no standing
## height either — otherwise a body would hover on the memory of a leg.
func test_losing_both_legs_settles_the_body_onto_the_floor() -> void:
	var tall: Unit = _biped(&"long_leg")
	assert_almost_eq(UnitGeometry.standing_offset(tall.shell.root), LONG_LEG_OFFSET, 0.0001)

	for part: Part in PartGraph.walk(tall.shell.root):
		if part.id == &"long_leg":
			part.hp = 0

	assert_eq(
		UnitGeometry.standing_offset(tall.shell.root),
		0.0,
		"with both legs destroyed the torso settles onto the ground it is lying on"
	)


## Losing ONE of a matched pair changes nothing — the survivor still reaches the same
## depth. Pinned separately because the two cases go through the same code and only
## one of them should move the body.
func test_losing_one_of_a_matched_pair_leaves_the_standing_height_alone() -> void:
	var tall: Unit = _biped(&"long_leg")

	for part: Part in PartGraph.walk(tall.shell.root):
		if part.id == &"long_leg":
			part.hp = 0
			break

	assert_almost_eq(UnitGeometry.standing_offset(tall.shell.root), LONG_LEG_OFFSET, 0.0001)


## **`shoulder_height` builds the body's placement itself**, and did so from its own
## copy of the expression — so it would have gone on reading the floor while the
## rendered shoulder socket read the legs. Checked against the arm's own *placed*
## transform rather than against a second copy of the formula: two different code
## paths agreeing is evidence, one formula agreeing with itself is not.
func test_the_shoulder_height_rises_with_the_legs() -> void:
	var pool: Dictionary = DeepStrike.reference_humanoid_pool()
	var tall: Unit = (
		BodyAssembler
		. assemble(
			(
				ShellTemplate
				. new(
					&"torso",
					[
						Mount.new(&"HIP_L", &"long_leg"),
						Mount.new(&"HIP_R", &"long_leg"),
						Mount.new(&"SHOULDER_L", &"arm"),
					]
				)
			),
			Loadout.new({}),
			pool,
			Matrix.new(),
			Vector2i.ZERO
		)
	)

	var arm_origin := INF
	for placement: BoxPlacement in UnitGeometry.placements(tall):
		if placement.part.id == &"arm":
			arm_origin = placement.transform.origin.y
			break

	assert_almost_eq(
		UnitGeometry.shoulder_height(tall),
		arm_origin,
		0.0001,
		"the reported shoulder is the shoulder the arm actually hangs from"
	)
	assert_almost_eq(
		UnitGeometry.shoulder_height(tall),
		1.53 + LONG_LEG_OFFSET,
		0.0001,
		"torso.tres's own SHOULDER_L at 1.53, lifted by the legs under it"
	)


## **The shot plane does NOT read `assembly_placements`** — `BodyProjector` composes
## the body in its own local space and `ShotPlane` adds the world elevation itself.
## So it needed the standing height wiring in explicitly, and this is what proves the
## two now agree: a long-legged unit that renders raised and resolves shots at the
## floor is the exact visual/logic disagreement taskblock-59 spent a block removing.
func test_the_shot_plane_resolves_against_the_same_standing_height_it_renders_at() -> void:
	var grid := GridFixture.flat(12, 12)
	var state := CombatState.new(grid)
	var tall: Unit = _biped(&"long_leg", Vector2i(5, 5))
	state.add_unit(tall)

	var origin := Vector3(0.0, 1.5, 5.0)
	var plane: Array[Region] = ShotPlane.build(origin, Vector3(1.0, 0.0, 0.0), state, false)

	var lowest := INF
	var highest := -INF
	for region: Region in plane:
		if region.body != tall:
			continue
		lowest = minf(lowest, region.rect.position.y)
		highest = maxf(highest, region.rect.position.y + region.rect.size.y)

	assert_ne(lowest, INF, "the plane must actually hold this unit")
	var rendered: Vector2 = _y_extent(UnitGeometry.placements(tall))
	assert_almost_eq(lowest, rendered.x, 0.0001, "the plane's floor is the rendered body's floor")
	assert_almost_eq(highest, rendered.y, 0.0001, "and its ceiling is the rendered body's ceiling")


## The flat case, asserted alongside, because it is what has been passing all along
## and a regression there would be invisible next to the interesting case above.
func test_the_shot_plane_is_unchanged_for_a_default_legged_unit() -> void:
	var grid := GridFixture.flat(12, 12)
	var state := CombatState.new(grid)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(5, 5))
	state.add_unit(unit)

	var plane: Array[Region] = ShotPlane.build(Vector3(0.0, 1.5, 5.0), Vector3.RIGHT, state, false)

	var lowest := INF
	for region: Region in plane:
		if region.body == unit:
			lowest = minf(lowest, region.rect.position.y)

	assert_almost_eq(lowest, 0.0, 0.0001, "an ordinary body still resolves from the floor plane")
