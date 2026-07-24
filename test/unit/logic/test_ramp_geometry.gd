extends GutTest

## taskblock-38 Pass C: docs/PLAN.md's settled ramp profile, proven now
## even though nothing renders it yet — the low edge at 0, the high edge
## at +0.5, the two lateral edges at +0.25, relative to the ramp's own
## base height, unaffected by which way it happens to face.


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


## The whole profile offsets cleanly with the tile's own base height —
## nothing hardcodes an absolute world height.
func test_edge_heights_offset_by_base_height() -> void:
	var edges: Dictionary = RampGeometry.edge_heights(2.0, 0.0)
	assert_almost_eq(edges.low, 2.0, 0.0001)
	assert_almost_eq(edges.high, 2.5, 0.0001)
	assert_almost_eq(edges.left, 2.25, 0.0001)


## The unit-standing height (a ramp tile's own center) is the same value
## as the lateral edges — the midpoint between low and high.
func test_standing_offset_matches_the_lateral_edge_offset() -> void:
	assert_almost_eq(RampGeometry.STANDING_OFFSET, RampGeometry.LATERAL_OFFSET, 0.0001)
