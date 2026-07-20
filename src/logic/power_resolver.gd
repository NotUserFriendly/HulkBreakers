class_name PowerResolver
extends RefCounted

## taskblock-20 Pass F: "AP stops being a flat baseline and becomes a
## function of the shell's power system." Reactor parts contribute their
## own steady `power_produced`; batteries store/discharge/recharge
## (`battery_capacity`/`battery_power_out`/`battery_power_in`/
## `battery_charge`).
##
## taskblock-22 Pass B: refined — power and AP are RELATED, not mutually
## defining. Consumers (`Part.power_consumed`) subtract from the shell's
## own reactor+battery output FIRST; only the SURPLUS converts to AP, and
## that conversion itself diminishes at high surplus (`POWER_TO_AP_CURVE`
## below) — "AP is time AND energy: a turn is a fixed amount of time, so
## past a point more energy can't buy more actions." Supersedes the old
## flat `total / POWER_PER_AP` entirely — `max_ap_for` is the one thing
## this pass actually replaces, not extends. `recharge_batteries`/
## `discharge_batteries` below are UNCHANGED: consumers affect only the
## AP surplus calculation, never the battery charge economy itself.
##
## "Damage the part that matters, the rest crumbles" is deliberately
## emergent, not a coded death hook: a destroyed reactor with no charged
## battery to fall back on simply leaves `max_ap_for` at 0 from the owning
## unit's own next turn start onward — no explicit kill, no special case,
## the exact same layered-body-plus-failure-model math that decides every
## other consequence in this game.

## taskblock-22 Pass B1: "a lookup table like dt_curve — authored,
## reviewable, tunable," the same [(x, y), ...] ascending-and-interpolated
## shape `MaterialEntry.dt_curve`/`dt_at()` already established — one
## shared conversion, not per-part (surplus->AP is a property of the
## economy, never of any one reactor/battery). Flagged placeholder numbers,
## not a tuned design: the taskblock's own two example points (8 surplus
## -> 6 AP, 12 surplus -> 8 AP) are authored here exactly, with (0, 0) and
## a 1:1 run up to (6, 6) below them — a bare reactor.tres alone (6.0
## power_produced, no consumers) still lands at EXACTLY today's baseline
## 6 AP, "existing shells land near ~6 AP by default" — and a soft
## continuation past 12 (20, 10) so the curve keeps bending down rather
## than hard-capping.
const POWER_TO_AP_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(6.0, 6.0),
	Vector2(8.0, 6.0),
	Vector2(12.0, 8.0),
	Vector2(20.0, 10.0),
]


## False for a shell that never opted into the power system at all (no
## part anywhere in it authors `power_produced` or `battery_capacity`) —
## every shell built before this pass, and most test fixtures — so
## `max_ap_for` falls back to the flat baseline rather than reading a
## missing power system as "zero power" (taskblock-20 Pass F's own "so
## nothing breaks"). Checked against `all_parts()`, not `operable_parts()`:
## a shell that HAD a reactor, now destroyed, still "has a power system" —
## its own power output correctly reads as reduced (maybe to 0), never
## silently substituted back to the flat baseline as if it never had one.
static func has_power_system(shell: Shell) -> bool:
	for part: Part in shell.all_parts():
		if part.power_produced > 0.0 or part.battery_capacity > 0.0:
			return true
	return false


## Every operable reactor's own steady output, summed — a wound-disabled or
## destroyed reactor (`operable_parts()`) contributes nothing.
static func reactor_power(shell: Shell) -> float:
	var total := 0.0
	for part: Part in shell.operable_parts():
		total += part.power_produced
	return total


## Every operable battery's own AVAILABLE discharge this turn — capped by
## its own `battery_power_out`, never by more charge than it actually
## holds.
static func battery_power(shell: Shell) -> float:
	var total := 0.0
	for part: Part in shell.operable_parts():
		if part.battery_capacity > 0.0:
			total += minf(part.battery_charge, part.battery_power_out)
	return total


## taskblock-22 Pass B1: every operable power-hungry part's own draw,
## summed — a wound-disabled or destroyed consumer draws nothing, same
## `operable_parts()` gate every other power field already reads.
static func consumer_power(shell: Shell) -> float:
	var total := 0.0
	for part: Part in shell.operable_parts():
		total += part.power_consumed
	return total


## taskblock-22 Pass B1: "consumers drain it first — the surplus converts
## to AP." Floored at 0.0: a shell drawing more than it produces has
## nothing left over, never a negative surplus (there's no such thing as
## negative AP to feed the curve below).
static func surplus(unit: Unit) -> float:
	var total: float = reactor_power(unit.shell) + battery_power(unit.shell)
	return maxf(0.0, total - consumer_power(unit.shell))


## taskblock-22 Pass B1: `surplus` run through `POWER_TO_AP_CURVE` — the
## same linear-interpolate-and-clamp-at-the-ends algorithm
## `MaterialEntry.dt_at()` already uses for its own authored curve, floored
## to a whole AP (never a fractional action). An empty curve (never true
## for the one authored above, but a caller building its own table could
## hand in one) degrades to 0 rather than crashing.
static func ap_for_surplus(surplus_value: float) -> int:
	if POWER_TO_AP_CURVE.is_empty():
		return 0
	if surplus_value <= POWER_TO_AP_CURVE[0].x:
		return int(floor(POWER_TO_AP_CURVE[0].y))
	if surplus_value >= POWER_TO_AP_CURVE[-1].x:
		return int(floor(POWER_TO_AP_CURVE[-1].y))
	for i in range(1, POWER_TO_AP_CURVE.size()):
		var point: Vector2 = POWER_TO_AP_CURVE[i]
		if surplus_value <= point.x:
			var prev: Vector2 = POWER_TO_AP_CURVE[i - 1]
			var t: float = (surplus_value - prev.x) / (point.x - prev.x)
			return int(floor(lerp(prev.y, point.y, t)))
	return int(floor(POWER_TO_AP_CURVE[-1].y))


## taskblock-20 Pass F: "weak-reactor + batteries (rest to recharge)."
## Every operable battery tops up from the shell's own total reactor
## output, up to its own `battery_power_in` and however much room is left
## under its own `battery_capacity` — never more than the reactor actually
## produces this turn, and never drawing down one battery to top up
## another (each battery reads the SAME reactor total independently, not a
## shared pool depleted in some arbitrary order). A no-op with no reactor
## power at all — nothing to recharge FROM.
static func recharge_batteries(shell: Shell) -> void:
	var available: float = reactor_power(shell)
	if available <= 0.0:
		return
	for part: Part in shell.operable_parts():
		if part.battery_capacity <= 0.0:
			continue
		var room: float = part.battery_capacity - part.battery_charge
		part.battery_charge += clampf(minf(part.battery_power_in, room), 0.0, available)


## taskblock-20 Pass F: "a battery-only shell's AP falls as batteries
## drain." Each operable battery gives up whatever `battery_power` already
## counted toward THIS turn's `max_ap` — the same amount, not re-derived —
## so a shell drawing on battery power always has less available next
## turn unless recharge (from real reactor output) offsets it. A no-op for
## a reactor that never touches battery_charge at all.
static func discharge_batteries(shell: Shell) -> void:
	for part: Part in shell.operable_parts():
		if part.battery_capacity <= 0.0:
			continue
		part.battery_charge -= minf(part.battery_charge, part.battery_power_out)


## The unit's own max AP for the turn ahead — `surplus()` (output minus
## consumers) run through `POWER_TO_AP_CURVE`; can be 0 for a genuinely
## cored shell, or for one whose consumers eat its whole output. Only
## meaningful once `has_power_system` is true; callers
## (`CombatState._start_turn`) gate on that themselves rather than this
## function silently substituting a fallback, so a shell with no power
## system at all (every shell built before this pass, most test fixtures)
## leaves `Unit.max_ap` COMPLETELY untouched — whatever it already was,
## including a test's own direct override — rather than this function
## quietly overwriting it back to some baseline on every turn start.
static func max_ap_for(unit: Unit) -> int:
	return ap_for_surplus(surplus(unit))
