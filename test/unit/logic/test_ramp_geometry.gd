extends GutTest

## taskblock-38 Pass C: docs/PLAN.md's settled ramp profile, proven now
## even though nothing renders it yet — the low edge at 0, the high edge
## at +0.5, the two lateral edges at +0.25, relative to the ramp's own
## base height, unaffected by which way it happens to face.
##
## **taskblock-69 follow-up: "nothing renders it yet" is still literally true**, thirty-one
## taskblocks later, and the last test in this file is what stops that going unnoticed again. See
## `RampGeometry`'s own header for the whole picture; the short version is that a placed `ramp` is
## a flat slab with a label, and everything below proves a rule that has no consumer.


func test_edge_heights_match_the_settled_profile() -> void:
	var edges: Dictionary = RampGeometry.edge_heights(0.0, 0.0)

	assert_almost_eq(edges.low, 0.0, 0.0001)
	assert_almost_eq(edges.high, UnitGeometry.LEVEL_HEIGHT * 0.5, 0.0001)
	assert_almost_eq(edges.left, UnitGeometry.LEVEL_HEIGHT * 0.25, 0.0001)
	assert_almost_eq(edges.right, UnitGeometry.LEVEL_HEIGHT * 0.25, 0.0001)


## The same relative profile holds regardless of `facing` — facing is a
## world-space rotation resolved later by a view-layer consumer, not a
## value these relative heights depend on.
func test_edge_heights_are_unaffected_by_facing() -> void:
	for facing: float in [0.0, PI * 0.5, PI, -PI * 0.5, 2.75]:
		var edges: Dictionary = RampGeometry.edge_heights(1.0, facing)
		assert_almost_eq(edges.low, 1.0, 0.0001, "facing %f" % facing)
		assert_almost_eq(
			edges.high, 1.0 + UnitGeometry.LEVEL_HEIGHT * 0.5, 0.0001, "facing %f" % facing
		)
		assert_almost_eq(
			edges.left, 1.0 + UnitGeometry.LEVEL_HEIGHT * 0.25, 0.0001, "facing %f" % facing
		)
		assert_eq(edges.facing, facing)


## The whole profile offsets cleanly with the cell's own base height —
## nothing hardcodes an absolute world height.
func test_edge_heights_offset_by_base_height() -> void:
	var edges: Dictionary = RampGeometry.edge_heights(2.0, 0.0)
	assert_almost_eq(edges.low, 2.0, 0.0001)
	assert_almost_eq(edges.high, 2.5, 0.0001)
	assert_almost_eq(edges.left, 2.25, 0.0001)


## The unit-standing height (a ramp cell's own center) is the same value
## as the lateral edges — the midpoint between low and high.
func test_standing_offset_matches_the_lateral_edge_offset() -> void:
	assert_almost_eq(RampGeometry.STANDING_OFFSET, RampGeometry.LATERAL_OFFSET, 0.0001)


## **The stub flag, and the guard that makes it fail loudly when ramps become real.**
##
## `ramp.tres` authors a flat 0.2 slab identical to `ship_floor`'s and nothing reads a ramp's
## facing, so an author reaching for one gets a floor tile with a name. The `display_name` says so,
## because the editor's parts list shows raw ids and the inspect panel is where an author actually
## reads a part.
##
## **This test exists to be deleted.** When the profile above acquires a real consumer — a `ramp`
## whose `volume` is not a flat slab, or a production caller of `edge_heights` — this goes red and
## the failure message says what to do. A flag nobody removes is a flag nobody believes, and the
## alternative (a comment) is exactly what went stale here in the first place: `Surface.RAMP_TAG`
## claimed for thirty-one taskblocks that a ramp rode a sloped profile.
func test_a_ramp_is_still_a_flat_stub_and_says_so() -> void:
	DataLibrary.load_all()
	var ramp: Part = DataLibrary.get_part(&"ramp")
	var tile: Part = DataLibrary.get_part(&"ship_floor")
	assert_not_null(ramp, "the ramp part must still exist — it is a stub, not a deletion")
	if ramp == null:
		DataLibrary.reset()
		return

	assert_eq(ramp.volume.size(), 1, "a ramp is one box")
	assert_eq(
		ramp.volume[0].size,
		tile.volume[0].size,
		(
			"A RAMP HAS BECOME A SLOPE. Good — now retire this test, drop the '(flat stub)' from "
			+ "`ramp.tres`'s display_name, and correct `RampGeometry`'s and `Surface.RAMP_TAG`'s "
			+ "headers, which both say a ramp is flat."
		)
	)
	assert_eq(ramp.volume[0].center, tile.volume[0].center, "and sits where a floor tile sits")
	assert_true(
		ramp.display_name.contains("stub"),
		(
			"a ramp reads as a real slope in the inspect panel while being a flat tile — either "
			+ "restore the flag in `ramp.tres` or make ramps real"
		)
	)
	DataLibrary.reset()
