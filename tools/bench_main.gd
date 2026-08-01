extends Node

## taskblock-44 Pass A: the RELEASE entry point to `AiPlanningBench`.
##
## An export template ignores `-s res://...` — it is a tools-only flag — and
## boots its main scene instead, so a release build can only be driven through
## `run/main_scene`. `project.godot` overrides that setting for the `bench`
## feature tag (`run/main_scene.bench`), and `export_presets.cfg` declares that
## feature, so the bench preset boots straight into this while the ordinary game
## preset is untouched.
##
## Deliberately does nothing but pick a bench, call it, and quit. Every
## measurement is the bench class's own; if any of it lived here instead, the
## release and debug numbers would be produced by two different code paths, which
## is the one thing a bench comparing two builds must not do.
##
## taskblock-52 Pass A2: **which** bench is now an argument, because the shot-cost
## figures the ray chain is judged against need a release number for exactly the
## reason the planning figures did. `--bench=<name>`, defaulting to the AI planner
## so every existing invocation is byte-for-byte unchanged.

const BENCH_AI_PLANNING := "ai_planning"
const BENCH_SHOT_COST := "shot_cost"


func _ready() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	match _selected_bench(argv):
		BENCH_SHOT_COST:
			ShotCostBench.new().run(argv)
		_:
			# tb45 Pass D: awaited — see `tools/bench_ai_planning.gd`.
			await AiPlanningBench.new().run(argv)
	get_tree().quit()


## An unrecognised name falls through to the default rather than failing, and
## says so — a release export that booted, printed nothing and exited zero would
## look exactly like a bench with no work to do.
static func _selected_bench(argv: PackedStringArray) -> String:
	for arg: String in argv:
		if not arg.begins_with("--bench="):
			continue
		var name: String = arg.trim_prefix("--bench=")
		if name == BENCH_SHOT_COST or name == BENCH_AI_PLANNING:
			return name
		print("unknown --bench=%s; running %s" % [name, BENCH_AI_PLANNING])
	return BENCH_AI_PLANNING
