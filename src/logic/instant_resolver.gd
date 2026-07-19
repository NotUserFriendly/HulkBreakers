class_name InstantResolver
extends RefCounted

## taskblock-18 Pass B: the re-validating ordered resolver every "multiple
## contenders resolving at once" case (overwatch racing a step out, two
## overwatchers firing on the same mover, later: initiative/simultaneity
## C, step outs D — taskblock-19 Pass B: Lean -> Step Out rename) funnels
## through. Generalises docs/09 taskblock06 D's own
## re-validation rule ("stop when the next step is no longer legal, not
## when anything changes") from ONE unit's own queue to several
## independent contenders racing each other.
##
## NOT a pre-sort fired blindly: each resolution can invalidate the ones
## behind it (the shooter dies mid-instant, a target dies mid-instant,
## whatever `is_legal()` itself checks) — so this re-sorts AND re-checks
## legality after every single pop, against whatever `state` looks like
## right now, never against a snapshot taken at the start. A naive
## sort-then-fire-every-one-of-them would let a dead unit's queued shot
## still land; this is what makes that impossible.


## Pops and resolves `contenders` fastest-first (`ResolutionSpeed`, A2 —
## lower resolves first), one at a time: sort the REMAINING contenders
## fresh, take the fastest, `apply()` it if still `is_legal()` against the
## world as it stands right now, otherwise drop it un-applied (its own
## trigger was invalidated by something that resolved ahead of it — e.g.
## its acting unit, or its target, died). Returns `{"resolved":
## Array[CombatAction], "dropped": Array[CombatAction]}`, both in the
## order they were popped — resolved unmodified.
static func resolve_instant(contenders: Array[CombatAction], state: CombatState) -> Dictionary:
	var remaining: Array[CombatAction] = contenders.duplicate()
	var resolved: Array[CombatAction] = []
	var dropped: Array[CombatAction] = []

	while not remaining.is_empty():
		var next: CombatAction = _fastest(remaining, state)
		remaining.erase(next)
		if next.is_legal(state):
			next.apply(state)
			resolved.append(next)
		else:
			dropped.append(next)

	return {"resolved": resolved, "dropped": dropped}


## The single fastest contender, re-derived fresh every call (never a
## cached initial sort — "re-evaluate remaining against the updated
## world"). Tie-break chain (taskblock-18 B): resolution_speed ->
## personal_speed -> unit.id. personal_speed is read independently of
## resolution_speed here on purpose: two contenders can land on the exact
## same resolution_speed via different base_speed/personal_speed
## combinations, and "who's faster" (the higher personal_speed, faster
## reflexes) is still the real tiebreak — id only exists for fully
## deterministic replay once even that's tied.
static func _fastest(contenders: Array[CombatAction], state: CombatState) -> CombatAction:
	var best: CombatAction = contenders[0]
	var best_speed: float = ResolutionSpeed.resolve(best, state).current
	var best_personal: float = _personal_speed(best, state)

	for contender: CombatAction in contenders.slice(1):
		var speed: float = ResolutionSpeed.resolve(contender, state).current
		var personal: float = _personal_speed(contender, state)
		var better: bool = speed < best_speed
		if not better and is_equal_approx(speed, best_speed):
			better = personal > best_personal
			if not better and is_equal_approx(personal, best_personal):
				better = contender.unit_id() < best.unit_id()
		if better:
			best = contender
			best_speed = speed
			best_personal = personal

	return best


static func _personal_speed(action: CombatAction, state: CombatState) -> float:
	var unit: Unit = state.find_unit(action.unit_id())
	return unit.matrix.personal_speed if unit != null else 0.0
