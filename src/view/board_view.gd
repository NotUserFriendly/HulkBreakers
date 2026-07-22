class_name BoardView
extends Node3D

## docs/10 Phase 12.1/12.2: the board's own geometry — a flat ground plane
## sized to the grid, plus a box mesh for every blocker (docs/02: cover is
## just a region in the shot plane; here it's just a box sitting on the
## board) — and, separately, the TACTICS overlay (reachable highlight,
## queued-move ghost paths, each its own container so one never rebuilds
## the other, and both can be visible at once). Pure presentation: BoardView
## never mutates Grid, only reads it. Real geometry (ground, blockers) is
## lit (WorldPalette.lit_material); only the transient overlay is unshaded
## (WorldPalette.overlay_material) — docs/10: unshaded same-colour boxes
## have no edges and merge into a blob, which is why real geometry must be
## lit.

## taskblock-23 Pass E2: a render layer the inspect panel's isolate camera
## (taskblock-22 G2, `HitVolumeView.ISOLATE_LAYER`) can ALSO include
## alongside the subject unit's own layer, so a real board tile renders
## under the model instead of it floating in a void — never other units
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
const LEG_COLORS: Array[Color] = [
	Color(0.95, 0.82, 0.25),
	Color(0.35, 0.85, 0.95),
	Color(0.95, 0.45, 0.85),
	Color(0.55, 0.95, 0.45),
]
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
## ladder — see `EXTRACTION_TILE_HEIGHT`'s own comment below for the full
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
## runNotes.md: "Not all of the drawn boards are navigable... If a tile
## isn't navigable, it needs something to show that. Color it Dark Gray and
## draw a cross through it." WALL cells are permanent map geometry, not a
## TACTICS overlay, so these live in `_static` alongside the grid lines, not
## one of the ephemeral overlay containers.
## taskblock-22 Pass A3: "simple colored floor markers now" — its own
## height tier, between the grid lines and the wall indicators, so it never
## z-fights with either (extraction tiles sit on open ground in practice,
## but nothing here assumes that).
##
## taskblock-27 Pass C2: the anchor of ONE ordered ground-overlay height
## ladder, enumerated here after tb26 A3's own facing-wedge fix twice
## missed a DIFFERENT co-planar element in turn (bumping one marker in
## isolation, with no shared ordering, was the actual bug). Center
## heights, not top faces (`_marker()`'s own doc comment) — most rungs are
## 0.02-thick boxes/discs:
##   `EXTRACTION_TILE_HEIGHT` (0.010, this constant)
##   -> `HitVolumeView.TEAM_MARKER_Y` (0.06 — was IDENTICAL to this
##      constant, 0.01, a real unreported co-planar pair found while
##      enumerating this set for the first time)
##   -> `OVERWATCH_ARC_HEIGHT` (0.09, below)
##   -> `HitVolumeView.FACING_WEDGE_Y` (0.17 — 5x taller than every other
##      rung, needs real headroom, not just the next small step)
## A future ground overlay takes the next rung in THIS ladder, not a
## value picked independently.
const EXTRACTION_TILE_HEIGHT := 0.010
const WALL_INDICATOR_COLOR := Color("#3A3A3A")
## runNotes.md follow-up: "fade it to a gray that's just slightly darker
## than the tile gray" — a quiet reference mark, not a bold warning X.
const WALL_CROSS_COLOR := Color("#2A2A2A")
const WALL_INDICATOR_HEIGHT := 0.015
## runNotes.md follow-up: "gray overlay for tiles is drawing overtop the
## cross indicator, put the cross on top." `_marker()` draws a real BoxMesh
## with its own 0.02 Y-thickness, centered on `height` — the indicator
## tile's top FACE therefore sits at WALL_INDICATOR_HEIGHT + 0.01 (0.025),
## above a same-magnitude flat cross at the old 0.02, which is exactly why
## the box was winning the depth test. Clearly above that top face, not
## just above the marker's own center height.
const WALL_CROSS_HEIGHT := 0.03
const WALL_CROSS_WIDTH := 0.06
## tb31 Pass C: "make void tiles black with a dark gray border so they
## read as void" — the same "non-navigable terrain needs a real marker"
## convention `WALL_INDICATOR_COLOR`/`WALL_CROSS_COLOR` above already
## established, just a fill+border instead of a fill+cross (void has
## nothing to cross out — it's not an obstruction, it's the absence of
## anything at all). Slots into the SAME ordered ground-overlay height
## ladder, between the wall indicator (0.015) and the wall cross (0.03) —
## void never coexists with a wall/extraction/team-marker/overwatch cell
## in practice, but the ladder convention is "the next rung," not "pick
## whatever's free."
const VOID_BORDER_COLOR := Color("#3A3A3A")
const VOID_FILL_COLOR := Color("#050505")
const VOID_BORDER_HEIGHT := 0.02
const VOID_FILL_HEIGHT := 0.025
## Border size close to the full cell (a thin dark-gray rim); fill
## smaller still, same relationship `OVERLAY_SIZE` already has to a full
## `CELL_SIZE` cell.
const VOID_BORDER_SIZE := 0.98
const VOID_FILL_SIZE := 0.8
## taskblock-30 follow-up: a loose `Matrix` field item has no `volume` to
## draw real geometry from (unlike a loose Part, rendered via the SAME
## `_spawn_blocker` boxes a cover item uses) — a flat marker, same "ground
## overlay" tier as the rest of this file's height ladder above, between
## `WALL_CROSS_HEIGHT` (0.03) and `HitVolumeView.TEAM_MARKER_Y` (0.06).
## Placeholder color, flagged/tunable like every other marker color here.
const FIELD_ITEM_MARKER_HEIGHT := 0.045
const FIELD_ITEM_MARKER_COLOR := Color(0.75, 0.65, 0.35)

## tb32 Pass A: how many tiles wide the wall-cutout porthole is, before
## being projected to screen pixels at each unit's own depth
## (`WallLegibility.pixel_radius_for_tiles`) — "~2.5 tiles, comfortably
## clears ~three walls" per the taskblock's own starting point. Flagged,
## tunable (CLAUDE.md: never invent a "final" balance number). Because
## it's tiles-at-that-unit's-own-depth, camera zoom scales the resulting
## pixel radius automatically — no separate distance logic. tb32 Pass B
## reuses this unchanged for the friendly-fade occlusion test too (same
## "how close counts as blocking" definition either way).
const OCCLUSION_RADIUS_TILES := 2.5
## The shader's own fixed-size uniform arrays (`wall_cutout.gdshader`'s
## `MAX_UNITS`) — must match exactly; a battle fielding more units than
## this simply stops feeding the excess to the cutout (they'd still be
## visible, just not cut through a wall for).
const WALL_CUTOUT_MAX_UNITS := 32

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
## Dictionary (every existing caller/test) simply draws no tiles at all,
## unchanged.
func build(
	p_grid: Grid, material_table: MaterialTable, team_extraction_cells: Dictionary = {}
) -> void:
	grid = p_grid
	_clear(_static)
	_wall_mesh_instances.clear()
	_wall_cutout_material = null
	_excluded_from_occlusion.clear()

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(grid.width * UnitGeometry.CELL_SIZE, grid.height * UnitGeometry.CELL_SIZE)
	plane.material = WorldPalette.lit_material(WorldPalette.GROUND)
	ground.mesh = plane
	ground.position = Vector3(
		(grid.width - 1) * UnitGeometry.CELL_SIZE * 0.5,
		0.0,
		(grid.height - 1) * UnitGeometry.CELL_SIZE * 0.5
	)
	ground.set_layer_mask_value(FLOOR_LAYER, true)
	_static.add_child(ground)
	var grid_lines: MeshInstance3D = _build_grid_lines(grid)
	grid_lines.set_layer_mask_value(FLOOR_LAYER, true)
	_static.add_child(grid_lines)
	_build_wall_indicators(grid)
	_build_void_indicators(grid)
	_build_extraction_tiles(team_extraction_cells)

	for cell: Vector2i in grid.blockers:
		_spawn_blocker(grid.blockers[cell], cell, material_table)

	for cell: Vector2i in grid.field_items:
		for item: Variant in grid.field_items[cell]:
			_spawn_field_item(item, cell, material_table)


## "Team-coded extraction tiles, drawn in their team's color" — one flat
## marker per tile, `WorldPalette.team_color(squad_id)` same as every other
## team-coded visual already reads (docs/10).
func _build_extraction_tiles(team_extraction_cells: Dictionary) -> void:
	for squad_id: int in team_extraction_cells:
		var color: Color = WorldPalette.team_color(squad_id)
		var cells: Array = team_extraction_cells[squad_id]
		for cell: Vector2i in cells:
			_static.add_child(_marker(cell, color, EXTRACTION_TILE_HEIGHT))


## docs/10 taskblock02 G3 / taskblock03 I: "the ground is a flat green plane
## and you can't tell where the tiles are." A line per cell boundary, just
## above the ground to avoid z-fighting — a reference, not decoration, so it
## stays unshaded and dim rather than lit and bright. Real GRID_LINE_WIDTH-
## wide quads, not 1px GPU line primitives (no shader/LOD trick — just
## actual geometry with a real width, drawn with the same real-width
## convention D2's leg lines / F2's targeting line already use).
func _build_grid_lines(p_grid: Grid) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var cell_size: float = UnitGeometry.CELL_SIZE
	var half: float = cell_size * 0.5
	var half_width: float = GRID_LINE_WIDTH * 0.5
	var min_x: float = -half
	var max_x: float = (p_grid.width - 1) * cell_size + half
	var min_z: float = -half
	var max_z: float = (p_grid.height - 1) * cell_size + half

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, WorldPalette.overlay_material(GRID_LINE_COLOR))
	for x in range(p_grid.width + 1):
		var wx: float = x * cell_size - half
		_add_quad(
			mesh,
			Vector3(wx - half_width, GRID_LINE_HEIGHT, min_z),
			Vector3(wx + half_width, GRID_LINE_HEIGHT, min_z),
			Vector3(wx + half_width, GRID_LINE_HEIGHT, max_z),
			Vector3(wx - half_width, GRID_LINE_HEIGHT, max_z)
		)
	for z in range(p_grid.height + 1):
		var wz: float = z * cell_size - half
		_add_quad(
			mesh,
			Vector3(min_x, GRID_LINE_HEIGHT, wz - half_width),
			Vector3(max_x, GRID_LINE_HEIGHT, wz - half_width),
			Vector3(max_x, GRID_LINE_HEIGHT, wz + half_width),
			Vector3(min_x, GRID_LINE_HEIGHT, wz + half_width)
		)
	mesh.surface_end()

	instance.mesh = mesh
	return instance


## Every non-navigable (WALL) cell gets a flat dark-gray tile plus a cross
## drawn through it, so "this tile can't be walked on" is legible from the
## default tactical camera, not just discoverable by clicking a cell and
## being denied a move.
func _build_wall_indicators(p_grid: Grid) -> void:
	for y in range(p_grid.height):
		for x in range(p_grid.width):
			var cell := Vector2i(x, y)
			if p_grid.get_terrain(cell) == Enums.TerrainType.WALL:
				_static.add_child(_marker(cell, WALL_INDICATOR_COLOR, WALL_INDICATOR_HEIGHT))
				_static.add_child(_wall_cross(cell))


## tb31 Pass C: every VOID cell (the negative-space fill past a wall's
## own ring) gets a black fill inside a dark-gray border — "there's
## nothing here" read at a glance, distinct from a WALL cell's own
## gray-plus-cross ("this is an obstruction"): void isn't an obstruction
## to cross out, it's the absence of anything at all.
func _build_void_indicators(p_grid: Grid) -> void:
	for y in range(p_grid.height):
		for x in range(p_grid.width):
			var cell := Vector2i(x, y)
			if p_grid.get_terrain(cell) == Enums.TerrainType.VOID:
				_static.add_child(
					_marker(cell, VOID_BORDER_COLOR, VOID_BORDER_HEIGHT, VOID_BORDER_SIZE)
				)
				_static.add_child(_marker(cell, VOID_FILL_COLOR, VOID_FILL_HEIGHT, VOID_FILL_SIZE))


func _wall_cross(cell: Vector2i) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var cell_size: float = UnitGeometry.CELL_SIZE
	var half: float = cell_size * 0.5 - GRID_LINE_WIDTH
	var half_width: float = WALL_CROSS_WIDTH * 0.5
	var origin: Vector3 = Vector3(cell.x, WALL_CROSS_HEIGHT, cell.y) * cell_size

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, WorldPalette.overlay_material(WALL_CROSS_COLOR))
	_add_cross_arm(mesh, origin, Vector3(-half, 0.0, -half), Vector3(half, 0.0, half), half_width)
	_add_cross_arm(mesh, origin, Vector3(-half, 0.0, half), Vector3(half, 0.0, -half), half_width)
	mesh.surface_end()

	instance.mesh = mesh
	return instance


## A thick line segment from `origin + from` to `origin + to`, `half_width`
## on either side along the segment's own horizontal perpendicular — the
## same real-geometry-not-1px-line convention `_build_grid_lines` already
## uses, just not axis-aligned.
##
## `overlay_material` culls back faces (StandardMaterial3D's own default),
## so the quad's winding actually matters — `_build_grid_lines`'s own quads
## go CCW in the X-Z plane; `Vector3(dir.z, 0.0, -dir.x)`, not the more
## "obvious" `Vector3(-dir.z, 0.0, dir.x)`, is the perpendicular that keeps
## this quad wound the same way for both diagonal arms (verified by hand:
## the flipped sign reverses the a-b-c-d cycle exactly once, which is what
## flips CW to CCW). Get this backwards and the cross renders — just never
## toward the camera.
static func _add_cross_arm(
	mesh: ImmediateMesh, origin: Vector3, from: Vector3, to: Vector3, half_width: float
) -> void:
	var dir: Vector3 = (to - from).normalized()
	var perp: Vector3 = Vector3(dir.z, 0.0, -dir.x) * half_width
	_add_quad(
		mesh, origin + from + perp, origin + to + perp, origin + to - perp, origin + from - perp
	)


static func _add_quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(d)


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
	var is_wall: bool = part.id == &"wall"
	for placement: BoxPlacement in UnitGeometry.assembly_placements(part, cell):
		var instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = placement.box.size
		if is_wall:
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
			_dropped_transform(cell) * world_transform if dropped else world_transform
		)
		_static.add_child(instance)
		# tb31 Pass C: tracked separately so `_process()` only re-evaluates
		# legibility fading against walls specifically, not every box on
		# the board.
		if is_wall:
			_wall_mesh_instances.append(instance)


static func _dropped_transform(cell: Vector2i) -> Transform3D:
	var pivot: Vector3 = Vector3(cell.x, 0.0, cell.y) * UnitGeometry.CELL_SIZE
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
	if camera != null and is_inside_tree():
		var camera_position: Vector3 = camera.global_position
		var viewport_height: float = float(get_viewport().size.y)
		for unit: Unit in wall_cutout_units:
			if count >= WALL_CUTOUT_MAX_UNITS:
				break
			if unit == null or not is_instance_valid(unit):
				continue
			# A unit that's actually left the board (docs/07 extraction —
			# distinct from ordinary death/shutdown, both of which leave a
			# real body in place) has no cell worth cutting a hole for —
			# `extracted` never clears `.cell`, so an unfiltered feed here
			# cuts a permanent, unit-less hole at wherever it left from.
			if unit.extracted or is_excluded_from_occlusion(unit.id):
				continue
			var position: Vector3 = UnitGeometry.bounding_sphere(unit).center
			# Behind the camera: unproject_position() gives nonsense
			# screen coordinates for a point the camera isn't actually
			# looking at — nothing can be occluded for a unit that isn't
			# even on screen.
			if camera.is_position_behind(position):
				continue
			var depth: float = camera_position.distance_to(position)
			screen_positions[count] = camera.unproject_position(position)
			depths[count] = depth
			radii[count] = WallLegibility.pixel_radius_for_tiles(
				OCCLUSION_RADIUS_TILES, depth, camera.fov, viewport_height
			)
			count += 1
	_wall_cutout_material.set_shader_parameter("unit_screen_positions", screen_positions)
	_wall_cutout_material.set_shader_parameter("unit_depths", depths)
	_wall_cutout_material.set_shader_parameter("unit_radii_px", radii)
	_wall_cutout_material.set_shader_parameter("unit_count", count)


func _process(_delta: float) -> void:
	if _wall_mesh_instances.is_empty():
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
	for i in range(paths.size()):
		var path: Array = paths[i]
		var color: Color = LEG_COLORS[i % LEG_COLORS.size()]
		for cell: Vector2i in path:
			_ghost_overlay.add_child(_marker(cell, color, GHOST_HEIGHT))
		if path.is_empty():
			continue
		_ghost_overlay.add_child(_leg_line(path, color))
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
		instance.position = Vector3(cell.x, OVERWATCH_ARC_HEIGHT, cell.y) * UnitGeometry.CELL_SIZE
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
		mesh.surface_add_vertex(Vector3(cell.x, GHOST_HEIGHT, cell.y) * UnitGeometry.CELL_SIZE)
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
	label.position = Vector3(cell.x, WAYPOINT_LABEL_HEIGHT, cell.y) * UnitGeometry.CELL_SIZE
	return label


## `size` defaults to `OVERLAY_SIZE` — every pre-existing call site (extraction
## tiles, wall indicator, field item marker, reachable/ghost overlays) keeps
## its own footprint unchanged; the void border/fill markers are the only
## callers that pass an explicit one.
func _marker(
	cell: Vector2i, color: Color, height: float, size: float = OVERLAY_SIZE
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(size, 0.02, size)
	box_mesh.material = WorldPalette.overlay_material(color)
	instance.mesh = box_mesh
	instance.position = Vector3(cell.x, height, cell.y) * UnitGeometry.CELL_SIZE
	return instance


func _clear(container: Node3D) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
