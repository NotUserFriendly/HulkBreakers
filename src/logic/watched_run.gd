class_name WatchedRun
extends RefCounted

## taskblock-47 Pass D: **watch the bouts a failing sample was talking about.**
##
## A completion figure says 8 of 20 finished. That is the end of what a number can
## tell you, and the next question — *what were they doing instead* — has until now
## meant a CC session reading a combat log. This is the connection between "the test
## failed" and "here is what happened", and it is the reason the 100-seed escalation
## could move out of the gate: watching answers the question escalating only
## sharpens.
##
## ## There is no artifact, and there must not be one
##
## `CompletionSampler.build_for_seed(map_seed)` takes nothing but the seed — rosters
## and presets are constants inside it. **A seed is therefore already a complete
## reproduction handle**, and a failing seed replays exactly with no recording, no
## capture format, and no replay machinery to keep in sync with the game. Any of that
## would be a second source of truth about what a bout was, which is the thing to
## avoid, not a feature to add.
##
## ## taskblock-48 Pass B2: seeds were one kind of replay handle all along
##
## This was written to replay completion-sampler seeds. A seed is exactly a
## `ReplayHandle` whose value is a seed, so the sequencing, skip, rewatch and stop
## below are the **general** controls and the criteria text is one handle describing
## itself. Folded rather than duplicated — *"if two code paths decide the same thing,
## that's the bug to fix"* — so a failed map-generation test and a failed completion
## seed queue up in one list with one set of buttons.
##
## `of(seeds)` still takes plain ints, because that is what the completion sampler
## deals in and rewriting its callers to wrap them would be churn for nothing.
##
## ## Why the sequencing lives here rather than in the overlay
##
## CC cannot see the screen (`docs/00`), so "the seeds played in the order given" and
## "stopping left nothing behind" have to be answerable in a headless test. What is
## left for the view is starting a bout and drawing a table — the thin part.

## What a seed's row looks like before it has been played. Distinguished from a real
## outcome so a half-finished run reads as half-finished rather than as a run where
## several bouts mysteriously produced nothing.
const PENDING := &"pending"
## Watched and deliberately abandoned. **Not the same as `PENDING`** — someone looked
## at this one and decided they had seen enough, which is information.
const SKIPPED := &"skipped"

## What to replay, in the order given. Order is the caller's and is never sorted:
## `[11, 3, 7]` plays 11 first, because someone asking for that order usually has a
## reason and silently reordering it would hide which bout they were watching.
var items: Array[ReplayHandle] = []
## `seed -> {"outcome": StringName, "turns": int}`. Only seeds that have finished or
## been skipped appear.
var results: Dictionary = {}
## Index into `seeds` of the bout currently being watched, or `seeds.size()` when the
## run is done.
var index: int = 0
## Set by `stop()`. A stopped run reports what it managed rather than discarding it —
## the 15-of-20 case is precisely one where the useful information arrives at seed 5.
var stopped: bool = false


## Parses `"3, 7, 11"`. **Tolerant of whitespace and empty entries and nothing else**:
## a typo should produce a shorter list, not a run against seed 0 that looks fine.
static func parse_seeds(text: String) -> Array[int]:
	var parsed: Array[int] = []
	for chunk: String in text.split(",", false):
		var trimmed: String = chunk.strip_edges()
		if trimmed.is_valid_int():
			parsed.append(trimmed.to_int())
	return parsed


static func of(seed_list: Array[int]) -> WatchedRun:
	var handles: Array[ReplayHandle] = []
	for map_seed: int in seed_list:
		handles.append(ReplayHandle.from_seed(map_seed))
	return of_handles(handles)


static func of_handles(handle_list: Array[ReplayHandle]) -> WatchedRun:
	var run := WatchedRun.new()
	run.items = handle_list.duplicate()
	return run


func is_done() -> bool:
	return stopped or index >= items.size()


## The handle being watched now, or `null`.
func current() -> ReplayHandle:
	if is_done():
		return null
	return items[index]


## The seed being watched now, or -1 when there is none — including when the current
## handle is not seed-shaped at all, which is the honest answer for a map-generation
## replay.
func current_seed() -> int:
	var handle: ReplayHandle = current()
	return -1 if handle == null else handle.seed_value


## What `results` is keyed on. The seed for a seed handle, so every existing caller and
## test keeps working unchanged.
func current_key() -> Variant:
	var handle: ReplayHandle = current()
	return null if handle == null else handle.key


## Records how the current bout ended and moves to the next. `turns` is the runner's
## own count, so the table and the headless report agree by construction.
func record(outcome: StringName, turns: int) -> void:
	if is_done():
		return
	results[current_key()] = {"outcome": outcome, "turns": turns}
	index += 1


## Abandon this bout and move on. **Recorded as `SKIPPED` rather than dropped**, so
## the table cannot be mistaken for a run where this seed passed.
func skip() -> void:
	if is_done():
		return
	results[current_key()] = {"outcome": SKIPPED, "turns": 0}
	index += 1


## Watch the current seed again from the top. Clears its recorded result, because a
## re-watch that kept the old row would report an outcome from a bout nobody is
## looking at any more.
func rewatch() -> void:
	if is_done():
		return
	results.erase(current_key())


## Go back to the seed before this one and watch it again — the "wait, what happened
## there" case, which is most of why anyone watches at all.
func rewatch_previous() -> void:
	if index <= 0:
		return
	index -= 1
	results.erase(current_key())


## **Ends the run and keeps what it learned.** `stopped` is the only state stopping
## leaves behind, and `results` is still readable — a stop that cleared the table
## would throw away the thing the run was for.
func stop() -> void:
	stopped = true


func completed() -> int:
	var count := 0
	for row: Dictionary in results.values():
		if StringName(row["outcome"]) == &"EXTRACTED":
			count += 1
	return count


## **What is being checked, in words, on screen.** A pass/fail against an unexplained
## criterion is something to interpret rather than read, and the three outcome names
## are not self-explanatory — "terminated" in particular reads like a crash when it
## means the opposite of anything happening.
static func describe_criteria(turn_cap: int, floor_rate: float) -> Array[String]:
	return [
		"Completion = the mission reaches EXTRACTED within %d turns." % turn_cap,
		"  EXTRACTED  — objectives done and the squad got out. This is the pass.",
		"  TERMINATED — nobody won before the turn cap. Not a loss; nothing finished.",
		"  STRANDED   — the squad cannot extract any more. A real loss.",
		"The suite fails below %.0f%% completion over its sample." % (floor_rate * 100.0),
	]


## The live table, one row per seed, rebuilt each time a bout ends. Seeds not yet
## played show as pending rather than being omitted, so the run's length is visible
## from the first frame instead of growing mysteriously.
func describe_table() -> Array[String]:
	var lines: Array[String] = ["what          outcome      turns"]
	var here: Variant = current_key()
	for handle: ReplayHandle in items:
		var row: Dictionary = results.get(handle.key, {})
		var outcome: StringName = StringName(row.get("outcome", PENDING))
		var turns: int = int(row.get("turns", 0))
		var marker: String = ">" if handle.key == here else " "
		lines.append(
			"%s%-13s %-12s %s" % [marker, handle.label, outcome, "" if turns == 0 else str(turns)]
		)
	lines.append(
		(
			"%d of %d watched, %d completed%s"
			% [results.size(), items.size(), completed(), " (stopped)" if stopped else ""]
		)
	)
	return lines
