extends GutTest

## docs/08: six colors, one Theme resource, no per-scene styling. HulkTheme
## governs the terminal UI only (docs/10's "two palettes" rule) — material
## and world colors live in WorldPalette/MaterialTable, covered in
## test_world_palette.gd.


func test_exactly_six_named_colors() -> void:
	# background, foreground, dim, highlight, warn, damage — docs/08's own
	# list, no more.
	var colors: Array[Color] = [
		HulkTheme.BACKGROUND,
		HulkTheme.FOREGROUND,
		HulkTheme.DIM,
		HulkTheme.HIGHLIGHT,
		HulkTheme.WARN,
		HulkTheme.DAMAGE,
	]
	assert_eq(colors.size(), 6)
	for i in range(colors.size()):
		for j in range(i + 1, colors.size()):
			assert_ne(colors[i], colors[j], "each of the six colors must be distinct")


func test_build_returns_a_real_theme_resource() -> void:
	var theme: Theme = HulkTheme.build()
	assert_true(theme is Theme)
	assert_eq(theme.get_color("default_color", "RichTextLabel"), HulkTheme.FOREGROUND)


func test_build_sets_the_real_monospace_font() -> void:
	var theme: Theme = HulkTheme.build()
	assert_not_null(theme.default_font, "docs/08: menus are monospace, text-first")
	assert_eq(theme.default_font_size, HulkTheme.FONT_SIZE)
