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

signal closed
## Fires after a successful Apply — `verb_id` + the resolved args, so a
## caller (an overlay) can refresh its own views without this panel
## needing to know anything about view-refresh itself.
signal applied(verb_id: StringName, args: Dictionary)

var bout_injector: BoutInjector
var pool: Dictionary
var input_owner: Object
var combat_state: CombatState

var _verb_option: OptionButton
var _param_container: VBoxContainer
var _status_label: Label
var _verbs: Array[DebugVerbSpec] = []
## param name (StringName) -> a single Control, or (CELL only) an
## `Array[SpinBox]` of the two X/Y fields.
var _param_controls: Dictionary = {}
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


func setup(p_bout_injector: BoutInjector, p_pool: Dictionary, p_input_owner: Object) -> void:
	bout_injector = p_bout_injector
	pool = p_pool
	input_owner = p_input_owner
	combat_state = bout_injector.state
	if _verb_option == null:
		_verbs = DebugVerbs.all()
		_build_ui()
	_select_verb(0)


func _build_ui() -> void:
	custom_minimum_size = Vector2(380, 0)
	# docs/09 taskblock07 Pass B4's own rule: a plain container has no click
	# of its own — IGNORE, same as InspectPanel's own root, so empty panel
	# padding never swallows a click intended for the board underneath.
	# Every genuinely interactive child (Button/SpinBox/OptionButton/...)
	# keeps its own native STOP; this is only the container shell.
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

	_verb_option = OptionButton.new()
	for verb: DebugVerbSpec in _verbs:
		_verb_option.add_item(verb.label)
	_verb_option.item_selected.connect(_select_verb)
	root.add_child(_verb_option)

	_param_container = VBoxContainer.new()
	root.add_child(_param_container)

	var apply_button := Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(_on_apply_pressed)
	root.add_child(apply_button)

	_status_label = Label.new()
	root.add_child(_status_label)


func _on_close_pressed() -> void:
	visible = false
	closed.emit()


func _select_verb(index: int) -> void:
	for child: Node in _param_container.get_children():
		_param_container.remove_child(child)
		child.queue_free()
	_param_controls.clear()
	_status_label.text = ""
	if index < 0 or index >= _verbs.size():
		return
	_verb_option.select(index)
	var verb: DebugVerbSpec = _verbs[index]
	for p: Dictionary in verb.params:
		_param_container.add_child(_build_param_row(p))


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


## `input_owner`'s own `board_clicked`/`input_capture_mode` — see this
## file's own header. A one-shot connection: the very next click resolves
## the pick and disconnects itself, never lingering armed after.
func _start_picking(on_pick: Callable) -> void:
	if input_owner == null or _picking:
		return
	_picking = true
	input_owner.set("input_capture_mode", true)
	var conn: Callable
	conn = func(hit: Dictionary) -> void:
		_picking = false
		input_owner.set("input_capture_mode", false)
		on_pick.call(hit)
	(input_owner.get("board_clicked") as Signal).connect(conn, CONNECT_ONE_SHOT)


func _resolve_param(p: Dictionary) -> Variant:
	var control: Variant = _param_controls[p.name]
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
			if preset_option.selected < 0:
				return null
			return DataLibrary.get_preset(
				StringName(preset_option.get_item_text(preset_option.selected))
			)
	return null


## The one place a verb actually runs — resolves every param, refuses
## (named, on the status label) if a required UNIT/PRESET reference can't
## be found, then makes exactly one call into `verb.apply` (a real
## `BoutInjector` verb) with the resolved args.
func _on_apply_pressed() -> void:
	var index: int = _verb_option.selected
	if index < 0 or index >= _verbs.size():
		return
	var verb: DebugVerbSpec = _verbs[index]
	var args: Dictionary = {}
	for p: Dictionary in verb.params:
		var value: Variant = _resolve_param(p)
		if (
			value == null
			and p.type in [DebugVerbSpec.ParamType.UNIT, DebugVerbSpec.ParamType.PRESET]
		):
			_status_label.text = "%s: no %s found" % [verb.label, p.name]
			return
		args[p.name] = value
	var ok: bool = verb.apply.call(bout_injector, pool, args)
	_status_label.text = "%s: %s" % [verb.label, "applied" if ok else "refused"]
	if ok:
		applied.emit(verb.id, args)
