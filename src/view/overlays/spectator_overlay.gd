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

## Seconds between steps at 1x speed — watching is the whole point (docs:
## "it must be watchable, not a blur"), so this is deliberately paced, not
## a tight loop. Flagged, not tuned.
const BASE_STEP_INTERVAL := 1.2

var battle: BattleScene
var runner: BoutRunner
var log_label: RichTextLabel
var log_sink: UISink

var playing: bool = false
var speed: float = 1.0

var _timer: Timer
var _play_button: Button
var _step_button: Button
var _speed_button: Button
var _status_label: Label


## `battle.combat_state`/`battle.mission` are already the freshly-built
## bout by the time this runs — `GenerateBoutOverlay` always calls
## `battle.load_battle()` before swapping to this overlay (A2), so unlike
## `SquadControlOverlay` there is no "not loaded yet" case to guard here,
## and no need to react to a later `battle_loaded` either: this overlay's
## own lifetime is exactly one bout.
func setup(p_battle: BattleScene) -> void:
	battle = p_battle
	runner = BoutRunner.new(battle.combat_state, battle.mission)
	_build_ui()
	battle.combat_state.combat_log.add_sink(log_sink)
	_refresh_status()


func teardown() -> void:
	pause()
	if battle != null and battle.combat_state != null:
		battle.combat_state.combat_log.remove_sink(log_sink)


## docs: "play / pause / step-one-action / speed (1x, 2x, 4x)."
func play() -> void:
	if runner == null or runner.finished:
		return
	playing = true
	_timer.wait_time = BASE_STEP_INTERVAL / speed
	_timer.start()
	_refresh_status()


func pause() -> void:
	playing = false
	if _timer != null:
		_timer.stop()
	_refresh_status()


## "step-one-action" — this bout's own step granularity is one unit's
## whole turn (BoutRunner's own header explains why finer isn't built
## here); pausing first mirrors a real pacing control ("step" implies not
## simultaneously auto-playing).
func step_once() -> void:
	pause()
	_advance()


func set_speed(multiplier: float) -> void:
	speed = multiplier
	if playing:
		_timer.wait_time = BASE_STEP_INTERVAL / speed
	_refresh_status()


func _on_timer_timeout() -> void:
	_advance()


func _advance() -> void:
	if runner == null or runner.finished:
		pause()
		return
	runner.step()
	battle.refresh_unit_views()
	if runner.last_unit != null:
		# "the camera follows the acting unit" (docs) — a plain center_on is
		# intentionally simpler than ease_to_attack_framing (which needs a
		# live shooter+target pair TacticsController's own aim flow already
		# tracks; a bout has no such pairing to reuse).
		battle.camera_rig.center_on(
			Vector3(runner.last_unit.cell.x, 0.0, runner.last_unit.cell.y) * UnitGeometry.CELL_SIZE
		)
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
	_timer = Timer.new()
	_timer.wait_time = BASE_STEP_INTERVAL
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)

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

	log_label = RichTextLabel.new()
	log_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_label.position = Vector2(16, -216)
	log_label.size = Vector2(520, 200)
	log_label.scroll_following = true
	theme_root.add_child(log_label)
	log_sink = UISink.new(log_label)

	_refresh_status()


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
