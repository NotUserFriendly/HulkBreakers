class_name BoardInspectModule
extends ViewModule

## taskblock-56 Pass C: click a body on the board to inspect it, hover one to highlight it.
##
## The spectator's whole board interaction. **Display**: it opens a modal and tints a mesh, and
## queues nothing — a spectator can look at anything and command nothing.
##
## **`PartPicker`, not `UnitPicker`, for the click.** taskblock-51 Pass K: this path saw units only,
## so a click on cover fell through to the cell branch and selected the ground underneath — the
## supervisor's "selecting a barrel selects the cell beneath", literally. `PartPicker` is the same
## ray-vs-box maths plus the blockers and field items the board already draws. The hover path below
## still uses `UnitPicker`, because highlighting is a unit-body affordance; that asymmetry is
## inherited, not introduced.
##
## **A bare cell opens nothing** (`BR48.01`). The cell branch used to pass `blockers.get(cell)`
## straight through, which is null for a bare cell, and the panel then rendered its matrixless shape
## with no root — a 900x600 modal over the board containing nothing, having paused the bout. That is
## the supervisor's *"selecting a bare cell causes the screen to dim"*, and it reads as a stuck dim
## because there is nothing in the panel to explain what happened.

## The same normalized `{"kind", "unit", "cell"}` shape `TacticsController.board_clicked` emits, so
## a debug panel can borrow a click against either module identically.
signal board_clicked(hit: Dictionary)

## taskblock-57 Pass G2: **the cell under the cursor**, emitted on every mouse motion that lands on
## the board, and once with the board's own out-of-bounds answer when it leaves.
##
## The editor's coordinate readout needs "which cell is the cursor over" and this module already
## owns the motion handler, the camera and the ray — a second module casting its own ray on every
## mouse move would be a second answer to one question, computed twice a frame.
##
## `cell` is `null` when the cursor is off the board entirely, which the readout shows as blank
## rather than as the last cell it saw.
signal hovered_cell(cell: Variant)
## Emitted when a click opened the inspect panel, so a mode that paces a bout can pause it.
signal inspect_opened

## While true, the next real click is captured and emitted instead of doing the normal thing.
## `DebugControlPanel` sets this through `input_owner`.
var input_capture_mode: bool = false
## taskblock-57 Pass D: whether a click that hit nothing else may open the floor tile.
## **Off by default and driven by the debug menu** — see `DebugUiElements.FLOOR_TILE_PICKING`.
var floor_tile_picking: bool = false

## Whether the bout was actually auto-playing when a click opened the inspect panel. **"Closing it
## resumes" must never START auto-play** for someone who had already paused by hand before clicking.
var _was_playing_before_inspect: bool = false


func module_id() -> StringName:
	return &"board_inspect"


## Clicking a body pauses the bout and opens the panel; closing it resumes, but only if it was
## running. Both halves live here because both are consequences of this module's own click.
func link() -> void:
	# The floor-tile toggle is offered by the debug menu and consumed here, the same way the
	# performance readout's is. A mode with no debug panel simply never turns it on.
	var debug: ViewModule = context.module(&"debug_panel")
	if debug != null:
		(debug as DebugPanelModule).ui_element_toggled.connect(_on_ui_element_toggled)
	inspect_opened.connect(_on_inspect_opened)
	var inspect: ViewModule = context.module(&"inspect")
	if inspect != null:
		(inspect as InspectModule).closed.connect(_on_inspect_closed)


func _on_ui_element_toggled(element: StringName, shown: bool) -> void:
	if element == DebugUiElements.FLOOR_TILE_PICKING:
		floor_tile_picking = shown


func _on_inspect_opened() -> void:
	var pacing: PlaybackModule = _playback()
	if pacing == null:
		return
	_was_playing_before_inspect = pacing.playing
	pacing.pause()


func _on_inspect_closed() -> void:
	var pacing: PlaybackModule = _playback()
	if pacing != null and _was_playing_before_inspect:
		pacing.play()


func _playback() -> PlaybackModule:
	var module: ViewModule = context.module(&"playback") if context != null else null
	return module as PlaybackModule


## **Called by the host, not by the engine.** A module defining `_unhandled_input` would receive
## events wherever the host happened to parent it, and a host that also forwards would dispatch the
## same click twice. One entry point, owned by whoever mounted this — the same reasoning that keeps
## the per-frame `tick` on the host.
func handle_input(event: InputEvent) -> void:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.combat_state == null:
		return
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
		return
	if event is not InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var camera: Camera3D = battle.camera_rig.camera() if battle.camera_rig != null else null
	if camera == null:
		return
	var from: Vector3 = camera.project_ray_origin(mb.position)
	var dir: Vector3 = camera.project_ray_normal(mb.position)
	var hit: Dictionary = PartPicker.hit(
		battle.combat_state.units, battle.combat_state.grid, from, dir
	)
	var target: SelectionTarget = SelectionTarget.from_pick(hit)
	if input_capture_mode:
		_capture(target, from, dir, battle)
		return
	var inspect: InspectModule = _inspect()
	if inspect != null and inspect.open_target(target):
		inspect_opened.emit()
		return
	# A ray that missed every body but hit the ground plane still opens whatever stands on that
	# cell — a real object, just picked coarsely.
	var cell: Variant = BoardPicker.cell_at_ray(from, dir, battle.combat_state.grid)
	if cell == null or not battle.combat_state.grid.in_bounds(cell as Vector2i):
		return
	var cell_root: Part = battle.combat_state.grid.blockers.get(cell)
	if cell_root == null:
		# **taskblock-57 Pass D: the floor tile, and only when it has been asked for.**
		#
		# *"Everything is a part"*, so the tile under a cell is as inspectable as anything standing
		# on it. But it is also under **every** cell, which is why the taskblock gates it: *"rare
		# targets — floor tiles especially — should need enabling from the debug menu rather than
		# being clickable by default, or every misclick lands on the floor."* Off, a click that hit
		# nothing does nothing, which is what it did before this pass.
		if not floor_tile_picking:
			return
		cell_root = _tile_at(cell as Vector2i, battle.combat_state.grid)
		if cell_root == null:
			return
	if inspect != null and inspect.open_cell(cell as Vector2i, cell_root):
		inspect_opened.emit()


## The walkable part a unit would stand on at `cell`, or null for an unfloored one.
##
## **The topmost surface**, because that is the one you can see and the one you would stand on —
## `UnitGeometry.true_height_for_cell` answers the same question about height and this is the part
## that answers it.
func _tile_at(cell: Vector2i, grid: Grid) -> Part:
	var best: Part = null
	var best_height: float = -INF
	for surface: Surface in grid.surfaces_at(cell):
		if surface.part != null and surface.height >= best_height:
			best = surface.part
			best_height = surface.height
	return best


func _capture(target: SelectionTarget, from: Vector3, dir: Vector3, battle: BattleScene) -> void:
	var resolved: SelectionTarget = target
	if target.empty:
		var picked: Variant = BoardPicker.cell_at_ray(from, dir, battle.combat_state.grid)
		if picked == null:
			return
		resolved = SelectionTarget.for_cell(picked as Vector2i)
	board_clicked.emit(resolved.to_hit())


## Whichever unit the cursor is over gets highlighted, and every other view clears.
##
## Unlike `TacticsController.update_hover`, which only highlights the *selected* unit's own parts,
## a display-only mode has no selection at all — so the thing under the cursor is the only sensible
## subject.
func _update_hover(screen_pos: Vector2) -> void:
	var battle: BattleScene = context.battle
	var camera: Camera3D = battle.camera_rig.camera() if battle.camera_rig != null else null
	if camera == null:
		return
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	# taskblock-57 Pass G2: the cell under the cursor, off the ray this handler already cast. Emitted
	# before the highlight so a listener sees the move even in a mode with no unit views at all —
	# which the editor is, until a board is loaded into it.
	_emit_hovered_cell(from, dir, battle.combat_state.grid)
	var hit: Dictionary = UnitPicker.hit(battle.combat_state.units, from, dir)
	var hovered_unit: Unit = hit.unit as Unit if not hit.is_empty() else null
	var hovered_part: Part = hit.part as Part if not hit.is_empty() else null
	for view: HitVolumeView in battle.unit_views:
		if view.unit == hovered_unit:
			view.highlight_part(hovered_part)
		else:
			view.clear_highlight()


## Emits the cell the cursor is over, or null when the ray misses the board or lands off its edge.
##
## **Off-board is `null`, not the nearest cell.** The readout says what is under the cursor, and
## "the last cell before you left" is a different claim that reads as the cursor being stuck.
func _emit_hovered_cell(from: Vector3, dir: Vector3, grid: Grid) -> void:
	var cell: Variant = BoardPicker.cell_at_ray(from, dir, grid)
	if cell != null and not grid.in_bounds(cell as Vector2i):
		cell = null
	hovered_cell.emit(cell)


func _inspect() -> InspectModule:
	var module: ViewModule = context.module(&"inspect") if context != null else null
	return module as InspectModule
