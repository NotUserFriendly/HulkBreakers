extends SceneTree

## Checkpoint 7 generator (docs/09, Phase 12 close-out): "a human launches
## the game, selects a cyborg, queues a move and an aimed shot... ends the
## turn, watches the burst fire and ricochet, and reads the log —
## repeatedly, until one side is down." Drives that loop for real through
## the same public TacticsController/CameraRig API a player's mouse would
## use. Two hand-armed cyborgs (guaranteed a working weapon — the default
## battle's DeepStrike.assemble_random loadouts are not guaranteed armed)
## trade pistol fire across several rounds.
##
## Run with `--write-movie <path>.avi` for the recording; this script also
## grabs three PNG stills along the way so there's something to look at
## without playing the video. Needs a real GPU frame (`--display-driver
## x11` or similar), never `--headless`. Run via `./checkpoint.sh 7`.

const FIRST_IMPACT_DELAY := LogPlayback.RESOLVE_LEAD_IN + 0.05
const DEFAULT_OUT_DIR := "out/checkpoints/07"

var _out_dir: String
var _battle_scene: Node3D
var _elapsed := 0.0
var _step := 0
var _next_step_at := 0.3
var _turns_taken := 0
var _shot_fired_at := -1.0
var _captured_first_impact := false
var _captured_round1 := false
var _captured_round2 := false


func _armed_unit(cell: Vector2i, squad: int, unit_id: StringName) -> Unit:
	var pistol := Part.new()
	pistol.id = StringName("%s_pistol" % unit_id)
	pistol.hp = 2
	pistol.max_hp = 2
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 4.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.15, 1.0), Ring.new(0.5, 2.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % unit_id)
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = StringName("%s_torso" % unit_id)
	torso.hp = 16
	torso.max_hp = 16
	torso.material = &"sheet_steel"
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Frame.new(torso), cell, squad)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else DEFAULT_OUT_DIR

	var packed: PackedScene = load("res://src/view/battle_scene.tscn")
	_battle_scene = packed.instantiate()
	root.add_child(_battle_scene)


func _save(file_name: String) -> void:
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, file_name])
	print("SAVED %s" % file_name)


func _take_turn(tactics: TacticsController, state: CombatState) -> bool:
	var current: Unit = state.current_unit()
	tactics.click_cell(current.cell)

	var enemy: Unit = null
	for u: Unit in state.units:
		if u.alive and u.squad_id != current.squad_id:
			enemy = u
			break
	if enemy == null:
		tactics.end_turn()
		return false

	if DeepStrike.find_operable_weapon(current) != null:
		tactics.click_cell(enemy.cell)  # enter aim mode
		if tactics.aiming_at != null:
			tactics.confirm_shot()
			tactics.end_turn()
			return true
	tactics.end_turn()
	return false


func _process(delta: float) -> bool:
	_elapsed += delta

	if _shot_fired_at > 0.0 and not _captured_first_impact:
		if _elapsed - _shot_fired_at >= FIRST_IMPACT_DELAY:
			_save("frame_first_impact.png")
			_captured_first_impact = true

	if _elapsed < _next_step_at:
		return false

	var tactics: TacticsController = _battle_scene.tactics

	match _step:
		0:
			var jerry := _armed_unit(Vector2i(3, 5), 0, &"jerry")
			var raider := _armed_unit(Vector2i(8, 5), 1, &"raider")
			var grid := Grid.new(12, 10)  # open ground: guarantees LoS for the demo
			_battle_scene.combat_state = CombatState.new(grid, [jerry, raider], 1)
			_battle_scene.combat_state.combat_log.add_sink(_battle_scene.log_sink)
			_battle_scene.board_view.build(grid, _battle_scene.combat_state.material_table)
			_battle_scene.tactics.setup(
				_battle_scene.combat_state, _battle_scene.board_view, _battle_scene.camera_rig
			)
			for view in _battle_scene.unit_views:
				view.queue_free()
			_battle_scene.unit_views.clear()
			for unit in _battle_scene.combat_state.units:
				var view := UnitView.new()
				_battle_scene.add_child(view)
				view.setup(unit, _battle_scene.combat_state.material_table)
				_battle_scene.unit_views.append(view)

			_battle_scene.camera_rig.center_on(Vector3(5.5, 0.0, 5.0))
			_battle_scene.camera_rig.state.zoom = 10.0
			_battle_scene.camera_rig.state.pitch = -0.45
			_battle_scene.camera_rig._apply_state()
			_next_step_at = _elapsed + 1.0
		1, 2, 3, 4, 5, 6:
			var state: CombatState = _battle_scene.combat_state
			var alive_squads: Dictionary = {}
			for u: Unit in state.units:
				if u.alive:
					alive_squads[u.squad_id] = true
			if alive_squads.size() >= 2:
				var fired := _take_turn(tactics, state)
				if fired and _shot_fired_at < 0.0:
					_shot_fired_at = _elapsed
				_turns_taken += 1
				if _turns_taken == 2 and not _captured_round1:
					_save("frame_round1_exchange.png")
					_captured_round1 = true
				if _turns_taken == 4 and not _captured_round2:
					_save("frame_round2_exchange.png")
					_captured_round2 = true
				_next_step_at = _elapsed + 3.2  # let resolution play out on screen
			else:
				_next_step_at = _elapsed + 0.01
		7:
			print("PLAYTHROUGH_DONE")
			return true

	_step += 1
	return false
