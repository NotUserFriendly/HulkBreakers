class_name ActionBarModule
extends ViewModule

## taskblock-56 Pass C: the action bar — bottom, centred, half a 16:9 screen wide.
##
## **An INPUT module.** `ActionBar` arms an action and `TacticsController` turns the next click into
## a queued `CombatAction`.
##
## **taskblock-57 Pass C: the AP/MP pips left.** They were built here on the argument that splitting
## a two-line label row into its own module would be structure for its own sake. Pass C's table
## overrules that for a stated reason rather than a stylistic one: G2 replaces this exact surface
## with a coordinate readout in editor mode — *"same slot, different module"* — and two modules
## cannot share a slot if one of them is welded inside a third. They are `UnitResourcesModule` now,
## mounted into `action_bar_top_left`, which is a slot this module publishes: the pips still sit
## above the bar and still move with it.

var action_bar: ActionBar = null
## The column the bar's own row sits in. Exposed because a test confirms that ordering structurally
## rather than by eye.
var action_column: VBoxContainer = null

## taskblock-57 Pass B: the bar's own root, holding the four published slots and the bar itself.
## **Moving this moves every dependant surface**, because they are its children rather than
## separately anchored to a screen corner — which is the whole reason the bar publishes slots
## instead of four modules each anchoring themselves near where they expect it to be.
var bar_root: VBoxContainer = null
## The four published slot containers. Public so a test reads back what was published rather than
## re-deriving where the bar put them.
var left_slot: HBoxContainer = null
var right_slot: HBoxContainer = null
var top_left_slot: HBoxContainer = null
var top_right_slot: HBoxContainer = null


func module_id() -> StringName:
	return &"action_bar"


## Arming an action is the first half of queueing one.
func kind() -> Kind:
	return Kind.INPUT


## taskblock-57 Pass C: bottom, centred, half a 16:9 screen wide.
##
## **`ACTION_ROW` is bottom-pinned, so this module is collapsible**, and that reverses a call made
## earlier in this same block ("the action bar and its four satellites are not collapsible"). The
## reason is that the earlier decision was already inconsistent with the data shipped alongside it:
## `ModuleSlots.SLOT_EDGES` carries `ACTION_ROW: EDGE_BOTTOM`, and `test_slot_properties.gd` pins
## "bottom is a side too". Nothing surfaced the contradiction while no module declared a slot.
##
## Taking the consistent reading — every edge-pinned slot is collapsible, no exceptions — costs
## nothing a player would notice: the bar is not collapsed by default, and being able to fold it
## away to look at the board is a reasonable verb rather than "a game you cannot play". The
## alternative was carving a named exception into a rule whose whole value is having none.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_ROW


## taskblock-57 Pass B: **the first module to publish slots.** Nothing here is special-cased in the
## host — `ControlOverlay` publishes whatever any module returns from this hook.
func published_slots() -> Dictionary:
	return {
		ModuleSlots.ACTION_BAR_LEFT: left_slot,
		ModuleSlots.ACTION_BAR_RIGHT: right_slot,
		ModuleSlots.ACTION_BAR_TOP_LEFT: top_left_slot,
		ModuleSlots.ACTION_BAR_TOP_RIGHT: top_right_slot,
	}


func _mount() -> void:
	var row: Control = context.slot(ModuleSlots.ACTION_ROW, null)

	# The bar and its four satellite slots, as one subtree. Two rows: the surfaces that sit *above*
	# the bar, then the bar flanked by the surfaces beside it.
	bar_root = VBoxContainer.new()
	bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if row != null:
		row.add_child(bar_root)
		_centre_on_the_bars_band(bar_root)
	else:
		add_child(bar_root)

	var above := HBoxContainer.new()
	above.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.add_child(above)
	top_left_slot = _slot_container(above, true)
	top_right_slot = _slot_container(above, false)

	var beside := HBoxContainer.new()
	beside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.add_child(beside)
	left_slot = _slot_container(beside, false)

	action_column = VBoxContainer.new()
	action_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beside.add_child(action_column)

	right_slot = _slot_container(beside, false)

	# taskblock-08 E1: "action bar 3x its current size" — `ActionBar.BOX_SIZE` carries the actual
	# number; this row only has to sit inside `action_column`.
	var action_row := HBoxContainer.new()
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_column.add_child(action_row)

	action_bar = ActionBar.new()
	add_child(action_bar)
	if context.tactics != null:
		action_bar.setup(context.tactics, action_row, _tooltip_view())


## **The bar's rect sizes the BAR; the cluster around it is wider, and has to grow both ways from
## the bar's centre rather than rightward from its left edge.**
##
## Measured, not assumed. The table gives the action bar "half a 16:9 screen wide" — 960 px — but
## the four surfaces published off it are outside that: the combat log alone asks for 520. The real
## cluster came to **1740 px**, and anchored at the region's top-left it ran from x = 480 to x =
## 2220 on a 1920 screen, putting the End Turn button at x = 2142 and the whole turn-control column
## off the right of the display. A click test caught it; nothing about the code looked wrong.
##
## Centring on the region's own centre-bottom fixes it without touching the table's number: the bar
## stays where `BattleLayout` puts it, and its satellites spread symmetrically around it and grow
## upward out of the band instead of downward off the screen.
##
## A no-op when the slot is a real `Container` (the taskblock-56 layouts' `ACTION_ROW` is an
## `HBoxContainer`), which positions its children itself and ignores their anchors.
static func _centre_on_the_bars_band(target: Control) -> void:
	target.anchor_left = 0.5
	target.anchor_right = 0.5
	target.anchor_top = 1.0
	target.anchor_bottom = 1.0
	target.offset_left = 0.0
	target.offset_right = 0.0
	target.offset_top = 0.0
	target.offset_bottom = 0.0
	target.grow_horizontal = Control.GROW_DIRECTION_BOTH
	target.grow_vertical = Control.GROW_DIRECTION_BEGIN


## One published slot container. `expanding` gives it the leftover width, which is what pushes the
## slot after it to the far edge — the "above the bar, right edge" placement in Pass C's table.
##
## `MOUSE_FILTER_IGNORE`, like every other wrapping container in the layout: these span real width
## and would otherwise swallow camera drags that started over them before `CameraRig` ever saw the
## event. **Whatever mounts INTO the slot sets its own filter**; an empty slot must never be a dead
## patch of screen.
func _slot_container(parent: HBoxContainer, expanding: bool) -> HBoxContainer:
	var slot := HBoxContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expanding:
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slot)
	return slot


## Folds the bar and every surface published off it in one gesture — they are its children, which
## is the whole reason the bar publishes slots rather than four modules anchoring themselves near
## where they expect it to be.
func _on_collapsed(value: bool) -> void:
	if bar_root != null:
		bar_root.visible = not value


## The one shared tooltip renderer, if this mode declared it before this module. Null is a legal
## answer — `ActionBar` already accepts it.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip")
	return (module as TooltipModule).view if module != null else null
