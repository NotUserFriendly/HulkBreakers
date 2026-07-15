class_name RunState
extends Resource

## Persistent meta-progression between missions (docs/07) — rewritten from
## scratch against the v2 socket/matrix model, not a port of v1's
## run_state.gd. A Resource so it save/load round-trips like Frame/Part.

@export var roster: Array[Matrix] = []  # base matrices — the persistent crew
@export var stash: Array[Part] = []  # parts/items banked between missions
@export var resource_counters: Dictionary = {}  # StringName resource id -> int (docs/05)
@export var credits: int = 0
## Not `seed` — that's a global GDScript function name.
@export var run_seed: int = 0


func add_resource(id: StringName, amount: int) -> void:
	resource_counters[id] = resource_counters.get(id, 0) + amount


func resource_count(id: StringName) -> int:
	return resource_counters.get(id, 0)
