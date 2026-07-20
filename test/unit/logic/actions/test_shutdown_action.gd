extends GutTest

## taskblock-22 Pass C: "a unit that cannot move and cannot act can
## shutdown — the player equivalent of matrix ejection, available to both
## sides." Legal for any unit at any time (a choice), not gated on being
## stalled — that's UnitAI's own policy for when to queue it, tested in
## test_unit_ai.gd instead.


func _unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_is_legal_true_for_the_current_unit_even_when_fully_healthy() -> void:
	var a := _unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [a])

	assert_true(ShutdownAction.new(a).is_legal(state), "any unit may shut down — it's a choice")


func test_is_legal_false_for_a_non_current_unit() -> void:
	var a := _unit(Vector2i(0, 0), 0)
	var b := _unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])

	assert_false(ShutdownAction.new(b).is_legal(state))


func test_is_legal_false_once_already_shut_down() -> void:
	var a := _unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [a])
	a.shutdown = true

	assert_false(ShutdownAction.new(a).is_legal(state))


## "Out of the fight, inert on the board... it still occludes/blocks as
## geometry." Deliberately NOT alive=false — stays alive, keeps its own
## cell, unlike death or extraction.
func test_apply_marks_shutdown_but_stays_alive_and_on_its_cell() -> void:
	var a := _unit(Vector2i(2, 2))
	var b := _unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])

	ShutdownAction.new(a).apply(state)

	assert_true(a.shutdown)
	assert_true(a.alive, "shutdown is not death")
	assert_eq(a.cell, Vector2i(2, 2))
	assert_eq(state.grid.get_occupant_id(a.cell), a.id, "still occupies/occludes its own cell")


func test_apply_ends_the_turn() -> void:
	var a := _unit(Vector2i(0, 0), 0)
	var b := _unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])

	ShutdownAction.new(a).apply(state)

	assert_eq(state.current_unit(), b)


func test_apply_emits_a_shutdown_event() -> void:
	var a := _unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [a])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShutdownAction.new(a).apply(state)

	assert_eq(sink.events_of_kind(&"shutdown").size(), 1)
	assert_eq(sink.events_of_kind(&"shutdown")[0].unit_id, a.id)


func test_apply_on_a_preview_never_touches_the_real_unit() -> void:
	var a := _unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [a])

	var preview: CombatState = state.dup()
	var previewed_unit: Unit = preview.find_unit(a.id)
	ShutdownAction.new(previewed_unit).apply(preview)

	assert_false(a.shutdown, "the real unit must be untouched by a speculative preview")


## taskblock-22 Pass C: "a wounded unit that shuts down may trigger its
## reactor's MELTDOWN if the reactor is in that state" — integration with
## DamageResolver.trigger_primed_meltdowns, real ImpactResult cascade and
## all, not a re-derived copy of that logic.
func test_apply_triggers_a_primed_meltdown() -> void:
	var reactor := Part.new()
	reactor.id = &"reactor"
	reactor.failure_mode = &"MELTDOWN"
	reactor.meltdown_turns = 5
	reactor.detonate_damage = 5.0
	reactor.detonate_radius = 2.0
	reactor.hp = 1
	reactor.max_hp = 1

	var owner_torso := Part.new()
	owner_torso.id = &"owner_torso"
	owner_torso.hp = 20
	owner_torso.max_hp = 20
	var internal := Socket.new(&"INTERNAL")
	internal.occupant = reactor
	owner_torso.sockets = [internal]
	var owner := Unit.new(Matrix.new(), Shell.new(owner_torso), Vector2i(5, 5))

	var near_root := Part.new()
	near_root.hp = 10
	near_root.max_hp = 10
	var near_unit := Unit.new(Matrix.new(), Shell.new(near_root), Vector2i(5, 6))
	var state := CombatState.new(Grid.new(10, 10), [owner, near_unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	assert_true(DamageResolver.apply_damage_to_part(reactor, 10.0))
	var impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(reactor, state, impact)
	assert_eq(reactor.meltdown_countdown, 5, "sanity: armed, nowhere near naturally expiring")

	ShutdownAction.new(owner).apply(state)

	assert_eq(reactor.meltdown_countdown, -1, "the shutdown must trigger it immediately")
	assert_lt(near_root.hp, 10, "the triggered meltdown must actually deal its detonate_damage")
	assert_eq(sink.events_of_kind(&"detonate").size(), 1)


## A healthy unit's own shutdown is a complete no-op for the meltdown
## hook — nothing armed, nothing to trigger.
func test_apply_with_no_primed_meltdown_detonates_nothing() -> void:
	var a := _unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [a])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShutdownAction.new(a).apply(state)

	assert_eq(sink.events_of_kind(&"detonate").size(), 0)
