class_name SelectionTarget
extends RefCounted

## taskblock-51 Pass K: **what is selected, when it is not necessarily a unit.**
##
## `SelectionController` held one slot — `selected_unit: Unit` — and that single missing type
## is the whole of Pass K. `PartPicker.hit` already scans `grid.blockers` and
## `grid.field_items` on every hover, so the picker has always *seen* barrels, cover, walls
## and loose field items; selection simply had nowhere to put them. Every symptom the
## supervisor reported is that one gap from a different direction:
##
## - selecting a barrel or any cover appeared to select the cell beneath it
## - `set_part_hp` could not be given a part that is not on a unit (`BR51.02`)
## - selecting a bare cell or cover dimmed the screen for something nothing could describe
## - `Inspect` stayed enabled with nothing selectable selected (`BR51.10`)
##
## ## This is the hit dict, not a second shape
##
## `board_clicked` already emits `{kind, unit, part, cell}` and `TacticsController._cell_at`
## already builds it from `PartPicker`. **This wraps that same dict rather than introducing a
## parallel vocabulary** — `from_hit()` is the only constructor a click path should use, and
## `to_hit()` hands the identical dict back for the debug panel, which speaks it already.
## Inventing a second target shape here would be the "no parallel systems" bug, not the fix.
##
## ## Declining is explicit
##
## Half the reported symptoms are things silently doing nothing. So this type answers
## `can_inspect()` and `describe()` for every kind it can be, and callers that cannot handle a
## kind are expected to **say so** — a disabled button, a logged refusal — rather than
## no-opping and reading as broken.

## Nothing is selected. A distinct object rather than `null` so callers can ask it questions
## without every call site guarding first — `SelectionTarget.none().can_inspect()` is false,
## which is exactly what an empty selection should answer.
static var _none: SelectionTarget = null

var kind: Enums.HitKind = Enums.HitKind.CELL
## Set only when `kind == UNIT`.
var unit: Unit = null
## Set when `kind == PART` — a blocker, a wall, a downed shell, or a loose field item.
var part: Part = null
## **Always populated**, for every kind — same contract `AimTarget` keeps, and what lets a
## queued action carry a cell no matter what was clicked (docs/09).
var cell: Vector2i = Vector2i.ZERO
## True only for the empty selection.
var empty: bool = false
## taskblock-58 Pass A: **the world normal of the face the pick ray struck**, or `null` when the
## pick did not strike a face at all — a bare cell picked off the ground plane, or the empty
## selection. `null` rather than `Vector3.ZERO` deliberately: a zero vector survives every
## direction test a caller might run on it and comes back with a plausible-looking answer, so the
## absence has to be a value that cannot be mistaken for a face.
##
## This is `PartPicker.hit`'s own reported normal carried through unchanged. **The editor's
## place-on-a-face tools read it rather than casting their own ray**, which is the whole reason
## Pass A precedes them: a second ray test would be a second answer to "which face did I click".
var normal: Variant = null


static func none() -> SelectionTarget:
	if _none == null:
		_none = SelectionTarget.new()
		_none.empty = true
	return _none


static func for_unit(p_unit: Unit) -> SelectionTarget:
	var target := SelectionTarget.new()
	target.kind = Enums.HitKind.UNIT
	target.unit = p_unit
	target.cell = p_unit.cell
	return target


static func for_part(p_part: Part, p_cell: Vector2i) -> SelectionTarget:
	var target := SelectionTarget.new()
	target.kind = Enums.HitKind.PART
	target.part = p_part
	target.cell = p_cell
	return target


## **A dead unit is selectable, but not as a unit** — the supervisor's decision, taskblock-51:
## *"Dead units should not be selectable as units. They should be selectable in the same way
## parts on the ground or cover is."*
##
## That is the right shape and it is why Pass K came first: a wreck is a thing on the board
## with parts on it, which is exactly what a `PART` target already describes. Nothing
## downstream needs a fourth kind, and nothing can accidentally queue an action against a
## corpse, because only a `UNIT` target can be commanded.
##
## Returns `none()` for a unit with no shell root — there is no wreck to select.
static func for_wreck(p_unit: Unit) -> SelectionTarget:
	if p_unit == null or p_unit.shell == null or p_unit.shell.root == null:
		return none()
	return for_part(p_unit.shell.root, p_unit.cell)


static func for_cell(p_cell: Vector2i) -> SelectionTarget:
	var target := SelectionTarget.new()
	target.kind = Enums.HitKind.CELL
	target.cell = p_cell
	return target


## The one constructor a click path should use — `board_clicked`'s own dict, unchanged.
## An empty dict is a click that hit nothing at all, which is `none()`, not a cell.
static func from_hit(hit: Dictionary) -> SelectionTarget:
	if hit.is_empty():
		return none()
	var target: SelectionTarget = _classify_hit(hit)
	return _with_normal(target, hit)


static func _classify_hit(hit: Dictionary) -> SelectionTarget:
	match hit.get("kind"):
		Enums.HitKind.UNIT:
			var hit_unit: Unit = hit.get("unit")
			if hit_unit == null:
				return none()
			# A corpse resolves to its wreck, not to a unit — see `for_wreck`.
			return for_unit(hit_unit) if hit_unit.alive else for_wreck(hit_unit)
		Enums.HitKind.PART:
			var hit_part: Part = hit.get("part")
			if hit_part == null:
				return none()
			return for_part(hit_part, hit.get("cell", Vector2i.ZERO))
		_:
			return for_cell(hit.get("cell", Vector2i.ZERO))


## taskblock-58 Pass A: attaches the struck face to a freshly built target.
##
## **`none()` is a shared singleton**, so it is never written to — writing a normal onto it would
## make the empty selection carry whatever the last miss happened to be adjacent to, permanently
## and for every caller. A `CELL` target is left alone too: a cell picked off the ground plane was
## not resolved against a face, and `BoardPicker.cell_at_ray` does not report one.
static func _with_normal(target: SelectionTarget, source: Dictionary) -> SelectionTarget:
	if target.empty or target.is_cell():
		return target
	var struck: Variant = source.get("normal")
	if struck is Vector3 and not (struck as Vector3).is_zero_approx():
		target.normal = struck
	return target


## **`PartPicker.hit`'s own raw shape**, which is `{unit, part, cell, t}` and carries **no
## `kind`** — that key is added downstream by `TacticsController._cell_at`. Routing a raw pick
## through `from_hit()` silently classified every hit as a bare cell, because the `kind`
## lookup returned null and fell to the default arm. Two dict shapes with the same keys minus
## one is exactly the trap `CsvLine` was written for, so each shape gets its own named door.
static func from_pick(pick: Dictionary) -> SelectionTarget:
	if pick.is_empty():
		return none()
	return _with_normal(_classify_pick(pick), pick)


static func _classify_pick(pick: Dictionary) -> SelectionTarget:
	var picked_unit: Unit = pick.get("unit")
	if picked_unit != null:
		return for_unit(picked_unit) if picked_unit.alive else for_wreck(picked_unit)
	var picked_part: Part = pick.get("part")
	if picked_part == null:
		return none()
	return for_part(picked_part, pick.get("cell", Vector2i.ZERO))


## The same dict back, so the debug panel's active-target path takes this without learning a
## new vocabulary.
##
## taskblock-58 Pass A: **`normal` is only present when there is one.** `to_hit()` feeds
## `from_hit()` across the `board_clicked` signal, so emitting the key unconditionally would put a
## `null` normal into a dict that `_with_normal` then correctly ignores — same outcome, but it
## would read as "this pick reported no face" when the truth is "this kind never has one".
func to_hit() -> Dictionary:
	var hit := {"kind": kind, "unit": unit, "part": part, "cell": cell}
	if normal != null:
		hit["normal"] = normal
	return hit


func is_unit() -> bool:
	return not empty and kind == Enums.HitKind.UNIT and unit != null


func is_part() -> bool:
	return not empty and kind == Enums.HitKind.PART and part != null


func is_cell() -> bool:
	return not empty and kind == Enums.HitKind.CELL


## **Whether there is anything for the inspect panel to show.** `BR51.10`: the control was
## live whenever something had been clicked, rather than when the thing clicked has a body to
## describe — so pressing it correctly did nothing and read as broken.
##
## A bare cell has no parts, so it answers false. A unit and a loose part both have a real
## assembly tree behind them and answer true.
func can_inspect() -> bool:
	return is_unit() or is_part()


## Human-readable, for a status line or a refusal message. **Never "Cell" for a barrel** — the
## debug panel used to call every non-unit hit a cell, which is how the supervisor ended up
## being told they had selected the floor.
func describe() -> String:
	if empty:
		return "nothing"
	if is_unit():
		return "unit %d at %s" % [unit.id, cell]
	if is_part():
		return "%s at %s" % [part.id, cell]
	return "cell %s" % cell


## Two targets pointing at the same thing. Identity on the object, not the cell — two props
## can share a cell with a unit standing on it.
func same_as(other: SelectionTarget) -> bool:
	if other == null:
		return false
	if empty or other.empty:
		return empty and other.empty
	if kind != other.kind:
		return false
	match kind:
		Enums.HitKind.UNIT:
			return unit == other.unit
		Enums.HitKind.PART:
			return part == other.part and cell == other.cell
		_:
			return cell == other.cell
