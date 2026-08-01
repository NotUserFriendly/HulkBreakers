extends SceneTree

## taskblock-52 Pass A2: the DEBUG entry point to `ShotCostBench` — a `-s` script
## under the editor/tools binary.
##
##     godot --headless --path . -s res://tools/bench_shot_cost.gd
##
## Its release counterpart is `tools/bench_main.gd`, reached as a main scene
## because an export template ignores `-s` entirely (see `AiPlanningBench`'s own
## doc comment for how that was confirmed). Both are three lines and share one
## implementation, so the two builds cannot measure different things.
##
##     ./tools/bench_release.sh shot_cost


func _init() -> void:
	ShotCostBench.new().run(OS.get_cmdline_user_args())
	quit()
