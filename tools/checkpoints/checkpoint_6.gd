extends SceneTree

## Checkpoint 6 generator (docs/09, Phase 12.1: the battle renders). Loads
## the real BattleScene — no mocked view — and captures its default-seeded
## battle plus a synthetic 12-shoulder rig, the exact acceptance case
## PLAN.md's Phase 12.0/12.1 exists to prove (one arm template, twelve
## SHOULDER sockets, no two arms landing on the same coordinates). Needs a
## real GPU frame (`--display-driver x11` or similar) — `--headless` only
## has the no-op renderer and can't produce one. Run via `./checkpoint.sh 6`.

const TWELVE_ARM_SOCKET_COUNT := 12
const TWELVE_ARM_SPACING := 0.6
const DEFAULT_OUT_DIR := "out/checkpoints/06"

var _out_dir: String
var _step := 0
var _battle_scene: Node3D
var _rig_scene: Node3D
var _rig: CameraRig


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else DEFAULT_OUT_DIR

	var packed: PackedScene = load("res://src/view/battle_scene.tscn")
	_battle_scene = packed.instantiate()
	root.add_child(_battle_scene)


func _build_twelve_arm_unit() -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.material = &"steel"
	torso.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 0.6))]

	var sockets: Array[Socket] = []
	for i in range(TWELVE_ARM_SOCKET_COUNT):
		var x: float = (i - (TWELVE_ARM_SOCKET_COUNT - 1) / 2.0) * TWELVE_ARM_SPACING
		var socket := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(x, 0.5, 0.0)))
		var arm := Part.new()
		arm.id = StringName("arm_%d" % i)
		arm.hp = 4
		arm.max_hp = 4
		arm.material = &"sheet_steel"
		arm.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]
		socket.occupant = arm
		sockets.append(socket)
	torso.sockets = sockets

	return Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))


func _save(file_name: String) -> void:
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, file_name])
	print("SAVED %s" % file_name)


func _process(_delta: float) -> bool:
	_step += 1

	match _step:
		10:
			# Default-seeded battle (BattleScene._ready -> new_battle(DEFAULT_SEED)),
			# both units and the board already visible with no further setup.
			_save("board_wide.png")
		20:
			var rig: CameraRig = _battle_scene.camera_rig
			rig.state.zoom = 4.0
			var unit0: Unit = _battle_scene.combat_state.units[0]
			rig.state.pan_offset = Vector3(unit0.cell.x, 0.0, unit0.cell.y)
			rig._apply_state()
		25:
			_save("cyborg_closeup.png")
		28:
			# Fresh scene for the rig case: the only Camera3D left in the tree
			# after this is freed is the new rig's, so it becomes current
			# automatically, same as a from-scratch scene would.
			_battle_scene.queue_free()
			_battle_scene = null
		32:
			_rig_scene = Node3D.new()
			root.add_child(_rig_scene)
			_rig_scene.add_child(WorldPalette.world_environment())
			_rig_scene.add_child(WorldPalette.directional_light())
			_rig = CameraRig.new()
			_rig_scene.add_child(_rig)
			var view := UnitView.new()
			_rig_scene.add_child(view)
			view.setup(_build_twelve_arm_unit(), MaterialTable.default_table())
		36:
			_rig.state.zoom = 10.0
			_rig.state.pitch = -0.3
			_rig._apply_state()
		40:
			_save("twelve_arm_rig.png")
		44:
			print("CHECKPOINT_6_DONE")
			return true

	return false
