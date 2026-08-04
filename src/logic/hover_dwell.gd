class_name HoverDwell
extends RefCounted

## taskblock-57 Pass C: **the one hover timer, shared by two behaviours that say different things.**
##
## The taskblock is specific about this: *"1.5 s motionless before a tooltip. **Two behaviours
## sharing one timer** — a button tooltip is descriptive (what will this do), a combat-log
## overflow preview is revealing (what does this line say, shown in place over the text). Do not
## merge their content models."*
##
## So the **timing** is shared and the **content** is not. This class is the shared half: it knows
## how long the cursor has been still and nothing whatsoever about what is under it. `TooltipView`
## drives a `TooltipData` off it; `CombatLogPanel` drives a line reveal off it; neither knows the
## other exists.
##
## ## Why a class rather than a constant both files read
##
## A shared constant is a shared *number*, not a shared timer — each caller still writes its own
## accumulate-and-compare, and the two drift the first time one of them forgets to reset. The
## project has produced two visibility systems, two aiming paths and two overlay hierarchies from
## exactly that shape. One object with one `tick` is the thing that cannot diverge.
##
## ## Logic, so the delay is testable without waiting 1.5 real seconds
##
## CLAUDE.md: `RefCounted` in `src/logic`, no SceneTree. `tick` takes an explicit delta, so a test
## advances the clock the same way `CameraRig`'s tween tests do — the delay is asserted, never
## slept through.

## **1.5 s motionless**, the taskblock's own number.
##
## This raises the previous 0.4 s that `TooltipView` shipped, which was itself flagged as "a tuning
## number, not a design decision". 1.5 s is specified, so it is no longer a guess.
const DELAY_SEC := 1.5

## How long the cursor has been still on the current target. Public so a caller can show progress.
var elapsed: float = 0.0
## True while a target is being dwelt on and the delay has not yet elapsed.
var pending: bool = false
## True once the delay has elapsed and the caller has been told to reveal. Stays true until the
## target changes or `cancel` is called, so a caller can ask "am I showing" without its own flag.
var fired: bool = false

var _target: Variant = null


## Starts (or restarts) the wait for a **new** target. A repeated call with an unchanged target does
## not restart the clock — that is the property that makes a tooltip follow the cursor across one
## button without resetting the wait every frame, which was `taskblock-08 D1`'s own requirement.
##
## `target` is whatever the caller uses to mean "the same thing": a rendered tooltip string, a log
## line index, a control. Compared with `!=`, so anything comparable works.
func aim_at(target: Variant) -> void:
	if pending or fired:
		if _target == target:
			return
	_target = target
	elapsed = 0.0
	pending = true
	fired = false


## Advances the clock. **Returns true on the single tick the delay is crossed**, so a caller does
## the expensive reveal once rather than every frame afterwards.
func tick(delta: float) -> bool:
	if not pending:
		return false
	elapsed += delta
	if elapsed < DELAY_SEC:
		return false
	pending = false
	fired = true
	return true


## Nothing is being hovered any more. Both the wait and anything already revealed are over.
func cancel() -> void:
	_target = null
	elapsed = 0.0
	pending = false
	fired = false


## Whatever the caller last aimed at, or null. Read by a caller that needs to know *what* to reveal
## on the tick `tick` returns true.
func target() -> Variant:
	return _target
