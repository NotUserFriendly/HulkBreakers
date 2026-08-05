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

## How solid the bar's own background is. A starting position, not a decision — matched to
## `CombatLogPanel.BACKGROUND_ALPHA` so the two surfaces beside each other read as one chrome.
const BACKGROUND_ALPHA := 0.82

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

## The panel drawing the bar's own background, and the thing that IS the bar's rect. Public so a
## test reads the drawn size back rather than re-deriving it.
var backing: PanelContainer = null


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
	var band: Vector2 = _band_size()

	# The bar and everything pinned to it, as one subtree.
	bar_root = VBoxContainer.new()
	bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if row != null:
		row.add_child(bar_root)
		_span_the_safe_width(bar_root, _safe_width())
	else:
		add_child(bar_root)

	# **Two anchored rows, not two containers, and that is what makes the centring exact.**
	#
	# The supervisor's review: *"Action bar needs to be the centered item, with the combat log to the
	# side of it. Currently the combined action bar and combat log space are centered."*
	#
	# The first attempt at the fix used two equally-expanding wings around the bar, which looks like
	# it centres and does not: an `HBoxContainer` distributes only the *leftover* space equally, on
	# top of each child's own minimum — so a 520 px combat log on one side and a narrow turn column
	# on the other still pushed the bar 48 px right of centre. **Measured, not reasoned: the bar's
	# centre came out at 1008 against a screen centre of 960.**
	#
	# Anchoring each piece against the band's own arithmetic has no such dependency. The bar sits on
	# the centre line at the width `BattleLayout` gives it; each satellite pins its inner edge to one
	# of the bar's edges and grows outward. What is in them cannot move the bar.
	var above := _anchored_row(bar_root, UiLayout.scaled(UiButton.SIDE))
	# Centred over the bar, which is the table's word and a second review point: *"This is supposed
	# to be centered above the action bar, not left aligned."*
	top_left_slot = _slot_container(above, false)
	_pin_centred(top_left_slot, band.x)
	# **Centred WITHIN the slot too.** The slot spans the bar; without this its content sits at the
	# slot's left edge, which is where the review found the unit resources — measured at x = 541
	# against a bar centre of 960, which is the bar's left edge plus half the readout.
	top_left_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	# And the UI buttons at the bar's right edge, which is the other half of the same row.
	top_right_slot = _slot_container(above, false)
	_pin_inside_right(top_right_slot, band.x)

	var beside := _anchored_row(bar_root, band.y)

	# **The bar's own background**, which the review found missing outright. A panel rather than a
	# `ColorRect` so it takes the theme's own corner and border treatment if one is ever added.
	backing = PanelContainer.new()
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, BACKGROUND_ALPHA
	)
	backing.add_theme_stylebox_override("panel", style)
	beside.add_child(backing)
	# **A fixed rect, not a strip that grows to its content** — the third review point. The band from
	# `BattleLayout` is the size, so the bar is what the placement table says it is and whatever goes
	# in it is fitted rather than allowed to set the height.
	_pin_centred(backing, band.x)
	backing.anchor_top = 0.0
	backing.offset_top = 0.0

	content_column = VBoxContainer.new()
	content_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.add_child(content_column)

	# The satellites, hanging off the bar's two edges and growing away from it.
	left_slot = _slot_container(beside, false)
	_pin_beside(left_slot, band.x, 1.0)
	right_slot = _slot_container(beside, false)
	_pin_beside(right_slot, band.x, -1.0)

	_fill_bar(content_column)


## Re-anchors everything against the screen's new shape. The battle layout places absolutely, so
## the safe rect and the band this was built against are both stale after a resize.
func relaid_out() -> void:
	if bar_root == null or bar_root.get_parent() is not Control:
		return
	var band: Vector2 = _band_size()
	_span_the_safe_width(bar_root, _safe_width())
	_pin_centred(top_left_slot, band.x)
	_pin_inside_right(top_right_slot, band.x)
	_pin_centred(backing, band.x)
	backing.anchor_top = 0.0
	backing.offset_top = 0.0
	_pin_beside(left_slot, band.x, 1.0)
	_pin_beside(right_slot, band.x, -1.0)
	for host: Control in [top_left_slot.get_parent(), backing.get_parent()]:
		if host != null:
			host.custom_minimum_size.y = (
				band.y if host == backing.get_parent() else UiLayout.scaled(UiButton.SIDE)
			)


## A full-width row inside `bar_root` that its children anchor themselves within.
##
## **A plain `Control`, deliberately** — a container would position its children by its own rules,
## which is exactly the thing the wings got wrong. `height` is a floor: a child taller than it grows
## upward out of the row, which is what the surfaces above the bar are supposed to do.
func _anchored_row(parent: VBoxContainer, height: float) -> Control:
	var strip := Control.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.custom_minimum_size = Vector2(0.0, height)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(strip)
	return strip


## Pins `target` centred on its row, `width` wide, bottom-aligned and growing upward.
static func _pin_centred(target: Control, width: float) -> void:
	target.anchor_left = 0.5
	target.anchor_right = 0.5
	target.offset_left = -width * 0.5
	target.offset_right = width * 0.5
	_pin_to_the_bottom(target)


## Pins `target`'s RIGHT edge to the right edge of a bar `width` wide, growing leftward — a surface
## that sits *within* the bar's span rather than beside it.
##
## The distinction from `_pin_beside` is which side of the bar's edge the surface lives on. The turn
## controls hang off the outside of the right edge; the UI buttons sit above the bar and end at that
## same edge. Pinning the UI buttons the way the turn controls are pinned put them 332 px past the
## bar's right edge, which is where the review's *"only some of the UI buttons are correct"* was
## looking.
static func _pin_inside_right(target: Control, width: float) -> void:
	target.anchor_left = 0.5
	target.anchor_right = 0.5
	target.offset_left = width * 0.5
	target.offset_right = width * 0.5
	target.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pin_to_the_bottom(target)


## Pins `target`'s inner edge to one edge of a bar `width` wide, growing away from it. `side` is +1
## for the surface on the bar's left and -1 for the one on its right.
static func _pin_beside(target: Control, width: float, side: float) -> void:
	var edge: float = width * 0.5 * -side
	target.anchor_left = 0.5
	target.anchor_right = 0.5
	target.offset_left = edge
	target.offset_right = edge
	target.grow_horizontal = (
		Control.GROW_DIRECTION_BEGIN if side > 0.0 else Control.GROW_DIRECTION_END
	)
	_pin_to_the_bottom(target)


## Bottom-aligned within its row, growing upward — every surface on this bar hangs off the same
## baseline, which is what makes a taller satellite rise rather than push the bar down.
static func _pin_to_the_bottom(target: Control) -> void:
	target.anchor_top = 1.0
	target.anchor_bottom = 1.0
	target.offset_top = 0.0
	target.offset_bottom = 0.0
	target.grow_vertical = Control.GROW_DIRECTION_BEGIN


## The rect `BattleLayout` gives the bar at the current screen size, or a zero size with no host.
func _band_size() -> Vector2:
	var root: Control = context.ui_root if context != null else null
	if root == null:
		return Vector2.ZERO
	return BattleLayout.action_bar_rect(root.size).size


func _safe_width() -> float:
	var root: Control = context.ui_root if context != null else null
	return UiLayout.safe_rect(root.size).size.x if root != null else 0.0


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


## **Spans the safe width, bottom-aligned on the band, so the wings inside it have room to be
## symmetrical.**
##
## Measured, not assumed. The table gives the action bar "half a 16:9 screen wide" — 960 px — but
## the surfaces published off it are outside that: the combat log alone asks for 520. A root sized
## to the band could not hold them, and a root centred on the band centred the *cluster* rather
## than the bar, which is the review point this pass is fixing.
##
## The band is centred in the safe rect, so anchoring at the region's own horizontal centre and
## reaching half the safe width each way lands exactly on the safe rect — no second copy of where
## the band is.
##
## A no-op when the slot is a real `Container` (the taskblock-56 layouts' `ACTION_ROW` is an
## `HBoxContainer`), which positions its children itself and ignores their anchors.
static func _span_the_safe_width(target: Control, safe_width: float) -> void:
	target.anchor_left = 0.5
	target.anchor_right = 0.5
	target.anchor_top = 1.0
	target.anchor_bottom = 1.0
	target.offset_left = -safe_width * 0.5
	target.offset_right = safe_width * 0.5
	target.offset_top = 0.0
	target.offset_bottom = 0.0
	target.grow_horizontal = Control.GROW_DIRECTION_BOTH
	target.grow_vertical = Control.GROW_DIRECTION_BEGIN


## One published slot container, added to `parent` and left for the caller to anchor.
##
## `parent` is any `Control`, not a `Container`: the bar's rows are plain `Control`s so their
## children can anchor against the band's own arithmetic rather than being positioned by a
## container's rules — which is what made the first attempt at centring the bar miss by 48 px.
##
## `MOUSE_FILTER_IGNORE`, like every other wrapping container in the layout: these span real width
## and would otherwise swallow camera drags that started over them before `CameraRig` ever saw the
## event. **Whatever mounts INTO the slot sets its own filter**; an empty slot must never be a dead
## patch of screen.
func _slot_container(parent: Control, _expanding: bool = false) -> HBoxContainer:
	var slot := HBoxContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)
	return slot


## The one shared tooltip renderer, if this mode declared it before this bar. Null is a legal
## answer — every consumer already accepts one.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip") if context != null else null
	return (module as TooltipModule).view if module != null else null
