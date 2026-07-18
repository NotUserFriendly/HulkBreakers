class_name BoutView
extends Node3D

## taskblock-14 Pass C: watch an all-AI bout play out. Thin — it drives
## `BoutRunner` on a `Timer` and reuses the exact board/camera/log
## components `BattleScene` already builds for a human-played battle
## (`BoardView`, `CameraRig`, `HitVolumeView`, `FileSink`/`UISink`); the
## only new piece is the pacing (play/pause/step/speed) and the
## camera-follow-the-actor wiring. `setup()` takes an already-built
## `CombatState`/`MissionState` — spawning the matchup itself is
## taskblock-14 Pass D's own job (the bout-setup menu), not this file's.
##
## docs/09/docs/10: this is a VIEW over `BoutRunner`, never a second way
## to decide a turn — every action a watcher sees came out of the exact
## same `UnitAI.plan_turn` + `CombatState.resolve_until` a human's own UI
## calls. Nothing here computes an outcome; it only reads one back.

## Seconds between steps at 1x speed — watching is the whole point (docs:
## "it must be watchable, not a blur"), so this is deliberately paced,
## not a tight loop. Flagged, not tuned.
const BASE_STEP_INTERVAL := 1.2
const MIN_WINDOW_SIZE := Vector2i(1280, 720)

var camera_rig: CameraRig
var board_view: BoardView
var unit_views: Array[HitVolumeView] = []
var runner: BoutRunner
var log_label: RichTextLabel
var log_sink: UISink
var file_sink: FileSink

var playing: bool = false
var speed: float = 1.0

var _timer: Timer
var _play_button: Button
var _step_button: Button
var _speed_button: Button
var _status_label: Label


func _ready() -> void:
	_ensure_built()


## `_ready()` isn't guaranteed to have already run by the time a caller
## adds this node and immediately calls `setup()` in the same call chain
## (a bare `SceneTree` script's own `_initialize()`, in particular, never
## flushes the ready notification before returning) — idempotent, so
## calling it from both `_ready()` and `setup()`'s own start is always
## safe regardless of which one actually gets there first.
func _ensure_built() -> void:
	if camera_rig != null:
		return
	if get_window() != null:
		get_window().min_size = MIN_WINDOW_SIZE
	add_child(WorldPalette.world_environment())
	add_child(WorldPalette.directional_light())

	camera_rig = CameraRig.new()
	add_child(camera_rig)
	board_view = BoardView.new()
	add_child(board_view)

	_timer = Timer.new()
	_timer.wait_time = BASE_STEP_INTERVAL
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)

	_build_ui()


## Wires the bout up to an already-built `CombatState`/`MissionState`
## (taskblock-14 Pass D spawns the matchup and calls this) — rebuilds the
## board/camera/unit views from `state` exactly like
## `BattleScene.new_battle` does, plus a fresh `BoutRunner`.
func setup(
	state: CombatState, mission: MissionState, turn_cap: int = BoutRunner.DEFAULT_TURN_CAP
) -> void:
	_ensure_built()
	for view: HitVolumeView in unit_views:
		remove_child(view)
		view.queue_free()
	unit_views.clear()
	if file_sink != null:
		file_sink.close()

	runner = BoutRunner.new(state, mission, turn_cap)
	file_sink = FileSink.new()
	state.combat_log.add_sink(log_sink)
	state.combat_log.add_sink(file_sink)

	board_view.build(state.grid, state.material_table)
	camera_rig.center_on(
		Vector3(
			(state.grid.width - 1) * UnitGeometry.CELL_SIZE * 0.5,
			0.0,
			(state.grid.height - 1) * UnitGeometry.CELL_SIZE * 0.5
		)
	)

	for unit: Unit in state.units:
		var view := HitVolumeView.new()
		add_child(view)
		view.setup(unit, state.material_table)
		unit_views.append(view)

	_refresh_status()


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
	_timer.stop()
	_refresh_status()


## "step-one-action" — this bout's own step granularity is one unit's
## whole turn (BoutRunner's own header explains why finer isn't built
## here); pausing first mirrors a real pacing control ("step" implies
## not simultaneously auto-playing).
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
	_refresh_unit_views()
	if runner.last_unit != null:
		# "the camera follows the acting unit" (docs) — a plain center_on
		# is intentionally simpler than ease_to_attack_framing (which
		# needs a live shooter+target pair TacticsController's own aim
		# flow already tracks; a bout has no such pairing to reuse).
		camera_rig.center_on(
			Vector3(runner.last_unit.cell.x, 0.0, runner.last_unit.cell.y) * UnitGeometry.CELL_SIZE
		)
	_refresh_status()
	if runner.finished:
		pause()


func _refresh_unit_views() -> void:
	for view: HitVolumeView in unit_views:
		view.refresh()


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
