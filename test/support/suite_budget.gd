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

## **`turns` here is the suite total MINUS `TURNS_EXCLUDED`.** The baseline these are
## derived from, kept as the raw measurement so a later
## re-ratchet can see what moved rather than only what the limit became.
##
## Regenerate with `godot --headless --path . -s res://tools/profile_suite.gd`.
##
## ## taskblock-56 Pass F: `ui_builds` 344 -> 627, and most of that is not this pass
##
## The ratchet says raise the number and say why in the same commit, so: **the committed
## profile was last regenerated at taskblock-52** (commit `de676fe`), and the per-taskblock
## regeneration was skipped for 53, 54, 55 and 56 A-E. Regenerating it here surfaced four
## taskblocks of growth at once, which is exactly the drift the budget exists to catch and
## exactly what a stale profile hides — the guard reads the committed file, not the live run.
##
## **Measured per file against the tb52 profile**, so the growth names its own causes rather
## than arriving as one number:
##
## | file | +ui_builds | from |
## |---|---|---|
## | `test_editor_mode.gd` | **63** | **this pass** — the editor mode is a new mounted surface |
## | `test_view_modes.gd` | 38 | tb56 D — mounts every mode in the table |
## | `test_spectator_overlay.gd` | 36 | tb56 C/D |
## | `test_resolution_player.gd` | 33 | tb56 C/D |
## | `test_squad_control_overlay.gd` | 15 | tb56 C/D |
## | eleven others | 47 | tb53-56, none over 9 |
##
## So Pass F is **63 of the 232**, and the other 169 landed before it and were never
## reflected here. The number is raised to the honest current measurement rather than to
## something that would have passed — and the lesson is about the *cadence*, not the size:
## a profile regenerated per taskblock would have reported each of these against the change
## that caused it, which is the whole argument in this file's own header.
##
## Nothing else moved past its limit: `bouts` 54 -> 57 against a 64 ceiling, and the gated
## turn total is still inside its headroom.
## **Re-ratcheted at the tb64 audit rebuild, and most of the growth was not tb64's.**
##
## The committed profile had not been regenerated since taskblock-56, and this budget reads that
## profile — so eight blocks of accumulated work sat under a baseline that could not see it.
## Regenerating surfaced five violations at once. Measured contribution of tb64's own new files:
## **2 bouts, ~14 turns, ~11k candidates, ~35 floods, 0 ui_builds** — against overshoots of +11
## bouts, +175 turns, +267 floods and +545 ui_builds. The ratchet is being raised to what the
## suite now measures, not to accommodate this block.
##
## `plans`, `candidates` and `shot_planes` are re-recorded from the same run for consistency even
## though `GATED` does not gate them; leaving three of seven entries eight blocks stale would make
## the table a mix of two measurements and nobody could tell which was which.
##
## ## tb65 Pass F: two new counters, and two old ones that were never controlled
##
## `maps` and `spawns` join the table so the **zero-bout half of the suite** — 308 files and
## 640 s that contributed nothing to any counter here — becomes visible. See `MapGen.
## maps_generated` and `SuiteRun.processes_spawned` for why those two quantities and not
## wall-clock.
##
## **Re-measuring for them exposed a flake this file did not know it had.** `BoutCorpus.sample()`
## is clock-seeded and plays *until the first win*, capped at `CompletionSampler.FIRST_WIN_CAP`
## (9) — so the number of bouts the corpus plays is a random variable, and it lands on whichever
## `SuiteTier.CORPUS_READERS` file touches it first. Measured across two green full gates with
## no relevant code change between them: **`test_watched_run.gd` went 2 bouts / 88 turns /
## 121.9 s to 7 bouts / 246 turns / 279.2 s.** That is a 158-turn swing against 15% headroom on a
## 1063 baseline, and it is the same class of defect `TURNS_EXCLUDED` already existed for.
##
## **The fix was not another exclusion, and it was not a looser baseline either.** Adding the other
## two corpus readers to `TURNS_EXCLUDED` was tried and `test_the_exclusion_list_stays_small_and_
## gates_bouts_regardless` rejected it — the guard doing its job, since three exemptions is a habit.
## Baselining `turns` at the measured *total* was the next attempt and it was also wrong: making the
## full gate write the profile turned the swing into a live flake, because a green run with an
## unlucky draw writes 1131 and the next run then fails a limit of 904.
##
## **`CompletionSampler.sampled_turns` is the answer** — the uncontrolled thing is a *quantity*, not
## a file, and it is now subtracted as one. So `turns` is baselined at the **controlled 496**
## (808 measured minus 312 sampled), which is tighter than the 1063 it replaces by a factor of two
## and does not move with the draw.
##
## **`bouts` is left gated too**: the corpus can add at most `FIRST_WIN_CAP` (9) and 15% of 85 is
## 12, so the headroom covers it where a 158-turn swing it plainly could not.
##
## Making the corpus's own turn count observable would let `turns` come down by roughly 250 —
## queued in `PLAN.md` rather than bodged here.
##
## Numbers below are the tb65 full gate, 363 scripts / 3547 tests / 0 failures / 1255.7 s.
const BASELINE: Dictionary = {
	"bouts": 85,
	"turns": 496,
	"plans": 571,
	"candidates": 1292621,
	"shot_planes": 9187,
	"floods": 5128,
	"ui_builds": 1267,
	"maps": 941,
	# tb66 Pass F: 25 -> 32. **All seven are this block's own**, and they are named rather than
	# absorbed: `test_merge_shards.gd` drives `tools/merge_shards.py` as a real subprocess seven
	# times (six tests, one of which runs it twice) to prove the merge cannot report green on a
	# killed shard. Spawning is the thing under test there, so the cost is irreducible.
	#
	# **The ratchet caught this exactly as designed, one run late, and that is the mechanism
	# working.** The full gate that *wrote* the new profile read the old one and passed; the very
	# next gate read the new numbers and went red. Drift lands, then is reported against the
	# baseline it broke — which is why taskblock-65 made the full gate write the profile at all.
	"spawns": 32,
}

## Files whose **turns** are excluded from the gated suite total.
##
## `test_full_mission.gd` seeds its sample from the clock on purpose — taskblock-46
## spent a pass establishing that, because a fixed window was measuring the wrong
## thing. The consequence is that its turn count is not a controlled quantity: eight
## bouts that each end somewhere between ~10 turns and the 100-turn cap.
##
## **Measured across three full runs the suite total came out at 1680, 1578 and 1385
## turns — a 19% spread against 15% headroom.** Gating that total on turns is
## therefore gating on which seeds came up, and the budget would have gone red on
## nobody's change. Its *bouts* stay gated, because that count is exactly
## `SAMPLE_SEEDS` and is entirely deterministic.
##
## This is the honest version of a flaky threshold: not "raise the number until it
## stops", but "this quantity was never something the suite controls".
## tb65 Pass F tried to add the other two `SuiteTier.CORPUS_READERS` here and
## `test_the_exclusion_list_stays_small_and_gates_bouts_regardless` refused it — correctly.
## **The guard is the better judgement**: an exemption is a hole in the gate, and the answer to
## "this counter moved for a reason I do not control" is not to widen the hole until nothing trips.
##
## tb65 close-out: **the right exclusion turned out not to be a file at all.** What is
## uncontrolled is the *sampler's own turns* — clock-drawn seeds, stopped at the first completion
## — and that cost lands on whichever corpus reader runs first, which failure-history reordering
## changes between runs. So a filename was only ever a proxy for a quantity, and
## `CompletionSampler.sampled_turns` is the quantity. This list stays at one entry and is now
## belt-and-braces: `test_full_mission.gd`'s turns are already inside `sampled_turns`.
const TURNS_EXCLUDED: Array[String] = ["res://test/integration/test_full_mission.gd"]

## Which counters are actually gated. **`candidates` and `shot_planes` are measured
## and reported but deliberately NOT gated**: they are consequences of how the planner
## scores, not of how much the suite asks it to do, so an AI change that legitimately
## scores differently would fail a test about suite cost — a false positive that
## teaches people to raise the number, which is the failure mode this whole file is
## written against. Bouts and turns are the ones the suite controls.
## `ui_builds` joins them at taskblock-48 Pass D: it is the only gated counter that is
## **not** AI work, and it exists because a view-only regression could not fail a budget
## before. `test_spectator_overlay.gd` costs 33 s with zero bouts, so the suite's most
## expensive non-bout file was invisible to the thing meant to notice files getting
## expensive.
## tb65 Pass F: `maps` and `spawns` join them — the first counters here that can see a file
## building no bout and mounting no surface. `test_spectator_overlay.gd` (56.6 s, 0 bouts, 36
## maps) and `test_replay_wiring.gd` (22.3 s, 0 bouts, 8 spawns) were both invisible to every
## gated counter except `ui_builds`, which cannot tell an expensive surface from a cheap one.
const GATED: Array[String] = ["bouts", "turns", "floods", "ui_builds", "maps", "spawns"]

## Per-file caps for the files that dominate. **The suite total alone is not enough**:
## a file could double while another halved and the total would sit still, which is
## precisely the drift being guarded against. Only files that build bouts get an
## entry — everything else is noise against these.
##
## Values are the current measurement with the same headroom applied, rounded up.
## A `turns` entry for a file in `TURNS_EXCLUDED` is ignored — kept in the table as a
## record of what it measured, not as a limit.
## tb65 Pass F: **"only files that build bouts get an entry" no longer holds**, and it was the
## rule that made the zero-bout half unbudgetable per file as well as in aggregate.
## **Re-ratcheted at every pass that moved the numbers**: taskblock-47 Pass C took the
## sampler file from 88 bouts to 40 via `SAMPLE_SEEDS` 20 → 8, Pass E took it to 24 by
## retargeting and merging, and taskblock-48 Pass C took it to 10 with the shared corpus
## and canned records. Leaving any of those old numbers behind would have left most of
## the budget as slack — a ratchet that only goes up is a ceiling.
const PER_FILE: Dictionary = {
	"res://test/unit/logic/test_completion_sampler.gd": {"bouts": 12, "turns": 351},
	"res://test/integration/test_full_mission.gd": {"bouts": 10, "turns": 409},
	# tb64 audit rebuild: 493 turns measured against a 136 cap set at taskblock-48. Nothing in
	# tb64 touched this file — the cap simply had not been re-read since the profile went stale,
	# and this is the suite's single most expensive file at 279.9 s (19.6% of the full gate).
	# tb65 Pass D took this file from 493 turns to 48 and 279.9 s to 22.4 s. Ratcheted down with
	# it — a cap left at 493 would be pure slack, and this file is exactly the one that proved a
	# stale cap hides growth for eight blocks.
	"res://test/unit/view/overlays/test_ai_batch_yield.gd": {"bouts": 4, "turns": 56},
	"res://test/unit/logic/ai/test_batch_plumbing.gd": {"bouts": 6, "turns": 37},
	# tb65 Pass F: **the first per-file caps on files that build no bout**, which is the whole
	# point of the two new counters. Measured, plus the same 15% headroom, rounded up.
	"res://test/unit/logic/test_map_gen.gd": {"maps": 235},
	"res://test/unit/view/test_battle_scene.gd": {"maps": 95},
	"res://test/unit/logic/test_map_gen_reachability.gd": {"maps": 58},
	"res://test/unit/view/overlays/test_spectator_overlay.gd": {"maps": 42},
	"res://test/unit/logic/test_suite_run.gd": {"spawns": 10},
	"res://test/unit/test_run_suite.gd": {"spawns": 10},
	"res://test/unit/view/test_replay_wiring.gd": {"spawns": 10},
}


## The budget for `counter`, as a whole number — the baseline plus headroom.
##
## **`-1` for a gated counter with no baseline**, rather than silently treating it as a
## budget of zero. Adding `ui_builds` to `GATED` without adding it here crashed the whole
## run: the missing key raised a runtime error, and under `-d` that is a debugger break
## which hangs rather than fails. A sentinel makes it a named failure instead.
static func limit_for(counter: String) -> int:
	if not BASELINE.has(counter):
		return -1
	return int(ceil(float(int(BASELINE[counter])) * (1.0 + HEADROOM)))


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
		if counter == "turns":
			# tb65 close-out: **the sampler's own turns come off first, as a quantity.** They are
			# clock-drawn and stop at the first completion, so they swing by hundreds between
			# identical runs and are charged to whichever corpus reader ran first.
			#
			# **The file exclusion below is now redundant rather than belt-and-braces, and the
			# distinction matters.** `test_full_mission.gd` reaches its bouts through `BoutCorpus`,
			# so its turns are already inside `sampled_turns` — subtracting both would double-count
			# them. It measures **0 turns** in every profile taken since tb64 for exactly that
			# reason (another corpus reader always plays first), so the double-subtraction is zero
			# in practice. It is kept because `test_suite_budget.gd`'s own exclusion tests are
			# written against the list, not because it still carries the rule.
			observed -= int(totals.get("sampled_turns", 0))
			observed -= _excluded_turns(profile)
		var limit: int = limit_for(counter)
		if limit < 0:
			found.append(
				"%s is gated but has no BASELINE entry — add one, measured not guessed" % counter
			)
			continue
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
			# **The exclusion applies here too, or it is not a rule.** A quantity the
			# suite does not control is no more budgetable per file than in aggregate,
			# and gating it in one place while exempting it in the other is the kind of
			# half-applied rule that reads as a bug in whichever half you hit first.
			if counter == "turns" and path in TURNS_EXCLUDED:
				continue
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


## The turns contributed by `TURNS_EXCLUDED`, so the gated total is the part of the
## suite that actually holds still between runs.
static func _excluded_turns(profile: Dictionary) -> int:
	var total := 0
	for row: Dictionary in profile.get("files", []):
		if String(row.get("path", "")) in TURNS_EXCLUDED:
			total += int(row.get("turns", 0))
	return total


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
