extends GutTest

## taskblock-20 Pass H: the reaction window — tb18's existing interrupt
## STOP offering the defender a choice before the shot resolves, not a new
## resolver. Every claim here is read off real `ReactionResolver`/
## `Overwatch` calls (CLAUDE.md: never re-derive a second copy of the same
## formula) — a live probe found that `Poses.prone()` alone did NOT change
## `BodyProjector`'s own output (the ROOT pose override was a documented,
## deferred gap, closed as part of this pass) before this file was written.


func _overwatcher_with_pistol(cell: Vector2i, id: int) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]
	pistol.requires = {&"TRIGGER": 1}

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [wrist]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 0)
	unit.id = id
	return unit


func _mover(cell: Vector2i, id: int) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.5, 1.0, 0.5))]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 1)
	unit.id = id
	return unit


## "Perk-gated... default: no reactions available until perks exist." Same
## hook shape as ResolutionSpeed.action_family_bonus.
func test_available_reactions_is_empty_with_no_perk_system() -> void:
	var mover: Unit = _mover(Vector2i(0, 5), 1)
	assert_eq(ReactionResolver.available_reactions(mover), [] as Array[StringName])


func test_ignore_reaction_is_a_no_op() -> void:
	var overwatcher: Unit = _overwatcher_with_pistol(Vector2i(0, 0), 0)
	var mover: Unit = _mover(Vector2i(0, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [overwatcher, mover])
	var orientation_before: float = mover.orientation

	ReactionResolver.apply_reaction(state, mover, overwatcher, ReactionResolver.IGNORE)

	assert_true(mover.pose.overrides.is_empty(), "idle stays idle")
	assert_eq(mover.orientation, orientation_before)


func test_dive_prone_reaction_sets_the_prone_pose() -> void:
	var overwatcher: Unit = _overwatcher_with_pistol(Vector2i(0, 0), 0)
	var mover: Unit = _mover(Vector2i(0, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [overwatcher, mover])

	ReactionResolver.apply_reaction(state, mover, overwatcher, ReactionResolver.DIVE_PRONE)

	assert_eq(mover.pose.overrides, Poses.prone().overrides)


func test_turn_shield_reaction_faces_the_defender_toward_the_threat() -> void:
	var overwatcher: Unit = _overwatcher_with_pistol(Vector2i(5, 0), 0)
	var mover: Unit = _mover(Vector2i(0, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [overwatcher, mover])

	ReactionResolver.apply_reaction(state, mover, overwatcher, ReactionResolver.TURN_SHIELD)

	assert_eq(mover.orientation, FaceAction.orientation_toward(mover.cell, overwatcher.cell))


func test_an_unrecognized_reaction_id_is_also_a_no_op() -> void:
	var overwatcher: Unit = _overwatcher_with_pistol(Vector2i(0, 0), 0)
	var mover: Unit = _mover(Vector2i(0, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [overwatcher, mover])
	var orientation_before: float = mover.orientation

	ReactionResolver.apply_reaction(state, mover, overwatcher, &"nonsense")

	assert_true(mover.pose.overrides.is_empty())
	assert_eq(mover.orientation, orientation_before)


## Every reaction — including IGNORE — is logged: docs/09 "if it changed
## the world, it's in the log," and a reaction window being offered and
## resolved is real combat information regardless of which choice was made.
func test_every_reaction_is_logged_including_ignore() -> void:
	var overwatcher: Unit = _overwatcher_with_pistol(Vector2i(0, 0), 0)
	var mover: Unit = _mover(Vector2i(0, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [overwatcher, mover])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ReactionResolver.apply_reaction(state, mover, overwatcher, ReactionResolver.IGNORE)

	var events: Array[LogEvent] = sink.events_of_kind(&"reaction_taken")
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("reaction"), ReactionResolver.IGNORE)
	assert_eq(events[0].data.get("threat"), overwatcher.id)


## "run -> trigger overwatch -> PROMPT ... -> resolve": the reaction must
## apply BEFORE the shot fires, not after — proven by the shot actually
## resolving against the ALTERED (prone) geometry, not the pre-reaction
## one. `check_trigger` itself is unaffected (available_reactions is
## always [] today); this is the seam a perk-aware caller uses once it
## isn't.
func test_resolve_reaction_window_applies_the_reaction_before_firing() -> void:
	var overwatcher: Unit = _overwatcher_with_pistol(Vector2i(0, 0), 0)
	var mover: Unit = _mover(Vector2i(0, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [overwatcher, mover])
	overwatcher.overwatch_weapon_id = &"pistol"
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	Overwatch.resolve_reaction_window(
		state,
		overwatcher,
		overwatcher.shell.find_part(&"pistol"),
		mover,
		ReactionResolver.DIVE_PRONE
	)

	assert_eq(mover.pose.overrides, Poses.prone().overrides, "the reaction landed")
	var reaction_events: Array[LogEvent] = sink.events_of_kind(&"reaction_taken")
	assert_eq(reaction_events.size(), 1)
	var impact_events: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_gt(impact_events.size(), 0, "the shot still actually fired, just after the reaction")
	assert_eq(
		overwatcher.overwatch_weapon_id,
		&"",
		"the watch is still spent exactly like an unreacted trigger"
	)


## check_trigger's own real trigger path is completely unaffected by any
## of this — available_reactions is always [] today, so it still fires
## immediately, unchanged from before this pass.
func test_check_trigger_still_fires_immediately_with_no_reaction_available() -> void:
	var overwatcher: Unit = _overwatcher_with_pistol(Vector2i(0, 0), 0)
	var mover: Unit = _mover(Vector2i(0, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [overwatcher, mover])
	overwatcher.overwatch_weapon_id = &"pistol"

	var triggered: bool = Overwatch.check_trigger(state, mover)

	assert_true(triggered)
	assert_true(mover.pose.overrides.is_empty(), "no reaction ever applied — none were available")
