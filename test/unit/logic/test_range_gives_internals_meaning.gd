extends GutTest

## taskblock-20 Pass G: "threading a shot to an internal is still a shot —
## it obeys the range accuracy band (tb19 C). No new range code here — just
## confirm internal aim runs through the same accuracy pipeline tb19 built,
## not a bypass." Every claim here is read off real
## `RangeModel`/`Dartboard`/`AttackAction` calls (CLAUDE.md: never re-derive
## a second copy of the same formula) — a live probe found the exact
## deviation numbers below (same rng seed, same aim_point, only the range
## band's own radius_multiplier differs) before this file was written.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _built(shooter_distance: int) -> Dictionary:
	var torso: Part = DataLibrary.get_part(&"torso")
	var reactor: Part = DataLibrary.get_part(&"reactor")
	PartGraph.attach(reactor, torso, PartGraph.find_free_socket(torso, &"BACK"))

	var shooter := Unit.new(
		Matrix.new(), Shell.new(DataLibrary.get_part(&"torso")), Vector2i(0, shooter_distance)
	)
	var target := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(40, 40), [shooter, target])
	return {"shooter": shooter, "target": target, "reactor": reactor, "state": state}


func _aim_point_and_offset(built: Dictionary) -> Dictionary:
	var shooter: Unit = built.shooter
	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(built.target.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), built.state)
	var offset: Variant = InternalTargeting.aim_offset_for(
		built.state, shooter, built.target, built.reactor, plane
	)
	return {"offset": offset, "aim_point": ShotPlane.center_of(plane, built.target) + offset}


## "an internal-targeting shot beyond effective range suffers the same
## accuracy penalty as any other shot at that range" — sniper_rifle:
## effective_range 20, max_range 30 (cells). Same seed, same known
## aim_point; only the range band differs, so any difference in where the
## round actually lands is attributable to the accuracy pipeline alone.
func test_a_known_position_aim_scatters_wider_beyond_effective_range() -> void:
	var built: Dictionary = _built(20)
	var aimed: Dictionary = _aim_point_and_offset(built)
	var weapon: Part = DataLibrary.get_part(&"sniper_rifle")

	var effective_scale: float = RangeModel.dartboard_radius_scale(weapon, 20)
	var degraded_scale: float = RangeModel.dartboard_radius_scale(weapon, 29)
	assert_gt(degraded_scale, effective_scale, "sanity: tb19's own accuracy band actually degrades")

	var rng_at_effective := RandomNumberGenerator.new()
	rng_at_effective.seed = 777
	var rng_at_degraded := RandomNumberGenerator.new()
	rng_at_degraded.seed = 777
	var scatter_effective: Array[Ring] = Dartboard.resolve_scatter(weapon, [], effective_scale)
	var scatter_degraded: Array[Ring] = Dartboard.resolve_scatter(weapon, [], degraded_scale)
	var point_effective: Vector2 = (
		Dartboard.sample(aimed.aim_point, scatter_effective, rng_at_effective, 1)[0]
	)
	var point_degraded: Vector2 = (
		Dartboard.sample(aimed.aim_point, scatter_degraded, rng_at_degraded, 1)[0]
	)

	var deviation_effective: float = (point_effective - aimed.aim_point).length()
	var deviation_degraded: float = (point_degraded - aimed.aim_point).length()
	assert_gt(
		deviation_degraded,
		deviation_effective,
		"the same known-position aim drifts farther from its own target at degraded range"
	)


## "internal aim uses the tb19 accuracy pipeline, not a separate path" —
## AttackAction.is_legal's own range gate (RangeModel.is_in_max_range) reads
## `range_cells` from the shooter/target CELLS alone; a non-zero aim_offset
## from a known-internal aim must never change what range band a shot is
## judged against.
func test_a_known_position_aim_offset_never_changes_the_range_band_a_shot_is_judged_against(
) -> void:
	var built: Dictionary = _built(30)  # exactly at sniper_rifle's own max_range
	var aimed: Dictionary = _aim_point_and_offset(built)
	var shooter: Unit = built.shooter
	var target: Unit = built.target
	var socket := Socket.new(&"GRIP")
	shooter.shell.root.sockets.append(socket)
	socket.occupant = DataLibrary.get_part(&"sniper_rifle")
	var hand := Part.new()
	hand.id = &"hand"
	hand.capabilities = [&"TRIGGER"]
	var hand_socket := Socket.new(&"HAND")
	shooter.shell.root.sockets.append(hand_socket)
	hand_socket.occupant = hand
	shooter.ap = 10

	var default_shot := AttackAction.new(shooter, &"sniper_rifle", target.cell)
	var known_position_shot := AttackAction.new(shooter, &"sniper_rifle", target.cell, aimed.offset)

	assert_eq(
		default_shot.is_legal(built.state),
		known_position_shot.is_legal(built.state),
		"legal-at-max-range for one must mean legal-at-max-range for the other"
	)

	# One cell past max_range: both must now be illegal, the offset changes
	# nothing about the range gate itself.
	var built_beyond: Dictionary = _built(31)
	var aimed_beyond: Dictionary = _aim_point_and_offset(built_beyond)
	var shooter_beyond: Unit = built_beyond.shooter
	var socket_beyond := Socket.new(&"GRIP")
	shooter_beyond.shell.root.sockets.append(socket_beyond)
	socket_beyond.occupant = DataLibrary.get_part(&"sniper_rifle")
	var hand_beyond := Part.new()
	hand_beyond.id = &"hand"
	hand_beyond.capabilities = [&"TRIGGER"]
	var hand_socket_beyond := Socket.new(&"HAND")
	shooter_beyond.shell.root.sockets.append(hand_socket_beyond)
	hand_socket_beyond.occupant = hand_beyond
	shooter_beyond.ap = 10

	var default_shot_beyond := AttackAction.new(
		shooter_beyond, &"sniper_rifle", built_beyond.target.cell
	)
	var known_position_shot_beyond := AttackAction.new(
		shooter_beyond, &"sniper_rifle", built_beyond.target.cell, aimed_beyond.offset
	)
	assert_false(default_shot_beyond.is_legal(built_beyond.state))
	assert_false(known_position_shot_beyond.is_legal(built_beyond.state))
