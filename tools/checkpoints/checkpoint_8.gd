extends SceneTree

## Checkpoint 8 generator (taskblock-40 Pass D): "hand the supervisor a
## loadable scenario, not a description." Three hand-built scenarios, each
## a real placed-Surface grid (`GridFixture`, the same call `MapGen._emit`
## makes) loaded through the real `BattleScene.load_battle()` entry point —
## never a mock — with the real attack-camera solve (`CameraRig.
## ease_to_framing`, tb34 Pass D's own "entering aim" entry point) framing
## each pair, so what's on screen is exactly what a player's own aim step
## would show. Needs a real GPU frame (`--display-driver x11` or similar),
## never `--headless`. Run via `./checkpoint.sh 8`.
##
## taskblock-40 Pass B's own height-delta matrix already proved, numerically,
## that both bodies fit and the camera never sits below the lower body
## across every case here — these screenshots are for the one question
## numbers can't answer: does the solved framing read as sensible to a
## human. taskblock-40 Pass C's wall-cutout finding (BR32.05) was reasoned
## from shader source only, never rendered — the same wall sits between
## shooter and target in every scenario below so the supervisor can confirm
## it against a real frame instead.

const GRID_WIDTH := 9
const GRID_ROWS := 7
const ELEVATED_LEVEL := 3.0
const DEFAULT_OUT_DIR := "out/checkpoints/08"

var _out_dir: String
var _battle_scene: Node3D
var _elapsed := 0.0
var _step := 0
var _next_step_at := 0.5


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


## A flat `GRID_WIDTH`x`GRID_ROWS` room at level 0, a real 3x3 floored
## platform at `ELEVATED_LEVEL` (x in [4,6], y in [2,4] — enough for a
## unit's own footprint plus a margin, not a single tile), and a real
## destructible wall on the level-0 floor at (3, 3), directly between the
## ground area and the platform. The same shape serves all three scenarios
## below; which cell each unit actually stands on is what changes.
func _build_grid() -> Grid:
	var grid: Grid = GridFixture.flat(GRID_WIDTH, GRID_ROWS, 0.0)
	for y in range(2, 5):
		for x in range(4, 7):
			GridFixture.place_floor(grid, Vector2i(x, y), ELEVATED_LEVEL)
	GridFixture.place_wall(grid, Vector2i(3, 3), 0.0)
	return grid


## `DeepStrike.assemble_reference_humanoid` never sets `unit.height` itself
## (every assembly path leaves that to whoever actually places the unit on
## a grid — see `BoutInjector.set_cell_level`'s own identical assignment)
## — read back from the real placed Surface at `cell`, never assumed from
## the level passed to `_build_grid`, so a unit's rendered height always
## matches what `Pathfinder`/damage resolution would also read.
func _place_unit(grid: Grid, cell: Vector2i, squad_id: int) -> Unit:
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, squad_id)
	unit.height = UnitGeometry.true_height_for_cell(cell, grid)
	return unit


## Loads a fresh scenario and eases the camera to it through the real
## "entering aim" entry point (`CameraRig.ease_to_framing`, tb34 Pass D) —
## the same distance-gated attack/sniper choice a player's own aim click
## makes, never a re-derived framing call.
func _load_scenario(shooter_cell: Vector2i, target_cell: Vector2i) -> void:
	var grid: Grid = _build_grid()
	var shooter: Unit = _place_unit(grid, shooter_cell, 0)
	var target: Unit = _place_unit(grid, target_cell, 1)
	var state := CombatState.new(grid, [shooter, target])
	# Both HUMAN: a static viewing scenario, never meant to be played turn by
	# turn -- `assign_all_to_human()` is the real "Control All Squads"
	# authoring shortcut (tb31 Pass B), not a hand-set fallback, and avoids
	# `BoutRunner`'s own "squad controller(s) never assigned" refusal that
	# `SquadControlOverlay.battle_loaded` triggers on load otherwise.
	state.assign_all_to_human()
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	_battle_scene.load_battle(state, mission)

	var shooter_sphere: Dictionary = UnitGeometry.bounding_sphere(shooter)
	var target_sphere: Dictionary = UnitGeometry.bounding_sphere(target)
	var distance_cells: int = maxi(
		absi(target_cell.x - shooter_cell.x), absi(target_cell.y - shooter_cell.y)
	)
	_battle_scene.camera_rig.ease_to_framing(shooter_sphere, target_sphere, distance_cells)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < _next_step_at:
		return false

	match _step:
		0:
			# Scenario A: target ABOVE the shooter — taskblock-40 Pass C's own
			# Case 1 (a low wall genuinely between them, should cut).
			_load_scenario(Vector2i(1, 3), Vector2i(5, 3))
			_next_step_at = _elapsed + CameraRig.ATTACK_TWEEN_DURATION + 0.3
		1:
			_save("a_target_above.png")
			_next_step_at = _elapsed + 0.1
		2:
			# Scenario B: target BELOW the shooter — the mirror of A, shooter
			# on the elevated platform this time.
			_load_scenario(Vector2i(5, 3), Vector2i(1, 3))
			_next_step_at = _elapsed + CameraRig.ATTACK_TWEEN_DURATION + 0.3
		3:
			_save("b_target_below.png")
			_next_step_at = _elapsed + 0.1
		4:
			# Scenario C: same-level control — both on the ground floor, same
			# wall in the same place, nothing elevated at all.
			_load_scenario(Vector2i(1, 5), Vector2i(5, 5))
			_next_step_at = _elapsed + CameraRig.ATTACK_TWEEN_DURATION + 0.3
		5:
			_save("c_same_level_control.png")
			_next_step_at = _elapsed + 0.1
		6:
			print("CHECKPOINT_8_DONE")
			return true

	_step += 1
	return false
