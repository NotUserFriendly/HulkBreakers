class_name SpectatorOverlay
extends ControlOverlay

## taskblock-15 Pass A: "nothing; no unit input; camera-follow + pacing
## only. A bout is this." Everything `BoutView` (taskblock-14 Pass C) used
## to own is folded in here, minus the world it used to build for
## itself (`board_view`/`camera_rig`/`unit_views`) — `BattleScene` already
## owns all of that now, shared with every other overlay. `wants_turn_for`
## is never overridden: the base class's own default (always false) is
## exactly right — no unit is ever human-driven under this overlay, which
## is also why `BoutRunner` here needs no injected predicate at all (its
## own default squad-controller check already matches, since
## `GenerateBoutOverlay`/`BoutSetup` always sets every squad to AI before
## handing off here). This is what makes "a spectator battle is identical
## in outcome to today's BoutRunner bout for the same seed" true BY
## CONSTRUCTION: this overlay IS a `BoutRunner`, paced by a view instead of
## a tight loop.
##
## taskblock-15 Pass B1: "during spectated playback, the next cue waits
## for the current animation to finish." A fixed-interval Timer can't give
## that guarantee (a real animated ResolutionPlayer.play() can legitimately
## outlast one tick, and a Timer keeps ticking underneath regardless,
## risking an overlapping/reentrant step) — play() now drives a
## self-chaining async loop instead: step, AWAIT that step's own full
## animated playback, then wait the inter-turn gap, repeat. Pause/Step/
## Speed still read exactly as before; only the internal driving mechanism
## changed.

## Seconds between turns at 1x speed, on TOP of whatever that turn's own
## ResolutionPlayer.play() call already took (its animation is real time,
## not instant) — watching is the whole point (docs: "it must be
## watchable, not a blur"), so this is deliberately paced. Flagged, not
## tuned.
const BASE_STEP_INTERVAL := 1.2

var battle: BattleScene
var runner: BoutRunner
var resolution_player: ResolutionPlayer
var log_label: RichTextLabel
var log_sink: UISink

## taskblock-17 Pass C1: "hovering a tile/unit/field-object shows the
## tooltip, same mechanism as the squad overlay" — a real `TacticsController`
## instance, its own `_unhandled_input` explicitly disabled (this overlay
## drives ONLY `update_hover()`, never click-select/queue/facing-drag/
## keyboard shortcuts — those would silently build dead `ActionQueue`
## previews for a bout no human is playing) so `TooltipController` can read
## `hovered_cell`/`inspected_part`/`selection` off it exactly like
## `SquadControlOverlay` does, with no second tooltip mechanism built.
var tactics: TacticsController
var tooltip_view: TooltipView
var tooltip_controller: TooltipController

var playing: bool = false
var speed: float = 1.0

var _play_button: Button
var _step_button: Button
var _speed_button: Button
var _status_label: Label
var _slide_ms_field: SpinBox
var _bullet_ms_field: SpinBox
var _tracer_count_field: SpinBox


## `battle.combat_state`/`battle.mission` are already the freshly-built
## bout by the time this runs — `GenerateBoutOverlay` always calls
## `battle.load_battle()` before swapping to this overlay (A2), so unlike
## `SquadControlOverlay` there is no "not loaded yet" case to guard here,
## and no need to react to a later `battle_loaded` either: this overlay's
## own lifetime is exactly one bout.
func setup(p_battle: BattleScene) -> void:
	battle = p_battle
	runner = BoutRunner.new(battle.combat_state, battle.mission)
	resolution_player = ResolutionPlayer.new()
	add_child(resolution_player)
	resolution_player.setup(battle)

	tactics = TacticsController.new()
	add_child(tactics)
	tactics.set_process_unhandled_input(false)
	tactics.setup(battle.combat_state, battle.board_view, battle.camera_rig)

	_build_ui()
	battle.combat_state.combat_log.add_sink(log_sink)
	_refresh_status()


## Forwards ONLY mouse motion into `tactics.update_hover()` — `tactics`'s
## own `_unhandled_input` is disabled (see `tactics`'s own doc comment
## above), so clicks/keys never reach `SelectionController`/facing-drag/
## aim mode; CameraRig's own independent `_unhandled_input` (orbit/pan/
## zoom) is untouched by any of this, exactly like every other overlay.
func _unhandled_input(event: InputEvent) -> void:
	if tactics == null or event is not InputEventMouseMotion:
		return
	tactics.update_hover((event as InputEventMouseMotion).position)


func teardown() -> void:
	pause()
	if battle != null and battle.combat_state != null:
		battle.combat_state.combat_log.remove_sink(log_sink)


## docs: "play / pause / step-one-action / speed (1x, 2x, 4x)."
func play() -> void:
	if runner == null or runner.finished or playing:
		return
	playing = true
	_refresh_status()
	_run_while_playing()


func pause() -> void:
	playing = false
	_refresh_status()


## "step-one-action" — this bout's own step granularity is one unit's
## whole turn (BoutRunner's own header explains why finer isn't built
## here); pausing first mirrors a real pacing control ("step" implies not
## simultaneously auto-playing). Awaited, per B1: a caller (a test, or the
## Step button's own handler) that cares when the animation has actually
## finished can wait on it; one that doesn't (a plain button press) just
## lets it run.
func step_once() -> void:
	pause()
	await _advance()


func set_speed(multiplier: float) -> void:
	speed = multiplier
	resolution_player.speed = multiplier
	_refresh_status()


## B1's own gating loop: step, await that step's FULL animated playback,
## wait the inter-turn gap (scaled by speed, same as every other duration
## here), repeat — until paused, the bout finishes, or this overlay is
## torn down (`runner`/`battle` freed out from under it).
func _run_while_playing() -> void:
	while playing and runner != null and not runner.finished:
		await _advance()
		if not playing or runner == null or runner.finished:
			break
		await get_tree().create_timer(BASE_STEP_INTERVAL / speed).timeout


## taskblock-17 Pass C2: "stop auto-snapping — let the spectator drive
## their own camera." Used to hard-cut CameraRig to the newly-acting unit
## every step here (`center_on`) — removed outright, not eased: the note
## is "let spectator control their own camera," and the default for that
## is simply no automatic camera movement at all, never a gentler version
## of the same jump. CameraRig's own independent `_unhandled_input`
## (orbit/pan/zoom) was never routed through this method and needs no
## change to keep working.
func _advance() -> void:
	if runner == null or runner.finished:
		pause()
		return
	runner.step()
	# taskblock-19 Pass I2: only the units this step's own events named —
	# see BattleScene.refresh_unit_views()'s own doc comment.
	battle.refresh_unit_views(LogPlayback.affected_unit_ids(runner.last_events))
	await resolution_player.play(runner.last_events)
	_refresh_status()
	if runner.finished:
		pause()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var state_text: String = "playing" if playing else "paused"
	var outcome_text: String = ""
	if runner != null and runner.finished:
		state_text = "finished"
		outcome_text = " — %s" % Enums.MissionOutcome.keys()[runner.mission.outcome]
	var turns_text: String = "%d turns" % (runner.turns_taken if runner != null else 0)
	_status_label.text = "%s (%s, %.0fx)%s" % [turns_text, state_text, speed, outcome_text]
	_play_button.text = "Pause" if playing else "Play"


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var theme_root := Control.new()
	theme_root.theme = HulkTheme.build()
	theme_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(theme_root)
	theme_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var controls := HBoxContainer.new()
	controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
	controls.position = Vector2(16, 16)
	controls.mouse_filter = Control.MOUSE_FILTER_STOP
	theme_root.add_child(controls)

	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_on_play_button_pressed)
	controls.add_child(_play_button)

	_step_button = Button.new()
	_step_button.text = "Step"
	_step_button.pressed.connect(step_once)
	controls.add_child(_step_button)

	_speed_button = Button.new()
	_speed_button.text = "1x"
	_speed_button.pressed.connect(_on_speed_button_pressed)
	controls.add_child(_speed_button)

	_status_label = Label.new()
	controls.add_child(_status_label)

	# taskblock-15 Pass B4: "editable fields at the top of the spectator
	# overlay... temporary debug knobs" — write straight into
	# resolution_player's own public fields, no intermediate state here.
	var tunables := HBoxContainer.new()
	tunables.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tunables.position = Vector2(16, 48)
	tunables.mouse_filter = Control.MOUSE_FILTER_STOP
	theme_root.add_child(tunables)

	_slide_ms_field = _tunable_field(
		tunables, "Slide Speed (ms/cell):", resolution_player.slide_ms, _on_slide_ms_changed, 10.0
	)
	_bullet_ms_field = _tunable_field(
		tunables, "Bullet Timing (ms):", resolution_player.bullet_ms, _on_bullet_ms_changed, 10.0
	)
	_tracer_count_field = _tunable_field(
		tunables, "Tracers:", float(resolution_player.tracer_count), _on_tracer_count_changed
	)

	log_label = RichTextLabel.new()
	log_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_label.position = Vector2(16, -216)
	log_label.size = Vector2(520, 200)
	log_label.scroll_following = true
	theme_root.add_child(log_label)
	log_sink = UISink.new(log_label)

	# taskblock-17 Pass C1: THE one tooltip renderer, same as
	# SquadControlOverlay's own — created last so it draws above every
	# other panel here too.
	tooltip_view = TooltipView.new()
	tooltip_controller = TooltipController.new()
	add_child(tooltip_controller)
	tooltip_controller.setup(tactics, tooltip_view, DataLibrary.material_table())
	theme_root.add_child(tooltip_view)

	_refresh_status()


## `arrow_step`, if given, sets `custom_arrow_step` — the up/down ARROW
## button increment ONLY. `step` itself (which Godot's `Range` quantizes
## every value assignment to, typed or not — `SpinBox.rounded` is a
## display-formatting flag, not what governs this) stays at its default
## fine granularity, so clicking into the field's own LineEdit and typing
## an exact value is never snapped to a multiple of the arrow step. Timing
## fields (slide/bullet ms) pass 10.0 so the arrows move at a pace that
## actually matters at millisecond scale; `tracer_count` (a plain count,
## not a duration) leaves the arrows at the default step of 1.
func _tunable_field(
	parent: HBoxContainer,
	label_text: String,
	initial: float,
	on_changed: Callable,
	arrow_step: float = 0.0
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


func _on_slide_ms_changed(value: float) -> void:
	resolution_player.slide_ms = value


func _on_bullet_ms_changed(value: float) -> void:
	resolution_player.bullet_ms = value


func _on_tracer_count_changed(value: float) -> void:
	resolution_player.tracer_count = int(value)


func _on_play_button_pressed() -> void:
	if playing:
		pause()
	else:
		play()


## Cycles 1x -> 2x -> 4x -> 1x — three fixed steps (docs), not a free slider.
func _on_speed_button_pressed() -> void:
	var next_speed: float = 1.0
	if speed == 1.0:
		next_speed = 2.0
	elif speed == 2.0:
		next_speed = 4.0
	set_speed(next_speed)
	_speed_button.text = "%.0fx" % next_speed
