class_name SuiteOrder
extends RefCounted

## taskblock-50 Pass E1: **run the tests that fail most often first, so a red run goes red
## early.**
##
## The pain a slow suite causes is not its total runtime — it is *time to first red*. A
## failure at minute nine costs the whole nine minutes before you learn anything; the same
## failure at second twenty costs twenty seconds. Ordering is the cheapest fix available,
## because it changes nothing about what runs.
##
## ## Ordering only. Never skipping.
##
## **A test is never dropped because an indicator passed.** An indicator that stays green
## while the thing it indicates is broken makes the suite greener than the code, and this
## project has hit that four blocks running — once from a single `""` return that silently
## removed eleven bout files from the gate and left it reporting success. Ordering is free
## and safe; skipping is the same hazard at suite scale, and the taskblock rules it out
## explicitly.
##
## `rank()` is therefore a permutation: the same set of scripts comes out, in a different
## sequence. `test_suite_order.gd` asserts that as a property rather than trusting it.
##
## ## The history is local, not committed
##
## Failure frequency is a fact about *this machine's recent runs*, and writing it into a
## tracked file would put churn in every diff and train people to `git checkout` it —
## which the profile artifacts deliberately avoid by only writing on an explicit full-gate
## flag. A learning cache has the opposite need: it has to update on ordinary runs or it
## never learns. So it lives in `out/`, gitignored, and a missing file is normal rather
## than an error — a fresh clone simply runs in declaration order until it has seen a
## failure.

## Where the local history lives. Under `out/` because that directory is already the
## home for local-only artifacts.
const HISTORY_PATH := "res://out/suite_failures.json"


## Scripts ordered most-recently-and-frequently failing first, then everything else in
## its original order.
##
## **Ties keep the incoming order** rather than sorting by path: the incoming order is
## GUT's own discovery order, so an unchanged history means an unchanged run, and a diff
## of two run logs shows only what the history actually moved.
static func rank(scripts: Array[String], history: Dictionary) -> Array[String]:
	var scored: Array[Dictionary] = []
	for i in range(scripts.size()):
		var path: String = scripts[i]
		var record: Dictionary = history.get(path, {})
		(
			scored
			. append(
				{
					"path": path,
					"index": i,
					"fails": int(record.get("fails", 0)),
					"last_failed_run": int(record.get("last_failed_run", -1)),
				}
			)
		)
	scored.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["fails"]) != int(b["fails"]):
				return int(a["fails"]) > int(b["fails"])
			# A file that failed more recently is the better bet among equals.
			if int(a["last_failed_run"]) != int(b["last_failed_run"]):
				return int(a["last_failed_run"]) > int(b["last_failed_run"])
			return int(a["index"]) < int(b["index"])
	)
	var out: Array[String] = []
	for row: Dictionary in scored:
		out.append(String(row["path"]))
	return out


## Fold this run's per-script failure counts into the history and return the new one.
##
## `failed` maps script path to the number of failing tests it had this run. A script that
## passed is recorded too — its `runs` climbs while `fails` does not — so a file that used
## to be flaky and has since been fixed sinks back down the order instead of sitting at
## the top forever.
static func fold(history: Dictionary, failed: Dictionary, run_number: int) -> Dictionary:
	var merged: Dictionary = history.duplicate(true)
	for path: String in failed:
		var record: Dictionary = merged.get(path, {"fails": 0, "runs": 0, "last_failed_run": -1})
		record["runs"] = int(record.get("runs", 0)) + 1
		if int(failed[path]) > 0:
			record["fails"] = int(record.get("fails", 0)) + 1
			record["last_failed_run"] = run_number
		merged[path] = record
	merged["__run"] = run_number
	return merged


static func load_history() -> Dictionary:
	if not FileAccess.file_exists(HISTORY_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HISTORY_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


static func save_history(history: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file == null:
		# A history that cannot be written is not worth failing a run over — the suite
		# still ran, it just will not learn from this one.
		return
	file.store_line(JSON.stringify(history))
	file.close()


## The run counter, so `last_failed_run` means something across runs.
static func next_run_number(history: Dictionary) -> int:
	return int(history.get("__run", 0)) + 1


## The paths carried in `history`, excluding its own bookkeeping key.
static func tracked_paths(history: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key: String in history:
		if key != "__run":
			out.append(key)
	return out
