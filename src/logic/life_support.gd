class_name LifeSupport
extends RefCounted

## docs/04 taskblock02 Pass D4: decay/hold/regen for an exposed surrogate,
## gated by socket + power + organics. Extends the existing
## exposed_turns/demote_surrogate mechanism (Phase 7) rather than
## replacing it — only WHEN a demotion advances changes, not the
## underlying ladder-stepping itself.
##
## | Surrogate is | Decay clock |
## |---|---|
## | socketed, no power | advances (today's plain tick_organics_decay) |
## | socketed + powered, no organics | holds |
## | socketed + powered + organics carried | winds back, consumes organics |
##
## Regen never promotes a tier — it only walks exposed_turns back toward 0,
## the same counter demotion already uses, floored there. Once a tier is
## actually lost it stays lost until a growth item (docs/04 Pass D5,
## explicitly a hook, not built here).
##
## Scope note: this only covers a surrogate still socketed in a piloted
## Unit. A DETACHED surrogate (dropped loose after ejection) has no
## per-turn ticking today — that needs a field-item tick loop the mission
## layer doesn't have yet. Flagged, not silently skipped.


static func tick(unit: Unit, ladder: Array[SurrogateTier]) -> void:
	if unit.exposed_turns <= 0:
		return

	if unit.shell.is_powered():
		if unit.shell.consume_organics() != null:
			unit.exposed_turns = maxi(unit.exposed_turns - 1, 0)
		return

	unit.tick_organics_decay(ladder)
