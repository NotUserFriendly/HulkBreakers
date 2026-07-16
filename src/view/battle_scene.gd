class_name BattleScene
extends Node3D

## docs/10 Phase 12.1: one battle, hand-seeded, from a "New Battle" button.
## No mission loop, no mission verbs yet — just something a human can see
## and orbit a camera around. No hand-authored .tscn for logic (CLAUDE.md):
## the .tscn is a bare Node3D with this script attached; every child is
## built here in code.

## Temporarily swapped for dartboard verification (runNotes.md follow-up) —
## seed 20260715's blue unit rolls a two-handed sword with only one hand to
## wield it (unarmed in practice). Seed 2 gives both squads a working
## pistol. Revert to 20260715 once verification is done.
const DEFAULT_SEED := 2
const GRID_WIDTH := 12
const GRID_HEIGHT := 10
## runNotes.md: "a 16:9 1080p minimum window should be what we work off
## going forward." project.godot's viewport_width/height sets the launch
## size; this is the actual resize floor.
const MIN_WINDOW_SIZE := Vector2i(1920, 1080)

var board_view: BoardView
var camera_rig: CameraRig
var tactics: TacticsController
var aim_view: AimView
var resolution_player: ResolutionPlayer
var stat_panel: StatPanel
var inventory_panel: InventoryPanel
var weapon_panel: WeaponPanel
var controls_overlay: ControlsOverlay
var log_sink: UISink
## docs/09 taskblock03 Pass B: "one stream, many sinks — never two
## streams." The on-screen log (`log_sink`) and this file are fed the same
## `CombatLog.emit()` calls, so they can never drift; neither one renders
## anything the other doesn't also get. A fresh file per `new_battle()`
## call — one session, one replayable log.
var file_sink: FileSink
var unit_views: Array[UnitView] = []
var combat_state: CombatState
## runNotes.md: "highlight what it's doing, and IF it's doing it" — the
## banner/aim-readout/stat-block cluster's own header, DIM when idle and
## HIGHLIGHT the instant either half of it actually has something to show.
var _readout_header: Label


func _ready() -> void:
	if get_window() != null:
		get_window().min_size = MIN_WINDOW_SIZE

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
	# runNotes.md: entering/cancelling aim must refresh the previewed facing
	# too (aim_facing() depends on `aiming_at`, not on anything
	# selection_changed already covers) — aim_changed is what actually
	# fires the instant that happens.
	tactics.aim_changed.connect(_on_selection_changed)

	var ui := CanvasLayer.new()
	add_child(ui)
	var theme_root := Control.new()
	theme_root.theme = HulkTheme.build()
	theme_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	theme_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(theme_root)

	# runNotes.md: "most of the left half of the screen should be the
	# inventory... the combat log should stay bottom left." A left column
	# (inventory, tall, over the log, fixed-height, at its bottom) and a
	# right column (controls overlay top-right; the readout cluster and
	# stacked turn buttons bottom-right) — four independently anchored
	# regions, not one long sidebar.
	#
	# runNotes.md follow-up: "only be as big as it needs to be" — anchored
	# full-height on the left edge, but with NO right anchor stretch, so its
	# actual width comes from inventory_tree's own custom_minimum_size
	# below, not half the screen. mouse_filter = IGNORE is load-bearing:
	# a bare Control defaults to MOUSE_FILTER_STOP, and this one used to
	# span half the screen — swallowing every RMB/MMB drag that started
	# over it before CameraRig's own _unhandled_input ever saw the event.
	var left_half := Control.new()
	left_half.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_half.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_root.add_child(left_half)
	var left_layout := VBoxContainer.new()
	left_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_half.add_child(left_layout)

	# docs/10 taskblock03 H: the inspected unit's inventory — nested tree +
	# a footer for the mass/RAM constraints (docs/05). EXPAND_FILL
	# (vertical only) so it absorbs the left column's height, not the fixed
	# ~4-row box it used to be. Width is a fixed, content-sized minimum
	# (runNotes.md: "only as big as it needs to be") — three narrow columns
	# (Part/Condition/Mass, since H2's decluttering) don't need anywhere
	# near half the screen.
	# runNotes.md follow-up: "add a UI element to the right of the
	# inventory... a list of weapons the unit has attached." A row, not
	# another vertical block — the weapons list sits beside the inventory
	# tree, not below it.
	var inventory_row := HBoxContainer.new()
	inventory_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_layout.add_child(inventory_row)

	var inventory_tree := Tree.new()
	inventory_tree.custom_minimum_size = Vector2(460, 0)
	inventory_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_row.add_child(inventory_tree)

	var weapon_label := RichTextLabel.new()
	weapon_label.bbcode_enabled = true
	weapon_label.custom_minimum_size = Vector2(260, 0)
	weapon_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	weapon_label.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	inventory_row.add_child(weapon_label)

	var inventory_footer := Label.new()
	inventory_footer.add_theme_color_override("font_color", HulkTheme.DIM)
	left_layout.add_child(inventory_footer)

	# runNotes.md: "since we aren't truncating log entries, move the
	# scrollbar to the left side so it doesn't overlay." Un-wrapped lines
	# run right up to the panel's own right edge, where the scrollbar sits
	# by default — silently eating the last character or two of every long
	# line. `layout_direction = RTL` mirrors the CONTROL's own layout
	# (scrollbar included) without touching `text_direction` (a separate
	# property, still LTR/Auto) — verified against a live render that text
	# order/alignment is completely unaffected. A first attempt fought the
	# scrollbar's anchors every frame instead (RichTextLabel resets them
	# internally each layout pass); this one-line flag does the same job
	# natively, no per-frame re-assertion. The matching left content margin
	# below (the scrollbar's own width) stops it from overlapping even the
	# shared "[T0/TACTICS]" prefix every line starts with.
	var log_label := RichTextLabel.new()
	log_label.layout_direction = Control.LAYOUT_DIRECTION_RTL
	log_label.custom_minimum_size = Vector2(0, 220)
	log_label.scroll_following = true
	# runNotes.md: "log needs to both be scrollable and not word wrapping" —
	# scroll_following/scroll_active above already provide the first half;
	# this is the actual fix for the second (autowrap defaults to wrapping
	# at the word boundary, which is what was cutting long lines across
	# multiple visual rows).
	log_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	left_layout.add_child(log_label)
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color.TRANSPARENT
	log_style.content_margin_left = log_label.get_v_scroll_bar().get_combined_minimum_size().x
	log_label.add_theme_stylebox_override("normal", log_style)
	log_sink = UISink.new(log_label)

	# runNotes.md follow-up: same MOUSE_FILTER_IGNORE fix as left_half — this
	# still spans the right half (controls_label and bottom_right anchor to
	# two different corners within it), but must not itself swallow camera
	# drags over that half of the board.
	var right_half := Control.new()
	right_half.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_half.anchor_left = 0.5
	right_half.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_root.add_child(right_half)

	# docs/10 taskblock03 J: "corner-anchored," now specifically top-right
	# (runNotes.md moved it off the turn-controls corner).
	var controls_label := Label.new()
	controls_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_half.add_child(controls_label)

	# runNotes.md: "put the turn controls in the bottom right, stacked,
	# with... [the readout cluster] above the turn controls." One
	# bottom-right-anchored stack: header, then the phase banner + aim/
	# damage readout, then the buttons — in that order, growing upward from
	# the corner.
	var bottom_right := VBoxContainer.new()
	bottom_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_right.alignment = BoxContainer.ALIGNMENT_END
	bottom_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_half.add_child(bottom_right)

	# runNotes.md: "I'm not entirely sure what the info... is. Highlight
	# what it's doing, and IF it's doing it." A plain, named header —
	# _update_readout_header() below flips its color/text with whether the
	# cluster underneath actually has anything live to show.
	_readout_header = Label.new()
	bottom_right.add_child(_readout_header)

	var banner := Label.new()
	banner.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT)
	bottom_right.add_child(banner)

	var aim_readout := RichTextLabel.new()
	aim_readout.bbcode_enabled = false
	aim_readout.custom_minimum_size = Vector2(320, 60)
	aim_readout.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	bottom_right.add_child(aim_readout)

	var stat_label := RichTextLabel.new()
	stat_label.custom_minimum_size = Vector2(320, 40)
	bottom_right.add_child(stat_label)
	var stat_drill_down := RichTextLabel.new()
	stat_drill_down.custom_minimum_size = Vector2(320, 60)
	stat_drill_down.add_theme_color_override("default_color", HulkTheme.DIM)
	bottom_right.add_child(stat_drill_down)

	var new_battle_button := Button.new()
	new_battle_button.text = "New Battle"
	new_battle_button.pressed.connect(_on_new_battle_pressed)
	bottom_right.add_child(new_battle_button)
	var end_turn_button := Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	bottom_right.add_child(end_turn_button)
	# docs/10 taskblock03 D4: "a single Reset Turn control (button + R)."
	var reset_turn_button := Button.new()
	reset_turn_button.text = "Reset Turn"
	reset_turn_button.pressed.connect(_on_reset_turn_pressed)
	bottom_right.add_child(reset_turn_button)

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

	inventory_panel = InventoryPanel.new()
	add_child(inventory_panel)
	inventory_panel.setup(tactics, inventory_tree, inventory_footer, combat_state.material_table)

	weapon_panel = WeaponPanel.new()
	add_child(weapon_panel)
	weapon_panel.setup(tactics, weapon_label)

	controls_overlay = ControlsOverlay.new()
	add_child(controls_overlay)
	controls_overlay.setup(controls_label, file_sink.path)

	_update_readout_header()


func _on_new_battle_pressed() -> void:
	new_battle(int(Time.get_ticks_usec()))


func _on_end_turn_pressed() -> void:
	tactics.end_turn()


func _on_reset_turn_pressed() -> void:
	tactics.reset_turn()


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
##
## docs/10 taskblock03 E3: the selected unit's own view must also render
## SelectionController.previewed_orientation() (queued-but-unresolved
## facing), never the committed `unit.orientation` — every other view's
## `preview_orientation` stays null. Only rebuilds a view when its preview
## actually changes, since this fires on every drag_face() motion event
## (and now, every aim_changed too).
##
## runNotes.md: while aiming, that preview is overridden to face the
## target instead (TacticsController.aim_facing()) — cancelling aim just
## makes aim_facing() start returning null again, so the preview falls
## straight back to the queued orientation with no separate "unface" step.
##
## runNotes.md follow-up: "clicking while a move is highlighted faces both
## the original position and the ghost" — once a move is actually queued,
## the STILL-STATIONARY live model previewing its post-move facing read as
## wrong (it hasn't gone anywhere yet) and duplicated what the end-position
## ghost (TacticsController._end_position_ghost()) already shows. The live
## model now only ever previews its own future while it hasn't queued
## anywhere to go (has_queued_move() == false) — in-place rotation or
## aim-facing with no move queued. The instant a move IS queued, the live
## model falls back to its plain committed orientation and the ghost alone
## carries the preview.
func _on_selection_changed() -> void:
	var selected: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	for view: UnitView in unit_views:
		view.set_selected(view.unit == selected)
		var target_preview: Variant = null
		if view.unit == selected and not tactics.has_queued_move():
			var facing: Variant = tactics.aim_facing()
			target_preview = facing if facing != null else tactics.selection.previewed_orientation()
		if view.preview_orientation != target_preview:
			view.preview_orientation = target_preview
			view.refresh()
	_update_readout_header()


## runNotes.md: "highlight what it's doing, and IF it's doing it." Active
## exactly when there's a selected unit (the stat block has something to
## resolve) or a live aim (the READING/RESOLVES readout has something to
## show) — the same two conditions that already drive whether AimView/
## StatPanel render anything at all, read here rather than re-derived.
func _update_readout_header() -> void:
	if _readout_header == null or tactics == null or tactics.selection == null:
		return
	var active: bool = tactics.aiming_at != null or tactics.selection.selected_unit != null
	if active:
		_readout_header.text = "COMBAT READOUT — active"
		_readout_header.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT)
	else:
		_readout_header.text = "COMBAT READOUT — idle"
		_readout_header.add_theme_color_override("font_color", HulkTheme.DIM)


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
	# docs/10 taskblock03 J / docs/09 B2: a fresh file per new_battle() call —
	# the overlay's "log: <path>" line must follow it. Null on the very
	# first call from _ready(), before controls_overlay exists yet.
	if controls_overlay != null:
		controls_overlay.set_log_path(file_sink.path)

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
	var spawn_a: Vector2i = _first_cell_of_terrain(grid, Enums.TerrainType.SPAWN_A, Vector2i(2, 2))
	var spawn_b: Vector2i = _first_cell_of_terrain(grid, Enums.TerrainType.SPAWN_B, Vector2i(9, 7))
	var units: Array[Unit] = [
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, spawn_a, 0),
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, spawn_b, 1),
	]
	return CombatState.new(grid, units, rng.randi())


## runNotes.md: "the red unit may be spawning in a non-navigable space" —
## MapGen carves real SPAWN_A/SPAWN_B zones but its own `generate()` return
## signature only hands back the Grid, not the cells it placed them at
## (test files already re-derive them the same way, e.g.
## test_full_mission.gd's `_cells_of_terrain`). `fallback` only fires if a
## map somehow has no cell of that terrain at all.
func _first_cell_of_terrain(grid: Grid, terrain: int, fallback: Vector2i) -> Vector2i:
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain:
				return cell
	return fallback


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
