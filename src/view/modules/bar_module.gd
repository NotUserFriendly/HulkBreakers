class_name BarModule
extends ViewModule

## taskblock-57 Pass G1: **the bar — and there are three of them, not one with three contents.**
##
## The taskblock's own title for the pass: *"Three action bars, not one with three contents. Shaped
## differently, so genuinely three modules sharing one slot."*
##
## | mode | bar | shape |
## |---|---|---|
## | player | `ActionBarModule` | square action items, left-aligned, two rows, small padding |
## | spectator | `SpectatorBarModule` | playback controls, plus the old top-left cluster |
## | editor | `EditorBarModule` | labelled buttons — place, tiles, claims, save, load, run, undo |
##
## ## What is shared is the placement, and only the placement
##
## All three occupy `ModuleSlots.ACTION_ROW`, and all three publish the four satellite slots Pass B
## defined — because *"four surfaces pin relative to the action bar"* is a fact about **where the
## bar is**, and every mode's bar is in the same place. The combat log sits left of whichever bar
## the mode has; the UI buttons sit above its right edge. A mode that had a bar publishing nothing
## would strand every one of those surfaces on `ui_root` at (0,0), which is exactly the defect Pass
## C already had to chase out of the suite once.
##
## **Content is what differs, and content is the hook.** `_fill_bar` is the only thing a concrete
## bar overrides, and it is handed the column it should build into.
##
## ## Why three modules rather than one with a mode branch
##
## A single bar module reading which mode it is in would be a fourth answer to "what is the surface
## right now", after `ViewMode`, `ModeChrome` and the module set — and it would put the editor's
## save/load buttons in the same file as the player's AP affordability check. This project has
## deleted two visibility systems, two aiming paths and two overlay hierarchies; the taskblock names
## the failure mode in the pass title, so the shape is three modules and a shared base that owns
## nothing but the scaffolding.
##
## **The base is not a mode subclass wearing a new hat.** What forced the overlay fork was
## all-or-nothing inheritance of *behaviour* — Spectator wanted Squad's panels without its input.
## Nothing here has behaviour to inherit: it builds six containers and publishes four names.

## The bar's own root: the two rows, the four published slots and the concrete bar's content.
## **Moving this moves every dependant surface**, because they are its children rather than
## separately anchored to a screen corner — the whole reason a bar publishes slots.
var bar_root: VBoxContainer = null

## The four published slot containers. Public so a test reads back what was published rather than
## re-deriving where the bar put them.
var left_slot: HBoxContainer = null
var right_slot: HBoxContainer = null
var top_left_slot: HBoxContainer = null
var top_right_slot: HBoxContainer = null

## The column a concrete bar builds into, between `left_slot` and `right_slot`. A `VBoxContainer`
## so a bar wanting two rows stacks them rather than re-laying-out.
var content_column: VBoxContainer = null


## Bottom, centred, half a 16:9 screen wide — `BattleLayout.action_bar_rect`.
##
## **`ACTION_ROW` is bottom-pinned, so every bar is collapsible.** That was decided in Pass C for
## the player's bar (reversing a call made earlier in the same block) on the grounds that every
## edge-pinned slot is collapsible with no exceptions; the rule is not weakened by there being
## three bars in the slot rather than one.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_ROW


## taskblock-57 Pass B's mechanism, now used by three modules rather than one. Nothing in the host
## is special-cased: `ControlOverlay` publishes whatever any module returns from this hook.
##
## A concrete bar with slots of its own overrides this and merges — `SpectatorBarModule` publishes
## the pacing row and the tunables row it folded in, and that is what lets `PlaybackModule` and
## `TopLeftControlsModule` land in the bar without either of them knowing a bar exists.
func published_slots() -> Dictionary:
	return {
		ModuleSlots.ACTION_BAR_LEFT: left_slot,
		ModuleSlots.ACTION_BAR_RIGHT: right_slot,
		ModuleSlots.ACTION_BAR_TOP_LEFT: top_left_slot,
		ModuleSlots.ACTION_BAR_TOP_RIGHT: top_right_slot,
	}


func _mount() -> void:
	var row: Control = context.slot(preferred_slot(), null)

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
	# **No separation of its own, because padding belongs to the surfaces, not to the row.** The
	# table gives each satellite its own rule — the combat log is "padded" open and "flush against
	# the bar, no padding" minimised — and a container that inserts 4 px between every child makes
	# "flush" unreachable no matter what the log does. Each satellite pads itself; measured, after
	# the minimised log stopped 4 px short of the bar with its own margin already at zero.
	beside.add_theme_constant_override("separation", 0)
	bar_root.add_child(beside)
	left_slot = _slot_container(beside, false)

	content_column = VBoxContainer.new()
	content_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beside.add_child(content_column)

	right_slot = _slot_container(beside, false)

	_fill_bar(content_column)


## **What this bar actually is.** Override it; the base builds nothing, which is a legal bar — a
## mode wanting only the four satellite positions gets exactly that.
func _fill_bar(_column: VBoxContainer) -> void:
	pass


## Folds the bar and every surface published off it in one gesture — they are its children, which
## is the whole reason a bar publishes slots rather than four modules anchoring themselves near
## where they expect it to be.
func _on_collapsed(value: bool) -> void:
	if bar_root != null:
		bar_root.visible = not value


## **The bar's rect sizes the BAR; the cluster around it is wider, and has to grow both ways from
## the bar's centre rather than rightward from its left edge.**
##
## Measured, not assumed. The table gives the action bar "half a 16:9 screen wide" — 960 px — but
## the four surfaces published off it are outside that: the combat log alone asks for 520. Anchored
## at the region's top-left the cluster ran from x = 480 to x = 2220 on a 1920 screen, putting the
## End Turn button entirely off the display. A click test caught it; nothing about the code looked
## wrong.
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


## The one shared tooltip renderer, if this mode declared it before this bar. Null is a legal
## answer — every consumer already accepts one.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip") if context != null else null
	return (module as TooltipModule).view if module != null else null
