class_name PowerResolver
extends RefCounted

## taskblock-20 Pass F: "AP stops being a flat baseline and becomes a
## function of the shell's power system." Reactor parts contribute their
## own steady `power_produced`; batteries store/discharge/recharge
## (`battery_capacity`/`battery_power_out`/`battery_power_in`/
## `battery_charge`). One point of power buys one AP — chosen so a shell
## authored with today's baseline reactor (`power_produced` == 6.0, the
## same number as `Unit.DEFAULT_MAX_AP`) sees no change from before this
## pass, whether or not this system has been wired in yet.
##
## "Damage the part that matters, the rest crumbles" is deliberately
## emergent, not a coded death hook: a destroyed reactor with no charged
## battery to fall back on simply leaves `max_ap_for` at 0 from the owning
## unit's own next turn start onward — no explicit kill, no special case,
## the exact same layered-body-plus-failure-model math that decides every
## other consequence in this game.

const POWER_PER_AP := 1.0


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


## The unit's own max AP for the turn ahead, derived purely from its own
## total available power (reactor + battery) — can be 0 for a genuinely
## cored shell. Only meaningful once `has_power_system` is true; callers
## (`CombatState._start_turn`) gate on that themselves rather than this
## function silently substituting a fallback, so a shell with no power
## system at all (every shell built before this pass, most test fixtures)
## leaves `Unit.max_ap` COMPLETELY untouched — whatever it already was,
## including a test's own direct override — rather than this function
## quietly overwriting it back to some baseline on every turn start.
static func max_ap_for(unit: Unit) -> int:
	var total: float = reactor_power(unit.shell) + battery_power(unit.shell)
	return int(floor(total / POWER_PER_AP))
