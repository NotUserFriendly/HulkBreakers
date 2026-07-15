class_name Hulk
extends Resource

## docs/07: hulks are pseudo-persistent. "The map is generated once from a
## seed and stays that way. You can return to it. Enemy presence and
## behavior are dynamic — it repopulates." One fixed seed drives the map
## forever; a second, visit-dependent seed drives the population, so
## returning to the same hulk shows the same rooms with different enemies.

@export var id: StringName
@export var map_seed: int = 0
@export var visits: int = 0


func generate_map(width: int, height: int) -> Grid:
	return MapGen.generate(map_seed, width, height)


## Combined with `visits` so the population re-rolls every time you come
## back, without ever touching map_seed (the layout must never change).
func population_seed() -> int:
	return map_seed * 1000003 + visits


func record_visit() -> void:
	visits += 1
