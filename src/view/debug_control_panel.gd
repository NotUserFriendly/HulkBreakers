class_name DebugControlPanel
extends PanelContainer

## taskblock-30/31 Pass C: turns `BoutInjector`'s verbs into a real
## click-to-force surface, live, in a running bout — the actual
## deliverable the supervisor presses. Built entirely from
## `DebugVerbs.all()` (data-driven: a new verb is a new table row, never
## new UI code here). **Programmatic parity**: every Apply press is
## exactly one `BoutInjector` call with the args this panel resolved —
## there is no logic in this file that isn't a verb call (CLAUDE.md "no
## parallel systems": the panel is a pure wrapper).
##
## `input_owner` is whichever object exposes the generic
## `board_clicked`/`input_capture_mode` hook (`TacticsController` for a
## player bout, the `SpectatorOverlay` itself for spectator) — duck-typed
## on purpose, this file never imports either concretely, so "Pick on
## Board" works identically against both.
##
## taskblock-30 follow-up (supervisor): "keep an active thing in memory."
## While the panel is visible, EVERY board click (not just a field's own
## "Pick" press) updates `_active` — the same hit-shaped `{kind, unit,
## cell}` dict `board_clicked` itself emits — and the label above the
## right-hand column shows it. `input_capture_mode` is armed/disarmed
## against the panel's OWN `visible` state (`visibility_changed`), not
## per-pick, so a field's one-shot `_start_picking` connection and the
## always-on active-target tracker both fire off the same click.

signal closed
## Fires after a successful Apply — `verb_id` + the resolved args, so a
## caller (an overlay) can refresh its own views without this panel
## needing to know anything about view-refresh itself.
signal applied(verb_id: StringName, args: Dictionary)

## Supervisor report: with no anchor at all the panel defaulted to the
## top-left corner and sat directly on top of the existing top-left HUD
## (`controls`/`tunables` in both overlays). Horizontally centered,
## pinned to a fixed top margin instead — same reasoning as InspectPanel's
## own `_clamp_to_viewport`: it stays out of the way of everything else,
## and a fixed screen anchor (not "wherever the mouse happened to be")
## means it's always found in the same place.
const TOP_MARGIN := 16.0

var bout_injector: BoutInjector
var pool: Dictionary
var input_owner: Object
var combat_state: CombatState

var _verb_list: ItemList
var _param_container: VBoxContainer
var _active_label: Label
var _status_label: Label
var _verbs: Array[DebugVerbSpec] = []
## param name (StringName) -> a single Control, or (CELL only) an
## `Array[SpinBox]` of the two X/Y fields. An OBJECT param has no entry
## here — it always resolves from `_active`, never a widget of its own.
var _param_controls: Dictionary = {}
## The last thing a board click hit while this panel was visible — a
## hit-shaped `{kind, unit, cell}` dict, `{}` before the first click.
## Persists across verb switches; several verbs can read the same target.
var _active: Dictionary = {}
var _picking: bool = false


## docs/09 taskblock07 Pass B4's own rule: a plain container has no click
## of its own — IGNORE, same as InspectPanel's own root, so empty panel
## padding never swallows a click intended for the board underneath.
## Set here, in `_init`, not `_build_ui()` — both overlays construct this
## panel eagerly (`DebugControlPanel.new()`) well before `setup()` ever
## runs (deferred until the operator actually presses Inject), so the
## fix has to land the instant the object exists, not lazily.
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Re-centers on every viewport resize (setup()'s own call handles the
## first layout), and arms/disarms the active-target tracker against this
## panel's OWN visibility — covers every way `visible` ever flips (both
## overlays' `debug_panel.visible = true/false` toggle AND this panel's
## own `_on_close_pressed`) from one place, with no per-call-site wiring.
func _ready() -> void:
	get_viewport().size_changed.connect(_center_top)
	visibility_changed.connect(_on_visibility_changed)


func _center_top() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	position = Vector2((viewport_size.x - size.x) / 2.0, TOP_MARGIN)


func _on_visibility_changed() -> void:
	if visible:
		_arm_active_tracking()
	else:
		_disarm_active_tracking()


func setup(p_bout_injector: BoutInjector, p_pool: Dictionary, p_input_owner: Object) -> void:
	bout_injector = p_bout_injector
	pool = p_pool
	input_owner = p_input_owner
	combat_state = bout_injector.state
	if _verb_list == null:
		_verbs = DebugVerbs.all()
		_build_ui()
	_select_verb(0)
	if visible:
		_arm_active_tracking()
	# Layout (which verb's params are showing) only settles after this
	# frame's own deferred calls run — center against the REAL post-layout
	# width, not a guess at what it's about to become.
	call_deferred(&"_center_top")


func _build_ui() -> void:
	custom_minimum_size = Vector2(520, 0)
	# docs/09 taskblock07 Pass B4's own rule: a plain container has no click
	# of its own — IGNORE, same as InspectPanel's own root, so empty panel
	# padding never swallows a click intended for the board underneath.
	# Every genuinely interactive child (Button/SpinBox/ItemList/...) keeps
	# its own native STOP; this is only the container shell.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root := VBoxContainer.new()
	add_child(root)

	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title := Label.new()
	title.text = "[*] Debug Control Panel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.pressed.connect(_on_close_pressed)
	title_row.add_child(close_button)

	var body := HBoxContainer.new()
	root.add_child(body)

	# Left: the verb picker, a scrolling list — `ItemList` has its own
	# native scrollbar once content overflows, no wrapping ScrollContainer
	# needed. `item_selected(index)`/`select(index)` are drop-in
	# replacements for the OptionButton this used to be.
	_verb_list = ItemList.new()
	_verb_list.custom_minimum_size = Vector2(150, 240)
	for verb: DebugVerbSpec in _verbs:
		_verb_list.add_item(verb.label)
	_verb_list.item_selected.connect(_select_verb)
	body.add_child(_verb_list)

	# Right: the "control panel" — whatever the selected verb needs. The
	# active-target label sits above it, not above the verb list on the
	# left — it describes the OBJECT a verb acts on, independent of which
	# verb is currently picked.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	_active_label = Label.new()
	right.add_child(_active_label)

	_param_container = VBoxContainer.new()
	right.add_child(_param_container)

	var apply_button := Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(_on_apply_pressed)
	right.add_child(apply_button)

	_status_label = Label.new()
	right.add_child(_status_label)

	_refresh_active_label()


func _on_close_pressed() -> void:
	visible = false
	closed.emit()


## `input_owner`'s own `board_clicked`/`input_capture_mode` — armed for as
## long as this panel is visible (see `_on_visibility_changed`), so any
## board click updates `_active`, not just a field's own one-shot "Pick".
func _arm_active_tracking() -> void:
	if input_owner == null:
		return
	input_owner.set("input_capture_mode", true)
	var sig := input_owner.get("board_clicked") as Signal
	if not sig.is_connected(_on_active_target_clicked):
		sig.connect(_on_active_target_clicked)


func _disarm_active_tracking() -> void:
	if input_owner == null:
		return
	var sig := input_owner.get("board_clicked") as Signal
	if sig.is_connected(_on_active_target_clicked):
		sig.disconnect(_on_active_target_clicked)
	input_owner.set("input_capture_mode", false)


## A miss (off the board entirely, an empty hit dict) leaves `_active`
## alone — "click a tile, it's in memory" means it STAYS in memory until
## the next real hit, not that a stray click into the void wipes it.
func _on_active_target_clicked(hit: Dictionary) -> void:
	if hit.is_empty():
		return
	_active = hit
	_refresh_active_label()


func _refresh_active_label() -> void:
	if _active_label == null:
		return
	if _active.is_empty():
		_active_label.text = "Active: none"
		return
	if _active.get("kind") == Enums.HitKind.UNIT and _active.get("unit") != null:
		var unit: Unit = _active.get("unit")
		_active_label.text = "Active: Unit #%d @ %s" % [unit.id, unit.cell]
	else:
		_active_label.text = "Active: Cell %s" % [_active.get("cell")]


func _select_verb(index: int) -> void:
	for child: Node in _param_container.get_children():
		_param_container.remove_child(child)
		child.queue_free()
	_param_controls.clear()
	_status_label.text = ""
	if index < 0 or index >= _verbs.size():
		return
	_verb_list.select(index)
	var verb: DebugVerbSpec = _verbs[index]
	for p: Dictionary in verb.params:
		_param_container.add_child(_build_param_row(p))
	# taskblock-30 follow-up: move_object's own accelerated path — "move to
	# next tile clicked" applies the move on the very next board click, no
	# separate Apply press. Verb-specific (not a generic ParamType widget)
	# because it side-effects immediately, unlike every other field, which
	# only ever fills in a value for Apply to use later.
	if verb.id == &"move_object":
		var move_on_click := Button.new()
		move_on_click.text = "Move On Next Click"
		move_on_click.pressed.connect(_begin_move_on_next_click)
		_param_container.add_child(move_on_click)


func _build_param_row(p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var field_label := Label.new()
	field_label.text = "%s:" % p.name
	field_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(field_label)

	match p.type:
		DebugVerbSpec.ParamType.UNIT:
			var spin: SpinBox = _int_spin()
			row.add_child(spin)
			var pick := Button.new()
			pick.text = "Pick"
			pick.pressed.connect(_begin_pick_unit.bind(spin))
			row.add_child(pick)
			_param_controls[p.name] = spin
		DebugVerbSpec.ParamType.CELL:
			var spin_x: SpinBox = _int_spin()
			var spin_y: SpinBox = _int_spin()
			row.add_child(spin_x)
			row.add_child(spin_y)
			var pick := Button.new()
			pick.text = "Pick"
			pick.pressed.connect(_begin_pick_cell.bind(spin_x, spin_y))
			row.add_child(pick)
			_param_controls[p.name] = [spin_x, spin_y]
		DebugVerbSpec.ParamType.INT:
			var spin: SpinBox = _int_spin()
			row.add_child(spin)
			_param_controls[p.name] = spin
		DebugVerbSpec.ParamType.FLOAT:
			var spin := SpinBox.new()
			spin.min_value = -99999.0
			spin.max_value = 99999.0
			spin.step = 0.01
			row.add_child(spin)
			_param_controls[p.name] = spin
		DebugVerbSpec.ParamType.BOOL:
			var check := CheckBox.new()
			row.add_child(check)
			_param_controls[p.name] = check
		DebugVerbSpec.ParamType.STRING_NAME:
			var edit := LineEdit.new()
			edit.custom_minimum_size = Vector2(160, 0)
			row.add_child(edit)
			_param_controls[p.name] = edit
		DebugVerbSpec.ParamType.POSE:
			var opt := OptionButton.new()
			for pose_id: StringName in Poses.all_ids():
				opt.add_item(pose_id)
			row.add_child(opt)
			_param_controls[p.name] = opt
		DebugVerbSpec.ParamType.PRESET:
			var opt := OptionButton.new()
			for preset: BotPreset in DataLibrary.presets_pool():
				opt.add_item(preset.preset_name)
			row.add_child(opt)
			_param_controls[p.name] = opt
		DebugVerbSpec.ParamType.OBJECT:
			var note := Label.new()
			note.text = "(uses Active Target above)"
			row.add_child(note)

	return row


func _int_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -999
	spin.max_value = 999
	spin.rounded = true
	return spin


func _begin_pick_unit(spin: SpinBox) -> void:
	_start_picking(
		func(hit: Dictionary) -> void:
			var unit: Variant = hit.get("unit")
			if unit != null:
				spin.value = (unit as Unit).id
	)


func _begin_pick_cell(spin_x: SpinBox, spin_y: SpinBox) -> void:
	_start_picking(
		func(hit: Dictionary) -> void:
			var cell: Variant = hit.get("cell")
			if cell != null:
				spin_x.value = (cell as Vector2i).x
				spin_y.value = (cell as Vector2i).y
	)


## The "move on next click" accelerated path for `move_object`: snapshots
## `_active` right now (the destination click below also updates `_active`
## itself, via the always-on tracker — snapshotting first means THAT click
## can't shift which object is moving out from under it), then applies the
## real `BoutInjector.move_object` call the instant a destination cell
## lands — no separate Apply press, unlike every other verb.
func _begin_move_on_next_click() -> void:
	if _active.is_empty():
		_status_label.text = "Move Object: no active target set"
		return
	var object_snapshot: Dictionary = _active.duplicate()
	_start_picking(
		func(hit: Dictionary) -> void:
			var cell: Variant = hit.get("cell")
			if cell == null:
				return
			var ok: bool = bout_injector.move_object(object_snapshot, cell)
			_status_label.text = "Move Object: %s" % ("applied" if ok else "refused")
			if ok:
				applied.emit(&"move_object", {"object": object_snapshot, "to_cell": cell})
	)


## `input_owner`'s own `board_clicked`/`input_capture_mode` — see this
## file's own header. A ONE-SHOT connection for a single field's own pick,
## alongside (not instead of) the always-on active-target tracker above —
## both fire off the same click. `input_capture_mode` itself is
## armed/disarmed against this panel's own visibility, not per-pick.
func _start_picking(on_pick: Callable) -> void:
	if input_owner == null or _picking:
		return
	_picking = true
	var conn: Callable
	conn = func(hit: Dictionary) -> void:
		_picking = false
		on_pick.call(hit)
	(input_owner.get("board_clicked") as Signal).connect(conn, CONNECT_ONE_SHOT)


func _resolve_param(p: Dictionary) -> Variant:
	var control: Variant = _param_controls.get(p.name)
	match p.type:
		DebugVerbSpec.ParamType.UNIT:
			return combat_state.find_unit(int((control as SpinBox).value))
		DebugVerbSpec.ParamType.CELL:
			var fields: Array = control
			return Vector2i(int((fields[0] as SpinBox).value), int((fields[1] as SpinBox).value))
		DebugVerbSpec.ParamType.INT:
			return int((control as SpinBox).value)
		DebugVerbSpec.ParamType.FLOAT:
			return (control as SpinBox).value
		DebugVerbSpec.ParamType.BOOL:
			return (control as CheckBox).button_pressed
		DebugVerbSpec.ParamType.STRING_NAME:
			return StringName((control as LineEdit).text)
		DebugVerbSpec.ParamType.POSE:
			var pose_option := control as OptionButton
			return (
				StringName(pose_option.get_item_text(pose_option.selected))
				if pose_option.selected >= 0
				else &""
			)
		DebugVerbSpec.ParamType.PRESET:
			var preset_option := control as OptionButton
			return (
				null
				if preset_option.selected < 0
				else DataLibrary.get_preset(
					StringName(preset_option.get_item_text(preset_option.selected))
				)
			)
		DebugVerbSpec.ParamType.OBJECT:
			return null if _active.is_empty() else _active.duplicate()
	return null


## The one place a verb actually runs — resolves every param, refuses
## (named, on the status label) if a required UNIT/PRESET/OBJECT
## reference can't be found, then makes exactly one call into `verb.apply`
## (a real `BoutInjector` verb) with the resolved args.
func _on_apply_pressed() -> void:
	var selected: PackedInt32Array = _verb_list.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	if index < 0 or index >= _verbs.size():
		return
	var verb: DebugVerbSpec = _verbs[index]
	var args: Dictionary = {}
	for p: Dictionary in verb.params:
		var value: Variant = _resolve_param(p)
		if (
			value == null
			and (
				p.type
				in [
					DebugVerbSpec.ParamType.UNIT,
					DebugVerbSpec.ParamType.PRESET,
					DebugVerbSpec.ParamType.OBJECT,
				]
			)
		):
			_status_label.text = "%s: no %s found" % [verb.label, p.name]
			return
		args[p.name] = value
	var ok: bool = verb.apply.call(bout_injector, pool, args)
	_status_label.text = "%s: %s" % [verb.label, "applied" if ok else "refused"]
	if ok:
		applied.emit(verb.id, args)
