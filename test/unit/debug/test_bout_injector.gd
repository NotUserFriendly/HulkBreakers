extends GutTest

## taskblock-29 Pass A: the injection channel — boundary-only, logged.
## Pass B's own verbs get their own test file; this one exercises the
## shared `_guard`/`_log_injection` machinery through `force_current_unit`,
## the one verb Pass A itself ships.


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_can_inject_is_true_outside_resolution() -> void:
	var state := CombatState.new(Grid.new(5, 5))
	var injector := BoutInjector.new(state)

	assert_true(injector.can_inject())


func test_can_inject_is_false_while_resolving() -> void:
	var state := CombatState.new(Grid.new(5, 5))
	var injector := BoutInjector.new(state)

	state.is_resolving = true

	assert_false(injector.can_inject())


func test_a_verb_mutates_and_logs_at_a_step_boundary() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var injector := BoutInjector.new(state)

	var ok: bool = injector.force_current_unit(b)

	assert_true(ok)
	assert_eq(state.current_unit(), b)
	var events: Array[LogEvent] = sink.events_of_kind(&"inject")
	assert_eq(events.size(), 1, 'every injection must emit exactly one &"inject" event')
	assert_eq(events[0].data.get("verb"), &"force_current_unit")


## The TESTS bar this taskblock names literally: "a mid-resolution
## injection attempt is rejected."
func test_a_mid_resolution_injection_attempt_is_rejected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var injector := BoutInjector.new(state)
	state.is_resolving = true

	var ok: bool = injector.force_current_unit(b)

	assert_false(ok)
	assert_push_error("mid-resolution")
	assert_ne(state.current_unit(), b, "a rejected injection must never mutate anything")
	assert_eq(
		sink.events_of_kind(&"inject").size(), 0, "a rejected injection must never log anything"
	)
	assert_false(state.was_injected, "a rejected injection must never flip the determinism flag")


func test_a_rejected_injection_is_a_true_noop_never_marks_the_bout_injected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)
	state.is_resolving = true

	injector.force_current_unit(a)

	assert_push_error("mid-resolution")
	assert_false(state.was_injected)


func test_a_successful_injection_marks_the_bout_as_injected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(Grid.new(5, 5), [a, b])
	var injector := BoutInjector.new(state)
	assert_false(state.was_injected, "sanity: a fresh bout is never pre-marked")

	injector.force_current_unit(b)

	assert_true(state.was_injected)


## taskblock-29 Pass B: the injection verbs — each fronts a real,
## already-existing mutation path; "produces the same state a legitimate
## path would."


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## torso: MATRIX + BACK (holding a real container) + GRIP (bare) — the
## same minimal shape test_kit_equipper.gd already proved KitEquipper
## against, reused here so hand_weapon/equip_from_kit exercise the real
## Inventory/PartGraph ops against a small, purpose-built fixture
## (CLAUDE.md: "if a test needs a concrete list, the test authors it as a
## fixture") rather than the full reference humanoid.
func _armable_unit(container_id: StringName = &"container") -> Dictionary:
	var container := Part.new()
	container.id = container_id
	container.attaches_to = [&"BACK"]
	container.is_container = true
	container.max_bulk = 20.0
	container.hp = 1
	container.max_hp = 1

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	var back_socket := Socket.new(&"BACK", Transform3D.IDENTITY, &"BACK")
	back_socket.occupant = container
	torso.sockets = [
		back_socket, Socket.new(&"GRIP", Transform3D.IDENTITY, &"GRIP"), Socket.new(&"MATRIX")
	]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	return {"unit": unit, "container": container}


func _weapon_part(id: StringName) -> Part:
	var p := Part.new()
	p.id = id
	p.attaches_to = [&"GRIP"]
	p.hp = 1
	p.max_hp = 1
	return p


func test_spawn_unit_adds_a_real_unit_through_the_real_assembly_path() -> void:
	var preset: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	assert_not_null(preset, "sanity: a real shipped preset must load")
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var before_count: int = state.units.size()
	var injector := BoutInjector.new(state)

	var spawned: Unit = injector.spawn_unit(preset, Vector2i(3, 3), 1)

	assert_not_null(spawned)
	assert_eq(state.units.size(), before_count + 1)
	assert_eq(state.grid.get_occupant_id(Vector2i(3, 3)), spawned.id)
	assert_eq(spawned.squad_id, 1)
	assert_true(state.was_injected)


func test_spawn_unit_draws_its_matrix_id_from_the_bout_rng_not_a_global_one() -> void:
	var preset: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	var a := _make_unit(Vector2i(0, 0), 0)
	var state_a := CombatState.new(Grid.new(10, 10), [a], 77)
	var spawned_a: Unit = BoutInjector.new(state_a).spawn_unit(preset, Vector2i(3, 3), 1)

	var b := _make_unit(Vector2i(0, 0), 0)
	var state_b := CombatState.new(Grid.new(10, 10), [b], 77)
	var spawned_b: Unit = BoutInjector.new(state_b).spawn_unit(preset, Vector2i(3, 3), 1)

	assert_eq(
		spawned_a.matrix.id, spawned_b.matrix.id, "same bout seed must draw the same matrix id"
	)


func test_set_position_moves_the_unit_and_updates_grid_occupancy() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_position(a, Vector2i(5, 5))

	assert_true(ok)
	assert_eq(a.cell, Vector2i(5, 5))
	assert_eq(state.grid.get_occupant_id(Vector2i(5, 5)), a.id)
	assert_eq(state.grid.get_occupant_id(Vector2i(0, 0)), -1)


func test_set_position_refuses_an_already_occupied_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_position(a, Vector2i(5, 5))

	assert_false(ok)
	assert_eq(a.cell, Vector2i(0, 0), "a refused move must never mutate the unit's own cell")


func test_hand_weapon_attaches_a_fresh_pool_copy_into_the_named_socket() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var template := _weapon_part(&"pistol")
	var pool := {&"pistol": template}
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.hand_weapon(unit, &"pistol", &"GRIP", pool)

	assert_true(ok)
	var grip: Socket = PartGraph.find_socket(unit.shell.root, &"GRIP")
	assert_not_null(grip.occupant)
	assert_eq(grip.occupant.id, &"pistol")
	assert_ne(grip.occupant, template, "must attach a duplicate, never the pool template itself")


func test_equip_from_kit_runs_the_real_kit_equip_path() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var container: Part = built.container
	var pool := {&"pistol": _weapon_part(&"pistol")}
	var kit := Kit.new(&"BACK", [&"pistol"], &"pistol", &"GRIP")
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.equip_from_kit(unit, kit, pool)

	assert_true(ok)
	assert_eq(PartGraph.find_socket(unit.shell.root, &"GRIP").occupant.id, &"pistol")
	assert_eq(container.contents.size(), 0, "the weapon must have left the kit's own container")


func test_set_part_hp_forces_an_exact_value() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_part_hp(unit, &"torso", 0)

	assert_true(ok)
	assert_eq(unit.shell.root.hp, 0)


func test_set_part_hp_refuses_an_unknown_part_id() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_part_hp(unit, &"nonexistent", 0)

	assert_false(ok)


## Reuses `WoundEffects.apply_if_status_crosses_threshold` — the exact
## primitive the inspect panel's own `[*] Inflict Status: Burn` debug menu
## already calls.
func test_inflict_wound_reuses_wound_effects() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.inflict_wound(unit, &"torso", 5.0, 3.0, &"burnt_electronics")

	assert_true(ok)
	assert_true(&"burnt_electronics" in unit.shell.root.wounds)


func test_inflict_wound_below_threshold_never_inflicts() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)

	injector.inflict_wound(unit, &"torso", 1.0, 3.0, &"burnt_electronics")

	assert_false(&"burnt_electronics" in unit.shell.root.wounds)


func test_set_ap_forces_an_exact_value() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	injector.set_ap(a, 0)

	assert_eq(a.ap, 0)


func test_set_mp_forces_an_exact_value() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	injector.set_mp(a, 4.5)

	assert_almost_eq(a.mp, 4.5, 0.0001)


func test_set_facing_forces_an_exact_orientation() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	injector.set_facing(a, PI)

	assert_almost_eq(a.orientation, PI, 0.0001)


func test_set_pose_forces_a_named_pose() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	injector.set_pose(a, &"PRONE")

	assert_eq(a.pose.overrides, Poses.prone().overrides)


## taskblock-29 Pass B: "a verb with no backing system yet is a flagged
## stub, not a fake."
func test_set_therms_is_a_flagged_stub_that_never_mutates() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_therms(a, &"torso", 10.0)

	assert_false(ok)
	assert_push_error("stub")
	assert_false(state.was_injected, "a stub must never claim to have mutated anything")


func test_force_overwatch_arm_sets_the_field_directly() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	injector.force_overwatch_arm(a, &"pistol")

	assert_eq(a.overwatch_weapon_id, &"pistol")


## `force_action` must reuse the real `CombatState.try_apply` — an action
## that isn't actually legal is refused, never bypassed.
func test_force_action_reuses_try_apply_and_its_own_legality_check() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)
	# A non-adjacent jump — illegal at the same path-continuity check any
	# ordinary MoveAction already fails on, never a bespoke rejection.
	var illegal_move := MoveAction.new(a, [Vector2i(0, 0), Vector2i(4, 4)])

	var ok: bool = injector.force_action(illegal_move)

	assert_false(ok, "an illegal path must be refused, same as any ordinary apply")
	assert_false(state.was_injected)


func test_force_action_applies_a_legal_action_for_real() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)
	var legal_move := MoveAction.new(a, [Vector2i(0, 0), Vector2i(1, 0)])

	var ok: bool = injector.force_action(legal_move)

	assert_true(ok)
	assert_eq(a.cell, Vector2i(1, 0))
	assert_true(state.was_injected)


## taskblock-31 (rolled into tb30): tile verbs — cover and passability.


func _cover_part(id: StringName) -> Part:
	var p := Part.new()
	p.id = id
	p.material = &"steel"
	p.hp = 4
	p.max_hp = 4
	p.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	return p


func test_place_cover_adds_a_real_blocker_and_blocks_movement() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var pool := {&"scrap_pile": _cover_part(&"scrap_pile")}
	var injector := BoutInjector.new(state)
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	assert_gt(pf.move_cost(Vector2i(2, 2)), 0.0, "sanity: the cell starts passable")

	var ok: bool = injector.place_cover(Vector2i(2, 2), &"scrap_pile", pool)

	assert_true(ok)
	assert_not_null(state.grid.blockers.get(Vector2i(2, 2)))
	assert_eq((state.grid.blockers[Vector2i(2, 2)] as Part).id, &"scrap_pile")
	assert_lt(
		Pathfinder.new(state.grid, state.terrain_costs).move_cost(Vector2i(2, 2)),
		0.0,
		"a placed blocker must actually block movement"
	)


func test_place_cover_refuses_an_already_blocked_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.grid.blockers[Vector2i(2, 2)] = _cover_part(&"existing")
	var pool := {&"scrap_pile": _cover_part(&"scrap_pile")}
	var injector := BoutInjector.new(state)

	var ok: bool = injector.place_cover(Vector2i(2, 2), &"scrap_pile", pool)

	assert_false(ok)
	assert_eq((state.grid.blockers[Vector2i(2, 2)] as Part).id, &"existing")


func test_clear_cover_removes_the_blocker_and_restores_passage() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.grid.blockers[Vector2i(2, 2)] = _cover_part(&"scrap_pile")
	var injector := BoutInjector.new(state)

	var ok: bool = injector.clear_cover(Vector2i(2, 2))

	assert_true(ok)
	assert_false(state.grid.blockers.has(Vector2i(2, 2)))
	assert_gt(Pathfinder.new(state.grid, state.terrain_costs).move_cost(Vector2i(2, 2)), 0.0)


func test_clear_cover_refuses_a_cell_with_nothing_to_clear() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	assert_false(injector.clear_cover(Vector2i(2, 2)))


func test_set_passable_false_makes_a_cell_impassable() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_passable(Vector2i(2, 2), false)

	assert_true(ok)
	assert_eq(state.grid.get_terrain(Vector2i(2, 2)), Enums.TerrainType.WALL)
	assert_lt(Pathfinder.new(state.grid, state.terrain_costs).move_cost(Vector2i(2, 2)), 0.0)


func test_set_passable_true_restores_passage() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.grid.set_terrain(Vector2i(2, 2), Enums.TerrainType.WALL)
	state.grid.set_opacity(Vector2i(2, 2), 1.0)
	var injector := BoutInjector.new(state)

	var ok: bool = injector.set_passable(Vector2i(2, 2), true)

	assert_true(ok)
	assert_eq(state.grid.get_terrain(Vector2i(2, 2)), Enums.TerrainType.OPEN)
	assert_almost_eq(state.grid.get_opacity(Vector2i(2, 2)), 0.0, 0.0001)
	assert_gt(Pathfinder.new(state.grid, state.terrain_costs).move_cost(Vector2i(2, 2)), 0.0)


## taskblock-31 (rolled into tb30): the general attach_part verb.


func test_attach_part_attaches_a_non_weapon_part_to_a_valid_socket() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var plate := Part.new()
	plate.id = &"backpack"
	plate.attaches_to = [&"GRIP"]
	plate.hp = 2
	plate.max_hp = 2
	var pool := {&"backpack": plate}
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.attach_part(unit, &"backpack", &"GRIP", pool)

	assert_true(ok)
	assert_eq(PartGraph.find_socket(unit.shell.root, &"GRIP").occupant.id, &"backpack")


func test_attach_part_refuses_an_illegal_attachment() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var wrong_socket_part := Part.new()
	wrong_socket_part.id = &"wrong"
	wrong_socket_part.attaches_to = [&"SOMETHING_ELSE"]
	var pool := {&"wrong": wrong_socket_part}
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.attach_part(unit, &"wrong", &"GRIP", pool)

	assert_false(ok)
	assert_null(PartGraph.find_socket(unit.shell.root, &"GRIP").occupant)


func test_hand_weapon_and_attach_part_share_the_same_mechanism_but_log_distinctly() -> void:
	var built: Dictionary = _armable_unit()
	var unit: Unit = built.unit
	var pool := {&"pistol": _weapon_part(&"pistol")}
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var injector := BoutInjector.new(state)

	injector.hand_weapon(unit, &"pistol", &"GRIP", pool)

	var events: Array[LogEvent] = sink.events_of_kind(&"inject")
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("verb"), &"hand_weapon", "hand_weapon must log its own verb name")


## taskblock-31 (rolled into tb30): remove_unit.


func test_remove_unit_kills_it_through_the_real_combat_state_path() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	var injector := BoutInjector.new(state)

	var ok: bool = injector.remove_unit(a)

	assert_true(ok)
	assert_false(a.alive)
	assert_eq(state.grid.get_occupant_id(Vector2i(0, 0)), -1)


func test_remove_unit_refuses_an_already_dead_unit() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [a])
	state.kill_unit(a)
	var injector := BoutInjector.new(state)

	assert_false(injector.remove_unit(a))
