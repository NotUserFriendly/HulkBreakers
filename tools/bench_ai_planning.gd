extends SceneTree

## taskblock-44 Pass A: the DEBUG entry point to `AiPlanningBench` — a `-s`
## script under the editor/tools binary, which is how every number this project
## has ever recorded was taken.
##
##     godot --headless --path . -s res://tools/bench_ai_planning.gd -- --no-compare
##
## Its release counterpart is `tools/bench_main.gd`, reached as a main scene
## because **an export template ignores `-s` entirely** (see `AiPlanningBench`'s
## own doc comment for how that was confirmed). Both are three lines and share
## one implementation, so the two builds cannot measure different things.
##
## `tools/bench_release.sh` runs both and prints the ratio.


func _init() -> void:
	AiPlanningBench.new().run(OS.get_cmdline_user_args())
	quit()
