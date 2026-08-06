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

## taskblock-58 Pass E: **the whole pick under the cursor**, carrying the struck face.
##
## `hovered_cell` answers "which cell", which is what a coordinate readout wants and all anything
## wanted until a ghost had to know *which face* of what is there. Emitted as `PartPicker.hit`'s own
## dict — `{unit, part, cell, t, normal}` — or empty when the cursor is over nothing, so a listener
## can tell "no geometry" from "geometry with no face", which are different situations.
##
## **A second signal rather than a wider `hovered_cell`**: that one is connected by
## `EditorCoordsModule` and means something narrower, and widening it would make every listener
## take a dict to read a coordinate.
signal hovered_pick(pick: Dictionary)
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
##
## **taskblock-57 Pass H: it returns false, always, and that is a statement.** The host now offers
## input to every module in declaration order and stops at the first that consumes it. This module
## never claims exclusivity: a mode that wants something to get a click *before* the board picker
## declares that module earlier and has it consume, which is exactly what the editor's gizmo does.
## Consuming here would make the board picker the end of the line for every event on the surface.
func handle_input(event: InputEvent) -> bool:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.combat_state == null:
		return false
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
		return false
	if event is not InputEventMouseButton:
		return false
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return false
	var camera: Camera3D = battle.camera_rig.camera() if battle.camera_rig != null else null
	if camera == null:
		return false
	_click_at(mb.position, camera, battle)
	return false


## What a left press on the board does, once the guards above have found a camera and a state.
##
## **Split out of `handle_input` rather than inlined**: the guards and the click are two different
## questions, and folding them into one function put eleven `return`s in it. Nothing here consumes
## the event — see `handle_input`.
func _click_at(screen_pos: Vector2, camera: Camera3D, battle: BattleScene) -> void:
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	# taskblock-59 follow-up: **surfaces included, so a click on a floor strikes the floor.** Without
	# it a plain tile answered `{}` and the editor placed into the cell it had just clicked rather
	# than against a face of what was there. `input_capture_mode` is the editor's own mode, and the
	# inspector benefits identically: clicking a floor should inspect the floor.
	var hit: Dictionary = PartPicker.hit(
		battle.combat_state.units, battle.combat_state.grid, from, dir, true
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
	var cell: Variant = _emit_hovered_cell(from, dir, battle.combat_state.grid)
	# taskblock-58 Pass E: the full pick, for a listener that needs the struck face. **Only when
	# somebody is connected** — this is `PartPicker.hit` on every motion event, which `BR35.01`
	# measured at 1 559 usec on a real board, and a mode with no ghost has no reason to pay it.
	if hovered_pick.get_connections().size() > 0:
		hovered_pick.emit(
			_pick_or_bare_cell(
				PartPicker.hit(
					battle.combat_state.units, battle.combat_state.grid, from, dir, true
				),
				cell,
				battle.combat_state.grid
			)
		)
	var hit: Dictionary = UnitPicker.hit(battle.combat_state.units, from, dir)
	var hovered_unit: Unit = hit.unit as Unit if not hit.is_empty() else null
	var hovered_part: Part = hit.part as Part if not hit.is_empty() else null
	for view: HitVolumeView in battle.unit_views:
		if view.unit == hovered_unit:
			view.highlight_part(hovered_part)
		else:
			view.clear_highlight()


## Emits the cell the cursor is over, and returns it. Null when the ray misses the board or lands
## off its edge.
##
## **Off-board is `null`, not the nearest cell.** The readout says what is under the cursor, and
## "the last cell before you left" is a different claim that reads as the cursor being stuck.
func _emit_hovered_cell(from: Vector3, dir: Vector3, grid: Grid) -> Variant:
	var cell: Variant = BoardPicker.cell_at_ray(from, dir, grid)
	if cell != null and not grid.in_bounds(cell as Vector2i):
		cell = null
	hovered_cell.emit(cell)
	return cell


## taskblock-59 Pass B: **an empty cell is a pick too.**
##
## `PartPicker.hit` answers `{}` over bare board, because it found no part — which is true and is
## the wrong answer for a listener asking *"what is under the cursor"*. The editor's ghost took it
## as "nothing to preview" and drew nothing, so **the one place an author most needs to know what a
## click will do — an empty tile, where there is nothing to infer it from — was the one place the
## preview was silent.**
##
## The bare-cell form carries a `null` normal, which is exactly what `FacePlacement.target_from`
## already reads as *"no struck face, use the authored height"*. So nothing downstream learns a new
## case; the branch that handles a click off the ground plane handles this too.
##
## ## Only when the cell really is empty, and that was a regression
##
## taskblock-59 follow-up. `BoardPicker.cell_at_ray` resolves against the board's own terrain plane,
## so **any** ray that eventually crosses the board yields a cell — including one passing well above
## a tile, or over a wall at something behind it. Substituting that whenever the box test missed
## reported geometry the cursor was not on.
##
## Reported as *"pointing at where the side of a floor would be if it were ~1.7 units higher up
## highlights it... almost like there's an invisible copy higher up"* and *"it's almost like I can
## click things behind the actual object I'm aiming at."* One cause, and it is the fallback being
## unconditional rather than anything phantom: point above a tile and the ray still meets the plane
## at that tile's cell, so a ghost drew there.
##
## **A cell holding something the ray missed is a cell the cursor is not on.** The fallback exists
## for the empty tile — *"where an author most needs to know what a click will do"* — and that is
## exactly the case it is now limited to.
static func _pick_or_bare_cell(pick: Dictionary, cell: Variant, grid: Grid = null) -> Dictionary:
	if not pick.is_empty() or cell == null:
		return pick
	if grid != null and _holds_anything(grid, cell as Vector2i):
		return {}
	return {"unit": null, "part": null, "cell": cell, "t": INF, "normal": null}


## Whether `cell` has any geometry on it at all. **Anything the picker could have struck** — if the
## box test missed all of it, the ray is passing over or behind rather than pointing at it.
static func _holds_anything(grid: Grid, cell: Vector2i) -> bool:
	if grid.blockers.has(cell) or not grid.surfaces_at(cell).is_empty():
		return true
	return not (grid.field_items.get(cell, []) as Array).is_empty()


func _inspect() -> InspectModule:
	var module: ViewModule = context.module(&"inspect") if context != null else null
	return module as InspectModule
