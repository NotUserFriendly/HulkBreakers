extends GutTest

## taskblock-57 Pass A — **two coordinate spaces, and a UI scale that exists.**
##
## All headless: where a panel should sit is arithmetic over a screen size, and `UiLayout` is in
## `src/logic/` precisely so that arithmetic can be tested without a window.
##
## **A tension in the spec, and which half these tests pin.** A1 says narrower ratios "crush rather
## than clip" while its own test says `safe_rect` "is 16:9 inside any screen ratio and never exceeds
## it". One rect cannot do both, so the rect keeps the 16:9 guarantee the stated test names and the
## crush is a separate factor applied to what is drawn into it. Both halves are asserted below.

## Real ratios, not round numbers — 16:9, ultrawide, 4:3, 16:10, and a square.
const RATIOS: Array[Vector2] = [
	Vector2(1920, 1080),
	Vector2(2560, 1080),
	Vector2(3440, 1440),
	Vector2(1024, 768),
	Vector2(1680, 1050),
	Vector2(1200, 1200),
]


func after_each() -> void:
	# `scale` is static and outlives a test; leaving it moved would silently retune every later one.
	UiLayout.scale = 1.0


# ---------------------------------------------------------------- safe_rect


## **THE STATED ACCEPTANCE.** 16:9 at every ratio, and never bigger than the screen it sits in.
func test_the_safe_rect_is_16_9_inside_any_screen_ratio_and_never_exceeds_it() -> void:
	for screen: Vector2 in RATIOS:
		var safe: Rect2 = UiLayout.safe_rect(screen)
		var aspect: float = safe.size.x / safe.size.y
		gut.p(
			(
				"screen %v (%.3f) -> safe %v (%.3f) at %v"
				% [screen, screen.x / screen.y, safe.size, aspect, safe.position]
			)
		)
		assert_almost_eq(aspect, UiLayout.REFERENCE_ASPECT, 0.001, "%v is not 16:9" % screen)
		assert_lt(safe.size.x, screen.x + 0.001, "%v: wider than its screen" % screen)
		assert_lt(safe.size.y, screen.y + 0.001, "%v: taller than its screen" % screen)


## Centred, so the bars are even on both sides — asserted rather than assumed, since an off-centre
## safe rect would put every "centred" surface off-centre with it.
func test_the_safe_rect_is_centred_in_its_screen() -> void:
	for screen: Vector2 in RATIOS:
		var safe: Rect2 = UiLayout.safe_rect(screen)
		assert_almost_eq(safe.position.x, (screen.x - safe.size.x) * 0.5, 0.001)
		assert_almost_eq(safe.position.y, (screen.y - safe.size.y) * 0.5, 0.001)


## On a screen that is already 16:9 the safe rect is the screen — no bars, no inset.
func test_a_16_9_screen_gets_the_whole_screen() -> void:
	var safe: Rect2 = UiLayout.safe_rect(Vector2(1920, 1080))
	assert_almost_eq(safe.size.x, 1920.0, 0.001)
	assert_almost_eq(safe.size.y, 1080.0, 0.001)
	assert_almost_eq(safe.position.x, 0.0, 0.001)


## An ultrawide is inset horizontally: the height binds and bars fall at the sides.
func test_an_ultrawide_is_inset_horizontally_and_keeps_its_full_height() -> void:
	var safe: Rect2 = UiLayout.safe_rect(Vector2(3440, 1440))
	assert_almost_eq(safe.size.y, 1440.0, 0.001, "the full height is used")
	assert_lt(safe.size.x, 3440.0, "and the width is inset")
	assert_gt(safe.position.x, 0.0, "with a bar on each side")


## A 4:3 screen is inset vertically — the width binds. This is the case `crush_factor` then
## reclaims.
func test_a_narrow_screen_is_inset_vertically_and_keeps_its_full_width() -> void:
	var safe: Rect2 = UiLayout.safe_rect(Vector2(1024, 768))
	assert_almost_eq(safe.size.x, 1024.0, 0.001, "the full width is used")
	assert_lt(safe.size.y, 768.0, "and the height is inset")


## A degenerate screen answers a degenerate rect rather than dividing by zero — headless fixtures
## and a window mid-resize both produce one.
func test_a_zero_sized_screen_answers_an_empty_rect() -> void:
	assert_eq(UiLayout.safe_rect(Vector2.ZERO).size, Vector2.ZERO)
	assert_eq(UiLayout.safe_rect(Vector2(0, 1080)).size, Vector2.ZERO)


# ---------------------------------------------------------------- crush, not clip


## **Ultrawide letterboxes; narrower ratios crush.** The two ends are handled differently on
## purpose: an ultrawide has more room than the layout was authored for, so spreading into it would
## only push things apart, while a narrow screen is short of exactly the axis the bars would waste.
func test_an_ultrawide_keeps_its_bars_and_a_narrow_screen_crushes_over_them() -> void:
	assert_eq(UiLayout.crush_factor(Vector2(1920, 1080)), Vector2.ONE, "16:9 crushes nothing")
	assert_eq(UiLayout.crush_factor(Vector2(3440, 1440)), Vector2.ONE, "an ultrawide keeps bars")

	var crush: Vector2 = UiLayout.crush_factor(Vector2(1024, 768))
	gut.p("4:3 crush factor %v" % crush)
	assert_almost_eq(crush.x, 1.0, 0.001, "the width already fits -- nothing is crushed across")
	assert_gt(crush.y, 1.0, "and the vertical bars are reclaimed rather than left empty")


## The crush exactly fills the screen: stretching the safe rect by the factor gives the screen back.
## **This is what "never clip" means arithmetically** — nothing is left over to cut off.
func test_crushing_the_safe_rect_fills_the_screen_exactly() -> void:
	for screen: Vector2 in [Vector2(1024, 768), Vector2(1680, 1050), Vector2(1200, 1200)]:
		var safe: Rect2 = UiLayout.safe_rect(screen)
		var crush: Vector2 = UiLayout.crush_factor(screen)
		assert_almost_eq(
			safe.size.y * crush.y, screen.y, 0.001, "%v: crushed height fills" % screen
		)


# ---------------------------------------------------------------- escaping is a slot property


## **THE STATED ACCEPTANCE.** A slot marked as escaping resolves against `screen_rect`; everything
## else resolves against `safe_rect`. Asserted through `UiLayout` directly, so it holds for any slot
## vocabulary rather than for the names that happen to exist today.
func test_an_escaping_slot_resolves_against_the_screen_and_others_against_the_safe_rect() -> void:
	var screen := Vector2(3440, 1440)
	assert_eq(UiLayout.rect_for(true, screen), UiLayout.screen_rect(screen), "escaping -> screen")
	assert_eq(UiLayout.rect_for(false, screen), UiLayout.safe_rect(screen), "otherwise -> safe")
	assert_ne(
		UiLayout.rect_for(true, screen),
		UiLayout.rect_for(false, screen),
		"sanity: the two differ on this ratio, or the assertion above proves nothing"
	)


## **Exactly three slots escape, and they are the three the table names.**
##
## Pass A shipped this as "nothing escapes yet, the three arrive in Pass C", and Pass C1 adding them
## is what made that version fail — the ratchet working rather than a regression. Pinned as a list
## so a fourth escaping surface has to be argued for in the commit that adds it: a surface escaping
## by accident is one that walks off an ultrawide's edge, which is the failure the safe rect exists
## to prevent.
func test_exactly_the_three_declared_surfaces_escape_the_safe_rect() -> void:
	var escaping: Array[StringName] = []
	for slot: StringName in ModuleSlots.SLOT_EDGES:
		if ModuleSlots.escapes_safe_rect(slot):
			escaping.append(slot)
	# The perf monitor floats rather than pinning to an edge, so it is not in SLOT_EDGES.
	assert_true(
		ModuleSlots.escapes_safe_rect(ModuleSlots.PERF_MONITOR), "the corner readout escapes"
	)
	escaping.append(ModuleSlots.PERF_MONITOR)

	gut.p("escaping: %s" % ", ".join(escaping))
	assert_eq(
		escaping,
		(
			[ModuleSlots.INSPECT_PANEL, ModuleSlots.INSPECT_VIEWER, ModuleSlots.PERF_MONITOR]
			as Array[StringName]
		),
		"the escaping set moved -- say why in the same commit"
	)


func test_an_undeclared_slot_does_not_escape() -> void:
	assert_eq(
		ModuleSlots.rect_for(&"a_slot_nobody_declared", Vector2(1920, 1080)),
		UiLayout.safe_rect(Vector2(1920, 1080)),
		"an unknown slot does not escape -- a surface escaping by accident walks off an ultrawide"
	)
	assert_false(ModuleSlots.escapes_safe_rect(ModuleSlots.ACTION_ROW), "the bar stays inside")


# ---------------------------------------------------------------- UI scale


## **THE STATED ACCEPTANCE: scale multiplies every sized element** — asserted against a changed
## value, not against a render.
func test_scale_multiplies_a_sized_element() -> void:
	assert_almost_eq(UiLayout.scaled(100.0), 100.0, 0.001, "1.0 is the identity")
	UiLayout.scale = 1.5
	assert_almost_eq(UiLayout.scaled(100.0), 150.0, 0.001)
	assert_eq(UiLayout.scaled_size(Vector2(10, 20)), Vector2(15, 30))


## The fractional helpers scale too — "half a 16:9 screen wide at 1x" has to mean something other
## than half a screen once the option moves.
func test_a_fraction_of_the_safe_rect_scales_with_the_option() -> void:
	var screen := Vector2(1920, 1080)
	assert_almost_eq(UiLayout.safe_width(screen, 0.5), 960.0, 0.001, "half a 16:9 screen at 1x")
	UiLayout.scale = 2.0
	assert_almost_eq(UiLayout.safe_width(screen, 0.5), 1920.0, 0.001)
	assert_almost_eq(UiLayout.safe_height(screen, 0.5), 1080.0, 0.001)


## The scale is a variable rather than a constant, which is the whole of A2 — an options menu needs
## something to write to.
func test_the_scale_is_settable_and_defaults_to_one() -> void:
	assert_almost_eq(UiLayout.scale, 1.0, 0.001, "the default a fresh session runs at")
	UiLayout.scale = 0.75
	assert_almost_eq(UiLayout.scaled(200.0), 150.0, 0.001, "and a smaller UI is expressible")
