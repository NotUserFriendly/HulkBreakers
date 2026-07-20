extends GutTest

## taskblock-25 Pass C (docs/PLAN.md "Phase M — Melee"): a slash hits
## everything along its own line, `slash_length` long. Fixtures mirror
## test_stab_action.gd's own conventions.


func _make_weapon(id: StringName, damage: float, reach: float, slash_length: float) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = damage
	weapon.ap_cost = 1
	weapon.burst = 1
	weapon.provides_actions = [&"slash"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.weapon_length = reach
	weapon.weapon_def.slash_length = slash_length
	weapon.scatter = [Ring.new(0.05, 1.0)]
	return weapon


func _make_striker(cell: Vector2i, weapon: Part) -> Unit:
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func _make_target(cell: Vector2i, hp: int = 10) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = hp
	torso.max_hp = hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 1)


## A torso (Y ~1.0-1.5) over legs (Y ~0.0-0.5), attached at a WAIST socket
## — two distinct parts stacked vertically, so a vertical slash spanning
## both proves "hits everything along it," not just a wide single box.
func _make_target_with_torso_and_legs(cell: Vector2i, hp: int = 10) -> Unit:
	var legs := Part.new()
	legs.id = &"legs"
	legs.hp = hp
	legs.max_hp = hp
	legs.volume = [Box.new(Vector3(0.0, 0.25, 0.0), Vector3(0.5, 0.5, 0.5))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = hp
	torso.max_hp = hp
	torso.volume = [Box.new(Vector3(0.0, 1.25, 0.0), Vector3(0.5, 0.5, 0.5))]
	var waist := Socket.new(&"WAIST")
	waist.occupant = legs
	torso.sockets = [waist]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, 1)


func test_is_legal_true_within_reach() -> void:
	var weapon := _make_weapon(&"sword", 20.0, 1.0, 1.0)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	assert_true(SlashAction.new(striker, &"sword", Vector2i(1, 0)).is_legal(state))


func test_is_legal_false_without_a_slash_provider() -> void:
	var weapon := _make_weapon(&"sword", 20.0, 1.0, 1.0)
	weapon.provides_actions = [&"stab"]  # provides stab, never authored to slash
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	assert_false(SlashAction.new(striker, &"sword", Vector2i(1, 0)).is_legal(state))


func test_apply_deals_damage_to_the_target() -> void:
	var weapon := _make_weapon(&"sword", 20.0, 1.0, 0.0)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	SlashAction.new(striker, &"sword", Vector2i(1, 0)).apply(state)

	assert_lt(target.shell.root.hp, 10)


## docs/PLAN.md Pass C: "a slash hits everything along it" and "a vertical
## slash uses the 3D plane to spread up/down a body" — both claims proven
## at once: torso AND legs, two distinct parts stacked in real height,
## both take damage from one vertical swing.
func test_a_vertical_slash_hits_every_part_along_its_line() -> void:
	var weapon := _make_weapon(&"greatsword", 20.0, 1.0, 2.0)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target_with_torso_and_legs(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	var legs: Part = target.shell.root.sockets[0].occupant

	SlashAction.new(striker, &"greatsword", Vector2i(1, 0), &"vertical").apply(state)

	assert_lt(target.shell.root.hp, 10, "the torso must take damage")
	assert_lt(legs.hp, 10, "the legs must ALSO take damage — the same swing hit both")


## A short slash confined to torso height must NOT also reach the legs —
## bounds the claim above so it isn't just "everything always gets hit."
func test_a_short_vertical_slash_does_not_reach_unrelated_parts() -> void:
	var weapon := _make_weapon(&"dagger", 20.0, 1.0, 0.1)
	var striker := _make_striker(Vector2i(0, 0), weapon)
	var target := _make_target_with_torso_and_legs(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])
	var legs: Part = target.shell.root.sockets[0].occupant

	SlashAction.new(striker, &"dagger", Vector2i(1, 0), &"vertical").apply(state)

	assert_lt(target.shell.root.hp, 10, "the torso must still take damage")
	assert_eq(legs.hp, 10, "a short slash confined to torso height must miss the legs")
