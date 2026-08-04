class_name SpectatorOverlay
extends ControlOverlay

## "Nothing; no unit input; camera-follow + pacing only. A bout is this."
##
## `wants_turn_for` is never overridden: the base class's own default (always false) is exactly
## right — no unit is ever human-driven here, which is also why the `BoutRunner` inside
## `PlaybackModule` needs no injected predicate. That is what makes "a spectated battle is identical
## in outcome to a headless bout for the same seed" true BY CONSTRUCTION.
##
## ## taskblock-56 Pass C: 718 lines became a module list
##
## **This overlay is now a declaration.** Everything it used to own — the pacing loop, the combat
## log window, the debug and perf panels, the replay panels, the inspect modal, the board click and
## hover handling, the timing tunables — is a `ViewModule` in `src/view/modules/`, and every one of
## them is shared with the player view rather than written twice.
##
## **`MODULES` contains no input module, and that is the whole contract**, checked by
## `has_unit_input()` rather than asserted in prose. Before this pass the same fact was expressed by
## *not inheriting* `SquadControlOverlay` — which cost a 718-line copy of everything Squad had that
## a spectator also wanted. The two axes replace the fork: display modules are taken, the input ones
## are simply not listed.
##
## Fields below are aliases into the mounted modules, kept because this file and its tests already
## reach for them by name.

## The same generic capture concept `TacticsController` has — a "borrow the next real click"
## mechanism a debug panel's board-picking mode can use, emitting the normalized
## `{"kind", "unit", "cell"}` shape either source produces. Forwarded from `BoardInspectModule` so a
## panel can listen against this overlay exactly as it always has.
signal board_clicked(hit: Dictionary)

## **Ordered, and the order is load-bearing.** `resolution` before `playback` (the tunables write
## into `ResolutionPlayer`'s own fields and the pacing loop awaits its playback); `debug_panel`
## before `top_left_controls` (the Inject button routes into it); `inspect` before `board_inspect`
## (a click opens the panel). Nothing here is alphabetical.
const MODULES: Array[StringName] = [
	&"combat_log",
	&"resolution",
	&"debug_panel",
	&"replay",
	&"inspect",
	&"playback",
	&"board_inspect",
	&"top_left_controls",
]

var battle: BattleScene
## taskblock-30: no longer constructed here — `BattleScene` owns the one instance (rebuilt per
## `load_battle()`, so it survives an overlay swap); this just reads it.
var bout_injector: BoutInjector

var log_panel: CombatLogPanel
var log_label: RichTextLabel
var log_sink: HierarchicalUiSink
var resolution_player: ResolutionPlayer
var inspect_panel: InspectPanel
var debug_panel: DebugControlPanel = null
var perf_panel: PerfPanel = null
var suite_run_panel: SuiteRunPanel = null
var watched_run_panel: WatchedRunPanel = null
var top_left_controls: TopLeftControls

## **Forwarding properties, not copies.** `playing`, `speed` and `runner` live in `PlaybackModule`
## and `input_capture_mode` in `BoardInspectModule`; storing a second copy here is precisely the
## two-sources-of-truth problem the collapse exists to remove, so these read and write straight
## through. Kept on the overlay because every existing caller reaches for them by these names.
var playing: bool:
	get:
		var pacing: PlaybackModule = playback()
		return pacing != null and pacing.playing
	set(value):
		var pacing: PlaybackModule = playback()
		if pacing != null:
			pacing.playing = value

var speed: float:
	get:
		var pacing: PlaybackModule = playback()
		return pacing.speed if pacing != null else 1.0
	set(value):
		var pacing: PlaybackModule = playback()
		if pacing != null:
			pacing.speed = value

var runner: BoutRunner:
	get:
		var pacing: PlaybackModule = playback()
		return pacing.runner if pacing != null else null
	set(value):
		var pacing: PlaybackModule = playback()
		if pacing != null:
			pacing.runner = value

var input_capture_mode: bool:
	get:
		var picking: BoardInspectModule = board_inspect()
		return picking != null and picking.input_capture_mode
	set(value):
		var picking: BoardInspectModule = board_inspect()
		if picking != null:
			picking.input_capture_mode = value

## Aliases into `PlaybackModule`'s own controls, kept under their original names.
var _play_button: Button
var _step_button: Button
var _speed_button: Button
var _status_label: Label
var _slide_ms_field: SpinBox
var _bullet_ms_field: SpinBox
var _tracer_count_field: SpinBox

## Whether the bout was actually auto-playing when a click opened the inspect panel — "closing it
## resumes" must never START auto-play for someone who had already paused by hand.
var _was_playing_before_inspect: bool = false


## `battle.combat_state`/`battle.mission` are already the freshly-built bout by the time this runs —
## `GenerateBoutOverlay` always calls `battle.load_battle()` before swapping here — so unlike the
## player view there is no "not loaded yet" case to guard.
func setup(p_battle: BattleScene) -> void:
	battle = p_battle
	bout_injector = battle.bout_injector
	var context: ModuleContext = build_root(battle)
	_build_chrome(context)
	mount_modules(MODULES, _configure)
	_alias_modules()
	_wire_modules()


func teardown() -> void:
	var pacing: PlaybackModule = playback()
	if pacing != null:
		pacing.pause()
	unmount_modules()


## Reads the pacing module rather than holding a duplicate of its state, so "is this playing" has
## one answer.
func playback() -> PlaybackModule:
	return module(&"playback") as PlaybackModule


func board_inspect() -> BoardInspectModule:
	return module(&"board_inspect") as BoardInspectModule


## The pacing controls, forwarded. Kept as methods on the overlay because tests and the Step button
## alike have always called them here.
func play() -> void:
	playback().play()


func pause() -> void:
	playback().pause()


func step_once() -> void:
	await playback().step_once()


func set_speed(multiplier: float) -> void:
	playback().set_speed(multiplier)


## Toggles the full debug control panel. A silent no-op outside a debug build, where the panel was
## never constructed at all — the same posture the button's own absence already gives it.
func _on_inject_pressed() -> void:
	var debug: DebugPanelModule = module(&"debug_panel") as DebugPanelModule
	if debug != null:
		debug.toggle()


## Cycles 1x -> 2x -> 4x -> 1x.
func _on_speed_button_pressed() -> void:
	playback().cycle_speed()


func _refresh_status() -> void:
	playback().refresh_status()


## One step, animated. Forwarded so the pacing loop's own granularity stays callable from here.
func _advance() -> void:
	await playback().advance()


func set_thinking_label(text: String) -> void:
	var pacing: PlaybackModule = playback()
	if pacing != null:
		pacing.set_thinking_label(text)


## Points this overlay at whatever `battle` currently holds, without rebuilding the UI.
##
## **Rebind, emphatically not `setup()`.** `setup` builds a fresh root and fresh panels — including
## the replay panel that is *in the middle of iterating* — which destroyed the run it was advancing
## and left the second seed unloaded. A new board needs a new runner and a re-pointed log; the UI is
## already correct.
func rebind_to_battle() -> void:
	bout_injector = battle.bout_injector
	rebind_modules()


func attach_log_sink(log: CombatLog) -> void:
	var logs: CombatLogModule = module(&"combat_log") as CombatLogModule
	if logs != null:
		logs.attach_to(log, battle.combat_state)


func ui_log_sink() -> UiLogSink:
	return log_sink


## The one engine input entry point. Routed into `BoardInspectModule` rather than handled here, and
## deliberately the only `_unhandled_input` in the pair — see that module's own note on why it does
## not define one. `CameraRig`'s independent handler (orbit/pan/zoom) is untouched by any of this,
## exactly as it always was.
func _unhandled_input(event: InputEvent) -> void:
	var picking: BoardInspectModule = board_inspect()
	if picking != null:
		picking.handle_input(event)


## Two top-left rows: the pacing controls and the shared cluster on the first, the timing tunables
## on the second. `MOUSE_FILTER_STOP` on both — these are real controls, not a pass-through gap.
func _build_chrome(context: ModuleContext) -> void:
	var controls := HBoxContainer.new()
	controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
	controls.position = Vector2(16, 16)
	controls.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(controls)
	context.set_slot(ModuleSlots.TOP_LEFT, controls)

	var tunables := HBoxContainer.new()
	tunables.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tunables.position = Vector2(16, 48)
	tunables.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(tunables)
	context.set_slot(ModuleSlots.TUNABLES, tunables)


## The handful of pre-mount fields this mode sets. **A spectated bout has no "New Battle" concept of
## its own**, and it announces every run outcome because silence after a run is indistinguishable
## from a broken replay.
func _configure(mounted: ViewModule) -> void:
	if mounted is TopLeftControlsModule:
		(mounted as TopLeftControlsModule).include_new_battle = false
		(mounted as TopLeftControlsModule).watch_label = "Assume Control"
	elif mounted is ReplayModule:
		(mounted as ReplayModule).announce_passes = true


func _alias_modules() -> void:
	var logs: CombatLogModule = module(&"combat_log") as CombatLogModule
	log_panel = logs.panel
	log_label = logs.panel.log_label
	log_sink = logs.sink
	resolution_player = (module(&"resolution") as ResolutionModule).player
	inspect_panel = (module(&"inspect") as InspectModule).panel
	top_left_controls = (module(&"top_left_controls") as TopLeftControlsModule).controls
	var debug: DebugPanelModule = module(&"debug_panel") as DebugPanelModule
	debug_panel = debug.panel
	perf_panel = debug.perf_panel
	var replay: ReplayModule = module(&"replay") as ReplayModule
	suite_run_panel = replay.suite_run_panel
	watched_run_panel = replay.watched_run_panel
	var pacing: PlaybackModule = playback()
	_slide_ms_field = pacing.slide_ms_field
	_bullet_ms_field = pacing.bullet_ms_field
	_tracer_count_field = pacing.tracer_count_field
	_status_label = pacing.status_label
	_play_button = pacing.play_button
	_step_button = pacing.step_button
	_speed_button = pacing.speed_button


func _wire_modules() -> void:
	var picking: BoardInspectModule = board_inspect()
	picking.board_clicked.connect(func(hit: Dictionary) -> void: board_clicked.emit(hit))
	picking.inspect_opened.connect(_on_inspect_opened)
	(module(&"debug_panel") as DebugPanelModule).input_owner = picking
	(module(&"debug_panel") as DebugPanelModule).on_applied = _on_debug_verb_applied
	(module(&"inspect") as InspectModule).closed.connect(_on_inspect_panel_closed)
	var pacing: PlaybackModule = playback()
	pacing.bout_finished.connect(_on_bout_finished)
	var replay: ReplayModule = module(&"replay") as ReplayModule
	replay.replay_loaded.connect(_on_replay_loaded)


func _on_inspect_opened() -> void:
	_was_playing_before_inspect = playback().playing
	pause()


func _on_inspect_panel_closed() -> void:
	if _was_playing_before_inspect:
		play()


func _on_bout_finished(turns_taken: int) -> void:
	var replay: ReplayModule = module(&"replay") as ReplayModule
	if replay != null:
		replay.report_bout_finished(turns_taken)


func _on_debug_verb_applied() -> void:
	playback().refresh_status()


## A replayed fixture has been loaded into the board. **Rebind, then play** — a loaded board with
## nothing driving it is a still image, which is what the supervisor saw: the bout was there and
## nothing moved it.
func _on_replay_loaded(_map_seed: int) -> void:
	rebind_to_battle()
	play()
