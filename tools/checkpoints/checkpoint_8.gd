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

const README := """# Checkpoint 8

taskblock-40 Pass D: "hand the supervisor a loadable scenario, not a description." Three
hand-built scenarios — a real placed-Surface grid (`GridFixture`, the same call
`MapGen._emit` makes), loaded through the real `BattleScene.load_battle()` entry point,
camera framed through the real `CameraRig.ease_to_framing()` "entering aim" call (tb34 Pass D) —
never a mock, never a re-derived formula. Same grid shape in all three: a ground floor, a real
3x3 elevated platform (3 levels up) at the far side, one real destructible wall on the ground
floor directly between the two areas.

- **`a_target_above.png`** — shooter on the ground, target on the elevated platform. Renders as a
  real over-the-shoulder shot, steep but coherent — this is the one to judge Pass B's tilt-angle
  question against.
- **`b_target_below.png`** — the mirror: shooter on the elevated platform, target on the ground.
  **This one is not a clean framing sample — see BR40.01 below; it currently demonstrates a real
  solver limitation, not a judgment call.**
- **`c_same_level_control.png`** — both on the ground floor, same wall, nothing elevated — the
  baseline every other shot is judged against. Both units clearly visible, wall clearly visible,
  no cutout needed at this angle (target isn't behind the wall from the camera's own solved
  position) and none is visibly present.

Regenerate with `./checkpoint.sh 8`. This file is written by `checkpoint_8.gd` itself, so the
scenario and its checklist can never drift apart; `run.log` alongside it is that run's stdout.

**These artifacts are local only.** Answers to the checklist below belong in
`reports/Report-TaskblockN.md` — that is the committed record. To keep an image, copy it into
`out/checkpoints-kept/`.

## BR40.01 — found building this checkpoint, not a judgment call

`b_target_below.png` doesn't show a target-below shot at all — it shows a wall of green filling
almost the whole frame, no target, no wall visible. Root-caused, not just observed: the solved
camera position (`(8.49, 3.6, 2.1)`) sits **past the far edge of the platform the shooter is
standing on** (which only spans x in [4,6]) — `_solve_back` pushes the camera backward far enough
to fit both bodies' angular footprint, with no awareness that "backward" here walks it off the
platform's own edge. What's on screen is the platform's own solid mass, now between the camera and
everything else. Full root-cause and candidate fixes are on `docs/BUGS.md` **BR40.01** (owner
`CC`) — nothing to re-derive here, just confirm it still reproduces if you regenerate this
checkpoint after any camera-rig change.

## Checklist

One line per item, answerable yes/no without interpretation. Numbers are taskblock-40 Pass B's
own measured height-delta matrix (`test_camera_orbit_state.gd`'s
`test_pass_b_height_delta_matrix_always_fits_and_never_drops_below_the_lower_body`, run against
the exact same solver this checkpoint's camera uses) — every hard invariant they check already
passed headlessly; these questions are for the one thing a number can't answer.

**Camera framing (tb40 Pass B — numerically clean; these ask whether it also LOOKS right):**
1. In `a_target_above.png`, are both the shooter and the target fully on screen?
2. In `c_same_level_control.png`, are both units fully on screen, framed the same familiar way
   as any flat-map shot?
3. Is the shooter positioned between the camera and the target in `a_target_above.png` (a real
   over-the-shoulder shot, not the shooter's own back to the camera or off to one side)?
4. Pass B's own measured vertical look angle grows from ~7° at the same level to ~25-34° at a
   6-level height delta (bounded by the fit search itself, never runaway) — comparing
   `a_target_above.png` against `c_same_level_control.png`: does that tilt still read as a
   coherent aim shot, or does it look broken/disorienting?
5. Does BR40.01's failure mode (camera walking off a small elevated stand) look like something
   that would come up often on real generated maps, or only on a deliberately narrow platform like
   this fixture's 3x3? Worth a priority call, not just a confirmation.

**Wall cutout under elevation (tb40 Pass C, BR32.05 — reasoned from shader source only, never
rendered before now; confirm, don't hunt):**
6. In `c_same_level_control.png`, is the wall rendered solid (no cutout), matching the fact that
   nothing is actually between the camera and either unit at this angle?
7. In `a_target_above.png`, can you find the wall at all, or does it read as fully hidden behind
   the shooter's own body from this angle (plausible — wall and shooter are only 1-2 cells apart,
   nearly on the same sightline)? If hidden, that's not evidence either way for BR32.05 — note it
   and, if a clean look at the cutout matters, reposition the wall via `Inject...` (BoutInjector)
   in a live session rather than reading a null result out of this fixed angle.
8. In any screenshot, is a chunk cut from a part of the wall that is clearly NOT between the
   camera and either unit (BR32.05's own named symptom)?
9. In any screenshot, does a cutout expose unlit/placeholder wall-interior texture where it
   shouldn't (BR32.05's own "interior-texture exposure" sub-symptom)?

If 8 or 9 come back yes, that's live confirmation of BR32.05's own elevation finding (tb40 Pass
C) — note which screenshot and roughly where on the wall; no new `docs/BUGS.md` entry needed,
append to BR32.05 instead (already covers this root cause).

Headless coverage for everything these screenshots can't show — both-fit and never-below-body
across the full +/-1, +/-3, +/-6 delta matrix, continuity across the zero crossing, the pinned
same-level regression guard — lives in `test/unit/logic/test_camera_orbit_state.gd`.
"""

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


## taskblock-41 Pass E: the scenario owns its own README and checklist. They
## used to live in a heredoc inside `run_visual_checkpoint.sh`, which meant the
## shell driver grew ~70 lines per scenario and the description sat a file away
## from the code it described — easy to leave stale. Written on every run, so
## regenerating the images always regenerates the questions about them.
func _write_readme() -> void:
	var file := FileAccess.open("%s/README.md" % _out_dir, FileAccess.WRITE)
	if file == null:
		push_error("checkpoint_8: could not write README.md into %s" % _out_dir)
		return
	file.store_string(README)
	file.close()
	print("SAVED README.md")


func _save(file_name: String) -> void:
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, file_name])
	print("SAVED %s" % file_name)


## A flat `GRID_WIDTH`x`GRID_ROWS` room at level 0, a real 3x3 floored
## platform at `ELEVATED_LEVEL` (x in [4,6], y in [2,4] — enough for a
## unit's own footprint plus a margin, not a single cell), and a real
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
	# the player mode's own `battle_loaded` reaction triggers on load otherwise.
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
			_write_readme()
			print("CHECKPOINT_8_DONE")
			return true

	_step += 1
	return false
