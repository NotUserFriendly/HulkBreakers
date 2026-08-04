class_name ControlOverlay
extends Node3D

## **The one view.** `BattleScene` builds the world — `CameraRig`, `BoardView`, one `HitVolumeView`
## per unit, the combat-log sinks — exactly once; this decides which control surface sits over it.
## Swapping surfaces never rebuilds the world.
##
## ## taskblock-56 Pass D: there are no overlay subclasses left
##
## | was | is |
## |---|---|
## | `SquadControlOverlay`, 942 lines | `ViewModes.player()` |
## | `SpectatorOverlay`, 718 lines | `ViewModes.spectator()` |
## | `SingleUnitOverlay`, 54 lines | `ViewModes.single_unit()` |
## | `GenerateBoutOverlay`, 373 lines | `ViewModes.bout_setup()` |
##
## A **mode** is a declaration (`ViewMode`): which modules, in what layout, with what options, under
## which turn policy. **Adding one is a table entry, not a file** — which is the property
## `test_view_modes.gd` tests by building a mode nothing in `src/` declares and mounting it.
##
## What is left in this class is the four things a *host* owns and a module cannot: building the
## themed root, mounting the declared modules in order, publishing the capabilities modules need
## (`advance_ai_turns`, `rebind_all`), and routing the engine's own input and frame ticks to exactly
## one place each.
##
## ## The turn driver never branches on which mode is active
##
## `BoutRunner` only ever asks `wants_turn_for(unit)`. True for the current unit means this
## surface's own UI drives that turn; false means the AI planner does. That was true when there were
## four subclasses and it is true with one class and a policy field — the difference is that the
## policy is now readable as data rather than as an override.

## The generic capture concept `TacticsController` also has — a "borrow the next real click"
## mechanism a debug panel's board-picking mode can use, emitting the normalized `{"kind", "unit",
## "cell"}` shape either source produces. Forwarded from `BoardInspectModule` so a listener can wire
## against the overlay exactly as it always has.
signal board_clicked(hit: Dictionary)

## Which modules are on, in what layout, under which turn policy. Set before
## `BattleScene.set_overlay` installs this — the same "configure, then hand off" convention every
## overlay already followed for its own fields, and for the same reason: `setup()` may drive several
## units' worth of turns before a caller gets another chance to touch anything.
var mode: ViewMode = null
## The one unit a `SINGLE_UNIT` mode drives. **Unset never means "drive everything"** — see
## `ViewMode.TurnPolicy`.
var controlled_unit: Unit = null

var battle: BattleScene = null
## The themed root every module's `Control`s live under. One `CanvasLayer` and one
## `HulkTheme.build()` per surface, never one per module.
var ui_root: Control = null
## The mounted modules, in declaration order.
var modules: Array[ViewModule] = []
## What every mounted module was handed. Public so a test can read back which modules a mode
## actually produced, which is Pass D's own acceptance.
var module_context: ModuleContext = null


static func for_mode(p_mode: ViewMode) -> ControlOverlay:
	var overlay := ControlOverlay.new()
	overlay.mode = p_mode
	return overlay


## Wires this surface onto the already-built world. Called once, right after
## `BattleScene.set_overlay()` swaps it in.
##
## **`battle.combat_state` may still be null here.** `BattleScene._ready()` installs a surface
## BEFORE its own first `new_battle()` call, exactly so the session-start log line has a live sink
## to land in the instant it is emitted. Nothing built here may depend on a battle existing yet,
## which is the same requirement that makes every `ModuleContext` field nullable.
func setup(p_battle: BattleScene) -> void:
	battle = p_battle
	# **An empty surface, not the player one.** A modeless overlay is a deliberate placeholder — see
	# `ViewModes.empty()` for why defaulting to `player()` here is actively wrong.
	if mode == null:
		mode = ViewModes.empty()
	_build_root()
	ModeChrome.build(mode.chrome, ui_root, module_context)
	_mount_declared_modules()
	# **After every module has mounted**, so the connections a module wants do not constrain the
	# declaration order the way its mount-time reads do.
	for mounted: ViewModule in modules:
		mounted.link()
	var tips: TooltipModule = module(&"tooltip") as TooltipModule
	if tips != null:
		tips.raise()
	_wire_host_signals()
	battle.battle_loaded.connect(_on_battle_loaded)
	if battle.combat_state != null:
		await _on_battle_loaded()


func teardown() -> void:
	if battle != null and battle.battle_loaded.is_connected(_on_battle_loaded):
		battle.battle_loaded.disconnect(_on_battle_loaded)
	var pacing: PlaybackModule = module(&"playback") as PlaybackModule
	if pacing != null:
		pacing.pause()
	for mounted: ViewModule in modules:
		mounted.unmount()
	modules.clear()


## The mounted module for `id`, or null.
func module(id: StringName) -> ViewModule:
	return module_context.module(id) if module_context != null else null


## Typed accessors for the modules that have callers outside their own file.
##
## **These are the surface's public API, not shims.** Before Pass D each overlay held a field per
## panel (`tactics`, `inspect_panel`, `log_sink`, twenty more) and everything reached through those.
## Naming the *module* instead is what makes "which panels exist" a property of the mode rather than
## of the class — a caller that wants the queue panel in a mode that has none gets null and can say
## so, where a field would have been silently null with no way to tell "absent" from "not built
## yet".
func unit_input() -> UnitInputModule:
	return module(&"unit_input") as UnitInputModule


func playback() -> PlaybackModule:
	return module(&"playback") as PlaybackModule


func board_inspect() -> BoardInspectModule:
	return module(&"board_inspect") as BoardInspectModule


func inspect() -> InspectModule:
	return module(&"inspect") as InspectModule


func stat_panels() -> StatPanelsModule:
	return module(&"stat_panels") as StatPanelsModule


func debug_panel_module() -> DebugPanelModule:
	return module(&"debug_panel") as DebugPanelModule


func replay() -> ReplayModule:
	return module(&"replay") as ReplayModule


func bout_setup() -> BoutSetupModule:
	return module(&"bout_setup") as BoutSetupModule


## The `TacticsController` this surface's input module published, or null in a display-only mode.
## Named because it is by far the most-reached-for thing on the surface and
## `unit_input().tactics` at every call site is noise.
func tactics() -> TacticsController:
	var input: UnitInputModule = unit_input()
	return input.tactics if input != null else null


## True if any mounted module accepts unit input. **This is the assertion the spectator's contract
## rests on** — a mode with no input modules has no `TacticsController`, and therefore no path from
## a click to `ActionQueue.enqueue`.
func has_unit_input() -> bool:
	for mounted: ViewModule in modules:
		if mounted.is_input():
			return true
	return false


## True if a HUMAN drives `unit`'s turn under this mode — the one question `BoutRunner` ever asks.
##
## `HUMAN_SQUADS` reads `controller_for` exactly as it always has: there is no silent HUMAN default
## to fall back on, and a bout cannot run with an `UNASSIGNED` squad on the board at all
## (`BoutRunner._init()`'s own hard error), so this reads what was assigned and nothing implied.
func wants_turn_for(unit: Unit) -> bool:
	match mode.turn_policy if mode != null else ViewMode.TurnPolicy.NONE:
		ViewMode.TurnPolicy.HUMAN_SQUADS:
			return battle.combat_state.controller_for(unit.squad_id) == Enums.SquadController.HUMAN
		ViewMode.TurnPolicy.SINGLE_UNIT:
			return true if controlled_unit == null else unit == controlled_unit
	return false


## Whatever this surface's UI has ALREADY assembled for `unit`. Never blocks waiting for more input:
## by the time anything calls this, a human has already pressed whatever control triggered it.
## Exists for contract completeness and headless verification; the real submission path stays the
## proven UI flow (`TacticsController.end_turn()`), not a second copy routed through here.
func build_queue(_unit: Unit, _state: CombatState, _mission: MissionState) -> ActionQueue:
	return null


## Shows (or clears, on "") which unit is currently planning. **Named, never a bare "Thinking…"** —
## once named enemies exist, the difference between a mook's turn and a boss's reads as *character*
## rather than as lag, because the intelligence tiers make a smarter unit genuinely think longer.
## What the label SAYS is `PlanPacer.thinking_label`'s decision, in logic, so it is answerable in a
## headless test; this is the render half only.
##
## A no-op in a mode with no status line, which is every mode but the spectator's.
func set_thinking_label(text: String) -> void:
	var pacing: PlaybackModule = module(&"playback") as PlaybackModule
	if pacing != null:
		pacing.set_thinking_label(text)


## Re-points this surface's log sink at `log`. Called by `BattleScene.load_battle()` BEFORE anything
## is built or emitted, because the session header (docs/09: "carries the seed as the file's FIRST
## line") and the bout-build log both fire during the load — a sink that only attaches at the end of
## it misses all of it. Must be idempotent; `remove_sink` is a documented no-op on a sink that was
## never added.
func attach_log_sink(log: CombatLog) -> void:
	var logs: CombatLogModule = module(&"combat_log") as CombatLogModule
	if logs != null and battle != null:
		logs.attach_to(log, battle.combat_state)


## Whichever `RichTextLabel`-backed combat-log sink this surface owns, or null. A `UiLogSink` only
## marks itself dirty on `emit()` — a `RefCounted` has no frame of its own — so something with a
## real frame has to draw it.
func ui_log_sink() -> UiLogSink:
	var logs: CombatLogModule = module(&"combat_log") as CombatLogModule
	return logs.sink if logs != null else null


## Points every module at whatever `battle` currently holds, without rebuilding anything.
##
## **Rebind, emphatically not a rebuild.** Calling `setup` on a replay constructs a fresh root and
## fresh panels — including the replay panel that is *in the middle of iterating* — which destroyed
## the run it was advancing and left the second seed unloaded. A new board needs a new runner and a
## re-pointed log; the UI is already correct.
func rebind_to_battle() -> void:
	for mounted: ViewModule in modules:
		mounted.rebind()


## The one per-frame render tick. At most one `label.text` reassignment per frame regardless of how
## many events landed — render cost stops scaling with event count, which is what makes the log's
## deliberate verbosity affordable rather than a regression (`BR27.09` cost #1).
##
## Driven from here rather than from each module's own `_process`, so "exactly one draw per frame"
## stays visible in one place instead of being a property of however many modules are mounted.
func _process(delta: float) -> void:
	for mounted: ViewModule in modules:
		mounted.tick(delta)


## The one engine input entry point, routed into whichever module owns board picking.
##
## **Deliberately the only `_unhandled_input` in the module system.** A module defining one would
## receive events wherever its host happened to parent it, and a host that also forwarded would
## dispatch the same click twice. `CameraRig`'s independent handler (orbit/pan/zoom) is untouched.
func _unhandled_input(event: InputEvent) -> void:
	var picking: BoardInspectModule = module(&"board_inspect") as BoardInspectModule
	if picking != null:
		picking.handle_input(event)


## The ONE shared "auto-advance AI turns" loop. Auto-resolves consecutive units this surface does
## NOT want, starting at the current unit, stopping the instant either the mission reaches a real
## outcome or a unit this surface DOES want comes up. A spectator mode never reaches this — it
## drives its own `BoutRunner` at its own paced cadence, and `wants_turn_for` is unconditionally
## false there anyway.
##
## **It yields, and the reason is `BR27.09`.** This was a bare `while` loop with no `await` anywhere
## in it. Each `step()` runs a full plan — pathfinding, LOS, cover scoring — so the main thread was
## blocked for the whole batch: nothing rendered, no input was processed, and every opposing unit
## appeared to move at once at the end.
##
## **The coalescing fork, decided rather than stumbled into.** taskblock-19 I2 deliberately made
## this refresh ONCE at the end, having measured a full-board refresh per batch as waste. Yielding
## reopens that: yield without refreshing and the player watches a frozen board; refresh the whole
## board per step and I2's finding is undone. Neither — **refresh only the units THAT step actually
## touched**, which is proportional to what changed and is usually one unit. The accumulated set
## still gets a final pass so the active-turn highlight lands once, on the real end state.
##
## **Determinism is unaffected, and that is the load-bearing property rather than the speed.**
## `BoutRunner.step()` draws only from `state.rng` and nothing on the frame path draws from it, so
## yielding cannot reorder the sim. The test asserts a seeded bout is identical whether driven
## through here or through a tight loop with no yielding at all.
func advance_ai_turns(p_battle: BattleScene) -> void:
	var runner := BoutRunner.new(
		p_battle.combat_state, p_battle.mission, BoutRunner.DEFAULT_TURN_CAP, wants_turn_for
	)
	# tb44 Pass D: the pacer is what makes a unit's turn watchable rather than a freeze. It carries
	# the frame signal the planner suspends on — supplied here because only the view knows what a
	# tree is — and the hard budget that guarantees the turn ends, which is what makes the label a
	# promise instead of a hope. Headless drivers build no pacer and never suspend.
	if is_inside_tree():
		runner.pacer = PlanPacer.new()
		runner.pacer.frame_signal = get_tree().process_frame
	var touched_ids: Dictionary = {}
	while not runner.finished and not wants_turn_for(p_battle.combat_state.current_unit()):
		set_thinking_label(PlanPacer.thinking_label(p_battle.combat_state.current_unit()))
		var run_finished: bool = await runner.step()
		var stepped: Array[int] = LogPlayback.affected_unit_ids(runner.last_events)
		for id: int in stepped:
			touched_ids[id] = true
		p_battle.refresh_unit_views(stepped, false)
		# **Selected the moment it becomes true, not after the batch drains.** A `SINGLE_UNIT` mode
		# promises "no selection step", and the unit becomes current partway through this loop —
		# waiting for the loop to finish means waiting for its trailing frame yield, by which time a
		# caller that did not await `setup()` has already looked and found nothing selected. That is
		# how the old fire-and-forget version happened to be right: it auto-selected at the first
		# suspension. Doing it here is the same timing without depending on where a suspension lands.
		_auto_select_controlled_unit()
		if run_finished:
			break
		# The yield. One frame between units, so input is processed and the board draws while the
		# batch is still running.
		if is_inside_tree():
			await get_tree().process_frame
	set_thinking_label("")
	_auto_select_controlled_unit()
	p_battle.refresh_unit_views(touched_ids.keys())


func _build_root() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.theme = HulkTheme.build()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Load-bearing: a bare `Control` defaults to `MOUSE_FILTER_STOP`, and this one spans the screen —
	# it would swallow every RMB/MMB drag that started over it before `CameraRig._unhandled_input`
	# ever saw the event.
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	module_context = ModuleContext.new()
	module_context.battle = battle
	module_context.ui_root = ui_root
	module_context.host = self
	# Published capabilities, not a back-door to the parent. A module gets exactly the one thing it
	# needs — see `ModuleContext.advance_ai_turns`.
	module_context.advance_ai_turns = _advance_ai_turns_here
	module_context.rebind_all = rebind_to_battle


## An unknown module id is skipped, not fatal: a mode listing something the catalog does not know
## gets a mode without it, the same "no further action, no silent rollback" posture
## `ActionCatalog.build_firing_action` has.
func _mount_declared_modules() -> void:
	for id: StringName in mode.modules:
		var mounted: ViewModule = ModuleCatalog.build(id)
		if mounted == null:
			continue
		add_child(mounted)
		mounted.configure(mode.options_for(id))
		mounted.mount(module_context)
		modules.append(mounted)


func _wire_host_signals() -> void:
	var picking: BoardInspectModule = module(&"board_inspect") as BoardInspectModule
	if picking != null:
		picking.board_clicked.connect(_forward_board_click)
	var setup_menu: BoutSetupModule = module(&"bout_setup") as BoutSetupModule
	if setup_menu != null:
		setup_menu.bout_started.connect(_on_bout_started)
	var replay: ReplayModule = module(&"replay") as ReplayModule
	if replay != null:
		replay.notice.connect(set_thinking_label)


func _forward_board_click(hit: Dictionary) -> void:
	board_clicked.emit(hit)


## Start Bout has built and loaded the matchup; the mode swap is the host's business.
##
## `BoutSetup.build_bout` always starts both squads AI, so `toggle_blue_control()` is what flips
## squad 0 to HUMAN and swaps to the player mode — never the spectator mode at all in that branch.
func _on_bout_started(assume_control: bool) -> void:
	if assume_control:
		battle.toggle_blue_control()
	else:
		battle.set_overlay(ControlOverlay.for_mode(ViewModes.spectator()))


## Re-wires against whichever `CombatState`/`MissionState` is now current — fired once from
## `setup()` and again every time `battle.load_battle()` reruns under an already-active surface (the
## New Battle button, which never swaps surfaces, only rebuilds the world).
func _on_battle_loaded() -> void:
	rebind_to_battle()
	# The PREVIOUS combat_state has already been replaced by the time this fires; its now-orphaned
	# log simply stops being written to, with nothing left to detach from.
	attach_log_sink(battle.combat_state.combat_log)
	# **Awaited**, and the reason is that `advance_ai_turns` is a coroutine: fire-and-forget returned
	# the instant the planner first suspended, so the batch ran after whatever came next had already
	# read the turn state.
	#
	# **The auto-select comes after, not before.** A `SINGLE_UNIT` mode's controlled unit is usually
	# not the one whose turn it is at load; the batch has to resolve every unit ahead of it first,
	# and only then is there anything to select. Selecting first and advancing second lands on
	# whoever happened to be current at load, which is the "no click should be needed" promise
	# quietly broken.
	if has_unit_input():
		await advance_ai_turns(battle)
	_auto_select_controlled_unit()


## A `SINGLE_UNIT` mode selects its own unit the instant that unit becomes the current one, so a
## player never has to click their own body first.
func _auto_select_controlled_unit() -> void:
	if controlled_unit == null or battle.combat_state == null:
		return
	var input: UnitInputModule = module(&"unit_input") as UnitInputModule
	if input == null or input.tactics == null or input.tactics.selection == null:
		return
	if battle.combat_state.current_unit() == controlled_unit:
		input.tactics.selection.select(controlled_unit)


## The capability handed to modules. Bound to this surface's own `battle`, so a module never has to
## hold one.
func _advance_ai_turns_here() -> void:
	if battle != null:
		await advance_ai_turns(battle)
	_auto_select_controlled_unit()
