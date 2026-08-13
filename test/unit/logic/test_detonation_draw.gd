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

## The muzzle height the shot is fired from. **tb68 Pass D: this used to be left at
## `resolve_and_log_point`'s own `origin_height` default of 0.0**, which puts the ray exactly on
## the ground plane, tangent to the bottom face of every box in its path — the barrel's own box
## starts at y 0.0, and so do the reference humanoid's legs. The shot hit **nothing at all**, and
## the assertion it fed was skipped by an `if blasts.is_empty(): assert_true(true); return`, so
## the file reported green while resolving a miss. Swept: 0.0 and 0.9 hit nothing, 0.3 hits but
## does not destroy, **0.5 detonates**.
const MUZZLE_HEIGHT := 0.5


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


## Fires one shot into whatever `volatile` is, placed at (4, 4), and returns the `detonation`
## events the combat log saw. Shared by the synthetic case and the real-barrel case below so the
## two differ only in the part, which is the whole comparison.
func _detonation_events(volatile: Part) -> Array[LogEvent]:
	var grid := Grid.new(10, 10)
	grid.place_blocker(Vector2i(4, 4), volatile)
	var bystander: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(5, 4), 0)
	var shooter: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(0, 4), 1)
	var state := CombatState.new(grid, [shooter, bystander])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state,
		shooter,
		Vector2(0, 4),
		Vector2(1, 0),
		Vector2(0.0, 0.5),
		12.0,
		0.0,
		0.0,
		null,
		false,
		0.0,
		MUZZLE_HEIGHT
	)
	return sink.events_of_kind(&"detonation")


## **The explosion's own geometry reaches the log**, which is what lets the drawn radius be a
## readout rather than a guess.
##
## **tb68 Pass D: this fixture used to be called `goo_barrel` and was not one.** It authored
## radius 3.0, `detonate_damage` 40.0 and material `steel` where the game's `goo_barrel` is 2.0,
## 12.0 and `reactive` — so the assertion "the part's own real radius" named a barrel that could
## not occur. The distinctive radius is worth keeping (2.0 could coincide with a hardcoded
## default; 3.0 cannot), so what changed is the **claim**: the id no longer borrows a real
## part's name, and the figure is read back off the part rather than restated as a literal.
## `test_the_real_goo_barrels_own_radius_is_what_gets_logged` covers the game's own part.
func test_a_detonation_logs_its_centre_and_its_authored_radius() -> void:
	var volatile := Part.new()
	volatile.id = &"test_volatile"
	volatile.material = &"steel"
	volatile.hp = 1
	volatile.max_hp = 1
	volatile.detonate_damage = 40.0
	volatile.detonate_radius = 3.0
	# An open StringName vocabulary, not an enum — CLAUDE.md: enums are for closed engine states.
	volatile.failure_mode = &"DETONATE"
	volatile.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 1.0))]

	var blasts: Array[LogEvent] = _detonation_events(volatile)
	assert_false(blasts.is_empty(), "the fixture must actually detonate or this asserts nothing")
	if blasts.is_empty():
		return
	gut.p("detonation: %s" % blasts[0].text)
	assert_eq(blasts.size(), 1, "one explosion, one event — not one per victim")
	assert_almost_eq(
		float(blasts[0].data["radius"]),
		volatile.detonate_radius,
		0.001,
		"the radius travelling in the log is the part's own, read back off the part"
	)
	assert_true(blasts[0].data.has("center_x"), "and where it happened")
	assert_true(blasts[0].data.has("center_height"))


## **The same claim against the part the game actually ships** (tb68 Pass D).
##
## The test above proves a detonation logs *its part's* radius using a synthetic barrel whose
## radius is distinctive. This one proves the game's own `goo_barrel` reaches the log intact —
## `DataLibrary`'s part, its authored `detonate_radius`, no literal in the assertion. Between
## them: a value that could not be a coincidence, and a value that is real.
func test_the_real_goo_barrels_own_radius_is_what_gets_logged() -> void:
	var barrel: Part = DataLibrary.get_part(&"goo_barrel")
	assert_not_null(barrel, "the game must still ship a goo_barrel")
	if barrel == null:
		return
	assert_eq(barrel.failure_mode, &"DETONATE", "sanity: it is still the part that explodes")

	var blasts: Array[LogEvent] = _detonation_events(barrel.duplicate(true))
	assert_false(blasts.is_empty(), "the real barrel must actually detonate under this shot")
	if blasts.is_empty():
		return
	gut.p("real goo_barrel detonation: %s" % blasts[0].text)
	assert_almost_eq(
		float(blasts[0].data["radius"]),
		barrel.detonate_radius,
		0.001,
		"the shipped part's own radius, not a number this test chose"
	)


## **`BR51.20`: zeroing a part actually fails it.**
##
## `set_part_hp` set the number and stopped — `resolve_part_failure` is the only thing that runs
## a failure mode and it had exactly one caller, inside impact resolution. So a goo barrel forced
## to 0 hp sat there intact, and forcing a detonation — the entire point of being able to target
## a barrel (`BR51.02`) — never worked.
##
## **This is a synthetic failure, not the real interaction.** The supervisor's own point: what
## matters is a barrel getting shot, and this forces the consequence without the cause. It makes
## the consequence observable; it does not verify the shot path.
func _barrel() -> Part:
	var volatile := Part.new()
	volatile.id = &"goo_barrel"
	volatile.material = &"steel"
	volatile.hp = 4
	volatile.max_hp = 4
	volatile.detonate_damage = 40.0
	volatile.detonate_radius = 3.0
	volatile.failure_mode = &"DETONATE"
	volatile.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 1.0))]
	return volatile


func test_zeroing_a_barrels_hp_detonates_it() -> void:
	var grid := Grid.new(10, 10)
	grid.place_blocker(Vector2i(4, 4), _barrel())
	var bystander: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(5, 4), 0)
	var state := CombatState.new(grid, [bystander])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_part_hp(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(4, 4)}, &"", 0
	)

	assert_true(ok, "the verb applied")
	var blasts: Array[LogEvent] = sink.events_of_kind(&"detonation")
	assert_eq(blasts.size(), 1, "zeroing it set it off")
	gut.p("forced: %s" % blasts[0].text)
	assert_almost_eq(float(blasts[0].data["radius"]), 3.0, 0.001, "at its own real radius")
	assert_lt(bystander.shell.root.hp, bystander.shell.root.max_hp, "and it hurt the bystander")


## **Above zero it must not fail.** A verb that detonated a barrel while merely wounding it would
## be worse than one that never detonated it at all.
func test_setting_a_barrel_above_zero_does_not_detonate_it() -> void:
	var grid := Grid.new(10, 10)
	grid.place_blocker(Vector2i(4, 4), _barrel())
	var state := CombatState.new(grid, [] as Array[Unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BoutInjector.new(state).set_part_hp(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(4, 4)}, &"", 2
	)

	assert_eq(sink.events_of_kind(&"detonation").size(), 0, "wounded, not destroyed")


## **`BR51.22`: cover takes the blast, and a chain never re-explodes anything.**
##
## Supervisor-specified: *"Chain reactions chain react simultaneously, then in order, they should
## never re-explode something that's already exploded."* `detonate` iterated `state.units` and
## nothing else, so a barrel beside a barrel could not chain at all.
func test_a_barrel_detonates_its_neighbour_exactly_once() -> void:
	var grid := Grid.new(12, 12)
	grid.place_blocker(Vector2i(4, 4), _barrel())
	grid.place_blocker(Vector2i(6, 4), _barrel())
	var state := CombatState.new(grid, [] as Array[Unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BoutInjector.new(state).set_part_hp(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(4, 4)}, &"", 0
	)

	var blasts: Array[LogEvent] = sink.events_of_kind(&"detonation")
	for blast: LogEvent in blasts:
		gut.p("chain: %s" % blast.text)
	assert_eq(blasts.size(), 2, "the first set off the second — and neither went off twice")


## **Termination is the exploded set, not a depth cap.** Two barrels in range of each other are
## the case that loops forever without it, and a depth limit would merely bound the loop rather
## than honour "never re-explode something that's already exploded".
func test_two_barrels_in_range_of_each_other_do_not_loop() -> void:
	var grid := Grid.new(12, 12)
	grid.place_blocker(Vector2i(4, 4), _barrel())
	grid.place_blocker(Vector2i(5, 4), _barrel())
	var state := CombatState.new(grid, [] as Array[Unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BoutInjector.new(state).set_part_hp(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(4, 4)}, &"", 0
	)

	assert_eq(sink.events_of_kind(&"detonation").size(), 2, "each barrel went off exactly once")


## **`BR51.23`: a mounted part explodes where it is, not at its wearer's feet.**
func test_a_part_on_a_unit_detonates_at_its_own_position() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var carrier: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(5, 5), 0)
	# **A sub-part, not the root.** The shell root legitimately sits at the unit's base, so using
	# it would have passed on the broken version too — the defect only shows on a part mounted
	# somewhere up the socket chain, which is exactly the ammo-rack case reported.
	var rack: Part = null
	for candidate: Part in carrier.shell.all_parts():
		if candidate != carrier.shell.root and not candidate.volume.is_empty():
			rack = candidate
			break
	assert_not_null(rack, "the reference humanoid has a mounted part to use")
	rack.detonate_damage = 5.0
	rack.detonate_radius = 1.0
	rack.failure_mode = &"DETONATE"
	var state := CombatState.new(grid, [carrier])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	DamageResolver.resolve_part_failure(rack, state, null)

	var blasts: Array[LogEvent] = sink.events_of_kind(&"detonation")
	assert_eq(blasts.size(), 1)
	gut.p("mounted: %s" % blasts[0].text)
	assert_gt(
		float(blasts[0].data["center_height"]),
		0.0,
		"a part carried on a body is above the floor it stands on"
	)
