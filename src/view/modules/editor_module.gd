class_name EditorModule
extends ViewModule

## taskblock-56 Pass F: **the editor, as one module over a mode's worth of existing ones.**
##
## The block called the editor its own proof: *"the editor mode should be a module set plus one new
## authoring module. If it is not — if it needs to subclass, or reach into another mode, or
## duplicate a panel — say so plainly."* This is that one module, and what it does **not** contain
## is the evidence:
##
## | the editor needs | it comes from |
## |---|---|
## | a board to look at | `BattleScene`'s own `BoardView`, unchanged |
## | clicks on that board | `BoardInspectModule`, in the capture mode the debug panel already uses |
## | claims drawn | `ClaimVolumeModule`, which has been sitting tested and unmounted since Pass E |
## | the camera pointed at what loaded | `CameraFramingModule`, unchanged |
## | a place to read what happened | `CombatLogModule`, unchanged |
## | a layout to sit in | `ModeChrome.PLAYER_COLUMNS`, unchanged — **no new chrome** |
## | a way to launch what was authored | `BoutInjector.load_map_file`, which is `load_map` with the
##   file-reading half taken off |
##
## **The scene gets no logic.** Every verb below is a call into `EditorController`, which is a
## `RefCounted` in `src/logic/` and is tested with no scene at all. What is here is widgets, the
## routing of a click to a verb, and redrawing after one — `BuilderController`'s split, applied
## again.
##
## ## Display, not input
##
## It authors a board; it queues nothing against a unit. `ViewModule`'s line is drawn at the
## `TacticsController` path ending in `ActionQueue.enqueue`, and nothing here goes near it — the
## same reasoning that keeps `DebugPanelModule` on the display side even though injection mutates.
##
## ## What a click does is the tool, and the tool is a table entry
##
## One click gesture, several meanings, chosen by the tool dropdown. That is deliberate rather than
## a dozen modal buttons: the editor's whole interaction is *point at a cell and mean something*,
## and `TOOLS` below is the list of things it can mean.
##
## ## A known limit, flagged rather than worked around
##
## The editor mode installs over whatever bout `BattleScene` already built, so any units already on
## the board are relocated onto the authored one by the same `BoardSwap` a map load uses. An
## authoring session that starts with no units at all wants an entry point that builds a world
## without a bout, which is *Main menu*'s job and is sequenced after this in `PLAN.md`.

## taskblock-57 Pass G2: **the active tool changed.** *"Current tool shows on the cursor — a small
## icon of what is being placed — **or** is carried by the action bar's own highlight. Either is
## fine; neither is not."* The bar's highlight is the option taken, and a signal is what lets the
## bar follow a tool set from anywhere — its buttons, a pick from the parts list, or a test.
signal tool_changed(tool: StringName)

## Every meaning a board click can carry. Open `StringName`s and generated into the dropdown from
## this list, so the panel and the router cannot disagree about which tools exist.
const TOOLS: Array[StringName] = [
	&"place",
	&"remove",
	&"height",
	&"spawn_a",
	&"spawn_b",
	&"spawn_none",
	&"sight_blocking",
	&"claim",
	&"chance",
	# taskblock-57 Pass H: **the manipulation gizmo, armed like every other verb.** A click with
	# this tool focuses the handles on whatever is at the cell instead of authoring — which is what
	# keeps the gizmo a tool over a click the one router already resolved, rather than a second
	# picking path with its own idea of what is selected.
	&"gizmo",
]

## The placement kinds the part dropdown can author. `MapPlacement`'s own three, read from its
## constants rather than respelled.
const PLACEMENT_KINDS: Array[StringName] = [
	MapPlacement.KIND_SURFACE,
	MapPlacement.KIND_BLOCKER,
	MapPlacement.KIND_FIELD_ITEM,
]

## The claim verbs offered, in the order `ClaimVolumeModule` documents its colours in.
const CLAIM_KINDS: Array[StringName] = [
	SectionClaim.KIND_INTERIOR,
	SectionClaim.KIND_EXTERIOR,
	SectionClaim.KIND_EMPTY,
	SectionClaim.KIND_ENTRY,
	SectionClaim.KIND_MERGE,
]

const EDGE_SIDES: Array[StringName] = [
	SectionEdge.SIDE_NORTH,
	SectionEdge.SIDE_SOUTH,
	SectionEdge.SIDE_EAST,
	SectionEdge.SIDE_WEST,
	SectionEdge.SIDE_UP,
	SectionEdge.SIDE_DOWN,
]

## Where a save lands when the author names a file rather than a path. The two authored
## directories the catalogs already scan, so a saved board appears in the load dropdown
## next time
## the panel is built with no further wiring.
const MAP_DIR := "res://data/maps"
const SECTION_DIR := "res://data/sections"

## A claim authored by clicking one cell covers that cell from the deck to here. Flagged and
## tunable; resizing afterwards is `EditorController.resize_claim`'s job.
const DEFAULT_CLAIM_HEIGHT := 2.4

## How much of a row a field's own name takes before the control gets the rest. A starting position,
## not a decision — see `_labelled`, which clips rather than widens.
const LABEL_WIDTH := 96.0

## How far the details panel's content sits inside its own border, before UI scale. A starting
## position, from the UI review's *"Panel needs some padding all around it."*
const PANEL_PADDING := 10.0

## The editing model. **Public and constructed here**, because the controller is the
## module's whole
## state and a test drives it directly rather than through widgets.
var controller := EditorController.new()

## The cell the last board click landed on, or null. What the claim and chance tools author
## against, and what the readout names.
var last_cell: Variant = null

# --- what a click means, as state rather than as a widget's index -----------------------------
#
# **taskblock-57 Pass G1: these were four `OptionButton`s and are four fields.** The tool, the
# placement kind, the part and the claim kind are chosen from the editor's own bar now, and a
# dropdown in a panel plus a button on a bar would be two ways to answer one question — the
# "no parallel systems" rule applied to an authoring surface. The bar writes these; `apply_tool_at`
# reads them; the panel below owns only what the bar does not.
#
# They are public and plainly assignable on purpose: a test drives the model directly, which is
# what it should have been doing through the dropdowns all along.

## What a board click does. One of `TOOLS`.
##
## A setter rather than a plain field so the highlight cannot fall out of step with the
## tool: every
## route that changes it goes through here, which is the same "one emitter, not one per
## call site"
## reasoning `QueueLog` is built on.
var active_tool: StringName = &"place":
	set(value):
		if active_tool == value:
			return
		active_tool = value
		tool_changed.emit(value)
## Which of `PLACEMENT_KINDS` a placed part becomes.
var selected_kind: StringName = MapPlacement.KIND_SURFACE
## The part the `place` tool places. Defaulted at mount to the first placeable id, so a
## fresh editor
## can place something without visiting the list first.
var selected_part: StringName = &""
## Which of `CLAIM_KINDS` the `claim` tool authors.
var selected_claim_kind: StringName = SectionClaim.KIND_INTERIOR

## The last surface part the author placed, so a wall dropped on bare ground brings that floor with
## it rather than a named default. See `_ensure_a_tile_under`.
var last_surface_part: StringName = &""

# Widgets, held as real references rather than re-found by node path — the same convention
# `BoutSetupModule` uses and for the same reason: the tests read them back directly.
var panel: PanelContainer = null
var layout: VBoxContainer = null
var name_field: LineEdit = null
var height_field: SpinBox = null
var facing_field: SpinBox = null
var edge_side_dropdown: OptionButton = null
var edge_kind_dropdown: OptionButton = null
var join_tag_field: LineEdit = null
var chance_tag_field: LineEdit = null
var chance_field: SpinBox = null
var status_label: Label = null

var _part_ids: Array[StringName] = []
## The warnings already put in the combat log, so a redraw does not repeat them. See
## `_report_warnings`.
var _reported_warnings: Array[String] = []


func module_id() -> StringName:
	return &"editor"


## taskblock-57 Pass G2: *"Section details go where the Inspect Viewer sits, with a toggle in UI
## buttons."*
##
## **Declaring the slot is the whole of the toggle.** `INSPECT_VIEWER` is left-edge-pinned, so
## `ViewModule.is_collapsible()` answers true from the slot alone and `UiButtonsModule`
## builds the
## checkbox by sweeping for exactly that — no module is named in either file. The taskblock
## asked
## for a toggle and the answer was a `preferred_slot()`, which is the collapse rule doing
## the job
## it was built for in Pass A.
func preferred_slot() -> StringName:
	return ModuleSlots.INSPECT_VIEWER


func _mount() -> void:
	# **The board arrives with the last bout's overlays still on it.** The UI review: *"Movement
	# tiles show on screen if going to edit mode from an in progress player controlled bout."* The
	# reachable tint and the queued-move ghosts belong to a TACTICS turn nobody is taking any more,
	# and the editor never draws them, so nothing else would ever clear them.
	if context != null and context.battle != null and context.battle.board_view != null:
		context.battle.board_view.clear_overlays()
	# **A default the author does not have to supply.** The part dropdown used to select its first
	# entry automatically; with the list on the bar, an editor opened and clicked immediately would
	# otherwise place nothing at all and look broken.
	if selected_part == &"" and not placeable_part_ids().is_empty():
		selected_part = placeable_part_ids()[0]
	if last_surface_part == &"" and not surface_part_ids().is_empty():
		last_surface_part = surface_part_ids()[0]
	_build_ui()
	refresh()


## Takes every board click for the whole session, and turns the claim drawing on.
##
## **Both are reads of modules this one does not own and does not require.** A context with no
## `board_inspect` gets an editor that authors through its verbs and not through clicks; a
## context
## with no `claim_volumes` gets one whose claims are invisible. Neither is an error, which
## is what
## `link()` degrading rather than asserting is for — and it is why this module mounts against an
## empty context at all.
func link() -> void:
	var picking: BoardInspectModule = _board_inspect()
	if picking != null:
		# The same capture mode `DebugControlPanel` borrows a click through. An editor's clicks are
		# *always* authoring gestures, so it is set once rather than armed per click.
		picking.input_capture_mode = true
		picking.board_clicked.connect(_on_board_clicked)
	refresh()


func _unmount() -> void:
	var picking: BoardInspectModule = _board_inspect()
	if picking != null:
		picking.input_capture_mode = false
		if picking.board_clicked.is_connected(_on_board_clicked):
			picking.board_clicked.disconnect(_on_board_clicked)


## A battle load re-points the editor at whatever board is now current, and frames it.
func rebind() -> void:
	refresh()


# --- the verbs a click and a button reach ----------------------------------------------------


## Applies the active tool at `cell`. **The whole router**, and every branch is one call into
## `EditorController` — which is the split this module exists to demonstrate.
func apply_tool_at(cell: Vector2i) -> bool:
	last_cell = cell
	var applied: bool = false
	match active_tool:
		&"place":
			_ensure_a_tile_under(cell)
			applied = (
				controller.place(cell, selected_part, selected_kind, height(), facing()) != null
			)
		&"remove":
			applied = controller.remove_top(cell)
		&"height":
			applied = controller.set_height(cell, height())
		&"spawn_a":
			controller.set_spawn_marker(cell, Enums.SpawnMarker.SPAWN_A)
			applied = true
		&"spawn_b":
			controller.set_spawn_marker(cell, Enums.SpawnMarker.SPAWN_B)
			applied = true
		&"spawn_none":
			controller.set_spawn_marker(cell, Enums.SpawnMarker.NONE)
			applied = true
		&"sight_blocking":
			controller.set_opacity(cell, 0.0 if controller.opacity.has(cell) else 1.0)
			applied = true
		&"claim":
			controller.add_claim(selected_claim_kind, _cell_claim_box(cell))
			applied = true
		&"gizmo":
			# **The gizmo is told, and it does not look.** This is the one router every board click
			# in the editor goes through, so handing it the cell here is what stops the gizmo
			# growing a second click path. A mode with no gizmo module answers false, which is the
			# honest report that the tool did nothing.
			applied = _focus_gizmo(cell)
		&"chance":
			applied = (
				controller.set_cell_chance(
					cell, SectionSpawn.KIND_CLUTTER, chance_tag(), chance_value()
				)
				!= null
			)
	refresh()
	return applied


## **A wall placed on bare ground brings its own floor.**
##
## The UI review: *"Wall pieces that require a tile beneath them should instantiate the tile."* A
## blocker or a field item on a cell with no surface is a placement standing on nothing, and an
## author who wanted a wall did not mean "and also a hole".
##
## **Which tile is the last one placed**, defaulting to the first surface part the data offers. That
## is deliberately not a new authored default: the author's most recent floor is the one they are
## building with, and a rule that reached for a named part would be inventing content.
##
## A no-op for a surface placement — a floor does not need a floor — and for a cell that already has
## one.
func _ensure_a_tile_under(cell: Vector2i) -> void:
	if selected_kind == MapPlacement.KIND_SURFACE:
		return
	for placement: MapPlacement in controller.placements_at(cell):
		if placement.kind == MapPlacement.KIND_SURFACE:
			return
	var floors: Array[StringName] = surface_part_ids()
	if floors.is_empty():
		return
	var beneath: StringName = last_surface_part if last_surface_part != &"" else floors[0]
	controller.place(cell, beneath, MapPlacement.KIND_SURFACE, height())


## Declares an edge on the selected side from the edge widgets.
func apply_edge() -> void:
	controller.set_edge(selected_edge_side(), selected_edge_kind(), join_tag())
	refresh()


func undo() -> bool:
	var stepped: bool = controller.undo()
	refresh()
	return stepped


## **Save as map.** `MapSerializer`'s format, through `EditorController.save_to`.
func save_as_map() -> Dictionary:
	controller.target = EditorController.TARGET_MAP
	return _save_into(MAP_DIR)


## **Save as section.** `SectionSerializer`'s format, carrying claims, edges and the authoring
## vocabulary.
func save_as_section() -> Dictionary:
	controller.target = EditorController.TARGET_SECTION
	return _save_into(SECTION_DIR)


## **Run a test bout on what was authored — the half that matters.**
##
## Goes through `BoutInjector.load_map_file`, which is the ordinary `load_map` verb with the
## file-reading half taken off, so the board reaches combat down the identical route a generated
## one does. **Never a second entry into a bout**, which is what an editor is most likely
## to grow
## by accident.
##
## An authored board that fails the navigability invariant launches anyway and the warnings
## say so
## — F4, and the reason this returns a result rather than gating on `warnings()`.
func run_test_bout() -> Dictionary:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.bout_injector == null:
		return {"error": "no bout to load this board into"}
	if not battle.bout_injector.load_map_file(controller.to_map_file()):
		return {"error": "the injector refused the board — see the combat log"}
	battle.sync_board_view()
	battle.refresh_unit_views()
	_frame_content()
	refresh()
	return {"error": ""}


## Loads an authored map or section into the editor, by catalog name or by path.
##
## **Through `BoardSwap`'s own resolution, not a second copy of it.** That is where "a name or a
## path" is already answered for `load_map` and `preview_section`, and an editor with its
## own idea
## of how to find a file would be the third answer to a question that has one.
##
## Tried as a map and then as a section, because the two formats share a name space from the
## author's point of view — they picked a board, not a schema.
func open(path_or_name: String) -> Dictionary:
	var as_map: Dictionary = BoardSwap.resolve_map(path_or_name)
	if as_map["error"] == &"":
		controller.load_map(as_map["map"] as MapFile)
	else:
		var as_section: Dictionary = BoardSwap.resolve_section(path_or_name)
		if as_section["error"] != &"":
			return {"error": "nothing on disk called '%s'" % path_or_name}
		controller.load_section(as_section["section"] as SectionFile)
	_show_name()
	refresh()
	_frame_content()
	return {"error": ""}


## Puts the model's own name into the field after a load. The other direction of the
## one-way pair
## `refresh()`'s note describes.
func _show_name() -> void:
	if name_field != null:
		name_field.text = controller.board_name


# --- what the widgets currently say ----------------------------------------------------------


func selected_edge_side() -> StringName:
	return _selected_of(edge_side_dropdown, EDGE_SIDES, SectionEdge.SIDE_NORTH)


func selected_edge_kind() -> StringName:
	var kinds: Array[StringName] = [SectionEdge.KIND_EXTERIOR, SectionEdge.KIND_OPEN]
	return _selected_of(edge_kind_dropdown, kinds, SectionEdge.KIND_EXTERIOR)


func height() -> float:
	return height_field.value if height_field != null else 0.0


func facing() -> float:
	return facing_field.value if facing_field != null else 0.0


func join_tag() -> StringName:
	return StringName(join_tag_field.text) if join_tag_field != null else &""


func chance_tag() -> StringName:
	return StringName(chance_tag_field.text) if chance_tag_field != null else &""


func chance_value() -> float:
	return chance_field.value if chance_field != null else 1.0


# --- redraw ------------------------------------------------------------------------------------


## Pushes the model out to everything that shows it: the live board, the claim boxes, the
## warnings
## list and the readout. Cheap to call after every edit, and called after every edit — an editor
## whose display is refreshed on some verbs and not others is one where the author cannot tell a
## no-op from a missed redraw.
## **Deliberately does not write the name field back into the model.** It used to, and that made
## `open()` lose the name of whatever it had just loaded: the load set `board_name` from
## the file
## and the very next `refresh()` overwrote it with whatever the field still had in it. The field
## pushes into the controller on edit (`_build_ui`) and the controller pushes into the
## field on load
## (`_show_name`) — one direction each way, rather than a write-back that fights a load.
func refresh() -> void:
	_refresh_board()
	_refresh_claims()
	_refresh_readout()


## Rebuilds the live board from the model, through `MapSerializer` exactly as a load would.
##
## **A board that cannot be built is left standing and reported**, never half-applied: the
## author
## sees the last good board plus a warning naming the placement that broke it, which is far more
## use than an empty grid.
func _refresh_board() -> void:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.combat_state == null:
		return
	var result: Dictionary = controller.to_grid()
	if not result.has("grid"):
		return
	var stranded: Array[int] = BoardSwap.swap_board(
		battle.combat_state, result["grid"] as Grid, true
	)
	battle.sync_board_view()
	_hide_stranded(battle, stranded)


## **A unit the authored board has nowhere to put is not drawn.**
##
## Reported by the supervisor as *"some units spawn in edit mode at the places they were in the
## last bout"*, and that is exactly what it was. The editor installs over whatever bout
## `BattleScene`
## already built, and `BoardSwap.swap_board` relocates every living unit onto the authored
## board —
## but it **returns the ones it could not place** and this module was discarding that list.
## A board
## with no floor on it yet strands all of them, so every unit kept its cell from the
## previous bout
## and was still rendered there, standing on nothing.
##
## Hiding rather than moving, and that is deliberately not a design decision: a stranded
## unit has
## no cell on this board, so drawing it somewhere is the view inventing a fact. It is the
## same rule
## this project has applied to risers and to the ground quad — **do not draw what is not
## there.** The
## units are untouched and `run_test_bout` relocates them onto the finished board down the
## ordinary
## injector path, which is when they come back.
##
## **The real answer is an entry point that builds a world with no bout in it**, which is
## `PLAN.md`'s
## *Main menu* and is flagged in this module's own header as a known limit. This makes the
## editor
## honest in the meantime.
func _hide_stranded(battle: BattleScene, stranded: Array[int]) -> void:
	for view: HitVolumeView in battle.unit_views:
		if view.unit != null:
			view.visible = not stranded.has(view.unit.id)


## **This is what `ClaimVolumeModule` was built for.** Pass E left it tested and mounted by no
## mode, with `PLAN.md` recording that "the authoring surface that would turn it on is *Map and
## section editors*". This is that surface, and turning it on is one call.
func _refresh_claims() -> void:
	var volumes: ClaimVolumeModule = _claim_volumes()
	if volumes != null:
		volumes.show_claims(controller.claims)


func _refresh_readout() -> void:
	if status_label != null:
		status_label.text = (
			"%dx%d | %d placed | %d claim(s) | %d edge(s) | cell %s | undo %d"
			% [
				controller.width,
				controller.rows,
				controller.placements.size(),
				controller.claims.size(),
				controller.edges.size(),
				str(last_cell) if last_cell != null else "-",
				controller.undo_depth(),
			]
		)
	# **Warnings are a list the author reads, not a gate** (F4). Both save buttons stay enabled
	# whatever is in here, and so does Run Test Bout.
	_report_warnings(controller.warnings())


## taskblock-57 Pass G2: **the warnings reach the combat log, and the significant ones
## announce.**
##
## *"Validation warnings go to the combat log, and the significant ones surface as
## announcements.
## Warn, never block needs somewhere to warn."*
##
## Only what is **new** is emitted. This runs after every edit against a list recomputed
## whole, so
## reporting all of it every time would put the same line in the log once per click. `EditorLog`
## owns the diff and the significance rule; this holds what was last said, and it shrinks as
## warnings clear so a reintroduced problem is reported again.
func _report_warnings(problems: Array[String]) -> void:
	var state: CombatState = (
		context.battle.combat_state if context != null and context.battle != null else null
	)
	var fresh: Array[String] = EditorLog.arrived(_reported_warnings, problems)
	_reported_warnings = problems.duplicate()
	if fresh.is_empty():
		return
	EditorLog.report(state, fresh, controller.navigability_warnings())


## Folds the section details away. The panel is the whole of what this module draws, so
## hiding it
## hides the module — and the authoring verbs, which live on the bar, keep working while it is
## folded. That is the point of a collapsible details panel rather than a collapsible editor.
func _on_collapsed(value: bool) -> void:
	if panel != null:
		panel.visible = not value


func _frame_content() -> void:
	var framing: CameraFramingModule = (
		context.module(&"camera_framing") as CameraFramingModule if context != null else null
	)
	if framing != null:
		framing.frame_loaded_content()


# --- internals ---------------------------------------------------------------------------------


## A one-cell claim standing on the deck. The extent is in the section's own local space,
## which is
## cells on X/Z and world units on Y — `SectionClaim`'s own convention, so a claim over cell
## `(2,1)` from the deck to 2.4 has centre `(2, 1.2, 1)`.
func _cell_claim_box(cell: Vector2i) -> Box:
	return Box.new(
		Vector3(cell.x, DEFAULT_CLAIM_HEIGHT * 0.5, cell.y), Vector3(1.0, DEFAULT_CLAIM_HEIGHT, 1.0)
	)


func _save_into(directory: String) -> Dictionary:
	var named: String = name_field.text if name_field != null else controller.board_name
	if named.strip_edges() == "":
		return {"error": "name the board before saving it"}
	controller.board_name = named
	# **A name or a path**, the same either-or `BoardSwap.resolve_map` accepts on the way in. Keyed
	# on `://` rather than on `res://` specifically: a test saves to `user://` and a board written
	# into `res://data/maps/user://...` is the shape of bug that only shows up as a write error.
	var path: String = named
	if not path.contains("://"):
		path = "%s/%s.tres" % [directory, named.to_snake_case()]
	var result: Dictionary = controller.save_to(path)
	if result["error"] == "":
		result["path"] = path
	_refresh_readout()
	return result


func _on_board_clicked(hit: Dictionary) -> void:
	var cell: Variant = hit.get("cell")
	if cell == null:
		return
	apply_tool_at(cell as Vector2i)


func _board_inspect() -> BoardInspectModule:
	return context.module(&"board_inspect") as BoardInspectModule if context != null else null


## Points the gizmo at whatever is at `cell`, or clears it when nothing there can be dragged.
##
## **Focusing and clearing are both real answers** — *"a click elsewhere deselects"* — so
## both count
## as the tool having done something.
func _focus_gizmo(cell: Vector2i) -> bool:
	var handles: GizmoModule = context.module(&"gizmo") as GizmoModule if context != null else null
	return handles.focus_at(cell) if handles != null else false


func _claim_volumes() -> ClaimVolumeModule:
	return context.module(&"claim_volumes") as ClaimVolumeModule if context != null else null


## The selected entry of `options`, or `fallback` when the dropdown is absent or
## unselected. Every
## dropdown here is populated from its own constant list in order, so index *is* identity.
func _selected_of(
	dropdown: OptionButton, options: Array[StringName], fallback: StringName
) -> StringName:
	if dropdown == null or options.is_empty():
		return fallback
	var index: int = dropdown.selected
	if index < 0 or index >= options.size():
		return fallback
	return options[index]


# --- the panel ---------------------------------------------------------------------------------


## **taskblock-57 Pass G1: what is left after the bar took the verbs.**
##
## The tool, the placement kind, the part and the claim kind are the bar's buttons now;
## save, load,
## run-a-bout and undo are its second row. What remains here is the *declarations* — the board's
## name, the numbers a placement carries, the section's edges and chance rolls, and the
## readout —
## which is what Pass G2 calls "section details".
##
## **It sits where the Inspect viewer sits**, which is G2's stated home for it. Landing it
## here in
## G1 rather than a pass later is not scope creep: the editor mode moves to `BATTLE_LAYOUT`
## in this
## pass, `LEFT_COLUMN` stops existing in it, and a panel asking for a slot no chrome
## publishes falls
## back to `ui_root` at (0,0) — on top of the debug menu's region and under the
## announcement band.
## The alternative was a temporary placement to be moved one pass later, which is churn on
## the same
## file for no gain. **The toggle that folds it away is still G2's**, and until it lands
## the panel
## is simply always shown.
func _build_ui() -> void:
	var host: Control = context.slots.get(ModuleSlots.INSPECT_VIEWER) if context != null else null
	panel = PanelContainer.new()
	# **Clipped and scrolled, so the slot's width is the panel's width.** The supervisor's review:
	# *"it's too wide. Should be roughly half as wide as it is tall."* The slot already is — the
	# layout gives it half the viewer's height in width — but a `PanelContainer` takes the largest
	# minimum width of its content, and a column of labelled `SpinBox` rows asks for more than that.
	# So the panel grew past its own slot and the rect the table describes was never what was drawn.
	#
	# Scrolling rather than shrinking the rows: the fields have to stay usable, and an authoring
	# panel with more in it than fits is a scroll, not a squeeze.
	panel.clip_contents = true
	# **Padded all round**, which the UI review asked for: *"EDIT INSPECT VIEWER — Panel needs some
	# padding all around it."* Same treatment `InspectPanel` gets, for the same reason: a
	# `PanelContainer` hands its child the whole rect, so every labelled row ran into the border.
	var style: StyleBox = panel.get_theme_stylebox("panel")
	if style != null:
		var padded: StyleBox = style.duplicate()
		for side: String in [
			"content_margin_left",
			"content_margin_right",
			"content_margin_top",
			"content_margin_bottom"
		]:
			padded.set(side, UiLayout.scaled(PANEL_PADDING))
		panel.add_theme_stylebox_override("panel", padded)
	var scroll := ScrollContainer.new()
	# **Horizontal scrolling ENABLED, which is what actually lets the panel be narrow.** A
	# `ScrollContainer` reports its content's minimum size on any axis it cannot scroll, so with
	# horizontal scrolling off the whole panel still grew to the widest labelled row it held — 516 px
	# against a 360 px slot, measured. Allowing the axis to scroll drops that minimum to zero and the
	# panel finally fits the rect the placement table gives it.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	layout = VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(layout)
	if host != null:
		host.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	elif context != null and context.ui_root != null:
		context.ui_root.add_child(panel)
	else:
		# The stand-alone case taskblock-56 Pass C's acceptance requires: every widget is real and
		# every verb works; the panel simply has nowhere of its own to be drawn.
		add_child(panel)

	var title := Label.new()
	title.text = "Editor"
	layout.add_child(title)

	name_field = LineEdit.new()
	name_field.placeholder_text = "board name"
	name_field.text_changed.connect(func(text: String) -> void: controller.board_name = text)
	layout.add_child(name_field)

	height_field = _number(0.0, -32.0, 32.0, 0.1)
	layout.add_child(_labelled("height", height_field))
	facing_field = _number(0.0, -TAU, TAU, 0.01)
	layout.add_child(_labelled("facing", facing_field))

	edge_side_dropdown = _dropdown(EDGE_SIDES)
	layout.add_child(_labelled("edge side", edge_side_dropdown))
	edge_kind_dropdown = _dropdown([SectionEdge.KIND_EXTERIOR, SectionEdge.KIND_OPEN])
	layout.add_child(_labelled("edge kind", edge_kind_dropdown))
	join_tag_field = LineEdit.new()
	join_tag_field.placeholder_text = "join_tag"
	layout.add_child(_labelled("join tag", join_tag_field))
	var edge_button := Button.new()
	edge_button.text = "Declare Edge"
	edge_button.pressed.connect(apply_edge)
	layout.add_child(edge_button)

	chance_tag_field = LineEdit.new()
	chance_tag_field.placeholder_text = "clutter tag"
	layout.add_child(_labelled("chance tag", chance_tag_field))
	chance_field = _number(1.0, 0.0, 1.0, 0.05)
	layout.add_child(_labelled("chance", chance_field))

	layout.add_child(_section_field_rows())

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(status_label)


## One row per whole-section declaration, **discovered from `SectionFile` rather than
## listed**. A
## new `@export` on that resource becomes an editable field here the day it is added, which
## is the
## open-vocabulary rule applied to an authoring surface.
func _section_field_rows() -> VBoxContainer:
	var rows := VBoxContainer.new()
	for name: StringName in EditorController.declaration_fields():
		var current: Variant = controller.section_field(name)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = String(name)
		row.add_child(label)
		if current is bool:
			var check := CheckBox.new()
			check.button_pressed = current
			check.toggled.connect(
				func(pressed: bool) -> void:
					controller.set_section_field(name, pressed)
					_refresh_readout()
			)
			row.add_child(check)
		elif current is int:
			var number := _number(float(current), -1.0, 999.0, 1.0)
			number.value_changed.connect(
				func(value: float) -> void:
					controller.set_section_field(name, int(value))
					_refresh_readout()
			)
			row.add_child(number)
		else:
			# An array field (`banned_clutter`, `encounter_types`) is a comma-separated list. Crude
			# and honest — a real tag picker wants a content library, which does not exist.
			var text := LineEdit.new()
			text.placeholder_text = "comma separated"
			text.text_submitted.connect(
				func(value: String) -> void:
					controller.set_section_field(name, _tag_list(value))
					_refresh_readout()
			)
			row.add_child(text)
		rows.add_child(row)
	return rows


static func _tag_list(text: String) -> Array[StringName]:
	var tags: Array[StringName] = []
	for piece: String in text.split(",", false):
		var trimmed: String = piece.strip_edges()
		if trimmed != "":
			tags.append(StringName(trimmed))
	return tags


## Every part the board can hold, by id, sorted so the list is the same on two machines.
##
## **Not a curated list.** Any part can be a blocker or a loose field item, and which parts make
## sense as a surface is already answered by the data — a `walkable` tag or a `GROUND`
## attachment.
## Authoring a new floor type is a `.tres`, exactly as the standing rule requires.
##
## taskblock-57 Pass G1: public, because the searchable list on the editor's bar is what offers
## these now. Cached after the first call — the pool does not change while a board is being
## authored
## and the list is reopened on every placement.
## The surface parts, which are the only kind the part data can currently tell apart. See
## `placeable_part_ids`.
func surface_part_ids() -> Array[StringName]:
	var floors: Array[StringName] = []
	for id: StringName in placeable_part_ids():
		var part: Part = DataLibrary.get_part(id)
		if part != null and GridPlacement.GROUND in part.attaches_to:
			floors.append(id)
	return floors


## The parts offered for `kind`, or every placeable part when the data cannot narrow it.
##
## ## What the data can and cannot answer, stated rather than worked around
##
## The UI review: *"Filtering inside the tile picker still doesn't seem to be happening. If this
## needs a whole 'tag' system built then let me know rather than just trying to make it work."*
##
## **It does need one, for two of the three kinds.** A *surface* is answerable today — a tile is a
## part that attaches to `GROUND`, which is not a convention but the rule `GridPlacement.can_place`
## enforces, so offering anything else as a tile produces a placement the loader refuses. That
## filter is applied.
##
## **A blocker and a field item are not answerable.** `DataLibrary.parts_pool()` is *every* `Part` —
## arms, heads, weapons, batteries — and nothing in the data says which of them belong on a board
## rather than on a body. Separating them wants a tag on the part, which is a content decision and
## is deliberately not invented here.
func placeable_part_ids(kind: StringName = &"") -> Array[StringName]:
	if kind == MapPlacement.KIND_SURFACE:
		return surface_part_ids()
	if not _part_ids.is_empty():
		return _part_ids
	var names: Array[String] = []
	for part: Part in DataLibrary.parts_pool():
		names.append(String(part.id))
	# **Sorted as Strings, and that is a real defect rather than a style choice.**
	#
	# `Array[StringName].sort()` orders by the engine's internal `StringName` ordering, which is not
	# alphabetical — it is stable within a run and looks like insertion order or noise to a reader.
	# The UI review saw exactly that: *"It's also showing items in what looks like 'add' order. I.e
	# looks random, should be alphanumeric if possible."* Measured: `ramp, metal_scraps,
	# twisted_sheet_metal, head, battery, ...` where alphabetical gives `ammo_rack, arc_welder, arm,
	# arm_cladding, ...`.
	names.sort()
	for name: String in names:
		_part_ids.append(StringName(name))
	return _part_ids


func _dropdown(options: Array[StringName]) -> OptionButton:
	var dropdown := OptionButton.new()
	for option: StringName in options:
		dropdown.add_item(String(option))
	if not options.is_empty():
		dropdown.selected = 0
	return dropdown


func _number(value: float, minimum: float, maximum: float, step: float) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = minimum
	box.max_value = maximum
	box.step = step
	box.value = value
	return box


## One labelled field, sized to whatever width the panel currently has.
##
## **The row shrinks with the panel rather than setting its width**, which the UI review found it
## doing: *"Looks like you just chopped the size of this panel, and the items within aren't set to
## resize with panel size."* The label is given a clip and a fixed share so a long field name cannot
## push the control it labels out of the panel, and the control expands into what is left.
func _labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.size_flags_horizontal = Control.SIZE_FILL
	# Clipped rather than allowed to widen the row — a `Label` reports its full text as its minimum
	# width otherwise, which is what made the panel wider than the slot it was given.
	label.clip_text = true
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = 0.0
	row.add_child(control)
	return row
