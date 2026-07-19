class_name InspectPanel
extends PanelContainer

## taskblock-21 Pass A: "wounds, deflections, per-part damage, and nested
## internals (tb20) now exist and are untrackable. This panel is what makes
## them legible." A self-contained, modal-style component — `open(unit)`
## shows it populated for that unit, `close()` hides it and emits `closed`
## — so any host (SquadControlOverlay, SpectatorOverlay/Pass B) can wire it
## in without this file knowing which one it's hosted by. Reuses, never
## reinvents: `HitVolumeView.show_assembly` for the bot viewer (same
## SubViewportContainer/Camera3D/pivot scaffold the Resource Editor's own
## preview already established — that preview is baked directly into
## `ResourceEditorScene`, not a shared component, so this is a parallel
## build of the same PATTERN, not a shared call), `InspectRows`/`WeaponRows`
## for the inventory tree, `TooltipBuilder`/`TooltipData`/
## `TooltipView.to_bbcode` for the info panel's own rendering (docs/08: no
## number is born in the view).
##
## Scope fence (taskblock21 "Out"): no authored per-type info shapes (every
## hovered thing renders through the same generic TooltipBuilder rows) and
## no per-item 3D view in the item-viewer sub-region (A5 itself flags this
## as a later addition) — the item-viewer sub-region exists as a labeled
## placeholder only.

signal closed

const VIEWER_WIDTH := 260
const VIEWER_HEIGHT := 420
const ROTATE_SPEED := 0.5
const DRAG_SENSITIVITY := 0.01
const CAMERA_TARGET := Vector3(0.0, 0.8, 0.0)
const CAMERA_DIRECTION := Vector3(0.0, 0.25, 1.0)
const CAMERA_DISTANCE_FACTOR := 2.2
const CAMERA_MIN_RADIUS := 0.4
const PIVOT_Y_OFFSET := 0.0
const COL_PART := 0

var _material_table: MaterialTable
var _unit: Unit = null

var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_pivot: Node3D
var _preview_view: HitVolumeView
var _rotating: bool = true
var _dragging: bool = false

var _status_wound_column: VBoxContainer
var _matrix_label: RichTextLabel
var _inventory_tree: Tree
var _info_panel: RichTextLabel

var _rows_by_part: Dictionary = {}  # Part -> InventoryRow, for the info panel's own hover
var _debug_menu: PopupMenu = null


func _init() -> void:
	visible = false
	# test_battle_scene_input.gd's own audit (taskblock-17-1): a plain
	# container defaults to STOP and silently swallows board clicks under
	# it — the same convention TooltipView (also a PanelContainer) already
	# follows. The panel's genuinely interactive regions (the bot viewer,
	# the inventory tree) each carry their own real gui_input/Tree handling
	# and stay clickable regardless of this container's own filter.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(material_table: MaterialTable) -> void:
	_material_table = material_table
	var title_bar := Label.new()
	title_bar.text = "INSPECT"
	title_bar.add_theme_color_override("font_color", HulkTheme.FOREGROUND)

	var close_button := Button.new()
	close_button.text = "x"
	close_button.pressed.connect(close)

	var title_row := HBoxContainer.new()
	title_row.add_child(title_bar)
	title_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(close_button)

	var root := VBoxContainer.new()
	add_child(root)
	root.add_child(title_row)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_build_bot_viewer(body)
	_build_status_wound_column(body)

	var right_column := VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_column)

	_build_matrix_area(right_column)
	_build_inventory_tree(right_column)
	_build_info_panel(right_column)


## docs/10 "a bot's whole assembly, rotates, drag to spin" — the Resource
## Editor's own preview scaffold, ported (not shared — see file header).
func _build_bot_viewer(parent: Control) -> void:
	_preview_container = SubViewportContainer.new()
	_preview_container.custom_minimum_size = Vector2(VIEWER_WIDTH, VIEWER_HEIGHT)
	_preview_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_preview_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview_container.stretch = true
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.gui_input.connect(_on_preview_gui_input)
	parent.add_child(_preview_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(VIEWER_WIDTH, VIEWER_HEIGHT)
	_preview_container.add_child(_preview_viewport)
	_preview_viewport.add_child(WorldPalette.world_environment())
	_preview_viewport.add_child(WorldPalette.directional_light())

	_preview_camera = Camera3D.new()
	_preview_viewport.add_child(_preview_camera)
	_preview_camera.position = CAMERA_TARGET + CAMERA_DIRECTION
	_preview_camera.look_at(CAMERA_TARGET, Vector3.UP)

	_preview_pivot = Node3D.new()
	_preview_pivot.position.y = PIVOT_Y_OFFSET
	_preview_viewport.add_child(_preview_pivot)

	_preview_view = HitVolumeView.new()
	_preview_pivot.add_child(_preview_view)


func _build_status_wound_column(parent: Control) -> void:
	_status_wound_column = VBoxContainer.new()
	_status_wound_column.custom_minimum_size = Vector2(48, 0)
	_status_wound_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_status_wound_column)


func _build_matrix_area(parent: Control) -> void:
	_matrix_label = RichTextLabel.new()
	_matrix_label.bbcode_enabled = true
	_matrix_label.fit_content = true
	_matrix_label.custom_minimum_size = Vector2(0, 90)
	_matrix_label.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	_matrix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_matrix_label)


func _build_inventory_tree(parent: Control) -> void:
	_inventory_tree = Tree.new()
	_inventory_tree.columns = 2
	_inventory_tree.column_titles_visible = true
	_inventory_tree.set_column_title(0, "Part")
	_inventory_tree.set_column_title(1, "Condition")
	_inventory_tree.hide_root = true
	_inventory_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_tree.gui_input.connect(_on_tree_gui_input)
	parent.add_child(_inventory_tree)


func _build_info_panel(parent: Control) -> void:
	_info_panel = RichTextLabel.new()
	_info_panel.bbcode_enabled = true
	_info_panel.custom_minimum_size = Vector2(0, 100)
	_info_panel.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_info_panel)


## Populates every region for `unit` and shows the panel.
func open(unit: Unit) -> void:
	_unit = unit
	visible = true
	_rotating = true
	_dragging = false
	if unit.shell.root != null:
		_preview_view.show_assembly(
			unit.shell.root, _material_table, WorldPalette.team_color(unit.squad_id)
		)
		_frame_camera()
	_refresh_status_wound_column()
	_refresh_matrix_area()
	_refresh_inventory_tree()
	_show_info_placeholder()


func close() -> void:
	visible = false
	_unit = null
	closed.emit()


func _process(delta: float) -> void:
	if visible and _rotating and not _dragging and _preview_pivot != null:
		_preview_pivot.rotate_y(ROTATE_SPEED * delta)


## "click-drag interrupts the auto-rotate to inspect, releases back to
## rotating" — the same interaction the Resource Editor's own toggle button
## approximates with a manual switch; this reads the drag directly.
func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_rotating = not mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _unit != null:
			_open_debug_menu_for_unit(mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_preview_pivot.rotate_y(mm.relative.x * DRAG_SENSITIVITY)


## docs/02 "read the real node back": the same AABB-readback framing the
## Resource Editor's own `_frame_preview_camera` uses (not shared code —
## see file header), reading `HitVolumeView`'s own composed mesh geometry
## instead of re-deriving a bounding box from Part volumes by hand.
func _frame_camera() -> void:
	var combined: AABB
	var has_any := false
	for meshes: Array in _preview_view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			var world_aabb: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
			combined = world_aabb if not has_any else combined.merge(world_aabb)
			has_any = true
	var center: Vector3 = combined.get_center() if has_any else CAMERA_TARGET
	var radius: float = maxf(combined.size.length() / 2.0, CAMERA_MIN_RADIUS) if has_any else 0.5
	_preview_camera.position = center + CAMERA_DIRECTION * radius * CAMERA_DISTANCE_FACTOR
	_preview_camera.look_at(center, Vector3.UP)


## A2: "a vertical column that fills with statuses above, wounds below...
## <5-char short blurb now... hovering an entry fills the info panel."
func _refresh_status_wound_column() -> void:
	for child: Node in _status_wound_column.get_children():
		child.queue_free()
	if _unit == null or _unit.shell.root == null:
		return
	# No status effect system exists yet (taskblock21 scope fence) — the
	# statuses half of the column is structurally ready and simply empty
	# until one does.
	var seen: Dictionary = {}  # StringName -> true, dedupe across parts
	for part: Part in _unit.shell.all_parts():
		for wound_id: StringName in part.wounds:
			if seen.has(wound_id):
				continue
			seen[wound_id] = true
			_add_wound_entry(wound_id)


func _add_wound_entry(wound_id: StringName) -> void:
	var def: WoundDef = DataLibrary.get_wound_def(wound_id)
	var label := Label.new()
	label.text = def.short_label() if def != null else String(wound_id).left(5).to_upper()
	label.add_theme_color_override(
		"font_color", HulkTheme.DAMAGE if (def != null and def.disables) else HulkTheme.WARN
	)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_entered.connect(func() -> void: _show_info(TooltipBuilder.for_wound(wound_id)))
	_status_wound_column.add_child(label)


## A3: "name, personal_speed, playstyle, perks, link/base state."
func _refresh_matrix_area() -> void:
	if _unit == null:
		_matrix_label.text = ""
		return
	var matrix: Matrix = _unit.matrix
	var lines: Array[String] = []
	if matrix == null:
		lines.append("[i]no matrix docked[/i]")
	else:
		var name: String = matrix.display_name if matrix.display_name != "" else String(matrix.id)
		lines.append("[b]%s[/b]" % name)
		lines.append("personal_speed: %.1f" % matrix.personal_speed)
		lines.append("playstyle: %s" % String(matrix.playstyle))
		var perks: Array[StringName] = matrix.active_perks()
		lines.append("perks: %s" % (", ".join(perks) if not perks.is_empty() else "none"))
		lines.append("link: %s" % ("yes" if matrix.base != null else "no (base)"))
		lines.append("recovery: %s" % Enums.RecoveryState.keys()[matrix.recovery_state])
	_matrix_label.text = "\n".join(lines)


## A4: InspectRows' own strong sort (Weapons -> Containers -> Body), each
## group a real TreeItem parent so the tree stays genuinely tree'd, not
## flattened with a label prefix standing in for structure.
func _refresh_inventory_tree() -> void:
	_inventory_tree.clear()
	_rows_by_part.clear()
	if _unit == null or _unit.shell.root == null:
		return
	var root: TreeItem = _inventory_tree.create_item()
	for group: InspectRow.Group in [
		InspectRow.Group.WEAPONS, InspectRow.Group.CONTAINERS, InspectRow.Group.BODY
	]:
		var label: String = ["Weapons", "Containers", "Body"][group]
		var group_item: TreeItem = _inventory_tree.create_item(root)
		group_item.set_text(0, label)
		var depth_items: Dictionary = {0: group_item}  # depth -> most recent TreeItem, this group only
		for inspect_row: InspectRow in InspectRows.build(_unit, _material_table):
			if inspect_row.group != group:
				continue
			var row: InventoryRow = inspect_row.row
			var parent_item: TreeItem = depth_items.get(row.depth, group_item)
			var item: TreeItem = _inventory_tree.create_item(parent_item)
			var part_name: String = (
				row.part.display_name if row.part.display_name != "" else String(row.part.id)
			)
			if row.kind == InventoryRow.Kind.CONTENTS:
				part_name = "» %s" % part_name
			item.set_text(0, part_name)
			item.set_text(1, "%d/%d" % [row.part.hp, row.part.max_hp])
			if row.part.hp < row.part.max_hp:
				item.set_custom_color(1, HulkTheme.DAMAGE)
			item.set_metadata(COL_PART, row.part)
			_rows_by_part[row.part] = row
			depth_items[row.depth + 1] = item


## A6: "hovering an entry fills the info panel... mousing into a dead zone
## leaves the info put." No branch here ever CLEARS the info panel — only
## a genuine hoverable target (a real Part under the cursor) repopulates
## it; a dead zone (empty tree space) is simply a no-op. Right-click opens
## the same A7 debug menu the bot viewer does, scoped to just this row's
## own part.
func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var item: TreeItem = _inventory_tree.get_item_at_position(motion.position)
		if item == null:
			return
		var part: Variant = item.get_metadata(COL_PART)
		if not (part is Part):
			return
		var row: InventoryRow = _rows_by_part.get(part)
		_show_info(TooltipBuilder.for_part(part, _material_table, row))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
			return
		var item: TreeItem = _inventory_tree.get_item_at_position(mb.position)
		if item == null:
			return
		var part: Variant = item.get_metadata(COL_PART)
		if part is Part:
			_open_debug_menu([part as Part], mb.position)


func _show_info(data: TooltipData) -> void:
	_info_panel.text = TooltipView.to_bbcode(data)


func _show_info_placeholder() -> void:
	_info_panel.text = "[i]hover a part, wound, or status to inspect it[/i]"


## A7: "on a bot/part: Reset Health, Set Health to 0, and on placeholder
## guns Set Ammo Type." Debug-only — mutates the real Part(s) directly,
## never through a CombatAction (this isn't a combat move, it's the
## developer poking data). Right-clicking the BOT VIEWER (no specific row
## under the cursor) scopes Reset/Zero Health to every part on the unit;
## right-clicking one inventory row scopes it to just that part.
func _open_debug_menu_for_unit(at_position: Vector2) -> void:
	_open_debug_menu(_unit.shell.all_parts(), at_position)


func _open_debug_menu(parts: Array[Part], at_position: Vector2) -> void:
	if _debug_menu != null:
		_debug_menu.queue_free()
	_debug_menu = PopupMenu.new()
	add_child(_debug_menu)
	_debug_menu.add_item("Reset Health", 0)
	_debug_menu.add_item("Set Health to 0", 1)
	var ammo_ids: Array[StringName] = []
	if parts.size() == 1 and parts[0].damage > 0.0:
		for ammo_id: StringName in DataLibrary.resources_of_type(DataLibrary.TYPE_AMMO):
			ammo_ids.append(ammo_id)
			_debug_menu.add_item("Set Ammo: %s" % ammo_id, 100 + ammo_ids.size() - 1)
	_debug_menu.id_pressed.connect(_on_debug_menu_id_pressed.bind(parts, ammo_ids))
	_debug_menu.close_requested.connect(_debug_menu.queue_free)
	_debug_menu.id_pressed.connect(_debug_menu.queue_free, CONNECT_DEFERRED)
	_debug_menu.popup(Rect2i(Vector2i(get_screen_position() + at_position), Vector2i.ZERO))


func _on_debug_menu_id_pressed(id: int, parts: Array[Part], ammo_ids: Array[StringName]) -> void:
	if id == 0:
		for part: Part in parts:
			part.hp = part.max_hp
	elif id == 1:
		for part: Part in parts:
			part.hp = 0
	elif id >= 100 and id - 100 < ammo_ids.size():
		parts[0].ammo_id = ammo_ids[id - 100]
	_refresh_inventory_tree()
	_refresh_status_wound_column()
	if _preview_view != null and _unit != null and _unit.shell.root != null:
		_preview_view.show_assembly(
			_unit.shell.root, _material_table, WorldPalette.team_color(_unit.squad_id)
		)
