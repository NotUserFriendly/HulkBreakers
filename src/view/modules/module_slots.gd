class_name ModuleSlots
extends RefCounted

## taskblock-56 Pass C: the named places a mode may publish for its modules to mount into.
##
## **Open `StringName`s, not an enum**, per CLAUDE.md's standing rule: a mode is data and a new mode
## may want a slot nobody has thought of. These constants exist so the four modes shipping today
## agree on spelling, not to close the set — `ModuleContext.set_slot` takes any name, and a module
## asking for a slot no mode published gets its fallback rather than an error.
##
## Every one of these is optional. A module must render somewhere sensible when its slot is absent,
## because the stand-alone acceptance mounts every module against a context with no slots at all.

## The full-height left column. Historically the inventory/weapons list, the Inspect button and the
## combat log, in that order.
const LEFT_COLUMN := &"left_column"
## The row inside the left column that the weapons list sits in.
const INVENTORY_ROW := &"inventory_row"
## Top-right, growing down: the keybindings toggle and the H-help legend under it.
const TOP_RIGHT := &"top_right"
## Bottom-right, growing up: the readout panel, then the action bar / turn controls row.
const BOTTOM_RIGHT := &"bottom_right"
## Inside the bottom-right readout panel: header, banner, aim readout, stat block, queue list.
const READOUT_COLUMN := &"readout_column"
## The horizontal row holding the action column on the left and the turn controls on the right.
const ACTION_ROW := &"action_row"
## Play/Step/Speed and the spectator's status line.
##
## **taskblock-57 Pass G1 renamed this from `top_left`, and the rename is the point.** The old name
## was a position, and Pass G1 moves the row into the spectator's own bar at the bottom of the
## screen — where a slot called `top_left` would be a lie that only the file defining it could
## catch. `pacing_row` says what the row is *for*, which is the only description that survives being
## moved, and moving it is exactly what the module system exists to make cheap.
##
## `ModeChrome.TOP_LEFT_ROWS` still publishes it at the top-left corner; `SpectatorBarModule`
## publishes it inside the bar. `PlaybackModule` does not know which.
const PACING_ROW := &"pacing_row"
## A second row under the pacing row — the spectator's tunable timing fields.
const TUNABLES := &"tunables"
## A single centred column owning the whole screen — a menu's own layout.
const MENU_COLUMN := &"menu_column"

# --- taskblock-57 Pass B: slots published by the action bar, not by a chrome ------------------
#
# **These resolve against the bar, not against the screen.** Four surfaces sit relative to it, so
# when the bar moves — a different UI scale, a different safe rect — they move with it for free,
# because they are its children rather than separately anchored to a corner.
#
# They are ordinary `ModuleSlots` names with nothing special about them: `ActionBarModule` returns
# them from `ViewModule.published_slots()` and the host publishes whatever any module returns.

## Immediately left of the bar. The combat log, which minimises to a button flush against it.
const ACTION_BAR_LEFT := &"action_bar_left"
## Immediately right of the bar. Turn-order management, in the player mode only.
const ACTION_BAR_RIGHT := &"action_bar_right"
## Above the bar, from its left edge. Unit resources — AP/MP pips, RAM, later resources.
const ACTION_BAR_TOP_LEFT := &"action_bar_top_left"
## Above the bar, at its right edge. Module toggles, Inspect, the debug menu.
const ACTION_BAR_TOP_RIGHT := &"action_bar_top_right"

## The four above, for a caller that wants to ask "is this an action-bar slot" without listing them.
const ACTION_BAR_SLOTS: Array[StringName] = [
	ACTION_BAR_LEFT,
	ACTION_BAR_RIGHT,
	ACTION_BAR_TOP_LEFT,
	ACTION_BAR_TOP_RIGHT,
]

# --- taskblock-57 Pass C: the screen-anchored positions -------------------------------------

## Top-right, roughly two thirds of the screen tall and square. **Escapes the safe rect.**
const INSPECT_PANEL := &"inspect_panel"
## Top-left, two thirds tall and half as wide — the 3D view, split out so the centre stays clear.
## **Escapes the safe rect.**
const INSPECT_VIEWER := &"inspect_viewer"
## Top edge, centred, a quarter of the 16:9 width. Budges left when Inspect crowds it.
const DEBUG_MENU := &"debug_menu"
## The true bottom-right corner, no padding. **Escapes the safe rect**, and is click-through.
const PERF_MONITOR := &"perf_monitor"
## Top, centred. Invisible and click-through — a position, not a panel.
const ANNOUNCEMENTS := &"announcements"

# --- taskblock-57 Pass A: what a slot is, beyond where it is ---------------------------------
#
# **Two properties, both declared here rather than known by the panels.** A convention lives in
# whichever file remembers it; a property is checkable, and both of these have a test that reads
# them back.

## The edges a slot may pin to. Open `StringName`s like every slot name, and `&""` for a slot that
## floats (a centred menu, the announcement position).
const EDGE_LEFT := &"left"
const EDGE_RIGHT := &"right"
const EDGE_TOP := &"top"
const EDGE_BOTTOM := &"bottom"

## Slots that resolve against `screen_rect` rather than `safe_rect`.
##
## **Three surfaces do this deliberately** — Inspect, the Inspect Viewer and the performance
## monitor — and taskblock-57 A1 asks for it as a property precisely because a comment in a panel
## cannot be asserted. A slot not named here does not escape, which is the safe default: a surface
## that escapes by accident is one that walks off an ultrawide's edge.
## taskblock-57 Pass C fills this with exactly the three the table names. **Nothing else may be
## added without a reason in the same commit** — a surface that escapes by accident is one that
## walks off an ultrawide's edge, which is the failure the safe rect exists to prevent.
const ESCAPING_SLOTS: Array[StringName] = [INSPECT_PANEL, INSPECT_VIEWER, PERF_MONITOR]

## Slot -> which screen edge it is pinned to. A slot absent from here floats.
##
## **This is what makes "collapsible" derivable rather than remembered.** taskblock-57 A2's rule is
## that everything pinned to a side is collapsible or off by default, so a square-ratio player
## toggles rather than shrinking the whole UI — and a module can answer that about itself by asking
## which slot it wants instead of each one carrying its own flag.
##
## **`ACTION_ROW` is here, so every bar is collapsible**, and that reverses a call made earlier in
## this same block ("the action bar and its four satellites are not collapsible"). The earlier
## reading was already inconsistent with this table, which has carried `ACTION_ROW: EDGE_BOTTOM`
## since Pass A; nothing surfaced the contradiction while no module declared a slot. Taking the
## consistent reading — every edge-pinned slot is collapsible, no exceptions — costs nothing a
## player notices, because no bar is collapsed by default.
##
## **The bar's four satellites are still absent, and for their own reason**: they ride a centred bar
## and fold with it, so they are not pinned to anything.
##
## **`PACING_ROW` and `TUNABLES` left this table in Pass G1**, and their absence is a statement
## rather than an omission. They used to be top-pinned because `TOP_LEFT_ROWS` was the only thing
## that published them; `SpectatorBarModule` now publishes the same two names inside a bar at the
## bottom. A slot published at two different edges by two different providers has no single edge,
## and saying `top` here would be a claim no shipped mode makes true. Anything mounted into them
## folds with the bar it rides.
const SLOT_EDGES: Dictionary = {
	LEFT_COLUMN: EDGE_LEFT,
	INVENTORY_ROW: EDGE_LEFT,
	TOP_RIGHT: EDGE_RIGHT,
	BOTTOM_RIGHT: EDGE_RIGHT,
	READOUT_COLUMN: EDGE_RIGHT,
	ACTION_ROW: EDGE_BOTTOM,
	INSPECT_PANEL: EDGE_RIGHT,
	INSPECT_VIEWER: EDGE_LEFT,
	DEBUG_MENU: EDGE_TOP,
}


## True if `slot` is drawn against the whole window rather than the 16:9 safe rect.
static func escapes_safe_rect(slot: StringName) -> bool:
	return ESCAPING_SLOTS.has(slot)


## Which edge `slot` pins to, or `&""` for one that floats.
static func edge_of(slot: StringName) -> StringName:
	return SLOT_EDGES.get(slot, &"")


## True if `slot` is pinned to any screen edge.
##
## **Every edge counts, not just left and right.** The rule exists so a player on a cramped ratio
## can reclaim space, and a bottom-pinned bar costs vertical room exactly as a left-pinned column
## costs horizontal room — which is the axis a square ratio is short of.
static func is_side_pinned(slot: StringName) -> bool:
	return edge_of(slot) != &""


## The rect `slot` is placed within, given the current screen. Thin, and deliberately the only
## place a caller has to look to find out which space a slot lives in.
static func rect_for(slot: StringName, screen: Vector2) -> Rect2:
	return UiLayout.rect_for(escapes_safe_rect(slot), screen)
