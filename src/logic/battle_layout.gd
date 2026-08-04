class_name BattleLayout
extends RefCounted

## taskblock-57 Pass C: **the placement table as arithmetic.**
##
## Logic, not view (CLAUDE.md): *where* every surface sits is a pure function of the screen size,
## and `ModeChrome` is only the thing that builds `Control`s at the answers. That split is what
## makes the whole layout assertable without a window — the alternative is a chrome full of anchor
## presets whose only test is a screenshot.
##
## ## Everything is derived from the safe rect except the three that escape
##
## `UiLayout.safe_rect` is the 16:9 reference every position is measured against, so on an ultrawide
## the layout stays together in the middle instead of smearing to the physical edges. The three
## surfaces that genuinely want the physical edge — Inspect, the Inspect Viewer and the performance
## monitor — say so through `ModuleSlots.escapes_safe_rect`, and `rect_for` hands each one the space
## it asked for. **The escape is read off the slot, never branched on here.**
##
## ## The numbers are approximate on purpose
##
## The taskblock says the supervisor fine-tunes these with CC once the bulk lands, and that padding
## and exact sizes are "the cheap half and the half that wants a screen". They are named constants
## so that pass is edits in one file.

## The action bar is half a 16:9 screen wide at 1x.
const ACTION_BAR_WIDTH_FRACTION := 0.5
## Its height is content-driven; this is the band reserved so the surfaces above it have somewhere
## to sit when nothing is mounted yet.
const ACTION_BAR_HEIGHT := 96.0
## Inspect and its viewer are about two thirds of the screen tall.
const INSPECT_HEIGHT_FRACTION := 2.0 / 3.0
## The viewer is half as wide as Inspect is tall — Inspect itself is square.
const INSPECT_VIEWER_WIDTH_FRACTION := 0.5
## The debug menu takes a quarter of the 16:9 width.
const DEBUG_MENU_WIDTH_FRACTION := 0.25
## Its starting height, before the author drags it.
const DEBUG_MENU_HEIGHT := 240.0
## The band the announcement position occupies at the top.
const ANNOUNCEMENT_HEIGHT := 120.0
## Ordinary breathing room between two pinned surfaces.
const PADDING := 8.0

## **There is no budge constant, and that is a measured decision rather than an omission.**
##
## The taskblock specifies "budges left if Inspect crowds it — a one-off, not a mechanism", and a
## fixed distance was the obvious reading. Measured against this table's own fractions, a fixed
## distance is wrong at both ends:
##
## | UI scale | debug menu | Inspect starts | overlap |
## |---|---|---|---|
## | 1.0 | 720 – 1200 | 1200 | **0** |
## | 1.5 | 600 – 1320 | 840 | 480 |
## | 2.0 | 480 – 1440 | 480 | 960 |
##
## **At 1x they abut exactly, and it is arithmetic rather than luck**: the menu ends at
## `1/2 + 1/8 = 5/8` of the safe width and Inspect begins at `1 - (2/3)(9/16) = 5/8`. So a fixed
## budge is dead code at the shipped default — and at any scale where they *do* overlap, 220 px
## would not have cleared it.
##
## `budged_debug_menu_rect` therefore shifts by **the overlap it actually measures**, plus padding.
## It stays a one-off — one function, one surface, one reason — while being correct at every scale,
## and it removes a constant nobody could have verified.


## Every slot this layout places, as `StringName` -> `Rect2`, for `screen`.
##
## The action bar's four satellites are deliberately absent: the bar publishes those itself (Pass B)
## and they move with it, which is the whole reason that mechanism exists.
static func slot_rects(screen: Vector2) -> Dictionary:
	return {
		ModuleSlots.ACTION_ROW: action_bar_rect(screen),
		ModuleSlots.INSPECT_PANEL: inspect_rect(screen),
		ModuleSlots.INSPECT_VIEWER: inspect_viewer_rect(screen),
		ModuleSlots.DEBUG_MENU: debug_menu_rect(screen),
		ModuleSlots.PERF_MONITOR: perf_monitor_rect(screen),
		ModuleSlots.ANNOUNCEMENTS: announcements_rect(screen),
	}


## Bottom, centred, half a 16:9 screen wide.
static func action_bar_rect(screen: Vector2) -> Rect2:
	var safe: Rect2 = UiLayout.safe_rect(screen)
	var width: float = UiLayout.safe_width(screen, ACTION_BAR_WIDTH_FRACTION)
	var height: float = UiLayout.scaled(ACTION_BAR_HEIGHT)
	return Rect2(
		Vector2(safe.position.x + (safe.size.x - width) * 0.5, safe.end.y - height),
		Vector2(width, height)
	)


## Top-right and **square** — the table says "~2/3 screen tall, square", so the height drives both
## extents. Escapes the safe rect, so it reaches the physical right edge.
static func inspect_rect(screen: Vector2) -> Rect2:
	var against: Rect2 = ModuleSlots.rect_for(ModuleSlots.INSPECT_PANEL, screen)
	var side: float = UiLayout.safe_height(screen, INSPECT_HEIGHT_FRACTION)
	return Rect2(Vector2(against.end.x - side, against.position.y), Vector2(side, side))


## Top-left, the same height, half as wide. Split out so the centre of the screen stays clear.
static func inspect_viewer_rect(screen: Vector2) -> Rect2:
	var against: Rect2 = ModuleSlots.rect_for(ModuleSlots.INSPECT_VIEWER, screen)
	var side: float = UiLayout.safe_height(screen, INSPECT_HEIGHT_FRACTION)
	return Rect2(against.position, Vector2(side * INSPECT_VIEWER_WIDTH_FRACTION, side))


## Top edge, centred, a quarter of the 16:9 width.
static func debug_menu_rect(screen: Vector2) -> Rect2:
	var safe: Rect2 = UiLayout.safe_rect(screen)
	var width: float = UiLayout.safe_width(screen, DEBUG_MENU_WIDTH_FRACTION)
	return Rect2(
		Vector2(safe.position.x + (safe.size.x - width) * 0.5, safe.position.y),
		Vector2(width, UiLayout.scaled(DEBUG_MENU_HEIGHT))
	)


## The debug menu's rect once Inspect is open, or its ordinary rect when Inspect is closed.
##
## **Idempotent by construction**: it is computed from the home rect every time rather than nudged
## from wherever the menu currently is, so calling it twice with the same answer cannot drift the
## menu across the screen. The first version of this did exactly that.
static func budged_debug_menu_rect(screen: Vector2, inspect_open: bool) -> Rect2:
	var home: Rect2 = debug_menu_rect(screen)
	if not inspect_open:
		return home
	# **Shifted by what is actually in the way**, not by a constant — see the note above the table.
	# A non-positive overlap means they do not crowd at this ratio and scale, and the menu stays put.
	var overlap: float = home.end.x - inspect_rect(screen).position.x
	if overlap <= 0.0:
		return home
	return Rect2(home.position - Vector2(overlap + UiLayout.scaled(PADDING), 0.0), home.size)


## True if the debug menu at its home position would overlap the Inspect panel. **This is the
## reason budging exists**, and answering it here means the one-off is at least measured rather
## than assumed.
static func inspect_crowds_debug_menu(screen: Vector2) -> bool:
	return debug_menu_rect(screen).intersects(inspect_rect(screen))


## The true bottom-right corner, no padding. Zero-sized because the readout sizes itself; what
## matters is the corner it grows from.
static func perf_monitor_rect(screen: Vector2) -> Rect2:
	return Rect2(ModuleSlots.rect_for(ModuleSlots.PERF_MONITOR, screen).end, Vector2.ZERO)


## Top, centred, spanning the safe width. A position rather than a panel.
static func announcements_rect(screen: Vector2) -> Rect2:
	var safe: Rect2 = UiLayout.safe_rect(screen)
	return Rect2(safe.position, Vector2(safe.size.x, UiLayout.scaled(ANNOUNCEMENT_HEIGHT)))
