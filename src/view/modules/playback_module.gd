class_name PlaybackModule
extends ViewModule

## taskblock-56 Pass C: the spectator's pacing controls — Play / Pause / Step / Speed, the status
## line, the timing tunables, and the `BoutRunner` loop they drive.
##
## **A gated self-chaining loop, not a Timer** — that distinction is this module's whole substance.
## A fixed-interval `Timer` cannot promise "the next cue waits for the current animation to finish":
## a real animated `ResolutionPlayer.play()` can legitimately outlast one tick and the Timer keeps
## ticking underneath, risking an overlapping, reentrant step. `_run_while_playing` steps, awaits
## that step's own full animated playback, waits the inter-turn gap, and repeats.
##
## **Display, not input.** It advances turns that the AI decides; it never queues a player action.
## That is exactly Spectator's contract — a spectator watches a bout play and cannot play it.
##
## **This module IS a `BoutRunner`, paced by a view instead of a tight loop**, which is what makes
## "a spectated battle is identical in outcome to a headless bout for the same seed" true by
## construction rather than by testing.

## Emitted when the bout on screen ends, carrying how many turns it took. `ReplayModule` listens.
signal bout_finished(turns_taken: int)

## Seconds between turns at 1x, on TOP of whatever that turn's own playback already took — its
## animation is real time, not instant. Watching is the whole point ("it must be watchable, not a
## blur"), so this is deliberately paced. Flagged, not tuned.
const BASE_STEP_INTERVAL := 1.2
## The speed button's three fixed steps, cycled. Not a free slider.
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

var runner: BoutRunner = null
var playing: bool = false
var speed: float = 1.0

var play_button: Button = null
var step_button: Button = null
var speed_button: Button = null
var status_label: Label = null
## The three timing knobs. Named rather than anonymous because their arrow-step behaviour is
## asserted directly — `custom_arrow_step` is the up/down increment ONLY, while typing an exact
## value into the field must never be snapped to a multiple of it.
var slide_ms_field: SpinBox = null
var bullet_ms_field: SpinBox = null
var tracer_count_field: SpinBox = null


func module_id() -> StringName:
	return &"playback"


func _mount() -> void:
	var row: Control = context.slot(ModuleSlots.TOP_LEFT, null)
	play_button = _button(row, "Play", _on_play_button_pressed)
	step_button = _button(row, "Step", step_once)
	speed_button = _button(row, "1x", cycle_speed)
	status_label = Label.new()
	if row != null:
		row.add_child(status_label)
	else:
		add_child(status_label)
	_build_tunables()
	rebind()


## The replay panel wants to know when a bout ends, a loaded fixture wants to be played, and a debug
## verb changes what the status line should say.
func link() -> void:
	var replay: ViewModule = context.module(&"replay")
	if replay != null:
		bout_finished.connect((replay as ReplayModule).report_bout_finished)
		(replay as ReplayModule).replay_loaded.connect(_on_replay_loaded)
	var debug: ViewModule = context.module(&"debug_panel")
	if debug != null:
		(debug as DebugPanelModule).verb_applied.connect(_on_verb_applied)


func _on_verb_applied(_verb_id: StringName) -> void:
	refresh_status()


## A replayed fixture has been loaded into the board. **Rebind, then play** — a loaded board with
## nothing driving it is a still image, which is what the supervisor saw: the bout was there and
## nothing moved it.
func _on_replay_loaded(_map_seed: int) -> void:
	if context != null and context.rebind_all.is_valid():
		context.rebind_all.call()
	play()


## Points this module at whatever `context.battle` currently holds, without rebuilding the UI.
##
## **Rebind, emphatically not a rebuild.** The spectator learned this the hard way: calling `setup`
## on a replay constructed a fresh set of panels including the replay panel that was *in the middle
## of iterating*, which destroyed the run it was advancing and left the second seed unloaded. What a
## new board actually needs is a new runner and a re-pointed log; the UI is already correct.
func rebind() -> void:
	playing = false
	if context == null or context.battle == null or context.battle.combat_state == null:
		refresh_status()
		return
	runner = BoutRunner.new(context.battle.combat_state, context.battle.mission)
	# tb44 Pass D: the pacer is what makes a unit's turn watchable rather than a freeze — the frame
	# signal the planner suspends on, plus the hard budget that guarantees the turn ends. Only a
	# module inside a live tree can supply one; a headless driver builds none and never suspends.
	if is_inside_tree():
		runner.pacer = PlanPacer.new()
		runner.pacer.frame_signal = get_tree().process_frame
	refresh_status()


func play() -> void:
	if runner == null or runner.finished or playing:
		return
	playing = true
	refresh_status()
	_run_while_playing()


func pause() -> void:
	playing = false
	refresh_status()


## One unit's whole turn — this bout's own step granularity. Pausing first mirrors a real pacing
## control: "step" implies not simultaneously auto-playing. Awaited, so a caller that cares when the
## animation has finished can wait on it and a plain button press need not.
func step_once() -> void:
	pause()
	await advance()


func set_speed(multiplier: float) -> void:
	speed = multiplier
	var module: ViewModule = context.module(&"resolution")
	if module != null:
		(module as ResolutionModule).set_speed(multiplier)
	refresh_status()


## The status line, and where a thinking unit is named. **Named, never a bare "Thinking…"** — once
## named enemies exist, the difference between a mook's turn and a boss's reads as character rather
## than as lag, because the intelligence tiers make a smarter unit genuinely think longer. What the
## label SAYS is `PlanPacer.thinking_label`'s decision, in logic, so it is answerable headlessly.
func set_thinking_label(text: String) -> void:
	if status_label == null:
		return
	if text == "":
		refresh_status()
		return
	status_label.text = text


func refresh_status() -> void:
	if status_label == null:
		return
	var state_text: String = "playing" if playing else "paused"
	var outcome_text: String = ""
	if runner != null and runner.finished:
		state_text = "finished"
		outcome_text = " — %s" % Enums.MissionOutcome.keys()[runner.mission.outcome]
	var turns_text: String = "%d turns" % (runner.turns_taken if runner != null else 0)
	status_label.text = "%s (%s, %.0fx)%s" % [turns_text, state_text, speed, outcome_text]
	if play_button != null:
		play_button.text = "Pause" if playing else "Play"


## One step, animated.
##
## **The camera is deliberately not moved.** This used to hard-cut to the newly-acting unit every
## step; taskblock-17 removed it outright rather than easing it, because "let the spectator drive
## their own camera" has no automatic movement as its default, not a gentler jump.
##
## **The highlight flip is deferred until after the animation** (`BR27.07`/`BR32.09`). Flipping it
## with the mesh rebuild pointed the indicator at the *next* unit while this one's move was still
## drawing — and because a human turn ends after its own animation, the player path never exposed
## the gap. That is why the same bug read as "correct when the player controls, wrong when the AI
## does".
func advance() -> void:
	if runner == null or runner.finished:
		pause()
		return
	var battle: BattleScene = context.battle
	set_thinking_label(PlanPacer.thinking_label(runner.state.current_unit()))
	await runner.step()
	set_thinking_label("")
	battle.refresh_unit_views(LogPlayback.affected_unit_ids(runner.last_events), false)
	var resolution: ViewModule = context.module(&"resolution")
	if resolution != null:
		await (resolution as ResolutionModule).play(runner.last_events)
	battle.apply_active_turn_highlight()
	refresh_status()
	if runner.finished:
		pause()


## Step, await the full animated playback, wait the inter-turn gap (scaled by speed, like every
## other duration here), repeat — until paused, the bout finishes, or the module is torn down and
## `runner`/`battle` are freed out from under it.
func _run_while_playing() -> void:
	while playing and runner != null and not runner.finished:
		await advance()
		if not playing or runner == null or runner.finished:
			break
		await get_tree().create_timer(BASE_STEP_INTERVAL / speed).timeout
	if runner != null and runner.finished:
		bout_finished.emit(runner.turns_taken)


func _button(parent: Control, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	if parent != null:
		parent.add_child(button)
	else:
		add_child(button)
	return button


## The timing knobs, writing straight into `ResolutionPlayer`'s own public fields — no intermediate
## state here. Temporary debug knobs, flagged as such since taskblock-15.
func _build_tunables() -> void:
	var module: ViewModule = context.module(&"resolution")
	var player: ResolutionPlayer = (module as ResolutionModule).player if module != null else null
	if player == null:
		return
	var row: Control = context.slot(ModuleSlots.TUNABLES, null)
	if row == null:
		return
	slide_ms_field = _tunable_field(
		row,
		"Slide Speed (ms/cell):",
		player.slide_ms,
		func(value: float) -> void: player.slide_ms = value,
		10.0
	)
	bullet_ms_field = _tunable_field(
		row,
		"Bullet Timing (ms):",
		player.bullet_ms,
		func(value: float) -> void: player.bullet_ms = value,
		10.0
	)
	tracer_count_field = _tunable_field(
		row,
		"Tracers:",
		float(player.tracer_count),
		func(value: float) -> void: player.tracer_count = int(value)
	)


## `arrow_step`, if given, sets `custom_arrow_step` — the up/down ARROW increment ONLY. `step`
## itself, which Godot's `Range` quantizes every assignment to, stays at its default fine
## granularity, so typing an exact value into the field is never snapped to a multiple of the arrow
## step. Timing fields pass 10.0 so the arrows move at a pace that matters at millisecond scale; a
## plain count leaves them at 1.
func _tunable_field(
	parent: Control, label_text: String, initial: float, on_changed: Callable, arrow_step := 0.0
) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var field := SpinBox.new()
	field.min_value = 0
	field.max_value = 10000
	if arrow_step > 0.0:
		field.custom_arrow_step = arrow_step
	field.value = initial
	field.value_changed.connect(on_changed)
	parent.add_child(field)
	return field


func _on_play_button_pressed() -> void:
	if playing:
		pause()
	else:
		play()


## Cycles 1x -> 2x -> 4x -> 1x. Public because the speed button is not the only caller — a test
## drives the cycle directly, which is the only way to assert the wrap without a click.
func cycle_speed() -> void:
	var index: int = SPEEDS.find(speed)
	var next_speed: float = SPEEDS[(index + 1) % SPEEDS.size()] if index >= 0 else SPEEDS[0]
	set_speed(next_speed)
	speed_button.text = "%.0fx" % next_speed
