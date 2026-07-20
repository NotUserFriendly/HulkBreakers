extends GutTest

## taskblock-24 Pass C: "the AI can consider overwatch (un-stranding the
## class)" — split out from test_unit_ai.gd (which was already near its own
## line/method-count lint caps) rather than raising either limit.


## Mirrors test_overwatch.gd's own `_make_overwatcher` (torso -[WRIST]-
## hand(TRIGGER) -[GRIP]- weapon) exactly — two load-bearing details, both
## already established there: `UnitGeometry.muzzle_point`'s own placement
## math specifically depends on a WRIST socket (a GRIP-via-HAND unit never
## resolves a real muzzle point, so `Overwatch._torso_visible` silently
## reads false for every candidate regardless of geometry); and the torso
## deliberately has NO `.volume` of its own — an overwatcher WITH real
## body geometry self-blocks its own ray (`ShotPlane.resolve_ray`, unlike
## `AttackAction`'s own cascade, never excludes the caster's own body), so
## every pre-existing overwatch fixture in this codebase leaves it bare.
func _overwatch_capable_unit(
	id: StringName, cell: Vector2i, squad_id: int, weapon_id: StringName, weapon_ap_cost: int = 1
) -> Unit:
	var weapon := Part.new()
	weapon.id = weapon_id
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = weapon_ap_cost
	weapon.provides_actions = [&"shoot", &"overwatch"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 15.0
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [wrist]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


func _target(id: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


## A clear, open field — no cover, no ally, nothing physically obstructing
## the shot in either direction: distance exactly MARKSMAN's own
## preferred_range (7), so `_pick_engagement_position` finds no reachable
## cell that improves on standing still, and `self_unit` starts already
## facing the enemy (well within the 30-degree overwatch arc). The
## weapon's own `ap_cost` (5) genuinely exceeds `self_unit`'s own AP (3) —
## a real shot is unaffordable this turn — while `OverwatchAction`'s own
## flat 1-AP declare cost still is. This is "can't improve my shot by
## moving/firing" for a real, on-topic mechanical reason, not a physical
## obstruction that would ALSO block overwatch's own real geometric
## trigger check the same way an ally standing in the exact same firing
## line would.
func _unaffordable_shot_scene(weapon_ap_cost: int = 5) -> Dictionary:
	var grid := Grid.new(20, 20)
	var self_unit := _overwatch_capable_unit(
		&"self_unit", Vector2i(0, 0), 0, &"rifle", weapon_ap_cost
	)
	self_unit.ap = 3
	self_unit.max_ap = 3
	self_unit.orientation = FaceAction.orientation_toward(Vector2i(0, 0), Vector2i(7, 0))
	var enemy := _target(&"enemy", Vector2i(7, 0), 1)
	var state := CombatState.new(grid, [self_unit, enemy])
	return {"state": state, "self_unit": self_unit, "enemy": enemy}


## C2: "a MARKSMAN with no improving move and an enemy likely to advance
## queues overwatch" — a real shot is unaffordable this turn (AP), no
## reachable cell improves the standoff either, but the enemy is already
## within real arc/range/LoS — holding overwatch is strictly better than
## wasting the turn.
func test_a_marksman_with_no_improving_move_and_a_threatened_enemy_queues_overwatch() -> void:
	var scene: Dictionary = _unaffordable_shot_scene()
	var self_unit: Unit = scene.self_unit

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, scene.state, null, &"MARKSMAN")

	# docs/09 golden rule: TACTICS queues intents and mutates nothing --
	# `self_unit.overwatch_weapon_id` only changes for real once RESOLUTION
	# actually applies the queue, not from planning it; the queued action's
	# OWN weapon_id is the thing to check here.
	var overwatch_action: OverwatchAction = null
	for action: CombatAction in queue.actions:
		if action is OverwatchAction:
			overwatch_action = action
	assert_not_null(
		overwatch_action,
		"nothing better to do, and the enemy is already threatened -- must hold overwatch"
	)
	assert_eq(overwatch_action.weapon_id, &"rifle")


## C2: "an AGGRESSIVE unit never overwatches" — the EXACT same scenario
## the MARKSMAN test above turns into overwatch, under the default
## playstyle, must still just hold/face, never overwatch.
func test_an_aggressive_unit_never_overwatches_the_same_scenario() -> void:
	var scene: Dictionary = _unaffordable_shot_scene()
	var self_unit: Unit = scene.self_unit

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, scene.state, null, &"AGGRESSIVE")

	assert_false(
		queue.actions.any(func(a: CombatAction) -> bool: return a is OverwatchAction),
		"AGGRESSIVE closes and fires, it never waits"
	)


## C2: "a unit whose weapon doesn't provide overwatch can't (catalog-
## gated)" — same scenario, same MARKSMAN playstyle, but the weapon never
## opted into providing &"overwatch" (only &"shoot") — must fall back to
## holding, never invent an action the weapon doesn't provide.
func test_a_marksman_whose_weapon_doesnt_provide_overwatch_cannot_overwatch() -> void:
	var scene: Dictionary = _unaffordable_shot_scene()
	var self_unit: Unit = scene.self_unit
	self_unit.shell.find_part(&"rifle").provides_actions = [&"shoot"]

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, scene.state, null, &"MARKSMAN")

	assert_false(
		queue.actions.any(func(a: CombatAction) -> bool: return a is OverwatchAction),
		"the weapon never provides overwatch -- catalog-gated, not a bot-type assumption"
	)


## A weaponless unit can't overwatch either, for the same catalog reason
## (no part anywhere provides it) — not a special case, the general one.
func test_a_weaponless_marksman_cannot_overwatch() -> void:
	var grid := Grid.new(20, 20)
	var self_unit := _target(&"self_unit", Vector2i(0, 0), 0)
	var enemy := _target(&"enemy", Vector2i(7, 0), 1)
	var state := CombatState.new(grid, [self_unit, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"MARKSMAN")

	assert_false(queue.actions.any(func(a: CombatAction) -> bool: return a is OverwatchAction))


## C2: overwatch choice must be exactly as deterministic as every other AI
## decision — same seed and setup, same choice, twice.
func test_overwatch_choice_is_deterministic_per_seed() -> void:
	var results: Array[bool] = []
	for run in range(2):
		var scene: Dictionary = _unaffordable_shot_scene()
		var self_unit: Unit = scene.self_unit

		var queue: ActionQueue = UnitAI.plan_turn(self_unit, scene.state, null, &"MARKSMAN")
		results.append(
			queue.actions.any(func(a: CombatAction) -> bool: return a is OverwatchAction)
		)

	assert_eq(results[0], results[1])
	assert_true(results[0], "sanity: this fixture must actually produce overwatch to be meaningful")
