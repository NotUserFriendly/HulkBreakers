class_name ResolverDifferential
extends RefCounted

## taskblock-52 hard pause: **the same seeded shots through both models, and every
## case where they disagree.**
##
## Disagreements are *expected* — the ray is more correct, and a replacement that
## agreed everywhere would not be worth making. The bar the taskblock sets is that
## each one is **explicable**, and that an inexplicable one is a defect in the new
## path rather than a curiosity.
##
## ## Each shot runs against its own board
##
## Resolution mutates: it damages parts, destroys cover, ejects matrices. Running
## the plane and then the chain over one board would measure the chain against a
## world the plane had already chewed. So every comparison builds two independent
## states from the same seed and fires one shot into each — which also means the
## RNG stream each model draws its crit roll from starts in the same place.
##
## ## What "disagree" means, and what it deliberately does not
##
## Compared: whether anything was hit at all, how many hops, and per hop the part
## struck and the outcome. **Not compared: exact hit coordinates.** The two models
## express a hit in genuinely different geometry — the plane's `depth` is a
## ground-plane distance and the chain's is a true 3D one — so comparing
## coordinates would report a disagreement on every single shot and drown the
## real ones.

## One classified difference, so the report can group rather than list 400 lines.
const KIND_AGREE: StringName = &"agree"
const KIND_PLANE_ONLY: StringName = &"plane_hit_ray_missed"
const KIND_RAY_ONLY: StringName = &"ray_hit_plane_missed"
const KIND_DIFFERENT_PART: StringName = &"different_part"
const KIND_DIFFERENT_OUTCOME: StringName = &"different_outcome"
const KIND_DIFFERENT_HOPS: StringName = &"different_hop_count"


## Runs `shots` through both models and returns a classified report.
##
## `build_state` is a `Callable() -> CombatState` — called **twice per shot**, so
## it must produce an identical, independent board every time. `shots` is an
## `Array[Dictionary]` of `{origin: Vector2, direction: Vector2, point: Vector2,
## damage: float, point_depth: float}`; a shot is described the way the *plane*
## takes one, because that is the input production code actually produces, and the
## chain's own input is derived from it through the single shared conversion in
## `ShotResolution`.
static func run(build_state: Callable, shots: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	var cases: Array[Dictionary] = []

	for index in range(shots.size()):
		var shot: Dictionary = shots[index]
		var plane: Array[ImpactResult] = _fire(
			build_state.call(), shot, ShotResolution.RESOLVER_PLANE
		)
		var ray: Array[ImpactResult] = _fire(build_state.call(), shot, ShotResolution.RESOLVER_RAY)
		var kind: StringName = _classify(plane, ray)
		counts[kind] = int(counts.get(kind, 0)) + 1
		if kind != KIND_AGREE:
			(
				cases
				. append(
					{
						"index": index,
						"kind": kind,
						"shot": shot,
						"plane": _describe(plane),
						"ray": _describe(ray),
					}
				)
			)

	return {
		"shots": shots.size(),
		"agreed": int(counts.get(KIND_AGREE, 0)),
		"counts": counts,
		"cases": cases,
	}


static func _fire(
	state: CombatState, shot: Dictionary, resolver: StringName
) -> Array[ImpactResult]:
	var shooter: Unit = state.units[0]
	return ShotResolution.resolve_point(
		state,
		shooter,
		shot["origin"],
		shot["direction"],
		shot["point"],
		shot.get("damage", 0.0),
		0.0,
		0.0,
		shot.get("origin_height", 1.0),
		DamageResolver.DEFLECT_MODE_RICOCHET,
		0.0,
		0.0,
		shot.get("point_depth", 0.0),
		resolver
	)


## **Compared by identity of the thing struck, not by object identity of the
## `Part`.** Each shot runs against its own independently built board, so the two
## `wall` Parts at one cell are different *instances* even when they are the same
## wall. The first version of this compared `region.part` by reference and
## reported 152 of 216 shots as `different_part` while the printed detail showed
## both models striking `wall/STOP_DEAD` — a comparator bug that would have read
## as a catastrophic parity failure.
##
## Identity here is **part id plus the cell the round landed in**, which is
## exactly the attribution question a hit answers ("which cell takes the damage").
## Both models stamp `hit_point` in cell space, so rounding it is a fair
## comparison rather than the coordinate-exact one this class deliberately avoids.
static func _classify(plane: Array[ImpactResult], ray: Array[ImpactResult]) -> StringName:
	if plane.is_empty() and ray.is_empty():
		return KIND_AGREE
	if ray.is_empty():
		return KIND_PLANE_ONLY
	if plane.is_empty():
		return KIND_RAY_ONLY
	if _struck(plane[0]) != _struck(ray[0]):
		return KIND_DIFFERENT_PART
	if plane[0].outcome != ray[0].outcome:
		return KIND_DIFFERENT_OUTCOME
	if plane.size() != ray.size():
		return KIND_DIFFERENT_HOPS
	return KIND_AGREE


## "What was struck, and where" — the pair that identifies a hit across two
## independently built boards.
static func _struck(result: ImpactResult) -> String:
	return (
		"%s@(%d,%d)"
		% [
			result.region.part.id,
			roundi(result.hit_point.x),
			roundi(result.hit_point.y),
		]
	)


static func _describe(results: Array[ImpactResult]) -> String:
	if results.is_empty():
		return "nothing"
	var parts: Array[String] = []
	for result: ImpactResult in results:
		parts.append("%s/%s" % [_struck(result), Enums.Outcome.keys()[result.outcome]])
	return ", ".join(parts)


## The report as a text block for the test log — CC cannot see the board, so a
## comparison that exists only as a return value is one nobody can read.
static func describe(report: Dictionary, label: String = "") -> String:
	var lines: Array[String] = []
	(
		lines
		. append(
			(
				"=== resolver differential%s: %d shots, %d agreed (%.1f%%) ==="
				% [
					"" if label.is_empty() else " [%s]" % label,
					report["shots"],
					report["agreed"],
					(
						0.0
						if report["shots"] == 0
						else 100.0 * float(report["agreed"]) / report["shots"]
					),
				]
			)
		)
	)
	var counts: Dictionary = report["counts"]
	for kind: StringName in counts:
		lines.append("  %-24s %d" % [kind, counts[kind]])
	var shown := 0
	for entry: Dictionary in report["cases"]:
		if shown >= 12:
			lines.append("  ... and %d more" % (report["cases"].size() - shown))
			break
		var shot: Dictionary = entry["shot"]
		(
			lines
			. append(
				(
					"  #%-4d %-22s lateral %+5.2f  plane: %s  |  ray: %s"
					% [
						entry["index"],
						entry["kind"],
						(shot["point"] as Vector2).x,
						entry["plane"],
						entry["ray"],
					]
				)
			)
		)
		shown += 1
	return "\n".join(lines)
