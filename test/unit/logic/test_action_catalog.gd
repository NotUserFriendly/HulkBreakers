extends GutTest

## taskblock-07 Pass E: ActionCatalog.actions_for(unit) — pure and
## headless-testable, same split as WeaponRows/InventoryRows: the action
## bar view only ever renders what this computes.


func _make_unit(root: Part) -> Unit:
	return Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)


func _pistol() -> Part:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 4.0
	pistol.provides_actions = [&"shoot", &"overwatch"]
	return pistol


func _hand_with_pistol() -> Part:
	var pistol: Part = _pistol()
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]
	return hand


func _saw_hand() -> Part:
	var saw := Part.new()
	saw.id = &"saw_hand"
	saw.hp = 4
	saw.max_hp = 4
	saw.attaches_to = [&"HAND"]
	saw.capabilities = [&"SUPPORT"]
	saw.provides_actions = [&"saw"]
	return saw


func _torso(sockets: Array[Socket]) -> Part:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.sockets = sockets
	return torso


## Array.map() always returns a bare Array, never Array[StringName] (the
## same pitfall as a ternary's untyped else-branch) — a plain for-loop
## avoids the "assign Array to Array[StringName]" parse error.
func _ids(actions: Array[ActionDef]) -> Array[StringName]:
	var result: Array[StringName] = []
	for action: ActionDef in actions:
		result.append(action.id)
	return result


## taskblock-07 E1/TESTS: "a shell with a pistol shows shoot and overwatch."
## Order per E2 ("by the providing part's position in the socket tree, THEN
## by action id"): both come from the one pistol, so the tiebreak is
## alphabetical — &"overwatch" sorts before &"shoot".
func test_a_shell_with_a_pistol_shows_shoot_and_overwatch() -> void:
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _hand_with_pistol()
	var unit := _make_unit(_torso([hand_socket]))

	var ids: Array[StringName] = _ids(ActionCatalog.actions_for(unit))

	assert_eq(ids, [&"overwatch", &"shoot"])


## taskblock-22 Pass E: a welder-shaped part (WELDER tag not required by
## the catalog itself — RepairAction/RepairResolver own that gate; the
## catalog only cares what `provides_actions` says) shows &"repair".
func test_a_shell_with_a_welder_shows_repair() -> void:
	var welder := Part.new()
	welder.id = &"arc_welder"
	welder.hp = 4
	welder.max_hp = 4
	welder.attaches_to = [&"GRIP"]
	welder.requires = {&"TRIGGER": 1}
	welder.provides_actions = [&"repair"]
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = welder
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var unit := _make_unit(_torso([hand_socket]))

	var ids: Array[StringName] = _ids(ActionCatalog.actions_for(unit))

	assert_has(ids, &"repair")


## taskblock-22 Pass E: "needs a PART picked from a list, never a board
## click" — repair.requires_target must be false, same posture overwatch
## already has, so arm_action's own click-driven flow leaves it alone.
func test_repair_def_never_requires_a_target() -> void:
	var by_id: Dictionary = {}
	for def: ActionDef in ActionCatalog.defs():
		by_id[def.id] = def

	assert_false(by_id[&"repair"].requires_target)


## taskblock-07 E1/TESTS: "removing the pistol removes both."
func test_removing_the_pistol_removes_shoot_and_overwatch() -> void:
	var hand: Part = _hand_with_pistol()
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var unit := _make_unit(_torso([hand_socket]))

	PartGraph.drop(unit.shell.root, (hand.sockets[0] as Socket).occupant)

	var actions: Array[ActionDef] = ActionCatalog.actions_for(unit)
	assert_eq(actions.size(), 0)


## taskblock-07 E1/TESTS: "a saw hand adds saw." Tree order: the pistol's
## own HAND_L subtree (contributing overwatch, shoot — alphabetical, as
## above) is walked before the saw hand's HAND_R subtree.
func test_a_saw_hand_adds_saw() -> void:
	var pistol_socket := Socket.new(&"HAND_L")
	pistol_socket.occupant = _hand_with_pistol()
	var saw_socket := Socket.new(&"HAND_R")
	saw_socket.occupant = _saw_hand()
	var unit := _make_unit(_torso([pistol_socket, saw_socket]))

	var ids: Array[StringName] = _ids(ActionCatalog.actions_for(unit))

	assert_eq(ids, [&"overwatch", &"shoot", &"saw"])


## taskblock-07 E1/TESTS: "an inert part contributes nothing" — docs/04
## taskblock02 D3's own fixture convention (test_inventory_rows.gd): a
## body_requires the default ladder's own tiers never grant.
func test_an_inert_part_contributes_nothing() -> void:
	var gadget: Part = _pistol()
	gadget.body_requires = [&"NEVER_GRANTED"]
	var socket := Socket.new(&"INTERNAL")
	socket.occupant = gadget
	var unit := _make_unit(_torso([socket]))

	assert_eq(
		ActionCatalog.actions_for(unit).size(),
		0,
		"an inert weapon must never put anything on the bar"
	)


## taskblock-07 E1/TESTS: "the bar's order is stable across refreshes."
func test_the_bars_order_is_stable_across_refreshes() -> void:
	var pistol_socket := Socket.new(&"HAND_L")
	pistol_socket.occupant = _hand_with_pistol()
	var saw_socket := Socket.new(&"HAND_R")
	saw_socket.occupant = _saw_hand()
	var unit := _make_unit(_torso([pistol_socket, saw_socket]))

	var first: Array[ActionDef] = ActionCatalog.actions_for(unit)
	var second: Array[ActionDef] = ActionCatalog.actions_for(unit)

	assert_eq(first.size(), second.size())
	for i in range(first.size()):
		assert_eq(first[i].id, second[i].id, "the same shell must never reshuffle between calls")


## taskblock-07 E3/TESTS: "actions_for reads perks as a source and today
## gets an empty array."
func test_actions_for_reads_the_matrix_as_a_source_and_gets_nothing_today() -> void:
	var matrix := Matrix.new()
	assert_eq(matrix.provides_actions(), [] as Array[StringName])

	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _hand_with_pistol()
	var unit := Unit.new(matrix, Shell.new(_torso([hand_socket])), Vector2i(0, 0), 0)

	# Only the pistol's own provides_actions is on the bar — the matrix
	# source contributes nothing, exactly matching its own empty return.
	var ids: Array[StringName] = _ids(ActionCatalog.actions_for(unit))
	assert_eq(ids, [&"overwatch", &"shoot"])


## taskblock-07 E3/TESTS: "moving overwatch from a gun's data to a perk's
## data changes the bar with no code edit — assert this, it's the whole
## point." No Perk resource exists yet (E3: "outline only... do not build a
## perk system"), so this proves the SOURCE-agnostic design the taskblock
## actually asks for the only way it's buildable today: a Matrix whose own
## provides_actions() stands in for "a perk now provides this" (the exact
## seam Matrix.provides_actions() exists to be) — ActionCatalog.actions_for
## itself is byte-for-byte identical in both halves of this test.
class _MatrixWithOverwatchPerk:
	extends Matrix

	func provides_actions() -> Array[StringName]:
		return [&"overwatch"]


func test_moving_overwatch_to_a_perk_changes_the_bar_with_no_code_edit() -> void:
	var pistol_only: Part = _pistol()
	pistol_only.provides_actions = [&"shoot"]  # overwatch moved OFF the gun
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol_only
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand

	var matrix := _MatrixWithOverwatchPerk.new()  # ... and ONTO a perk
	var unit := Unit.new(matrix, Shell.new(_torso([hand_socket])), Vector2i(0, 0), 0)

	var ids: Array[StringName] = _ids(ActionCatalog.actions_for(unit))
	assert_eq(ids, [&"shoot", &"overwatch"], "same result, moved to a different data source")


## taskblock-07 E3/TESTS: "overwatch disappears when no part provides
## shoot" — requires_action keeps the instrument honest even once its own
## provider is a perk, not the gun.
func test_overwatch_disappears_when_no_part_provides_shoot() -> void:
	var matrix := _MatrixWithOverwatchPerk.new()
	var saw_socket := Socket.new(&"HAND")
	saw_socket.occupant = _saw_hand()
	var unit := Unit.new(matrix, Shell.new(_torso([saw_socket])), Vector2i(0, 0), 0)

	var ids: Array[StringName] = _ids(ActionCatalog.actions_for(unit))
	assert_eq(ids, [&"saw"], "the matrix knows overwatch, but has no instrument to do it with")


## taskblock-08 A1: "the armed action decides what a click means" —
## provider_for() is what makes that concrete. A unit with both a gun and a
## saw must resolve each action id to its OWN part, never just whichever
## weapon a blind "any operable part" search would return first.
func test_provider_for_returns_the_part_that_actually_provides_the_id() -> void:
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _hand_with_pistol()
	var saw_socket := Socket.new(&"HAND")
	saw_socket.occupant = _saw_hand()
	var unit := _make_unit(_torso([hand_socket, saw_socket]))

	var shoot_provider: Part = ActionCatalog.provider_for(unit, &"shoot")
	var saw_provider: Part = ActionCatalog.provider_for(unit, &"saw")

	assert_eq(shoot_provider.id, &"pistol")
	assert_eq(saw_provider.id, &"saw_hand")


func test_provider_for_returns_null_when_nothing_provides_the_id() -> void:
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _hand_with_pistol()
	var unit := _make_unit(_torso([hand_socket]))

	assert_null(ActionCatalog.provider_for(unit, &"saw"))


## Same per-part gates actions_for() itself applies (docs/01 capability
## matching) — a rifle two saw hands can't operate must not be handed back
## as a provider just because it's the only part listing &"shoot".
func test_provider_for_respects_the_same_operability_gate_as_actions_for() -> void:
	var rifle := _pistol()
	rifle.id = &"rifle"
	rifle.requires = {&"TRIGGER": 1, &"SUPPORT": 1}
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]  # no SUPPORT — the rifle can't actually fire
	var grip := Socket.new(&"GRIP")
	grip.occupant = rifle
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var unit := _make_unit(_torso([hand_socket]))

	assert_null(ActionCatalog.provider_for(unit, &"shoot"))


## taskblock-24 Pass A: the ONE place an action id becomes a real
## CombatAction — the player's confirm_shot and the AI's own firing
## helper both read this instead of hardcoding a class.
func test_build_firing_action_shoot_returns_an_attack_action() -> void:
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _hand_with_pistol()
	var unit := _make_unit(_torso([hand_socket]))

	var action: CombatAction = ActionCatalog.build_firing_action(
		&"shoot", unit, &"pistol", Vector2i(3, 0)
	)

	assert_true(action is AttackAction)


func test_build_firing_action_burst_returns_a_burst_action() -> void:
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _hand_with_pistol()
	var unit := _make_unit(_torso([hand_socket]))

	var action: CombatAction = ActionCatalog.build_firing_action(
		&"burst", unit, &"pistol", Vector2i(3, 0)
	)

	assert_true(action is BurstAction)


## `&"saw"` is a different providing weapon, never a different resolution
## mechanic — it's still backed by AttackAction, same as shoot.
func test_build_firing_action_saw_also_returns_an_attack_action() -> void:
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _saw_hand()
	var unit := _make_unit(_torso([hand_socket]))

	var action: CombatAction = ActionCatalog.build_firing_action(
		&"saw", unit, &"saw_hand", Vector2i(3, 0)
	)

	assert_true(action is AttackAction)


func test_build_firing_action_returns_null_for_an_unrecognized_id() -> void:
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _hand_with_pistol()
	var unit := _make_unit(_torso([hand_socket]))

	assert_null(
		ActionCatalog.build_firing_action(&"overwatch", unit, &"pistol", Vector2i(3, 0)),
		"overwatch has no aimed-target CombatAction of its own to build here"
	)


## taskblock-25 Pass C: "a weapon usually provides both stab and slash" —
## a single weapon Part authoring both ids lists BOTH actions and each
## dispatches to its own distinct payload class, never collapsing to one.
func test_a_weapon_can_provide_both_stab_and_slash_with_different_payloads() -> void:
	var knife := Part.new()
	knife.id = &"knife"
	knife.hp = 3
	knife.max_hp = 3
	knife.attaches_to = [&"GRIP"]
	knife.requires = {&"TRIGGER": 1}
	knife.provides_actions = [&"stab", &"slash"]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = knife
	hand.sockets = [grip]

	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var unit := _make_unit(_torso([hand_socket]))

	var ids: Array[StringName] = []
	for def: ActionDef in ActionCatalog.actions_for(unit):
		ids.append(def.id)
	assert_true(&"stab" in ids)
	assert_true(&"slash" in ids)

	var stab: CombatAction = ActionCatalog.build_firing_action(
		&"stab", unit, &"knife", Vector2i(1, 0)
	)
	var slash: CombatAction = ActionCatalog.build_firing_action(
		&"slash", unit, &"knife", Vector2i(1, 0)
	)
	assert_true(stab is StabAction)
	assert_true(slash is SlashAction)
