class_name PlanPacer
extends RefCounted

## taskblock-44 Pass D: what lets a unit's turn be *watched* instead of endured.
##
## A player who can pan, click and inspect while a label reads "Unit 2 is
## thinking…" is playing a game that is working. A player staring at a frozen
## frame is playing one that has crashed. **Those can be the same number of
## milliseconds** — the difference is entirely whether the main thread is free.
##
## taskblock-42 Pass D already yields *between* `BoutRunner.step()` calls, and
## that is not enough: one step is the entire think, so the freeze it was meant
## to cure is exactly as long as it ever was. The yield has to happen **inside**
## one unit's plan, which is what this drives.
##
## ## Why this is a stored `Signal` and not a `Node`
##
## The planner is logic (CLAUDE.md: zero SceneTree dependency, headlessly
## testable). It awaits `frame_signal`, a plain `Signal` value the view fills in
## with `get_tree().process_frame`. Logic never learns what a tree is; the view
## supplies the only thing that knows. Headless callers leave it null, nothing
## ever suspends, and the planner runs exactly as it did before this existed.
##
## ## The budget is not optional decoration
##
## **A visible "thinking" state that never ends is WORSE than a freeze**, because
## the player waits longer before concluding something is wrong. So the label is
## only honest if something guarantees the turn ends: past `budget_msec` the
## pacer reports `should_abort()`, the candidate loop stops where it is, and the
## unit acts on the best cell it had found so far. The full escape hatch is
## `PLAN.md`'s *Panic* item and is not this block's job — this is the hard stop
## that makes the promise keepable in the meantime.
##
## **Aborting is safe by construction**: `_pick_engagement_position` seeds its
## incumbent with the unit's own cell and only ever replaces it on a strict
## improvement, so stopping early yields the best cell found so far, which is a
## legitimate answer at every point in the scan — never a partial or invalid one.

## How many candidate cells are scored between yields. Small enough that a chunk
## is comfortably inside a frame at the per-candidate costs taskblock-44 Pass B
## measured, large enough that the yield overhead stays negligible. Flagged, not
## a tuned number.
const DEFAULT_CHUNK := 16
## The hard ceiling on one unit's positional search. Flagged, not tuned — it is a
## guarantee that the turn ends, not a balance figure.
const DEFAULT_BUDGET_MSEC := 400

var chunk: int = DEFAULT_CHUNK
var budget_msec: int = DEFAULT_BUDGET_MSEC
## The view's `get_tree().process_frame`, or null headless. `Variant` rather than
## `Signal` because a null default is what "nobody is watching" means, and a bare
## `Signal` has no null.
var frame_signal: Variant = null

## Diagnostics, read by tests and by the report — never by planning.
##
## `yields` is CUMULATIVE across every turn this pacer drives; `aborted` is
## per-turn and reset by `begin()`. The split is deliberate: "did this unit
## overrun" is a question about one turn, while "is the slicing actually firing"
## is a question about the run, and a per-turn yield count would read zero
## whenever the last unit happened not to search.
var yields: int = 0
var aborted: bool = false

var _deadline_msec: int = 0
var _since_yield: int = 0


## Starts one unit's turn. Called by the planner, so a caller cannot forget to —
## and so the budget measures the plan rather than however long the view sat
## holding a pacer before using it.
func begin() -> void:
	_deadline_msec = Time.get_ticks_msec() + budget_msec
	_since_yield = 0
	aborted = false


## True once this turn has overrun. Latches `aborted` so a caller that keeps
## asking gets a stable answer and the report can tell an abort from a
## comfortable finish.
func should_abort() -> bool:
	if aborted:
		return true
	if Time.get_ticks_msec() >= _deadline_msec:
		aborted = true
	return aborted


## Counts one scored candidate and answers whether the caller should now yield.
## Always false when nobody is watching, so a headless plan contains no
## suspension at all.
func note_candidate() -> bool:
	if frame_signal == null:
		return false
	_since_yield += 1
	if _since_yield < chunk:
		return false
	_since_yield = 0
	yields += 1
	return true


## taskblock-44 Pass D3: **"Unit 2 is thinking…", never "Thinking…".**
##
## Once named enemies exist, the difference between a mook's turn and a boss's
## turn becomes legible as *character* rather than as lag — the intelligence
## tiers make a smarter unit genuinely think longer, and the label turns that
## from a defect into a tell. It costs nothing to do now and cannot be
## retrofitted into a habit later.
##
## Lives here, in logic, for the usual reason: CC cannot see the screen, so what
## the label SAYS has to be answerable in a headless test, leaving the view with
## nothing but an assignment.
static func thinking_label(unit: Unit) -> String:
	if unit == null:
		return ""
	var name: String = ""
	if unit.matrix != null:
		name = (
			unit.matrix.display_name if unit.matrix.display_name != "" else String(unit.matrix.id)
		)
	if name == "":
		name = "Unit %d" % unit.id
	return "%s is thinking…" % name
