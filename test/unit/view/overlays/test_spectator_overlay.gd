extends GutTest

## taskblock-14 Pass C / taskblock-15 Pass A/B: SpectatorOverlay — the
## structural/state-machine half of the watch loop that can actually be
## asserted headlessly (play/pause/step/speed transitions). The
## moment-to-moment visual result (camera framing, board mesh, real
## animated playback) is not something a headless test can read back
## meaningfully; those were confirmed by a single live check, per this
## project's own "you cannot see the game — read the real node back"
## discipline applied at the structural level instead.
##
## taskblock-15 Pass A: this overlay no longer builds its own world
## (BoutView used to) — every test below builds a real BattleScene,
## loads a bout into it, then swaps to SpectatorOverlay, exactly the path
## GenerateBoutOverlay itself uses.
##
## taskblock-15 Pass B: step_once()/play() now await a real (if brief)
## ResolutionPlayer.play() call per turn — `_spectate()` zeroes every
## animation duration by default so the loops below (some running up to
## 500 steps) stay fast; ResolutionPlayer's own animation timing is
## covered directly in test_resolution_player.gd, not re-tested here.


func _armed_unit(
	id: StringName, cell: Vector2i, squad_id: int, weapon_id: StringName, torso_hp: int = 10
) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = torso_hp
	torso.max_hp = torso_hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var weapon := Part.new()
	weapon.id = weapon_id
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 6.0
	weapon.ap_cost = 1
	# taskblock-24 Pass A: the AI now asks ActionCatalog what this weapon
	# actually provides before firing — without this, no bout unit here
	# ever fires at all, and a bout that can never resolve by combat runs
	# to its own turn cap instead of a normal few-turn finish.
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
	torso.sockets = [hand_socket, Socket.new(&"MATRIX")]

	var link := Matrix.new()
	link.id = StringName("%s_link" % id)
	torso.hosted_matrix = link
	return Unit.new(link, Shell.new(torso), cell, squad_id)


func _bout(map_seed: int = 11) -> Dictionary:
	var jerry := _armed_unit(&"jerry", Vector2i(0, 0), 0, &"rifle", 30)
	var enemy := _armed_unit(&"enemy", Vector2i(8, 0), 1, &"pistol", 5)
	var state := CombatState.new(Grid.new(12, 5), [jerry, enemy], map_seed)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]
	return {"state": state, "mission": mission}


## Every test's own real path: a real BattleScene, a bout loaded into it,
## then swapped to SpectatorOverlay — the exact sequence
## GenerateBoutOverlay itself drives (A2). Neutralizes _ready()'s own
## default SquadControlOverlay FIRST (a bare ControlOverlay — the base
## class's every method is already a real, working no-op) — loading an
## all-AI bout straight into a STILL-ATTACHED SquadControlOverlay would
## trigger ITS OWN battle_loaded reactivity and auto-resolve the whole
## bout via advance_ai_turns() before this function ever got to install
## SpectatorOverlay, exactly the hazard GenerateBoutOverlay itself avoids
## by never being the SquadControlOverlay in the first place. Every
## animation duration is zeroed (taskblock-15 Pass B) so step_once()/play()
## await near-instantly — this file tests PACING, not playback timing.
func _spectate(built: Dictionary) -> SpectatorOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(built.state, built.mission)
	battle.set_overlay(SpectatorOverlay.new())
	var overlay: SpectatorOverlay = battle.overlay as SpectatorOverlay
	overlay.resolution_player.slide_ms = 0.0
	overlay.resolution_player.bullet_ms = 0.0
	overlay.resolution_player.tracer_count = 0
	return overlay


func test_setup_wires_a_bout_runner_against_the_loaded_battle() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	assert_not_null(overlay.runner)
	assert_eq(overlay.runner.state, overlay.battle.combat_state)


func test_play_sets_playing_and_pause_clears_it() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	overlay.play()
	assert_true(overlay.playing)

	overlay.pause()
	assert_false(overlay.playing)


## "Step-one-action" (this bout's own granularity: one unit's whole
## turn) advances exactly one turn and leaves the bout paused, never
## auto-continuing.
func test_step_once_advances_exactly_one_turn_and_stays_paused() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	await overlay.step_once()

	assert_eq(overlay.runner.turns_taken, 1)
	assert_false(overlay.playing)


## "Speed (1x, 2x, 4x)" — three fixed steps, cycling back to 1x. Also
## keeps ResolutionPlayer's own `speed` field in sync (B2: "pacing speed
## multiplies all durations").
func test_speed_cycles_through_the_three_fixed_steps() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	assert_almost_eq(overlay.speed, 1.0, 0.0001)
	overlay._on_speed_button_pressed()
	assert_almost_eq(overlay.speed, 2.0, 0.0001)
	assert_almost_eq(overlay.resolution_player.speed, 2.0, 0.0001)
	overlay._on_speed_button_pressed()
	assert_almost_eq(overlay.speed, 4.0, 0.0001)
	overlay._on_speed_button_pressed()
	assert_almost_eq(overlay.speed, 1.0, 0.0001)


## "Pause/step/speed don't alter the outcome, only its pacing" —
## verified at the BoutRunner level already (test_bout_runner.gd); this
## confirms the overlay's own pacing controls don't touch runner state
## beyond what step() itself already does: each step_once() call advances
## turns_taken by exactly one, never zero or more than one, regardless of
## speed (this fixture's own combat can finish before 3 calls — set_speed
## must not change THAT either).
func test_a_faster_speed_never_skips_or_repeats_a_single_step() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())
	overlay.set_speed(4.0)

	for i in range(3):
		if overlay.runner.finished:
			break
		var before: int = overlay.runner.turns_taken
		await overlay.step_once()
		assert_eq(
			overlay.runner.turns_taken, before + 1, "step %d must advance by exactly one turn" % i
		)


func test_the_bout_finishing_stops_playback() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	var guard := 0
	while not overlay.runner.finished and guard < 500:
		await overlay.step_once()
		guard += 1

	assert_true(overlay.runner.finished)
	assert_false(overlay.playing)


## taskblock-15 Pass B4: "editable fields at the top of the spectator
## overlay" — writing into the SpinBox fields must reach
## resolution_player's own real fields, not a local copy.
func test_the_dev_tunable_fields_write_directly_into_resolution_player() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	overlay._slide_ms_field.value = 50.0
	overlay._bullet_ms_field.value = 400.0
	overlay._tracer_count_field.value = 5.0

	assert_almost_eq(overlay.resolution_player.slide_ms, 50.0, 0.0001)
	assert_almost_eq(overlay.resolution_player.bullet_ms, 400.0, 0.0001)
	assert_eq(overlay.resolution_player.tracer_count, 5)


## "Timing arrows can go by 10ms, not 1ms — clicking into it lets you get
## more specific." `custom_arrow_step` governs ONLY the arrow-button
## increment; `Range.step` itself is what a typed/assigned value actually
## quantizes to (`SpinBox.rounded` is a display-formatting flag, unrelated
## to this — Range.step snaps unconditionally otherwise), so it's left at
## its default fine granularity — typing an exact value is never snapped
## to a multiple of the arrow step. `tracer_count` is a plain count, not a
## timing field, and never sets a custom arrow step at all.
func test_timing_fields_step_by_ten_ms_but_still_accept_an_exact_typed_value() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	assert_almost_eq(overlay._slide_ms_field.custom_arrow_step, 10.0, 0.0001)
	assert_almost_eq(overlay._bullet_ms_field.custom_arrow_step, 10.0, 0.0001)
	assert_almost_eq(overlay._tracer_count_field.custom_arrow_step, 0.0, 0.0001)

	overlay._slide_ms_field.value = 137.0
	assert_almost_eq(
		overlay.resolution_player.slide_ms,
		137.0,
		0.0001,
		"a typed/assigned value must not snap to the arrow step"
	)


## taskblock-21 Pass B: supersedes tb17 C's hover-tooltip — "clicking a bot
## during a bout pauses the bout and opens the inspect panel on that bot."
## Drives a real `InputEventMouseButton` through `_unhandled_input` (not a
## direct method call, since the click path itself — UnitPicker.hit() off
## a real camera ray — is the thing this test means to prove) with a real
## projected screen position, the same pattern the old hover test used
## (`camera_rig.camera().unproject_position(world_point)`). Sets `playing`
## directly rather than calling the real, async `play()` — `play()` runs
## synchronously up to its own first `await` (inside `_advance()`, AFTER
## `runner.step()` already ran), so calling it here would silently advance
## the bout at least one real turn before the click, leaving `enemy` at a
## stale cell or dead — an unrelated confound this test has no interest in.
func test_clicking_a_unit_pauses_the_bout_and_opens_the_inspect_panel() -> void:
	var built: Dictionary = _bout()
	var overlay: SpectatorOverlay = _spectate(built)
	var enemy: Unit = built.state.units[1]
	overlay.playing = true

	var world_point := Vector3(enemy.cell.x, 0.5, enemy.cell.y) * UnitGeometry.CELL_SIZE
	var screen_pos: Vector2 = overlay.battle.camera_rig.camera().unproject_position(world_point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_pos
	overlay._unhandled_input(click)

	assert_false(overlay.playing, "the click must pause the bout")
	assert_true(overlay.inspect_panel.visible)


## "Closing it resumes" — but only if the bout was actually auto-playing
## before the click; a spectator who had already paused by hand must not
## have the panel silently restart auto-play for them. Same `playing = true`
## reasoning as the test above — only the SECOND half needs `play()` for
## real, since resuming through the real function (not just the flag) is
## exactly what "closing it resumes" needs to prove.
func test_closing_the_inspect_panel_resumes_only_if_it_was_playing_before() -> void:
	var built: Dictionary = _bout()
	var overlay: SpectatorOverlay = _spectate(built)
	var enemy: Unit = built.state.units[1]
	var world_point := Vector3(enemy.cell.x, 0.5, enemy.cell.y) * UnitGeometry.CELL_SIZE
	var screen_pos: Vector2 = overlay.battle.camera_rig.camera().unproject_position(world_point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_pos

	# Already paused before clicking: closing must NOT start auto-play.
	overlay._unhandled_input(click)
	overlay.inspect_panel.close()
	assert_false(overlay.playing, "was already paused — closing must not start auto-play")

	# Was auto-playing before clicking: closing must resume it.
	overlay.playing = true
	overlay._unhandled_input(click)
	overlay.inspect_panel.close()
	assert_true(overlay.playing, "was auto-playing — closing must resume it")


## taskblock-26 Pass E: "objects and tiles don't [have a click inspector]."
## A click that misses every unit's own body now falls through to
## `BoardPicker.cell_at_ray` and opens the SAME `inspect_panel` on whatever
## `Grid.blockers` holds at that cell — `open_tile()`, not a second
## inspector. `crate` sits at a cell with no unit on it, so this proves the
## fallback, not `UnitPicker.hit()`, is what found it.
func test_clicking_a_bare_tile_or_a_tiles_object_opens_the_same_inspect_panel() -> void:
	var built: Dictionary = _bout()
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 4
	crate.max_hp = 4
	built.state.grid.blockers[Vector2i(4, 0)] = crate
	var overlay: SpectatorOverlay = _spectate(built)
	overlay.playing = true

	# taskblock-26 Pass E: unlike the unit-click tests above (which project a
	# point at body HEIGHT, since `UnitPicker.hit` tests a real 3D box, not
	# a ground plane), `BoardPicker.cell_at_ray` intersects the ray with the
	# y == 0 GROUND plane specifically — projecting from any other height
	# and re-casting lands on a DIFFERENT ground point (the ray continues
	# past that height to a shifted x/z), not the point directly below it.
	# The click must originate from a ground-plane (y == 0) world point.
	var world_point := Vector3(4, 0.0, 0) * UnitGeometry.CELL_SIZE
	var camera: Camera3D = overlay.battle.camera_rig.camera()
	var screen_pos: Vector2 = camera.unproject_position(world_point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_pos
	overlay._unhandled_input(click)

	assert_false(overlay.playing, "the click must pause the bout, same as clicking a unit")
	assert_true(overlay.inspect_panel.visible)
	assert_true(overlay.inspect_panel._rows_by_part.has(crate), "the tile's own object shows")


func test_clicking_empty_space_does_nothing() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())
	overlay.playing = true

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(-9999, -9999)  # off the board entirely
	overlay._unhandled_input(click)

	assert_true(overlay.playing, "a click that hits nothing must not pause the bout")
	assert_false(overlay.inspect_panel.visible)


## taskblock-17 Pass C2: "stop auto-snapping — let the spectator drive
## their own camera." The camera's own transform must be byte-identical
## before and after stepping through several turns — CameraRig is never
## told to move by anything in this overlay anymore.
func test_the_camera_never_moves_on_its_own_while_stepping() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())
	var camera: Camera3D = overlay.battle.camera_rig.camera()
	var transform_before: Transform3D = camera.global_transform

	var guard := 0
	while not overlay.runner.finished and guard < 10:
		await overlay.step_once()
		guard += 1

	assert_eq(
		camera.global_transform,
		transform_before,
		"the camera must never move on its own during spectated playback"
	)


## taskblock-15 Pass A's own TESTS list: "a spectator battle is identical
## in outcome to today's BoutRunner bout for the same seed (the overlay
## is cosmetic — prove it)." Two independently-built CombatStates from
## the same seed, one driven by a bare BoutRunner (taskblock-14's own
## path), one driven by SpectatorOverlay stepped to completion — same
## outcome, same turn count. True by construction (SpectatorOverlay IS a
## BoutRunner underneath), but locked in as a real regression test rather
## than left as an architectural claim nobody checks.
func test_a_spectated_bout_matches_a_bare_bout_runner_for_the_same_seed() -> void:
	var bare: Dictionary = _bout(42)
	var bare_runner := BoutRunner.new(bare.state, bare.mission)
	bare_runner.run_to_completion()

	var spectated: Dictionary = _bout(42)
	var overlay: SpectatorOverlay = _spectate(spectated)
	var guard := 0
	while not overlay.runner.finished and guard < 500:
		await overlay.step_once()
		guard += 1

	assert_eq(spectated.mission.outcome, bare.mission.outcome)
	assert_eq(overlay.runner.turns_taken, bare_runner.turns_taken)
