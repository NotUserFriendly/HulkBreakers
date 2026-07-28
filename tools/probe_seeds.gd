extends SceneTree

## taskblock-46 Pass B: **the completion measurement, as a command.**
##
##     godot --headless --path . -s res://tools/probe_seeds.gd
##         the deterministic escalation — `ESCALATION_SEEDS` from 0, the number
##         the suite's sampler defers to and the one to quote
##
##     godot --headless --path . -s res://tools/probe_seeds.gd -- <first> <count>
##         an arbitrary window, for comparing one part of the seed space with
##         another
##
## **The escalation is deliberately NOT run by `run_tests.sh`.** It plays a hundred
## missions and costs upward of ten minutes, and the suite is the feedback loop
## everything else depends on; a gate that occasionally triples its own runtime
## teaches people to stop running it. The suite samples and points here when the
## sample dips.
##
## **A thin entry point over `CompletionSampler`, never its own copy of the
## measurement.** It was written as a standalone probe first, and committing it
## that way would have left two implementations of "play N bouts and count the
## extractions" — which is how the number the suite gates on and the number a
## person quotes start to disagree. The sampler is the one implementation; this
## chooses a seed window and prints.
##
## Kept because the in-window verb samples ten random seeds and the suite's
## escalation is fixed at 0..99, while re-baselining wants an arbitrary window —
## seeds 12-23 against 0-11, say, which is how the pinned window was caught being
## the pessimistic one.


func _initialize() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var started: int = Time.get_ticks_msec()
	var result: Dictionary = {}

	if args.is_empty():
		# **No arguments runs THE escalation** — the canonical, deterministic
		# measurement the suite's sampler defers to. Named rather than described so
		# a failure message can point at one command.
		print("running the deterministic %d-seed escalation" % CompletionSampler.ESCALATION_SEEDS)
		result = await CompletionSampler.escalate()
	else:
		var first: int = int(args[0])
		var count: int = int(args[1]) if args.size() > 1 else 24
		var seeds: Array[int] = []
		for i in range(first, first + count):
			seeds.append(i)
		result = await CompletionSampler.run_seeds(seeds)

	for line: String in CompletionSampler.describe(result):
		print(line)
	print("elapsed: %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit()
