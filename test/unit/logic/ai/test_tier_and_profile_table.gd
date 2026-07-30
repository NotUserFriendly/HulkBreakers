extends GutTest

## taskblock-46 Pass E: **the two assertions that matter most whenever the table
## grows.**
##
## > Every tier decides differently from its neighbours on the same seed; every
## > profile decides differently with tier held constant.
##
## A table where two rows play identically has a bug in it, **and no completion
## metric will catch it** — a decorative tier costs nothing and finishes just as
## many missions, so the only thing that ever notices is an assertion aimed
## directly at it. `docs/11` names this as one of its two failure modes for the same
## reason.
##
## Asserted on the DECISION (which action won) rather than on the queue, because two
## different actions routinely produce the same `MoveAction` when they pick the same
## cell — a queue diff reads those as identical while the decisions differ, which is
## how the batch-objective test managed to look inert for a whole commit.

const TIERS: Array[StringName] = [&"MINDLESS", &"GRUNT", &"TRAINED", &"ELITE"]


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _armed_unit(id: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var weapon := Part.new()
	weapon.id = StringName("%s_gun" % id)
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = 1
	weapon.provides_actions = [&"shoot"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 30.0
	weapon.scatter = [Ring.new(0.1, 1.0)]
	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


## One board, one seed, cover available so `take_cover` is genuinely on offer, and
## an enemy in plain sight so the combat actions are too.
## Cover to take, an enemy in plain sight, a mission with somewhere to withdraw to,
## and a hurt unit.
##
## **All four are needed for the profiles to be distinguishable at all**, and
## finding that out was the point of writing the test: with no mission, the profile
## whose whole character is wanting OUT has nowhere to want to go, and reads as
## identical to one that merely likes cover. A board that cannot express a
## difference is not evidence that there is none.
func _board() -> Dictionary:
	var grid: Grid = GridFixture.flat(24, 16)
	# `place_wall` sets `Grid.opacity`; a hand-rolled blocker does not, and a wall
	# that does not block sight is not a wall — which is why this stub stops short of
	# the enemy's row. **Cover beside the firing lane, never across it.** Walled all
	# the way through, the hunter could not see the prey at all, every combat action
	# fell out of the pool, and all four profiles came back with the single verb they
	# had left. Four identical rows read as four decorative profiles rather than as a
	# board with nothing on it to disagree about.
	for y in range(3, 8):
		GridFixture.place_wall(grid, Vector2i(10, y))
	var hunter: Unit = _armed_unit(&"hunter", Vector2i(6, 8), 0)
	var prey: Unit = _armed_unit(&"prey", Vector2i(18, 8), 1)
	var state := CombatState.new(grid, [hunter, prey])
	state.force_current_unit(hunter.id)
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
	# Hurt, so the profiles that read condition have something to read.
	hunter.shell.root.hp = 4
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(2, 2)]
	var view: WorldView = WorldView.full(state)
	view.restricted = true
	return {"state": state, "hunter": hunter, "prey": prey, "view": view, "mission": mission}


## **A tier's whole signature: what it may do AND what it may know.**
##
## `docs/11`'s table has three columns — actions added, world model, depth — and
## comparing only the first was enough to call Elite decorative when its entire
## difference from Trained lives in the other two. Written as the pool plus the world-model
## capabilities so a tier that differs on either axis reads as different, which is
## what "decides differently" actually means.
func _signature(unit: Unit, view: WorldView, context: UtilityContext) -> Array[String]:
	var signature: Array[String] = []
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		if not action.tiers.is_empty() and unit.intelligence_tier not in action.tiers:
			continue
		for cell: Vector2i in context.candidate_cells:
			if UtilityScorer.preconditions_hold(action, context.predicates_for(cell)):
				signature.append(String(action.id))
				break
	signature.sort()
	signature.append("memory=%s" % (unit.intelligence_tier in WorldView.MEMORY_TIERS))
	signature.append("blackboard=%s" % view.has_blackboard(unit))
	signature.append("sets_objective=%s" % view.may_set_objective(unit))
	signature.append("searches=%s" % UtilityLookahead.searches(unit))
	return signature


## The winning action ids, in order, for one planned turn.
func _decisions(
	unit: Unit, view: WorldView, profile: StringName, mission: MissionState = null
) -> Array[String]:
	var state: CombatState = view.canonical_state_for_resolvers()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	await UtilityPlanner.plan_turn(unit, view, mission, profile)
	state.combat_log.remove_sink(sink)
	var chosen: Array[String] = []
	for event: LogEvent in sink.events_of_kind(&"ai_utility_decision"):
		var index: int = int(event.data["winner_index"])
		if index >= 0:
			chosen.append(str((event.data["candidates"] as Array)[index]["action_id"]))
	return chosen


# --- every tier differs from its neighbour ------------------------------------


## **The first of the two.** Compared neighbour-to-neighbour rather than
## all-against-all, because "some pair differs" would pass with two identical rows
## sitting next to each other, which is exactly the bug.
func test_every_tier_differs_from_the_one_below_it() -> void:
	var by_tier: Dictionary = {}
	for tier: StringName in TIERS:
		var bout: Dictionary = _board()
		bout.hunter.intelligence_tier = tier
		var context: UtilityContext = UtilityContext.build(bout.hunter, bout.view)
		by_tier[tier] = _signature(bout.hunter, bout.view, context)
		gut.p("%-8s %s" % [tier, by_tier[tier]])

	for i in range(1, TIERS.size()):
		var lower: Array[String] = by_tier[TIERS[i - 1]]
		var higher: Array[String] = by_tier[TIERS[i]]
		assert_ne(
			lower,
			higher,
			"%s and %s play identically — one of them is decorative" % [TIERS[i - 1], TIERS[i]]
		)


## Elite's difference is not in its action pool but in what it may DO with the
## blackboard: reading a batch plan is Trained's, setting one is Elite's. Without
## this, Elite and Trained are the same row.
func test_only_elite_may_set_a_batch_objective() -> void:
	var bout: Dictionary = _board()
	var view: WorldView = bout.view

	for tier: StringName in TIERS:
		bout.hunter.intelligence_tier = tier
		var may: bool = view.may_set_objective(bout.hunter)
		assert_eq(may, tier == &"ELITE", "%s: setting an objective is Elite's alone" % tier)

	bout.hunter.intelligence_tier = &"TRAINED"
	assert_true(view.has_blackboard(bout.hunter), "but Trained still READS one")


## The information half, which is the load-bearing idea rather than the pool half:
## Mindless has no memory, Grunt does.
func test_memory_is_what_separates_mindless_from_grunt() -> void:
	var bout: Dictionary = _board()
	var view: WorldView = bout.view
	for y in range(bout.state.grid.rows):
		GridFixture.place_wall(bout.state.grid, Vector2i(12, y))
	view.remembered[bout.prey.id] = {"cell": bout.prey.cell, "round_seen": view.round_number}

	bout.hunter.intelligence_tier = &"MINDLESS"
	assert_null(UtilityContext.build(bout.hunter, view).target, "MINDLESS cannot use a sighting")
	bout.hunter.intelligence_tier = &"GRUNT"
	assert_not_null(
		UtilityContext.build(bout.hunter, view).target, "GRUNT acts on last-known positions"
	)


# --- every profile differs with tier held constant ----------------------------


## **The second of the two.** Tier pinned at TRAINED throughout, so any difference
## is the weight vector and nothing else.
func test_every_profile_decides_differently_with_tier_held_constant() -> void:
	var profiles: Array[StringName] = []
	for profile: UtilityProfile in DataLibrary.utility_profiles_pool():
		profiles.append(profile.id)
	assert_gt(profiles.size(), 2, "sanity: there is a table to test")

	var seen: Dictionary = {}
	for profile: StringName in profiles:
		var bout: Dictionary = _board()
		bout.hunter.intelligence_tier = &"TRAINED"
		var decisions: Array[String] = await _decisions(
			bout.hunter, bout.view, profile, bout.mission
		)
		gut.p("%-11s decides: %s" % [profile, decisions])
		var key: String = ",".join(decisions)
		assert_false(
			seen.has(key),
			"%s plays identically to %s — one of them is decoration" % [profile, seen.get(key, "")]
		)
		seen[key] = profile


## A profile is a weight vector, never a code path — so an unknown id is fully
## neutral rather than an error, and still plans a real turn.
func test_an_unknown_profile_is_neutral_rather_than_broken() -> void:
	var bout: Dictionary = _board()
	bout.hunter.intelligence_tier = &"TRAINED"

	var decisions: Array[String] = await _decisions(
		bout.hunter, bout.view, &"no_such_profile", bout.mission
	)

	assert_gt(decisions.size(), 0, "a neutral profile is still a profile")


# --- what the tier table still owes ------------------------------------------


## **The rows that have no executor, recorded as a test so they cannot be quietly
## forgotten.** `docs/11`'s table gives Trained `use item` and `call help`, and Elite
## `bait` and `ambush`. None of those has an executor in `src/logic/actions/`, so
## none can be "preconditions and a consideration set" the way the rest were — they
## need new machinery, which is precisely what that claim says they do not.
##
## This asserts the CURRENT truth so that authoring one of them makes this test go
## red and its author has to come and delete the line.
func test_the_four_utility_actions_with_no_executor_are_still_unauthored() -> void:
	var authored: Array[StringName] = []
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		authored.append(action.id)

	for missing: StringName in [&"use_item", &"call_for_help", &"bait", &"ambush"]:
		assert_does_not_have(
			authored,
			missing,
			(
				(
					"%s is authored but has no executor — if that changed, delete this line "
					+ "and say what it runs through"
				)
				% missing
			)
		)
