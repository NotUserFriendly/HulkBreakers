extends GutTest


class FakeRegion:
	var rect: Rect2
	var depth: float
	var part: Variant

	func _init(p_rect: Rect2, p_depth: float, p_part: Variant) -> void:
		rect = p_rect
		depth = p_depth
		part = p_part


func test_grid_to_text_renders_terrain_and_cover() -> void:
	var grid := Grid.new(4, 2)
	grid.set_terrain(Vector2i(1, 0), Enums.TerrainType.WALL)
	grid.set_terrain(Vector2i(2, 0), Enums.TerrainType.SPAWN_A)
	grid.set_terrain(Vector2i(3, 0), Enums.TerrainType.SPAWN_B)
	grid.set_cover_value(Vector2i(0, 1), 0.5)
	grid.set_cover_value(Vector2i(1, 1), 1.0)

	var text: String = AsciiRender.grid_to_text(grid)
	var lines: Array = text.split("\n")
	assert_eq(lines.size(), 2)
	assert_eq(lines[0], ".#ab")
	assert_eq(lines[1], "oO..")


func test_grid_to_text_occupant_overlay_overrides_terrain() -> void:
	var grid := Grid.new(2, 1)
	var text: String = AsciiRender.grid_to_text(grid, {Vector2i(1, 0): "X"})
	assert_eq(text, ".X")


func test_plane_to_text_frontmost_region_wins() -> void:
	var near_part := Part.new()
	near_part.id = &"near"
	var far_part := Part.new()
	far_part.id = &"far"

	var plane: Array = [
		FakeRegion.new(Rect2(0, 0, 2, 1), 5.0, far_part),
		FakeRegion.new(Rect2(0, 0, 1, 1), 1.0, near_part),
	]
	var text: String = AsciiRender.plane_to_text(plane, 2, 1)
	assert_eq(text, "NF")


func test_plane_to_text_gap_is_dot() -> void:
	var part := Part.new()
	part.id = &"a"
	var plane: Array = [FakeRegion.new(Rect2(0, 0, 1, 1), 1.0, part)]
	var text: String = AsciiRender.plane_to_text(plane, 3, 1)
	assert_eq(text, "A..")


func test_overlay_impacts_marks_points() -> void:
	var base := "....\n...."
	var marked: String = AsciiRender.overlay_impacts(base, [Vector2i(1, 0), Vector2i(3, 1)])
	var lines: Array = marked.split("\n")
	assert_eq(lines[0], ".*..")
	assert_eq(lines[1], "...*")
