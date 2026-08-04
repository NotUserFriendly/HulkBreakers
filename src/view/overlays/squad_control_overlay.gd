class_name SquadControlOverlay
extends ControlOverlay

## "A squad — select-then-command (`TacticsController`) — the current experience."
##
## `wants_turn_for` reads `CombatState.controller_for` exactly as it always has; the capability this
## overlay adds over a bout is auto-resolving any squad a designer or test flips to AI
## (`ControlOverlay.advance_ai_turns`).
##
## ## taskblock-56 Pass C: 942 lines became chrome plus a module list
##
## Everything this file used to build panel by panel is a `ViewModule` in `src/view/modules/`, and
## every module here except the three input ones is **shared with the spectator view** rather than
## written a second time. What is left is the two things a mode genuinely owns: the **chrome** (four
## independently anchored regions and the containers inside them) and the **declaration** of which
## modules hang in them.
##
## **The layout notes stayed with the layout, and they are load-bearing.** `mouse_filter = IGNORE`
## on every wrapping container is not tidiness: a bare `Control` defaults to `STOP`, and these span
## half the screen each — they would swallow every RMB/MMB camera drag that started over them before
## `CameraRig._unhandled_input` ever saw it. The columns' anchoring is likewise deliberate: the left
## one is full-height with **no right-anchor stretch**, so its width comes from its own content
## rather than from half the screen.
##
## Fields below are aliases into the mounted modules, kept because this file's tests, `BattleScene`
## and `SingleUnitOverlay` all reach for them by these names.

## **Ordered, and the order is load-bearing.** `unit_input` first, because it publishes the
## `TacticsController` every display module reads at its own mount time; `tooltip` next, because
## three later modules ask for its shared `TooltipView`; `stat_panels` before `resolution` (the
## banner is the readout cluster's); `debug_panel` before `top_left_controls` (the Inject button
## routes into it). Nothing here is alphabetical.
const MODULES: Array[StringName] = [
	&"unit_input",
	&"tooltip",
	&"stat_panels",
	&"resolution",
	&"inspect",
	&"queue_panel",
	&"action_bar",
	&"turn_controls",
	&"controls_legend",
	&"combat_log",
	&"debug_panel",
	&"replay",
	&"top_left_controls",
]

var battle: BattleScene

var tactics: TacticsController
var aim_view: AimView
var resolution_player: ResolutionPlayer
var stat_panel: StatPanel
var weapon_panel: WeaponPanel
var tooltip_view: TooltipView
var tooltip_controller: TooltipController
var queue_panel: QueuePanel
var action_bar: ActionBar
var ap_mp_pip_row: ApMpPipRow
var controls_overlay: ControlsOverlay
var keybindings_button: Button
var inspect_panel: InspectPanel
var inspect_button: Button
var inject_button: Button
var action_column: VBoxContainer
var turn_controls_column: VBoxContainer
var end_turn_button: Button
var reset_turn_button: Button
var top_left_controls: TopLeftControls
var new_battle_button: Button
var watch_button: Button
var log_sink: HierarchicalUiSink
var debug_panel: DebugControlPanel = null
var perf_panel: PerfPanel = null
var suite_run_panel: SuiteRunPanel = null
var watched_run_panel: WatchedRunPanel = null


## `battle.combat_state` may still be null here — `BattleScene._ready()` installs this overlay
## BEFORE its own first `new_battle()` call, exactly so the session-start log line has a live sink
## to land in the instant it is emitted. **Nothing built here may depend on a battle existing yet**,
## which is the same requirement that makes every `ModuleContext` field nullable.
func setup(p_battle: BattleScene) -> void:
	battle = p_battle
	var context: ModuleContext = build_root(battle)
	_build_chrome(context)
	mount_modules(MODULES, _configure)
	(module(&"tooltip") as TooltipModule).raise()
	_alias_modules()
	_wire_modules()
	battle.battle_loaded.connect(_on_battle_loaded)
	if battle.combat_state != null:
		await _on_battle_loaded()


func teardown() -> void:
	if battle != null and battle.battle_loaded.is_connected(_on_battle_loaded):
		battle.battle_loaded.disconnect(_on_battle_loaded)
	unmount_modules()


## The unit-input module, or null in a mode that declares none. Named because several callers want
## it and `module(&"unit_input") as UnitInputModule` at each site is noise.
func unit_input() -> UnitInputModule:
	return module(&"unit_input") as UnitInputModule


func attach_log_sink(log: CombatLog) -> void:
	var logs: CombatLogModule = module(&"combat_log") as CombatLogModule
	if logs != null and battle != null:
		logs.attach_to(log, battle.combat_state)


func ui_log_sink() -> UiLogSink:
	return log_sink


## docs/10 taskblock02 F1 (tb31 Pass B): true only for an explicitly HUMAN squad —
## `controller_for` has no silent HUMAN default to fall back on, and a bout cannot be running with
## an `UNASSIGNED` squad on the board at all (`BoutRunner._init()`'s own hard error). Every real
## entry point assigns explicitly, so this reads exactly what was assigned, nothing implied.
func wants_turn_for(unit: Unit) -> bool:
	return battle.combat_state.controller_for(unit.squad_id) == Enums.SquadController.HUMAN


## Re-wires against whichever `CombatState`/`MissionState` is now current — fired once from
## `setup()` and again every time `battle.load_battle()` reruns under an already-active overlay (the
## New Battle button, which never swaps overlays, only rebuilds the world).
func _on_battle_loaded() -> void:
	rebind_modules()
	# The PREVIOUS combat_state has already been replaced by the time this fires; its now-orphaned
	# log simply stops being written to, with nothing left to detach from.
	attach_log_sink(battle.combat_state.combat_log)
	# Awaited for the same reason as the `turn_resolved` call site below.
	await advance_ai_turns(battle)


## Four independently anchored regions, not one long sidebar: a left column (weapons list, Inspect,
## the combat log at its bottom), a top-right column (keybindings), and a bottom-right stack (the
## readout panel above the action bar / turn controls row).
func _build_chrome(context: ModuleContext) -> void:
	var left_half := Control.new()
	left_half.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_half.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(left_half)
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

	# Still spans the right half — the legend and the bottom-right stack anchor to two different
	# corners within it — but must not itself swallow camera drags over that half of the board.
	var right_half := Control.new()
	right_half.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_half.anchor_left = 0.5
	right_half.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(right_half)

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


## The handful of pre-mount fields this mode sets. The replay panels are **spectator-only while the
## bug hunt runs** (`SuiteRunPanel.SHOW_IN_PLAYER_VIEW`) — they crowd the surfaces the hunt
## reproduces against, and a run is watched from the spectator view regardless. The Inject panel is
## deliberately untouched by that: it is a hunting tool, not a test surface.
func _configure(mounted: ViewModule) -> void:
	if mounted is InspectModule:
		(mounted as InspectModule).with_button = true
	elif mounted is TopLeftControlsModule:
		(mounted as TopLeftControlsModule).include_new_battle = true
		(mounted as TopLeftControlsModule).watch_label = "Watch"
	elif mounted is ReplayModule:
		(mounted as ReplayModule).enabled = SuiteRunPanel.SHOW_IN_PLAYER_VIEW


func _alias_modules() -> void:
	var input: UnitInputModule = module(&"unit_input") as UnitInputModule
	tactics = input.tactics
	var stats: StatPanelsModule = module(&"stat_panels") as StatPanelsModule
	aim_view = stats.aim_view
	stat_panel = stats.stat_panel
	weapon_panel = stats.weapon_panel
	var tips: TooltipModule = module(&"tooltip") as TooltipModule
	tooltip_view = tips.view
	tooltip_controller = tips.controller
	resolution_player = (module(&"resolution") as ResolutionModule).player
	queue_panel = (module(&"queue_panel") as QueuePanelModule).panel
	var bar: ActionBarModule = module(&"action_bar") as ActionBarModule
	action_bar = bar.action_bar
	ap_mp_pip_row = bar.ap_mp_pip_row
	action_column = bar.action_column
	var turns: TurnControlsModule = module(&"turn_controls") as TurnControlsModule
	turn_controls_column = turns.column
	end_turn_button = turns.end_turn_button
	reset_turn_button = turns.reset_turn_button
	var legend: ControlsLegendModule = module(&"controls_legend") as ControlsLegendModule
	controls_overlay = legend.controls_overlay
	keybindings_button = legend.keybindings_button
	var inspect: InspectModule = module(&"inspect") as InspectModule
	inspect_panel = inspect.panel
	inspect_button = inspect.button
	var logs: CombatLogModule = module(&"combat_log") as CombatLogModule
	log_sink = logs.sink
	var debug: DebugPanelModule = module(&"debug_panel") as DebugPanelModule
	debug_panel = debug.panel
	perf_panel = debug.perf_panel
	var replay: ReplayModule = module(&"replay") as ReplayModule
	suite_run_panel = replay.suite_run_panel
	watched_run_panel = replay.watched_run_panel
	var cluster: TopLeftControlsModule = module(&"top_left_controls") as TopLeftControlsModule
	top_left_controls = cluster.controls
	new_battle_button = cluster.new_battle_button()
	watch_button = cluster.watch_button()
	inject_button = cluster.inject_button()


func _wire_modules() -> void:
	var input: UnitInputModule = module(&"unit_input") as UnitInputModule
	input.turn_resolved.connect(_on_turn_ended)
	input.selection_changed.connect(_on_selection_changed)
	var debug: DebugPanelModule = module(&"debug_panel") as DebugPanelModule
	debug.input_owner = tactics
	debug.on_applied = _on_debug_verb_applied
	var replay: ReplayModule = module(&"replay") as ReplayModule
	replay.notice.connect(set_thinking_label)


## Once the human's own turn has fully resolved AND animated, any squad flagged AI auto-advances
## through the shared `advance_ai_turns`. Fired by `UnitInputModule.turn_resolved`, which is what
## now owns the view resync and the playback that precede it.
##
## **Kept under its original name** because `SingleUnitOverlay` overrides it to auto-select after
## the turn, and that override calls `super` — a rename here would have silently dropped that step.
##
## **Awaited, and both awaits matter.** `advance_ai_turns` fast-forwards every AI turn with no
## animation at all, so calling it before this turn's own playback had started made the AI squad
## visibly snap to its new positions while the human's tracer had not fired yet. And it is itself a
## coroutine: fire-and-forget returned the instant the planner first suspended, so the batch ran
## after whatever came next had already read the turn state.
func _on_turn_ended(_events: Array[LogEvent]) -> void:
	await advance_ai_turns(battle)


func _on_selection_changed() -> void:
	var inspect: InspectModule = module(&"inspect") as InspectModule
	if inspect != null:
		inspect.refresh_button()
	var stats: StatPanelsModule = module(&"stat_panels") as StatPanelsModule
	if stats != null:
		stats.refresh_header()


func _on_debug_verb_applied() -> void:
	var stats: StatPanelsModule = module(&"stat_panels") as StatPanelsModule
	if stats != null:
		stats.refresh_header()


## Toggles the full debug control panel. A silent no-op outside a debug build, where the panel was
## never constructed at all.
func _on_inject_pressed() -> void:
	var debug: DebugPanelModule = module(&"debug_panel") as DebugPanelModule
	if debug != null:
		debug.toggle()


func _on_inspect_pressed() -> void:
	var inspect: InspectModule = module(&"inspect") as InspectModule
	if inspect != null:
		inspect.open_selected()


func _on_keybindings_pressed() -> void:
	var legend: ControlsLegendModule = module(&"controls_legend") as ControlsLegendModule
	if legend != null:
		legend.toggle()


func _on_end_turn_pressed() -> void:
	tactics.end_turn()


func _on_reset_turn_pressed() -> void:
	tactics.reset_turn()


func _on_repair_menu_id_pressed(id: int, damaged: Array[Part], welder: Part) -> void:
	var input: UnitInputModule = unit_input()
	if input != null:
		input.pick_repair(id, damaged, welder)


func _on_repair_pressed() -> void:
	var input: UnitInputModule = unit_input()
	if input != null:
		input.open_repair_picker()
