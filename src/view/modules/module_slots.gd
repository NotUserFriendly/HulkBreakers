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
## Top-left, the corner `DebugControlPanel`'s own centering already steers clear of. Play/Step/Speed
## and the shared Inject/New Battle/Watch cluster.
const TOP_LEFT := &"top_left"
## A second top-left row under the first — the spectator's tunable timing fields.
const TUNABLES := &"tunables"
## A single centred column owning the whole screen — a menu's own layout.
const MENU_COLUMN := &"menu_column"

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
const ESCAPING_SLOTS: Array[StringName] = []

## Slot -> which screen edge it is pinned to. A slot absent from here floats.
##
## **This is what makes "collapsible" derivable rather than remembered.** taskblock-57 A2's rule is
## that everything pinned to a side is collapsible or off by default, so a square-ratio player
## toggles rather than shrinking the whole UI — and a module can answer that about itself by asking
## which slot it wants instead of each one carrying its own flag.
const SLOT_EDGES: Dictionary = {
	LEFT_COLUMN: EDGE_LEFT,
	INVENTORY_ROW: EDGE_LEFT,
	TOP_RIGHT: EDGE_RIGHT,
	BOTTOM_RIGHT: EDGE_RIGHT,
	READOUT_COLUMN: EDGE_RIGHT,
	ACTION_ROW: EDGE_BOTTOM,
	TOP_LEFT: EDGE_TOP,
	TUNABLES: EDGE_TOP,
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
