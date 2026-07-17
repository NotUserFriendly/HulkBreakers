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


## docs/10 taskblock03 H2: "Tree control, docs/08 terminal theme, monospace."
func test_build_styles_the_inventory_panels_tree() -> void:
	var theme: Theme = HulkTheme.build()
	assert_eq(theme.get_color("font_color", "Tree"), HulkTheme.FOREGROUND)
	assert_true(theme.has_stylebox("panel", "Tree"))


## runNotes.md: "the 'highlight' meant to show more details on a body part
## isn't showing at all" — the tooltip needs its own solid, high-contrast
## panel, not Godot's unstyled default sitting directly on top of this
## panel's own near-identical dark background.
func test_build_styles_the_tooltip_with_a_solid_high_contrast_panel() -> void:
	var theme: Theme = HulkTheme.build()
	assert_true(theme.has_stylebox("panel", "TooltipPanel"))
	var style: StyleBoxFlat = theme.get_stylebox("panel", "TooltipPanel")
	assert_almost_eq(style.bg_color.a, 0.97, 0.001, "must actually be opaque, not blend into a row")
	assert_eq(style.border_color, HulkTheme.HIGHLIGHT)
	assert_eq(theme.get_color("font_color", "TooltipLabel"), HulkTheme.FOREGROUND)


## docs/10 taskblock05 A2: "the inspector's scrollbar is unreachable" — the
## engine default grabber is a near-transparent sliver until hovered, easy
## to miss against this panel's own translucent background. Tree draws its
## scrollbar internally (no exposed node to toggle `.visible` on), so the
## fix is a grabber style that's clearly visible on its own, not only once
## Godot swaps in the hover variant.
func test_build_styles_scrollbars_with_an_always_visible_grabber() -> void:
	var theme: Theme = HulkTheme.build()
	for scrollbar_type in ["VScrollBar", "HScrollBar"]:
		assert_true(theme.has_stylebox("grabber", scrollbar_type))
		var grabber: StyleBoxFlat = theme.get_stylebox("grabber", scrollbar_type)
		assert_eq(grabber.bg_color, HulkTheme.DIM)
		assert_true(grabber.bg_color.a > 0.5, "the resting grabber must not be near-transparent")


func test_build_sets_the_real_monospace_font() -> void:
	var theme: Theme = HulkTheme.build()
	assert_not_null(theme.default_font, "docs/08: menus are monospace, text-first")
	assert_eq(theme.default_font_size, HulkTheme.FONT_SIZE)
