class_name EditorLog
extends RefCounted

## taskblock-57 Pass G2: **validation warnings go to the combat log, and the significant ones
## announce.**
##
## The taskblock: *"Validation warnings go to the combat log, and the significant ones surface as
## announcements. **Warn, never block** needs somewhere to warn."*
##
## Until this pass the editor's warnings existed only as a `RichTextLabel` in its own panel — which
## is a list you have to be looking at, in a panel Pass G2 makes collapsible. A board that cannot be
## traversed should say so where the author is already reading.
##
## ## Only what is new is said
##
## `EditorModule.refresh()` runs after **every** edit, and the warning list is recomputed whole each
## time. Emitting all of it every time would put the same "no walkable surface anywhere" line in the
## log once per click — which is not a log, it is a stutter. `arrived` diffs against what was last
## reported, so a warning is announced when it appears and stays quiet while it persists.
##
## **And it is said again if it comes back.** A warning that is fixed and then reintroduced is new
## information the second time, so the caller's "last reported" list shrinks as warnings clear.
##
## ## What counts as significant, stated rather than invented
##
## `CLAUDE.md`: never invent a rule and present it as design. The taskblock says *"the significant
## ones"* and does not say which, so this takes a distinction the code **already** draws:
## `EditorController.navigability_warnings()` is its own separately-computed category, and it is the
## one that describes a board a bout cannot be played on. Those announce; bounds and grammar
## warnings go to the log alone.
##
## **The caller supplies both lists rather than this file computing them**, so the rule is one
## `has()` and there is no second copy of the validation.
##
## `ALERT`, not `CRITICAL`: the priority table reserves the loudest tier for things that end or
## change a mission, and an authoring warning is not one. Flagged as tunable; the supervisor's pass
## owns the tier.

## The event kind every editor warning carries. An open `StringName` like every other kind, so a
## sink or a fold can filter authoring noise in or out without knowing what a warning says.
const WARNING: StringName = &"editor_warning"


## The entries of `current` that were not in `previous`, in `current`'s own order.
##
## Pure, so "say it once" is testable without an editor, a board, or a log.
static func arrived(previous: Array[String], current: Array[String]) -> Array[String]:
	var fresh: Array[String] = []
	for warning: String in current:
		if not previous.has(warning):
			fresh.append(warning)
	return fresh


## Emits one line per warning in `warnings`, tagging the ones that also appear in `significant` for
## the announcement position.
##
## Returns how many were emitted, so a caller can assert the count rather than scraping the log.
##
## A null state or log is a legal quiet no-op — the editor mounts against a context with no battle
## at all, which is `test_view_modules_stand_alone.gd`'s own acceptance.
static func report(state: CombatState, warnings: Array[String], significant: Array[String]) -> int:
	if state == null or state.combat_log == null:
		return 0
	for warning: String in warnings:
		var data: Dictionary = {"warning": warning}
		if significant.has(warning):
			# **One emit, two views** (Pass E). Tagging is what puts the line at the announcement
			# position; there is deliberately no second call that could put it in one and not the
			# other.
			Announcement.tag(data, Announcement.ALERT)
		# An authoring edit is not part of a turn. `TACTICS` is the phase that mutates nothing by
		# resolution, which is the closer of the two, and no reader branches on the phase of an
		# editor warning. `unit_id` is -1: no unit did this.
		var event := LogEvent.new(
			state.round_number, Enums.Phase.TACTICS, -1, WARNING, data, "editor: %s" % warning
		)
		state.combat_log.emit(event)
	return warnings.size()
