class_name BattleScene
extends Node3D

## docs/10 Phase 12.1: one battle, hand-seeded, from a "New Battle" button.
## No mission loop, no mission verbs yet — just something a human can see
## and orbit a camera around. No hand-authored .tscn for logic (CLAUDE.md):
## the .tscn is a bare Node3D with this script attached; every child is
## built here in code.

const DEFAULT_SEED := 20260715
const GRID_WIDTH := 12
const GRID_HEIGHT := 10

var board_view: BoardView
var camera_rig: CameraRig
var tactics: TacticsController
var aim_view: AimView
var resolution_player: ResolutionPlayer
var stat_panel: StatPanel
var log_sink: UISink
## docs/09 taskblock03 Pass B: "one stream, many sinks — never two
## streams." The on-screen log (`log_sink`) and this file are fed the same
## `CombatLog.emit()` calls, so they can never drift; neither one renders
## anything the other doesn't also get. A fresh file per `new_battle()`
## call — one session, one replayable log.
var file_sink: FileSink
var unit_views: Array[UnitView] = []
var combat_state: CombatState


func _ready() -> void:
	add_child(WorldPalette.world_environment())
	add_child(WorldPalette.directional_light())

	camera_rig = CameraRig.new()
	add_child(camera_rig)

	board_view = BoardView.new()
	add_child(board_view)

	tactics = TacticsController.new()
	add_child(tactics)
	tactics.turn_ended.connect(_on_turn_ended)
	tactics.selection_changed.connect(_on_selection_changed)

	var ui := CanvasLayer.new()
	add_child(ui)
	var theme_root := Control.new()
	theme_root.theme = HulkTheme.build()
	theme_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	theme_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(theme_root)
	var layout := VBoxContainer.new()
	theme_root.add_child(layout)

	var buttons := HBoxContainer.new()
	layout.add_child(buttons)
	var new_battle_button := Button.new()
	new_battle_button.text = "New Battle"
	new_battle_button.pressed.connect(_on_new_battle_pressed)
	buttons.add_child(new_battle_button)
	var end_turn_button := Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	buttons.add_child(end_turn_button)

	var banner := Label.new()
	banner.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT)
	layout.add_child(banner)

	var aim_readout := RichTextLabel.new()
	aim_readout.bbcode_enabled = false
	aim_readout.custom_minimum_size = Vector2(320, 60)
	aim_readout.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	layout.add_child(aim_readout)

	var stat_label := RichTextLabel.new()
	stat_label.custom_minimum_size = Vector2(320, 40)
	layout.add_child(stat_label)
	var stat_drill_down := RichTextLabel.new()
	stat_drill_down.custom_minimum_size = Vector2(320, 60)
	stat_drill_down.add_theme_color_override("default_color", HulkTheme.DIM)
	layout.add_child(stat_drill_down)

	var log_label := RichTextLabel.new()
	log_label.custom_minimum_size = Vector2(320, 200)
	log_label.scroll_following = true
	layout.add_child(log_label)
	log_sink = UISink.new(log_label)

	aim_view = AimView.new()
	add_child(aim_view)
	aim_view.setup(tactics, aim_readout)

	resolution_player = ResolutionPlayer.new()
	add_child(resolution_player)
	resolution_player.setup(banner, tactics)

	stat_panel = StatPanel.new()
	add_child(stat_panel)
	stat_panel.setup(tactics, stat_label, stat_drill_down)

	new_battle(DEFAULT_SEED)


func _on_new_battle_pressed() -> void:
	new_battle(int(Time.get_ticks_usec()))


func _on_end_turn_pressed() -> void:
	tactics.end_turn()


## Resolution has already mutated combat_state for real (docs/09) — every
## UnitView rebuilds from the unit it already tracks, so a destroyed part
## disappears and a moved unit redraws at its new cell. `events` is then
## handed to ResolutionPlayer purely as a cosmetic replay (docs/10 Phase
## 12.4) — it never re-drives the sim, which has already finished.
func _on_turn_ended(events: Array[LogEvent]) -> void:
	for view: UnitView in unit_views:
		view.refresh()
	_on_selection_changed()
	resolution_player.play(events)


## docs/10 team flagging: the selected unit's ground marker brightens, and
## no other unit's does — a pure overlay, never touching a part's material.
func _on_selection_changed() -> void:
	var selected: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	for view: UnitView in unit_views:
		view.set_selected(view.unit == selected)


## Public (not just _ready-internal) so a headless caller/test can seed a
## battle without going through button input.
func new_battle(seed_value: int) -> void:
	for view: UnitView in unit_views:
		remove_child(view)
		view.queue_free()
	unit_views.clear()

	if file_sink != null:
		file_sink.close()
	file_sink = FileSink.new()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	combat_state = _seed_battle(rng)
	combat_state.combat_log.add_sink(log_sink)
	combat_state.combat_log.add_sink(file_sink)
	# docs/09 taskblock03 Pass B2: the seed at session start, so a session
	# is replayable from its own log file alone. This scene has no separate
	# loadout selection to log (assemble_random draws everything — geometry,
	# loadout, the works — from this one seed already).
	combat_state.combat_log.emit(_session_start_event(seed_value))

	board_view.build(combat_state.grid, combat_state.material_table)
	camera_rig.center_on(
		Vector3(
			(combat_state.grid.width - 1) * UnitGeometry.CELL_SIZE * 0.5,
			0.0,
			(combat_state.grid.height - 1) * UnitGeometry.CELL_SIZE * 0.5
		)
	)
	tactics.setup(combat_state, board_view, camera_rig)

	for unit: Unit in combat_state.units:
		var view := UnitView.new()
		add_child(view)
		view.setup(unit, combat_state.material_table)
		unit_views.append(view)


## A small hand-seeded fight, two squads of deep-struck cyborgs — reusing
## DeepStrike's pool for quick, varied loadouts rather than re-authoring
## parts here. Mission loop, roster/loadout selection: out of scope for
## Phase 12 (one battle, no mission).
func _seed_battle(rng: RandomNumberGenerator) -> CombatState:
	var grid: Grid = MapGen.generate(rng.randi(), GRID_WIDTH, GRID_HEIGHT)
	var pool: Array[Part] = DeepStrike.default_part_pool()
	var units: Array[Unit] = [
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, Vector2i(2, 2), 0),
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, Vector2i(9, 7), 1),
	]
	return CombatState.new(grid, units, rng.randi())


## docs/09 taskblock03 Pass B2: "log the seed... at session start, so a
## session is replayable from its own log file." unit_id -1: no specific
## unit caused this, same convention `_log_impact` already uses for
## cover/terrain.
func _session_start_event(seed_value: int) -> LogEvent:
	return LogEvent.new(
		0,
		Enums.Phase.TACTICS,
		-1,
		&"session_start",
		{"seed": seed_value},
		"session_start: seed=%d" % seed_value
	)


func _exit_tree() -> void:
	if file_sink != null:
		file_sink.close()
