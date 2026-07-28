extends SceneTree

## taskblock-46 Pass B: headless re-measurement of the completion rate over an
## arbitrary seed window.
##
##     godot --headless --path . -s res://tools/probe_seeds.gd -- <first> <count>
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
	var first: int = int(args[0]) if args.size() > 0 else 0
	var count: int = int(args[1]) if args.size() > 1 else 24

	var seeds: Array[int] = []
	for i in range(first, first + count):
		seeds.append(i)
	var started: int = Time.get_ticks_msec()
	var result: Dictionary = await CompletionSampler.run_seeds(seeds)

	for line: String in CompletionSampler.describe(result):
		print(line)
	print("elapsed: %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit()
