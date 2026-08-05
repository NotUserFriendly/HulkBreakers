class_name VisibilityField
extends RefCounted

## The line-of-fire query, inverted: one field computed **from the target**, after
## which each candidate's question is a bit test. `docs/11` has why, and the
## correctness obligation this rests on:
##
## > **Never report "no line" for a cell that actually has one.**
##
## Over-inclusion is safe; under-inclusion is a bug. Three deliberate
## over-inclusions follow, each costing a `ShotPlane` build the field could in
## principle have saved:
##
## 1. **Cover never occludes here.** `Grid.blockers` cover blocks shots but is not
##    opaque (`LoS`: cover never blocks vision). Excluding those cells would be
##    under-inclusion.
## 2. **Units never occlude here.** An ally in the way blocks a shot; the
##    ally-in-line check answers that against the real plane.
## 3. **A cell at a different elevation from the target is always included.**
##    taskblock-58 Pass C: this used to be forced — occlusion data was 2D, `Grid.opacity` being
##    per cell with no per-level component, so a wall "at" a cell said nothing reliable about a
##    shot passing over it from a catwalk. **That limit is gone**; the occluder test is a real
##    3D march now and could answer across bands. It is **kept as a deliberate safety margin**
##    instead, because the line this field casts is eye-to-eye (`LoS.SIGHT_HEIGHT` above each
##    cell's own surface) and the line a shot takes runs muzzle-to-aim-point — and a raised arm
##    or a shot over a low wall is exactly where those two diverge. Narrowing the margin means
##    risking under-inclusion, the one failure mode that matters, to save casts on a build that
##    happens once per target per turn. Retire it when the field and the shot share an origin,
##    not before.
##
## ## Why the volume is indexed in 3D when the occlusion data is 2D
##
## `i = x + y*W + z*W*H` over a `PackedInt64Array`. Today the z axis carries the
## third over-inclusion and nothing else — but multi-level has landed, and a
## per-level structure with a cross-level path bolted on later is the thing that
## gets rewritten. The representation is also load-bearing beyond speed: a packed
## array can be handed to a worker thread where a `CombatState`/`Grid`/`Unit` object
## graph cannot, so this is a prerequisite for later off-thread work rather than an
## alternative to it.

## Bits per word in the `PackedInt64Array` backing store.
const BITS_PER_WORD := 64

var width: int = 0
var rows: int = 0
## How many discrete elevation bands the volume covers. At least 1.
var levels: int = 1
## The band the field was actually computed for — every OTHER band is fully set
## (see over-inclusion 3 above).
var target_level: int = 0

var _bits: PackedInt64Array = PackedInt64Array()
## The elevation band each (x, y) column stands at, derived once at build from
## the cell's own walkable surface. Flat, `x + y*width`.
var _column_level: PackedInt32Array = PackedInt32Array()


## The band a world height falls in. Rounds rather than floors so a surface
## sitting fractionally under a whole level (a ramp's rest offset) reads as the
## level it is effectively part of.
static func level_of_height(height: float) -> int:
	return int(roundf(height / UnitGeometry.LEVEL_HEIGHT))


## Builds the field for a shot originating at `target_cell`.
##
## taskblock-58 Pass C: **the occluder set is whatever the geometry is.** It used to be "opaque
## **and** carrying a blocker the shot plane would resolve against" — two conditions, both
## load-bearing, because `Grid.opacity` was never cleared when a wall was destroyed and would
## otherwise have occluded here while shots passed straight through the hole. That whole
## construction existed to work around the flat array; with the array retired there is no second
## claim to reconcile, and `LoS.has_los` is asked directly. A destroyed wall stops occluding
## because `BodyProjector.projects` says its boxes are gone, in the one place that decides it.
## taskblock-58 Pass C: takes a `Grid`, not a `CombatState`. It only ever read `state.grid`, and
## now that occlusion is geometry the narrower argument is also the truthful one — sight is a
## question about the world, and handing this the unit list would suggest bodies enter into it.
## `spans` lets a caller building **several fields over one grid** derive the geometry once.
## `SightSpans.of` is half the cost of a build (3.7 ms of 7.4 on a 32x24 board) and does not
## depend on the target at all, so a planning turn that builds one field per enemy and one per
## shortlist candidate was re-deriving the same board twenty times. **Owned by the caller for the
## duration of one planning pass** rather than cached on the `Grid`: a cache would have to notice
## a wall losing its last hit point, and a stale span table is a shot through a wall.
static func build(grid: Grid, target_cell: Vector2i, spans: SightSpans = null) -> VisibilityField:
	var field := VisibilityField.new()
	field.width = grid.width
	field.rows = grid.rows
	field._column_level.resize(grid.width * grid.rows)

	# taskblock-58 Pass C: **the heights are kept, not recomputed.** This pass already asks every
	# cell what it stands on in order to band it, and the sight walk below needs the same number
	# to place each cell's eye point — `Surface.first_walkable` is a tag scan per cell, and paying
	# for it twice over a whole board is 768 of them for nothing.
	var heights := PackedFloat32Array()
	heights.resize(grid.width * grid.rows)
	var max_level := 0
	for y in range(grid.rows):
		for x in range(grid.width):
			var height: float = UnitGeometry.true_height_for_cell(Vector2i(x, y), grid)
			heights[x + y * grid.width] = height
			var level: int = level_of_height(height)
			field._column_level[x + y * grid.width] = level
			max_level = maxi(max_level, level)
	field.levels = max_level + 1
	field.target_level = level_of_height(heights[target_cell.x + target_cell.y * grid.width])

	var cell_count: int = grid.width * grid.rows * field.levels
	field._bits.resize((cell_count + BITS_PER_WORD - 1) / BITS_PER_WORD)
	field._bits.fill(0)

	# Every band that is NOT the target's is set wholesale — over-inclusion 3.
	# Done first so the target band's real answers can be written over a clean
	# slate rather than being OR-ed into a partially-set volume.
	for level in range(field.levels):
		if level == field.target_level:
			continue
		for y in range(grid.rows):
			for x in range(grid.width):
				field._set_bit(x, y, level)

	# taskblock-58 Pass C: **built from geometry, once.** This used to walk `Grid.line` reading a
	# flat opacity array. Asking `LoS.has_los` per cell instead — the exact march — was measured
	# at 535 ms per build on a 32x24 board and rejected on the spot; `SightSpans` is the derived
	# structure that keeps the answer geometric at a cost a per-turn build can carry. It is
	# deliberately weaker than the march in the safe direction, which is this field's standing
	# contract rather than a compromise: false is conclusive, true means ask the real resolver.
	var derived: SightSpans = spans if spans != null else SightSpans.of(grid)
	var origin: Vector3 = LoS.sight_point(grid, target_cell)
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var eye := Vector3(
				float(x) * UnitGeometry.CELL_SIZE,
				heights[x + y * grid.width] + LoS.SIGHT_HEIGHT,
				float(y) * UnitGeometry.CELL_SIZE
			)
			if not derived.obstructs(origin, eye, target_cell, cell):
				field._set_bit(x, y, field.target_level)
	return field


## Could a shot between `cell` and the target this field was built for possibly
## be clear? **False is conclusive; true means "ask `ShotPlane`".** Out-of-bounds
## reads true, since a caller handing in a cell off the board is asking a
## question this field has no standing to answer negatively.
##
## **The containment obligation is scoped to cells a unit could stand on**, which
## is every cell any call site can supply: candidates come from
## `Pathfinder.reachable`, which never returns a cell holding a live blocker, plus
## the unit's own cell. Asked about a wall cell *itself*, the field and
## `ShotPlane` genuinely can disagree — `Grid.line`'s supercover picks up the
## neighbouring wall cells along the same wall while the real plane, resolving
## from a position inside that wall, does not. That was found by sweeping every
## cell on a walled board and is recorded rather than papered over; it is
## unreachable in practice, and narrowing the field to match it would be work
## spent on a question nothing asks.
func allows(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= rows:
		return true
	return _get_bit(cell.x, cell.y, _column_level[cell.x + cell.y * width])


## True when no cell in `cells` could possibly have a line — the case the whole
## pass exists for. taskblock-43's branch census found **19 of 60 turns** ending
## with nothing reachable having a shot, and each of those had to build a real
## `ShotPlane` per candidate to discover it. This answers the same question with
## no casts at all.
func allows_none(cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		if allows(cell):
			return false
	return true


func _index(x: int, y: int, level: int) -> int:
	return x + y * width + level * width * rows


func _set_bit(x: int, y: int, level: int) -> void:
	var i: int = _index(x, y, level)
	_bits[i / BITS_PER_WORD] |= 1 << (i % BITS_PER_WORD)


func _get_bit(x: int, y: int, level: int) -> bool:
	if level < 0 or level >= levels:
		return true
	var i: int = _index(x, y, level)
	return (_bits[i / BITS_PER_WORD] & (1 << (i % BITS_PER_WORD))) != 0
