class_name Unit
extends RefCounted

## Runtime combat pilot: a Matrix (persistent brain) currently seated in a
## Shell (disposable body) on the grid.

const BASE_MP: float = 2.0
## Appendix E / docs/05: "a standard cyborg has 6 AP per turn, before perks
## and upgrades." Every other AP cost in the docs is quoted against this.
const DEFAULT_MAX_AP: int = 6
const AGILITY_STAT_KEY: StringName = &"agility"
## docs/04 gives no turn count for organic decay — a flagged, tunable
## placeholder, not a design decision.
const DECAY_TURNS := 3

var id: int = -1  # assigned by CombatState.add_unit; matches Grid.occupant_id
var matrix: Matrix
var shell: Shell
var cell: Vector2i
## taskblock-36 Pass D: this unit's own true elevation — `Grid.level` at
## `cell`, cached here (mirroring `cell` itself) rather than re-derived
## from the grid every time `UnitGeometry` needs a real Y, since neither
## `UnitGeometry` nor `BodyProjector` otherwise touch the grid at all.
## Synced from the grid at `CombatState.add_unit()`.
## taskblock-37 Pass D: also re-synced by `MoveAction` on every real cell
## change (Pass D adds movement verbs that can genuinely change it —
## tb36's own "nothing else writes it this pass" is no longer true) and by
## `BoutInjector.set_cell_level`'s existing debug force.
var level: int = 0
## taskblock-37 Pass D: the real, continuous world height `UnitGeometry`/
## `ShotPlane` actually place this unit at — `level * LEVEL_HEIGHT` for an
## ordinary cell, plus a half-level offset while resting on a RAMP tile
## (`UnitGeometry.true_height_for_cell`'s own doc comment). `level` alone
## gates discrete decisions (can I climb, is this drop legal); this is
## what drives position and the shot plane. Synced everywhere `level` is.
var height: float = 0.0
var squad_id: int = 0

var ap: int = 0
var max_ap: int = DEFAULT_MAX_AP
var mp: float = 0.0  # movement pool; discarded (not banked) at end of turn
var alive: bool = true
## taskblock-22 Pass A: true once this unit has actually left the board via
## either extraction path (docs/07's "EXIT with loot") — distinct from
## `alive == false`, which also covers death. An extracted unit is a real
## success, never reported/rendered like a kill; `alive` still gates turn
## order/shot-plane membership/targeting exactly as it always has (an
## extracted unit sets both), so nothing downstream needs a second check.
var extracted: bool = false
## taskblock-22 Pass A2: "sit in extract until the end of the next round."
## The round this unit was first found standing on its own team's
## extraction tile, or -1 while not currently holding — reset the instant
## it steps off (EndTurnAction's own hold-check, the only writer). A
## flagged, simple approximation of "held through the end of the next
## round" (checked at this unit's own next turn, not a true round-boundary
## event — see EndTurnAction's own doc comment).
var extraction_hold_start_round: int = -1
## taskblock-22 Pass C: "the unit powers down — out of the fight, inert
## on the board (a shell with no active pilot). It still occludes/blocks
## as geometry." Deliberately NOT `alive == false` — a shut-down unit
## must stay in the shot plane (ShotPlane.build only ever gates on
## `alive`) and keep its own grid cell occupied, unlike death or
## extraction. `CombatState.advance_turn()`'s own turn-order candidates
## are the one thing this actually excludes it from — one-way for now, no
## "wake up" mechanic exists yet (flagged, not invented).
var shutdown: bool = false

## Radians, ground-plane facing (docs/02). 0.0 faces
## BodyProjector.WORLD_FORWARD; continuous, never snapped to
## FRONT/BACK/LEFT/RIGHT.
var orientation: float = 0.0

## docs/10 taskblock05 F: socket transform overrides composing onto the
## body when UnitGeometry/BodyProjector walk it — snap, never animated.
## DOWN is never stored here directly; callers that want it (HitVolumeView,
## based on is_downed()) pass Poses.down() in as an explicit override
## (see UnitGeometry.placements()'s own pose_override parameter) rather
## than this field silently switching underneath them.
var pose: Pose = Poses.idle()

## docs/10 taskblock03 E2: "1 MP unlocks free refacing for the turn — not 1
## MP per rotation." The first manual FaceAction each turn costs 1 MP and
## sets this; every manual face after that, same turn, is free. Reset at
## turn start (CombatState._start_turn()). Free-with-action facing
## (FaceAction.face_for_free) never reads or sets this — it's always free.
var facing_unlocked: bool = false

## docs/09 taskblock06 Pass F: which weapon (by pool part id) this unit is
## holding overwatch with, or empty if not armed. Set by OverwatchAction's
## own apply() (which also ends the unit's turn — you're holding, not
## acting); cleared the instant it fires (fires once, then spent) or at
## the start of this unit's own next turn (CombatState._start_turn()),
## same reset convention as facing_unlocked above.
var overwatch_weapon_id: StringName = &""

var held_matrix: Matrix = null  # a Matrix carried after PickUpAction, awaiting ImplantAction

## docs/04: a ladder, not a health bar. Demoted on damage to the matrix-
## hosting part (DamageResolver), decays further the longer it stays
## exposed (tick_organics_decay).
var surrogate_tier: SurrogateTier = SurrogateLadder.default_ladder()[0]
## Turns since the surrogate was first exposed or damaged; 0 means intact.
var exposed_turns: int = 0


func _init(p_matrix: Matrix, p_shell: Shell, p_cell: Vector2i, p_squad_id: int = 0) -> void:
	matrix = p_matrix
	shell = p_shell
	cell = p_cell
	squad_id = p_squad_id


## Steps the surrogate one rung down the ladder (docs/04: "a torso chewed
## to SPINAL still functions") and starts (or keeps) its exposure clock
## running.
func demote_surrogate(ladder: Array[SurrogateTier]) -> void:
	surrogate_tier = SurrogateLadder.demote(surrogate_tier, ladder)
	if exposed_turns == 0:
		exposed_turns = 1


## Called once per turn this unit is exposed (docs/04: "once exposed or
## damaged, tier decays over turns"). Demotes one further rung every
## DECAY_TURNS calls since the last demotion; a no-op once nothing is
## exposed yet.
func tick_organics_decay(ladder: Array[SurrogateTier]) -> void:
	if exposed_turns <= 0:
		return
	exposed_turns += 1
	if exposed_turns > DECAY_TURNS:
		exposed_turns = 1
		surrogate_tier = SurrogateLadder.demote(surrogate_tier, ladder)


## MP granted per AP burned for movement (Appendix E). Resolved live through
## StatResolver (docs/08) so part swaps immediately affect mobility, and so
## this stays the one true source of the number — not an ad-hoc sum.
##
## docs/10 taskblock05 E1's own rule ("broken parts already leave
## living_parts(), so a destroyed part's own modifiers already stop
## applying") was not actually true here — this read shell.all_parts()
## (every part regardless of hp) until docs/09 taskblock06 Pass D's own
## mid-move interrupt test needed a destroyed leg to genuinely lower
## mobility and found it didn't. Fixed to match every other modifier-
## bearing part in the game. taskblock-20 Pass D: reads `operable_parts()`
## now, not `living_parts()` directly — a `severed_controls`-wounded leg
## (hp intact, but inert) must stop contributing agility the same way a
## destroyed one already does.
func mp_per_ap() -> float:
	var context := ResolverContext.new()
	context.parts = shell.operable_parts()
	var agility: float = StatResolver.resolve(AGILITY_STAT_KEY, context).current
	return BASE_MP + agility


## docs/04 taskblock02 Pass D1: "Unit resolves its matrix by walking the
## tree" — works whether it docks directly in the shell root (a bot) or two
## levels down, inside an attached surrogate (a cyborg). The same object as
## `matrix` while piloted; the one place that still knows where it actually
## lives once nesting is involved.
func resolve_matrix() -> Matrix:
	for part: Part in shell.all_parts():
		if part.hosts_matrix() and part.hosted_matrix != null:
			return part.hosted_matrix
	return null


## docs/10 taskblock03 G: "a unit with no matrix docked (a shell)... needs
## to read as down." Moved here (was HitVolumeView's own copy) — a query, not a
## stored flag, same as always. Callers that want DOWN's geometry to
## actually apply (taskblock05 F3's Pose) pass `Poses.down()` in
## explicitly where it matters (HitVolumeView) rather than this being read
## automatically by every headless placements()/project() call — a bare
## test fixture that never bothers docking a matrix (most of them; matrix
## docking is irrelevant to what they're actually testing) must not
## silently start rendering sideways.
func is_downed() -> bool:
	return resolve_matrix() == null


## docs/09 taskblock06 Pass C: "poses are sampled at instants — nothing is
## ever integrated." `progress` (0.0-1.0, e.g. how far along a queued move
## a freeze lands) exists for a future real rig to pick a genuinely
## different pose partway through a walk cycle; today there is no such
## thing — only the three snap poses (docs/10 taskblock05 F3) — so this
## always returns the SAME pose regardless of `progress`. Sampling between
## discrete states is not interpolating between them, and this seam is
## deliberately incapable of the latter: resolution is always "set the
## pose, cast the ray, read the hit" against one frozen instant, never a
## blend two instants apart. Deterministic by construction — no
## accumulated float drift, no tick-rate dependence.
func pose_at(_progress: float) -> Pose:
	return pose


## docs/04 taskblock02 Pass D3: the docked surrogate's own capabilities, or
## empty for a bot (no surrogate at all) or an unoccupied shell.
func docked_surrogate_capabilities(ladder: Array[SurrogateTier]) -> Array[StringName]:
	for part: Part in shell.all_parts():
		if part.surrogate_tier == &"":
			continue
		for tier: SurrogateTier in ladder:
			if tier.id == part.surrogate_tier:
				return tier.capabilities
	return []


## False only if `part.body_requires` names a capability the docked
## surrogate doesn't have — a part failing this is INERT (present,
## carried, massed, shootable) never removed or errored (docs/04).
func can_use_part(part: Part, ladder: Array[SurrogateTier]) -> bool:
	if part.body_requires.is_empty():
		return true
	var capabilities: Array[StringName] = docked_surrogate_capabilities(ladder)
	for required: StringName in part.body_requires:
		if not required in capabilities:
			return false
	return true


## A fully independent copy — matrix, whole shell tree, and every scalar
## field — for TACTICS-time speculative previews (docs/09). Mutating a dup
## must never be observable on the original.
func dup() -> Unit:
	var cloned := Unit.new(matrix.duplicate(true) as Matrix, shell.dup(), cell, squad_id)
	cloned.id = id
	cloned.ap = ap
	cloned.max_ap = max_ap
	cloned.mp = mp
	cloned.alive = alive
	cloned.extracted = extracted
	cloned.extraction_hold_start_round = extraction_hold_start_round
	cloned.shutdown = shutdown
	cloned.orientation = orientation
	cloned.pose = pose
	cloned.facing_unlocked = facing_unlocked
	cloned.overwatch_weapon_id = overwatch_weapon_id
	cloned.held_matrix = held_matrix.duplicate(true) as Matrix if held_matrix != null else null
	cloned.surrogate_tier = surrogate_tier
	cloned.exposed_turns = exposed_turns
	return cloned
