extends GutTest

## taskblock-24 Pass A: "the AI fires what the weapon provides" — split out
## from test_unit_ai.gd (which hit the file's own line/method-count lint
## caps) rather than raising either limit. Same `_armed_unit` fixture
## convention as that file, unchanged.


func _armed_unit(
	id: StringName, cell: Vector2i, squad_id: int, weapon_id: StringName, torso_hp: int = 10
) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = torso_hp
	torso.max_hp = torso_hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	if weapon_id != &"":
		var weapon := Part.new()
		weapon.id = weapon_id
		weapon.hp = 3
		weapon.max_hp = 3
		weapon.attaches_to = [&"GRIP"]
		weapon.requires = {&"TRIGGER": 1}
		weapon.damage = 5.0
		weapon.ap_cost = 1
		weapon.provides_actions = [&"shoot"]
		weapon.weapon_def = WeaponDef.new()
		weapon.weapon_def.max_range = 15.0
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


## taskblock-24 Pass A: "the AI fires what the weapon provides" — a
## chaingun-shaped weapon (provides_actions == [&"burst"] only, burst_size
## > 1) must queue a real BurstAction, never fall back to a plain single
## shot the way the AI always used to before this pass.
func test_a_chaingun_wielding_ai_queues_a_burst_action_not_an_attack_action() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"chaingun")
	var weapon: Part = self_unit.shell.find_part(&"chaingun")
	weapon.provides_actions = [&"burst"]
	weapon.weapon_def.burst_size = 12
	var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"")
	var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 42)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	assert_true(
		queue.actions.any(func(a: CombatAction) -> bool: return a is BurstAction),
		"the AI must actually queue a real burst"
	)
	assert_false(
		queue.actions.any(func(a: CombatAction) -> bool: return a is AttackAction),
		"a burst-only weapon must never fall back to a plain single shot"
	)


func test_a_pistol_wielding_ai_queues_a_plain_attack_action() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"pistol")
	var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"")
	var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 42)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	assert_true(
		queue.actions.any(func(a: CombatAction) -> bool: return a is AttackAction),
		"a plain shoot-only weapon fires as an ordinary AttackAction"
	)


## B1: "prefer burst when affordable and engaging, else shoot" — an
## auto-shotgun-shaped weapon (provides both) with ample AP must prefer
## the burst.
func test_an_auto_shotgun_ai_prefers_burst_when_it_can_afford_it() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"auto_shotgun")
	var weapon: Part = self_unit.shell.find_part(&"auto_shotgun")
	weapon.provides_actions = [&"shoot", &"burst"]
	weapon.weapon_def.burst_size = 3
	var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"")
	var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 42)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	assert_true(
		queue.actions.any(func(a: CombatAction) -> bool: return a is BurstAction),
		"burst is affordable and engaging -- the AI must prefer it over a plain shot"
	)


## B1's own fallback half: when burst genuinely can't be afforded (AP too
## low), the SAME weapon must still fire, just as a plain shot instead.
func test_an_auto_shotgun_ai_falls_back_to_shoot_when_it_cannot_afford_burst() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"auto_shotgun")
	self_unit.max_ap = 1
	var weapon: Part = self_unit.shell.find_part(&"auto_shotgun")
	weapon.provides_actions = [&"shoot", &"burst"]
	weapon.weapon_def.burst_size = 3
	weapon.weapon_def.burst_ap_cost = 4
	var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"")
	var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 42)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	assert_true(
		queue.actions.any(func(a: CombatAction) -> bool: return a is AttackAction),
		"burst is unaffordable -- the AI must fall back to a plain shot"
	)
	assert_false(
		queue.actions.any(func(a: CombatAction) -> bool: return a is BurstAction),
		"burst never gets queued when it can't be afforded"
	)


## taskblock-24 Pass A: "the did-the-AI-fire detection catches bursts" —
## the exact repositioning-around-an-ally scenario
## test_an_ai_repositions_rather_than_firing_through_an_ally_in_the_line
## (test_unit_ai.gd) already proves for a plain shot, replayed with a
## burst-only weapon: `attack_fired`'s own broadened predicate
## (AttackAction OR BurstAction) must recognize the burst as a real shot,
## or the AI would incorrectly ALSO queue a superfluous HoldAction on top
## of a burst it already fired.
func test_a_repositioned_burst_is_recognized_as_having_fired_no_extra_hold() -> void:
	var grid := Grid.new(20, 20)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 10), 0, &"chaingun")
	var weapon: Part = self_unit.shell.find_part(&"chaingun")
	weapon.provides_actions = [&"burst"]
	weapon.weapon_def.burst_size = 12
	var ally := _armed_unit(&"ally", Vector2i(5, 10), 0, &"")
	var enemy := _armed_unit(&"enemy", Vector2i(10, 10), 1, &"")
	var state := CombatState.new(grid, [self_unit, ally, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	assert_true(
		queue.actions.any(func(a: CombatAction) -> bool: return a is BurstAction),
		"plenty of room to find a clear shot -- must fire a real burst, not hold"
	)
	assert_false(
		queue.actions.any(func(a: CombatAction) -> bool: return a is HoldAction),
		"a fired burst must not ALSO be treated as having done nothing"
	)


## "the AI never constructs a firing action the weapon doesn't provide" —
## a weapon damaging enough to be picked as THE weapon by `_find_weapon_id`
## but providing no firing action at all must never fire.
func test_an_ai_never_constructs_a_firing_action_the_weapon_doesnt_provide() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"decorative_prop")
	var weapon: Part = self_unit.shell.find_part(&"decorative_prop")
	weapon.provides_actions = []
	var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"")
	var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 42)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	assert_false(
		queue.actions.any(
			func(a: CombatAction) -> bool: return a is AttackAction or a is BurstAction
		),
		"a weapon that provides no firing action must never be fired"
	)
