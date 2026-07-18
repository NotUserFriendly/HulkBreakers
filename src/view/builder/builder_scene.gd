class_name BuilderScene
extends Node3D

## docs/10 taskblock05 G: a debug scene to assemble, modify, save and load
## bots — a UI over BuilderController and nothing more. "The builder is
## the best test the assembler will ever get": every assembly goes through
## the exact same BodyAssembler call the game itself makes (BuilderController
## owns that; this Node only reads it and draws what it says).
##
## G6: "no cost/economy, no progression, no unlock rules, no drag-and-drop
## polish. It's a debug tool. It must be correct and honest, not pretty."

var controller: BuilderController = BuilderController.new()
var current_unit: Unit

var camera_rig: CameraRig
var preview: HitVolumeView
var socket_tree: Tree
var validation_label: RichTextLabel
var picker_list: ItemList
var picker_label: Label
var template_option: OptionButton
var pose_option: OptionButton
var preset_option: OptionButton
var preset_name_field: LineEdit

var _selected_host: Part
var _selected_socket: Socket


func _ready() -> void:
	add_child(WorldPalette.world_environment())
	add_child(WorldPalette.directional_light())

	camera_rig = CameraRig.new()
	add_child(camera_rig)

	preview = HitVolumeView.new()
	add_child(preview)

	var theme_root := Control.new()
	theme_root.theme = HulkTheme.build()
	theme_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	theme_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(theme_root)

	_build_top_bar(theme_root)
	_build_left_panel(theme_root)
	_build_right_panel(theme_root)

	_populate_template_option()
	_populate_pose_option()
	_refresh_preset_option()
	refresh()


func _build_top_bar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(bar)

	template_option = OptionButton.new()
	template_option.item_selected.connect(_on_template_selected)
	bar.add_child(template_option)

	pose_option = OptionButton.new()
	pose_option.item_selected.connect(_on_pose_selected)
	bar.add_child(pose_option)

	preset_option = OptionButton.new()
	bar.add_child(preset_option)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_pressed)
	bar.add_child(load_button)

	preset_name_field = LineEdit.new()
	preset_name_field.placeholder_text = "preset name"
	preset_name_field.custom_minimum_size = Vector2(160, 0)
	bar.add_child(preset_name_field)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	bar.add_child(save_button)

	var send_button := Button.new()
	send_button.text = "Send to Battle"
	send_button.pressed.connect(_on_send_to_battle_pressed)
	bar.add_child(send_button)


func _build_left_panel(root: Control) -> void:
	socket_tree = Tree.new()
	socket_tree.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	socket_tree.custom_minimum_size = Vector2(420, 0)
	socket_tree.hide_root = true
	socket_tree.columns = 1
	socket_tree.item_selected.connect(_on_socket_row_selected)
	root.add_child(socket_tree)


func _build_right_panel(root: Control) -> void:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.custom_minimum_size = Vector2(360, 0)
	root.add_child(panel)

	validation_label = RichTextLabel.new()
	validation_label.custom_minimum_size = Vector2(0, 200)
	validation_label.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	# docs/09 taskblock07 Pass B4: RichTextLabel defaults to STOP, not
	# IGNORE — a purely read-only label with no scroll/selection feature
	# swallowing clicks over its own rect is the exact bug class that pass
	# audits for.
	validation_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(validation_label)

	picker_label = Label.new()
	picker_label.text = "PART PICKER — click a socket"
	panel.add_child(picker_label)

	picker_list = ItemList.new()
	picker_list.custom_minimum_size = Vector2(0, 300)
	picker_list.item_selected.connect(_on_picker_item_selected)
	panel.add_child(picker_list)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(_on_remove_pressed)
	panel.add_child(remove_button)


func _populate_template_option() -> void:
	template_option.clear()
	for id: StringName in ShellTemplates.all_ids():
		template_option.add_item(String(id))
	template_option.select(0)


func _populate_pose_option() -> void:
	pose_option.clear()
	for id: StringName in Poses.all_ids():
		pose_option.add_item(String(id))
	pose_option.select(0)


func _refresh_preset_option() -> void:
	preset_option.clear()
	for preset_name: String in BotPreset.list_names():
		preset_option.add_item(preset_name)


## Rebuilds everything from `controller`'s current state — the one place
## a real assembly happens (BuilderController.assemble(), which is just
## BodyAssembler.assemble()) and everything else redraws from.
func refresh() -> void:
	current_unit = controller.assemble()
	preview.setup(current_unit, DataLibrary.material_table())
	_populate_tree()
	_refresh_validation()
	_refresh_picker()


func _populate_tree() -> void:
	socket_tree.clear()
	if current_unit == null or current_unit.shell.root == null:
		return
	var root_item: TreeItem = socket_tree.create_item()
	_add_part_row(current_unit.shell.root, root_item)


func _add_part_row(part: Part, parent_item: TreeItem) -> void:
	var item: TreeItem = socket_tree.create_item(parent_item)
	item.set_text(0, part.display_name if part.display_name != "" else String(part.id))
	# docs/10 taskblock05 G3: sockets (structural) and contents (inventory)
	# stay visually distinct (docs/01 taskblock03 H1) — the builder only
	# edits the socket tree, never a container's own contents.
	for socket: Socket in part.sockets:
		var socket_item: TreeItem = socket_tree.create_item(item)
		socket_item.set_metadata(0, {"host": part, "socket": socket})
		if socket.occupant != null:
			socket_item.set_text(0, "[%s]" % socket.id)
			_add_part_row(socket.occupant, socket_item)
		else:
			socket_item.set_text(0, "[%s] (empty)" % socket.id)
			socket_item.set_custom_color(0, HulkTheme.DIM)


func _refresh_validation() -> void:
	var report: Dictionary = controller.validate(current_unit)
	var lines: Array[String] = [
		"mass %.1f/%.1f" % [report.mass, report.max_mass],
		"ram %.1f/%.1f" % [report.ram, report.max_ram],
		"armed: %s" % report.armed,
	]
	var violations: Array = report.violations
	if not violations.is_empty():
		lines.append("")
		lines.append("VIOLATIONS")
		for violation: String in violations:
			lines.append("· %s" % violation)
	validation_label.text = "\n".join(lines)


func _refresh_picker() -> void:
	picker_list.clear()
	if _selected_socket == null or current_unit == null:
		picker_label.text = "PART PICKER — click a socket"
		return
	picker_label.text = "PART PICKER — socket %s" % _selected_socket.id
	var candidates: Dictionary = controller.candidates_for(current_unit.shell, _selected_socket)
	for part: Part in candidates.legal as Array:
		var idx: int = picker_list.add_item(String(part.id))
		picker_list.set_item_metadata(idx, part.id)
	for entry: Dictionary in candidates.illegal as Array:
		var part: Part = entry.part
		var idx: int = picker_list.add_item("%s — %s" % [part.id, entry.reason])
		picker_list.set_item_disabled(idx, true)
		picker_list.set_item_custom_fg_color(idx, HulkTheme.DIM)


func _on_socket_row_selected() -> void:
	var item: TreeItem = socket_tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		_selected_host = null
		_selected_socket = null
		return
	_selected_host = (meta as Dictionary).host
	_selected_socket = (meta as Dictionary).socket
	_refresh_picker()


func _on_picker_item_selected(index: int) -> void:
	if _selected_socket == null or picker_list.is_item_disabled(index):
		return
	var part_id: Variant = picker_list.get_item_metadata(index)
	if part_id == null:
		return
	controller.set_part(_selected_socket.id, part_id)
	refresh()


func _on_remove_pressed() -> void:
	if _selected_socket == null:
		return
	controller.clear_socket(_selected_socket.id)
	refresh()


func _on_template_selected(index: int) -> void:
	controller.template_id = StringName(template_option.get_item_text(index))
	refresh()


func _on_pose_selected(index: int) -> void:
	controller.pose_id = StringName(pose_option.get_item_text(index))
	refresh()


func _on_save_pressed() -> void:
	var preset_name: String = preset_name_field.text.strip_edges()
	if preset_name.is_empty():
		return
	BotPreset.save(controller.to_preset(preset_name))
	_refresh_preset_option()


func _on_load_pressed() -> void:
	var index: int = preset_option.selected
	if index < 0:
		return
	var preset: BotPreset = BotPreset.load_preset(preset_option.get_item_text(index))
	if preset == null:
		return
	controller.apply_preset(preset)
	refresh()


## docs/10 taskblock05 G5: "presets feed everything" — sending to battle is
## the same save a named preset already does; whatever picks up presets
## for a real squad setup reads the same user://presets/ files this
## writes; this scene has no live battle of its own to hand a Unit to
## directly.
func _on_send_to_battle_pressed() -> void:
	var preset_name: String = preset_name_field.text.strip_edges()
	if preset_name.is_empty():
		preset_name = "sent_to_battle"
	BotPreset.save(controller.to_preset(preset_name))
	_refresh_preset_option()


## docs/10 taskblock05 G5: "load a live unit into the builder to inspect
## or edit it" — the debug case that pays for the whole scene. Public so
## whoever launches the builder with a specific live unit in hand (a
## future battle-scene hook) can call it directly.
func load_unit(unit: Unit) -> void:
	controller.load_from_unit(unit)
	refresh()
