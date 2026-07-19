extends GutTest

## taskblock-19 Pass E: Suppression — adjacent-enemy weapon suppression
## and the stubbed attack-of-opportunity trigger.


func _torso_unit(cell: Vector2i, squad: int, hp: int = 10) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = hp
	torso.max_hp = hp
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func _weapon(two_handed: bool) -> Part:
	var weapon := Part.new()
	weapon.id = &"gun"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.two_handed = two_handed
	return weapon


func test_adjacent_living_enemies_includes_orthogonal_and_diagonal() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var north := _torso_unit(Vector2i(1, 0), 1)
	var diagonal := _torso_unit(Vector2i(2, 2), 1)
	var far := _torso_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, north, diagonal, far])

	var enemies: Array[Unit] = Suppression.adjacent_living_enemies(state, self_unit, self_unit.cell)

	assert_true(north in enemies)
	assert_true(diagonal in enemies)
	assert_false(far in enemies)


func test_adjacent_living_enemies_excludes_the_dead_and_same_squad() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var dead_enemy := _torso_unit(Vector2i(1, 0), 1)
	dead_enemy.alive = false
	var ally := _torso_unit(Vector2i(2, 1), 0)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, dead_enemy, ally])

	assert_eq(
		Suppression.adjacent_living_enemies(state, self_unit, self_unit.cell), [] as Array[Unit]
	)


func test_is_suppressed_true_only_when_adjacent_to_a_living_enemy() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var enemy := _torso_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, enemy])

	assert_true(Suppression.is_suppressed(state, self_unit))

	enemy.cell = Vector2i(9, 9)
	assert_false(Suppression.is_suppressed(state, self_unit))


## taskblock-19 Pass E: "a unit adjacent to an enemy can't fire a long
## gun (can fire a short one)."
func test_blocks_weapon_true_for_a_long_gun_adjacent_to_an_enemy() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var enemy := _torso_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, enemy])
	var rifle: Part = _weapon(true)

	assert_true(Suppression.blocks_weapon(state, self_unit, rifle))


func test_blocks_weapon_false_for_a_short_gun_adjacent_to_an_enemy() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var enemy := _torso_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, enemy])
	var pistol: Part = _weapon(false)

	assert_false(Suppression.blocks_weapon(state, self_unit, pistol))


func test_blocks_weapon_false_for_a_long_gun_when_not_adjacent() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var enemy := _torso_unit(Vector2i(9, 9), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, enemy])
	var rifle: Part = _weapon(true)

	assert_false(Suppression.blocks_weapon(state, self_unit, rifle))


## taskblock-19 Pass E: "moving OUT of a tile adjacent to an enemy lets
## that enemy make a free melee attack as you leave."
func test_would_trigger_opportunity_attack_when_genuinely_leaving_adjacency() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var enemy := _torso_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, enemy])

	var attackers: Array[Unit] = Suppression.would_trigger_opportunity_attack(
		state, self_unit, Vector2i(1, 1), Vector2i(5, 5)
	)

	assert_eq(attackers, [enemy])


## A sidestep that stays adjacent to the SAME enemy draws no attack.
func test_no_opportunity_attack_when_still_adjacent_to_the_same_enemy() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var enemy := _torso_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, enemy])

	# (2, 1) and (2, 0) are BOTH adjacent to the enemy at (1, 0) —
	# sidestepping between them never leaves its threat range.
	var attackers: Array[Unit] = Suppression.would_trigger_opportunity_attack(
		state, self_unit, Vector2i(1, 1), Vector2i(2, 0)
	)

	assert_eq(attackers, [] as Array[Unit])


func test_no_opportunity_attack_when_never_adjacent_in_the_first_place() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var enemy := _torso_unit(Vector2i(9, 9), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, enemy])

	var attackers: Array[Unit] = Suppression.would_trigger_opportunity_attack(
		state, self_unit, Vector2i(1, 1), Vector2i(5, 5)
	)

	assert_eq(attackers, [] as Array[Unit])


func test_would_trigger_opportunity_attack_is_empty_for_a_zero_length_step() -> void:
	var self_unit := _torso_unit(Vector2i(1, 1), 0)
	var enemy := _torso_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [self_unit, enemy])

	assert_eq(
		Suppression.would_trigger_opportunity_attack(
			state, self_unit, Vector2i(1, 1), Vector2i(1, 1)
		),
		[] as Array[Unit]
	)


## taskblock-19 Pass E: "the melee resolution is a flagged stub, not real
## damage" — a flat, un-armored hit, logged as is_stub, never routed
## through DamageResolver's real penetration cascade.
func test_resolve_opportunity_attacks_applies_a_flat_stub_hit_and_logs_it() -> void:
	var mover := _torso_unit(Vector2i(1, 1), 0, 10)
	var attacker := _torso_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [mover, attacker])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var before_hp: int = mover.shell.root.hp

	Suppression.resolve_opportunity_attacks(state, mover, [attacker])

	assert_eq(mover.shell.root.hp, before_hp - int(Suppression.STUB_OPPORTUNITY_DAMAGE))
	var events: Array[LogEvent] = sink.events_of_kind(&"opportunity_attack")
	assert_eq(events.size(), 1)
	assert_true(events[0].data.get("is_stub"))
	assert_eq(events[0].data.get("target_unit_id"), mover.id)


func test_resolve_opportunity_attacks_can_kill_a_unit_with_no_other_parts() -> void:
	var mover := _torso_unit(Vector2i(1, 1), 0, 1)
	var attacker := _torso_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [mover, attacker])

	Suppression.resolve_opportunity_attacks(state, mover, [attacker])

	assert_false(mover.alive)


## taskblock-19 Pass E: MoveHooks composes Suppression's opportunity check
## with Overwatch's real trigger onto one mid_move_hook — leaving an
## adjacent enemy behind while resolving a real queued move must apply
## the stub hit, with no overwatch on the board at all to confuse the
## result.
func test_move_hooks_combined_applies_an_opportunity_attack_on_a_real_move() -> void:
	var mover := _torso_unit(Vector2i(0, 0), 0, 10)
	var attacker := _torso_unit(Vector2i(1, 0), 1)
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [mover, attacker])
	var path: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(0, 2),
		Vector2i(0, 3),
		Vector2i(0, 4),
		Vector2i(0, 5)
	]
	var queue := ActionQueue.new(mover)
	assert_true(queue.enqueue(MoveAction.new(mover, path), state))
	var before_hp: int = mover.shell.root.hp

	var hooks := MoveHooks.new(mover.cell)
	var outcome: Dictionary = state.resolve_until(queue, hooks.check)

	assert_eq(outcome.kind, Enums.ResolveOutcome.COMPLETED)
	assert_eq(mover.shell.root.hp, before_hp - int(Suppression.STUB_OPPORTUNITY_DAMAGE))
