extends GutTest

## taskblock-51 `BR51.11`: **a unit turns the short way round.**
##
## > *"When moving, sometimes units spin the long way around to reface. Turning left 270
## > degrees instead of turning right 90."*
##
## `ResolutionPlayer` tweens the facing with `tween_method`, which interpolates its two
## arguments as **plain numbers**. Handed raw orientations it runs 0.1 -> 6.0 the long way —
## 336 degrees left instead of 24 right. Only the path was ever wrong: both endpoints name the
## same facing, which is why the supervisor saw units "end up facing in reasonable directions"
## and why the point-to-point animation looked correct.


## Every case is an angle pair a real bout produces, and the assertion is on the **arc**, not on
## the endpoint — an endpoint test passes on the broken version, because the broken version
## arrives in the right place too.
func test_the_arc_is_never_longer_than_half_a_turn() -> void:
	var cases: Array[Array] = [
		[0.1, 6.0],
		[6.0, 0.1],
		[0.0, PI + 0.2],
		[PI + 0.2, 0.0],
		[-PI + 0.1, PI - 0.1],
		[TAU - 0.05, 0.05],
	]
	for case: Array in cases:
		var from_orientation: float = case[0]
		var to_orientation: float = case[1]
		var arc: float = absf(
			(
				ResolutionPlayer.shortest_arc_target(from_orientation, to_orientation)
				- from_orientation
			)
		)
		gut.p(
			(
				"%.3f -> %.3f sweeps %.3f rad (%.0f deg)"
				% [from_orientation, to_orientation, arc, rad_to_deg(arc)]
			)
		)
		assert_true(
			arc <= PI + 0.0001,
			"%.3f -> %.3f took the long way" % [from_orientation, to_orientation]
		)


## **And it still arrives at the right facing.** The target is numerically adjacent to `from`
## rather than canonical, so this checks the two are the same *angle* — a fix that turned the
## short way to the wrong place would be worse than the bug.
func test_it_arrives_at_the_same_facing_it_was_asked_for() -> void:
	for case: Array in [[0.1, 6.0], [6.0, 0.1], [0.0, PI + 0.2], [TAU - 0.05, 0.05]]:
		var target: float = ResolutionPlayer.shortest_arc_target(case[0], case[1])
		assert_almost_eq(
			absf(angle_difference(target, case[1])),
			0.0,
			0.0001,
			"%.3f -> %.3f landed on a different facing" % [case[0], case[1]]
		)


## The supervisor reported this on squad 1 and not squad 0, which is a distribution of starting
## facings rather than a squad rule — the defect is in the arithmetic and has no idea which
## squad it is serving. Pinned so the fix is not mistaken for a squad-specific patch.
func test_the_short_way_has_nothing_to_do_with_which_squad_is_turning() -> void:
	var quarter_turn: float = ResolutionPlayer.shortest_arc_target(0.0, -PI / 2.0)
	var same_from_the_other_side: float = ResolutionPlayer.shortest_arc_target(PI, PI / 2.0)

	assert_almost_eq(quarter_turn - 0.0, -PI / 2.0, 0.0001, "a right turn from facing +x")
	assert_almost_eq(same_from_the_other_side - PI, -PI / 2.0, 0.0001, "and from facing -x")
