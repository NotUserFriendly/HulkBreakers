extends GutTest

## taskblock-30 follow-up (supervisor report): the panel had no anchor at
## all, so a freshly opened panel sat at the top-left corner, directly on
## top of the existing top-left HUD (`controls`/`tunables` in both
## overlays). CLAUDE.md's own view-math rule applies: build the real node,
## read `position`/`size` back — don't re-derive the centering formula in
## the test.


func _make_state() -> CombatState:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)
	return CombatState.new(Grid.new(5, 5), [unit])


func _open_panel() -> DebugControlPanel:
	var panel := DebugControlPanel.new()
	add_child_autofree(panel)
	panel.setup(BoutInjector.new(_make_state()), DeepStrike.reference_humanoid_pool(), self)
	return panel


## `_center_top()` reads `size`, which only reflects real content after a
## layout pass — same reasoning as InspectPanel's own clamp test: pin
## `size` to a known value first rather than race the engine's own layout
## timing, so the assertion is against a fixed, known input.
func test_center_top_pins_the_panel_to_a_fixed_top_margin() -> void:
	var panel := _open_panel()
	panel.size = Vector2(380.0, 200.0)

	panel._center_top()

	assert_eq(panel.position.y, DebugControlPanel.TOP_MARGIN)


func test_center_top_horizontally_centers_the_panel_in_the_real_viewport() -> void:
	var panel := _open_panel()
	panel.size = Vector2(380.0, 200.0)

	panel._center_top()

	var viewport_size: Vector2 = panel.get_viewport_rect().size
	assert_eq(panel.position.x, (viewport_size.x - 380.0) / 2.0)


## A window resized while the panel is open must re-center, not stay put
## at an offset computed against the old size.
func test_viewport_resize_recenters_the_panel() -> void:
	var panel := _open_panel()
	panel.size = Vector2(380.0, 200.0)
	panel._center_top()
	var original_x: float = panel.position.x

	panel.position = Vector2(-999.0, 999.0)
	panel._center_top()

	assert_ne(panel.position, Vector2(-999.0, 999.0))
	assert_eq(panel.position.x, original_x)
	assert_eq(panel.position.y, DebugControlPanel.TOP_MARGIN)
