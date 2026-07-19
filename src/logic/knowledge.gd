class_name Knowledge
extends RefCounted

## taskblock-20 Pass B: "a hidden internal is targetable only if the
## player knows it's there... this is where the deferred fog-of-
## knowledge finally has a job ('chess, then chess with hidden
## pieces')." A single flagged checkpoint, not a real sensor system —
## "the knowledge SOURCE (what sensor reveals internals) is a flagged
## hook — default to 'internals known' so it's testable; gate on real
## scanning when sensors exist. Don't build sensors." Every caller that
## wants to aim at a specific internal part goes through here, never a
## second, independently-maintained "do I know about this" check.


## Always true today — no sensor/scan system exists yet to gate on for
## real. The signature is already shaped for one (state/observer/target/
## part all present) so wiring a real check in later is a body change
## inside this one function, never a call-site migration.
static func knows_internal(
	_state: CombatState, _observer: Unit, _target: Unit, _part: Part
) -> bool:
	return true
