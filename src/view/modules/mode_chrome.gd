class_name ModeChrome
extends RefCounted

## taskblock-56 Pass D: the named layouts a mode may ask for, and the slots each publishes.
##
## **Chrome is the one thing a mode owns that a module cannot.** Where a panel sits is a property of
## the surface, not of the panel — moving the queue list from the readout column to the left column
## should be a mode's decision and should touch no module. So a mode names a layout, this builds it,
## and the containers it produces are published as `ModuleSlots` names that modules ask for.
##
## **Every layout is optional from a module's point of view.** A module asking for a slot no layout
## published falls back to `ui_root` or to itself — which is what lets the same module appear in the
## player's four-region layout and the spectator's two top-left rows without knowing which it is in.
##
## ## The mouse filters are load-bearing, not tidiness
##
## A bare `Control` defaults to `MOUSE_FILTER_STOP`. The wrapping containers below span half the
## screen each, so without `IGNORE` they swallow every RMB/MMB camera drag that starts over them
## before `CameraRig._unhandled_input` ever sees the event. The two rows that carry real buttons
## keep `STOP` deliberately: those are controls, not a pass-through gap.

## Four independently anchored regions: a full-height left column (weapons list, Inspect, the
## combat log at its bottom), a top-right column (keybindings legend), and a bottom-right stack
## (the readout panel above the action bar / turn controls row). Not one long sidebar.
const PLAYER_COLUMNS := &"player_columns"
## Two top-left rows — pacing controls and the shared cluster on the first, timing tunables on the
## second — and nothing else. Everything else in this layout anchors itself.
const TOP_LEFT_ROWS := &"top_left_rows"
## A single centred column, for a menu that owns the whole screen.
const CENTERED_MENU := &"centered_menu"
## taskblock-57 Pass C: **the layout.** Every surface in the block's own placement table, built
## against `UiLayout`'s safe rect rather than against raw screen anchors.
const BATTLE_LAYOUT := &"battle_layout"

const TOP_LEFT_MARGIN := Vector2(16, 16)
const TUNABLES_MARGIN := Vector2(16, 48)


## Builds `chrome` into `ui_root` and publishes its slots on `context`. An unknown name builds
## nothing, which is a legal mode: every module falls back to `ui_root`.
static func build(chrome: StringName, ui_root: Control, context: ModuleContext) -> void:
	match chrome:
		PLAYER_COLUMNS:
			_player_columns(ui_root, context)
		TOP_LEFT_ROWS:
			_top_left_rows(ui_root, context)
		CENTERED_MENU:
			_centered_menu(ui_root, context)
		BATTLE_LAYOUT:
			_battle_layout(ui_root, context)


static func _player_columns(ui_root: Control, context: ModuleContext) -> void:
	# Anchored full-height on the left edge but with NO right-anchor stretch, so its width comes
	# from its own content rather than from half the screen.
	var left_half := _region(ui_root, Control.PRESET_LEFT_WIDE)
	var left_layout := VBoxContainer.new()
	left_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_half.add_child(left_layout)
	context.set_slot(ModuleSlots.LEFT_COLUMN, left_layout)

	var inventory_row := HBoxContainer.new()
	inventory_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_layout.add_child(inventory_row)
	context.set_slot(ModuleSlots.INVENTORY_ROW, inventory_row)

	# Spans the right half — the legend and the bottom-right stack anchor to two different corners
	# within it — but must not itself swallow camera drags over that half of the board.
	var right_half := _region(ui_root, Control.PRESET_RIGHT_WIDE)
	right_half.anchor_left = 0.5

	var top_right := VBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_half.add_child(top_right)
	context.set_slot(ModuleSlots.TOP_RIGHT, top_right)

	var bottom_right := VBoxContainer.new()
	bottom_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_right.alignment = BoxContainer.ALIGNMENT_END
	bottom_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_half.add_child(bottom_right)
	context.set_slot(ModuleSlots.BOTTOM_RIGHT, bottom_right)

	# The readout and the queued-actions list get their own boxed panel, sized to its own content.
	# `SHRINK_END` keeps it from being stretched to the action bar's much wider row below, which
	# sharing one `VBoxContainer` used to force.
	var readout_panel := PanelContainer.new()
	readout_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	readout_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_right.add_child(readout_panel)
	var readout_column := VBoxContainer.new()
	readout_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout_panel.add_child(readout_column)
	context.set_slot(ModuleSlots.READOUT_COLUMN, readout_column)

	# taskblock-08 E1: "action bar on the LEFT, the turn-control stack to its RIGHT" — one row, two
	# columns, replacing the single vertical stack the pips, bar and buttons used to share.
	var action_row := HBoxContainer.new()
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_right.add_child(action_row)
	context.set_slot(ModuleSlots.ACTION_ROW, action_row)


static func _top_left_rows(ui_root: Control, context: ModuleContext) -> void:
	context.set_slot(ModuleSlots.TOP_LEFT, _button_row(ui_root, TOP_LEFT_MARGIN))
	context.set_slot(ModuleSlots.TUNABLES, _button_row(ui_root, TUNABLES_MARGIN))


static func _centered_menu(ui_root: Control, context: ModuleContext) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	ui_root.add_child(column)
	context.set_slot(ModuleSlots.MENU_COLUMN, column)


## taskblock-57 Pass C: **the placement table, built.**
##
## Thin on purpose. Every rect comes from `BattleLayout`, which is pure logic and is where the
## arithmetic is tested; this only turns answers into `Control`s. A chrome full of anchor presets
## whose only test is a screenshot is what that split avoids.
##
## **The action bar is placed; its four satellites are not.** Those are published by the bar itself
## (Pass B) and move with it, which is the entire reason that mechanism exists.
static func _battle_layout(ui_root: Control, context: ModuleContext) -> void:
	var rects: Dictionary = BattleLayout.slot_rects(ui_root.size)
	for slot: StringName in rects:
		context.set_slot(slot, _placed(ui_root, rects[slot] as Rect2))
	_legacy_readout(ui_root, context)


## **A holding pen for the three surfaces Pass D deletes, and it goes with them.**
##
## `queue_panel`, `stat_panels` and `controls_legend` are not in the placement table because the
## taskblock retires or relocates all three in the very next pass. Switching the player mode to this
## layout without them would strand each one on `ui_root` at (0,0) — stacked on top of each other
## and on top of the debug menu, which is not "unplaced", it is broken. **Two passes of churn on the
## same files is the alternative**, and a deliberately labelled temporary beats a surface that does
## not work for a pass.
##
## Pinned bottom-right, which is where all three sat under `PLAYER_COLUMNS`, so nothing moves that
## Pass D is not about to remove anyway.
##
## **Delete this function when `queue_panel` and `stat_panels` retire.** Nothing else uses these
## three slot names once `controls_legend` moves into the UI buttons cluster.
static func _legacy_readout(ui_root: Control, context: ModuleContext) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# **Raised clear of the action bar's band, and that is not cosmetic.** Under `PLAYER_COLUMNS`
	# this column sat directly above the action row in one `VBoxContainer`, so they could not
	# overlap. Anchored independently they can: the queue panel is wide, it grows leftward from the
	# right edge, and it reached far enough left to cover the End Turn button — clicks landed on the
	# panel instead of the button. Caught by `test_battle_scene_input.gd`, which pushes a real click
	# at the button's real rect, not by looking at it.
	column.offset_bottom = -UiLayout.scaled(BattleLayout.ACTION_BAR_HEIGHT + BattleLayout.PADDING)
	ui_root.add_child(column)
	context.set_slot(ModuleSlots.READOUT_COLUMN, column)
	context.set_slot(ModuleSlots.INVENTORY_ROW, column)

	var legend := VBoxContainer.new()
	legend.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	legend.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(legend)
	context.set_slot(ModuleSlots.TOP_RIGHT, legend)


## **Re-places an already-built layout against a new screen size.**
##
## The other three layouts anchor their regions with presets and survive a resize for free. This one
## places absolutely — which is what makes it testable arithmetic instead of a screenshot — and
## absolute positions do not follow a window that changes shape. **That is a real regression the
## moment the layout goes live**, not a nicety: going fullscreen would strand every surface at the
## windowed size.
##
## Re-positions the regions that already exist rather than rebuilding them, because the modules are
## mounted **into** those regions; rebuilding would orphan every panel on the surface.
##
## An unknown chrome, or one whose regions were never built, does nothing.
static func relayout(chrome: StringName, ui_root: Control, context: ModuleContext) -> void:
	if chrome != BATTLE_LAYOUT or ui_root == null or context == null:
		return
	var rects: Dictionary = BattleLayout.slot_rects(ui_root.size)
	for slot: StringName in rects:
		var region: Control = context.slots.get(slot)
		if region == null:
			continue
		var rect: Rect2 = rects[slot]
		region.position = rect.position
		region.custom_minimum_size = rect.size
		region.size = rect.size


## A positioned, click-through region. **`MOUSE_FILTER_IGNORE` on every one**, like the wrapping
## regions the other layouts build: these span real area and would otherwise swallow the camera
## drags that start over them before `CameraRig._unhandled_input` ever sees the event. Whatever
## mounts into the slot sets its own filter, so an empty slot is never a dead patch of screen.
static func _placed(ui_root: Control, rect: Rect2) -> Control:
	var region := Control.new()
	region.set_anchors_preset(Control.PRESET_TOP_LEFT)
	region.position = rect.position
	region.custom_minimum_size = rect.size
	region.size = rect.size
	region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(region)
	return region


## **The one-off the taskblock names**: the debug menu shifts left when Inspect would overlap it,
## and nothing else budges for anything.
##
## Re-placed from `BattleLayout`'s answer rather than nudged from where it currently sits, so
## calling this repeatedly cannot walk the menu across the screen.
static func budge_debug_menu(context: ModuleContext, screen: Vector2, inspect_open: bool) -> void:
	var menu: Control = context.slots.get(ModuleSlots.DEBUG_MENU)
	if menu == null:
		return
	menu.position = BattleLayout.budged_debug_menu_rect(screen, inspect_open).position


static func _region(ui_root: Control, preset: int) -> Control:
	var region := Control.new()
	region.set_anchors_preset(preset)
	region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(region)
	return region


## `STOP`, unlike the wrapping regions above — these rows carry real buttons.
static func _button_row(ui_root: Control, margin: Vector2) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	row.position = margin
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(row)
	return row
