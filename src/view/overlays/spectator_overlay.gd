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

## taskblock-30/31: the same generic capture concept `TacticsController`
## gained — no `BoutInjector` reference here either, just a "borrow the
## next real click" mechanism a debug panel's own board-picking mode can
## use. Emits the same normalized `{"kind", "unit", "cell"}` shape
## `TacticsController.board_clicked` does, so a panel can listen against
## either overlay identically.
signal board_clicked(hit: Dictionary)

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
var log_sink: HierarchicalUiSink

## taskblock-29 Pass D / taskblock-30: every button below calls straight
## into this, never a bespoke direct mutation of its own (CLAUDE.md "no
## parallel systems"). taskblock-30: no longer constructed here —
## `BattleScene` owns the one instance (rebuilt per `load_battle()`, so it
## survives a spectator <-> player overlay swap); this just reads it.
## `TacticsController`/`ActionBar` (the actual gameplay-INPUT classes,
## never an overlay shell) still never reference `BoutInjector` at all
## (test_bout_injector_determinism.gd's own routing/guard test proves it
## from source) — that's the real safety property, and it's unchanged by
## `SquadControlOverlay` gaining its own debug-gated Inject affordance.
var bout_injector: BoutInjector
## taskblock-30/31: paired with `board_clicked` (declared with this
## file's other signals, above) — while true, the next real click is
## captured instead of doing this overlay's own normal thing.
var input_capture_mode: bool = false
## taskblock-30/31 Pass C: the full click-to-force panel (`DebugVerbs.
## all()`), superseding the old flat 3-item `InjectMenu` popup — reachable
## via the same "Inject..." button, only inside `if OS.is_debug_build():`
## (never even constructed in a release export).
var debug_panel: DebugControlPanel = null

## taskblock-21 Pass B: "clicking a bot during a bout pauses the bout and
## opens the inspect panel on that bot. Closing it resumes." Supersedes
## tb17 C's hover-tooltip entirely — `UnitPicker.hit()` (a plain static
## ray-pick, the same one `TacticsController.update_hover()` used
## internally) is all a click handler needs; no `TacticsController`/
## `TooltipController`/`TooltipView` instance is wired here anymore.
var inspect_panel: InspectPanel

var playing: bool = false
var speed: float = 1.0

var _play_button: Button
var _step_button: Button
var _speed_button: Button
var _status_label: Label
var _slide_ms_field: SpinBox
var _bullet_ms_field: SpinBox
var _tracer_count_field: SpinBox
## Whether the bout was actually auto-playing at the moment a click opened
## the inspect panel — "closing it resumes" must never START auto-play for
## someone who had already paused by hand before clicking a unit.
var _was_playing_before_inspect: bool = false
## Whichever unit `_update_hover` last found under the cursor — the
## injection menu's own implicit "target," the same "whichever unit the
## cursor is actually over" concept `_update_hover` already tracks
## visually (highlight), just also remembered here since the debug menu
## needs to know WHO by the time it's actually clicked open.
var _hovered_unit: Unit = null


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
	bout_injector = battle.bout_injector

	_build_ui()
	battle.combat_state.combat_log.add_sink(log_sink)
	_refresh_status()


## taskblock-21 Pass B: a left click picks a real unit under the cursor
## (`UnitPicker.hit()`, the same ray-pick `TacticsController.update_hover()`
## used internally — no full TacticsController needed for a plain pick) and
## opens the inspect panel on it, pausing the bout the same way the Pause
## button already does. CameraRig's own independent `_unhandled_input`
## (orbit/pan/zoom) is untouched by any of this, exactly like every other
## overlay.
##
## taskblock-26 Pass E: "objects and tiles don't [have a click inspector]."
## A miss against every unit's own body now falls through to
## `BoardPicker.cell_at_ray` (the same ground-plane pick move-target
## selection already uses) — a hit there opens the SAME `inspect_panel`
## against `Grid.blockers.get(cell)` (`open_tile()`, InspectPanel's own
## tile-shaped entry point; null for a bare tile is already its documented
## "empty state" case, not a special case here). A miss against the board
## plane too (looking off into the void) is still a real no-op.
##
## taskblock-27 Pass D1c: mouse motion drives `_update_hover()` (below) so
## this view gets the same inspect-on-hover feedback `SquadControlOverlay`
## already has, instead of only reacting to clicks.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
		return
	if event is not InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var camera: Camera3D = battle.camera_rig.camera() if battle != null else null
	if camera == null:
		return
	var from: Vector3 = camera.project_ray_origin(mb.position)
	var dir: Vector3 = camera.project_ray_normal(mb.position)
	var hit: Dictionary = UnitPicker.hit(battle.combat_state.units, from, dir)
	if input_capture_mode:
		var picked_unit: Unit = hit.unit as Unit if not hit.is_empty() else null
		var picked_cell: Variant = (
			hit.unit.cell if picked_unit != null else BoardPicker.cell_at_ray(from, dir)
		)
		(
			board_clicked
			. emit(
				{
					"kind": Enums.HitKind.UNIT if picked_unit != null else Enums.HitKind.CELL,
					"unit": picked_unit,
					"cell": picked_cell,
				}
			)
		)
		return
	if not hit.is_empty():
		_was_playing_before_inspect = playing
		pause()
		inspect_panel.open(hit.unit as Unit)
		return
	var cell: Variant = BoardPicker.cell_at_ray(from, dir)
	if cell == null or not battle.combat_state.grid.in_bounds(cell as Vector2i):
		return
	# taskblock-27 Pass D5: "wall tiles should not be inspectable" — a wall
	# isn't a part assembly (`Grid.blockers` is never populated for one,
	# `map_gen.gd`'s own `_scatter_cover` only ever writes cover onto OPEN
	# terrain), so this is a real, deliberate exclusion, not a stand-in for
	# the null-root "empty state" `open_tile` already handles gracefully.
	if battle.combat_state.grid.get_terrain(cell) == Enums.TerrainType.WALL:
		return
	_was_playing_before_inspect = playing
	pause()
	inspect_panel.open_tile(cell as Vector2i, battle.combat_state.grid.blockers.get(cell))


## taskblock-27 Pass D1c: the same `UnitPicker.hit()` ray-pick the click
## handler above already uses, run on every mouse-motion event instead of a
## button press. Unlike `TacticsController.update_hover()` (which only
## highlights the currently-selected unit's own parts — meaningful in
## player view, where "selected" is a real concept), spectator view has no
## selection at all, so whichever unit the cursor is actually over gets
## highlighted; every other view's highlight clears the same way
## `SquadControlOverlay._on_highlight_changed()` clears every
## not-currently-selected view.
func _update_hover(screen_pos: Vector2) -> void:
	var camera: Camera3D = battle.camera_rig.camera() if battle != null else null
	if camera == null:
		return
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var hit: Dictionary = UnitPicker.hit(battle.combat_state.units, from, dir)
	var hovered_unit: Unit = hit.unit as Unit if not hit.is_empty() else null
	var hovered_part: Part = hit.part as Part if not hit.is_empty() else null
	_hovered_unit = hovered_unit
	for view: HitVolumeView in battle.unit_views:
		if view.unit == hovered_unit:
			view.highlight_part(hovered_part)
		else:
			view.clear_highlight()


func _on_inspect_panel_closed() -> void:
	if _was_playing_before_inspect:
		play()


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

	# taskblock-21 Pass C: "toggle assume-control of blue team <-> watch...
	# mid-bout toggle is allowed." battle.toggle_blue_control() tears this
	# whole overlay down as part of the swap — nothing further to do here
	# after calling it.
	var assume_control_button := Button.new()
	assume_control_button.text = "Assume Control"
	assume_control_button.pressed.connect(battle.toggle_blue_control)
	controls.add_child(assume_control_button)

	# taskblock-29 Pass D / taskblock-30/31 Pass C: "programmatic injection
	# is the primary path... the spectator UI is a convenience wrapper over
	# the same BoutInjector calls, not a separate path" — the panel below
	# is exactly that wrapper, full verb table instead of a flat 3-item
	# menu now. `OS.is_debug_build()` is a REAL gate, not just the `[*]`
	# naming convention — neither the button nor the panel is ever added to
	# the tree in a release export, so there's nothing to click regardless
	# of what's drawn.
	if OS.is_debug_build():
		var inject_button := Button.new()
		inject_button.text = "Inject..."
		inject_button.pressed.connect(_on_inject_pressed)
		controls.add_child(inject_button)

		debug_panel = DebugControlPanel.new()
		debug_panel.visible = false
		debug_panel.applied.connect(_on_debug_panel_applied)
		theme_root.add_child(debug_panel)

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
	# taskblock-27 Pass D1a: `SquadControlOverlay`'s own log label already
	# fixed this (runNotes.md: "log needs to both be scrollable and not
	# word wrapping") — autowrap defaults to wrapping at the word
	# boundary, cutting long lines across multiple visual rows. This
	# overlay's own log label never got the same one-line fix.
	log_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	theme_root.add_child(log_label)
	log_sink = HierarchicalUiSink.new(log_label, battle.combat_state)

	# taskblock-21 Pass B: THE inspect surface now, superseding tb17 C's
	# hover-tooltip — created last so it draws above every other panel
	# here too. Added to the tree BEFORE setup() (docs/02: setup()'s own
	# bot-viewer build needs a live tree for Camera3D.look_at()).
	inspect_panel = InspectPanel.new()
	# taskblock-22 Pass G1: InspectPanel's own _clamp_to_viewport now owns
	# fitting this to the real viewport — no anchors preset needed.
	inspect_panel.custom_minimum_size = Vector2(900, 600)
	theme_root.add_child(inspect_panel)
	# taskblock-22 Pass G2: same live-view lookup SquadControlOverlay wires.
	inspect_panel.setup(DataLibrary.material_table(), null, battle.find_unit_view)
	inspect_panel.closed.connect(_on_inspect_panel_closed)

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


## taskblock-30/31 Pass C: toggles the full debug control panel —
## `debug_panel` is null whenever this isn't a debug build (never
## constructed at all in `_build_ui()`), so this is a silent no-op there
## too, same posture the button's own absence already gives it.
func _on_inject_pressed() -> void:
	if debug_panel == null:
		return
	if debug_panel.visible:
		debug_panel.visible = false
		return
	debug_panel.setup(bout_injector, DeepStrike.reference_humanoid_pool(), self)
	debug_panel.visible = true


func _on_debug_panel_applied(_verb_id: StringName, _args: Dictionary) -> void:
	battle.sync_unit_views()
	battle.refresh_unit_views()
	_refresh_status()
