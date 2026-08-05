class_name InspectModule
extends ViewModule

## taskblock-56 Pass C: the inspect/status modal, and the button that opens it.
##
## **Both overlays built this and wired it differently, and both wirings survive here.**
## `SquadControlOverlay` gave it the live `SelectionController` and a `TacticsController` and opened
## it from a button; `SpectatorOverlay` gave it neither and opened it from a board click, pausing
## the bout. The panel itself was identical — same preferred size, same tree-before-`setup` order,
## same live-view lookup. What differed was who opens it, which is now the mode's business.
##
## **Added to the tree BEFORE `setup()`, and that order is load-bearing.** `setup()` builds a bot
## viewer whose `Camera3D.look_at()` needs a live tree to resolve a `Node3D`'s global transform
## against. Getting this backwards produces an error at construction, not at first open.
##
## **900x600 is the PREFERRED size, not an anchor.** `InspectPanel._clamp_to_viewport` shrinks and
## re-centres against the real viewport; a one-shot `PRESET_CENTER` never revisited was the "falls
## off the bottom" bug.
##
## Display: it describes what is already there and queues nothing.

## Emitted when the panel closes, so a mode that paused something to open it can resume.
signal closed
## taskblock-57 Pass C: emitted when the panel actually opens — **the one thing the debug menu
## budges for.** Paired with `closed` so a listener sees both edges rather than polling `visible`,
## and emitted only when `open_target` really opened something (`BR48.01`: a refused open must not
## look like an open).
signal opened

const PREFERRED_SIZE := Vector2(900, 600)

## Set before `mount`. `SquadControlOverlay` had an Inspect button in its left column;
## `SpectatorOverlay` opened the same panel from a board click and had none.
var with_button: bool = false

var panel: InspectPanel = null
var button: UiButton = null


func module_id() -> StringName:
	return &"inspect"


## Top-right, two thirds of the screen tall and square. **Escapes the safe rect**
## (`ModuleSlots.ESCAPING_SLOTS`) so it reaches the physical right edge on an ultrawide, and is
## edge-pinned, so this module is collapsible by the derivation in `ViewModule.is_collapsible`.
func preferred_slot() -> StringName:
	return ModuleSlots.INSPECT_PANEL


## **This module builds its own control in the cluster**, so the cluster must not build a second.
## Only when it was actually asked for one — a mode without `with_button` has no Inspect control at
## all and wants the derived toggle.
func provides_own_button() -> bool:
	return with_button


## The panel's own visibility, so its button lights whenever the inspector is up — including when a
## board click opened it, which is how it is opened in the spectator view.
func is_showing() -> bool:
	return panel != null and panel.visible


func _mount() -> void:
	panel = InspectPanel.new()
	# taskblock-57 Pass C3: **the 3D view may be somewhere else on the screen.** If this mode
	# declared `inspect_viewer` before this module, take its `BotViewer`; otherwise the panel builds
	# one inside its own body, exactly as it always did. Set BEFORE the panel is added to the tree,
	# because `setup()` builds against it.
	var supplied: ViewModule = context.module(&"inspect_viewer")
	if supplied != null:
		panel.viewer = (supplied as InspectViewerModule).viewer
	_place(panel)
	panel.closed.connect(_on_panel_closed)

	var tactics: TacticsController = context.tactics
	var selection: SelectionController = tactics.selection if tactics != null else null
	var lookup: Callable = context.battle.find_unit_view if context.battle != null else Callable()
	panel.setup(DataLibrary.material_table(), selection, lookup, tactics)

	if with_button:
		# **A `UiButton`, so it matches the cluster it sits in.** The supervisor's review of the
		# layout asked for every control in the UI-buttons row to be a square abbreviation with a
		# hover description; this one is built here rather than by `UiButtonsModule` because it owns
		# the enabled state that follows the selection (`BR51.10`), and splitting a control from the
		# thing that controls it is the split that rule exists to avoid.
		button = UiButton.build(
			UiButton.abbreviate(module_id()),
			"Inspect",
			"Opens the inspector on whatever is selected.",
			_tooltip_view()
		)
		# `BR51.10`: starts disabled, because nothing is selected yet. An affordance that lies about
		# what it can do reads as a broken action when it correctly does nothing.
		button.disabled = true
		button.pressed.connect(_on_button_pressed)
		# taskblock-57 Pass C: **the UI buttons cluster, above the bar's right edge** — the table's
		# "module toggles, Inspect, the debug menu". `LEFT_COLUMN` is the taskblock-56 fallback for
		# a mode whose chrome still builds one; a mode with neither gets the button on the module
		# itself, which is the stand-alone case.
		var column: Control = context.slots.get(ModuleSlots.LEFT_COLUMN)
		var host: Control = context.slot(ModuleSlots.ACTION_BAR_TOP_RIGHT, column)
		if host != null:
			host.add_child(button)
		else:
			add_child(button)


## The one shared tooltip renderer, if this mode declared it before this module. Null is legal and
## means the button carries no hover description.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip") if context != null else null
	return (module as TooltipModule).view if module != null else null


## **The slot's rect IS the panel's rect** when the mode publishes one — the table's "~2/3 screen
## tall, square" is the region's size, so filling it is the placement rather than an approximation
## of it, and `placed_by_host` is what stops the panel re-centring itself on the next resize.
##
## **`PREFERRED_SIZE` is applied only in the unplaced case, and that was measured**: a 900 px
## minimum width silently wins over a 720 px slot, so the panel read as placed while being 180 px
## wider than the square the table asks for. A preferred size and a declared slot are two answers to
## one question; this block made the slot the authoritative one.
func _place(target: InspectPanel) -> void:
	# **Asked of `slots` directly, NOT through `context.slot`**: that helper falls back to `ui_root`,
	# so the spectator and editor modes — which publish no `inspect_panel` slot — would come back
	# with a non-null answer and get a modal stretched over the entire screen. The fallback is right
	# for a module looking for somewhere to hang a child; it is wrong for one asking "was I placed".
	var slot: Control = context.slots.get(preferred_slot())
	if slot != null:
		target.placed_by_host = true
		slot.add_child(target)
		target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	target.custom_minimum_size = PREFERRED_SIZE
	if context.ui_root != null:
		context.ui_root.add_child(target)
	else:
		add_child(target)


## The button's enabled state follows the selection.
func link() -> void:
	var input: ViewModule = context.module(&"unit_input")
	if input != null:
		(input as UnitInputModule).selection_changed.connect(refresh_button)


## Opens on whatever the selection currently holds. Since taskblock-51 Pass K that includes cover:
## `open_cell` could always describe a loose part, the selection simply could never hold one.
func open_selected() -> void:
	var tactics: TacticsController = context.tactics if context != null else null
	if tactics == null or tactics.selection == null:
		return
	open_target(tactics.selection.selected_target)


## **Only opens what the panel can describe.** `BR48.01`: opening the modal for a target it cannot
## render leaves the dim over the board with nothing on top of it, which reads as a stuck dim rather
## than a refused action. Returns whether it actually opened, so a caller that pauses a bout only
## pauses when something is on screen.
func open_target(target: SelectionTarget) -> bool:
	if panel == null or target == null or not target.can_inspect():
		return false
	if target.is_unit():
		panel.open(target.unit)
	else:
		panel.open_cell(target.cell, target.part)
	opened.emit()
	return true


## Opens a cell's own root part directly — the coarse pick a spectator's ground-plane click
## produces when the ray missed the blocker's body but hit the cell it stands on.
func open_cell(cell: Vector2i, part: Part) -> bool:
	if panel == null or part == null:
		return false
	panel.open_cell(cell, part)
	opened.emit()
	return true


## Drives the button's enabled state from whether the TARGET has something to describe, not from
## whether anything has been clicked — a bare cell is a real selection with nothing to inspect
## (`BR51.10`). Called by the mode on selection changes.
func refresh_button() -> void:
	if button == null:
		return
	var tactics: TacticsController = context.tactics if context != null else null
	button.disabled = (
		tactics == null or tactics.selection == null or not tactics.selection.can_inspect()
	)


## Closes rather than merely hides, so the debug menu un-budges and a paused bout resumes — a
## collapse that left the surface believing Inspect was still open would strand the menu off centre.
func _on_collapsed(value: bool) -> void:
	if value and panel != null and panel.visible:
		panel.close()


func _on_panel_closed() -> void:
	# The panel closes from its own control and from a board click as well as from the button, so
	# the border is refreshed on the close itself rather than at each of the places that cause one.
	refresh_border()
	closed.emit()


## **Summon, then dismiss.** The UI review collapsed every control in the cluster to one feel:
## *"Button 'on', button is highlighted and module is visible. Button 'off', button is
## un-highlighted and module is disabled/hidden."* This button used to only ever open, which is why
## it read as the one that "always does something" beside two collapse toggles that appeared to do
## nothing.
func _on_button_pressed() -> void:
	if panel != null and panel.visible:
		panel.close()
	else:
		open_selected()
	refresh_border()


## Lights the button while the panel is up. Called every frame from `tick` as well as on the edges,
## because the panel opens and closes from board clicks and from its own control — neither of which
## goes through this button.
func refresh_border() -> void:
	if button != null:
		button.active = is_showing()


func tick(_delta: float) -> void:
	refresh_border()
