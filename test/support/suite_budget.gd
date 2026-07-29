class_name SuiteBudget
extends RefCounted

## taskblock-47 Pass B: **a budget on the work the suite does, gated on counts rather
## than on seconds.**
##
## ## Why not seconds
##
## A wall-clock threshold is machine-dependent, and the recorded response to a flaky
## threshold in this project is to raise the constant — `MIN_COMPLETION_RATE` went
## 0.5 to 0.25 to 0.35 that way, and the file limit in `run_tests.sh` was raised eight
## times before anyone deleted the thing that needed it. taskblock-47 Pass A measured
## the case directly: **two runs of identical work came out at 1286 s and 1493 s**, a
## 16% spread with nothing changed between them. A budget with that much noise in it
## teaches people to ignore it.
##
## Work counts have no such spread — Pass A asserts they are identical across runs —
## and they name the cause. taskblock-46's search-memory fix took mean turns per bout
## 19.1 to 26.8 and every bout-running test inherited it. **A turns budget would have
## gone red on the commit that caused it.** A seconds budget would have gone red three
## commits later, on whichever change happened to cross the line, and the investigation
## would have started in the wrong place.
##
## ## A ratchet, not a ceiling
##
## Going over is not forbidden — it is a decision. Raise the number and say why in the
## same commit; that is the whole mechanism. What it prevents is *drift*, where no
## single change looked expensive and the total quadrupled anyway, which is exactly
## what happened between taskblock-45 and taskblock-46.
##
## **And it ratchets down too.** taskblock-47 Pass E cuts work; these numbers come
## down with it, or the budget stops describing the suite.

## Headroom over the measured baseline, as a fraction. **Sized from what it has to
## catch, not picked for feeling generous.**
##
## | headroom | trips on | ordinary bout tests before tripping |
## |---|---|---|
## | 5% | almost anything | ~7 |
## | **15%** | **a systemic change** | **~22** |
## | 40% | nothing that has happened | ~58 |
##
## The two ends are set by real events. taskblock-46's search-memory change raised
## turns per bout by **40%** across every bout-running test at once, so headroom has
## to sit meaningfully below that or the budget cannot see the class of change it
## exists for. At the other end, a newly added bout test costs roughly 2 bouts and 30
## turns — 0.7% of the turn baseline — so 15% leaves room for about twenty of them
## before anyone has to think about it, which is more than a taskblock adds.
const HEADROOM := 0.15

## The Pass A baseline these are derived from, kept as the raw measurement so a later
## re-ratchet can see what moved rather than only what the limit became.
##
## Regenerate with `godot --headless --path . -s res://tools/profile_suite.gd`.
const BASELINE: Dictionary = {
	"bouts": 62,
	"turns": 1578,
	"plans": 1456,
	"candidates": 2068318,
	"shot_planes": 19599,
	"floods": 6032,
}

## Which counters are actually gated. **`candidates` and `shot_planes` are measured
## and reported but deliberately NOT gated**: they are consequences of how the planner
## scores, not of how much the suite asks it to do, so an AI change that legitimately
## scores differently would fail a test about suite cost — a false positive that
## teaches people to raise the number, which is the failure mode this whole file is
## written against. Bouts and turns are the ones the suite controls.
const GATED: Array[String] = ["bouts", "turns", "floods"]

## Per-file caps for the files that dominate. **The suite total alone is not enough**:
## a file could double while another halved and the total would sit still, which is
## precisely the drift being guarded against. Only files that build bouts get an
## entry — everything else is noise against these.
##
## Values are the current measurement with the same headroom applied, rounded up.
## **Re-ratcheted twice**: at Pass C, where `SAMPLE_SEEDS` 20 → 8 took the sampler file
## from 88 bouts to 40, and again at Pass E, where retargeting and merging took it to
## 24. Leaving either set of old numbers behind would have left most of the budget as
## slack in the two files that matter most — a ratchet that only goes up is a ceiling.
const PER_FILE: Dictionary = {
	"res://test/unit/logic/test_completion_sampler.gd": {"bouts": 28, "turns": 873},
	"res://test/integration/test_full_mission.gd": {"bouts": 10, "turns": 412},
	"res://test/unit/view/overlays/test_ai_batch_yield.gd": {"bouts": 4, "turns": 136},
	"res://test/unit/logic/ai/test_batch_plumbing.gd": {"bouts": 6, "turns": 37},
}


## The budget for `counter`, as a whole number — the baseline plus headroom.
static func limit_for(counter: String) -> int:
	return int(ceil(float(int(BASELINE.get(counter, 0))) * (1.0 + HEADROOM)))


## Every way `profile` exceeds its budget, as messages ready to print.
##
## **Returns all of them rather than the first.** A change that pushes three files
## over is one investigation, and reporting it as three consecutive red runs turns it
## into three.
##
## `profile` is `tools/profile_suite.gd`'s JSON: `{"totals": {...}, "files": [...]}`.
static func violations(profile: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var totals: Dictionary = profile.get("totals", {})
	for counter: String in GATED:
		var observed: int = int(totals.get(counter, 0))
		var limit: int = limit_for(counter)
		if observed > limit:
			(
				found
				. append(
					(
						"suite %s: %d over a budget of %d (baseline %d + %d%% headroom, +%d)"
						% [
							counter,
							observed,
							limit,
							int(BASELINE.get(counter, 0)),
							int(HEADROOM * 100.0),
							observed - limit,
						]
					)
				)
			)
	for row: Dictionary in profile.get("files", []):
		var path: String = String(row.get("path", ""))
		if not PER_FILE.has(path):
			continue
		var caps: Dictionary = PER_FILE[path]
		for counter: String in caps:
			var observed: int = int(row.get(counter, 0))
			var limit: int = int(caps[counter])
			if observed > limit:
				# **The file and the delta, never just the total.** "The suite got
				# more expensive" is not something anyone can act on; "this file did,
				# by this much" is.
				found.append(
					(
						"%s %s: %d over a budget of %d (+%d)"
						% [
							path.replace("res://test/", ""),
							counter,
							observed,
							limit,
							observed - limit
						]
					)
				)
	return found


## Files that build a bout, read from the profile rather than from a directory glob.
## taskblock-47 Pass C gates the fast tier on this: **a glob goes stale the moment
## someone adds a bout to a unit test**, and the counter cannot.
static func bout_building_files(profile: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	for row: Dictionary in profile.get("files", []):
		if int(row.get("bouts", 0)) > 0:
			paths.append(String(row.get("path", "")))
	paths.sort()
	return paths
