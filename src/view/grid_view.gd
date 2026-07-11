class_name GridView
extends TileMapLayer

## Renders a Grid's terrain as flat-colored tiles. Programmer-primitive
## visuals only — the tileset is a runtime-generated solid-color atlas, no art.

const TILE_PX := 24

const COLOR_OPEN := Color(0.75, 0.75, 0.75)
const COLOR_WALL := Color(0.12, 0.12, 0.14)
const COLOR_SPAWN_A := Color(0.55, 0.72, 1.0)
const COLOR_SPAWN_B := Color(1.0, 0.58, 0.58)

const ATLAS_COLORS: Array[Color] = [COLOR_OPEN, COLOR_WALL, COLOR_SPAWN_A, COLOR_SPAWN_B]


func _init() -> void:
	tile_set = _build_tile_set()


func _build_tile_set() -> TileSet:
	var image := Image.create(TILE_PX * ATLAS_COLORS.size(), TILE_PX, false, Image.FORMAT_RGBA8)
	for i in range(ATLAS_COLORS.size()):
		image.fill_rect(Rect2i(i * TILE_PX, 0, TILE_PX, TILE_PX), ATLAS_COLORS[i])
	var texture := ImageTexture.create_from_image(image)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	for i in range(ATLAS_COLORS.size()):
		atlas.create_tile(Vector2i(i, 0))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)
	ts.add_source(atlas, 0)
	return ts


func render(grid: Grid) -> void:
	clear()
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var terrain: int = grid.get_terrain(cell)
			var atlas_x: int = 0
			match terrain:
				Enums.TerrainType.WALL:
					atlas_x = 1
				Enums.TerrainType.SPAWN_A:
					atlas_x = 2
				Enums.TerrainType.SPAWN_B:
					atlas_x = 3
				_:
					atlas_x = 0
			set_cell(cell, 0, Vector2i(atlas_x, 0))
