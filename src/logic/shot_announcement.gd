class_name ShotAnnouncement
extends RefCounted

## tb60 Pass B: **every way of putting a round in the air announces itself, and it announces
## by construction rather than by whoever adds the next one remembering to.**
##
## Before this, `BurstAction` was the only firing path that emitted a fire event.
## `AttackAction`, `StabAction`, `SlashAction`, `GrindAction`, `Suppression` and `Overwatch`
## emitted **impacts only** — one of seven paths announced itself, so a sniper firing and a
## sniper idling were indistinguishable in the log until something was hit. That cost real
## time: `BR54.01`'s angle table had to be inferred from impacts, and it was inferrable at all
## only because impacts happen to carry origin and hit points.
##
## ## Why this is an object and not one more event kind
##
## The point was never "add a seventh emit". It is that a **new** firing path cannot resolve a
## shot without describing it: `ShotResolution.resolve_and_log_point` takes one of these as a
## required argument and reads the shot's origin and direction back out of it. So an eighth
## path physically cannot reach the resolver without building an announcement, and it cannot
## announce a direction different from the one it resolves — there is one description of the
## shot, not two that can drift. `test_every_firing_path_announces_itself.gd` enumerates the
## paths and fails when an unlisted one appears.
##
## ## The vocabulary is neutral, and the method is data
##
## `weapon_used`, not `fired`. A stab resolves through the identical path and *fired* is the
## wrong word for it, so the event kind says only that a weapon was employed and `method`
## carries how — an **open `StringName` vocabulary**, so a designer adding a weapon that
## delivers its damage some new way adds a method, not a code branch.
##
## **`burst_fired` is unaffected and stays.** It is a per-burst *summary* that `LogFold` reads
## to fold a burst's impacts into one line, and it answers a different question than "a
## trigger was pulled": one `burst_fired` covers the several `weapon_used` events a burst's
## own pulls emit.

const KIND: StringName = &"weapon_used"

## The open method vocabulary. **Never an enum** — this is content, and a weapon that stabs,
## saws, sprays or lobs is a `.tres` away.
const METHOD_FIRE: StringName = &"fire"
const METHOD_THRUST: StringName = &"thrust"
const METHOD_SWING: StringName = &"swing"
const METHOD_GRIND: StringName = &"grind"

## Which firing path took the shot. Diagnostic provenance — a reader asking "was this
## overwatch or a queued attack" should not have to infer it from what else is in the log.
var path: StringName
var attacker_id: int
## The muzzle point in plane space, and the direction the round actually travels. **Read back
## out by the resolver rather than passed alongside it**, so the announcement and the
## resolution cannot describe different shots.
var origin: Vector2
var direction: Vector2
## **The unit's own facing at the moment of the shot, in radians.** Carried because
## `BR54.01` is precisely the angle between where a unit is pointed and where its round went,
## and without facing in the event that angle has to be inferred all over again.
var facing: float
var weapon_id: StringName
var method: StringName

var _announced: bool = false


func _init(
	p_path: StringName,
	p_attacker_id: int,
	p_origin: Vector2,
	p_direction: Vector2,
	p_facing: float,
	p_weapon_id: StringName,
	p_method: StringName = METHOD_FIRE
) -> void:
	path = p_path
	attacker_id = p_attacker_id
	origin = p_origin
	direction = p_direction
	facing = p_facing
	weapon_id = p_weapon_id
	method = p_method


## **Once per trigger pull, not once per projectile.** A shotgun pull resolves nine pellets
## through nine `resolve_and_log_point` calls and they share one announcement, so the log
## reads as one shot rather than nine. A caller that genuinely fires independently per
## projectile builds an announcement per projectile — that is its choice, expressed by how
## many it constructs, rather than a flag this class has to interpret.
##
## Silent under `is_preview`, the same posture every other resolution emit takes: TACTICS
## queues intents and mutates nothing, and a speculative shot has not been taken.
func announce_once(state: CombatState) -> void:
	if _announced:
		return
	_announced = true
	if state.is_preview:
		return
	(
		state
		. combat_log
		. emit(
			(
				LogEvent
				. new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					attacker_id,
					KIND,
					{
						"path": path,
						"weapon": weapon_id,
						"method": method,
						"origin": origin,
						"direction": direction,
						"facing": facing,
						"travel": travel_angle(),
						"off_facing": off_facing_degrees(),
					},
					(
						"unit %d %s %s toward %.1f deg (facing %.1f, %.1f off)"
						% [
							attacker_id,
							_verb(),
							weapon_id,
							rad_to_deg(travel_angle()),
							rad_to_deg(facing),
							off_facing_degrees(),
						]
					)
				)
			)
		)
	)


## The direction of travel as an angle, in the same convention `Unit.orientation` uses, so the
## two are directly comparable — which is the whole reason both are in the event.
func travel_angle() -> float:
	return atan2(direction.x, direction.y)


## **`BR54.01` as a number in the log rather than a reconstruction.** The signed magnitude of
## the angle between where the unit is pointed and where the round went, wrapped to
## `[0, 180]`, in degrees.
func off_facing_degrees() -> float:
	return absf(rad_to_deg(wrapf(travel_angle() - facing, -PI, PI)))


func _verb() -> String:
	match method:
		METHOD_THRUST:
			return "thrusts"
		METHOD_SWING:
			return "swings"
		METHOD_GRIND:
			return "grinds"
	return "fires"
