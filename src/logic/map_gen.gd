class_name MapGen
extends RefCounted

## Seeded BSP dungeon generator: recursively splits the map into leaf
## rectangles, carves a room in each leaf, and connects sibling rooms with
## L-shaped corridors as the recursion unwinds — this guarantees every room
## (and therefore both spawn zones) sits in one connected component.
##
## taskblock-39 Pass B: every carving decision below works against a private
## `MapGenScratch`, never `Grid`'s own public API — `_emit` is the ONE
## place the finished scratch becomes real, as `Grid.surfaces` (the
## placement model's real output; Pass D retired the `Grid.terrain`/
## `Grid.level` legacy fields `_emit` used to also populate). See
## `MapGenScratch`'s and `_emit`'s own doc comments for why.

## taskblock-16 Pass C: "too cramped — no room to maneuver or use cover."
## Rooms >= 7 on their min dimension; MIN_CHILD_SIZE keeps a split child
## room-sized (its own `+ 2` for the 1-cell border `_carve_room` always
## leaves); MIN_LEAF_SIZE keeps the same buffer over MIN_CHILD_SIZE the
## old 8-vs-5 pair had (a margin, not a hard requirement — only
## MIN_LEAF_SIZE >= MIN_CHILD_SIZE is load-bearing, for `_split_and_carve`
## to hand both children a valid size).
const MIN_ROOM_SIZE: int = 7
const MIN_CHILD_SIZE: int = MIN_ROOM_SIZE + 2
const MIN_LEAF_SIZE: int = MIN_CHILD_SIZE + 3

## taskblock-16 Pass C: corridors were a single carved cell wide — too
## cramped for movement or cover once rooms are actually spacious. Each
## corridor rolls its own width in this range (seeded), same "obvious
## knob" convention as room sizing.
const CORRIDOR_WIDTH_MIN: int = 3
const CORRIDOR_WIDTH_MAX: int = 5

const COVER_PROBABILITY: float = 0.18
## taskblock-16 Pass B2: the reference humanoid's own torso/head boundary
## (docs/01) — no longer a placement height (the object's own real volume
## IS its height now), kept only as the debug ASCII dump's own full/half
## glyph threshold (`AsciiRender._blocker_height`).
const FULL_COVER_HEIGHT: float = 1.60
## taskblock-16 Pass B1: "all cover objects (old three + new three) are
## field-object part-trees at a cell" — a flagged, uniformly-weighted
## pick among every real cover part this codebase has (never a design
## decision). `barrel_pallet` gets its own extra generation step
## (`_roll_barrels`) once picked — every other id is placed as-is.
const COVER_IDS: Array[StringName] = [
	&"scrap_pile", &"goo_barrel", &"crate", &"pillar", &"forklift", &"barrel_pallet"
]
## "generates with 0-4 goo_barrels on it (seeded)."
const BARREL_PALLET_MAX_BARRELS: int = 4

const SPAWN_ZONE_SIZE: int = 2
## taskblock-37 Pass D: "MapGen authors real levels... ramps are what make
## a raised area generally reachable" (docs/PLAN.md) — a flagged, tunable
## fraction of carved rooms, not a design decision. One raised level only
## (deep towers are a later authoring concern, not this pass's).
const RAISED_ROOM_PROBABILITY: float = 0.35
const RAISED_ROOM_LEVEL: int = 1

## taskblock-53 Pass D: how many repair sweeps `guarantee_navigability` will make. One
## repair can expose another, so a single pass is not enough; a bound stops a pathological
## board hanging generation. **Flagged, not designed** — 6 clears every seed measured, and
## the sweep test is what would notice it being too low.
const NAVIGABILITY_REPAIR_PASSES: int = 6

## tb62 Pass B: what share of the routes-up this generator opens are **mag lifts** rather
## than ladders. **Flagged, not designed** — an even split is the honest placeholder for
## "both should appear", and it is the number to move once there is any evidence about
## which route a bout actually wants. The two are not interchangeable: a ladder costs MP
## and a lift costs AP, so the share decides how often a unit's route up competes with its
## shooting rather than with its walking.
##
## **Only consulted when an RNG is handed in.** `guarantee_navigability` is called by the
## editor and by tests with no RNG at all, and those callers keep stamping ladders exactly
## as they did — a repair that varied by whether its caller happened to have randomness
## would be a repair nobody could reproduce.
const LIFT_SHARE: float = 0.5


## tb60 Pass A: **`step_height` is a parameter, because the invariant this generator owes is
## owed to the shortest unit that will play on the board.** Defaults to
## `Unit.BASE_STEP_HEIGHT` — a generated map made before any roster exists assumes the
## unmodified body — and a caller with real units passes `Unit.lowest_step_height(units)`.
##
## It reaches three places and they must all agree: the stair `_author_levels` builds, the
## reachability floods `_repair_stranded_elevation` and `_ensure_spawns_connected` run, and
## the `guarantee_navigability` sweep that has the last word. A generator that built stairs
## for one step height and checked them against another would certify boards nobody can
## walk.
static func generate(
	map_seed: int, width: int, rows: int, step_height: float = Unit.BASE_STEP_HEIGHT
) -> Grid:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed

	var grid := Grid.new(width, rows)
	var scratch := MapGenScratch.new(width, rows)

	var rooms: Array[Rect2i] = []
	_split_and_carve(grid, scratch, Rect2i(Vector2i.ZERO, Vector2i(width, rows)), rng, rooms)

	# Vector2i -> true, every cell a stair flight runs through. **Cover must not land on a
	# tread**, and until tb60 Pass A that was carried by the tread being a `RAMP` cell kind,
	# which `_scatter_cover` skipped for free. Dissolving the kind dissolved the protection
	# with it, and the measurement is what caught it: raised ground across eight seeds fell
	# from 15.8% of walkable cells to 8.3% purely because scattered cover sealed stairs and
	# `_repair_stranded_elevation` then flattened the rooms behind them. Carrying the set
	# explicitly restores exactly the old guarantee without restoring the enum.
	var stair_cells: Dictionary = {}
	_author_levels(scratch, rooms, rng, step_height, stair_cells)

	_scatter_cover(grid, scratch, rng, stair_cells)

	# taskblock-37 Pass D: repairs AFTER cover scatter, not before — a
	# scattered blocker can land squarely on a raised room's own single
	# ramp APPROACH (the ramp cell itself is never coverable, but the
	# ordinary corridor cell leading into it still can be), sealing off
	# the whole room with no redundant route. Checking before cover exists
	# would miss exactly this failure mode.
	_repair_stranded_elevation(grid, scratch, rooms, step_height)

	var spawn_cells: Array = _place_spawn_zones(grid, scratch, rooms)
	_ensure_spawns_connected(grid, scratch, spawn_cells[0], spawn_cells[1], rng, step_height)

	_finalize_walls_and_empty(grid, scratch)

	_emit(grid, scratch)

	# taskblock-53 Pass D: **the generator owes navigability.** Runs last, on the finished
	# `Grid` rather than on the scratch, because that is where real surfaces, heights and
	# heights live — and it is what `MapNavigability` measures, so the repair and the
	# check cannot disagree about what a legal step is.
	# tb62 Pass B: the RNG reaches the repair so a route up can be a mag lift instead of a
	# ladder. **Drawn here, after everything else** — no earlier draw moves, so every seed
	# still carves the same rooms, raises the same floors and scatters the same cover as it
	# did before lifts existed. What changes is only which fixture stands in a repaired cell.
	guarantee_navigability(grid, step_height, rng)

	return grid


## **`BR46.02`'s fix, as a generation rule.** Descent is free and ascent is
## capability-gated, so every lowered region is a one-way door for a unit with no climbing
## capability — 16 of 40 seeds at real bout size, worst 216 cells. A symmetric connectivity
## check cannot see it: spawn zones stay mutually reachable on 60 of 60 seeds.
##
## Repairs by opening the cheapest edge out of each stranded cell — **which is now always a
## ladder** (tb60 Pass A). A generator rule only; the editor will enforce nothing, because an
## authored map may be broken on purpose.
##
## **The `rise <= RAMP_MAX_RISE gets a ramp` branch is deleted, and the branch was the bug in
## it.** A ramp made a rise free by relabelling one cell, which is a thing no amount of real
## geometry can do: under `step_height` a rise is free when it is short, and a rise this
## function is looking at is by definition one no unit could step. So there is nothing left
## for a one-cell repair to relabel. The two remaining options are a **stair** — which needs
## a run of free cells in some direction and cannot be promised at an arbitrary stranded cell
## — and a **ladder**, which needs one cell and is the capability-free route up by design.
## The repair path takes the one it can always build; `_author_levels` builds stairs where it
## does have the room. One fewer categorical check, and the check that went was the one that
## could not have been honest.
##
## **Iterates, because one repair can expose another.** Opening a pit's edge can reveal a
## deeper shelf inside it that was never reachable to begin with. Bounded rather than
## looped-until-stable so a pathological board cannot hang generation; the remaining cells
## are left rather than forced, and the sweep test is what would notice a bound set too low.
static func guarantee_navigability(
	grid: Grid, step_height: float = Unit.BASE_STEP_HEIGHT, rng: RandomNumberGenerator = null
) -> void:
	for _attempt: int in range(NAVIGABILITY_REPAIR_PASSES):
		var stranded: Array[Vector2i] = MapNavigability.stranding_cells(grid, step_height)
		if stranded.is_empty():
			return
		var opened := 0
		for cell: Vector2i in stranded:
			if _open_a_route_out(grid, cell, rng):
				opened += 1
		# Nothing left that this rule knows how to fix. Stopping is honest; looping would
		# spin.
		if opened == 0:
			return


## Opens one upward edge out of `cell`, or false if it could not. Sized to the LOWEST
## neighbour above `cell` — the smallest rise is the cheapest thing to build, and on a
## terraced board it is also the one most likely to be reachable itself.
##
## tb60 Pass A: **the chosen neighbour's identity stopped mattering, only its height.** A
## ramp had to face the cell it served, so the old code carried `best_neighbour` to compute a
## direction from — and getting that direction from an 8-way neighbour list while the other
## stamping path used 4 is exactly what `BR56.01` was. A ladder is vertical and faces
## nothing, so the whole question is gone rather than answered.
## tb62 Pass B: **a mag lift is the other thing this can stamp**, and it is the same slot
## doing the same job in a different currency. The chosen neighbour's identity started
## mattering again for exactly one reason — a lift is a *pair*, so the upper pad has to go
## somewhere, and that somewhere is the cell whose rise the route was sized to.
static func _open_a_route_out(
	grid: Grid, cell: Vector2i, rng: RandomNumberGenerator = null
) -> bool:
	var here: float = UnitGeometry.true_height_for_cell(cell, grid)
	var best_rise: float = INF
	var best_neighbour: Variant = null
	for neighbour: Vector2i in grid.neighbors(cell):
		if grid.blockers.has(neighbour):
			continue
		if Surface.first_walkable(grid.surfaces_at(neighbour)) == null:
			continue
		var rise: float = UnitGeometry.true_height_for_cell(neighbour, grid) - here
		if rise <= 0.001 or rise >= best_rise:
			continue
		best_rise = rise
		best_neighbour = neighbour
	if is_inf(best_rise):
		return false
	if rng != null and rng.randf() < LIFT_SHARE:
		if _stamp_mag_lift(grid, cell, best_neighbour as Vector2i, here, here + best_rise):
			return true
		# A lift the attachment grammar refused is not a reason to leave the cell stranded —
		# fall through to the ladder, which is the route that needs one cell and no partner.
	return _stamp_ladder(grid, cell, here, best_rise)


## Stands enough ladder segments at `cell` to reach `rise` above it. Placed through
## `GridPlacement` rather than written straight into `Grid.surfaces`, so the generator is
## held to the same attachment grammar an author would be — a ladder the grammar refuses is a
## ladder that should not exist, and finding that out here is the point of having a grammar.
static func _stamp_ladder(grid: Grid, cell: Vector2i, height: float, rise: float) -> bool:
	var segments: int = int(ceil(rise / Surface.LADDER_SEGMENT_RISE))
	var placed := 0
	for i: int in range(segments):
		var at: float = height + float(i) * Surface.LADDER_SEGMENT_RISE
		if GridPlacement.place(grid, cell, DataLibrary.get_part(&"ladder"), at) != null:
			placed += 1
	return placed > 0


## tb62 Pass B: **stands a mag lift pair — the low pad and the pad it delivers to.**
##
## Placed through `GridPlacement` for the same reason the ladder is: the generator is held
## to the attachment grammar an author would be, so a lift the grammar refuses is a lift
## that should not exist. Both ends go through it, which is what makes the pair either
## whole or absent.
##
## **All or nothing, checked before anything is written.** A lower pad with no upper pad is
## a route that visibly promises a way up and has none — worse than no route at all, which
## is exactly why `_stair_run_fits` checks a whole stair run before stamping a tread. Both
## ends are cleared through `GridPlacement.can_place` first, so there is no half-lift to
## unwind and the caller can fall back to a ladder cleanly.
##
## **A duplicate per pad**, unlike `_stamp_ladder`'s shared template: a side attachment
## really occupies its host's socket (`PartGraph.attach`), so two pads that are the same
## object would be one part claiming two sockets.
##
## ## Why it refuses to build near another lift
##
## `Surface.mag_lift_destination` DERIVES the pair from the board rather than storing it, so
## a lift is only well-defined where the derivation has one possible answer. The repair sweep
## fixes many stranded cells and readily stamps two lifts a cell or two apart — measured on
## seeds 5, 9 and 4242, where pads cross-linked into chains and one cell ended up holding two
## pads from two different passes.
##
## **The fix is at placement, not in the derivation.** A cleverer tie-break would have
## returned one answer out of an ambiguous board, which is guessing with extra steps; a lift
## whose pairing is unambiguous *by construction* cannot be got wrong later. Same posture as
## `_stair_run_fits`: establish the whole fixture is buildable before writing any of it, and
## let the caller fall back to a ladder — which needs one cell and no partner, and is exactly
## the right answer in a crowded spot.
static func _stamp_mag_lift(
	grid: Grid, cell: Vector2i, landing: Vector2i, height: float, landing_height: float
) -> bool:
	var pad: Part = DataLibrary.get_part(&"mag_lift_pad")
	if pad == null:
		return false
	if _pad_in_reach_of(grid, cell) or _pad_in_reach_of(grid, landing):
		return false
	var lower: Part = pad.duplicate(true)
	var upper: Part = pad.duplicate(true)
	if not GridPlacement.can_place(grid, cell, lower, height):
		return false
	if not GridPlacement.can_place(grid, landing, upper, landing_height):
		return false
	return (
		GridPlacement.place(grid, landing, upper, landing_height) != null
		and GridPlacement.place(grid, cell, lower, height) != null
	)


## True if `cell` or any neighbour of it already carries a mag lift pad — i.e. if a pad
## placed here would be within reach of a pairing that is not its own. The cell itself is
## included because two repair passes can otherwise stack pads on one cell, which is the
## same ambiguity with a zero displacement.
static func _pad_in_reach_of(grid: Grid, cell: Vector2i) -> bool:
	if Surface.has_mag_lift_at(grid, cell):
		return true
	for neighbour: Vector2i in grid.neighbors(cell):
		if Surface.has_mag_lift_at(grid, neighbour):
			return true
	return false


static func _split_and_carve(
	grid: Grid,
	scratch: MapGenScratch,
	rect: Rect2i,
	rng: RandomNumberGenerator,
	rooms: Array[Rect2i]
) -> Vector2i:
	var can_split_x: bool = rect.size.x >= MIN_LEAF_SIZE * 2
	var can_split_y: bool = rect.size.y >= MIN_LEAF_SIZE * 2

	if not can_split_x and not can_split_y:
		return _carve_room(grid, scratch, rect, rng, rooms)

	var split_x: bool
	if can_split_x and can_split_y:
		split_x = rng.randf() < 0.5
	else:
		split_x = can_split_x

	var child_a: Rect2i
	var child_b: Rect2i
	if split_x:
		@warning_ignore("integer_division")
		var lo: int = maxi(MIN_CHILD_SIZE, rect.size.x / 3)
		@warning_ignore("integer_division")
		var hi: int = mini(rect.size.x - MIN_CHILD_SIZE, rect.size.x * 2 / 3)
		if hi < lo:
			hi = lo
		var offset: int = rng.randi_range(lo, hi)
		var split_at: int = rect.position.x + offset
		child_a = Rect2i(rect.position, Vector2i(offset, rect.size.y))
		child_b = Rect2i(
			Vector2i(split_at, rect.position.y), Vector2i(rect.size.x - offset, rect.size.y)
		)
	else:
		@warning_ignore("integer_division")
		var lo_y: int = maxi(MIN_CHILD_SIZE, rect.size.y / 3)
		@warning_ignore("integer_division")
		var hi_y: int = mini(rect.size.y - MIN_CHILD_SIZE, rect.size.y * 2 / 3)
		if hi_y < lo_y:
			hi_y = lo_y
		var offset_y: int = rng.randi_range(lo_y, hi_y)
		var split_at_y: int = rect.position.y + offset_y
		child_a = Rect2i(rect.position, Vector2i(rect.size.x, offset_y))
		child_b = Rect2i(
			Vector2i(rect.position.x, split_at_y), Vector2i(rect.size.x, rect.size.y - offset_y)
		)

	var point_a: Vector2i = _split_and_carve(grid, scratch, child_a, rng, rooms)
	var point_b: Vector2i = _split_and_carve(grid, scratch, child_b, rng, rooms)
	_carve_corridor(grid, scratch, point_a, point_b, rng)
	return point_a


static func _carve_room(
	grid: Grid,
	scratch: MapGenScratch,
	leaf: Rect2i,
	rng: RandomNumberGenerator,
	rooms: Array[Rect2i]
) -> Vector2i:
	var max_w: int = maxi(MIN_ROOM_SIZE, leaf.size.x - 2)
	var max_h: int = maxi(MIN_ROOM_SIZE, leaf.size.y - 2)
	var room_w: int = mini(rng.randi_range(MIN_ROOM_SIZE, max_w), leaf.size.x - 2)
	var room_h: int = mini(rng.randi_range(MIN_ROOM_SIZE, max_h), leaf.size.y - 2)
	room_w = maxi(room_w, 1)
	room_h = maxi(room_h, 1)

	var max_offset_x: int = maxi(leaf.size.x - 2 - room_w, 0)
	var max_offset_y: int = maxi(leaf.size.y - 2 - room_h, 0)
	var offset_x: int = rng.randi_range(0, max_offset_x)
	var offset_y: int = rng.randi_range(0, max_offset_y)

	var room := Rect2i(
		leaf.position + Vector2i(1 + offset_x, 1 + offset_y), Vector2i(room_w, room_h)
	)

	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			_set_open(grid, scratch, Vector2i(x, y))

	rooms.append(room)
	@warning_ignore("integer_division")
	return room.position + room.size / 2


## taskblock-37 Pass D: raises a seeded subset of the already-carved rooms
## by one level, then guarantees each is generally reachable — "since
## climbing is capability-gated and most units lack it, ramps are what
## make a raised area generally reachable" (docs/PLAN.md). Runs before
## `_scatter_cover` so a scattered blocker never lands on a stair tread —
## the cells it stamps are recorded into `stair_cells` and refused there
## (tb60 Pass A; before that the `RAMP` cell kind did the same job
## implicitly).
## `generate()` runs its own `_repair_stranded_elevation` pass AFTER cover
## scatter too — see that function's own doc comment for why one pass
## right here isn't enough on its own.
static func _author_levels(
	scratch: MapGenScratch,
	rooms: Array[Rect2i],
	rng: RandomNumberGenerator,
	step_height: float,
	stair_cells: Dictionary
) -> void:
	for room: Rect2i in rooms:
		if rng.randf() >= RAISED_ROOM_PROBABILITY:
			continue
		for y in range(room.position.y, room.position.y + room.size.y):
			for x in range(room.position.x, room.position.x + room.size.x):
				scratch.set_level(Vector2i(x, y), RAISED_ROOM_LEVEL)
		_connect_with_a_stair(scratch, room, step_height, stair_cells)


## General safety net, not another hand-chased special case: a raised
## room's single ramp can still leave something stranded in topologies
## `_connect_with_a_ramp` doesn't anticipate — a wide (`CORRIDOR_WIDTH_MIN`-
## `_MAX`) corridor connecting two OTHER rooms happens to cross this one's
## rect and gets raised right along with it, two raised rooms share their
## only real ground-level neighbor and each leaves the other stranded, or
## (the reason `generate()` calls this AFTER `_scatter_cover`, not just
## once right after `_author_levels`) a scattered blocker lands on the
## ordinary corridor cell leading into a room's own single ramp, sealing
## the whole room behind it. Rather than chase every such shape by hand,
## flood from a real anchor point with a non-climbing `Pathfinder` (the
## same posture any unit without `CLIMBER` always has) and flatten any
## `OPEN` cell it can't reach back to level 0 — "ramps couldn't fix it"
## becomes "don't raise it after all," never a silently broken island.
##
## taskblock-38 Pass C: a stranded RAMP cell now needs the same treatment
## as a stranded room interior, not just OPEN cells — the corrected
## two-cell profile authors the cell BORDERING the room at a genuinely
## non-zero level (`RAISED_ROOM_LEVEL - 0.5`), so an orphaned ramp (its
## own room already flattened above, or its OTHER cell cut off by cover)
## would otherwise sit at that half-level forever, an isolated "raised"
## island of one or two cells this pass's own reachability test can
## actually see (tb37's single-cell ramp was always authored at its LOWER
## endpoint, level 0 — the same latent gap existed there too, just never
## observable, since a level-0 cell never read as "raised" to begin with).
## Reverting a stranded ramp fully to plain OPEN ground at level 0 is
## strictly correct: a ramp with nothing reachable on either end isn't a
## ramp, it's just a dead-end cell.
##
## taskblock-39 Pass B: level/terrain reads run entirely in scratch now —
## `MapGenScratch.as_temporary_grid()` gives `Pathfinder` a real (if
## throwaway) `Grid` to flood, never a second, hand-rolled reachability
## walk. `grid.blockers` is passed through explicitly: this runs AFTER
## `_scatter_cover` specifically so a cover object sealing off a raised
## room's approach is caught (this function's own doc comment above), and
## `_base_cost` only sees that at all if the temporary grid actually
## carries the real blockers.
static func _repair_stranded_elevation(
	grid: Grid, scratch: MapGenScratch, rooms: Array[Rect2i], step_height: float
) -> void:
	@warning_ignore("integer_division")
	var anchor: Vector2i = rooms[0].position + rooms[0].size / 2
	var pf := Pathfinder.new(scratch.as_temporary_grid(grid.blockers), false, step_height)
	var reachable: Array[Vector2i] = pf.reachable(anchor, INF)
	var reachable_set: Dictionary = {}
	for cell: Vector2i in reachable:
		reachable_set[cell] = true
	for y in range(scratch.rows):
		for x in range(scratch.width):
			var cell := Vector2i(x, y)
			if reachable_set.has(cell):
				continue
			# taskblock-46 Pass A (BR40.03/BR40.04): **a cell carrying a blocker is
			# unreachable BY CONSTRUCTION** — `Pathfinder._base_cost` returns -1.0 for
			# any cell with a live blocker — so its absence from the flood says nothing
			# about whether it is stranded. Flattening on that answer punched a
			# one-cell pit through every raised floor a crate happened to land on, and
			# for a spawn cell the pit outlived the blocker `_mark_zone` later erased.
			# Deferred to the connectivity question below instead.
			if grid.blockers.has(cell):
				continue
			# tb60 Pass A: **one branch, where there were two.** A stranded stair tread used
			# to need its own `RAMP`-kind clause to be flattened back to plain ground; a
			# tread is an `OPEN` cell at a fractional level now, so flattening it is the
			# same `set_level(cell, 0)` that flattens any other stranded cell. The old
			# clause's own justification — "a ramp with nothing reachable on either end is
			# not a ramp, it is a dead-end cell" — survives as a statement about heights.
			if scratch.get_terrain(cell) == MapGenScratch.CellKind.OPEN:
				scratch.set_level(cell, 0)
	_flatten_stranded_blocker_cells(grid, scratch, reachable_set)


## taskblock-46 Pass A: the second half of the strand repair, for the cells the
## flood cannot answer for.
##
## A blocker's own cell is never in the reachable set, so "is this cell stranded"
## has to be asked of its **surroundings** instead. If anything orthogonally
## adjacent is reachable, the cell is part of connected ground and keeps the level
## its room authored. If nothing adjacent is reachable it really is inside a
## stranded region, and it flattens with that region exactly as before — which is
## what keeps a cover object sinking along with a room that genuinely gets lowered.
##
## **Its own authored level is kept rather than copied from the neighbour.** Copying
## reads better in prose and is wrong at a room boundary: a crate on the edge of a
## raised room sits next to a reachable corridor cell at ground level, and adopting
## that neighbour's level would punch the same hole this pass exists to stop, just
## from the other direction. The flatten exists to repair strandedness and nothing
## else, so a cell that is not stranded should not be touched at all.
static func _flatten_stranded_blocker_cells(
	grid: Grid, scratch: MapGenScratch, reachable_set: Dictionary
) -> void:
	for cell: Vector2i in grid.blockers.keys():
		if _has_reachable_neighbour(scratch, reachable_set, cell):
			continue
		if scratch.get_terrain(cell) == MapGenScratch.CellKind.OPEN:
			scratch.set_level(cell, 0)


## **`Grid.NEIGHBOR_OFFSETS`, deliberately — the same adjacency the flood used.**
## Movement here is 8-way and a diagonal step costs exactly what an orthogonal one
## does, so asking "is anything next to this reachable" with a 4-way answer
## disagrees with the flood that produced `reachable_set`. Written orthogonal-only
## first, it left one crate sunk out of 9279 across the sweep: a cell whose only
## reachable neighbour was diagonal read as stranded and flattened. One cell in
## nine thousand is exactly the density at which a wrong adjacency looks like an
## acceptable rounding error rather than a bug.
static func _has_reachable_neighbour(
	scratch: MapGenScratch, reachable_set: Dictionary, cell: Vector2i
) -> bool:
	for offset: Vector2i in Grid.NEIGHBOR_OFFSETS:
		var neighbour: Vector2i = cell + offset
		if neighbour.x < 0 or neighbour.y < 0:
			continue
		if neighbour.x >= scratch.width or neighbour.y >= scratch.rows:
			continue
		if reachable_set.has(neighbour):
			return true
	return false


## tb60 Pass A: **a run of already-OPEN, genuinely lower cells in a straight line out from
## `room` becomes a STAIR** — ordinary floor tiles at evenly spaced heights, replacing
## taskblock-38's two-cell `RAMP` profile.
##
## **The step count is derived, never authored.** A stair spanning `rise` in steps no taller
## than `step_height` needs `ceil(rise / step_height)` steps, hence that many *minus one*
## intermediate cells — the room's own floor is the top step and the ground outside is the
## bottom one. At the default 0.3 step height a level-1 room takes 4 steps of 0.25 across 3
## cells, where the old ramp took 2 steps of 0.5 across 2. **That is the pass's cost, stated
## plainly: stairs are longer than ramps were, so a ring position that supported a ramp may
## not support a stair, and a room that finds no position anywhere gets flattened by
## `_repair_stranded_elevation` instead.** Deriving rather than hardcoding is what makes that
## a tunable consequence instead of a wall — raise `step_height` and the stairs shorten.
##
## Every cell in the run must be `OPEN` and below `RAISED_ROOM_LEVEL` (the same "a neighbour
## that is actually part of a DIFFERENT already-raised room still reads as plain OPEN"
## reasoning tb37 established). A ring position that cannot support the full depth — a map
## edge, a wall, a corridor shallower than the run — simply is not used.
static func _connect_with_a_stair(
	scratch: MapGenScratch, room: Rect2i, step_height: float, stair_cells: Dictionary = {}
) -> void:
	var rise: float = float(RAISED_ROOM_LEVEL) * UnitGeometry.LEVEL_HEIGHT
	var steps: int = maxi(1, int(ceil(rise / maxf(step_height, 0.001))))
	var treads: int = steps - 1
	for y in range(room.position.y - 1, room.position.y + room.size.y + 1):
		for x in range(room.position.x - 1, room.position.x + room.size.x + 1):
			var inner := Vector2i(x, y)
			var inside_room: bool = (
				x >= room.position.x
				and x < room.position.x + room.size.x
				and y >= room.position.y
				and y < room.position.y + room.size.y
			)
			if inside_room or not scratch.in_bounds(inner):
				continue
			var outward: Variant = _outward_ring_direction(room, inner)
			if outward == null:
				continue  # a diagonal corner cell — no cardinal approach to run a stair along
			if _stair_run_fits(scratch, inner, outward as Vector2i, treads):
				_stamp_stair(scratch, inner, outward as Vector2i, treads, stair_cells)
				return


## Whether `treads` cells running outward from `inner` can all carry a step. Checked in full
## before anything is written, so a partial stair — a run that climbs halfway and stops at a
## wall, which is worse than no stair at all because it reads as a route — cannot be stamped.
static func _stair_run_fits(
	scratch: MapGenScratch, inner: Vector2i, outward: Vector2i, treads: int
) -> bool:
	for i: int in range(treads):
		var cell: Vector2i = inner + outward * i
		if not scratch.in_bounds(cell):
			return false
		if scratch.get_terrain(cell) != MapGenScratch.CellKind.OPEN:
			return false
		if scratch.get_level(cell) >= RAISED_ROOM_LEVEL:
			return false
	return true


## Writes the treads. The cell bordering the room is the highest, each further-out cell one
## step lower, and the ground beyond the last tread is the bottom of the flight — so a run of
## `treads` cells divides the rise into `treads + 1` equal steps.
##
## **No facing is recorded, and nothing needs one.** The old pair-stamper computed an ascent
## direction for `Surface.facing` because a ramp's geometry had an up-slope; a floor tile at a
## height does not. That deleted field is the whole of `BR56.01`.
static func _stamp_stair(
	scratch: MapGenScratch,
	inner: Vector2i,
	outward: Vector2i,
	treads: int,
	stair_cells: Dictionary = {}
) -> void:
	var steps: int = treads + 1
	for i: int in range(treads):
		var cell: Vector2i = inner + outward * i
		scratch.set_level(cell, float(RAISED_ROOM_LEVEL) * float(steps - 1 - i) / float(steps))
		stair_cells[cell] = true
	# **The cell the flight lands on is protected too, not just the treads.** It is ordinary
	# ground at level 0, so nothing about its height marks it — but a blocker there seals the
	# bottom of the stair exactly as surely as one on a tread, and that is the failure mode
	# `_repair_stranded_elevation`'s own header describes.
	stair_cells[inner + outward * treads] = true


## The cardinal direction from `room` through `cell` (a ring cell exactly
## one step outside it), or null for a diagonal corner cell — a stair only
## ever runs along a single N/S/E/W approach, never a corner graft (the
## same orthogonal-only posture `GridPlacement`'s own attachment grammar
## uses).
static func _outward_ring_direction(room: Rect2i, cell: Vector2i) -> Variant:
	var x_inside: bool = cell.x >= room.position.x and cell.x < room.position.x + room.size.x
	var y_inside: bool = cell.y >= room.position.y and cell.y < room.position.y + room.size.y
	if x_inside:
		return Vector2i(0, -1) if cell.y < room.position.y else Vector2i(0, 1)
	if y_inside:
		return Vector2i(-1, 0) if cell.x < room.position.x else Vector2i(1, 0)
	return null


static func _carve_corridor(
	grid: Grid, scratch: MapGenScratch, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator
) -> void:
	var mid: Vector2i = Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	var width: int = rng.randi_range(CORRIDOR_WIDTH_MIN, CORRIDOR_WIDTH_MAX)
	_carve_straight(grid, scratch, a, mid, width)
	_carve_straight(grid, scratch, mid, b, width)


## taskblock-16 Pass C: carves a band `width` cells thick, centered on the
## a->b line, instead of the single-cell line the name still describes —
## widened perpendicular to the direction of travel so a straight run
## reads as one corridor, not `width` parallel ones.
static func _carve_straight(
	grid: Grid, scratch: MapGenScratch, a: Vector2i, b: Vector2i, width: int
) -> void:
	@warning_ignore("integer_division")
	var behind: int = width / 2
	var ahead: int = width - 1 - behind
	if a.x == b.x:
		var y_start: int = mini(a.y, b.y)
		var y_end: int = maxi(a.y, b.y)
		for y in range(y_start, y_end + 1):
			for x in range(a.x - behind, a.x + ahead + 1):
				_set_open(grid, scratch, Vector2i(x, y))
	else:
		var x_start: int = mini(a.x, b.x)
		var x_end: int = maxi(a.x, b.x)
		for x in range(x_start, x_end + 1):
			for y in range(a.y - behind, a.y + ahead + 1):
				_set_open(grid, scratch, Vector2i(x, y))


## taskblock-16 Pass B: also clears any blocker already sitting at `cell`
## — harmless during the main carve (nothing's in `blockers` yet at that
## point), but load-bearing for `_ensure_spawns_connected`'s own forced-
## corridor fallback, which runs AFTER `_scatter_cover`: forcing a cell
## open but leaving a blocker sitting in it would still leave that "fix"
## corridor impassable, defeating the whole safety net.
## taskblock-37 Pass D: also flattens the cell's own level back to 0 — a
## no-op during the normal carve (nothing has been raised yet;
## `_author_levels` runs after `_split_and_carve` finishes), but load-
## bearing for the SAME forced-corridor fallback, which runs AFTER levels
## are authored: forcing a cell open while leaving its level raised would
## leave the "fix" corridor climb-gated at whatever raised room it
## happened to cross, defeating the whole safety net exactly the same way
## an un-cleared blocker would.
##
## taskblock-39 Pass B: terrain/level go to SCRATCH; `opacity`/`blockers`
## stay direct `Grid` writes — both genuinely needed live, during carving
## itself, not just derivable from the finished scratch state at `_emit`
## time (a forced corridor must clear a stray blocker THEN, so
## `_ensure_spawns_connected`'s own reachability check moments later sees
## the cleared result).
static func _set_open(grid: Grid, scratch: MapGenScratch, cell: Vector2i) -> void:
	if not scratch.in_bounds(cell):
		return
	scratch.set_terrain(cell, MapGenScratch.CellKind.OPEN)
	grid.blockers.erase(cell)
	scratch.set_level(cell, 0)


## taskblock-16 Pass B: cover used to be a single synthetic, permanent,
## non-destructible box driving a numeric `cover_value` alongside it —
## the "two-parallel-systems" B2 retired. Every scattered cell now gets a
## REAL field object (`_make_cover`, below): destructible, salvageable,
## lootable exactly like any other Part, already blocking movement
## (`Pathfinder.move_cost`) and projecting into the shot plane
## (`ShotPlane.build` already reads every `grid.blockers` entry) the
## instant it's placed here — no further wiring needed.
static func _scatter_cover(
	grid: Grid, scratch: MapGenScratch, rng: RandomNumberGenerator, stair_cells: Dictionary = {}
) -> void:
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if scratch.get_terrain(cell) != MapGenScratch.CellKind.OPEN:
				continue
			if stair_cells.has(cell):
				continue
			if rng.randf() < COVER_PROBABILITY:
				grid.blockers[cell] = _make_cover(rng)


static func _make_cover(rng: RandomNumberGenerator) -> Part:
	var id: StringName = COVER_IDS[rng.randi() % COVER_IDS.size()]
	var part: Part = DataLibrary.get_part(id)
	if id == &"barrel_pallet":
		_roll_barrels(part, rng)
	return part


## "A barrel_pallet generates with 0-4 goo_barrels on it (seeded)" — each
## real `goo_barrel` attached through `PartGraph.attach` (never
## `Part.contents` — only `sockets` project into the shot plane, so only
## an attached barrel can ever actually be shot and cooked off).
static func _roll_barrels(pallet: Part, rng: RandomNumberGenerator) -> void:
	var count: int = rng.randi_range(0, BARREL_PALLET_MAX_BARRELS)
	for i in range(count):
		var socket: Socket = PartGraph.find_free_socket(pallet, &"BARREL_SLOT")
		if socket == null:
			break
		PartGraph.attach(DataLibrary.get_part(&"goo_barrel"), pallet, socket)


## Picks the two carved rooms whose centers are farthest apart (Chebyshev) and
## tags a small zone in each with SPAWN_A / SPAWN_B. Returns [cell_a, cell_b],
## one representative cell per zone.
##
## `_split_and_carve` only splits a leaf when BOTH its dimensions clear
## `MIN_LEAF_SIZE * 2` — a grid smaller than that (e.g. a 12x10 fixture,
## taskblock-16/17's own single-room regression before both real callers'
## default sizes were fixed) never clears that bar, so it always carves
## exactly one room. When `best_a` and
## `best_b` land on the very same room (single room, or every room tied at
## distance 0), marking SPAWN_B into it the normal way would silently
## overwrite every SPAWN_A cell just written — one squad would spawn
## nowhere in the grid at all, and its caller would have to fall back to a
## coordinate no longer guaranteed to be inside carved-open ground (this was
## a real, reproduced bug: BattleScene's own hardcoded fallback landed a
## unit on a WALL cell for several seeds before this fix). Split into two
## non-overlapping corners of that one room instead.
##
## taskblock-39 Pass B: `SPAWN_A`/`SPAWN_B` are a real-`Grid`-only overlay —
## game markers, not a physical fact scratch needs any notion of (they
## survive Pass D's own retirement for exactly that reason). Written
## directly to `grid.terrain`, never to scratch.
static func _place_spawn_zones(grid: Grid, scratch: MapGenScratch, rooms: Array[Rect2i]) -> Array:
	var best_a: Rect2i = rooms[0]
	var best_b: Rect2i = rooms[1] if rooms.size() > 1 else rooms[0]
	var best_dist: int = -1
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			@warning_ignore("integer_division")
			var center_i: Vector2i = rooms[i].position + rooms[i].size / 2
			@warning_ignore("integer_division")
			var center_j: Vector2i = rooms[j].position + rooms[j].size / 2
			var d: int = Grid.distance_chebyshev(center_i, center_j)
			if d > best_dist:
				best_dist = d
				best_a = rooms[i]
				best_b = rooms[j]

	if best_a == best_b:
		var cell_a: Vector2i = _mark_zone(grid, scratch, best_a, Enums.SpawnMarker.SPAWN_A)
		var cell_b: Vector2i = _mark_zone(
			grid, scratch, _far_corner(best_a), Enums.SpawnMarker.SPAWN_B
		)
		return [cell_a, cell_b]

	var cell_a: Vector2i = _mark_zone(grid, scratch, best_a, Enums.SpawnMarker.SPAWN_A)
	var cell_b: Vector2i = _mark_zone(grid, scratch, best_b, Enums.SpawnMarker.SPAWN_B)
	return [cell_a, cell_b]


## The room's own bottom-right SPAWN_ZONE_SIZE-ish corner, as a room-shaped
## Rect2i `_mark_zone` can mark directly — guaranteed a different position
## than `room.position` itself since MIN_ROOM_SIZE is always bigger than
## a 2x2 zone in at least one axis.
static func _far_corner(room: Rect2i) -> Rect2i:
	var w: int = mini(SPAWN_ZONE_SIZE, room.size.x)
	var h: int = mini(SPAWN_ZONE_SIZE, room.size.y)
	return Rect2i(room.position + room.size - Vector2i(w, h), Vector2i(w, h))


## taskblock-16 Pass B: `_scatter_cover` runs BEFORE spawn zones are
## marked (it only ever sees plain OPEN cells) — a scattered blocker can
## land on a cell that becomes a spawn zone a moment later. Harmless
## while blockers were purely cosmetic, but now that they actually block
## movement (`Pathfinder.move_cost`), a leftover blocker on a spawn cell
## would make it unwalkable, or worse, plant a unit inside real,
## occupied geometry at turn 0. Clearing any blocker here — the one
## place every spawn cell is already visited — keeps spawn zones
## guaranteed clear without a second full-grid pass.
## tb60 follow-up: **and every marked cell shares the anchor's height.**
##
## `BR40.04`'s invariant is that a spawn zone is flat, and until this pass it held by luck
## rather than by construction — nothing here ever looked at a height. The ramp retirement
## changed which rooms stay raised, and at a two-tread stair one seed put a zone across a full
## `LEVEL_HEIGHT` ledge: units spawning on both sides of a step none of them can climb.
## **Measured: zero non-uniform zones before this block, one after, so it was a regression
## introduced here rather than a pre-existing defect surfaced** — which is why it is fixed
## rather than pinned.
##
## **The zone shrinks rather than the terrain flattening.** Reshaping ground under a spawn
## point would be a second, invisible authority on what the board looks like, competing with
## `_author_levels` and `_repair_stranded_elevation`; declining to mark a cell is local and
## says exactly what it means. The anchor is `room.position`, which is the cell this returns,
## so the zone can never shrink to nothing.
## **Read out of `scratch`, not out of the grid, and that is not a style choice.** This runs
## before `_emit`, so `grid.surfaces` is still empty and `UnitGeometry.true_height_for_cell`
## would answer 0.0 for every cell on the board — a filter that silently matches everything.
## The first version of this fix did exactly that and the sweep stayed red, which is the only
## reason it was caught.
##
## **The kept level is the block's MAJORITY, not the corner cell's**, and that correction
## matters more than it looks. Anchoring on `room.position` collapsed one zone from four cells
## to one, because the corner happened to be the single low cell beside a raised shelf — and
## the three cells it discarded were the board's only way onto that shelf, turning a
## spawn-zone defect into a 95-cell unreachable region. **Keeping the majority keeps the zone
## whole and keeps whatever it stood on reachable.** Ties break to the lower level, so the
## choice is deterministic rather than dictionary-order.
static func _mark_zone(grid: Grid, scratch: MapGenScratch, room: Rect2i, marker: int) -> Vector2i:
	var w: int = mini(SPAWN_ZONE_SIZE, room.size.x)
	var h: int = mini(SPAWN_ZONE_SIZE, room.size.y)

	var counts: Dictionary = {}
	for y in range(room.position.y, room.position.y + h):
		for x in range(room.position.x, room.position.x + w):
			var level: float = scratch.get_level(Vector2i(x, y))
			counts[level] = int(counts.get(level, 0)) + 1
	var levels: Array = counts.keys()
	levels.sort()
	var kept: float = levels[0]
	for level: float in levels:
		if int(counts[level]) > int(counts[kept]):
			kept = level

	# The representative cell must be one this actually marked — `_ensure_spawns_connected`
	# floods from it, and a cell outside its own zone would flood from the wrong side of the
	# ledge the zone was just moved off.
	var representative := Vector2i(-1, -1)
	for y in range(room.position.y, room.position.y + h):
		for x in range(room.position.x, room.position.x + w):
			var cell := Vector2i(x, y)
			if not is_equal_approx(scratch.get_level(cell), kept):
				continue
			if representative.x < 0:
				representative = cell
			grid.set_spawn_marker(cell, marker)
			grid.blockers.erase(cell)
	return representative if representative.x >= 0 else room.position


## tb31 Pass C: the settled wall/empty model, replacing BR30.10's
## indestructible-wall-terrain approach. `UNCARVED` is only ever a
## SCRATCH marker while `_split_and_carve` is still carving ("not yet
## carved") — this is the ONE place it gets resolved into its final,
## real form. Run LAST (after `_ensure_spawns_connected`, which can still
## carve UNCARVED cells to OPEN) so this sees the grid's final layout.
##
## An UNCARVED cell with at least one non-UNCARVED neighbor (reachable
## from the playable area) becomes ordinary OPEN ground carrying a
## destructible wall `Part` blocker — the exact `_scatter_cover` shape (a
## real, high-DT field object in `grid.blockers`), just authored on
## `wall.tres` instead of rolled from `COVER_IDS`. Opacity is left at the
## `1.0` the initial full-grid fill already gave it: an INTACT wall must
## still block LoS/tactical-cover checks exactly as it always has — only
## its terrain/blocker REPRESENTATION changes here, not what "wall
## opacity" means. (`LoS` doesn't yet react to a wall's later
## destruction — same known, deliberately out-of-scope gap BR30.10
## already had; flagged in the taskblock report, not solved this pass.)
##
## An UNCARVED cell buried in solid, unreachable rock (no non-UNCARVED
## neighbor) becomes EMPTY instead (taskblock-39 Pass D renamed this from
## the old terrain model's own physical-absence value): non-navigable,
## opacity 0 (nothing to hit — a shot passes
## into it), no Part. It can never be the nearest hit along any real ray
## anyway (whatever wall cell sits between it and the open area resolves
## first) — giving it geometry too would only cost `ShotPlane.build`'s
## own unculled per-shot scan for zero behavior change, the same perf
## reasoning BR30.10 already established for skipping it.
## Two passes, deliberately: classify every UNCARVED cell's exposure
## FIRST, against the grid's own untouched layout, THEN apply every
## mutation in a second pass. A single combined pass (classify-and-mutate
## per cell in one scan order) has a real bug: converting an exposed cell
## to OPEN makes it read as a non-UNCARVED neighbor for whatever UNCARVED
## cell is scanned next, so exposure cascades outward from every real
## opening through however much solid rock the scan order happens to
## reach — walls many cells thick instead of the intended single ring,
## empty space reduced to whatever pocket a run of stale UNCARVED
## neighbors on every side never got swept into. Classifying against a
## frozen snapshot first (nothing mutated yet) is what actually keeps
## this to one cell.
##
## taskblock-39 Pass B: reads/writes scratch's own terrain; `grid.blockers` stays a direct `Grid`
## write, same as everywhere else. taskblock-58 Pass C: the paired `grid.set_opacity` writes went
## with the array — an EMPTY cell is see-through because there is no geometry in it, which is a
## fact about the board rather than a flag the generator has to remember to set.
static func _finalize_walls_and_empty(grid: Grid, scratch: MapGenScratch) -> void:
	var wall_cells: Array[Vector2i] = []
	for y in range(scratch.rows):
		for x in range(scratch.width):
			var cell := Vector2i(x, y)
			if scratch.get_terrain(cell) == MapGenScratch.CellKind.UNCARVED:
				wall_cells.append(cell)

	var exposed_by_cell: Dictionary = {}
	for cell: Vector2i in wall_cells:
		exposed_by_cell[cell] = _is_exposed_wall(scratch, cell)

	for cell: Vector2i in wall_cells:
		if exposed_by_cell[cell]:
			scratch.set_terrain(cell, MapGenScratch.CellKind.OPEN)
			grid.blockers[cell] = DataLibrary.get_part(&"wall")
		else:
			scratch.set_terrain(cell, MapGenScratch.CellKind.EMPTY)


static func _is_exposed_wall(scratch: MapGenScratch, cell: Vector2i) -> bool:
	for offset: Vector2i in Grid.NEIGHBOR_OFFSETS:
		var n: Vector2i = cell + offset
		if scratch.in_bounds(n) and scratch.get_terrain(n) != MapGenScratch.CellKind.UNCARVED:
			return true
	return false


## Safety net: BSP corridor-carving already guarantees connectivity, but if a
## future change ever breaks that invariant, force a direct corridor rather
## than silently shipping an unwinnable map.
##
## taskblock-16 Pass B: this used to spin up its own unseeded
## `RandomNumberGenerator` — harmless while the fallback almost never
## triggered, but movement-blocking cover (`Pathfinder.move_cost` now
## checks `blockers`) trips it far more often, which turned that unseeded
## generator into real, visible non-determinism (`same seed, two calls,
## two different maps`). Reuses the caller's already-seeded `rng` instead.
##
## taskblock-39 Pass B: no more spawn-label snapshot/restore. That dance
## existed only because the OLD `_set_open` wrote directly to `Grid.
## terrain`, so a forced corridor crossing a spawn cell would erase its
## own label. Now that corridor carving touches only SCRATCH (never
## `Grid.terrain` at all), a spawn label `_place_spawn_zones` already
## wrote is structurally untouchable by anything carving does afterward
## — the old workaround is simply unnecessary now, not just simplified.
static func _ensure_spawns_connected(
	grid: Grid,
	scratch: MapGenScratch,
	a: Vector2i,
	b: Vector2i,
	rng: RandomNumberGenerator,
	step_height: float
) -> void:
	var pf := Pathfinder.new(scratch.as_temporary_grid(grid.blockers), false, step_height)
	if pf.astar(a, b).is_empty():
		_carve_corridor(grid, scratch, a, b, rng)


## taskblock-39 Pass D: the ONE place the finished scratch becomes real —
## `Grid.surfaces` (the placement model's real output, `GridPlacement`'s
## attachment grammar validated exactly ONCE against a finished map,
## never fighting a cell carving re-visits). `Grid.terrain`/`Grid.level`,
## the legacy fields this used to also populate for compat, are retired
## outright — every real caller now reads the surface this places
## directly instead. Replaces tb38 Pass C's own `_author_surfaces` — same
## formula, now sourced from scratch instead of `Grid` directly, and this
## pass's own reason for being: carving no longer talks to the attachment
## grammar at all, only this one final sweep does.
##
## `SPAWN_A`/`SPAWN_B` are a real-`Grid`-only overlay (`_place_spawn_
## zones` writes `Grid.spawn_marker` directly, never touching scratch) —
## untouched here; only the surface comes from scratch.
static func _emit(grid: Grid, scratch: MapGenScratch) -> void:
	for y in range(scratch.rows):
		for x in range(scratch.width):
			var cell := Vector2i(x, y)
			if scratch.get_terrain(cell) == MapGenScratch.CellKind.EMPTY:
				continue
			MapGenScratch.place_surface(grid, cell, scratch.get_level(cell))
