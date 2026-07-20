class_name ImpactResult
extends RefCounted

## What resolve_impact decided for one region (docs/03): the outcome, the
## region it hit, how much damage actually landed on that region's part,
## and — for a DEFLECT — the ricochet's new direction and how much of the
## original damage it keeps.

var outcome: int = Enums.Outcome.STOP_DEAD
var region: Region
var incoming_dir: Vector2 = Vector2.ZERO
## taskblock-23 Pass C: `incoming_dir`/`reflected_dir` (below) stay the
## ground-plane heading they always were; these are the real vertical
## slope (rise per unit of ground distance) each one travels at --
## 0.0 for an ordinary flat shot, same as `incoming_dir`/`reflected_dir`
## were always implicitly flat before this pass. Kept as separate scalars
## rather than upgrading `incoming_dir`/`reflected_dir` to Vector3, so
## every existing ground-plane-only reader keeps working unchanged.
var incoming_vertical: float = 0.0
var part_damage: float = 0.0
## taskblock-22 Pass D: "every shot is visible" — the muzzle THIS specific
## hop actually fired from (the true shooter's own position for a shot's
## first hop; the previous hop's own deflection point for a ricochet) and
## where it actually landed, both in the same flat cell-space coords
## `origin`/`point` already use throughout `resolve_shot` — never
## re-derived by the view from a target's own current position, which a
## ricochet's real muzzle (a bounce point in open air) has no other way
## to reach at all. Zero-vector defaults on every ImpactResult a caller
## builds by hand without ever calling through `resolve_shot` (most
## existing tests) — harmless, since nothing reads these unless a real
## shot flight set them.
var origin: Vector2 = Vector2.ZERO
var hit_point: Vector2 = Vector2.ZERO
## taskblock-23 Pass C: `origin`/`hit_point` above are still ground-plane
## only (x, z) -- these carry the real world height each one landed at
## (a Region's own rect, since Pass A, already IS real height on its own
## y-axis), the missing third coordinate a real 3D tracer (Pass D) needs.
## Additive, not a replacement: origin/hit_point's own meaning and every
## existing reader of them is unchanged.
var origin_height: float = 0.0
var hit_height: float = 0.0
## taskblock-09 B/F: the DT this impact's penetrate/stop-dead/deflect
## decision was actually weighed against — Pass B's spill-through reads
## this back rather than re-deriving material.dt a second time, so the
## spill amount can never drift from the decision that produced it. Flat
## `material.dt` today; Pass E swaps the source to `dt_at(thickness)` and
## Pass F folds in `bonus_pen` — this field's meaning stays the same
## across both, only how it's computed changes.
var effective_dt: float = 0.0
var reflected_dir: Vector2 = Vector2.ZERO
## taskblock-23 Pass C: `reflected_dir`'s own real vertical slope — see
## `incoming_vertical` above for why this stays a separate scalar instead
## of upgrading `reflected_dir` to Vector3. Only meaningful when
## `outcome == DEFLECT`; 0.0 (the harmless default) otherwise.
var reflected_vertical: float = 0.0
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
