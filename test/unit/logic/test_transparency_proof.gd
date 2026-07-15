extends GutTest

## docs/08's headline test — "the single most testable feature in the
## project": for every (loadout, target, seed), the damage a tooltip would
## predict must be exactly the damage the resolver actually applies. Not
## approximately — exactly. This is what catches the bug where an attack
## reads a raw Part field while a tooltip reads the resolved stat: they'd
## quietly drift the moment a perk or ammo modifier existed.


func _weapon(id: StringName, damage: float, stat_mod: float = 0.0) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = damage
	weapon.ap_cost = 1
	weapon.burst = 1
	weapon.scatter = [Ring.new(0.02, 1.0)]  # tight: lands on the target's one part every time
	if stat_mod != 0.0:
		weapon.stat_mods = {&"damage": stat_mod}
	return weapon


func _shooter(cell: Vector2i, weapon: Part) -> Unit:
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
	return Unit.new(Matrix.new(), Frame.new(torso), cell, 0)


## Unarmored (no material -> dt 0): any positive damage always penetrates,
## regardless of angle, so the property below isn't accidentally
## exercising deflection/retention — only "does the number match."
func _unarmored_target(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 1000
	torso.max_hp = 1000
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Frame.new(torso), cell, 1)


func test_headline_property_tooltip_predicted_damage_equals_actual_damage() -> void:
	var loadouts: Array[Dictionary] = [
		{id = &"pistol", damage = 4.0, mod = 0.0},
		{id = &"rifle", damage = 6.0, mod = 2.0},  # a perk-equivalent part stat_mod
		{id = &"cannon", damage = 12.0, mod = -3.0},
	]
	var target_cells: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 2)]
	var seeds: Array[int] = [1, 2, 3, 4, 5]

	for loadout: Dictionary in loadouts:
		for target_cell: Vector2i in target_cells:
			for seed_value: int in seeds:
				var weapon: Part = _weapon(loadout.id, loadout.damage, loadout.mod)
				var shooter := _shooter(Vector2i(0, 0), weapon)
				var target := _unarmored_target(target_cell)
				var grid := Grid.new(10, 10)
				var state := CombatState.new(grid, [shooter, target])
				state.rng.seed = seed_value

				# The tooltip's number: resolved once, before the shot fires.
				var predicted: float = WeaponResolver.resolve_damage(weapon).current

				AttackAction.new(shooter, loadout.id, target_cell).apply(state)
				var actual_damage: int = target.frame.root.max_hp - target.frame.root.hp

				assert_eq(
					actual_damage,
					int(ceil(predicted)),
					(
						"loadout %s, target %s, seed %d: tooltip said %s, actual damage was %d"
						% [loadout.id, target_cell, seed_value, predicted, actual_damage]
					)
				)


## The same property, but proving the resolved (modified) number is what's
## used — not the weapon's raw, unmodified damage field.
func test_a_damage_modifier_changes_both_the_tooltip_and_the_actual_damage_together() -> void:
	var weapon: Part = _weapon(&"rifle", 6.0, 3.0)  # resolves to 9, not 6
	var shooter := _shooter(Vector2i(0, 0), weapon)
	var target := _unarmored_target(Vector2i(2, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	state.rng.seed = 1

	var predicted: float = WeaponResolver.resolve_damage(weapon).current
	assert_eq(predicted, 9.0, "sanity: the tooltip must reflect the modifier")

	AttackAction.new(shooter, &"rifle", Vector2i(2, 0)).apply(state)
	var actual_damage: int = target.frame.root.max_hp - target.frame.root.hp

	assert_eq(actual_damage, 9, "the modifier must reach the actual attack, not just the tooltip")
	assert_ne(actual_damage, 6, "the raw, unmodified weapon.damage must not be what actually fired")
