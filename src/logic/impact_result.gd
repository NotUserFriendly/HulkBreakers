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
## taskblock-09 B/F: the DT this impact's penetrate/stop-dead/deflect
## decision was actually weighed against — Pass B's spill-through reads
## this back rather than re-deriving material.dt a second time, so the
## spill amount can never drift from the decision that produced it. Flat
## `material.dt` today; Pass E swaps the source to `dt_at(thickness)` and
## Pass F folds in `bonus_pen` — this field's meaning stays the same
## across both, only how it's computed changes.
var effective_dt: float = 0.0
var reflected_dir: Vector2 = Vector2.ZERO
var retained_fraction: float = 0.0
var is_crit: bool = false
var is_double_crit: bool = false
var bypassed_armor: bool = false
var destroyed_part: bool = false
## taskblock-09 A3: renamed from cooked_off_units — DETONATE, not "cook-off."
var detonated_units: Array[Unit] = []
## taskblock-09 A4: the K fragment rays' own results, when this impact
## destroyed a failure_mode == FRAGMENT part — each one a full nested
## resolve_shot flight (penetration/deflect/ricochet, all of it), never
## just a flat damage number.
var fragment_hits: Array[ImpactResult] = []
## taskblock-09 A4: true when this impact started a MELTDOWN countdown
## (as opposed to detonating immediately, which shows up in
## `detonated_units` instead, same as any other DETONATE).
var meltdown_armed: bool = false
var ejected_matrix: Matrix = null
## docs/04 taskblock02 Pass D1: the shell root's attached surrogate,
## matrix and all, when the root itself is destroyed while hosting one —
## distinct from `ejected_matrix`, which fires when a part hosts a BARE
## matrix directly (a bot). Mutually exclusive on any one impact.
var ejected_surrogate: Part = null
## taskblock-09 C2: populated only by a SEVERED JOINT hit now, never by a
## part reaching 0 hp (BREAK is gone) — the socket's own occupant subtree
## dropping intact, rooted at the child the joint connected. A part
## failing under MANGLE/DISABLE/DETONATE/FRAGMENT/MELTDOWN never touches
## this field at all.
var dropped_subtree: Array[Part] = []
## Set alongside `ejected_matrix` (docs/04: ejection always demotes the
## surrogate one rung) — captured here rather than re-derived afterward,
## since the demoted unit's owning part may already be detached from its
## shell by the time a caller gets around to logging this impact.
var demoted_unit: Unit = null
var demoted_tier_before: SurrogateTier = null
## taskblock-20 Pass C4: non-empty (e.g. `&"lodged_bullet"`) when this
## impact is the one where the round finally floored while still inside a
## `hollow` part's own shell — entered, never cleared the far face. Empty
## for every ordinary impact, including a round that floors on a SOLID
## part outside any hollow envelope (that's just "stopped," not "lodged").
var wound_inflicted: StringName = &""
