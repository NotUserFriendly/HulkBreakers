extends GutTest

## taskblock-57 Pass C — **the placement table, asserted as arithmetic.**
##
## Every surface in the block's own table has a declared place, and `BattleLayout` is pure logic
## precisely so that "is it in its declared place" is answerable without a window. `ModeChrome` only
## turns these rects into `Control`s.
##
## The three claims worth the most here:
##
## 1. **The three escaping surfaces reach the physical edge and nothing else does.** On an ultrawide
##    that is the visible difference between a layout that stays together and one that smears.
## 2. **Budging is idempotent.** The first version nudged the menu from wherever it currently was,
##    which walked it across the screen on repeated calls.
## 3. **Nothing lands outside the screen** at any supported ratio.

const RATIOS: Array[Vector2] = [
	Vector2(1920, 1080),
	Vector2(3440, 1440),
	Vector2(1024, 768),
	Vector2(1200, 1200),
]


func after_each() -> void:
	UiLayout.scale = 1.0


# ---------------------------------------------------------------- the table


## Every slot the layout places is present, and none of them is empty by accident.
func test_the_layout_places_every_slot_in_the_table() -> void:
	var rects: Dictionary = BattleLayout.slot_rects(Vector2(1920, 1080))
	for slot: StringName in [
		ModuleSlots.ACTION_ROW,
		ModuleSlots.INSPECT_PANEL,
		ModuleSlots.INSPECT_VIEWER,
		ModuleSlots.DEBUG_MENU,
		ModuleSlots.PERF_MONITOR,
		ModuleSlots.ANNOUNCEMENTS,
	]:
		assert_true(rects.has(slot), "%s has no declared place" % slot)
		gut.p("%s -> %s" % [slot, rects[slot]])


## **The four action-bar satellites are deliberately absent.** They are published by the bar and
## move with it, which is the entire reason Pass B's mechanism exists — a chrome placing them too
## would be a second answer to where they sit.
func test_the_layout_does_not_place_the_action_bars_own_satellites() -> void:
	var rects: Dictionary = BattleLayout.slot_rects(Vector2(1920, 1080))
	for slot: StringName in ModuleSlots.ACTION_BAR_SLOTS:
		assert_false(rects.has(slot), "%s is the bar's to publish, not the chrome's" % slot)


## Bottom, centred, half a 16:9 screen wide.
func test_the_action_bar_is_bottom_centred_at_half_the_safe_width() -> void:
	var screen := Vector2(1920, 1080)
	var safe: Rect2 = UiLayout.safe_rect(screen)
	var bar: Rect2 = BattleLayout.action_bar_rect(screen)

	assert_almost_eq(bar.size.x, safe.size.x * 0.5, 0.001, "half a 16:9 screen wide")
	assert_almost_eq(
		bar.get_center().x, safe.get_center().x, 0.001, "centred on the safe rect, not the screen"
	)
	assert_almost_eq(bar.end.y, safe.end.y, 0.001, "and sitting on the safe rect's bottom edge")


## Inspect is square, which the table states outright, and the height drives both extents.
func test_the_inspect_panel_is_square_and_two_thirds_tall() -> void:
	var screen := Vector2(1920, 1080)
	var inspect: Rect2 = BattleLayout.inspect_rect(screen)
	assert_almost_eq(inspect.size.x, inspect.size.y, 0.001, "square")
	assert_almost_eq(inspect.size.y, 1080.0 * BattleLayout.INSPECT_HEIGHT_FRACTION, 0.001)


## The viewer is half as wide, at the same height, on the other side.
func test_the_inspect_viewer_is_half_as_wide_and_on_the_opposite_side() -> void:
	var screen := Vector2(1920, 1080)
	var inspect: Rect2 = BattleLayout.inspect_rect(screen)
	var viewer: Rect2 = BattleLayout.inspect_viewer_rect(screen)

	assert_almost_eq(viewer.size.y, inspect.size.y, 0.001, "the same height")
	assert_almost_eq(viewer.size.x, inspect.size.x * 0.5, 0.001, "half as wide")
	assert_lt(viewer.end.x, inspect.position.x, "and the centre of the screen is left clear")


## The debug menu is a quarter of the 16:9 width, centred on the top edge.
func test_the_debug_menu_is_a_quarter_width_and_centred_on_the_top_edge() -> void:
	var screen := Vector2(1920, 1080)
	var safe: Rect2 = UiLayout.safe_rect(screen)
	var menu: Rect2 = BattleLayout.debug_menu_rect(screen)
	assert_almost_eq(menu.size.x, safe.size.x * 0.25, 0.001)
	assert_almost_eq(menu.get_center().x, safe.get_center().x, 0.001)
	assert_almost_eq(menu.position.y, safe.position.y, 0.001)


# ---------------------------------------------------------------- escaping, and what it buys


## **THE ACCEPTANCE that escaping is real.** On an ultrawide, exactly the three declared surfaces
## reach the physical edge; everything else stays inside the 16:9 reference rect.
func test_only_the_three_declared_surfaces_leave_the_safe_rect() -> void:
	var screen := Vector2(3440, 1440)
	var safe: Rect2 = UiLayout.safe_rect(screen)
	assert_gt(safe.position.x, 0.0, "sanity: this ratio really does inset, or nothing is proven")

	assert_almost_eq(
		BattleLayout.inspect_rect(screen).end.x, screen.x, 0.001, "Inspect reaches the real edge"
	)
	assert_almost_eq(
		BattleLayout.inspect_viewer_rect(screen).position.x, 0.0, 0.001, "and so does its viewer"
	)
	assert_almost_eq(
		BattleLayout.perf_monitor_rect(screen).position.x, screen.x, 0.001, "and the perf corner"
	)

	# Everything else stays inside the reference rect.
	for rect: Rect2 in [
		BattleLayout.action_bar_rect(screen),
		BattleLayout.debug_menu_rect(screen),
		BattleLayout.announcements_rect(screen),
	]:
		assert_gt(rect.position.x, safe.position.x - 0.001, "%s escaped and should not have" % rect)
		assert_lt(rect.end.x, safe.end.x + 0.001, "%s escaped and should not have" % rect)


func test_the_perf_monitor_sits_in_the_true_bottom_right_corner() -> void:
	for screen: Vector2 in RATIOS:
		var corner: Rect2 = BattleLayout.perf_monitor_rect(screen)
		assert_almost_eq(corner.position.x, screen.x, 0.001, "%v: hard against the right" % screen)
		assert_almost_eq(corner.position.y, screen.y, 0.001, "%v: and the bottom" % screen)


## Nothing walks off the screen at any supported ratio — the one failure a layout cannot recover
## from, since a surface you cannot see is one you cannot toggle back.
func test_no_surface_lands_outside_the_screen_at_any_ratio() -> void:
	for screen: Vector2 in RATIOS:
		var full := Rect2(Vector2.ZERO, screen)
		for slot: StringName in BattleLayout.slot_rects(screen):
			var rect: Rect2 = BattleLayout.slot_rects(screen)[slot]
			assert_gt(rect.position.x, -0.001, "%v %s starts left of the screen" % [screen, slot])
			assert_gt(rect.position.y, -0.001, "%v %s starts above the screen" % [screen, slot])
			assert_lt(
				rect.position.x, full.end.x + 0.001, "%v %s starts past the right" % [screen, slot]
			)
			assert_lt(
				rect.position.y,
				full.end.y + 0.001,
				"%v %s starts below the bottom" % [screen, slot]
			)


# ---------------------------------------------------------------- budging, the one-off


## **Idempotent by construction.** The first version nudged the menu from wherever it currently
## sat, so calling it twice walked it across the screen. It is computed from the home rect every
## time instead.
##
## Exercised at 2x, where the measured overlap rather than the floor is what moves it — the two
## paths into `debug_menu_budge_distance` must both be idempotent, and the floor's path is covered
## at 1x by the test below.
func test_budging_is_idempotent_and_reversible() -> void:
	var screen := Vector2(1920, 1080)
	UiLayout.scale = 2.0
	var home: Rect2 = BattleLayout.debug_menu_rect(screen)

	var budged: Rect2 = BattleLayout.budged_debug_menu_rect(screen, true)
	assert_lt(budged.position.x, home.position.x, "it moved left, out of Inspect's way")
	assert_eq(
		BattleLayout.budged_debug_menu_rect(screen, true),
		budged,
		"asking twice gives the same answer -- it does not walk"
	)
	assert_eq(
		BattleLayout.budged_debug_menu_rect(screen, false),
		home,
		"and closing Inspect puts it exactly back"
	)


## **At 1x they abut exactly — measured, not assumed — and the floor is what makes budging fire
## anyway.**
##
## The menu ends at `1/2 + 1/8 = 5/8` of the safe width and Inspect begins at `1 - (2/3)(9/16) =
## 5/8`, so with the table's own fractions they touch and never overlap. That is why the budge is
## `max(floor, measured overlap)` and not either alone: a purely measured budge is zero here, at the
## one scale anyone can currently play at, so the one-off would never have fired in normal play.
## Supervisor's call, taskblock-57: floor it at `X * SCALE`.
func test_at_one_x_the_two_abut_exactly_and_the_budge_falls_back_to_its_floor() -> void:
	var screen := Vector2(1920, 1080)
	var menu: Rect2 = BattleLayout.debug_menu_rect(screen)
	var inspect: Rect2 = BattleLayout.inspect_rect(screen)
	gut.p("debug menu ends at %.1f, inspect starts at %.1f" % [menu.end.x, inspect.position.x])

	assert_almost_eq(menu.end.x, inspect.position.x, 0.001, "they abut exactly at 1x")
	assert_false(BattleLayout.inspect_crowds_debug_menu(screen), "so nothing OVERLAPS anything")
	assert_almost_eq(
		BattleLayout.debug_menu_budge_distance(screen),
		BattleLayout.DEBUG_MENU_BUDGE_BASE,
		0.001,
		"with no overlap to measure, the floor is the whole distance"
	)
	assert_almost_eq(
		BattleLayout.budged_debug_menu_rect(screen, true).position.x,
		menu.position.x - BattleLayout.DEBUG_MENU_BUDGE_BASE,
		0.001,
		"so the menu still moves clear at the shipped default"
	)


## **The floor scales, and it is the same scaling every other size goes through.**
##
## The supervisor gave the rule as `X + X*(SCALE-1)`, which is `X * SCALE` — i.e. exactly
## `UiLayout.scaled(X)`. Asserted against `UiLayout.scaled` rather than against a second copy of the
## multiplication, so a change to how scaling works cannot leave this agreeing with nothing.
func test_the_budge_floor_scales_with_the_ui() -> void:
	# **Scales at and BELOW 1x, and the fixture is the point.** Inspect grows as `(2/3)*height*scale`
	# while the menu grows as `(1/4)*width*scale`, so above 1x Inspect always catches the menu and
	# the measured term takes over — a sweep over 1.5x/2.0x would skip every iteration and assert
	# the floor exactly once, which is the "passes while proving nothing" shape this suite keeps
	# finding. Shrinking the UI is a real setting and leaves the two clear at every step.
	var screen := Vector2(1920, 1080)
	for scale: float in [0.5, 0.75, 1.0]:
		UiLayout.scale = scale
		assert_false(
			BattleLayout.inspect_crowds_debug_menu(screen),
			"fixture broken: scale %.2f must leave nothing to measure" % scale
		)
		var distance: float = BattleLayout.debug_menu_budge_distance(screen)
		gut.p("scale %.2f: floor-only budge %.1f" % [scale, distance])
		assert_almost_eq(
			distance,
			UiLayout.scaled(BattleLayout.DEBUG_MENU_BUDGE_BASE),
			0.001,
			"scale %.2f: the floor must go through the one place that reads UI scale" % scale
		)
	# And the three answers really were different, or the loop proved nothing about scaling.
	UiLayout.scale = 0.5
	var half: float = BattleLayout.debug_menu_budge_distance(screen)
	UiLayout.scale = 1.0
	assert_almost_eq(
		BattleLayout.debug_menu_budge_distance(screen), half * 2.0, 0.001, "and it really is linear"
	)


## **The measured term wins wherever it is larger, and the floor never shrinks it.**
##
## This is the half a fixed constant got wrong: at 1.5x the overlap is 480 px and at 2.0x it is 960,
## against a floor of 64. A budge that took the floor at those scales would leave the menu sitting
## on top of Inspect.
func test_a_real_overlap_beats_the_floor_rather_than_being_capped_by_it() -> void:
	var screen := Vector2(1920, 1080)
	for scale: float in [1.5, 2.0]:
		UiLayout.scale = scale
		var overlap: float = (
			BattleLayout.debug_menu_rect(screen).end.x
			- BattleLayout.inspect_rect(screen).position.x
		)
		var distance: float = BattleLayout.debug_menu_budge_distance(screen)
		gut.p("scale %.1f: overlap %.1f, budge %.1f" % [scale, overlap, distance])
		assert_gt(distance, overlap, "scale %.1f: the budge must clear the overlap" % scale)
		assert_gt(
			distance,
			UiLayout.scaled(BattleLayout.DEBUG_MENU_BUDGE_BASE),
			"scale %.1f: and the floor must not have capped it" % scale
		)


## **Where budging actually earns its keep: a scaled-up UI.** Both surfaces grow, the overlap is
## real, and the shift is sized from what it measures rather than from a constant that happened to
## be too small.
func test_a_scaled_up_ui_really_does_crowd_and_budging_clears_it() -> void:
	var screen := Vector2(1920, 1080)
	for scale: float in [1.5, 2.0]:
		UiLayout.scale = scale
		var menu: Rect2 = BattleLayout.debug_menu_rect(screen)
		var inspect: Rect2 = BattleLayout.inspect_rect(screen)
		gut.p(
			(
				"scale %.1f: menu ends %.1f, inspect starts %.1f, overlap %.1f"
				% [scale, menu.end.x, inspect.position.x, menu.end.x - inspect.position.x]
			)
		)
		assert_true(
			BattleLayout.inspect_crowds_debug_menu(screen),
			"at scale %.1f they must overlap" % scale
		)
		var budged: Rect2 = BattleLayout.budged_debug_menu_rect(screen, true)
		assert_false(
			budged.intersects(inspect),
			"scale %.1f: budging left the menu still overlapping Inspect" % scale
		)


# ---------------------------------------------------------------- scale


## Scale reaches the layout, not just individual widgets — a UI scale that moved panels' contents
## and not the panels would be worse than none.
func test_ui_scale_moves_the_layout_itself() -> void:
	var screen := Vector2(1920, 1080)
	var at_one: Rect2 = BattleLayout.action_bar_rect(screen)
	UiLayout.scale = 2.0
	var at_two: Rect2 = BattleLayout.action_bar_rect(screen)
	assert_almost_eq(at_two.size.x, at_one.size.x * 2.0, 0.001, "the bar scales")
	assert_gt(
		BattleLayout.inspect_rect(screen).size.y,
		at_one.size.y,
		"and so does everything else measured off the safe rect"
	)
