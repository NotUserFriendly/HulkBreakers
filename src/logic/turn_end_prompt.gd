class_name TurnEndPrompt
extends RefCounted

## taskblock-57 Pass C: **ending a turn with AP or MP left asks first.**
##
## The table's row for turn-order management: *"End turn with AP or MP left **prompts for
## confirmation**"*. The prompt is a dialog and belongs to the view; **whether there is anything to
## prompt about is arithmetic**, and arithmetic belongs here — so the question is answerable in a
## headless test rather than only by clicking the button.
##
## ## It asks the PREVIEWED unit, not the raw one
##
## A queued move has not resolved yet, so the raw unit still holds the AP and MP that move is about
## to spend. Prompting off that would fire on almost every turn, which is the fastest way to teach a
## player to click through a confirmation without reading it. `SelectionController.previewed_unit()`
## is the same speculative state the pips, the reachable-cell highlighting and the queue panel all
## already key off — the number in the prompt is the number the player can see in the pips.
##
## ## What it does not know
##
## **"Has AP left" is not the same as "could have done something useful with it"**, and this does
## not try to be. A unit with 1 AP and no weapon, or with 0.3 MP and nowhere within 0.3 MP to step,
## still prompts. Answering the better question means asking `ActionCatalog` what is actually
## affordable, which is a real piece of work and not what the table asks for. Recorded rather than
## quietly approximated — if the prompt turns out to be noisy in play, this is the reason and
## `ActionCatalog` is the fix.

## Float slack. MP is a pool of fractions, so a residue of 1e-7 left by arithmetic is not "movement
## remaining" and must not raise a dialog. **Noise only** — anything above this really is unspent,
## per the paragraph above.
const MP_EPSILON := 0.001


## What `unit` still has, as `{"ap": int, "mp": float}`. An empty dictionary for a null unit, which
## is a real state (nothing selected) and not an error.
static func unspent(unit: Unit) -> Dictionary:
	if unit == null:
		return {}
	return {"ap": unit.ap, "mp": unit.mp}


## True if ending the turn now would waste something.
static func should_confirm(unit: Unit) -> bool:
	var left: Dictionary = unspent(unit)
	if left.is_empty():
		return false
	return int(left["ap"]) > 0 or float(left["mp"]) > MP_EPSILON


## The line the dialog shows. **Built from the same call that decides whether to ask**, so the
## number in the prompt cannot disagree with the reason the prompt appeared — `docs/08`'s rule that
## the number shown is the number computed, applied to a confirmation.
##
## Says only what is actually left: a unit with AP and no MP should not be told about its MP.
static func message(unit: Unit) -> String:
	var left: Dictionary = unspent(unit)
	if left.is_empty():
		return ""
	var parts: Array[String] = []
	if int(left["ap"]) > 0:
		parts.append("%d AP" % int(left["ap"]))
	if float(left["mp"]) > MP_EPSILON:
		parts.append("%.1f MP" % float(left["mp"]))
	if parts.is_empty():
		return ""
	return "End the turn with %s unspent?" % " and ".join(parts)
