class_name ControlOverlay
extends Node3D

## taskblock-15 Pass A: base for the four swappable control overlays
## (`SquadControlOverlay`, `SingleUnitOverlay`, `SpectatorOverlay`,
## `GenerateBoutOverlay`). `BattleScene` builds the world — `CameraRig`,
## `BoardView`, one `HitVolumeView` per unit, the combat-log sinks — exactly
## once; an overlay only ever decides HOW input maps to units and WHICH
## units a human drives. It never rebuilds the world, and it's the only
## thing that changes when the same battle is watched instead of played.
##
## The shared turn driver (`BoutRunner`, generalized this pass) never
## branches on which overlay is active: it only ever asks
## `wants_turn_for(unit)`. `wants_turn_for` true for the CURRENT unit means
## this overlay's own UI drives that turn (already wired in `setup()`, the
## same way `TacticsController`'s End Turn button already resolves a turn
## today); false means `AiPlanner.plan_turn` drives it instead
## (taskblock-14).
##
## ## taskblock-56 Pass C: this is a module host now
##
## The surface an overlay used to build by hand is a set of `ViewModule`s
## (`src/view/modules/`), and this base owns the machinery every host needs:
## the themed `CanvasLayer`/`Control` root, the `ModuleContext`, mounting in
## declaration order, re-pointing everything on a battle load, the per-frame
## tick, and unmounting on teardown. A subclass supplies **which** modules and
## **what chrome** to hang them in — never how any of them work.

## The themed root every module's `Control`s live under. One `CanvasLayer` and
## one `HulkTheme.build()` per host, never one per module — two overlays each
## building their own is how the same theme came to be applied twice with
## subtly different anchor presets.
var ui_root: Control = null
## The mounted modules, in declaration order. Order matters: a module that
## reads another (`ActionBarModule` wants the shared `TooltipView`) must be
## declared after it.
var modules: Array[ViewModule] = []
## What every mounted module was handed. Public so a test can read back which
## modules a mode actually produced, which is Pass D's own acceptance.
var module_context: ModuleContext = null


## Wires this overlay's own UI onto the already-built world. Called once,
## right after `BattleScene.set_overlay()` swaps this overlay in.
func setup(_battle: BattleScene) -> void:
	pass


## Builds the themed root and an empty context against `battle`. A subclass
## calls this first, then adds whatever chrome it wants as slots, then mounts.
func build_root(battle: BattleScene) -> ModuleContext:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.theme = HulkTheme.build()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Load-bearing: a bare `Control` defaults to `MOUSE_FILTER_STOP`, and this
	# one spans the screen — it would swallow every RMB/MMB drag that started
	# over it before `CameraRig._unhandled_input` ever saw the event.
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	module_context = ModuleContext.new()
	module_context.battle = battle
	module_context.ui_root = ui_root
	module_context.host = self
	return module_context


## Mounts `ids` in order, through `ModuleCatalog`. `configure`, if given, is
## called with each freshly built module BEFORE it mounts — that is where a
## mode sets the handful of pre-mount fields modules expose (`with_button`,
## `include_new_battle`, `announce_passes`), which is the whole reason those
## are fields rather than constructor arguments.
##
## **An unknown id is skipped, not fatal.** A mode listing something the
## catalog does not know gets a mode without it, the same "no further action,
## no silent rollback" posture `ActionCatalog.build_firing_action` has.
func mount_modules(ids: Array[StringName], configure: Callable = Callable()) -> void:
	for id: StringName in ids:
		var module: ViewModule = ModuleCatalog.build(id)
		if module == null:
			continue
		add_child(module)
		if configure.is_valid():
			configure.call(module)
		module.mount(module_context)
		modules.append(module)


## The mounted module for `id`, or null.
func module(id: StringName) -> ViewModule:
	return module_context.module(id) if module_context != null else null


## True if any mounted module accepts unit input. **This is the assertion
## Spectator's contract rests on** — a mode with no input modules has no
## `TacticsController` and therefore no path from a click to
## `ActionQueue.enqueue`.
func has_unit_input() -> bool:
	for mounted: ViewModule in modules:
		if mounted.is_input():
			return true
	return false


## Re-points every module at whatever `battle` now holds.
func rebind_modules() -> void:
	for mounted: ViewModule in modules:
		mounted.rebind()


func unmount_modules() -> void:
	for mounted: ViewModule in modules:
		mounted.unmount()
	modules.clear()


## True if a HUMAN drives `unit`'s turn under this overlay — the one
## question the shared turn driver (`BoutRunner`) ever asks. False means
## `AiPlanner.plan_turn` drives it instead. The base default (false, always
## AI) is exactly `SpectatorOverlay`'s and `GenerateBoutOverlay`'s own
## answer — neither overrides this.
func wants_turn_for(_unit: Unit) -> bool:
	return false


## Whatever this overlay's own UI has ALREADY assembled for `unit` — a
## trailing `EndTurnAction` included — never blocks waiting for more
## input: by the time anything calls this, a human has already pressed
## whatever control (End Turn, today) triggered it. Exists for contract
## completeness and headless verification ("what would this overlay
## submit") — the two interactive overlays' own real submission path
## stays their existing, already-proven UI flow
## (`TacticsController.end_turn()`), not a second copy of it routed
## through here. Only ever meaningful when `wants_turn_for(unit)` was
## true for it; the base default (null) matches every overlay that never
## drives a human turn at all.
func build_queue(_unit: Unit, _state: CombatState, _mission: MissionState) -> ActionQueue:
	return null


## Cleans up this overlay's own UI/connections before `BattleScene` swaps
## to a different one (A2: generate-bout -> spectator) or frees it.
## taskblock-44 Pass D3: shows (or clears, on "") which unit is currently
## planning. **Named, never a bare "Thinking…"** — once named enemies exist, the
## difference between a mook's turn and a boss's turn reads as *character* rather
## than as lag, because the intelligence tiers make a smarter unit genuinely
## think longer. What the label SAYS is `PlanPacer.thinking_label`'s decision, in
## logic, so it is answerable in a headless test; this is the render half only.
##
## A no-op on the base overlay: not every control surface has somewhere sensible
## to put it, and an overlay that does overrides this. `advance_ai_turns` above
## calls it unconditionally regardless, so adding the display to a new overlay is
## one override and nothing else.
func set_thinking_label(_text: String) -> void:
	pass


func teardown() -> void:
	pass


## taskblock-41 Pass D: re-points this overlay's own log sink at `log`, the
## stream of whichever battle is being loaded. Called by
## `BattleScene.load_battle()` BEFORE anything is built or emitted, because
## the session header (docs/09: "carries the seed as the file's FIRST line")
## and the bout-build log both fire during the load — a sink that only
## attaches on `battle_loaded`, at the END of the load, misses all of it.
##
## Must be idempotent: `_on_battle_loaded` calls it again for the overlays
## that re-wire themselves on a "New Battle" press under an already-active
## overlay.
func attach_log_sink(_log: CombatLog) -> void:
	pass


## taskblock-41 Pass A: whichever `RichTextLabel`-backed combat-log sink
## this overlay owns, or null. A `UiLogSink` only marks itself dirty on
## `emit()` now — a `RefCounted` has no frame of its own — so something
## with a real frame has to draw it, and the overlay that built the label
## is the one thing that always outlives it. Overlays with no log panel
## (`SingleUnitOverlay`, `GenerateBoutOverlay`) keep the null default and
## never pay for the tick at all.
func ui_log_sink() -> UiLogSink:
	return null


## The one per-frame render tick. At most one `label.text` reassignment per
## frame regardless of how many events landed in it — which is the whole
## point: render cost stops scaling with event count, so taskblock-41 Pass D's
## deliberate verbosity is affordable rather than a regression (BR27.09 cost
## #1).
##
## taskblock-56 Pass C: the tick is driven from here rather than from each
## module's own `_process`, so "exactly one draw per frame" stays visible in
## one place instead of being a property of however many modules happen to be
## mounted.
func _process(delta: float) -> void:
	var sink: UiLogSink = ui_log_sink()
	if sink != null:
		sink.render_if_dirty()
	for mounted: ViewModule in modules:
		mounted.tick(delta)


## The ONE shared "auto-advance AI turns" loop every interactive overlay
## (`SquadControlOverlay`, `SingleUnitOverlay`) drives after its own human
## turn resolves — auto-resolves consecutive units this overlay does NOT
## want (`AiPlanner.plan_turn`, taskblock-14) starting at the current unit,
## stopping the instant either the mission reaches a real outcome or a
## unit this overlay DOES want control of comes up. `SpectatorOverlay`
## never calls this — it drives its own `BoutRunner` directly, at its own
## paced cadence, since `wants_turn_for` is unconditionally false there
## anyway. This is the literal, single turn-driver the taskblock asks for:
## every overlay that needs AI auto-advancement shares this one method,
## never a per-overlay reimplementation of it.
## taskblock-42 Pass D (BR27.09 cost #4): this was a bare `while` loop with no
## `await` anywhere in it. Each `step()` runs a full `AiPlanner.plan_turn` —
## pathfinding, LOS, cover scoring — so the main thread was blocked for the
## entire batch: nothing rendered, no input was processed, the window was
## unresponsive, and every opposing unit appeared to move at once at the end.
##
## **The coalescing fork, decided before implementing (the pass required it).**
## taskblock-19 Pass I2 deliberately made this refresh ONCE at the end, having
## measured a full-board refresh per batch as waste. Yielding reopens that: yield
## without refreshing and the player watches a frozen board for several seconds,
## merely an interactive one; refresh the whole board per step and I2's finding
## is undone.
##
## Neither. **Refresh only the units THAT step actually touched, after that
## step.** I2's waste was refreshing every unit on the board repeatedly; this is
## proportional to what changed, which is usually one unit — and taskblock-42
## Pass B made each of those ~2.4× cheaper. The accumulated set still gets a
## final pass so the active-turn highlight lands once, on the real end state.
##
## **Determinism is unaffected and that is the load-bearing property, not the
## speed.** `BoutRunner.step()` draws only from `state.rng`, and nothing on the
## frame path draws from it, so yielding cannot reorder the sim. The test asserts
## a seeded bout is identical whether driven through here or through a tight
## `BoutRunner` loop with no yielding at all.
func advance_ai_turns(battle: BattleScene) -> void:
	var runner := BoutRunner.new(
		battle.combat_state, battle.mission, BoutRunner.DEFAULT_TURN_CAP, wants_turn_for
	)
	# tb44 Pass D: the pacer is what makes a unit's turn watchable rather than a
	# freeze. It carries the frame signal the planner suspends on — supplied here
	# because only the view knows what a tree is — and the hard budget that
	# guarantees the turn ends, which is what makes the label below a promise
	# instead of a hope. Headless drivers build no pacer and never suspend.
	if is_inside_tree():
		runner.pacer = PlanPacer.new()
		runner.pacer.frame_signal = get_tree().process_frame
	var touched_ids: Dictionary = {}
	while not runner.finished and not wants_turn_for(battle.combat_state.current_unit()):
		set_thinking_label(PlanPacer.thinking_label(battle.combat_state.current_unit()))
		var run_finished: bool = await runner.step()
		var stepped: Array[int] = LogPlayback.affected_unit_ids(runner.last_events)
		for id: int in stepped:
			touched_ids[id] = true
		# This step's own units only — never the whole board (taskblock-19 I2).
		battle.refresh_unit_views(stepped, false)
		if run_finished:
			break
		# The yield. One frame between units, so input is processed and the
		# board draws while the batch is still running.
		if is_inside_tree():
			await get_tree().process_frame
	set_thinking_label("")
	battle.refresh_unit_views(touched_ids.keys())
