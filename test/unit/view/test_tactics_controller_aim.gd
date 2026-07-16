extends GutTest

## docs/10 Phase 12.3/12.4: aim mode, the dartboard read/resolve pair, and
## RESOLUTION input-locking — split out of test_tactics_controller.gd
## purely to stay under gdlint's max-public-methods; same conventions
## (click_cell() driven directly, no live camera/viewport needed).


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


## torso -[HAND]- hand(TRIGGER) -[GRIP]- pistol — the same shape
## test_attack_action.gd uses, so the shooter can actually fire.
func _make_armed_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func _setup(units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), units)
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)
	return {
		"state": state, "controller": controller, "board_view": board_view, "camera_rig": camera_rig
	}


func test_clicking_an_enemy_while_selected_enters_aim_mode() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))

	assert_eq(controller.aiming_at, b)
	assert_eq(controller.layer_index, 0)
	assert_eq(controller.reticle_offset, Vector2.ZERO)


## docs/10 taskblock03 C1: entering aim eases (never cuts) to the
## over-the-shoulder attack framing.
func test_entering_aim_mode_starts_easing_the_camera_to_attack_framing() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))

	assert_not_null(camera_rig._active_tween)


## docs/10 taskblock03 C2: F eases back to the same over-the-shoulder
## default, after the player has orbited/panned/zoomed away from it.
func test_f_key_resets_framing_while_aiming() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))
	camera_rig._kill_active_tween()  # as if the player had already orbited away
	assert_null(camera_rig._active_tween)

	controller.reset_framing()

	assert_not_null(camera_rig._active_tween)


func test_f_key_does_nothing_outside_aim_mode() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig
	controller.click_cell(Vector2i(0, 0))  # selected, not aiming

	controller.reset_framing()

	assert_null(camera_rig._active_tween, "nothing to reset to outside Attack mode")


func test_entering_aim_mode_disables_camera_zoom_cancelling_restores_it() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))
	assert_false(camera_rig.zoom_enabled, "docs/10: scroll steps layers while aiming, not zoom")

	controller.cancel_aim()
	assert_true(camera_rig.zoom_enabled)
	assert_null(controller.aiming_at)


func test_scroll_layer_only_changes_layer_index_while_aiming() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.scroll_layer(1)
	assert_eq(controller.layer_index, 0, "not aiming yet — nothing to scroll")

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))
	controller.scroll_layer(1)

	assert_eq(controller.layer_index, 1)


func test_move_reticle_only_changes_offset_while_aiming() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.move_reticle(Vector2(1, 1))
	assert_eq(controller.reticle_offset, Vector2.ZERO, "not aiming yet")

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))
	controller.move_reticle(Vector2(0.3, -0.1))

	assert_eq(controller.reticle_offset, Vector2(0.3, -0.1))


func test_confirm_shot_queues_an_attack_action_with_the_reticle_offset() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))
	controller.move_reticle(Vector2(0.2, 0.0))
	controller.confirm_shot()

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 1)
	var attack := actions[0] as AttackAction
	assert_not_null(attack)
	assert_eq(attack.aim_offset, Vector2(0.2, 0.0))
	assert_eq(attack.target_cell, Vector2i(5, 5))
	assert_null(controller.aiming_at, "confirming a shot must return to Tactical")


func test_clicking_anywhere_while_aiming_confirms_the_shot() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))
	controller.click_cell(Vector2i(2, 2))  # anywhere at all — this is "confirm"

	assert_eq(controller.selection.current_queue().actions.size(), 1)
	assert_null(controller.aiming_at)


func test_confirm_shot_with_no_operable_weapon_still_exits_aim_mode() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)  # no weapon at all
	var b := _make_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))
	controller.confirm_shot()

	assert_eq(controller.selection.current_queue().actions.size(), 0)
	assert_null(controller.aiming_at)


func test_end_turn_cancels_an_active_aim() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))
	controller.end_turn()

	assert_null(controller.aiming_at)
	assert_true(camera_rig.zoom_enabled)


## docs/10 taskblock03 D5: aim_plane() now builds from a speculative preview
## clone (so a queued move changes it before resolution — covered below),
## which means every Region.body in it is a clone unit sharing the real
## unit's `id`, never the same object. Comparisons here go through `.id`
## rather than `==` for exactly that reason.
func test_aim_plane_excludes_the_shooters_own_body_but_keeps_the_targets() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var state: CombatState = built.state

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))

	var raw: Array[Region] = ShotPlane.build(Vector2(0, 0), Vector2(5, 5).normalized(), state)
	var plane: Array[Region] = controller.aim_plane()

	assert_lt(plane.size(), raw.size(), "the raw plane includes the shooter's own body")
	for region: Region in plane:
		var body: Unit = region.body as Unit
		assert_ne(body.id, a.id, "the aim plane must never carry the shooter as a phantom layer")
	var target_regions: Array[Region] = []
	for region: Region in plane:
		var body: Unit = region.body as Unit
		if body != null and body.id == b.id:
			target_regions.append(region)
	assert_true(target_regions.size() > 0, "the actual target must still be in the aim plane")


## docs/10 taskblock03 D5: shooter/target/plane must come from the SAME
## preview (aim_state()) — pulling them from separate calls would hand back
## unrelated clones whose Parts never object-match each other.
func test_entering_aim_mode_reads_the_target_not_the_shooters_own_phantom_layer() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))

	var aim: Dictionary = controller.aim_state()
	var weapon: Part = DeepStrike.find_operable_weapon(aim["shooter"])
	var target_point: Vector2 = ShotPlane.center_of(aim["plane"], aim["target"])
	var result: AimResult = AimController.resolve(
		aim["plane"], target_point, controller.layer_index, weapon
	)

	assert_eq((result.reading as Unit).id, b.id, "layer 0 of the aim plane must be the target")


## docs/10 taskblock03 D5: "the aim preview must build its shot plane from
## the speculative state... the queued end cell and end facing."
func test_aim_plane_originates_from_the_queued_end_cell_not_the_current_one() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(9, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	a.mp = 10.0

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 0))  # queue a move, still just queued
	controller.click_cell(Vector2i(9, 0))  # aim at b from the queued end position

	assert_eq(a.cell, Vector2i(0, 0), "still just queued — the real unit has not moved")
	var aim: Dictionary = controller.aim_state()
	var target_point: Vector2 = ShotPlane.center_of(aim["plane"], aim["target"])
	var target_region: Region = ShotPlane.resolve_projectile(aim["plane"], target_point)

	assert_not_null(target_region, "the target must actually resolve")
	# Origin at the queued end cell (5,0) puts the target's near face ~3
	# away; origin at the current cell (0,0) — the bug this guards against —
	# would put it ~8 away. A generous midpoint threshold distinguishes the
	# two without pinning the exact face-offset geometry.
	assert_lt(target_region.depth, 6.0, "must have originated from the queued end cell, not (0,0)")


## docs/10 taskblock03 D5: "a queued move behind cover changes what the
## reticle resolves to, before resolution." The wall sits on column x == 2,
## between shooter and target. The shooter's ORIGINAL cell (0,0) shoots at
## the target diagonally, clearing the wall; the QUEUED end cell (2,0) is
## dead in line with it. Only the aim plane sourced from the queued end
## position should resolve the center-mass shot as blocked.
func test_a_queued_move_behind_cover_changes_the_aim_plane_before_resolution() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(2, 6), 1)
	var wall := Part.new()
	wall.id = &"wall"
	wall.hp = 10
	wall.max_hp = 10
	wall.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 2.0, 1.0))]
	var built: Dictionary = _setup([a, b])
	var state: CombatState = built.state
	state.grid.blockers[Vector2i(2, 3)] = wall
	var controller: TacticsController = built.controller
	a.mp = 10.0

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(2, 6))
	var aim_before: Dictionary = controller.aim_state()
	var point_before: Vector2 = ShotPlane.center_of(aim_before["plane"], aim_before["target"])
	var hit_before: Region = ShotPlane.resolve_projectile(aim_before["plane"], point_before)
	controller.cancel_aim()

	controller.click_cell(Vector2i(2, 0))  # queue a move onto the wall's own column
	controller.click_cell(Vector2i(2, 6))  # re-aim from the queued end position
	var aim_after: Dictionary = controller.aim_state()
	var point_after: Vector2 = ShotPlane.center_of(aim_after["plane"], aim_after["target"])
	var hit_after: Region = ShotPlane.resolve_projectile(aim_after["plane"], point_after)

	assert_not_null(hit_before)
	assert_ne(hit_before.part.id, &"wall", "the original diagonal line of fire clears the wall")
	assert_not_null(hit_after)
	assert_eq(hit_after.part.id, &"wall", "the queued end position's line of fire is blocked")


## docs/10 Phase 12.4: End Turn locks input for the whole of RESOLUTION and
## hands whoever's listening exactly the events resolve_turn() emitted.
func test_end_turn_locks_input_and_emits_exactly_the_events_it_resolved() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))

	# GDScript lambdas capture outer locals by value — reassigning `captured`
	# from inside the lambda wouldn't propagate out, so mutate in place.
	var captured: Array[LogEvent] = []
	controller.turn_ended.connect(
		func(events: Array[LogEvent]) -> void: captured.append_array(events)
	)
	controller.end_turn()

	assert_true(controller.input_locked, "input must stay locked through RESOLUTION")
	assert_true(captured.size() > 0, "must have captured at least the move + turn_end events")
	for event: LogEvent in captured:
		assert_true(
			event.kind in [&"move", &"turn_end", &"turn_start"],
			"only this turn's own events, kind was %s" % event.kind
		)


func test_input_locked_blocks_click_scroll_reticle_and_confirm() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))  # enters aim mode
	controller.input_locked = true

	controller.scroll_layer(1)
	assert_eq(controller.layer_index, 0, "locked input must not step the layer")

	controller.move_reticle(Vector2(1, 1))
	assert_eq(controller.reticle_offset, Vector2.ZERO, "locked input must not move the reticle")

	controller.confirm_shot()
	assert_eq(controller.selection.current_queue().actions.size(), 0, "locked input must not fire")
	assert_eq(controller.aiming_at, b, "locked input must not even exit aim mode")

	controller.input_locked = false
	controller.click_cell(Vector2i(2, 2))
	assert_eq(
		controller.selection.current_queue().actions.size(), 1, "unlocked, confirm works again"
	)


func test_end_turn_is_a_no_op_while_already_locked() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.input_locked = true
	controller.end_turn()

	# still locked, and the queue was never touched by this second call —
	# it would have raised the queue's action count if it had run again.
	assert_true(controller.input_locked)


func test_unlock_input_clears_the_lock() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.input_locked = true

	controller.unlock_input()

	assert_false(controller.input_locked)
