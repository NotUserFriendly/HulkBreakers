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
## Deliberately does nothing but call the shared bench and quit. The measurement
## is `AiPlanningBench`'s; if any of it lived here instead, the release and debug
## numbers would be produced by two different code paths, which is the one thing
## a bench comparing two builds must not do.


func _ready() -> void:
	AiPlanningBench.new().run(OS.get_cmdline_user_args())
	get_tree().quit()
