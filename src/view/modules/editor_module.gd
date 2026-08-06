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
## `RefCounted` in `src/logic/` and is tested with no scene at all. What is here is the routing of a
## click to a verb and the redraw after one — `BuilderController`'s split, applied again. The
## widgets went one step further out in taskblock-59 Pass A and are `EditorPanel`'s.
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
## ## A known limit, and it has now produced three defects rather than one
##
## The editor mode installs over whatever bout `BattleScene` already built, so any units already on
## the board are relocated onto the authored one by the same `BoardSwap` a map load uses. An
## authoring session that starts with no units at all wants an entry point that builds a world
## without a bout, which is *Main menu*'s job and is sequenced after this in `PLAN.md`.
##
## **That limit is not theoretical, and the pattern is worth naming.** The editor inherits every
## piece of view state the bout owned, and each one has had to be found by eye:
##
## | inherited | where it lived | cleared by |
## |---|---|---|
## | units at their last cells | `CombatState.units` | `_hide_bout_units` (`BR57.01`, and see it) |
## | movement tiles and ghosts | `BoardView`'s overlay layers | `clear_overlays` in `_mount` |
## | extraction markers | `BoardView`'s statics, from `MissionState` | building with no mission |
##
## **Three symptoms, one cause**: the editor is a surface over a world it did not build. Each fix
## above is right on its own terms — do not draw what is not there — and none of them touches the
## cause, so expect a fourth. The entry point that builds a world with no bout in it is the fix;
## clearing things one at a time is the interim.
##
## **The fourth arrived, and then a fifth wearing the same clothes.** taskblock-59 Pass B found the
## wall cutout still keyed on the previous bout's units. The report came back: it was still
## happening, *"goes away after placing more walls or just more items"*, alongside *"a random unit
## stuck around in the editor from the prior map."* One unit, both symptoms — `BoardSwap.swap_board`
## seats on the **first free walkable cell**, so the author's first floor tile put it on the board.
## `_hide_bout_units` stops treating this a symptom at a time: **no bout unit is drawn in the editor
## at all.**

## taskblock-57 Pass G2: **the active tool changed.** *"Current tool shows on the cursor — a small
## icon of what is being placed — **or** is carried by the action bar's own highlight. Either is
## fine; neither is not."* The bar's highlight is the option taken, and a signal is what lets the
## bar follow a tool set from anywhere — its buttons, a pick from the parts list, or a test.
signal tool_changed(tool: StringName)

## taskblock-58 Pass D: **the tool vocabulary moved to `EditorTools`.** Which tools exist and what
## kind each authors are questions with no widget in them, and this file was over its 1000-line
## limit — the same split `InspectPanel` took when `BotViewer` came out of it. Referenced as
## `EditorTools.TOOLS` everywhere, never re-listed here, so there is one vocabulary.

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

## taskblock-59 Pass A: **the widgets moved to `EditorPanel`.** Which sides an edge can be declared
## on is a dropdown's contents, and the panel that draws it owns it — referenced as
## `EditorPanel.EDGE_SIDES` everywhere rather than re-listed here.

## Where a save lands when the author names a file rather than a path. The two authored
## directories the catalogs already scan, so a saved board appears in the load dropdown
## next time
## the panel is built with no further wiring.
const MAP_DIR := "res://data/maps"
const SECTION_DIR := "res://data/sections"

## A claim authored by clicking one cell covers that cell from the deck to here. Flagged and
## tunable; resizing afterwards is `EditorController.resize_claim`'s job.
const DEFAULT_CLAIM_HEIGHT := 2.4

## **The ordinary floor**: what a fresh editor is armed with, and what goes under a wall dropped on
## bare ground. See `default_floor` for why it is a named id.
const DEFAULT_FLOOR: StringName = &"ship_floor"

## The editing model. **Public and constructed here**, because the controller is the
## module's whole
## state and a test drives it directly rather than through widgets.
var controller := EditorController.new()

## The cell the last board click landed on, or null. What the claim and chance tools author
## against, and what the readout names.
var last_cell: Variant = null

## **True while this is a board being authored rather than a bout being played.** Cleared by
## `run_test_bout`, which is the moment the author stops authoring and starts watching. What reads
## it is `_hide_bout_units`; see that for why the editor shows no units at all.
var authoring: bool = true

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
var active_tool: StringName = &"place_terrain":
	set(value):
		if active_tool == value:
			return
		active_tool = value
		_release_gizmo()
		tool_changed.emit(value)
## Which of `PLACEMENT_KINDS` a placed part becomes.
##
## taskblock-58 Pass D: **derived from the tool and the part now, not chosen beside them.** It is
## still the field the placement reads, so nothing downstream changed; what went away is the author
## picking a kind and a part separately and being able to pick a pair that does not exist.
var selected_kind: StringName = MapPlacement.KIND_SURFACE
## The part the place tools place. Defaulted at mount to the first placeable id, so a
## fresh editor
## can place something without visiting the list first.
var selected_part: StringName = &""
## Which of `CLAIM_KINDS` a placed claim authors.
var selected_claim_kind: StringName = SectionClaim.KIND_INTERIOR
## taskblock-58 Pass D: which of `MAP_THINGS` the *Place Map Thing* tool puts down. One tool, one
## selection — the same shape the place tools have with `selected_part`, rather than a verb per
## marker.
var selected_map_thing: StringName = &"claim"

## taskblock-58 Pass E: **the face the last pick struck**, or null when the pick resolved off the
## ground plane instead of off geometry. Set for the duration of one click by `_on_board_clicked`,
## and set by the hover path while a ghost is being drawn — which is what makes the ghost and the
## click take the same branch of `placement_target`.
var struck_normal: Variant = null

## taskblock-59 follow-up: **the world point the pick struck**, or null. What tells the editor
## *which* of a cell's stacked placements was clicked — a column of floors is one cell, and every
## verb that resolved a click to the cell then acted on the wrong one of them. Set and cleared
## beside `struck_normal`, by the same two paths, for the same reason.
var struck_point: Variant = null

## The last surface part the author placed, so a wall dropped on bare ground brings that floor with
## it rather than a named default. See `_ensure_a_tile_under`.
var last_surface_part: StringName = &""

## Every widget the editor draws. Held as a real reference rather than re-found by node path — the
## same convention `BoutSetupModule` uses and for the same reason: the tests read it back directly.
var panel: EditorPanel = null

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
	if last_surface_part == &"":
		last_surface_part = default_floor()
	if selected_part == &"":
		if last_surface_part != &"":
			selected_part = last_surface_part
		elif not placeable_part_ids().is_empty():
			selected_part = placeable_part_ids()[0]
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
		&"place_terrain", &"place_big_part", &"place_part":
			applied = _place_with(cell, active_tool)
		&"delete":
			# taskblock-59 follow-up: **the one that was clicked, not the one authored last.**
			# Reported as *"clicking the bottom item in the stack instead deletes the top item"* —
			# `remove_top` is cell-addressed and a stack is one cell.
			applied = controller.remove_placement(struck_placement(cell))
		&"place_map_thing":
			applied = _place_map_thing(cell)
		&"select", &"scale":
			# **The gizmo is told, and it does not look.** This is the one router every board click
			# in the editor goes through, so handing it the cell here is what stops the gizmo
			# growing a second click path. A mode with no gizmo module answers false, which is the
			# honest report that the tool did nothing.
			applied = _focus_gizmo(cell)
	refresh()
	return applied


## The three placing tools, which differ only in what kind of thing they put down.
##
## taskblock-58 Pass D: **the kind is derived, not chosen alongside the part.** `selected_kind` is
## still what the placement reads — nothing downstream changed — but it is now answered by
## `kind_for(tool, part)` rather than by a separate dropdown an author could set to a pair that
## does not exist (a `wall` authored as a field item, say).
func _place_with(cell: Vector2i, tool: StringName) -> bool:
	selected_kind = EditorTools.kind_for(tool, selected_part)
	# taskblock-59 Pass A: **a refusal the author can read.** Asked before the floor goes in, so a
	# click that cannot land does not leave an auto-placed tile behind it as its only trace — and the
	# sentence reaches the combat log, where every other authoring complaint already goes. A click
	# that silently does nothing is indistinguishable from a broken editor, which is how the original
	# report arrived.
	var refusal: String = placement_refusal(cell)
	if refusal != "":
		_tell_the_author(refusal)
		return false
	var target: Dictionary = placement_target(cell)
	var at: Vector2i = target["cell"]
	# taskblock-59 Pass D: **a veneer is grown, not placed at a height.** Asked before the tile goes
	# in, because the span reads what is already at the landing cell and an auto-placed floor would
	# be a surface the author never authored, arriving in time to be snapped to.
	var veneer: Dictionary = _veneer_at(cell, at)
	if not veneer.is_empty():
		var grown: MapPlacement = controller.place(
			at, selected_part, selected_kind, veneer["height"], facing()
		)
		if grown == null:
			return false
		grown.size = veneer["size"]
		return true
	_ensure_a_tile_under(at)
	var placed: MapPlacement = controller.place(
		at, selected_part, selected_kind, target["height"], facing()
	)
	if placed == null:
		return false
	_seat_on_the_struck_deck(placed, at, float(target["height"]))
	return true


## **A blocker or a loose item lands on the deck that was clicked, not on the bottom of the stack.**
##
## taskblock-59 follow-up: *"cover items also don't land atop a set of stacked ship floors."*
## `BoardView` draws a blocker at `UnitGeometry.true_height_for_cell`, which is
## `Surface.first_walkable` — **the first authored**, so on a column of floors it is the lowest one.
## That is correct of the grid (`first_walkable` is a documented rule the pathfinder reads) and
## wrong for an author who clicked the top of a stack.
##
## **`MapPlacement.offset` is what reconciles them**, and it is why Pass C's field earns its keep a
## second time: the grid still says the cell's walkable height is the bottom floor, and the
## placement carries the difference. Nothing about `first_walkable` moves, so no gameplay rule
## changes.
##
## A no-op for a surface — its own `height` already says where it is — and for a cell whose drawn
## ground is where the click landed anyway, which is every unstacked cell.
func _seat_on_the_struck_deck(placed: MapPlacement, cell: Vector2i, wanted: float) -> void:
	if placed.kind == MapPlacement.KIND_SURFACE:
		return
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.board_view == null or battle.board_view.grid == null:
		return
	var drawn: float = UnitGeometry.true_height_for_cell(cell, battle.board_view.grid)
	if is_equal_approx(drawn, wanted):
		return
	placed.offset = Vector3(placed.offset.x, wanted - drawn, placed.offset.z)


## **The span a ledge veneer takes**, as `{height, size}`, or `{}` when the armed part is not one.
##
## taskblock-59 Pass D: `LedgeVeneer` computed the span, `ledge_veneer` was an authored part, and
## the hp followed volume — all landed in taskblock-58 Pass F. **Nothing called `span_at` from a
## click**, so a veneer could not be placed on a board without hand-authoring a `.tres`. This is the
## call.
##
## **Recognised by the part carrying a rise to compute rather than by an id in a list.** A veneer is
## the one terrain part whose height is a question about the board instead of a number the author
## types, and `LedgeVeneer.PART_ID` names the single part that is true of today — but the check is
## one place, so a second facing part is an entry there rather than a branch here.
func _veneer_at(struck_cell: Vector2i, landing: Vector2i) -> Dictionary:
	if selected_part != LedgeVeneer.PART_ID:
		return {}
	var part: Part = DataLibrary.get_part(selected_part)
	if part == null:
		return {}
	return LedgeVeneer.placement_for(
		part,
		controller.placements_at(struck_cell),
		controller.placements_at(landing),
		struck_normal
	)


## **Why a click here would author nothing**, or `""` when it would author something.
##
## taskblock-59 Pass A: **the ghost asks this and so does the click** — the same structure
## `placement_target` already has, and for the same reason. A preview that decided on its own
## whether a placement was possible would be a second answer to the question the click asks, and the
## one that is wrong is the one nobody exercises.
##
## **This is what stops the ghost promising something the board cannot hold.** Clicking the top face
## of a wall previews a wall stacked on it, which reads as obviously correct and is not expressible:
## `Grid.blockers` holds one part per cell and `MapPlacement.height` is a surface's field. The
## preview drew it, the model took it, the board refused the model, and everything after was
## invisible — the pillar-on-a-pillar report, with the ghost as its accomplice rather than its
## victim. **Stacking blockers vertically is a real capability and it is queued**, not deleted; what
## is deleted is the editor pretending it already has it.
func placement_refusal(cell: Vector2i) -> String:
	if not EditorTools.is_place_tool(active_tool):
		return ""
	var kind: StringName = EditorTools.kind_for(active_tool, selected_part)
	return controller.blocks_placement(placement_target(cell)["cell"], kind)


## One authoring sentence into the combat log, through the same `EditorLog` the validation warnings
## use. **Not** routed through `_report_warnings`: that one diffs against a list recomputed whole so
## a persistent warning is said once, and a refused click is an event rather than a state — an
## author who clicks the same illegal cell three times should be told three times.
func _tell_the_author(sentence: String) -> void:
	var state: CombatState = (
		context.battle.combat_state if context != null and context.battle != null else null
	)
	EditorLog.report(state, [sentence], [])


## **Arming a different tool lets go of whatever the gizmo was holding.** taskblock-59 follow-up.
##
## Reported as *"clicking to a different tool needs to clean up gizmos attached to other parts.
## Can't have something with the scale handles visible while trying to place something."* Exactly
## right, and it is the same *do not draw what is not there* rule the rest of this module runs on: a
## handle set is a claim that something is selected, and arming *Place Terrain* is saying it is not.
##
## **`select` and `scale` keep it**, because those are the two tools the gizmo belongs to — swapping
## between them is changing which handles you want on the same subject, not letting go of it.
##
## The ghost is released with it: `reassert_ghost` reads the gizmo's own focus, so clearing the one
## clears the other and there is no second place that remembers what was selected.
func _release_gizmo() -> void:
	if EditorTools.arms_the_gizmo(active_tool):
		return
	var handles: GizmoModule = context.module(&"gizmo") as GizmoModule if context != null else null
	if handles == null:
		return
	handles.gizmo.clear()
	handles.reassert_ghost()
	handles.redraw()


## **Where the next placement lands**, given the cell under the cursor or the click.
##
## taskblock-58 Pass E: **the one answer, called by the ghost and by the click.** A preview that
## worked out where a placement would go, and a placement that worked out where it goes, would be
## two answers to one question — so *"what appears is what the ghost showed"* is structural rather
## than something a test has to keep true.
func placement_target(cell: Vector2i) -> Dictionary:
	return FacePlacement.target_from(
		struck_placements(cell), cell, struck_normal, height(), DataLibrary.get_part(selected_part)
	)


## **The placement the click struck**, or the topmost at `cell` when the pick reported no point.
##
## taskblock-59 follow-up. Reported three ways — *"clicking the side of a stacked ship_floor places
## a ship_floor back at zero"*, *"clicking the bottom item in the stack instead deletes the top
## item"*, and *"selecting the floor under a wall selects the wall"* — and they are one thing: the
## editor addressed a **cell** where the author had clicked a **thing**, and a cell can hold a
## column.
func struck_placement(cell: Vector2i) -> MapPlacement:
	if struck_point is Vector3:
		var found: MapPlacement = controller.placement_at(cell, (struck_point as Vector3).y)
		if found != null:
			return found
	var here: Array[MapPlacement] = controller.placements_at(cell)
	return here[here.size() - 1] if not here.is_empty() else null


## The struck placement as a one-entry list, for `FacePlacement`, which measures a span. **The
## struck thing's own span, not the cell's** — that is what stops the side of an upper floor
## reporting the bottom of the stack.
func struck_placements(cell: Vector2i) -> Array[MapPlacement]:
	var one: MapPlacement = struck_placement(cell)
	if one == null:
		return controller.placements_at(cell)
	return [one] as Array[MapPlacement]


## *Place Map Thing* — everything the player never sees, put down by one verb with its own
## selection rather than by a verb apiece.
##
## taskblock-58 Pass D: `spawn_a`, `spawn_b`, `spawn_none`, `chance` and `claim` were five entries
## in the tool vocabulary and are five entries in `MAP_THINGS`. **The calls into `EditorController`
## are unchanged**, which is the point — this reorganises what a click means, not what it does.
func _place_map_thing(cell: Vector2i) -> bool:
	match selected_map_thing:
		&"claim":
			controller.add_claim(selected_claim_kind, _cell_claim_box(cell))
			return true
		&"spawn_a":
			controller.set_spawn_marker(cell, Enums.SpawnMarker.SPAWN_A)
			return true
		&"spawn_b":
			controller.set_spawn_marker(cell, Enums.SpawnMarker.SPAWN_B)
			return true
		&"spawn_none":
			controller.set_spawn_marker(cell, Enums.SpawnMarker.NONE)
			return true
		&"chance":
			# **A chance is a thing you place**, not a verb — a generic "this could be any cover"
			# item with defaults, whose categories and value are the widgets beside it.
			return (
				controller.set_cell_chance(
					cell, SectionSpawn.KIND_CLUTTER, panel.chance_tag(), panel.chance_value()
				)
				!= null
			)
	return false


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
	controller.set_edge(panel.selected_edge_side(), panel.selected_edge_kind(), panel.join_tag())
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
	# **Cleared before the redraw**, so the `refresh()` below does not immediately hide the units the
	# injector has just seated.
	authoring = false
	battle.sync_board_view()
	battle.refresh_unit_views()
	for view: HitVolumeView in battle.unit_views:
		view.visible = true
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
	panel.show_name(controller.board_name)
	refresh()
	_frame_content()
	return {"error": ""}


## The height a new placement is authored at. Kept on the module because `placement_target` and the
## auto-placed tile beneath a blocker both read it, and `PlacementGhostModule` reads `facing()` from
## outside — a widget question the rest of the editor asks in view-agnostic words.
func height() -> float:
	return panel.height() if panel != null else 0.0


func facing() -> float:
	return panel.facing() if panel != null else 0.0


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
## ## taskblock-59 Pass A: **this function is where the editor's state corruption lived**
##
## It used to read *"a board that cannot be built is left standing and reported, never
## half-applied: the author sees the last good board plus a warning naming the placement that broke
## it, which is far more use than an empty grid."* **That was wrong on both halves, and it is the
## defect rather than a contributing factor.**
##
## - *Reported*: nothing reported it. `MapSerializer.to_grid`'s refusals were errors nobody
##   surfaced, and `describe_problems` — the list the author actually reads — has never had a word
##   to say about a second blocker on a cell.
## - *Left standing*: a stale board that keeps accepting edits is not a conservative fallback, it is
##   a view lying about the model. One unbuildable placement froze the screen for the rest of the
##   session, so **everything placed afterwards was invisible and so was every delete** — the two
##   reports Pass A was opened for, which are one defect seen from either side.
##
## The build is `to_grid`'s lenient one now, so there is a board to draw whatever the model holds:
## every placement that can be drawn is, and the ones that cannot arrive through `warnings()` with
## the author's name for them. The half-applied board the old note feared is the *honest* one — it
## is what the model describes, minus exactly what it says it dropped.
func _refresh_board() -> void:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.combat_state == null:
		return
	var result: Dictionary = controller.to_grid()
	if not result.has("grid"):
		# **A board with no cells in it, which the lenient build cannot rescue.** Drawing the
		# previous one is what this pass exists to stop, so the surface is emptied instead and
		# `_refresh_readout` says why — *do not draw what is not there*, the same rule that hides a
		# stranded unit rather than putting it somewhere plausible.
		battle.board_view.build(Grid.new(1, 1), battle.combat_state.material_table, {})
		return
	BoardSwap.swap_board(battle.combat_state, result["grid"] as Grid, true)
	# **Built without the mission's decoration, not through `sync_board_view`.**
	#
	# That helper passes `mission.team_extraction_cells`, so every editor redraw re-stamped the
	# previous bout's extraction markers onto the authored board — the UI review's *"Extract color
	# indicators are not being cleared when going to edit mode from a bout."*
	#
	# **An authored board has no mission**, so it has no extraction cells. Passing an empty dictionary
	# is not a workaround; it is the honest argument for a board nobody is playing.
	battle.board_view.build(battle.combat_state.grid, battle.combat_state.material_table, {})
	_hide_bout_units(battle)
	# taskblock-59 Pass B: **the rebuild just freed every mesh, including the ghosted one.** The
	# gizmo holds what is focused, so it re-states it against the meshes that now exist, rather than
	# this module keeping a second record of the selection to restore from.
	var handles: GizmoModule = context.module(&"gizmo") as GizmoModule if context != null else null
	if handles != null:
		handles.reassert_ghost()


## **The editor draws no bout units at all**, and none of them cuts a hole in a wall.
##
## taskblock-59 follow-up, and it **supersedes taskblock-59 Pass B's own fix rather than adding to
## it.** Pass B hid the units the authored board could not seat (`BR57.01`) and excluded those from
## the wall cutout. That covered the wrong half: `BoardSwap.swap_board` seats every living unit on
## **the first free walkable cell**, so the author's very first floor tile puts a bout unit on the
## board — visible, and feeding the cutout shader a porthole to punch through nearby walls.
##
## Reported twice and as two defects: *"something is causing a cutout or culling sphere on wall
## parts in the editor"* and *"a random unit stuck around in the editor from the prior map, a squad
## 0 unit 0 looks like"* — both with the note that they came and went together as more was placed.
## **They are one unit.** It appeared with the first floor and vanished whenever the board stopped
## being able to seat it, which is what made it read as intermittent.
##
## **Hiding all of them is not a bigger hammer, it is the correct statement**: the editor authors a
## board, it does not play one, so no unit has a place on it until a bout is launched. That is the
## same *do not draw what is not there* rule Pass B applied to stranded units, applied to the
## premise instead of to a symptom. `run_test_bout` clears `authoring` and the units come back
## through the ordinary injector path.
##
## The real answer is still upstream and still queued — an entry point that builds a world with no
## bout in it (`PLAN.md`, *Main menu*). This makes the editor honest in the meantime, and unlike the
## interim fixes above it does not depend on what the author has placed.
func _hide_bout_units(battle: BattleScene) -> void:
	if not authoring:
		return
	for view: HitVolumeView in battle.unit_views:
		if view.unit == null:
			continue
		view.visible = false
		# A unit that is not drawn has no body to see round, so it cuts nothing. The exclusion set is
		# the mechanism that already says exactly that, and `BoardView.build` clears it every redraw.
		battle.board_view.exclude_unit_from_occlusion(view.unit.id)


## **This is what `ClaimVolumeModule` was built for.** Pass E left it tested and mounted by no
## mode, with `PLAN.md` recording that "the authoring surface that would turn it on is *Map and
## section editors*". This is that surface, and turning it on is one call.
func _refresh_claims() -> void:
	var volumes: ClaimVolumeModule = _claim_volumes()
	if volumes != null:
		volumes.show_claims(controller.claims)


func _refresh_readout() -> void:
	if panel != null:
		panel.show_readout(controller, last_cell)
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
	var named: String = panel.board_name() if panel != null else controller.board_name
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


## taskblock-58 Pass E: **the struck face rides in on the hit dict** (Pass A), and a place verb
## resolves it into where the placement lands. Held on `struck_normal` rather than threaded through
## `apply_tool_at`, because every other tool's answer to "which face" is "it does not matter" and
## widening the router's signature for one of seven would put the exception in every branch.
func _on_board_clicked(hit: Dictionary) -> void:
	var cell: Variant = hit.get("cell")
	if cell == null:
		return
	var normal: Variant = hit.get("normal")
	struck_normal = normal if normal is Vector3 else null
	var point: Variant = hit.get("point")
	struck_point = point if point is Vector3 else null
	apply_tool_at(cell as Vector2i)
	struck_normal = null
	struck_point = null


func _board_inspect() -> BoardInspectModule:
	return context.module(&"board_inspect") as BoardInspectModule if context != null else null


## Points the gizmo at whatever is at `cell`, or clears it when nothing there can be dragged.
##
## **Focusing and clearing are both real answers** — *"a click elsewhere deselects"* — so
## both count
## as the tool having done something.
func _focus_gizmo(cell: Vector2i) -> bool:
	var handles: GizmoModule = context.module(&"gizmo") as GizmoModule if context != null else null
	if handles == null:
		return false
	# taskblock-58 Pass D: **which handle set is the tool, not a second click.** `Select` and
	# `Scale` are two intentions, so arming one of them is how you choose — where a toggle on
	# re-click is a mode you leave by accident. `focus_at` still decides *what* was grabbed;
	# this only says which handles it comes up wearing.
	var focused: bool = handles.focus_at(cell)
	if focused and handles.gizmo.subject != Gizmo.SUBJECT_NONE:
		handles.gizmo.handles = (
			Gizmo.Handles.RESIZE if active_tool == &"scale" else Gizmo.Handles.TRANSLATE
		)
		handles.redraw()
	return focused


func _claim_volumes() -> ClaimVolumeModule:
	return context.module(&"claim_volumes") as ClaimVolumeModule if context != null else null


# --- the panel ---------------------------------------------------------------------------------


## **Puts `EditorPanel` where the Inspect viewer sits**, which is taskblock-57 Pass G2's stated home
## for the section details. What the panel contains is its own file's business as of taskblock-59
## Pass A; what is decided here is only *where it goes* — and the three-way fallback is why this is
## not the panel's own job. A module asking for a slot no chrome publishes lands at `ui_root` (0,0),
## on top of the debug menu and under the announcement band, and mounting against no context at all
## is `test_view_modules_stand_alone.gd`'s acceptance.
func _build_ui() -> void:
	var host: Control = context.slots.get(ModuleSlots.INSPECT_VIEWER) if context != null else null
	panel = EditorPanel.new()
	if host != null:
		host.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	elif context != null and context.ui_root != null:
		context.ui_root.add_child(panel)
	else:
		# The stand-alone case taskblock-56 Pass C's acceptance requires: every widget is real and
		# every verb works; the panel simply has nowhere of its own to be drawn.
		add_child(panel)
	# **Built after it is in the tree**, because the padding override reads the theme it inherits.
	panel.build(controller)
	panel.edge_declared.connect(apply_edge)


## **The floor the editor reaches for when the author has not chosen one**, or `&""` when the data
## has no surfaces at all.
##
## taskblock-59 Pass B: **a named id, and that is the supervisor's call rather than mine.**
##
## This was `surface_part_ids()[0]` — "the first surface part" — which taskblock-56 chose over a
## named default precisely to avoid hardcoding content. **It sorts alphabetically, and the parts
## that attach to `GROUND` are `[ramp, ship_floor]`, so the ordinary floor of this game has been
## `ramp` ever since.** Two reports come off that one line:
##
## - *"The editor's auto-placed terrain places ramps"* — `_ensure_a_tile_under` puts
##   `last_surface_part` under a wall dropped on bare ground, and that was a ramp.
## - *"Warnings appear when placing `ship_floor`"* — and **the warning was correct.** The author
##   places a wall, the editor silently authors a ramp under it, the author then places their own
##   floor on that cell and is told *"the cell already has a surface"* about a surface they never
##   put there and cannot see they put there. A true statement about a state the editor created on
##   their behalf reads exactly like a spurious warning.
##
## taskblock-56's own comment named the intent — *"it should probably be the `ship_floor` part"* —
## and then implemented "first surface part", which is the same sentence only while the data
## happens to sort that way. **Naming it is the smaller lie**: a fallback id in code is visible and
## greppable, where an ordering dependency is neither. The sort order remains the fallback for data
## that has no `ship_floor` in it at all.
func default_floor() -> StringName:
	var floors: Array[StringName] = surface_part_ids()
	if floors.has(DEFAULT_FLOOR):
		return DEFAULT_FLOOR
	return floors[0] if not floors.is_empty() else &""


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
