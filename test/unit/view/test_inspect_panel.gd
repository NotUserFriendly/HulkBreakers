extends GutTest

## taskblock-21 Pass A: the inspect panel is a thin renderer over
## InspectRows/WeaponRows/TooltipBuilder — this only checks the panel
## actually wires those into its own Tree/labels/info-panel correctly.
## Follows the established convention (test_resource_editor_dropdown.gd's
## own `_apply_dropdown_choice` call) of exercising a PopupMenu's own
## handler directly rather than simulating a real popup interaction.


func _armed_unit(squad: int = 0) -> Unit:
	var weapon := Part.new()
	weapon.id = &"weapon"
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.damage = 5.0

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	torso.sockets = [grip]

	return Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), squad)


func _find_item(tree: Tree, part: Part) -> TreeItem:
	var root: TreeItem = tree.get_root()
	if root == null:
		return null
	return _find_item_under(root, part)


func _find_item_under(item: TreeItem, part: Part) -> TreeItem:
	if item.get_metadata(0) == part:
		return item
	var child: TreeItem = item.get_first_child()
	while child != null:
		var found: TreeItem = _find_item_under(child, part)
		if found != null:
			return found
		child = child.get_next()
	return null


func _panel() -> InspectPanel:
	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(DataLibrary.material_table())
	return panel


func test_open_populates_the_tree_with_weapon_and_body_groups() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()

	panel.open(unit)

	var root: TreeItem = panel._inventory_tree.get_root()
	assert_not_null(root)
	var groups: Array[String] = []
	var child: TreeItem = root.get_first_child()
	while child != null:
		groups.append(child.get_text(0))
		child = child.get_next()
	assert_eq(groups, ["Weapons", "Containers", "Body"])


func test_open_shows_the_panel_and_close_hides_it_and_emits_closed() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)
	assert_true(panel.visible)

	watch_signals(panel)
	panel.close()

	assert_false(panel.visible)
	assert_signal_emitted(panel, "closed")


## A6: "hovering an entry fills the info panel... mousing into a dead zone
## leaves the info put."
func test_hovering_a_tree_row_fills_the_info_panel_and_a_dead_zone_leaves_it() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)
	var weapon: Part = unit.shell.find_part(&"weapon")
	var weapon_item: TreeItem = _find_item(panel._inventory_tree, weapon)
	assert_not_null(weapon_item, "sanity: the weapon must actually be in the tree")
	panel._inventory_tree.size = Vector2(400, 300)

	# Read the real on-screen rect back (CLAUDE.md: never guess pixel
	# coordinates for something the control can report itself).
	var rect: Rect2 = panel._inventory_tree.get_item_area_rect(weapon_item)
	var motion := InputEventMouseMotion.new()
	motion.position = rect.position + Vector2(5, rect.size.y / 2.0)
	panel._on_tree_gui_input(motion)
	var after_hover: String = panel._info_panel.text
	assert_true(after_hover.contains("weapon"), "hovering the weapon row must fill the info panel")

	# A motion event far outside any real row is the dead zone — text must
	# be completely unchanged, not cleared.
	var dead_zone := InputEventMouseMotion.new()
	dead_zone.position = Vector2(10, 5000)
	panel._on_tree_gui_input(dead_zone)
	assert_eq(panel._info_panel.text, after_hover, "a dead-zone hover must never clear the panel")


## A2: the status/wound column lists every wound a unit's parts carry.
func test_wounds_on_any_part_populate_the_status_wound_column() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	WoundEffects.inflict(unit.shell.root, &"severed_controls")

	panel.open(unit)

	assert_eq(panel._status_wound_column.get_child_count(), 1)
	var entry: Label = panel._status_wound_column.get_child(0)
	assert_eq(entry.text, DataLibrary.get_wound_def(&"severed_controls").short_label())


## A7: Reset Health / Set Health to 0, exercised the same way
## test_resource_editor_dropdown.gd exercises its own PopupMenu handler —
## directly, not via a simulated popup click.
func test_debug_menu_reset_and_zero_health_mutate_the_real_part() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)
	var weapon: Part = unit.shell.find_part(&"weapon")
	weapon.hp = 1

	panel._on_debug_menu_id_pressed(0, [weapon], [])
	assert_eq(weapon.hp, weapon.max_hp, "Reset Health restores to max")

	panel._on_debug_menu_id_pressed(1, [weapon], [])
	assert_eq(weapon.hp, 0, "Set Health to 0")


func test_debug_menu_set_ammo_sets_the_chosen_ammo_id() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)
	var weapon: Part = unit.shell.find_part(&"weapon")

	panel._on_debug_menu_id_pressed(100, [weapon], [&"some_ammo"])

	assert_eq(weapon.ammo_id, &"some_ammo")


## A3: matrix info renders without any locally invented number — a raw
## field read straight off the real Matrix.
func test_matrix_area_shows_personal_speed_and_playstyle() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	unit.matrix.personal_speed = 3.5
	unit.matrix.playstyle = &"MARKSMAN"

	panel.open(unit)

	assert_true(panel._matrix_label.text.contains("3.5"))
	assert_true(panel._matrix_label.text.contains("MARKSMAN"))
