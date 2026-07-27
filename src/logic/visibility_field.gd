class_name VisibilityField
extends RefCounted

## taskblock-44 Pass B: the line-of-fire query, inverted.
##
## The planner used to cast from N candidate cells to one target, paying a real
## `ShotPlane.build` per candidate — measured at **271.9ms per repositioning
## turn** (taskblock-43's profile), which is roughly 70% of a planning turn and
## the single largest cost in the AI. This computes one field **from the target**
## instead, after which each candidate's question is a bit test.
##
## **One field per target, reused by every shooter.** That is where the
## asymptotic win is: cost stops scaling with the number of units asking.
##
## ## The correctness obligation, which is the whole design
##
## > **Never report "no line" for a cell that actually has one.**
##
## Over-inclusion is safe; under-inclusion is a bug. `ShotPlane` remains the one
## canonical resolver (`docs/02`, `docs/08`) and this never overrides it — a
## survivor of the field is still confirmed by a real cast. A second visibility
## system permitted to *disagree* with `ShotPlane` would be a two-sources-of-truth
## problem, and it would disagree: different rounding, different partial-cover
## handling, different level transitions. Being a conservative prefilter is a far
## weaker burden than being right, and it is directly testable
## (`test_visibility_field.gd`).
##
## Three deliberate over-inclusions follow from that, each of which costs a
## `ShotPlane` build that the field could in principle have saved:
##
## 1. **Cover never occludes here.** `Grid.blockers` cover blocks shots but is
##    not opaque (`LoS`: "cover never blocks vision"). Excluding those cells
##    would be under-inclusion.
## 2. **Units never occlude here.** An ally in the way blocks a shot;
##    `_ally_in_firing_line` is what answers that, against the real plane.
## 3. **A cell at a different elevation from the target is always included.**
##    Occlusion data in this project is 2D — `Grid.opacity` is per cell, with no
##    per-level component — so a wall "at" a cell says nothing reliable about a
##    shot passing over it from a catwalk. The 2D answer is only sound within the
##    target's own level band.
##
## ## Why the volume is indexed in 3D when the occlusion data is 2D
##
## `i = x + y*W + z*W*H` over a `PackedInt64Array`, per the block's own
## instruction, and it is not decoration. Today the z axis carries the third
## over-inclusion above and nothing else. But multi-level has landed, the game is
## 3D, and a per-level structure with a cross-level path bolted on later is the
## thing that gets rewritten. The representation is also load-bearing beyond
## speed: a packed array is what can be handed to a worker thread safely, where a
## `CombatState`/`Grid`/`Unit` object graph cannot — so this is a prerequisite
## for any later off-thread work rather than an alternative to it.

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
## The occluder set is deliberately the SMALLEST defensible one: a cell occludes
## only when it is opaque **and** carries a blocker the shot plane would actually
## resolve against (`BodyProjector.projects`). Both halves are load-bearing.
## Opacity alone is wrong because `Grid.opacity` is never cleared when a wall is
## destroyed, so a dead wall would occlude here while shots pass straight through
## it — under-inclusion, the one failure mode that matters. A blocker alone is
## wrong because ordinary cover is a blocker and does not stop sight.
static func build(state: CombatState, target_cell: Vector2i) -> VisibilityField:
	var field := VisibilityField.new()
	var grid: Grid = state.grid
	field.width = grid.width
	field.rows = grid.rows
	field._column_level.resize(grid.width * grid.rows)

	var max_level := 0
	for y in range(grid.rows):
		for x in range(grid.width):
			var level: int = level_of_height(
				UnitGeometry.true_height_for_cell(Vector2i(x, y), grid)
			)
			field._column_level[x + y * grid.width] = level
			max_level = maxi(max_level, level)
	field.levels = max_level + 1
	field.target_level = level_of_height(UnitGeometry.true_height_for_cell(target_cell, grid))

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

	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if _line_is_open(grid, target_cell, cell):
				field._set_bit(x, y, field.target_level)
	return field


## The same `Grid.line` supercover walk `LoS.has_los` performs — deliberately the
## same shape, so the corner-blocking rule and the endpoint exemptions match what
## the rest of the codebase already means by "a line between two cells" — with a
## strictly WEAKER occluder test. Weaker is the safe direction: fewer occluders
## means more cells reported visible means over-inclusion.
static func _line_is_open(grid: Grid, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if from_cell == to_cell:
		return true
	var cells: Array[Vector2i] = Grid.line(from_cell, to_cell)
	for i in range(1, cells.size() - 1):
		if _occludes(grid, cells[i]):
			return false
	return true


static func _occludes(grid: Grid, cell: Vector2i) -> bool:
	if grid.get_opacity(cell) < LoS.OPAQUE_THRESHOLD:
		return false
	return BodyProjector.projects(grid.blockers.get(cell))


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
