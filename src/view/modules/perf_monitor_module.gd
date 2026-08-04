class_name PerfMonitorModule
extends ViewModule

## taskblock-57 Pass C: **the performance readout, in the true bottom-right corner.**
##
## ## Why it left `DebugPanelModule`
##
## The readout was owned by the debug-panel module because the debug panel is where its toggle is
## offered. Pass C's table gives it its own placement — *"true bottom-right corner, no padding,
## click-through and mostly transparent"* — and a module declares **one** `preferred_slot()`. A
## surface welded inside another module cannot be in its own slot, so "is every surface in its
## declared place" would have been unanswerable for this one.
##
## **The ownership rule it was built under is unchanged and is why this is a module rather than a
## panel the debug menu parents**: closing the debug panel must not take the readout down with it.
## You open the debug panel to switch the readout on, then get the panel out of the way and keep
## watching the numbers while you play. The two are tied only at the point of *offering* the toggle,
## which is now a signal this module subscribes to instead of a field the other one held.
##
## ## It takes the FPS readout off the combat log
##
## taskblock-41 drew a live FPS figure on the combat log's title bar, because at the time there was
## nowhere else for it. Pass C's table says to use *"the existing perf stats from the debug menu
## rather than the log's"* — so `CombatLogPanel` no longer carries a meter, and this is the one
## framerate surface. Two readouts sampling two different meters and disagreeing by a frame is the
## kind of thing that costs an afternoon.
##
## ## Click-through, with two deliberate exceptions
##
## The background and every line of text are `MOUSE_FILTER_IGNORE`, so a readout sitting over the
## board's corner never eats a camera drag. **The dump checkbox and the Reset button keep their own
## clicks** — a control you cannot press is not a control, and the alternative was moving them into
## the debug menu, whose redesign this block explicitly does not do. Recorded rather than quietly
## decided: the table says "click-through", and this is click-through everywhere except the two
## pixels that are targets.
##
## Display: it reads frame times and draws them. It queues nothing.

## **Mostly transparent**, per the table — against `PerfPanel`'s own 0.82, which was chosen when the
## readout sat in an empty top-right corner rather than over the board. A flagged starting position,
## not a decision; the supervisor's fine-tuning pass owns it.
const BACKGROUND_ALPHA := 0.35

var panel: PerfPanel = null


func module_id() -> StringName:
	return &"perf_monitor"


## The true bottom-right corner. **Escapes the safe rect** (`ModuleSlots.ESCAPING_SLOTS`), so on an
## ultrawide it sits in the physical corner rather than at the letterbox's inner edge — which is the
## one place a readout is least in the way.
func preferred_slot() -> StringName:
	return ModuleSlots.PERF_MONITOR


func _mount() -> void:
	panel = PerfPanel.new()
	panel.visible = false
	panel.background_alpha = BACKGROUND_ALPHA
	panel.stats_ticked.connect(_on_stats_ticked)
	var slot: Control = context.slot(preferred_slot(), null)
	if slot == null:
		# No host surface at all — the stand-alone case taskblock-56 Pass C's acceptance requires.
		# The readout is still real and still samples; it simply has nowhere to be drawn.
		add_child(panel)
		return
	slot.add_child(panel)
	_pin_to_bottom_right(panel)


## **All four anchors and all four offsets, set explicitly** — the lesson already written into
## `PerfPanel`'s own history, applied a third time because a preset got it wrong again.
##
## `set_anchors_preset` recomputes offsets to preserve the control's *current* rect, and at mount
## time the parent has not been laid out: preserving a rect measured against a zero-width parent put
## the readout at x = -420, entirely off the left of the screen. Measured, not guessed — it is what
## `test_debug_panel_layout.gd` reported.
##
## Four anchors at 1 with four zero offsets is a zero-size rect pinned to the bottom-right corner,
## whenever it is evaluated. `grow BEGIN` on both axes then expands the panel's minimum size up and
## to the left, out of the corner. **No padding**, which is the table's own word.
##
## This is also why the same call serves both parents. The slot is a zero-sized region already at
## the corner (`BattleLayout.perf_monitor_rect`), so its bottom-right *is* that corner; with no slot
## the parent is `ui_root` and the corner is the viewport's. One rule, two hosts.
static func _pin_to_bottom_right(target: Control) -> void:
	target.anchor_left = 1.0
	target.anchor_top = 1.0
	target.anchor_right = 1.0
	target.anchor_bottom = 1.0
	target.offset_left = 0.0
	target.offset_top = 0.0
	target.offset_right = 0.0
	target.offset_bottom = 0.0
	target.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	target.grow_vertical = Control.GROW_DIRECTION_BEGIN


## The toggle is offered by the debug panel and consumed here. **A signal, not a field the other
## module holds** — that is the whole of what changed when this surface moved out of it.
func link() -> void:
	var debug: ViewModule = context.module(&"debug_panel")
	if debug != null:
		(debug as DebugPanelModule).ui_element_toggled.connect(_on_ui_element_toggled)


func _on_ui_element_toggled(element: StringName, shown: bool) -> void:
	if element == DebugUiElements.PERF_PANEL and panel != null:
		panel.visible = shown


## The panel emits; this writes. **A view reaching into a `CombatState` to log would be the second
## logging path this project keeps deleting** — carried over verbatim from the module this left,
## because the reason is unchanged by the move.
func _on_stats_ticked(snapshot: Dictionary) -> void:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.combat_state == null:
		return
	battle.combat_state.combat_log.emit(
		LogEvent.new(
			battle.combat_state.round_number,
			Enums.Phase.RESOLUTION,
			-1,
			&"fps_dump",
			snapshot,
			"perf: %s" % " | ".join(panel.stats.describe())
		)
	)
