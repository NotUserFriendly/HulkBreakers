class_name SuiteProcess
extends RefCounted

## tb65 Pass F: **the one place a test spawns a real process, so the suite can count them.**
##
## ## Why this counter exists at all
##
## `test_suite_budget.gd` gates on bouts, turns, floods and ui_builds. `test_suite_run.gd` and
## `test_run_suite.gd` cost **36.7 s between them and report zero on every single one of those**
## — they build no bout, resolve no turn, run no flood and mount no surface. They are the purest
## example of the invisible half of the suite: 308 files and 640 s that no budget can see, which
## grew 3.3× between taskblock-56 and taskblock-64 with every gate green throughout.
##
## **A spawn is the most expensive unit of work in the suite per occurrence.** Each one pays
## `run_tests.sh`'s whole floor — gdlint, an import pass, GUT startup — measured at roughly
## **3.7 s for a targeted run** (taskblock-48 A1). Ten of them is most of a minute. So this
## counter is small, and a single new one moving it by one is worth knowing about in a way that
## one more `ui_build` is not.
##
## ## Why a wrapper rather than counting inside `OS.execute`
##
## `OS.execute` is the engine's, so there is nothing to instrument. The alternative was to leave
## subprocess cost uncounted and gate only on maps, which would have left the two files that
## *most* clearly demonstrate the problem still contributing nothing.
##
## **`test_no_test_spawns_a_process_behind_the_counter`** is what keeps this honest — a
## `VocabularySweep` over `test/` refusing a direct `OS.execute`, the same instrument the
## retired-identifier guards use. A counter something can bypass is a counter that reads low
## and looks green, which is the failure mode the whole budget is written against.


## `OS.execute`, counted. Same arguments, same return value, same blocking behaviour —
## deliberately not a convenience layer, because a wrapper that also *changes* something is one
## a caller has a reason to go around.
static func execute(
	path: String,
	arguments: Array[String],
	output: Array = [],
	read_stderr: bool = false,
	open_console: bool = false
) -> int:
	SuiteRun.processes_spawned += 1
	return OS.execute(path, arguments, output, read_stderr, open_console)


## `OS.create_process`, counted. Returns the pid, or -1.
##
## Separate from `execute` because it is genuinely a different thing — it does not block and it
## does not collect output — and `test_suite_run.gd` deliberately exercises **both**, on the
## stated grounds that agreement between two different spawn paths means something.
static func create_process(
	path: String, arguments: Array[String], open_console: bool = false
) -> int:
	SuiteRun.processes_spawned += 1
	return OS.create_process(path, arguments, open_console)
