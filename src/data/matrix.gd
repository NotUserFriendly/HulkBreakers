class_name Matrix
extends Resource

## docs/04: the Base Matrix stays on the ship and writes itself into a Link
## Matrix (a standard Logic Matrix) in the field. One class serves both
## roles rather than two — `base == null` means this instance IS a base (or
## an unlinked bot's own matrix); `base` set means this instance is the
## physical Link deployed in the field, and effective_level()/active_perks()
## defer to whatever the base actually has. A low-tier link caps capability
## but still lets the player choose which of the base's perks travel.

@export var id: StringName
@export var display_name: String = ""
@export var level: int = 1
@export var xp: int = 0
@export var perks: Array[StringName] = []
@export var recovery_state: Enums.RecoveryState = Enums.RecoveryState.PILOTING
## taskblock-14 Pass B2: "baked-in personality" — travels with the matrix,
## not the shell, so the same mind reads the same way across bodies.
## Open StringName (`UnitAI.plan_turn`'s own vocabulary — AGGRESSIVE,
## COVER_SEEKER today), never an enum: a third playstyle is new data, not
## a code change. A player matrix carries one too, as a fallback only —
## no selection UI beyond the bout menu (taskblock-14 Pass D) is built
## for it.
@export var playstyle: StringName = &"AGGRESSIVE"
## taskblock-18 Pass A1: "reflexes are the pilot's, not the chassis's" — on
## the matrix, not the shell, same reasoning as `playstyle` above; a fast
## matrix in a slow body is still quick, and swapping bodies carries your
## speed. A flat bonus `ResolutionSpeed.resolve()` subtracts from every
## action's own resolution speed everywhere that axis is read (taskblock-18
## A2) — it reads as a pure player-facing bonus. Flagged placeholder
## default: same for every matrix until tuned, so the ORDERING works
## immediately without the resolver waiting on balance numbers.
@export var personal_speed: float = 0.0

## Link-only fields (docs/04). `perk_slots` is explicitly "not final" in the
## docs — a flagged, tunable default, not a design decision.
@export var base: Matrix = null
@export var tier_ratio: float = 1.0
@export var perk_slots: int = 3
@export var chosen_perks: Array[StringName] = []


## `base.level * link.tier_ratio` when linked; this instance's own level
## when it IS the base (or an unlinked matrix).
func effective_level() -> float:
	if base == null:
		return float(level)
	return float(base.level) * tier_ratio


## The base's full perk pool when this instance IS the base; the player-
## chosen subset (bounded by perk_slots) when it's a link.
func active_perks() -> Array[StringName]:
	if base == null:
		return perks
	return chosen_perks


## taskblock-07 Pass E3: the matrix's own contribution to `actions_for` —
## "overwatch is on guns FOR NOW, later it'll be a matrix's perk... it's
## something the matrix KNOWS HOW to do." Empty today: no `Perk` resource
## exists yet to carry a `provides_actions` array of its own ("outline
## only... do not invent perk ids, do not build a perk system" — E3).
## `ActionCatalog.actions_for` already unions this alongside every part's
## own `provides_actions`, so the day a perk can name an action, this
## method is the only thing that changes — the collector needs no edit.
func provides_actions() -> Array[StringName]:
	return []


## Link destroyed (docs/04): "the feeling of dying mirrors back to the
## base." Recovery state moves to LINK_KILLED and one perk is docked from
## the base's pool — the concrete mechanic docs/04 offers as its own
## example ("perk reduction"), not an invented number. A no-op if this
## instance isn't actually a link, or the base has no perks left to lose.
func destroy(rng: RandomNumberGenerator) -> StringName:
	if base == null:
		return &""
	base.recovery_state = Enums.RecoveryState.LINK_KILLED
	if base.perks.is_empty():
		return &""
	var index: int = rng.randi_range(0, base.perks.size() - 1)
	return base.perks.pop_at(index)
