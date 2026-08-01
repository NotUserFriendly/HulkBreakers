class_name SeamSweep
extends RefCounted

## The instrument `BR34.05` ("misses vanish instead of striking anything") and
## `PLAN.md`'s *Wide scatter passing through a wall seam* are both judged
## against. The supervisor's standing rule is that **a shot fired inside an
## enclosed room must hit something**; until taskblock-52 that rule had no
## runnable form, so no change could be shown to have satisfied it.
##
## taskblock-35 reproduced the seam at **56/200 empties at a lateral offset of
## ~8** with a harness that was never committed. An uncommitted measurement is
## not a baseline — it cannot be re-taken, and a later "the seam is closed" would
## be an assertion against a remembered number. This is that experiment,
## committed and rerunnable.
##
## **Parameterised by the thing that fires**, so the shot plane and the ray chain
## are measured by one instrument rather than by two that could disagree about
## what "empty" means. `fire` answers exactly one question — *did this shot
## resolve against anything at all* — which is the miss condition itself, not a
## proxy for it.
##
## **Zero damage by default, and that is what makes it non-destructive.** Whether
## a shot lands is decided by region lookup (`DamageResolver._find_next` /
## the ray march), never by how much damage it carries; damage only decides what
## happens *after* something is found. So a zero-damage probe asks the identical
## question and leaves the room intact — 200 real shots would chew the walls
## being measured, and every shot after the first breach would be sweeping a
## different room. `test_seam_sweep.gd` asserts the room survives a full sweep.
##
## Reports counts and never asserts, the same posture `DeterminismCheck` takes.

## The recorded taskblock-35 experiment's own shape: 200 shots reaching a lateral
## offset of 8. Kept as a named constant rather than inlined into the baseline
## test, because the point of it is to be *the same experiment* across blocks.
const LEGACY_ANGLES := 20
const LEGACY_LATERAL_SAMPLES := 10
const LEGACY_LATERAL_MAX := 8.0

const DEFAULTS := {
	"angles": 20,
	"lateral_max": 8.0,
	"lateral_samples": 10,
	"height": 1.0,
	"bands": 4,
	"first_angle": 0.0,
	"max_detail": 12,
}


## Fires `angles x lateral_samples` shots from `origin` and counts how many
## resolved against nothing.
##
## Angles sweep a full circle from `first_angle`; lateral offsets sweep the
## signed range `[-lateral_max, +lateral_max]` inclusive, which is what makes the
## seam reachable at all — the recorded reproduction only ever saw empties once
## `|x|` passed ~4-5, and a sweep that never leaves the centre cannot see the
## defect it exists to measure.
##
## `fire.call(origin: Vector2, direction: Vector2, point: Vector2) -> bool` —
## true iff the shot resolved against something.
static func run(origin: Vector2, config: Dictionary, fire: Callable) -> Dictionary:
	var settings: Dictionary = DEFAULTS.duplicate()
	settings.merge(config, true)

	var angles: int = settings["angles"]
	var samples: int = settings["lateral_samples"]
	var lateral_max: float = settings["lateral_max"]
	var height: float = settings["height"]
	var band_count: int = settings["bands"]
	var first_angle: float = settings["first_angle"]
	var max_detail: int = settings["max_detail"]

	var bands: Array[Dictionary] = []
	for b in range(band_count):
		(
			bands
			. append(
				{
					"lo": lateral_max * float(b) / float(band_count),
					"hi": lateral_max * float(b + 1) / float(band_count),
					"shots": 0,
					"empties": 0,
				}
			)
		)

	var shots := 0
	var empties := 0
	var detail: Array[Dictionary] = []

	for a in range(angles):
		var angle: float = first_angle + TAU * float(a) / float(angles)
		var direction := Vector2(cos(angle), sin(angle))
		for s in range(samples):
			var lateral: float = _lateral_at(s, samples, lateral_max)
			var hit: bool = fire.call(origin, direction, Vector2(lateral, height))
			shots += 1
			var band: Dictionary = _band_for(bands, absf(lateral))
			band["shots"] += 1
			if not hit:
				empties += 1
				band["empties"] += 1
				if detail.size() < max_detail:
					(
						detail
						. append(
							{
								"angle_deg": rad_to_deg(angle),
								"lateral": lateral,
								"height": height,
							}
						)
					)

	return {
		"shots": shots,
		"empties": empties,
		"empty_rate": 0.0 if shots == 0 else float(empties) / float(shots),
		"bands": bands,
		"detail": detail,
		"lateral_max": lateral_max,
		"height": height,
	}


## The signed lateral offset for sample `index` of `count`, spanning
## `[-lateral_max, +lateral_max]` inclusive. A single sample sits at the centre
## (0.0) rather than at an arbitrary end of the range.
static func _lateral_at(index: int, count: int, lateral_max: float) -> float:
	if count <= 1:
		return 0.0
	return -lateral_max + 2.0 * lateral_max * float(index) / float(count - 1)


## The band holding `magnitude`. The top band is closed on its upper edge so a
## sample landing exactly on `lateral_max` is counted rather than dropped.
static func _band_for(bands: Array[Dictionary], magnitude: float) -> Dictionary:
	for band: Dictionary in bands:
		if magnitude < band["hi"]:
			return band
	return bands[bands.size() - 1]


## The report as a text table for the test log — CC cannot see the board, so a
## spatial measurement that only exists as a return value is one nobody can read
## (CLAUDE.md: "a spatial system without a dump is one nobody can verify").
static func describe(report: Dictionary, label: String = "") -> String:
	var lines: Array[String] = []
	(
		lines
		. append(
			(
				"=== seam sweep%s: %d/%d empty (%.1f%%), lateral +/-%.1f at height %.2f ==="
				% [
					"" if label.is_empty() else " [%s]" % label,
					report["empties"],
					report["shots"],
					100.0 * report["empty_rate"],
					report["lateral_max"],
					report["height"],
				]
			)
		)
	)
	lines.append("  |lateral|        shots  empty   rate")
	for band: Dictionary in report["bands"]:
		var rate: float = (
			0.0 if band["shots"] == 0 else 100.0 * float(band["empties"]) / float(band["shots"])
		)
		lines.append(
			(
				"  %5.2f - %5.2f   %6d %6d %6.1f%%"
				% [band["lo"], band["hi"], band["shots"], band["empties"], rate]
			)
		)
	if not (report["detail"] as Array).is_empty():
		lines.append("  first empties (angle deg, lateral):")
		for entry: Dictionary in report["detail"]:
			lines.append("    %7.1f deg  lateral %+6.2f" % [entry["angle_deg"], entry["lateral"]])
	return "\n".join(lines)
