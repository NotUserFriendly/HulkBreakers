class_name ReplayCatalog
extends RefCounted

## taskblock-48 Pass B2: **which failed tests have something worth looking at.**
##
## The headless run names the tests that failed. This asks each one's script whether
## it can rebuild what it built, and hands back the ones that can — in the order they
## failed, capped, because the point is to look at the first few rather than to sit
## through everything.
##
## ## Tests declare themselves; nothing maintains a list
##
## A test script opts in by exposing:
##
## ```gdscript
## static func replay_handle_for(test_name: String) -> ReplayHandle
## ```
##
## returning `null` for tests it has no visual form for. **A script without the method
## simply has no visual form**, which is the answer for most of the suite — a failed
## assertion about a dictionary has nothing to show. No registry, nothing to keep in
## sync, and adding a handle is a local edit to the test that wants one.
##
## Looked up by loading the script rather than by instantiating it: building a
## `GutTest` outside GUT drags in a harness this has no business starting, and the
## method is static precisely so it can be asked without one.

## How many failures the panel offers by default. **Small on purpose**: the first few
## are where the pattern is, and "show all" is a deliberate second choice rather than
## the default — taskblock-47's watched run made the same argument about seeds.
const DEFAULT_LIMIT := 3

## The method a test script exposes to opt in.
const HANDLE_METHOD := "replay_handle_for"


## The handle `test_name` in `script_path` declares, or `null`.
##
## Returns `null` for every ordinary failure mode — script missing, method absent,
## test not covered — because **"no visual form" is a normal answer here**, not an
## error to report. A replay that surfaced a warning for every dictionary assertion in
## the suite would be noise nobody reads.
static func handle_for(script_path: String, test_name: String) -> ReplayHandle:
	if not ResourceLoader.exists(script_path):
		return null
	var script: GDScript = load(script_path)
	if script == null or not script.has_method(HANDLE_METHOD):
		return null
	var handle: Variant = script.call(HANDLE_METHOD, test_name)
	if handle is ReplayHandle and (handle as ReplayHandle).is_valid():
		return handle
	return null


## Handles for `failures`, in the order they failed, at most `limit` of them.
##
## `failures` is `SuiteRun.failures()`: `[{"script": String, "test": String}, ...]`.
## Pass `limit <= 0` for the deliberate "show all" path.
static func handles_for(failures: Array, limit: int = DEFAULT_LIMIT) -> Array[ReplayHandle]:
	var handles: Array[ReplayHandle] = []
	for failure: Dictionary in failures:
		if limit > 0 and handles.size() >= limit:
			break
		var handle: ReplayHandle = handle_for(
			String(failure.get("script", "")), String(failure.get("test", ""))
		)
		if handle != null:
			handles.append(handle)
	return handles


## How many of `failures` have a visual form at all, ignoring the cap. Reported beside
## the offer so "3 of 11 failures can be replayed" is visible — otherwise a capped list
## reads as though the rest had nothing to show.
static func replayable_count(failures: Array) -> int:
	return handles_for(failures, 0).size()
