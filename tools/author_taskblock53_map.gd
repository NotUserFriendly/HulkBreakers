extends SceneTree

## taskblock-53 Pass B: authors `res://data/maps/proving_ground.tres`, the project's first
## committed, hand-made map. Run once via
## `godot --headless -s res://tools/author_taskblock53_map.gd`; kept afterward as the record
## of what the map *means*, which a 700-entry `.tres` cannot express.
##
## ## "CC hand-authors the first map" — why this is a script and not typed `.tres`
##
## Same convention every `tools/author_taskblock*.gd` already uses. The map is **designed**
## here — every region below is a deliberate choice with a reason — and the `.tres` is its
## serialization. Typing several hundred `sub_resource` blocks by hand would express the same
## data with none of the intent and one transposed row away from a silent hole in the floor.
##
## ## What the map is for
##
## A **proving ground**: small enough to read at a glance, and built so every vertical
## mechanic this block touches has somewhere to happen. Eight blocks of AI diagnosis were done
## by hunting seeds; this exists so the next one is *"build the situation"*.
##
## ```
##   x:  0                   9                  19
##  y:0  #####################
##       #.........|=========#     #  wall
##       #.........|====^====#     .  ground floor      (height 0)
##       #....c....|=========#     =  raised platform   (height 2)
##       #.........+=========#     ^  high ledge        (height 4)
##       #.........|====^====#     +  ramp  (ground -> platform, rise 2)
##       #A........|=========#     |  the shelf's edge: a 2-high face, no route
##       #A........|====^====#     A  spawn A     B  spawn B
##       #.........|=========#     c  cover
##       #.........+====B===B#
##  y:11 #####################
## ```
##
## **The shape is the point.** A single ramp is the *only* way up onto the platform, so the
## rest of that edge is a two-high face a unit cannot cross — which is exactly the geometry
## Pass D's asymmetric-reachability flood is meant to catch and Pass C's ladder is meant to
## solve. The two high ledges at height 4 sit on the platform with a further 2-high face and
## **no route at all**: they are deliberately unreachable until a ladder exists. Authoring a
## map that is *knowingly* unnavigable is legitimate (taskblock-53: an authored map may be
## broken on purpose; the editor warns, never blocks) and it gives Pass E a target that can
## only be reached by climbing.

const OUT_PATH := "res://data/maps/proving_ground.tres"
const WIDTH := 21
const ROWS := 12

## Ground is height 0; the platform sits one ordinary rise above it and the ledges one above
## that. **Flagged, not designed:** 2.0 is `Pass D`'s own ramp/ladder threshold ("rise <= 2
## gets a ramp; anything higher gets a ladder"), reused here so the map exercises both sides
## of that rule rather than inventing a third number.
const PLATFORM_HEIGHT := 2.0
const LEDGE_HEIGHT := 4.0

## The platform occupies x in [11, 19]; the wall of the room is the border ring.
const PLATFORM_X0 := 11
const PLATFORM_X1 := 19
## The one way up. Two ramp cells, deliberately at opposite ends of the platform edge so a
## route exists but is not free — crossing the map to reach it is a real decision.
const RAMP_CELLS: Array[Vector2i] = [Vector2i(10, 4), Vector2i(10, 9)]
## Height-4 shelves on top of the platform, unreachable without a ladder.
const LEDGE_CELLS: Array[Vector2i] = [Vector2i(15, 2), Vector2i(15, 5), Vector2i(15, 7)]
const COVER_CELLS: Array[Vector2i] = [Vector2i(5, 3), Vector2i(7, 6)]
const SPAWN_A_CELLS: Array[Vector2i] = [Vector2i(1, 6), Vector2i(1, 7)]
const SPAWN_B_CELLS: Array[Vector2i] = [Vector2i(14, 9), Vector2i(18, 9)]


func _initialize() -> void:
	var map := MapFile.new()
	map.map_name = "Proving Ground"
	map.width = WIDTH
	map.rows = ROWS

	for y: int in range(ROWS):
		for x: int in range(WIDTH):
			var cell := Vector2i(x, y)
			if _is_border(cell):
				# A wall is a blocker with no walkable surface under it, and it blocks sight.
				map.placements.append(MapPlacement.new(cell, MapPlacement.KIND_BLOCKER, &"wall"))
				map.opacity_cells.append(cell)
				map.opacity_values.append(1.0)
				continue
			if cell in RAMP_CELLS:
				# A ramp's facing points up-slope: +X, toward the platform it serves.
				map.placements.append(
					MapPlacement.new(cell, MapPlacement.KIND_SURFACE, &"ramp", 0.0, 0.0)
				)
				continue
			var height: float = 0.0
			if x >= PLATFORM_X0 and x <= PLATFORM_X1:
				height = PLATFORM_HEIGHT
			map.placements.append(
				MapPlacement.new(cell, MapPlacement.KIND_SURFACE, &"ship_floor", height, 0.0)
			)
			if cell in LEDGE_CELLS:
				# A SECOND surface at the same cell, above the platform — the format's ordered
				# per-cell array doing the thing it exists for. First is the platform a unit
				# stands on; second is the shelf it cannot yet reach.
				map.placements.append(
					MapPlacement.new(
						cell, MapPlacement.KIND_SURFACE, &"ship_floor", LEDGE_HEIGHT, 0.0
					)
				)

	for cell: Vector2i in COVER_CELLS:
		map.placements.append(MapPlacement.new(cell, MapPlacement.KIND_BLOCKER, &"forklift"))
	for cell: Vector2i in SPAWN_A_CELLS:
		map.spawn_cells.append(cell)
		map.spawn_markers.append(Enums.SpawnMarker.SPAWN_A)
	for cell: Vector2i in SPAWN_B_CELLS:
		map.spawn_cells.append(cell)
		map.spawn_markers.append(Enums.SpawnMarker.SPAWN_B)

	var problems: Array[String] = MapSerializer.describe_problems(map)
	for problem: String in problems:
		print("authoring warning: %s" % problem)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/maps"))
	var err: Error = ResourceSaver.save(map, OUT_PATH)
	if err != OK:
		printerr("failed to write %s: %d" % [OUT_PATH, err])
		quit(1)
		return
	print(
		(
			"wrote %s — %d placements, %d spawns, %d opacity cells"
			% [OUT_PATH, map.placements.size(), map.spawn_cells.size(), map.opacity_cells.size()]
		)
	)
	quit(0)


func _is_border(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.y == 0 or cell.x == WIDTH - 1 or cell.y == ROWS - 1
