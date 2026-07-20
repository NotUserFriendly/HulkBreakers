extends GutTest

## taskblock-24 Pass D: "the invariant guard (anti-regression rail)" — the
## point of the whole taskblock is that player and AI choose actions
## through the SAME seam (`ActionCatalog`). These tests lock that down so
## it can't silently drift again: the AI's own constructable actions are
## always a SUBSET of what `ActionCatalog.actions_for()` offers for that
## same unit — never invented past what a part actually provides, never a
## hardcoded one left behind once the catalog itself would refuse it.


## Maps a queued CombatAction back to the action id `ActionCatalog` would
## have offered it under — the same shoot/saw -> AttackAction, burst ->
## OverwatchAction... mapping `ActionCatalog.build_firing_action`'s own
## match uses, inverted. `null` for a universal, non-part-provided action
## (Move/Face/EndTurn/Hold/Shutdown/Gather/Extract) — those are correctly
## exempt from this invariant (docs: "universal actions... are correctly
## hardcoded, they're not part-provided, every unit has them").
func _provided_action_id_for(action: CombatAction) -> Variant:
	if action is BurstAction:
		return &"burst"
	if action is OverwatchAction:
		return &"overwatch"
	if action is AttackAction:
		# taskblock-24 Pass A: &"shoot" and &"saw" both construct a plain
		# AttackAction — either is a legitimate match; a fixture that
		# provides one or the other (never both under the same weapon_id)
		# still satisfies the subset property as long as AT LEAST one of
		# them is genuinely offered.
		return [&"shoot", &"saw"]
	return null


## The core guard: every part-provided action `UnitAI.plan_turn` actually
## queues for `unit` must be something `ActionCatalog.actions_for(unit)`
## really offers — never a hardcoded action surviving past what the
## catalog would refuse.
func _assert_every_queued_action_is_catalog_offered(unit: Unit, queue: ActionQueue) -> void:
	var offered: Array[StringName] = []
	for def: ActionDef in ActionCatalog.actions_for(unit):
		offered.append(def.id)
	for action: CombatAction in queue.actions:
		var expected: Variant = _provided_action_id_for(action)
		if expected == null:
			continue  # a universal action -- exempt, not part-provided
		if expected is Array:
			assert_true(
				(expected as Array).any(func(id: StringName) -> bool: return id in offered),
				(
					"%s must match something ActionCatalog actually offers: %s"
					% [action.describe(), offered]
				)
			)
		else:
			assert_true(
				expected in offered,
				(
					"%s must be something ActionCatalog actually offers: %s"
					% [action.describe(), offered]
				)
			)


func _weapon(weapon_id: StringName, provides: Array[StringName], ap_cost: int = 1) -> Part:
	var weapon := Part.new()
	weapon.id = weapon_id
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = ap_cost
	weapon.provides_actions = provides
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 15.0
	if &"burst" in provides:
		weapon.weapon_def.burst_size = 6
	weapon.scatter = [Ring.new(0.1, 1.0)]
	return weapon


## torso -[WRIST]- hand(TRIGGER) -[GRIP]- weapon — the WRIST shape every
## real overwatch-capable fixture in this codebase needs
## (UnitGeometry.muzzle_point depends on it); harmless for the
## shoot/burst-only fixtures below too, which never touch overwatch.
func _unit_with_weapon(id: StringName, cell: Vector2i, squad_id: int, weapon: Part) -> Unit:
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
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
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


## "the AI's constructable actions subset ActionCatalog's offered
## actions for the same unit" — checked across a representative spread of
## provides_actions shapes (shoot-only, burst-only, both, overwatch+shoot,
## and no weapon at all), each planned for every playstyle so overwatch
## consideration is exercised too.
func test_the_ai_never_constructs_an_action_the_catalog_wouldnt_also_offer() -> void:
	var fixtures: Array = [
		[&"pistol", [&"shoot"] as Array[StringName]],
		[&"chaingun", [&"burst"] as Array[StringName]],
		[&"auto_shotgun", [&"shoot", &"burst"] as Array[StringName]],
		[&"rifle", [&"shoot", &"overwatch"] as Array[StringName]],
	]
	for fixture: Array in fixtures:
		var weapon_id: StringName = fixture[0]
		var provides: Array[StringName] = fixture[1]
		for playstyle: StringName in [&"AGGRESSIVE", &"SKIRMISHER", &"MARKSMAN", &"COVER_SEEKER"]:
			var weapon: Part = _weapon(weapon_id, provides)
			var self_unit := _unit_with_weapon(&"self_unit", Vector2i(0, 0), 0, weapon)
			var enemy := _target(&"enemy", Vector2i(6, 0), 1)
			var state := CombatState.new(Grid.new(15, 15), [self_unit, enemy])

			var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, playstyle)

			_assert_every_queued_action_is_catalog_offered(self_unit, queue)

	# The weaponless case: no part provides anything at all.
	var bare_unit := _target(&"bare", Vector2i(0, 0), 0)
	var bare_enemy := _target(&"enemy", Vector2i(6, 0), 1)
	var bare_state := CombatState.new(Grid.new(15, 15), [bare_unit, bare_enemy])
	var bare_queue: ActionQueue = UnitAI.plan_turn(bare_unit, bare_state, null, &"MARKSMAN")
	_assert_every_queued_action_is_catalog_offered(bare_unit, bare_queue)


## The other half of the subset property: a weapon that provides an action
## id `UnitAI`/`ActionCatalog.build_firing_action` doesn't even recognize
## (a hypothetical future `&"mag_dump"`, say) must never make the AI
## invent an action for it — it's simply invisible to the AI's own firing/
## overwatch machinery today, exactly as `ActionCatalog.build_firing_action`
## returning null for an unrecognized id already guarantees.
func test_an_unrecognized_provided_action_is_never_invented_by_the_ai() -> void:
	var weapon: Part = _weapon(&"prototype_launcher", [&"mag_dump"])
	var self_unit := _unit_with_weapon(&"self_unit", Vector2i(0, 0), 0, weapon)
	var enemy := _target(&"enemy", Vector2i(6, 0), 1)
	var state := CombatState.new(Grid.new(15, 15), [self_unit, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"MARKSMAN")

	var fires_or_overwatches := func(a: CombatAction) -> bool:
		return a is AttackAction or a is BurstAction or a is OverwatchAction
	assert_false(
		queue.actions.any(fires_or_overwatches),
		"a weapon providing only an id the AI doesn't recognize must never fire or overwatch"
	)


## Corollary: "adding a new provided action to a part surfaces it to BOTH
## the player bar and the AI's consideration set with no AI code change."
## `&"repair"` (taskblock-22 Pass E, already a registered ActionDef) is
## the clean, already-real proof: none of this taskblock's own new
## UnitAI code (firing, overwatch) has ANY idea `&"repair"` exists —
## no `&"repair"` string appears anywhere in unit_ai.gd — yet a part
## providing it surfaces through `ActionCatalog.actions_for()` regardless,
## because that seam was never AI-specific to begin with. Wiring an
## actual when-to-repair DECISION is explicitly out of this taskblock's
## own scope (taskblock24.md: "AI repair... deferred, not fixed here");
## this only proves the AI is no longer BLIND to it, exactly the
## distinction the taskblock itself draws.
func test_a_newly_provided_action_surfaces_to_the_catalog_with_no_ai_code_change() -> void:
	var weapon: Part = _weapon(&"arc_welder", [&"shoot", &"repair"])
	var self_unit := _unit_with_weapon(&"self_unit", Vector2i(0, 0), 0, weapon)

	var offered: Array[StringName] = []
	for def: ActionDef in ActionCatalog.actions_for(self_unit):
		offered.append(def.id)

	assert_true(
		&"repair" in offered,
		(
			"a provided action UnitAI has no firing/overwatch-specific handling for at all must still"
			+ " surface through the SAME catalog seam"
		)
	)
