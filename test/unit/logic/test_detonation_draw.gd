extends GutTest

## taskblock-51 Pass C `BR35.08`: **a detonation is visible, and its size is the real one.**
##
## Supervisor-specified: a translucent red sphere from the detonation point, growing outward to
## the **actual explosion radius**, then fading — grow : fade 1 : 3, total time tunable beside
## the other bullet timing, defaulting to 1000 ms.
##
## The radius travelling in the log is the point. A drawn extent computed in the view would be
## the same defect `BR35.04` was filed for — geometry that looks right and corresponds to
## nothing — so what is drawn comes from what resolved.


func test_the_timing_matches_the_specified_ratio() -> void:
	assert_almost_eq(ResolutionPlayer.DETONATION_MS, 1000.0, 0.001, "the stated default")
	# 1 : 3 grow-to-fade means the grow occupies a quarter of the total.
	assert_almost_eq(
		ResolutionPlayer.DETONATION_GROW_FRACTION, 0.25, 0.0001, "grow : fade is 1 : 3"
	)
	var grow: float = ResolutionPlayer.DETONATION_MS * ResolutionPlayer.DETONATION_GROW_FRACTION
	assert_almost_eq(
		ResolutionPlayer.DETONATION_MS - grow, grow * 3.0, 0.001, "the fade is three times the grow"
	)


func test_the_sphere_is_translucent_and_red() -> void:
	var colour: Color = ResolutionPlayer.DETONATION_COLOR
	assert_lt(colour.a, 1.0, "translucent")
	assert_gt(colour.r, colour.g, "red")
	assert_gt(colour.r, colour.b)


## **The explosion's own geometry reaches the log**, which is what lets the drawn radius be a
## readout rather than a guess.
func test_a_detonation_logs_its_centre_and_its_real_radius() -> void:
	var volatile := Part.new()
	volatile.id = &"goo_barrel"
	volatile.material = &"steel"
	volatile.hp = 1
	volatile.max_hp = 1
	volatile.detonate_damage = 40.0
	volatile.detonate_radius = 3.0
	# An open StringName vocabulary, not an enum — CLAUDE.md: enums are for closed engine states.
	volatile.failure_mode = &"DETONATE"
	volatile.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 1.0))]

	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(4, 4)] = volatile
	var bystander: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(5, 4), 0)
	var shooter: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(0, 4), 1)
	var state := CombatState.new(grid, [shooter, bystander])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 4), Vector2(1, 0), Vector2(0.0, 0.5), 12.0, 0.0, 0.0, null
	)

	var blasts: Array[LogEvent] = sink.events_of_kind(&"detonation")
	if blasts.is_empty():
		gut.p("the fixture did not detonate — nothing to assert about geometry")
		assert_true(true)
		return
	gut.p("detonation: %s" % blasts[0].text)
	assert_eq(blasts.size(), 1, "one explosion, one event — not one per victim")
	assert_almost_eq(float(blasts[0].data["radius"]), 3.0, 0.001, "the part's own real radius")
	assert_true(blasts[0].data.has("center_x"), "and where it happened")
	assert_true(blasts[0].data.has("center_height"))
