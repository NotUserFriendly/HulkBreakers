class_name BoardView
extends Node3D

## docs/10 Phase 12.1/12.2: the board's own geometry — a box mesh for every
## placed **tile** and every blocker (docs/02: cover is just a region in the
## shot plane; here it's just a box sitting on the board) — and, separately,
## the TACTICS overlay (reachable highlight, queued-move ghost paths, each its
## own container so one never rebuilds the other, and both can be visible at
## once). Pure presentation: BoardView never mutates Grid, only reads it. Real
## geometry (tiles, blockers) is lit (WorldPalette.lit_material); only the
## transient overlay is unshaded (WorldPalette.overlay_material) — docs/10:
## unshaded same-colour boxes have no edges and merge into a blob, which is why
## real geometry must be lit.
##
## **taskblock-55 Pass B: there is no ground plane.** There was one — first a
## single flat `PlaneMesh`, then one quad per cell at that cell's own height —
## and it is gone rather than reshaped. A **cell** is a grid square and carries
## no elevation; a **tile** is a walkable part and carries all of it. What gets
## drawn is the tiles, from the same `UnitGeometry.assembly_placements` call the
## ray caster marches, so an unfloored cell draws nothing because there is
## nothing there. See `_build_tiles`.

## taskblock-23 Pass E2: a render layer the inspect panel's isolate camera
## (taskblock-22 G2, `HitVolumeView.ISOLATE_LAYER`) can ALSO include
## alongside the subject unit's own layer, so a real board cell renders
## under the model instead of it floating in empty space — never other units
## or blockers, which stay excluded exactly as G2 already fixed. Tagged
## onto the ground plane and grid lines in `build()` below, on top of
## their existing default layer, so the main camera's own view is
## completely unaffected.
const FLOOR_LAYER := 3

## Overlay markers sit slightly above the ground to avoid z-fighting with it;
## ghosts sit a touch higher still so they never fight the reachable tint.
const REACHABLE_HEIGHT := 0.02
const GHOST_HEIGHT := 0.03
const OVERLAY_SIZE := 0.8
const REACHABLE_COLOR := Color(0.55, 0.55, 0.52)
const GHOST_COLOR := Color(0.95, 0.82, 0.25)
## docs/10 taskblock03 D2: each queued leg gets its own tint so consecutive
## moves read as distinct segments instead of one merged smear — cycled if
## the queue ever outgrows this list, since nothing caps queue length.
## `BR30.04`, taskblock-61 Pass D — **the per-leg colour cycle is retired.** Waypoints shuffled
## colour when an attack was armed because `LEG_COLORS[i % 4]` re-indexed every leg whenever
## step-out inserted its free ones, and the supervisor's answer was to stop colouring by index at
## all: *"mono color it. All queued waypoints are one color and a hollow box drawn on the walkable
## terrain underneath. The most recent waypoint is a filled in box. Lime green for each."*
##
## **The shuffle is fixed by construction rather than by fixing the modulo** — with nothing keyed on
## leg index, inserting a leg cannot recolour the legs already on screen. Which also means the
## ledger's own step-out diagnosis is neither confirmed nor needed; the supervisor doubted it
## (*"I'm not sure this is step out related"*) and it is now moot either way.
##
## The literal value is CSS `limegreen`; the supervisor named the colour, not the hex, so this is
## the flagged, tunable spelling of it (CLAUDE.md: never invent a final number).
const WAYPOINT_COLOR := Color("#32CD32")

const WAYPOINT_LABEL_HEIGHT := 0.6
const WAYPOINT_FONT_SIZE := 24
## docs/10 taskblock03 F1: "translucent... low alpha" — low enough to never
## be mistaken for the real, opaque unit.
const UNIT_GHOST_ALPHA := 0.35
## taskblock-19 Pass D: the visible-overwatch pie slice — amber, distinct
## from every other overlay's own colour, translucent (WorldPalette:
## "a transparent overlay, not the UI palette"). Sits above the ghost
## overlays so it never fights them for z-order when both are live.
const OVERWATCH_ARC_COLOR := Color(0.95, 0.55, 0.15, 0.30)
## taskblock-27 Pass C2: part of the one ordered ground-overlay height
## ladder — see `EXTRACTION_CELL_HEIGHT`'s own comment below for the full
## enumeration. Raised from 0.04 to clear `HitVolumeView.TEAM_MARKER_Y`'s
## own new top face (0.07) with margin.
const OVERWATCH_ARC_HEIGHT := 0.09
## docs/10 taskblock03 I: the original #253B29 was a value or two off
## WorldPalette.GROUND (#2E4A32) — nearly the same value, so it mipped away
## to nothing at the default tactical camera distance. Pushed much further
## from the ground's own value (still dim, still a reference, never bright)
## and drawn as real-width quads (below) rather than 1px GPU line
## primitives, which is the actual fix for "thin": PRIMITIVE_LINES has no
## adjustable width in this renderer, so no color change alone could have
## fixed legibility.
const GRID_LINE_COLOR := Color("#16241A")
const GRID_LINE_HEIGHT := 0.005
const GRID_LINE_WIDTH := 0.04
## runNotes.md: "Not all of the drawn boards are navigable... If a cell
## isn't navigable, it needs something to show that. Color it Dark Gray and
## draw a cross through it." WALL cells are permanent map geometry, not a
## TACTICS overlay, so these live in `_static` alongside the grid lines, not
## one of the ephemeral overlay containers.
## taskblock-22 Pass A3: "simple colored floor markers now" — its own
## height tier, between the grid lines and the wall indicators, so it never
## z-fights with either (extraction cells sit on open ground in practice,
## but nothing here assumes that).
##
## taskblock-27 Pass C2: the anchor of ONE ordered ground-overlay height
## ladder, enumerated here after tb26 A3's own facing-wedge fix twice
## missed a DIFFERENT co-planar element in turn (bumping one marker in
## isolation, with no shared ordering, was the actual bug). Center
## heights, not top faces (`_marker()`'s own doc comment) — most rungs are
## 0.02-thick boxes/discs:
##   `EXTRACTION_CELL_HEIGHT` (0.010, this constant)
##   -> `HitVolumeView.TEAM_MARKER_Y` (0.06 — was IDENTICAL to this
##      constant, 0.01, a real unreported co-planar pair found while
##      enumerating this set for the first time)
##   -> `OVERWATCH_ARC_HEIGHT` (0.09, below)
##   -> `HitVolumeView.FACING_WEDGE_Y` (0.17 — 5x taller than every other
##      rung, needs real headroom, not just the next small step)
## A future ground overlay takes the next rung in THIS ladder, not a
## value picked independently.
const EXTRACTION_CELL_HEIGHT := 0.010
## taskblock-39 Pass C: the wall-indicator marker/cross these four
## constants used to feed is retired (never actually rendered on a real
## generated map — see `_build_empty_indicators`'s own doc comment). Kept,
## unconsumed, purely as the height-ladder anchors `EMPTY_BORDER_HEIGHT`/
## `FIELD_ITEM_MARKER_HEIGHT` below are still calibrated against.
const WALL_INDICATOR_COLOR := Color("#3A3A3A")
## runNotes.md follow-up: "fade it to a gray that's just slightly darker
## than the cell gray" — a quiet reference mark, not a bold warning X.
const WALL_CROSS_COLOR := Color("#2A2A2A")
const WALL_INDICATOR_HEIGHT := 0.015
## runNotes.md follow-up: "gray overlay for cells is drawing overtop the
## cross indicator, put the cross on top." `_marker()` draws a real BoxMesh
## with its own 0.02 Y-thickness, centered on `height` — the indicator
## cell's top FACE therefore sits at WALL_INDICATOR_HEIGHT + 0.01 (0.025),
## above a same-magnitude flat cross at the old 0.02, which is exactly why
## the box was winning the depth test. Clearly above that top face, not
## just above the marker's own center height.
const WALL_CROSS_HEIGHT := 0.03
const WALL_CROSS_WIDTH := 0.06
## tb31 Pass C: make empty/unfloored cells black with a dark gray border
## so they read as empty (taskblock-39 Pass D retired the original spec
## language's own term for this — this file's own concept has always been
## empty/unfloored ground) — the same "non-navigable terrain needs a real
## marker" convention `WALL_INDICATOR_COLOR`/`WALL_CROSS_COLOR` above
## already established, just a fill+border instead of a fill+cross (an
## empty cell has nothing to cross out — it's not an obstruction, it's the
## absence of anything at all). Slots into the SAME ordered ground-overlay
## height ladder, between the wall indicator (0.015) and the wall cross
## (0.03) — an empty cell never coexists with a wall/extraction/team-
## marker/overwatch cell in practice, but the ladder convention is "the
## next rung," not "pick whatever's free."
const EMPTY_BORDER_COLOR := Color("#3A3A3A")
const EMPTY_FILL_COLOR := Color("#050505")
const EMPTY_BORDER_HEIGHT := 0.02
const EMPTY_FILL_HEIGHT := 0.025
## Border size close to the full cell (a thin dark-gray rim); fill
## smaller still, same relationship `OVERLAY_SIZE` already has to a full
## `CELL_SIZE` cell.
const EMPTY_BORDER_SIZE := 0.98
const EMPTY_FILL_SIZE := 0.8
## taskblock-30 follow-up: a loose `Matrix` field item has no `volume` to
## draw real geometry from (unlike a loose Part, rendered via the SAME
## `_spawn_blocker` boxes a cover item uses) — a flat marker, same "ground
## overlay" tier as the rest of this file's height ladder above, between
## `WALL_CROSS_HEIGHT` (0.03) and `HitVolumeView.TEAM_MARKER_Y` (0.06).
## Placeholder color, flagged/tunable like every other marker color here.
const FIELD_ITEM_MARKER_HEIGHT := 0.045
const FIELD_ITEM_MARKER_COLOR := Color(0.75, 0.65, 0.35)

## tb32 Pass A: how many cells wide the wall-cutout porthole is, before
## being projected to screen pixels at each unit's own depth
## (`WallLegibility.pixel_radius_for_cells`) — "~2.5 cells, comfortably
## clears ~three walls" per the taskblock's own starting point. Flagged,
## tunable (CLAUDE.md: never invent a "final" balance number). Because
## it's cells-at-that-unit's-own-depth, camera zoom scales the resulting
## pixel radius automatically — no separate distance logic. tb32 Pass B
## reuses this unchanged for the friendly-fade occlusion test too (same
## "how close counts as blocking" definition either way).
const OCCLUSION_RADIUS_CELLS := 2.5
## The shader's own fixed-size uniform arrays (`wall_cutout.gdshader`'s
## `MAX_UNITS`) — must match exactly; a battle fielding more units than
## this simply stops feeding the excess to the cutout (they'd still be
## visible, just not cut through a wall for).
const WALL_CUTOUT_MAX_UNITS := 32

## taskblock-51 (`BR26.02`): switched by the `set_aim_visual` debug verb so the supervisor
## can bisect a GPU cost CC cannot measure. **Default on — the game behaves normally unless
## someone is deliberately hunting.**
## The `discard`-based cutout shader runs over every wall mesh every frame; `discard`
## disables early-Z, so this is a real fill-rate suspect on a board with 166 walls.
static var show_wall_cutout: bool = true

## taskblock-41 Pass D: the bout-build log's destination, set by
## `BattleScene.load_battle()` before it calls `build()`. Optional and
## null-safe — every headless fixture builds a board with no battle around it
## and must keep working untouched.
var build_log: CombatLog = null

var grid: Grid
## tb32 Pass A: "cut around every unit, not one focal unit." Whichever
## units are worth reading through a wall right now — set directly by
## whichever overlay owns "what's on the board right now"
## (`SquadControlOverlay._on_battle_loaded()` points this at the live
## `CombatState.units` array; `SpectatorOverlay`/`GenerateBoutOverlay`
## never set it, so the cutout simply never fires there, per the
## taskblock's own "spectator keeps its current no-fade behavior for
## now"). Re-projected every frame (`_process`, below), never cached,
## since the camera itself can move continuously (drag-to-orbit) with no
## signal of its own to react to. tb32 Pass B also scans this same list
## for "is any OTHER unit blocking the active unit's own aim" — one
## source of "every unit on the board," not two.
var wall_cutout_units: Array[Unit] = []
## `BR32.04`: the live `BattleScene.unit_views` array, or empty. **A display-position source, never
## a membership one** — `wall_cutout_units` still decides who gets a cutout, and a unit with no
## view here simply falls back to its logical position, which is exactly the behaviour before this
## existed. So an out-of-date entry cannot remove a cutout or invent one; the worst it can do is
## place a hole where the body already is.
##
## **Why the view at all.** `resolve_to_marker()` mutates `unit.cell` synchronously, so the logical
## body arrives at the destination the frame Resolve is clicked, while `ResolutionPlayer` is still
## tweening the visible one across several frames. Reading the position from `unit.cell` therefore
## cut the hole at the destination around a body that had not got there — the reported symptom.
## `ResolutionPlayer._apply_display_transform` writes this node's own `position`/`basis` on every
## tween tick and leaves them at identity when nothing is animating, so the rendered transform is
## always current with no cache to invalidate. `docs/00`: read the real node back rather than
## deriving a second opinion about where the body is.
var wall_cutout_views: Array[HitVolumeView] = []
## tb32 Pass B: "in dartboard/aiming view only" — the shooter whose own
## read of its shot is worth protecting RIGHT NOW (`selection.
## selected_unit`, not `aiming_at` — the target). Null whenever the
## player isn't both aiming AND has a unit selected, so the friendly-fade
## check simply never fires outside that view (`SquadControlOverlay
## ._on_selection_changed()` owns exactly when this is set/cleared). Read
## by `BattleScene._process()` — the actual per-unit occlusion decision
## and fade live on `HitVolumeView` itself now (a real body fade, not a
## ghost overlay drawn elsewhere; see `HitVolumeView.set_occlusion_faded`'s
## own doc comment for why), and BoardView has no reference to any
## HitVolumeView to call that on directly.
var aim_active_unit: Unit = null

## taskblock-59 Pass B: which mesh stands at which cell, so the gizmo can make what it grabbed
## see-through. Its own class — `CellGhosting` carries the seam and the merged-tile limit.
var ghosting := CellGhosting.new()

## A unit whose own `HitVolumeView` was explicitly destroyed
## (`BattleScene.remove_unit_view()`, the debug-only "make it fully
## vanish" verb) never clears its stale `.cell` from `combat_state.units`
## — an unfiltered feed here cuts/occludes a permanent, unit-less hole at
## wherever it last stood. Populated by `BattleScene.remove_unit_view()`
## via `exclude_unit_from_occlusion()`; cleared on every `build()` (a
## fresh "New Battle" must not inherit a previous bout's own exclusions —
## same reasoning `BattleScene._removed_unit_ids` already follows).
## Deliberately NOT applied to an ordinary in-combat kill (`alive ==
## false` alone) — that unit's downed body is still really there; only an
## explicitly vanished view has nothing left to protect visibility of.
var _excluded_from_occlusion: Dictionary = {}

## Reset at the top of every `build()` — a rebuilt board restarts its own
## sequence rather than continuing the previous one's numbering.
var _build_step_index := 0
## The last cutout arrangement actually written to the log, so an unchanged
## one is not written again. Cleared on every `build()`.
var _cutout_log := CutoutLog.new()
var _static: Node3D
var _reachable_overlay: Node3D
var _ghost_overlay: Node3D
## docs/10 taskblock03 F1: the end-position unit ghost — its own container,
## separate from `_ghost_overlay` (waypoint paths), since show_ghost_paths()
## and show_unit_ghost() each clear only their own overlay and both can be
## live at once.
var _unit_ghost_overlay: Node3D
## taskblock-19 Pass D: the visible-overwatch pie slice — its own
## container, same reasoning as `_unit_ghost_overlay`.
var _overwatch_overlay: Node3D
## tb31 Pass C: every wall's own `MeshInstance3D`(s), tracked separately
## from ordinary scatter-cover meshes (`_spawn_blocker` below) so
## `_process()` only ever re-evaluates the (usually much smaller) set of
## meshes that can actually be tall/opaque enough to be a legibility
## problem in the first place.
var _wall_mesh_instances: Array[MeshInstance3D] = []
## tb32 Pass A: ONE shared `wall_cutout_material()` instance for every
## wall spawned by this `build()` — walls all draw from the same `steel`
## material today, and the cutout is a per-fragment shader effect, not a
## per-object property, so there's nothing an individual wall needs its
## own copy for. Lazily created on the first wall placement encountered
## (`_spawn_blocker`), reset to null at the top of `build()` so a rebuilt
## map never keeps a stale instance around.
var _wall_cutout_material: ShaderMaterial = null


func _init() -> void:
	_static = Node3D.new()
	add_child(_static)
	_reachable_overlay = Node3D.new()
	add_child(_reachable_overlay)
	_ghost_overlay = Node3D.new()
	add_child(_ghost_overlay)
	_unit_ghost_overlay = Node3D.new()
	add_child(_unit_ghost_overlay)
	_overwatch_overlay = Node3D.new()
	add_child(_overwatch_overlay)


## taskblock-22 Pass A3: `team_extraction_cells` (squad_id -> Array[Vector2i],
## the same shape `MissionState` already carries) is optional — an empty
## Dictionary (every existing caller/test) simply draws no cells at all,
## unchanged.
func build(
	p_grid: Grid, material_table: MaterialTable, team_extraction_cells: Dictionary = {}
) -> void:
	grid = p_grid
	_build_step_index = 0
	_cutout_log.reset()
	_clear(_static)
	_wall_mesh_instances.clear()
	ghosting.reset()
	_wall_cutout_material = null
	_excluded_from_occlusion.clear()

	# taskblock-41 Pass D: "a bout-build log in the order things actually
	# happen... recounted in build order rather than summarised at the end.
	# Build order is what makes it a diagnostic; the same numbers summarised
	# are not." Each step is emitted as it completes, so a board that comes out
	# wrong can be read as a sequence — the step that produced nothing, or ran
	# before something it depended on, is visible without a rebuild.
	# taskblock-55 Pass B: counted in **tiles placed**, not cells. The board no
	# longer draws one thing per cell, so a per-cell count would report a number
	# nothing in the scene corresponds to — and "how many walkable parts are
	# actually on this board" is the more useful diagnostic anyway, since an
	# unfloored cell is now genuinely empty rather than quietly floored.
	# taskblock-58 Pass B: one flat walk of the store rather than a cell-at-a-time
	# reassembly of it. Same number — "tiles placed" is exactly what a placement is.
	_log_build_step(&"tiles", grid.placements().size(), "walkable parts")
	var ground: MeshInstance3D = _build_tiles(grid, material_table)
	ground.set_layer_mask_value(FLOOR_LAYER, true)
	_static.add_child(ground)
	var grid_lines: MeshInstance3D = _build_grid_lines(grid)
	grid_lines.set_layer_mask_value(FLOOR_LAYER, true)
	_static.add_child(grid_lines)
	_log_build_step(&"grid_lines", grid.width * grid.rows, "cell borders")
	_log_build_step(&"empty_cells", _build_empty_indicators(grid), "unfloored cells")
	_log_build_step(&"extraction_cells", _build_extraction_cells(team_extraction_cells), "cells")

	var walls := 0
	var cover := 0
	for cell: Vector2i in grid.blockers:
		var blocker: Part = grid.blockers[cell]
		_spawn_blocker(blocker, cell, material_table)
		if blocker.id == &"wall":
			walls += 1
		else:
			cover += 1
	# Walls and cover come off the SAME `grid.blockers` sweep, so they are
	# counted where they are actually built rather than re-derived afterwards
	# from the grid — a recount would agree with the map, not with the board.
	_log_build_step(&"walls", walls, "wall blockers")
	_log_build_step(&"cover", cover, "cover objects")

	var field_items := 0
	for cell: Vector2i in grid.field_items:
		for item: Variant in grid.field_items[cell]:
			_spawn_field_item(item, cell, material_table)
			field_items += 1
	_log_build_step(&"field_items", field_items, "loose items")


## One step of the bout-build log. `index` is the running step number, so the
## ORDER survives even if a consumer sorts or filters the stream.
func _log_build_step(step: StringName, count: int, noun: String) -> void:
	if build_log == null:
		return
	_build_step_index += 1
	build_log.emit(
		LogEvent.new(
			0,
			Enums.Phase.TACTICS,
			-1,
			&"build_step",
			{"step": step, "count": count, "index": _build_step_index},
			"build %d: %s — %d %s" % [_build_step_index, step, count, noun]
		)
	)


## taskblock-55 Pass B: **only parts carry height, so only parts are drawn.**
##
## This function used to draw one flat quad per *cell*, at that cell's own height
## — and before taskblock-54 Pass B1, a vertical riser between neighbours that
## differed. The riser went because it had no `Part` behind it (`BR52.03`). **The
## per-cell quad had exactly the same defect, one primitive down**, and survived
## the riser deletion only because it was the older of the two:
##
## - On a cell with a floor, the quad was a *second* thing at that elevation,
##   co-planar with the real `Surface` part's own top face and hiding it. Two
##   drawings of one fact, and a shot only ever intersected the part.
## - On a cell with **no** floor at all, the quad was ground you could see and
##   walk your eye across with nothing behind it whatsoever.
##
## **A cell is not a thing with an elevation.** It is a grid square, and empty.
## A walkable part — a **tile** — sits at the height it occupies, and that part is
## the only thing at that elevation, the only thing a shot can strike and the only
## thing a foot can find. So the tiles are what gets drawn, as their **real
## authored box geometry** rather than a stand-in quad.
##
## **The placements come from `UnitGeometry.assembly_placements`, which is the
## same call `RayCaster._consider_surface` makes** — the same part, the same
## height, the same `facing`. *Render is hitbox* (`docs/10`) stops being a
## property this file has to remember and becomes one it cannot break: there is
## no second formula here to drift away from the first.
##
## **Expect the board to look sparser**, exactly as the riser deletion did, and
## for the same reason. A raised floor reads as a floating slab; filling its side
## is authored content — a wall, a strut, a bulkhead placed by a section — not an
## automatic terrain feature. An unfloored cell now draws nothing at all, which is
## what `_build_empty_indicators` is already there to mark.
func _build_tiles(p_grid: Grid, material_table: MaterialTable) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()

	# Grouped by colour so the whole board's tiles cost one surface per material
	# rather than one MeshInstance3D per cell. Iterated in a stable order — a
	# Dictionary keyed by colour would leave surface order dependent on insertion,
	# and a mesh that rebuilds differently between two identical grids is a
	# needless source of "the board changed and nothing changed."
	var by_color: Dictionary = {}
	var color_order: Array[Color] = []
	for surface: Surface in p_grid.placements():
		var color: Color = WorldPalette.tile_color(material_table, surface.part.material)
		if not by_color.has(color):
			by_color[color] = [] as Array[BoxPlacement]
			color_order.append(color)
		(by_color[color] as Array[BoxPlacement]).append_array(
			UnitGeometry.assembly_placements(
				surface.part, surface.cell, surface.facing, null, surface.height
			)
		)

	for color: Color in color_order:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, WorldPalette.lit_material(color))
		for placement: BoxPlacement in by_color[color]:
			_add_box(
				mesh, placement.transform.translated_local(placement.box.center), placement.box.size
			)
		mesh.surface_end()

	instance.mesh = mesh
	return instance


## "Team-coded extraction cells, drawn in their team's color" — one flat
## marker per cell, `WorldPalette.team_color(squad_id)` same as every other
## team-coded visual already reads (docs/10).
## taskblock-41 Pass D: returns how many cells it drew, same reasoning as
## `_build_empty_indicators`.
func _build_extraction_cells(team_extraction_cells: Dictionary) -> int:
	var count := 0
	for squad_id: int in team_extraction_cells:
		var color: Color = WorldPalette.team_color(squad_id)
		var cells: Array = team_extraction_cells[squad_id]
		for cell: Vector2i in cells:
			_static.add_child(_marker(cell, color, EXTRACTION_CELL_HEIGHT))
			count += 1
	return count


## docs/10 taskblock02 G3 / taskblock03 I: "the ground is a flat green plane
## and you can't tell where the cells are." A line per cell boundary, just
## above the ground to avoid z-fighting — a reference, not decoration, so it
## stays unshaded and dim rather than lit and bright. Real GRID_LINE_WIDTH-
## wide quads, not 1px GPU line primitives (no shader/LOD trick — just
## actual geometry with a real width, drawn with the same real-width
## convention D2's leg lines / F2's targeting line already use).
## taskblock-37 Pass E follow-up made this per-cell, each cell drawing its
## border at THAT cell's own real height, to match the terraced ground quad.
##
## ## taskblock-55 Pass B: back to one flat plane, because the cell is empty
##
## The ground quad it was matching is gone, and with it the reason to climb.
## Two rules from this pass settle it between them:
##
## - **"The grid stops expressing height — one flat plane, or nothing."** This
##   mesh is now the flat plane: a floor-plan reference at a constant Y, saying
##   where the cells are and nothing about how high anything is.
## - **"That part is the only thing at that elevation."** A line riding a tile's
##   own top face would be a second thing there — precisely the co-planar pairing
##   the ground quad was deleted for, and the reason this could not simply keep
##   reading the tile instead of the cell.
##
## A shared edge between two neighbours is drawn twice (perfectly overlapping
## geometry, no visible difference) rather than deduplicated — with every line at
## one height that is now always an exact overlap, where the per-cell version
## relied on it only for equal-height pairs.
##
## **A raised tile hides the lines beneath it, and that is honest**: the tile is
## solid and it is above them. The drop at its edge is marked by the tile's own
## real sides now, which — unlike both the riser and the per-cell border — is
## geometry a shot actually intersects.
func _build_grid_lines(p_grid: Grid) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var cell_size: float = UnitGeometry.CELL_SIZE
	var half: float = cell_size * 0.5
	var half_width: float = GRID_LINE_WIDTH * 0.5
	var wy: float = GRID_LINE_HEIGHT

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, WorldPalette.overlay_material(GRID_LINE_COLOR))
	for y in range(p_grid.rows):
		for x in range(p_grid.width):
			var cx: float = x * cell_size
			var cz: float = y * cell_size
			var x_min: float = cx - half - half_width
			var x_max: float = cx + half + half_width
			var z_min: float = cz - half - half_width
			var z_max: float = cz + half + half_width
			for wx: float in [cx - half, cx + half]:
				_add_quad(
					mesh,
					Vector3(wx - half_width, wy, z_min),
					Vector3(wx + half_width, wy, z_min),
					Vector3(wx + half_width, wy, z_max),
					Vector3(wx - half_width, wy, z_max)
				)
			for wz: float in [cz - half, cz + half]:
				_add_quad(
					mesh,
					Vector3(x_min, wy, wz - half_width),
					Vector3(x_max, wy, wz - half_width),
					Vector3(x_max, wy, wz + half_width),
					Vector3(x_min, wy, wz + half_width)
				)
	mesh.surface_end()

	instance.mesh = mesh
	return instance


## tb31 Pass C: every empty cell (the negative-space fill past a wall's
## own ring) gets a black fill inside a dark-gray border — "there's
## nothing here" read at a glance.
##
## taskblock-39 Pass C: the sibling wall-indicator marker (gray cell plus
## a cross, "this is an obstruction") this comment used to contrast
## against is retired — it never actually rendered on any real generated
## map (`MapGen._finalize_walls_and_empty` always resolves an uncarved
## cell to OPEN+blocker or empty before `_emit`, so a raw WALL terrain
## read was already unreachable there); a real wall's own full-height
## blocker box already makes "can't walk here" obvious without a
## redundant flat marker.
##
## Empty is "no Surface placed at all" — the exact real-placement
## equivalent `MapGen._finalize_walls_and_empty` resolves an unreachable
## uncarved cell into (no floor, no blocker, opacity 0), not a retired
## terrain code read directly.
## taskblock-41 Pass D: returns how many it drew, so the bout-build log counts
## what was actually placed rather than re-deriving it from the grid a second
## time — two counts of the same thing eventually disagree.
func _build_empty_indicators(p_grid: Grid) -> int:
	var count := 0
	for y in range(p_grid.rows):
		for x in range(p_grid.width):
			var cell := Vector2i(x, y)
			if Surface.first_walkable(p_grid.surfaces_at(cell)) == null:
				_static.add_child(
					_marker(cell, EMPTY_BORDER_COLOR, EMPTY_BORDER_HEIGHT, EMPTY_BORDER_SIZE)
				)
				_static.add_child(
					_marker(cell, EMPTY_FILL_COLOR, EMPTY_FILL_HEIGHT, EMPTY_FILL_SIZE)
				)
				count += 1
	return count


static func _add_quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(d)


## taskblock-55 Pass B: one authored `Box`, as six real faces at `xform`.
##
## `xform` is the placement transform with the box's own centre already composed
## in — the identical expression `_spawn_blocker` hands to a `BoxMesh`
## (`placement.transform.translated_local(placement.box.center)`), so a tile drawn
## into this mesh and a blocker drawn as its own node agree about where a box is.
##
## **A box, not a top quad.** A tile has thickness — `ship_floor` is 0.2 — and a
## shot fired at its edge intersects that thickness. Drawing only the top face
## would put the *old* defect back at a smaller scale: visible geometry whose
## sides a round passes through unseen.
##
## ## taskblock-56 Pass A, `BR55.02`: the winding was reversed, and the comment said so
##
## This is the only hand-wound geometry on the board — every other box (blockers,
## cover, dropped assemblies, markers, ghosts) is a Godot `BoxMesh`, correct by
## construction. So the tiles were the only thing that could show this, and they did:
## outward faces culled, interior faces drawn.
##
## **The convention, measured rather than assumed.** `BoxMesh` emits every triangle
## with `(b - a).cross(c - a)` pointing **into** the solid — its dot with the stored
## outward normal is `-1` on all twelve. That is Godot's front-face rule stated in the
## only terms this file can check: **a face's vertices run clockwise seen from
## outside**, and the cross product of the emitted order points *inward*. The previous
## comment here asserted the opposite ("counter-clockwise seen from outside"), which is
## the bug written down as if it were true. `test_board_view_winding.gd` reads a real
## `BoxMesh` back and requires this mesh to agree with it, so the convention is never
## restated from memory again.
##
## **No normals are emitted, and that is deliberate rather than an oversight.**
## `_add_quad` calls `surface_add_vertex` only, so culling is decided by winding alone
## — there is no normal to disagree with it and mask the fault as a material setting.
static func _add_box(mesh: ImmediateMesh, xform: Transform3D, size: Vector3) -> void:
	var h: Vector3 = size * 0.5
	# The eight corners, in the box's own local space, then placed by `xform`.
	var c: Array[Vector3] = []
	for sx: float in [-h.x, h.x]:
		for sy: float in [-h.y, h.y]:
			for sz: float in [-h.z, h.z]:
				c.append(xform * Vector3(sx, sy, sz))
	# Indices into `c`, whose order above is x-major then y then z: 0 = (-,-,-),
	# 1 = (-,-,+), 2 = (-,+,-), 3 = (-,+,+), 4 = (+,-,-), 5 = (+,-,+),
	# 6 = (+,+,-), 7 = (+,+,+). Each quad runs CLOCKWISE seen from outside the box
	# — Godot's front-face order, see the note above — so back-face culling keeps
	# the faces pointing at the camera and discards the interior.
	_add_quad(mesh, c[6], c[7], c[3], c[2])  # +Y, the top face a unit stands on
	_add_quad(mesh, c[1], c[5], c[4], c[0])  # -Y
	_add_quad(mesh, c[7], c[5], c[1], c[3])  # +Z
	_add_quad(mesh, c[0], c[4], c[6], c[2])  # -Z
	_add_quad(mesh, c[4], c[5], c[7], c[6])  # +X
	_add_quad(mesh, c[2], c[3], c[1], c[0])  # -X


## docs/10 taskblock04 C1/C2: a field object can be a whole part TREE (a
## dropped assembly — plate, weapon and all), the same "render is hitbox"
## contract HitVolumeView already honours — never just the root's own `volume`,
## which would silently drop a still-living child riding along a destroyed
## parent. `assembly_placements` walks it exactly like a Unit's own shell.
## A part tagged DROPPED (DamageResolver's own marker) lays on its side —
## the same trick HitVolumeView already uses for a downed unit (taskblock03 G) —
## so it reads as a fallen assembly, not upright cover.
func _spawn_blocker(part: Part, cell: Vector2i, material_table: MaterialTable) -> void:
	var dropped: bool = DamageResolver.DROPPED_TAG in part.tags
	# taskblock-61 Pass C1: an authored tag, not `part.id == &"wall"` — content identity in code is
	# what CLAUDE.md forbids, and a second cuttable terrain type would have needed an edit here.
	# `WallLegibility.CUTOUT_TAG` is the same fact the sight gate reads, so what is drawn cuttable
	# and what counts as occluding cannot drift apart.
	var is_cutout: bool = WallLegibility.CUTOUT_TAG in part.tags
	# taskblock-37 Pass E: the real height to sit at — `assembly_placements`
	# defaults to a flat `height == 0.0`, which used to be harmless (nothing
	# was ever raised); a cover object or wall over a raised cell needs to
	# actually rest ON the ground there, not float at world level 0 beneath it.
	#
	# taskblock-55 Pass B: that ground is **the tile**, which is what
	# `_height_for` has always resolved to (`true_height_for_cell` reads the
	# placed walkable `Surface`). A blocker standing on a tile is a part on a
	# part — real geometry resting on real geometry — so this is the one height
	# read the pass leaves exactly as it was.
	var height: float = _height_for(cell)
	for placement: BoxPlacement in UnitGeometry.assembly_placements(part, cell, 0.0, null, height):
		var instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = placement.box.size
		if is_cutout:
			# tb32 Pass A: one shared cutout material for every wall,
			# not `WorldPalette.lit_material()` per-placement — see
			# `_wall_cutout_material`'s own doc comment.
			if _wall_cutout_material == null:
				_wall_cutout_material = WorldPalette.wall_cutout_material(
					material_table.color_for(placement.part.material)
				)
			box_mesh.material = _wall_cutout_material
		else:
			box_mesh.material = WorldPalette.lit_material(
				material_table.color_for(placement.part.material)
			)
		instance.mesh = box_mesh
		var world_transform: Transform3D = placement.transform.translated_local(
			placement.box.center
		)
		instance.transform = (
			_dropped_transform(cell, height) * world_transform if dropped else world_transform
		)
		_static.add_child(instance)
		ghosting.record(cell, instance)  # taskblock-59 Pass B — see `CellGhosting`.
		# tb31 Pass C: tracked separately so `_process()` only re-evaluates
		# legibility fading against walls specifically, not every box on
		# the board.
		if is_cutout:
			_wall_mesh_instances.append(instance)


static func _dropped_transform(cell: Vector2i, height: float = 0.0) -> Transform3D:
	var pivot: Vector3 = Vector3(
		cell.x * UnitGeometry.CELL_SIZE, height, cell.y * UnitGeometry.CELL_SIZE
	)
	return (
		Transform3D(Basis.IDENTITY, pivot)
		* Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
		* Transform3D(Basis.IDENTITY, -pivot)
	)


## taskblock-30 follow-up (supervisor report): `Grid.field_items` (loose
## dropped Parts/Matrices lying on the ground — a real, pre-existing
## `Grid` concept, `Grid.dup()`'s own doc comment already calls it out)
## had ZERO visual representation anywhere, in debug tooling AND real
## gameplay alike (a shot ejecting a matrix, or dropping a severed limb,
## mutated this dict correctly but nothing ever drew it). A loose Part
## reuses `_spawn_blocker`'s own geometry unchanged — the exact same
## "render is hitbox" contract, just not blocking movement/LoS (nothing
## about `Pathfinder`/`ShotPlane` reads `field_items` at all, so drawing
## it here changes nothing mechanical). A loose Matrix has no `volume` to
## draw real geometry from — a flat placeholder marker instead, same tier
## as every other ground overlay in this file.
func _spawn_field_item(item: Variant, cell: Vector2i, material_table: MaterialTable) -> void:
	if item is Part:
		_spawn_blocker(item, cell, material_table)
	elif item is Matrix:
		_static.add_child(_marker(cell, FIELD_ITEM_MARKER_COLOR, FIELD_ITEM_MARKER_HEIGHT))


## `BattleScene.remove_unit_view()` calls this the instant a unit's own
## real presence on the board vanishes (the debug-only "make it fully
## vanish" verb) — see `_excluded_from_occlusion`'s own doc comment for
## why this is a real, distinct case from an ordinary in-combat kill.
func exclude_unit_from_occlusion(unit_id: int) -> void:
	_excluded_from_occlusion[unit_id] = true


func is_excluded_from_occlusion(unit_id: int) -> bool:
	return _excluded_from_occlusion.has(unit_id)


## tb32 Pass A: supersedes `update_wall_legibility` — GDScript's only job
## now is projecting every unit in `wall_cutout_units` to a screen
## position/depth/radius and feeding them to the ONE shared
## `_wall_cutout_material` as uniform arrays; `wall_cutout.gdshader`
## itself decides, per fragment, whether a wall discards. Re-evaluated
## every frame (`_process`, below), not just on a selection/unit-list
## change — the camera itself can move continuously (drag-to-orbit) with
## no signal of its own to react to. Split from `_process` so a test can
## drive it against a real, deliberately positioned `Camera3D` directly
## (docs/10 standing rule 2: read the real node back).
func update_wall_cutout(camera: Camera3D) -> void:
	if _wall_cutout_material == null:
		return
	var screen_positions := PackedVector2Array()
	var depths := PackedFloat32Array()
	var radii := PackedFloat32Array()
	screen_positions.resize(WALL_CUTOUT_MAX_UNITS)
	depths.resize(WALL_CUTOUT_MAX_UNITS)
	radii.resize(WALL_CUTOUT_MAX_UNITS)
	var count := 0
	var blocked_by: Array = []
	var display: Dictionary = _display_transforms()
	if camera != null and is_inside_tree():
		var camera_position: Vector3 = camera.global_position
		var viewport_height: float = float(get_viewport().size.y)
		for unit: Unit in wall_cutout_units:
			if count >= WALL_CUTOUT_MAX_UNITS:
				break
			if unit == null or not is_instance_valid(unit):
				continue
			# `WallLegibility.cuts_for` states the per-unit rule whole; this runs its two halves
			# in cost order and hands the ONE `bounding_box` walk to both the sight gate and the
			# fed position. Two walks per unit per frame took the feed 3 020 -> 5 281 usec.
			if is_excluded_from_occlusion(unit.id) or not WallLegibility.is_cutout_subject(unit):
				continue
			# `BR32.04`: the body where it is DRAWN, not where the model says it is. Identity for
			# anything not mid-animation, so this is a no-op except during a slide or a turn.
			var shown: Transform3D = display.get(unit.id, Transform3D.IDENTITY)
			var points: Array[Vector3] = WallLegibility.body_sight_points(
				UnitGeometry.bounding_box(unit)
			)
			for i in range(points.size()):
				points[i] = shown * points[i]
			var position: Vector3 = points[0]
			# Behind the camera: unproject_position() gives nonsense screen coordinates for a
			# point the camera isn't looking at — nothing is occluded for a unit that is off screen,
			# and this rejects before the sight gate rather than after it.
			if camera.is_position_behind(position):
				continue
			var blamed: Variant = WallLegibility.blocking_cell(
				grid, camera_position, UnitGeometry.cell_of(position), points
			)
			if blamed == null:
				continue
			blocked_by.append(blamed)
			var depth: float = camera_position.distance_to(position)
			# BR32.02: `unproject_position()` and the shader's own
			# FRAGCOORD are BOTH top-left-origin, Y-DOWN — confirmed live,
			# empirically (a hardcoded-corner diagnostic landed in the
			# window's own top-left corner). No conversion needed; feed
			# unproject_position()'s own output directly. A Y-flip was
			# tried here first, based on documentation claiming FRAGCOORD
			# matches GLSL's bottom-left-origin gl_FragCoord default — that
			# was confirmed EMPIRICALLY WRONG (it turned "no cutout ever
			# appears" into "a cutout appears, detached from any unit,
			# drifting as the camera orbits" — a vertical mirror of the
			# correct position) and has been removed.
			screen_positions[count] = camera.unproject_position(position)
			depths[count] = depth
			radii[count] = WallLegibility.pixel_radius_for_cells(
				OCCLUSION_RADIUS_CELLS, depth, camera.fov, viewport_height
			)
			count += 1
	_wall_cutout_material.set_shader_parameter("unit_screen_positions", screen_positions)
	_wall_cutout_material.set_shader_parameter("unit_depths", depths)
	_wall_cutout_material.set_shader_parameter("unit_radii_px", radii)
	_wall_cutout_material.set_shader_parameter("unit_count", count)
	_cutout_log.emit(build_log, screen_positions, count, blocked_by)


## Every rendered unit's own current transform, keyed by unit id — rebuilt each frame from the live
## view array rather than cached, so there is nothing to invalidate and nothing to go stale. Empty
## whenever `wall_cutout_views` is (a spectator load before views exist, or any headless test that
## never builds them), which is what makes the fallback to logical positions total rather than
## partial.
func _display_transforms() -> Dictionary:
	var transforms: Dictionary = {}
	for view: HitVolumeView in wall_cutout_views:
		if view != null and is_instance_valid(view) and view.unit != null:
			transforms[view.unit.id] = view.global_transform
	return transforms


func _process(_delta: float) -> void:
	if _wall_mesh_instances.is_empty() or not show_wall_cutout:
		return
	update_wall_cutout(get_viewport().get_camera_3d() if is_inside_tree() else null)


## The reachable-cell highlight (docs/10 Phase 12.2) — one flat marker per
## cell, replacing whatever reachable highlight was shown before. Never
## touches the ghost-path overlay.
func show_reachable(cells: Array[Vector2i]) -> void:
	_clear(_reachable_overlay)
	for cell: Vector2i in cells:
		_reachable_overlay.add_child(_marker(cell, REACHABLE_COLOR, REACHABLE_HEIGHT))


## One queued MoveAction's path per entry — multiple queued moves must stack
## visibly, so this never collapses them into a single overlay. Never
## touches the reachable-highlight overlay.
##
## docs/10 taskblock03 D2: "waypoints must read as waypoints" — each leg
## gets its own tint and its own polyline (a distinct segment, not one
## merged smear), plus a numbered label at its destination cell showing
## that leg's own MP cost and the running total, so queue order is obvious
## at a glance. `leg_costs` is parallel to `paths` — SelectionController.
## leg_costs() is the one source for the numbers, never re-derived here.
func show_ghost_paths(paths: Array, leg_costs: Array[float] = []) -> void:
	_clear(_ghost_overlay)
	var running_total: float = 0.0
	# `BR30.04`: **one box per cell, solid on the most recent leg and hollow everywhere else** —
	# the supervisor's own reading, *"all boxes except the most recent move's boxes to be hollow."*
	# Waypoints stopped being a separate thing to draw once style followed the leg rather than the
	# position, which is what collapsed this from two passes into one.
	#
	# Styled before anything is drawn because legs are contiguous: leg N+1's first cell IS leg N's
	# waypoint, so one cell belongs to two legs and the later leg has to win. Drawing per leg put a
	# filled square on top of a hollow one and read as "not visually distinct from a full square".
	var style: Dictionary = {}
	for i in range(paths.size()):
		var latest: bool = i == paths.size() - 1
		for cell: Vector2i in paths[i]:
			if latest or not style.has(cell):
				style[cell] = latest
	for cell: Vector2i in style:
		var cell_y: float = GHOST_HEIGHT + _height_for(cell)
		_ghost_overlay.add_child(
			OverlayMarkers.waypoint_box(cell, WAYPOINT_COLOR, cell_y, OVERLAY_SIZE, style[cell])
		)
	for i in range(paths.size()):
		var path: Array = paths[i]
		if path.is_empty():
			continue
		_ghost_overlay.add_child(_leg_line(path, WAYPOINT_COLOR))
		var leg_cost: float = leg_costs[i] if i < leg_costs.size() else 0.0
		running_total += leg_cost
		_ghost_overlay.add_child(
			_waypoint_label(path[path.size() - 1], i + 1, leg_cost, running_total)
		)


## docs/10 taskblock03 F1: "a translucent ghost of the unit where it will
## end up after the queued path — at its final facing." `previewed_unit`'s
## own `.cell`/`.orientation` already ARE that end state (Selection
## Controller.previewed_unit()), so this just renders its boxes, translucent
## and team-tinted, with none of HitVolumeView's marker/wedge/rim — a null
## `previewed_unit` (nothing queued, or nothing selected) just clears it.
func show_unit_ghost(previewed_unit: Unit) -> void:
	_clear(_unit_ghost_overlay)
	if previewed_unit == null:
		return
	var base: Color = WorldPalette.team_color(previewed_unit.squad_id)
	var color := Color(base.r, base.g, base.b, UNIT_GHOST_ALPHA)
	for box: MeshInstance3D in _ghost_boxes(previewed_unit, color):
		_unit_ghost_overlay.add_child(box)


## The per-placement translucent-box construction `show_unit_ghost` uses
## for its own team-colored end-of-move ghost.
static func _ghost_boxes(unit: Unit, color: Color) -> Array[MeshInstance3D]:
	var boxes: Array[MeshInstance3D] = []
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		var instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = placement.box.size
		box_mesh.material = WorldPalette.translucent_material(color)
		instance.mesh = box_mesh
		instance.transform = placement.transform.translated_local(placement.box.center)
		boxes.append(instance)
	return boxes


## taskblock-19 Pass D: "a transparent pie slice... the slice shows
## exactly the cells that would trigger." `cells` is `Overwatch.arc_cells`'
## own output, never re-derived here — a lookalike apex/radius/angle wedge
## can't see LoS/cover the way the real query does, so rendering the
## actual cell set (the same convention `show_reachable` already uses) is
## the only way this can't visually lie about the mechanic. Flagged: once
## heights exist this becomes a cone; this is its flat, 2D projection.
func show_overwatch_arc(cells: Array[Vector2i]) -> void:
	_clear(_overwatch_overlay)
	for cell: Vector2i in cells:
		var instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(OVERLAY_SIZE, 0.02, OVERLAY_SIZE)
		box_mesh.material = WorldPalette.translucent_material(OVERWATCH_ARC_COLOR)
		instance.mesh = box_mesh
		instance.position = Vector3(
			cell.x * UnitGeometry.CELL_SIZE,
			OVERWATCH_ARC_HEIGHT + _height_for(cell),
			cell.y * UnitGeometry.CELL_SIZE
		)
		_overwatch_overlay.add_child(instance)


func clear_overlays() -> void:
	_clear(_reachable_overlay)
	_clear(_ghost_overlay)
	_clear(_overwatch_overlay)
	_clear(_unit_ghost_overlay)


## A distinct polyline through one leg's cells (docs/10 taskblock03 D2) — a
## real segment a human can trace, not just a row of same-looking dots.
func _leg_line(path: Array, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, WorldPalette.overlay_material(color))
	for cell: Vector2i in path:
		mesh.surface_add_vertex(
			Vector3(
				cell.x * UnitGeometry.CELL_SIZE,
				GHOST_HEIGHT + _height_for(cell),
				cell.y * UnitGeometry.CELL_SIZE
			)
		)
	mesh.surface_end()
	instance.mesh = mesh
	return instance


## "1: 2.0 (2.0)" — this leg's own number and MP cost, then the running
## total in parens, at the leg's destination cell.
func _waypoint_label(cell: Vector2i, number: int, leg_cost: float, running_total: float) -> Label3D:
	var label := Label3D.new()
	label.text = "%d: %.1f (%.1f)" % [number, leg_cost, running_total]
	label.font_size = WAYPOINT_FONT_SIZE
	label.modulate = GHOST_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(
		cell.x * UnitGeometry.CELL_SIZE,
		WAYPOINT_LABEL_HEIGHT + _height_for(cell),
		cell.y * UnitGeometry.CELL_SIZE
	)
	return label


## `size` defaults to `OVERLAY_SIZE` — every pre-existing call site (extraction
## cells, wall indicator, field item marker, reachable/ghost overlays) keeps
## its own footprint unchanged; the empty-cell border/fill markers are the
## only callers that pass an explicit one.
## One flat overlay marker on `cell`'s own ground. Construction lives in `OverlayMarkers`; this
## resolves the height, the only part needing the board.
func _marker(
	cell: Vector2i, color: Color, height: float, size: float = OVERLAY_SIZE
) -> MeshInstance3D:
	return OverlayMarkers.flat_box(cell, color, height + _height_for(cell), size)


## `grid` is null whenever a TACTICS overlay method (`show_reachable`/
## `show_ghost_paths`/`show_overwatch_arc`/etc.) runs against a bare
## `BoardView` with no prior `build()` call — an established fixture
## shortcut this file's own test suite already relies on throughout,
## never a real path (a real caller always has a grid by the time any
## overlay could be shown at all). Falls back to ground level 0 rather
## than crashing.
func _height_for(cell: Vector2i) -> float:
	return UnitGeometry.true_height_for_cell(cell, grid) if grid != null else 0.0


func _clear(container: Node3D) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
