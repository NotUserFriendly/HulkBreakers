class_name SuiteTier
extends RefCounted

## taskblock-47 Pass C: **two gates, because they answer different questions.**
##
## - **Fast** — the per-change loop. Everything that does not build a bout, which is
##   the overwhelming majority of the suite at a small fraction of its cost. This is
##   what you run after an edit.
## - **Full** — the per-pass loop. Everything, bouts included. Green before a pass is
##   committed, which is the standing rule and is not relaxed by any of this.
##
## The full gate is a strict superset: the fast gate is the full one minus the files
## that build bouts, so nothing exists only in the fast tier and nothing can be lost
## by running the slow one.
##
## ## Why the tier is a list of files rather than a directory
##
## The obvious implementation is "skip `integration/`". It is wrong today, not
## hypothetically: **eleven of the twelve bout-building files live under `unit/`**,
## including the most expensive file in the whole suite. A directory rule would have
## declared the fast gate bout-free while it played nearly all of them.
##
## So the list is explicit, and `test_suite_tier.gd` checks it against the profile's
## own bout counter every run. **Adding a bout to a unit test makes that test fail**
## rather than quietly making the fast gate slow — which is the failure this design
## exists to prevent, since a fast gate that has silently stopped being fast is worse
## than no fast gate at all.

## Set by `run_tests.sh fast`. An environment variable rather than a command-line
## flag because GUT owns the command line and this has to be readable from inside a
## test script's `should_skip_script()`.
const FAST_GATE_ENV := "HB_FAST_GATE"

## Files skipped by the fast gate — **every file that builds a bout, and nothing
## else.** Kept as a fixture rather than derived at runtime: the profile is a
## measurement of the last run, and a gate that decided what to skip by reading it
## would change behaviour depending on how stale that file was.
const BOUT_FILES: Array[String] = [
	"res://test/integration/test_full_mission.gd",
	"res://test/unit/logic/ai/test_batch_plumbing.gd",
	"res://test/unit/logic/ai/test_bout_setup.gd",
	"res://test/unit/logic/ai/test_plan_pacer.gd",
	"res://test/unit/logic/ai/test_utility_planner.gd",
	"res://test/unit/logic/test_bout_corpus.gd",
	"res://test/unit/logic/test_completion_sampler.gd",
	"res://test/unit/logic/test_replay_handle.gd",
	"res://test/unit/logic/test_watched_run.gd",
	"res://test/unit/logic/test_work_counters.gd",
	"res://test/unit/logic/test_world_view_seam.gd",
	"res://test/unit/view/overlays/test_ai_batch_yield.gd",
	"res://test/unit/view/overlays/test_generate_bout_overlay.gd",
	"res://test/unit/view/test_battle_scene.gd",
	"res://test/unit/view/test_replay_wiring.gd",
]

## Files that read `BoutCorpus` rather than building their own bouts.
##
## **Their measured bout count depends on run order**, which is why they need naming.
## The corpus plays on first touch, so in the full gate `test_full_mission.gd` runs
## first and is charged all eight; `test_bout_corpus.gd` then measures zero. In the fast
## gate the integration file is skipped and the corpus file would pay instead.
##
## So they must be in `BOUT_FILES` — a fast gate that ran one of them would build bouts
## — while the profile will sometimes show them at zero. That is a correct measurement of
## who paid, not a stale entry, and `test_suite_tier.gd` has to tell those apart.
const CORPUS_READERS: Array[String] = [
	"res://test/unit/logic/test_bout_corpus.gd",
]


static func is_fast_gate() -> bool:
	return OS.get_environment(FAST_GATE_ENV) != ""


## What a bout-building test script returns from `should_skip_script()`.
##
## **`Variant`, and that is GUT's contract rather than sloppiness.** `gut.gd` skips on
## *any* String — including an empty one — and only a `bool false` means "run me". The
## first version of this returned `""` for the non-skip case and silently skipped all
## every bout file in the full gate; the suite went green with 11 fewer files in it, which
## is exactly the shape of failure this pass is supposed to prevent.
##
## The reason is spelled out rather than left blank because a skipped test with no
## stated cause reads as a broken test, and someone eventually deletes it.
static func skip_if_fast() -> Variant:
	if not is_fast_gate():
		return false
	return "fast gate: this file builds bouts — run `./run_tests.sh` for the full gate"
