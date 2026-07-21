class_name SquadControlOverlay
extends ControlOverlay

## taskblock-15 Pass A: "a squad — today's select-then-command
## (TacticsController) — the current experience." Everything
## `BattleScene._ready()` used to build beyond the world itself (every
## panel, TacticsController, the turn buttons) moves here verbatim —
## behavior-preserving by construction, not a rewrite. `wants_turn_for`
## reads `CombatState.controller_for` exactly as it already existed
## (taskblock-02 F1's "Control All Squads" default is untouched); the one
## genuinely new capability this pass adds is auto-resolving any squad a
## designer/test DOES flip to AI (`ControlOverlay.advance_ai_turns`),
## which was structurally impossible before this taskblock (nothing ever
## consumed `Enums.SquadController.AI` outside a bout).

var battle: BattleScene
var tactics: TacticsController
var aim_view: AimView
var resolution_player: ResolutionPlayer
var stat_panel: StatPanel
var weapon_panel: WeaponPanel
var tooltip_view: TooltipView
var tooltip_controller: TooltipController
var queue_panel: QueuePanel
var action_bar: ActionBar
var ap_mp_pip_row: ApMpPipRow
var controls_overlay: ControlsOverlay
## tb31 Pass A: toggles `controls_overlay.label.visible` — the display
## itself defaults OFF now (reference, not chrome); this is the second of
## its two surfaces, the H-key (`ControlsOverlay._unhandled_input`) being
## the first. Both flip the SAME state, never two mechanisms.
var keybindings_button: Button
## taskblock-21 Pass A: the inspect/status panel — a modal opened
## on-demand for whatever's currently selected. taskblock-22 Pass I: now
## THE inventory surface in player view — the old always-visible
## `InventoryPanel`/`inventory_tree` it used to sit alongside is retired.
var inspect_panel: InspectPanel
var inspect_button: Button
## taskblock-22 Pass E3: "an action-bar task: on click, prompts with all
## repairable damaged parts, each with its own scrap cost." A plain
## button + PopupMenu, the same shape `inspect_button`/InspectPanel's own
## debug menu already establish — never routed through `arm_action`
## (`&"repair"`'s own `requires_target=false`, matching overwatch's own
## still-flagged gap, means arming it is a documented no-op).
var repair_button: Button
## taskblock-30/31 Pass C: `SquadControlOverlay`'s own debug-gated Inject
## affordance — opens the full `DebugControlPanel` (`DebugVerbs.all()`),
## targeting a unit id typed/picked directly in the panel rather than
## `tactics.selection.selected_unit` implicitly (the panel's own "Pick"
## buttons cover the common "target whatever's selected" case just as
## well, and stay uniform with every other UNIT param). Null in a release
## export — `OS.is_debug_build()` gates whether `_build_ui()` ever
## constructs it at all, not just a `[*]`-style label.
var inject_button: Button
## taskblock-08 E1: the left column pairing the AP/MP pip rows above the
## action bar — exposed so a test can confirm that ordering structurally,
## the same way `action_bar`/`ap_mp_pip_row` are already exposed for their
## own logic-level tests.
var action_column: VBoxContainer
## taskblock-08 E1/E3: the Resolve to Here / End Turn / Reset Turn column,
## to the action bar's right — exposed so a test can confirm New Battle
## (E3: "not a turn control") is never among its children.
var turn_controls_column: VBoxContainer
## tb31 Pass A: the shared top-left cluster (`TopLeftControls`) — these
## three fields alias straight into it (`new_battle_button`/`watch_button`/
## `inject_button` below), so every existing reference to "this overlay's
## own New Battle/Watch/Inject button" keeps working unchanged; the actual
## construction/wiring lives in the ONE shared class now, not here.
var top_left_controls: TopLeftControls
var new_battle_button: Button
## taskblock-21 Pass C: mid-bout toggle back to spectating.
var watch_button: Button
var log_sink: HierarchicalUiSink
## taskblock-30/31 Pass C: the full click-to-force panel, superseding the
## old flat 3-item `InjectMenu` popup — built once (inside `_build_ui()`,
## only when `OS.is_debug_build()`), toggled by `inject_button`.
var debug_panel: DebugControlPanel = null
## runNotes.md: "highlight what it's doing, and IF it's doing it" — the
## banner/aim-readout/stat-block cluster's own header, DIM when idle and
## HIGHLIGHT the instant either half of it actually has something to show.
var _readout_header: Label
## taskblock-22 Pass E3: the repair picker's own PopupMenu instance —
## rebuilt fresh on every `_on_repair_pressed` call, same "queue_free the
## old one first" convention InspectPanel's own debug menu already has.
var _repair_menu: PopupMenu = null


## `battle.combat_state` may still be null here — `BattleScene._ready()`
## installs this overlay BEFORE its own first `new_battle()` call, exactly
## so the session-start log line has a live log_sink to land in the
## instant it's emitted (`_on_battle_loaded()` below re-attaches log_sink
## synchronously, inside `load_battle()`'s own `battle_loaded.emit()`,
## strictly before `new_battle()` goes on to emit that event). `_build_ui()`
## itself must not depend on a battle actually being loaded yet.
func setup(p_battle: BattleScene) -> void:
	battle = p_battle
	_build_ui()
	battle.battle_loaded.connect(_on_battle_loaded)
	if battle.combat_state != null:
		_on_battle_loaded()


func teardown() -> void:
	if battle != null and battle.battle_loaded.is_connected(_on_battle_loaded):
		battle.battle_loaded.disconnect(_on_battle_loaded)
	if battle != null and battle.combat_state != null:
		battle.combat_state.combat_log.remove_sink(log_sink)


## docs/10 taskblock02 F1 (tb31 Pass B): true only for an explicitly
## HUMAN squad — `controller_for` no longer has a silent HUMAN default to
## fall back on (UNASSIGNED is the zero-default now, and a bout can't
## actually be running with one of those left on the board at all,
## `BoutRunner._init()`'s own hard error). Every real entry point assigns
## explicitly (`CombatState.assign_all_to_human()`/`assign_rest_to_ai()`),
## so this reads exactly what was assigned, nothing implied.
func wants_turn_for(unit: Unit) -> bool:
	return battle.combat_state.controller_for(unit.squad_id) == Enums.SquadController.HUMAN


## Re-wires against whichever CombatState/MissionState is now current —
## fired once from setup() and again every time `battle.load_battle()`
## reruns under an ALREADY-active SquadControlOverlay (the New Battle
## button, which never swaps overlays, only rebuilds the world).
func _on_battle_loaded() -> void:
	tactics.setup(battle.combat_state, battle.board_view, battle.camera_rig, battle.mission)
	# The PREVIOUS combat_state (if any) has already been replaced on
	# `battle.combat_state` by the time this fires (load_battle() swaps it
	# before emitting) — its own now-orphaned CombatLog simply stops being
	# written to; nothing left to explicitly detach from. remove_sink() is a
	# documented no-op on a sink that was never added, so this is safe on
	# the very first call too (right after _build_ui() just created it).
	battle.combat_state.combat_log.remove_sink(log_sink)
	# taskblock-22 Pass F: "unit N down" in a folded attack summary is
	# derived from the live CombatState (LogFold.state), never a new
	# LogEvent kind — re-pointed here alongside every other panel's own
	# re-wire, same reason: the PREVIOUS CombatState this sink's fold was
	# reading is about to go stale.
	log_sink.fold.state = battle.combat_state
	battle.combat_state.combat_log.add_sink(log_sink)
	if controls_overlay != null:
		controls_overlay.set_log_path(battle.file_sink.path)
	advance_ai_turns(battle)


func _build_ui() -> void:
	tactics = TacticsController.new()
	add_child(tactics)
	tactics.turn_ended.connect(_on_turn_ended)
	# docs/10 taskblock06 G1: "Resolve to Here" mutates authoritative state
	# exactly like End Turn does (resolve_until against the real
	# CombatState) — the same view resync (unit meshes + resolution replay)
	# applies either way, and neither one deselects/clears overlays here
	# (end_turn() and resolve_to_marker() each already own that decision).
	tactics.queue_partially_resolved.connect(_on_turn_ended)
	tactics.selection_changed.connect(_on_selection_changed)
	# runNotes.md: entering/cancelling aim must refresh the previewed facing
	# too (aim_facing() depends on `aiming_at`, not on anything
	# selection_changed already covers) — aim_changed is what actually
	# fires the instant that happens.
	tactics.aim_changed.connect(_on_selection_changed)
	tactics.highlight_changed.connect(_on_highlight_changed)

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
	# actual width comes from its own content's combined minimum size
	# below (taskblock-22 Pass I: the weapon_label row, now that the
	# inventory tree that used to sit beside it is gone), not half the
	# screen. mouse_filter = IGNORE is load-bearing:
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

	# taskblock-22 Pass I: the old always-visible inventory tree (nested
	# tree + mass/RAM footer, docs/10 taskblock03 H) lived here, right next
	# to the weapons list. InspectPanel (taskblock-21 Pass A) now supersedes
	# it everywhere, including a docs/05 mass/RAM footer of its own — see
	# InspectPanel._build_inventory_footer/_footer_text — so it's gone,
	# not just superseded-but-left-running-alongside. The weapons list
	# (weapon_label/WeaponPanel) is a separate feature the taskblock never
	# named for retirement; it keeps its own row, on its own now that the
	# tree it used to sit beside is gone.
	var inventory_row := HBoxContainer.new()
	inventory_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_layout.add_child(inventory_row)

	# docs/09 taskblock07 Pass B4: RichTextLabel's own mouse_filter DEFAULTS
	# to STOP (not IGNORE — that's plain Label's default, not this class's),
	# since it natively supports scrolling/text selection. A purely
	# read-only label with no such feature swallowing clicks over its own
	# rect is exactly the "class of bug" this pass audits for — every
	# RichTextLabel below that isn't the log (log_label keeps STOP: it has
	# a real, wanted scrollbar) gets IGNORE explicitly, same as the
	# containers around it already do.
	var weapon_label := RichTextLabel.new()
	weapon_label.bbcode_enabled = true
	weapon_label.custom_minimum_size = Vector2(260, 0)
	weapon_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	weapon_label.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_row.add_child(weapon_label)

	# taskblock-22 Pass I: the ONE inventory surface in player view now —
	# no more "additive alongside the always-visible tree" (A8's own old
	# framing); opened on demand for whatever's currently selected.
	inspect_button = Button.new()
	inspect_button.text = "Inspect"
	inspect_button.pressed.connect(_on_inspect_pressed)
	left_layout.add_child(inspect_button)

	# taskblock-22 Pass E3: the action-bar task's own entry point — a
	# button rather than a catalog-armed action (see the field's own doc
	# comment above for why).
	repair_button = Button.new()
	repair_button.text = "Repair"
	repair_button.pressed.connect(_on_repair_pressed)
	left_layout.add_child(repair_button)

	# taskblock-30/31 Pass C: `SquadControlOverlay`'s own debug-gated
	# DebugControlPanel — the button that toggles it moved into the shared
	# `TopLeftControls` cluster (tb31 Pass A); the panel itself stays a
	# direct `theme_root` child (a floating, self-centering modal, never
	# nested inside the top-left row it's opened from).
	if OS.is_debug_build():
		debug_panel = DebugControlPanel.new()
		debug_panel.visible = false
		debug_panel.applied.connect(_on_debug_panel_applied)
		theme_root.add_child(debug_panel)

	# tb31 Pass A: the shared Inject/New Battle/Watch cluster — one
	# construction path (`TopLeftControls`), not a per-overlay copy. Added
	# directly to `theme_root` (not nested under `left_layout`) so it sits
	# at the fixed top-left corner regardless of the inventory column's own
	# height.
	top_left_controls = TopLeftControls.new()
	# No pre-existing top-left row here (unlike SpectatorOverlay's own
	# `controls`) — anchor it directly, the same top-left corner
	# `DebugControlPanel`'s own `_center_top` fix already steers clear of.
	top_left_controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_left_controls.position = Vector2(16, 16)
	theme_root.add_child(top_left_controls)
	top_left_controls.setup(battle, _on_inject_pressed, true, "Watch")
	new_battle_button = top_left_controls.new_battle_button
	watch_button = top_left_controls.watch_button
	inject_button = top_left_controls.inject_button

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
	log_sink = HierarchicalUiSink.new(log_label)

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
	# taskblock-08 E3: "New Battle is a debug tool — split it out... place it
	# above the controls list." One top-right-anchored column: the debug
	# button first, the H-help legend directly under it.
	var top_right := VBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_half.add_child(top_right)

	# tb31 Pass A: the keybindings display defaults off now (reference, not
	# chrome) — this button is its second surface, alongside the existing
	# H-key toggle (`ControlsOverlay._unhandled_input`), both flipping the
	# same `label.visible`.
	keybindings_button = Button.new()
	keybindings_button.text = "Keybindings"
	keybindings_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	keybindings_button.pressed.connect(_on_keybindings_pressed)
	top_right.add_child(keybindings_button)

	var controls_label := Label.new()
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.add_child(controls_label)

	# runNotes.md: "put the turn controls in the bottom right, stacked,
	# with... [the readout cluster] above the turn controls." One
	# bottom-right-anchored stack: the readout+queue panel, then the
	# action bar/turn buttons row, in that order, growing upward from the
	# corner.
	var bottom_right := VBoxContainer.new()
	bottom_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_right.alignment = BoxContainer.ALIGNMENT_END
	bottom_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_half.add_child(bottom_right)

	# The combat readout (header/banner/aim/stat readouts) and the queued-
	# actions list get their own boxed panel, sized to its own content —
	# SHRINK_END keeps it from being stretched to the action bar's own
	# (much wider) row below, which shared this same VBoxContainer used to
	# force it to match, and right-aligns it within the column instead of
	# spanning it.
	var readout_panel := PanelContainer.new()
	readout_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	readout_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_right.add_child(readout_panel)
	var readout_column := VBoxContainer.new()
	readout_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout_panel.add_child(readout_column)

	# runNotes.md: "I'm not entirely sure what the info... is. Highlight
	# what it's doing, and IF it's doing it." A plain, named header —
	# _update_readout_header() below flips its color/text with whether the
	# cluster underneath actually has anything live to show.
	_readout_header = Label.new()
	_readout_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout_column.add_child(_readout_header)

	var banner := Label.new()
	banner.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout_column.add_child(banner)

	var aim_readout := RichTextLabel.new()
	aim_readout.bbcode_enabled = false
	aim_readout.custom_minimum_size = Vector2(320, 60)
	aim_readout.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	aim_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout_column.add_child(aim_readout)

	var stat_label := RichTextLabel.new()
	stat_label.custom_minimum_size = Vector2(320, 40)
	stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout_column.add_child(stat_label)
	var stat_drill_down := RichTextLabel.new()
	stat_drill_down.custom_minimum_size = Vector2(320, 60)
	stat_drill_down.add_theme_color_override("default_color", HulkTheme.DIM)
	stat_drill_down.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout_column.add_child(stat_drill_down)

	# docs/10 taskblock06 G2: "an in-turn, ordered list of the selected
	# unit's queued actions" — click a row to set the stop marker, then
	# "Resolve to Here" resolves the queue's prefix through it for real.
	# taskblock-08 E1: the button itself now lives in the turn-control
	# column below, alongside End Turn/Reset Turn — only the tree (a
	# readout, not a turn control) stays up here with the rest of the
	# readout cluster.
	var queue_tree := Tree.new()
	queue_tree.custom_minimum_size = Vector2(320, 100)
	readout_column.add_child(queue_tree)

	# taskblock-08 E1: "action bar on the LEFT... the turn-control stack
	# sits to its RIGHT" — one row, two columns, replacing the single
	# vertical stack pips/action-bar/buttons used to share.
	var action_and_turn_row := HBoxContainer.new()
	action_and_turn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_right.add_child(action_and_turn_row)

	action_column = VBoxContainer.new()
	action_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_and_turn_row.add_child(action_column)

	# taskblock-07 Pass G: "above the action bar: pips, not numbers." A
	# label prefix on each row (docs/08: terminal UI is text-first) is what
	# keeps a 0-pip row legible as "AP" / "MP" rather than reading as blank
	# space — "a unit with 0 shows an empty row, not a missing one."
	var pip_rows := VBoxContainer.new()
	pip_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_column.add_child(pip_rows)

	var ap_row := HBoxContainer.new()
	ap_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip_rows.add_child(ap_row)
	var ap_label := Label.new()
	ap_label.text = "AP"
	ap_label.custom_minimum_size = Vector2(28, 0)
	ap_label.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT)
	ap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ap_row.add_child(ap_label)
	var ap_pip_container := HBoxContainer.new()
	ap_row.add_child(ap_pip_container)

	var mp_row := HBoxContainer.new()
	mp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip_rows.add_child(mp_row)
	var mp_label := Label.new()
	mp_label.text = "MP"
	mp_label.custom_minimum_size = Vector2(28, 0)
	mp_label.add_theme_color_override("font_color", HulkTheme.MP_PIP)
	mp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_row.add_child(mp_label)
	var mp_pip_container := HBoxContainer.new()
	mp_row.add_child(mp_pip_container)

	# taskblock-08 E1: "action bar 3x its current size" — ActionBar.BOX_SIZE
	# itself carries the actual number; this row just sits directly under
	# the pips, both inside `action_column`.
	var action_row := HBoxContainer.new()
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_column.add_child(action_row)

	# taskblock-08 E1/E2: the turn-control stack proper — Resolve to Here /
	# End Turn / Reset Turn, sized to their own text (E2), nothing else in
	# this column to stretch them wider.
	turn_controls_column = VBoxContainer.new()
	turn_controls_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_controls_column.alignment = BoxContainer.ALIGNMENT_END
	turn_controls_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_and_turn_row.add_child(turn_controls_column)

	var resolve_to_here_button := Button.new()
	resolve_to_here_button.text = "Resolve to Here"
	resolve_to_here_button.disabled = true
	resolve_to_here_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	turn_controls_column.add_child(resolve_to_here_button)
	var end_turn_button := Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	turn_controls_column.add_child(end_turn_button)
	# docs/10 taskblock03 D4: "a single Reset Turn control (button + R)."
	var reset_turn_button := Button.new()
	reset_turn_button.text = "Reset Turn"
	reset_turn_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset_turn_button.pressed.connect(_on_reset_turn_pressed)
	turn_controls_column.add_child(reset_turn_button)

	aim_view = AimView.new()
	add_child(aim_view)
	aim_view.setup(tactics, aim_readout)

	resolution_player = ResolutionPlayer.new()
	add_child(resolution_player)
	resolution_player.setup(battle, tactics.unlock_input, banner)

	stat_panel = StatPanel.new()
	add_child(stat_panel)
	stat_panel.setup(tactics, stat_label, stat_drill_down)

	# taskblock-07 Pass F1/F2: THE one tooltip renderer — created before
	# every panel below so each can be handed the same instance, but only
	# added to the tree (theme_root's LAST child, so it draws above every
	# other panel) once they're all wired.
	tooltip_view = TooltipView.new()

	# DataLibrary.material_table() directly, not battle.combat_state's own —
	# _build_ui() must not depend on a battle already being loaded (see
	# setup()'s own doc comment), and material_table's content is the same
	# shared game data regardless of which CombatState instance holds it
	# (today's pre-overlay code already only ever wired this ONCE, in
	# _ready(), never refreshing it on a later New Battle either).
	var material_table: MaterialTable = DataLibrary.material_table()

	weapon_panel = WeaponPanel.new()
	add_child(weapon_panel)
	weapon_panel.setup(tactics, weapon_label)

	# taskblock-07 Pass F2: replaces combat_readout_panel.gd — "hovering a
	# tile or an enemy now produces a tooltip instead of filling a panel."
	tooltip_controller = TooltipController.new()
	add_child(tooltip_controller)
	tooltip_controller.setup(tactics, tooltip_view, material_table)

	queue_panel = QueuePanel.new()
	add_child(queue_panel)
	queue_panel.setup(tactics, queue_tree, resolve_to_here_button, tooltip_view)

	action_bar = ActionBar.new()
	add_child(action_bar)
	action_bar.setup(tactics, action_row, tooltip_view)

	ap_mp_pip_row = ApMpPipRow.new()
	add_child(ap_mp_pip_row)
	ap_mp_pip_row.setup(tactics, ap_pip_container, mp_pip_container, tooltip_view)

	inspect_panel = InspectPanel.new()
	# taskblock-22 Pass G1: 900x600 is the PREFERRED size — InspectPanel's
	# own _clamp_to_viewport shrinks/re-centers it against the real
	# viewport (no anchors preset needed/wanted here anymore; a one-shot
	# PRESET_CENTER never revisited was the "falls off the bottom" bug).
	inspect_panel.custom_minimum_size = Vector2(900, 600)
	# docs/02: `Camera3D.look_at()` (inside `setup()`'s own bot-viewer build)
	# needs a live tree to resolve a Node3D's global transform against — add
	# to the tree FIRST, setup() second, the same order the Resource
	# Editor's own preview relies on (there, `_ready()` firing at all is
	# what already guarantees it; here it has to be explicit).
	theme_root.add_child(inspect_panel)
	# taskblock-22 Pass G2: the isolate camera's own live-view lookup —
	# battle is a real BattleScene by this point (its own unit_views may
	# still be empty pre-battle-load; find_unit_view degrades to null
	# gracefully, same as every other optional thread-through here).
	inspect_panel.setup(material_table, tactics.selection, battle.find_unit_view, tactics)

	controls_overlay = ControlsOverlay.new()
	add_child(controls_overlay)
	# "" placeholder: _build_ui() must not depend on a battle already being
	# loaded — _on_battle_loaded() immediately corrects this via
	# set_log_path() the instant a real battle (and its file_sink) exists.
	controls_overlay.setup(controls_label, "")

	theme_root.add_child(tooltip_view)

	_update_readout_header()


func _on_end_turn_pressed() -> void:
	tactics.end_turn()


func _on_reset_turn_pressed() -> void:
	tactics.reset_turn()


func _on_keybindings_pressed() -> void:
	controls_overlay.label.visible = not controls_overlay.label.visible


## Resolution has already mutated combat_state for real (docs/09) — every
## HitVolumeView rebuilds from the unit it already tracks, so a destroyed
## part disappears and a moved unit redraws at its new cell. `events` is
## then handed to ResolutionPlayer purely as a cosmetic replay (docs/10
## Phase 12.4) — it never re-drives the sim, which has already finished.
##
## taskblock-15 Pass A: once the human's own turn has actually resolved,
## any squad flagged AI auto-advances through the same shared
## `advance_ai_turns` every overlay shares — a genuinely new capability
## (no `CombatState.controller_for` value outside a bout was ever consumed
## before this taskblock), inert (a single no-op check) for every existing
## battle, which never sets a squad to AI.
## taskblock-26 Pass B1: "the opposing team appeared to jump to new
## positions before that unit's attack animation resolved." `advance_ai_
## turns` fast-forwards every AI turn with NO animation at all (a single
## instant `refresh_unit_views` at its own end, by design — see its own
## doc comment) — calling it BEFORE this turn's own `resolution_player.
## play()` had even started meant the AI squad visibly snapped to its new
## positions while the human's own attack tracer hadn't fired yet. Now
## AWAITED first, so the human's own turn finishes its full animated
## playback before the AI batch is even resolved, let alone shown.
func _on_turn_ended(events: Array[LogEvent]) -> void:
	# taskblock-19 Pass I2: only the units THIS turn's own events actually
	# named, not the whole board — advance_ai_turns() already does its
	# own refresh at ITS OWN end (covering whatever it resolves), so a
	# third, unconditional full-board refresh right after it used to be
	# pure duplicate work, not a second, more-correct pass.
	battle.refresh_unit_views(LogPlayback.affected_unit_ids(events))
	_on_selection_changed()
	await resolution_player.play(events)
	advance_ai_turns(battle)


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
## taskblock-21 Pass A: opens the inspect panel on whatever's currently
## selected — a no-op with nothing selected, the same guard every other
## selection-dependent action here already uses.
func _on_inspect_pressed() -> void:
	var selected: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	if selected != null:
		inspect_panel.open(selected)


## taskblock-22 Pass E3: "prompts with all repairable damaged parts, each
## with its own scrap cost." A no-op with nothing selected or nothing
## damaged — same degenerate-case posture `_on_inspect_pressed` above
## already has, never an empty popup.
func _on_repair_pressed() -> void:
	var selected: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	if selected == null:
		return
	var damaged: Array[Part] = RepairResolver.repairable_parts(selected)
	if damaged.is_empty():
		return

	if _repair_menu != null:
		_repair_menu.queue_free()
	_repair_menu = PopupMenu.new()
	add_child(_repair_menu)
	var welder: Part = RepairResolver.find_operable_welder(selected)
	var mission: MissionState = tactics.selection.mission
	for i in range(damaged.size()):
		var part: Part = damaged[i]
		var cost: int = RepairResolver.scrap_cost_for(part)
		var scrap_id: StringName = RepairResolver.scrap_resource_id_for(part)
		var available: int = (
			int(mission.gathered_resources.get(scrap_id, 0)) if mission != null else 0
		)
		_repair_menu.add_item("%s (%d %s)" % [part.id, cost, scrap_id], i)
		if welder == null or available < cost:
			_repair_menu.set_item_disabled(_repair_menu.get_item_index(i), true)
	_repair_menu.id_pressed.connect(_on_repair_menu_id_pressed.bind(damaged, welder))
	_repair_menu.close_requested.connect(_repair_menu.queue_free)
	_repair_menu.id_pressed.connect(_repair_menu.queue_free, CONNECT_DEFERRED)
	_repair_menu.popup(Rect2i(Vector2i(repair_button.get_screen_position()), Vector2i.ZERO))


func _on_repair_menu_id_pressed(id: int, damaged: Array[Part], welder: Part) -> void:
	if welder == null or id < 0 or id >= damaged.size():
		return
	tactics.selection.queue_repair(welder.id, damaged[id].id)


## taskblock-30/31 Pass C: toggles the full debug control panel — `debug_
## panel` is null whenever this isn't a debug build (never constructed at
## all in `_build_ui()`), so this is a silent no-op there too, same
## posture the button's own absence already gives it. `battle.bout_
## injector` is read lazily, here, never cached at `_build_ui()` time
## (which runs before any battle is loaded).
func _on_inject_pressed() -> void:
	if debug_panel == null:
		return
	if debug_panel.visible:
		debug_panel.visible = false
		return
	debug_panel.setup(battle.bout_injector, DeepStrike.reference_humanoid_pool(), tactics)
	debug_panel.visible = true


## Refreshes the same way a debug HP/state mutation elsewhere in this
## codebase already does (InspectPanel's own debug menu calls its own
## view refresh) — a forced HP-to-0 can kill a part the header/views need
## to know about.
## taskblock-30 follow-up (supervisor): `remove_object` on a unit is the
## one verb that needs to REMOVE a view rather than add/refresh one — done
## here, before `sync_unit_views()` runs, so the same call never
## resurrects what it was just told to vanish (`sync_unit_views()`'s own
## `_removed_unit_ids` check is what makes that permanent afterward too).
func _on_debug_panel_applied(verb_id: StringName, args: Dictionary) -> void:
	if verb_id == &"remove_object":
		var object: Dictionary = args.get("object", {})
		if object.get("kind") == Enums.HitKind.UNIT and object.get("unit") != null:
			battle.remove_unit_view(object.unit)
	battle.sync_unit_views()
	battle.sync_board_view()
	battle.refresh_unit_views()
	_update_readout_header()


func _on_selection_changed() -> void:
	var selected: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	# tb31 Pass C: "walls must not block the player's read of the action
	# behind them" — the selected unit is the one thing worth protecting
	# from a wall's own legibility fade; `BoardView.focal_unit` re-reads
	# this every frame against the live camera (drag-to-orbit has no
	# signal of its own), not just at the instant selection changes.
	battle.board_view.focal_unit = selected
	for view: HitVolumeView in battle.unit_views:
		view.set_selected(view.unit == selected)
		var target_preview: Variant = null
		if view.unit == selected and not tactics.has_queued_move():
			var facing: Variant = tactics.aim_facing()
			target_preview = facing if facing != null else tactics.selection.previewed_orientation()
		if view.preview_orientation != target_preview:
			view.preview_orientation = target_preview
			view.refresh()
	_update_readout_header()


## docs/10 taskblock05 C: bidirectional hover highlight — only the selected
## unit's own view can ever have a matching part (that's the only body the
## inventory tree, the other trigger for this signal, has rows for at all).
func _on_highlight_changed() -> void:
	var selected: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	for view: HitVolumeView in battle.unit_views:
		if view.unit == selected:
			view.highlight_part(tactics.highlighted_part)
		else:
			view.clear_highlight()


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
