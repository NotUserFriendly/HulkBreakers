extends GutTest

## tb32 Pass B (corrected design): the friendly-fade decision now lives on
## `BattleScene` (`_process()`/`_occluding_friendlies()`), which is the one
## place holding both the live camera (`board_view`) and every unit's real
## `HitVolumeView` — the first version tried to do this from `BoardView`
## alone via a separate ghost overlay, which never touched the friendly's
## own already-opaque body (see `HitVolumeView.set_occlusion_faded`'s own
## doc comment). These tests drive `battle._process()` directly against a
## real, hand-placed scene and read the REAL `HitVolumeView`'s material
## back — never re-deriving the occlusion decision a second time.


func _armed_unit(cell: Vector2i, squad: int) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]
	pistol.provides_actions = [&"shoot"]
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
	var matrix_socket := Socket.new(&"MATRIX")
	torso.sockets = [hand_socket, matrix_socket]
	# A piloted (not downed) unit — is_downed() gates the facing wedge, and
	# a "downed" unit renders in a different pose, both of which would
	# otherwise make this fixture's own child indices unpredictable.
	torso.dock_matrix(Matrix.new())
	return Unit.new(torso.hosted_matrix, Shell.new(torso), cell, squad)


## Shooter at (5,5), a friendly directly between the camera and the
## shooter once the real attack-camera framing eases (verified via
## `TacticsController`'s own real click-to-aim flow, not a hand-positioned
## camera), and an enemy target far off at (5,10). Returns the loaded
## `BattleScene` plus the three units.
func _occlusion_scene() -> Dictionary:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var shooter := _armed_unit(Vector2i(5, 5), 0)
	var friendly := _armed_unit(Vector2i(5, 4), 0)
	var enemy := _armed_unit(Vector2i(5, 10), 1)
	var state := CombatState.new(Grid.new(20, 20), [shooter, friendly, enemy])
	state.set_squad_controller(0, Enums.SquadController.HUMAN)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	scene.load_battle(state, mission)
	scene.set_overlay(SquadControlOverlay.new())
	var overlay: SquadControlOverlay = scene.overlay as SquadControlOverlay
	overlay.tactics.click_cell(shooter.cell)
	overlay.tactics.arm_action(&"shoot")
	overlay.tactics.click_cell(enemy.cell)
	scene.camera_rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION)
	return {"scene": scene, "shooter": shooter, "friendly": friendly, "enemy": enemy}


func test_occluding_friendly_gets_faded_on_the_real_hit_volume_view() -> void:
	var built: Dictionary = _occlusion_scene()
	var scene: BattleScene = built.scene

	scene._process(0.016)

	var friendly_view: HitVolumeView = scene.find_unit_view(built.friendly.id)
	assert_true(
		friendly_view._occlusion_faded, "a friendly blocking the shooter's own read must fade"
	)
	var torso_mesh: MeshInstance3D = friendly_view.get_child(2)
	assert_not_null(torso_mesh.material_override, "the fade must apply to the real rendered body")


func test_the_active_shooter_never_fades_itself() -> void:
	var built: Dictionary = _occlusion_scene()
	var scene: BattleScene = built.scene

	scene._process(0.016)

	var shooter_view: HitVolumeView = scene.find_unit_view(built.shooter.id)
	assert_false(shooter_view._occlusion_faded, "the active unit must never fade itself")


func test_an_enemy_in_the_same_spot_is_never_faded() -> void:
	var built: Dictionary = _occlusion_scene()
	var scene: BattleScene = built.scene
	var enemy_view: HitVolumeView = scene.find_unit_view(built.enemy.id)
	enemy_view.unit.cell = built.friendly.cell

	scene._process(0.016)

	assert_false(enemy_view._occlusion_faded, "an enemy must never fade — friendly-only")


func test_leaving_aim_clears_the_fade() -> void:
	var built: Dictionary = _occlusion_scene()
	var scene: BattleScene = built.scene
	scene._process(0.016)
	var friendly_view: HitVolumeView = scene.find_unit_view(built.friendly.id)
	assert_true(friendly_view._occlusion_faded, "sanity: fade fired while aiming")

	(scene.overlay as SquadControlOverlay).tactics.cancel_aim()
	scene._process(0.016)

	assert_false(friendly_view._occlusion_faded, "leaving aim must restore full opacity")


## A real, reported bug: an extracted friendly (docs/07) never clears its
## own stale `.cell`, and its HitVolumeView stays live (extraction never
## calls remove_unit_view) — without this, an extracted friendly would
## visibly fade as if it were still standing there blocking the shot.
func test_an_extracted_friendly_is_never_faded() -> void:
	var built: Dictionary = _occlusion_scene()
	var scene: BattleScene = built.scene
	built.friendly.extracted = true

	scene._process(0.016)

	var friendly_view: HitVolumeView = scene.find_unit_view(built.friendly.id)
	assert_false(friendly_view._occlusion_faded, "an extracted unit must never fade")


## `BattleScene.remove_unit_view()` (the debug-only "make it fully
## vanish" verb) must also stop feeding that unit's own stale cell into
## the wall-cutout shader — otherwise a debug-removed unit leaves a
## permanent, unit-less hole exactly where it was removed.
func test_removing_a_unit_view_excludes_it_from_occlusion() -> void:
	var built: Dictionary = _occlusion_scene()
	var scene: BattleScene = built.scene
	assert_false(scene.board_view.is_excluded_from_occlusion(built.friendly.id))

	scene.remove_unit_view(built.friendly)

	assert_true(scene.board_view.is_excluded_from_occlusion(built.friendly.id))
