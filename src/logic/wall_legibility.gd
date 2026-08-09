class_name WallLegibility
extends RefCounted

## tb31 Pass C: "walls must not block the player's read of the action
## behind them." Pure geometry — screen positions/depths in, a fade
## decision out, zero SceneTree dependency (the view layer reads the real
## `Camera3D.unproject_position()`/`global_position` and hands in plain
## `Vector2`/`float`s, never the node itself, so this stays
## headless-testable the way `CameraRig`'s own solver math already is
## elsewhere).
##
## SCREEN-space on purpose, not world-space: the tactical camera sits
## well above and back from the board (`CameraOrbitState.DEFAULT_PITCH`/
## `DEFAULT_ZOOM`), so a straight 3D line from camera to a ground-level
## unit spends almost its whole length far above wall height — "is this
## wall within N world units of that 3D ray" almost never fires in
## practice, regardless of N, for any wall more than a cell or two from
## the unit. Screen-space asks the question a player would actually
## answer by eye instead: does the wall's own projected position sit
## close to the unit's on screen, AND is it nearer to the camera (in
## front of, not behind, the thing it would be hiding)?


## True if a wall projecting to `wall_screen_position` (at `wall_depth`
## from the camera) should fade so a player can still read a focal point
## projecting to `focal_screen_position` (at `focal_depth`).
##
## tb32 Pass A retires the GDScript loop that called this against one
## `focal_unit` at a time (`BoardView.update_wall_legibility`, superseded
## by the per-fragment cutout shader) but Pass B's own friendly-ghost fade
## reuses this exact function unchanged (same screen-space-and-nearer
## test, just "is this friendly within R of, and nearer than, the active
## unit" instead of "is this wall...") — kept here rather than deleted.
static func occludes_on_screen(
	wall_screen_position: Vector2,
	wall_depth: float,
	focal_screen_position: Vector2,
	focal_depth: float,
	screen_radius: float
) -> bool:
	if wall_depth >= focal_depth:
		return false
	return wall_screen_position.distance_to(focal_screen_position) <= screen_radius


## **Does this unit get a cutout at all?** taskblock-61 Pass C1 — the whole per-unit rule, in one
## place a headless test can drive, rather than three conditions accumulated in a `_process` loop.
##
## Three reasons a unit is not worth cutting a wall for, and they are different kinds of reason:
##
## - **It has left the board.** `extracted` never clears `.cell` (docs/07 — extraction is distinct
##   from death, both leave the roster entry behind), so an unfiltered feed cuts a permanent,
##   unit-less hole at wherever it walked off from. `BR32.01`, archived.
## - **It does not take turns.** `BR32.08`, the supervisor's rule: *"if it gets a turn, it gets a
##   cutout, if not, then no cutout."* Dead and shut-down bodies stay in `CombatState.units`
##   forever, so every corpse used to cut its own full-radius hole permanently and a long firefight
##   progressively opened the level up. **A DOWNED unit still cuts** — `is_downed()` is "no matrix
##   docked", orthogonal to both flags, and a downed unit may be one turn from standing back up.
## - **Nothing is in front of it.** `BR32.05` — see `sight_blocked_to_body` below.
##
## The one filter that stays in the view is `BoardView.is_excluded_from_occlusion`, because a
## debug verb having destroyed a unit's own render node is view state and nothing here can know it.
##
## A null `grid` cannot be asked about geometry, so it answers the first two questions and stops
## rather than inventing an answer to the third.
##
## **Stated whole here; the view calls the two halves in cost order.** `BoardView` checks
## `is_cutout_subject` before it builds any geometry, because a `bounding_box` walk on a real
## 48-box shell is the single most expensive thing in the feed and a dead unit must never pay for
## one. Both paths run the same two predicates, so they cannot drift.
static func cuts_for(grid: Grid, camera_position: Vector3, unit: Unit) -> bool:
	if not is_cutout_subject(unit):
		return false
	if grid == null:
		return true
	return sight_blocked_to_body(grid, camera_position, unit.cell, UnitGeometry.bounding_box(unit))


## The two flag questions — the cheap half of `cuts_for`, answerable with no geometry at all.
static func is_cutout_subject(unit: Unit) -> bool:
	return not unit.extracted and CombatState.can_take_a_turn(unit)


## **Is anything actually in the way?** taskblock-61 Pass C1, `BR32.05`.
##
## The supervisor's own inversion of the problem: *"if a wall is detected between the camera and
## the unit, then continue doing what we're doing already, and if no wall is detected, then
## disable the cutout for that unit."* One gate in front of the existing screen-space heuristic
## rather than a fourth attempt to tune the heuristic itself — and the heuristic has been "fixed"
## three times already (`BR31.03`, `BR32.01`, `BR32.02`, all archived against this same path).
##
## **What this deletes:** `wall_cutout.gdshader`'s own header records the symptom still open since
## tb32 — *"with the camera and unit on the SAME side of a wall (nothing should occlude at all),
## the cutout still fires and over-cuts neighboring wall segments."* A unit with nothing between it
## and the camera is no longer fed to the shader at all, so there is nothing for that over-cut to
## happen to.
##
## **What this does NOT delete, stated so nobody reads more into it:** once *one* wall genuinely
## occludes a unit, that unit is fed exactly as before and the screen-space test still decides
## per fragment — so a second wall near it, nearer the camera, can still take a bite. That is the
## residual half of `BR32.05` (its *"a chunk is cut out of the top of a wall behind them"*), and it
## wants the per-wall-cell version, not this one.
##
## **A real 3D question, asked of the real geometry.** This class's own header explains why the
## *radius* is screen-space and that reasoning is untouched — but "is a wall in the way" was never
## the question a screen radius could answer, and `RayCaster.obstructed` has been the one march
## that answers it since taskblock-52. Note it walks blockers, placed surfaces and field items but
## **not units** (`LoS`'s own rule: a body in the way is a shot-resolution concern), so a unit can
## never read as blocking sight to itself.
##
## **Biased toward keeping the cutout.** Three points, not one, and *any* of them blocked keeps the
## hole: a false "nothing is occluding" switches the cutout off exactly when it is needed, which is
## worse than leaving one on. A single centre ray misses a wall that hides only the legs.
##
## **Blockers only, and that is a correctness choice before it is a cost one.** Only walls carry
## the cutout material (`BoardView`'s own `part.id == &"wall"`), so a unit hidden by a catwalk
## overhead is not something cutting a wall can help with — keeping the cutout alive for it would
## put the hole back exactly where `BR32.05` complains about it. Non-wall blockers (cover) still
## count, deliberately: the safe direction is keeping a cutout, and reading `&"wall"` here would
## put the view's own content decision in the logic layer.
##
## **Over the ray's own supercover cells, not over every blocker on the board.** This runs on a
## `_process` path and the first version of it did not: walking `grid.blockers` cost 629 usec per
## unit, over 10 ms a frame for a full roster. `Grid.line` is the same supercover walk `LoS` used
## before geometry replaced the opacity array, used here as a candidate filter in front of the
## real box test rather than as an answer in its own right.
##
## **Takes the body's box rather than the unit**, so the caller's own `bounding_box` walk is the
## only one — see `UnitGeometry.bounding_box` for what the second walk was costing. The three rays
## share that one supercover walk too (`RayCaster.blocker_obstructed_among`), because the per-cell
## lookup and the `assembly_placements` allocation are most of the cost, not the arithmetic.
##
## **The cost history, because the first two numbers here were both wrong.** Measured end-to-end
## in `test_cutout_feed_cost_probe.gd` over a 16-unit roster on a real board, as usec per frame of
## `BoardView.update_wall_cutout`: **3 020 before this gate existed** -> **5 281** shipped ->
## **4 796** with the duplicate body walk removed -> **3 613** with the supercover walk shared.
## The isolated gate probe said 41 usec per unit and was measuring a one-box torso fixture; a real
## shell is 48 boxes. **A component measured headlessly is not the system**, which is why the
## end-to-end probe exists alongside the unit one.
static func sight_blocked_to_body(
	grid: Grid, camera_position: Vector3, cell: Vector2i, box: AABB
) -> bool:
	var exclude: Array[Part] = grid.parts_at(cell)
	var camera_cell := Vector2i(roundi(camera_position.x), roundi(camera_position.z))
	var cells: Array[Vector2i] = Grid.line(camera_cell, cell)
	return RayCaster.blocker_obstructed_among(
		grid, cells, camera_position, body_sight_points(box), exclude
	)


## The points on `unit`'s own body the cutout's sight test casts to: its real world-space AABB
## centre, and the centres of that box's top and bottom faces. Read off the actual placements
## rather than sized by a constant — a tall shell and a downed one are different heights and
## nothing here should have an opinion about which.
##
## The unit's own cell's parts are excluded by the caller, so the bottom point sitting exactly on
## the floor it stands on is not a self-block — the same endpoint exemption `LoS` states as *"a
## floor that blinded whoever stood on it would be a spectacular way to fail this pass."*
##
## A shell with no geometry at all (`unit.shell.root == null`, or a root authoring no `volume` —
## the board state `BR51.01`'s loud miss caught two fixtures building) reports a zero-size box at
## its own origin, so all three points collapse onto that one honest position rather than being
## special-cased into a shorter list.
static func body_sight_points(box: AABB) -> Array[Vector3]:
	var center: Vector3 = box.get_center()
	return [
		center,
		Vector3(center.x, box.position.y, center.z),
		Vector3(center.x, box.end.y, center.z),
	]


## tb32 Pass A: how many screen pixels a `cells`-wide circle spans at
## `depth` from the camera — pure trig mirroring `Camera3D`'s own
## perspective projection, so the wall-cutout shader's per-unit radius
## (fed as a uniform every frame, `BoardView.update_wall_cutout`) can be
## computed and unit-tested without a real camera node; the shader itself
## only does the per-fragment discard.
##
## `fov_deg` is `Camera3D.fov`, which this project's own camera treats as
## VERTICAL fov (`CameraOrbitState.CAMERA_FOV_DEG`'s own doc comment) — so
## `viewport_height_px` is the matching dimension, not width. Because the
## radius is cells-at-THAT-unit's-own-depth, zoom falls out for free: zoom
## out (greater depth for the same cell count) shrinks the pixel radius
## automatically, no separate distance logic needed.
static func pixel_radius_for_cells(
	cells: float, depth: float, fov_deg: float, viewport_height_px: float
) -> float:
	if depth <= 0.0:
		return 0.0
	var world_radius: float = cells * UnitGeometry.CELL_SIZE
	return world_radius / (2.0 * depth * tan(deg_to_rad(fov_deg) * 0.5)) * viewport_height_px
