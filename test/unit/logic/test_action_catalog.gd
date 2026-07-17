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
