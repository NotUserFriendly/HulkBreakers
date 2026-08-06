extends SceneTree

## taskblock-59 Pass F: **the completion measurement, per intelligence tier.**
##
##     godot --headless --path . -s res://tools/probe_tiers.gd
##         the default window, every tier plus the mixed roster
##
##     godot --headless --path . -s res://tools/probe_tiers.gd -- <first> <count>
##         an arbitrary window
##
## **Every completion rate this project has recorded is an all-`TRAINED` rate**, because
## `Unit.intelligence_tier` defaulted to `TRAINED` and nothing set it until taskblock-59 Pass E.
## This is that figure taken again with the tiers actually authored.
##
## *"A single number across a mixed roster hides which row moved it"*, so each tier is played
## against itself over the **same seeds** and the mixed roster is played over them too. A per-tier
## figure taken on a different window would be comparing maps as much as intelligence.
##
## **An all-`MINDLESS` squad may never complete a mission, and that is not a failure of this
## probe** — it is what a squad that cannot shoot, take cover or overwatch does. Report it; do not
## tune it.
##
## A thin entry point over `CompletionSampler`, never its own copy of the measurement — the same
## rule `probe_seeds.gd` is written to.
##
## ## Every row prints as it finishes, and that is not a nicety
##
## The first cut printed the whole table at the end and was killed by its own timeout at 37 minutes
## having emitted **nothing** — 60 bouts of compute for no data. The `MINDLESS` row is why: a squad
## that cannot shoot never completes, so every one of its bouts runs the full `TURN_CAP` with six
## units planning, and it is by far the most expensive row in the table. **The slowest row is the
## one whose result is most predictable**, so a probe that reports nothing until the slowest row is
## done is a probe that reports nothing.

## The tiers to report. **A fixture here, not a constant in logic**: `intelligence_tier` is an open
## vocabulary and the standing rule is that a caller needing a concrete list authors one.
const TIERS: Array[StringName] = [&"MINDLESS", &"GRUNT", &"TRAINED", &"ELITE"]

const DEFAULT_FIRST := 0
const DEFAULT_COUNT := 24


func _initialize() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var first: int = int(args[0]) if args.size() > 0 else DEFAULT_FIRST
	var count: int = int(args[1]) if args.size() > 1 else DEFAULT_COUNT
	var seeds: Array[int] = []
	for i in range(first, first + count):
		seeds.append(i)

	print("seeds %d..%d, %d per row, %d rows" % [first, first + count - 1, count, TIERS.size() + 1])
	print("roster: %s per side" % [CompletionSampler.MIXED_ROSTER])
	var started: int = Time.get_ticks_msec()
	print(CompletionSampler.describe_per_tier([] as Array[Dictionary])[0])
	var rows: Array[Dictionary] = []
	for tier: StringName in TIERS + ([&""] as Array[StringName]):
		var row_started: int = Time.get_ticks_msec()
		var row: Dictionary = await CompletionSampler.run_seeds(
			seeds, CompletionSampler.TURN_CAP, tier
		)
		rows.append(row)
		# Printed here rather than collected, so a probe that is killed part way through still hands
		# back every row it finished.
		print(
			(
				"%s   [%.1f s]"
				% [
					CompletionSampler.describe_per_tier([row] as Array[Dictionary])[1],
					(Time.get_ticks_msec() - row_started) / 1000.0
				]
			)
		)
	print("took %.1f s overall" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit()
