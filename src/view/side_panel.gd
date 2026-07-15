class_name SidePanel
extends PanelContainer

## Selected unit's parts/HP/AP + a swap control, and a New Battle button.
## Built entirely in code — scenes stay minimal.

signal swap_requested(slot_type: Enums.SlotType, container: Part, new_part: Part)
signal new_battle_requested
signal mode_toggle_requested

var _title_label: Label
var _ap_label: Label
var _parts_container: VBoxContainer
var _mode_button: Button


func _init() -> void:
	custom_minimum_size = Vector2(240, 0)
	var vbox := VBoxContainer.new()
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "No unit selected"
	vbox.add_child(_title_label)

	_ap_label = Label.new()
	vbox.add_child(_ap_label)

	vbox.add_child(HSeparator.new())

	_parts_container = VBoxContainer.new()
	vbox.add_child(_parts_container)

	vbox.add_child(HSeparator.new())

	_mode_button = Button.new()
	_mode_button.pressed.connect(func() -> void: mode_toggle_requested.emit())
	vbox.add_child(_mode_button)
	set_mode_label("move")

	vbox.add_child(HSeparator.new())

	var new_battle_button := Button.new()
	new_battle_button.text = "New Battle"
	new_battle_button.pressed.connect(func() -> void: new_battle_requested.emit())
	vbox.add_child(new_battle_button)


func set_mode_label(mode: String) -> void:
	_mode_button.text = "Mode: %s (click to toggle)" % mode.capitalize()


func show_unit(unit: Unit) -> void:
	for child in _parts_container.get_children():
		child.queue_free()

	if unit == null:
		_title_label.text = "No unit selected"
		_ap_label.text = ""
		return

	var status: String = "" if unit.alive else "  [DESTROYED]"
	_title_label.text = "Unit %d (squad %d)%s" % [unit.id, unit.squad_id, status]
	_ap_label.text = "AP: %d / %d    MP: %.1f" % [unit.ap, unit.max_ap, unit.mp]

	for slot_type: Variant in unit.chassis.slots.keys():
		var part: Part = unit.chassis.slots[slot_type]
		var label := Label.new()
		var part_name: String = part.display_name if part.display_name != "" else String(part.id)
		label.text = (
			"%s: %s  hp %d/%d" % [Enums.SlotType.keys()[slot_type], part_name, part.hp, part.max_hp]
		)
		_parts_container.add_child(label)

	for part: Part in unit.chassis.slots.values():
		if not part.is_container:
			continue
		for spare: Part in part.contents:
			if spare.hp <= 0:
				continue
			var btn := Button.new()
			btn.text = (
				"Swap in %s (%s)" % [String(spare.id), Enums.SlotType.keys()[spare.slot_type]]
			)
			var container_ref: Part = part
			var spare_ref: Part = spare
			btn.pressed.connect(
				func() -> void: swap_requested.emit(spare_ref.slot_type, container_ref, spare_ref)
			)
			_parts_container.add_child(btn)
