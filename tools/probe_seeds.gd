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
## missions, and the suite is the feedback loop everything else depends on; a gate that
## occasionally triples its own runtime teaches people to stop running it.
##
## ## tb66 Pass C2: it costs ~110 minutes serial, not "upward of ten"
##
## **The old figure was stale by an order of magnitude and it dated from a different game.**
## It was written when the completion rate was ~0.72, so most seeds ended early in a win;
## measured at taskblock-66 Pass A the rate is **0.220**, a losing bout averages **61.3 turns**
## with **38% of them running to `TURN_CAP`**, and 20 seeds took **1315.8 s**. A hundred is
## about **110 minutes** on one process.
##
## **Run it as ten parallel windows instead — the same hundred seeds in ~11 minutes.** Each
## window is an independent process and the machine has 32 cores, so nothing is shared and
## nothing contends:
##
## ```
## for first in 0 1000 2000 3000 4000 5000 6000 7000 8000 9000; do
##   godot --headless --path . -s res://tools/probe_seeds.gd -- $first 10 &
## done; wait
## ```
##
## **Documented here rather than left to be rediscovered**, because the serial form's cost is
## what makes people quote a stale number instead of re-measuring.
##
## **A thin entry point over `CompletionSampler`, never its own copy of the
## measurement.** It was written as a standalone probe first, and committing it
## that way would have left two implementations of "play N bouts and count the
## extractions" — which is how the number the suite gates on and the number a
## person quotes start to disagree. The sampler is the one implementation; this
## chooses a seed window and prints.
##
## Kept because the in-window verb samples ten random seeds and the suite's
## escalation is fixed at 0..99, while re-baselining wants an arbitrary window.
##
## **tb66 Pass A: the windows do not differ, and the belief that they do is retired.** This
## header used to end by citing seeds 12-23 against 0-11 as *"how the pinned window was caught
## being the pessimistic one."* Fisher exact on that 5/12 vs 8/12 gives **0.414**, and Pass A
## tested it directly across ten scattered windows: **chi-square 11.42 on 9 df against a 16.92
## critical value — no evidence the seed space has structure.** taskblock-46's decision to
## *sample* rather than pin is correct regardless and is untouched; sampling is the right method
## whether or not that particular spread was real. What is corrected is the claim that the
## windows are *known* to differ.


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
