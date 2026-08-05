class_name UiButtonsModule
extends ViewModule

## taskblock-57 Pass C: **the UI buttons cluster, above the bar's right edge.**
##
## The table's row is *"module toggles, Inspect, the debug menu"*. Inspect brings its own button —
## it owns the enabled state that follows the selection (`BR51.10`) and splitting the button from
## the panel would be splitting a control from the thing it controls — so what this module builds is
## the other two: one toggle per collapsible module, and the debug menu's.
##
## ## This is what makes A2's collapse rule reachable
##
## taskblock-57 A2: *every side-pinned surface is collapsible or off by default, so a square-ratio
## player is never forced to shrink the UI to play. They lose nothing; they toggle.* Until now
## `ViewModule.collapsed` was a flag with a hook and no way to reach it. **A rule whose affordance
## does not exist is a rule nobody can use**, so the toggles are built here, from the modules that
## report themselves collapsible, rather than from a list.
##
## ## Derived, never listed
##
## The toggles come from sweeping `context.modules` for `is_collapsible()`, and the label comes from
## the module's own id. **No module is named in this file.** A module added later — or re-slotted
## onto an edge later — grows a toggle the day it does, with no edit here, which is the standing
## "content is data, not a code edit" rule applied to the control surface itself.
##
## Built in `link()`, not `_mount()`: the sweep needs every module mounted, and `link()` is the hook
## that runs after all of them are.
##
## Display: it toggles panels. It never queues an action against a unit.

## Shown when a debug build offers the menu. Absent entirely in a release export, where
## `DebugPanelModule` never constructs a panel at all.
const DEBUG_MENU_LABEL := "Debug"
const DEBUG_MENU_ABBREV := "DBG"

## The row every button lands in, so a test reads back what was built rather than re-deriving it.
var row: HBoxContainer = null
## Module id -> the `UiButton` that folds it, for a test and for a later options menu.
var toggles: Dictionary = {}
var debug_button: UiButton = null


func module_id() -> StringName:
	return &"ui_buttons"


## Above the bar, at its right edge — a slot the bar publishes, so the cluster travels with it.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_BAR_TOP_RIGHT


func _mount() -> void:
	var slot: Control = context.slot(preferred_slot(), null)
	row = HBoxContainer.new()
	# The row itself is not a target; its buttons are. Same rule every wrapping container in the
	# layout follows, so an empty cluster is never a dead patch of screen over the board.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if slot != null:
		slot.add_child(row)
	else:
		add_child(row)


## One toggle per collapsible module, then the debug menu's button. **Order is the mode's own
## declaration order**, which is stable and readable, rather than alphabetical or arbitrary.
func link() -> void:
	# **The bar's own toggle is built last and smaller**, which the UI review asked for: *"Can the
	# Action/spectator/edit bar toggle button be the farthest to the right, and ~70% the size of the
	# other UI buttons?"* Deferred rather than sorted, because "last" is the only ordering claim
	# being made and a sort key would be a second thing to keep true.
	var bar_id: StringName = &""
	for id: StringName in context.modules:
		var module: ViewModule = context.modules[id]
		# **A module with its own control in this row does not get a second one.** See
		# `ViewModule.provides_own_button` — this is what produced three Inspect buttons and two
		# debug buttons, two of each doing something subtly different from the one that worked.
		if module == self or not module.is_collapsible() or module.provides_own_button():
			continue
		# Identified by class, not by id, so a fourth mode's bar is covered the day it is written.
		if module is BarModule:
			bar_id = id
			continue
		toggles[id] = _toggle(id, module)
	var debug: ViewModule = context.module(&"debug_panel")
	if debug != null and (debug as DebugPanelModule).panel != null:
		debug_button = UiButton.build(
			DEBUG_MENU_ABBREV, DEBUG_MENU_LABEL, "Opens and closes the debug menu.", _tooltip_view()
		)
		debug_button.pressed.connect(_on_debug_pressed)
		row.add_child(debug_button)

	# Last of all, so it really is the farthest right in the row.
	if bar_id != &"":
		toggles[bar_id] = _toggle(bar_id, context.module(bar_id), UiButton.SECONDARY_SCALE)


## A readable label from the module's own id, so no module is named here. `unit_resources` reads as
## "Unit Resources"; a module added later gets a sensible label without an entry in a table.
static func label_for(id: StringName) -> String:
	return String(id).replace("_", " ").capitalize()


## One square toggle for `module`. **A `UiButton`, not a `CheckButton` with a sentence on it** —
## the supervisor's review: *"all toggles and descriptive text should be replaced with square
## BUTTONS with an up-to three letter abbreviation on them."* The sentence did not disappear; it
## moved into the hover description, which is where a row of controls can afford one.
func _toggle(id: StringName, module: ViewModule, scale: float = 1.0) -> UiButton:
	var button: UiButton = UiButton.build(
		UiButton.abbreviate(id),
		label_for(id),
		"Summons and dismisses the %s module." % label_for(id),
		_tooltip_view(),
		scale
	)
	# **A press flips it**, which is the summon/dismiss feel the review asked every button in this
	# row to share. `collapsed` stays the module's own inverse-sense field; nothing about what it
	# means changed, only how it is reached.
	button.active = module.is_showing()
	# **The press only flips the flag.** The border is re-read every frame from `is_showing()` — see
	# `tick` — because a button that lit itself would go on claiming a panel is up after anything
	# else closed it.
	button.pressed.connect(func() -> void: module.collapsed = not module.collapsed)
	row.add_child(button)
	return button


## Re-reads every border from what is actually on screen.
##
## **Per frame, not per press**, which is the UI review's *"the button highlight should only appear
## if the window is visible, even if it's launched some other way."* Inspect opens from a board
## click, the keybindings sheet from the H key, and the debug menu from its own close control —
## none of which go through the button that claims to own them.
func tick(_delta: float) -> void:
	for id: StringName in toggles:
		var module: ViewModule = context.module(id)
		if module != null:
			(toggles[id] as UiButton).active = module.is_showing()
	_refresh_debug_border()


## The one shared tooltip renderer, if this mode declared it. Null is a legal answer and means the
## buttons carry no hover description — see `UiButton`.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip") if context != null else null
	return (module as TooltipModule).view if module != null else null


func _on_debug_pressed() -> void:
	var debug: ViewModule = context.module(&"debug_panel")
	if debug != null:
		(debug as DebugPanelModule).toggle()


func _refresh_debug_border() -> void:
	var debug: ViewModule = context.module(&"debug_panel")
	if debug_button != null and debug != null:
		var panel: DebugControlPanel = (debug as DebugPanelModule).panel
		debug_button.active = panel != null and panel.visible
