class_name ImpactResult
extends RefCounted

## What resolve_impact decided for one region (docs/03): the outcome, the
## region it hit, how much damage actually landed on that region's part,
## and — for a DEFLECT — the ricochet's new direction and how much of the
## original damage it keeps.

var outcome: int = Enums.Outcome.STOP_DEAD
var region: Region
var incoming_dir: Vector2 = Vector2.ZERO
var part_damage: float = 0.0
var reflected_dir: Vector2 = Vector2.ZERO
var retained_fraction: float = 0.0
var is_crit: bool = false
var is_double_crit: bool = false
var bypassed_armor: bool = false
var destroyed_part: bool = false
var cooked_off_units: Array[Unit] = []
var ejected_matrix: Matrix = null
## docs/04 taskblock02 Pass D1: the shell root's attached surrogate,
## matrix and all, when the root itself is destroyed while hosting one —
## distinct from `ejected_matrix`, which fires when a part hosts a BARE
## matrix directly (a bot). Mutually exclusive on any one impact.
var ejected_surrogate: Part = null
## docs/10 taskblock05 E2: usually one entry (the non-mangling case: the
## destroyed part's own subtree, rooted at it) but a mangling destruction
## can drop several separate items at once — its own children, each its
## own intact assembly, plus the wreckage `part` itself became.
var dropped_subtree: Array[Part] = []
## Set alongside `ejected_matrix` (docs/04: ejection always demotes the
## surrogate one rung) — captured here rather than re-derived afterward,
## since the demoted unit's owning part may already be detached from its
## shell by the time a caller gets around to logging this impact.
var demoted_unit: Unit = null
var demoted_tier_before: SurrogateTier = null
