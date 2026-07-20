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


## taskblock-22 Pass E3/G: a welder (charged Tool Battery, held by a real
## hand) plus one damaged leg — the minimum assembly the repair menu item
## actually needs to compute a real cost/availability.
func _welder_unit(target_hp: int = 5, target_max_hp: int = 10) -> Dictionary:
	var target := Part.new()
	target.id = &"leg"
	target.material = &"steel"
	target.hp = target_hp
	target.max_hp = target_max_hp

	var battery := Part.new()
	battery.id = &"tool_battery"
	battery.hp = 3
	battery.max_hp = 3
	battery.battery_capacity = 6.0
	battery.battery_power_out = 3.0
	battery.battery_charge = 6.0
	battery.tags = [&"POWER_SOURCE", &"BATTERY", &"TOOL_BATTERY"]

	var welder := Part.new()
	welder.id = &"welder"
	welder.hp = 4
	welder.max_hp = 4
	welder.attaches_to = [&"GRIP"]
	welder.requires = {&"TRIGGER": 1}
	welder.tags = [&"WELDER"]
	var battery_socket := Socket.new(&"TOOL_BATTERY")
	battery_socket.occupant = battery
	welder.sockets = [battery_socket]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = welder
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var leg_socket := Socket.new(&"LEG")
	leg_socket.occupant = target
	torso.sockets = [hand_socket, leg_socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)
	return {"unit": unit, "welder": welder, "battery": battery, "target": target}


## A wired panel with a real SelectionController/MissionState behind it —
## `unit` is both the inspected AND the currently-selected/acting one,
## matching the one real case repairing is legal from at all.
func _panel_with_selection(unit: Unit, scrap_amount: int = 5) -> Dictionary:
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.gather_resource(&"steel", scrap_amount)
	var selection := SelectionController.new(state, mission)
	selection.select(unit)
	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(DataLibrary.material_table(), selection)
	panel.open(unit)
	return {"panel": panel, "selection": selection, "state": state, "mission": mission}


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

	panel._on_debug_menu_id_pressed(0, [weapon], [], null)
	assert_eq(weapon.hp, weapon.max_hp, "Reset Health restores to max")

	panel._on_debug_menu_id_pressed(1, [weapon], [], null)
	assert_eq(weapon.hp, 0, "Set Health to 0")


func test_debug_menu_set_ammo_sets_the_chosen_ammo_id() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)
	var weapon: Part = unit.shell.find_part(&"weapon")

	panel._on_debug_menu_id_pressed(100, [weapon], [&"some_ammo"], null)

	assert_eq(weapon.ammo_id, &"some_ammo")


## taskblock-22 Pass E3/G: "Repair with Scrap" is the first non-debug
## option, shown for a single damaged part when a selection controller is
## actually wired (SquadControlOverlay's own usage).
func test_repair_menu_item_appears_for_a_single_damaged_part() -> void:
	var built: Dictionary = _welder_unit()
	var wired: Dictionary = _panel_with_selection(built.unit)
	var panel: InspectPanel = wired.panel

	panel._open_debug_menu([built.target], Vector2.ZERO)

	assert_gt(panel._debug_menu.item_count, 0)
	assert_eq(panel._debug_menu.get_item_id(0), InspectPanel.REPAIR_ITEM_ID)
	assert_false(panel._debug_menu.is_item_disabled(0), "a charged welder + enough scrap: enabled")


func test_repair_menu_item_absent_without_a_selection_controller() -> void:
	var built: Dictionary = _welder_unit()
	var panel: InspectPanel = _panel()
	panel.open(built.unit)

	panel._open_debug_menu([built.target], Vector2.ZERO)

	for i in range(panel._debug_menu.item_count):
		assert_ne(panel._debug_menu.get_item_id(i), InspectPanel.REPAIR_ITEM_ID)


## Repairing "the whole unit at once" isn't a thing — right-clicking the
## bot viewer itself (every part at once) must never offer it.
func test_repair_menu_item_absent_for_more_than_one_part() -> void:
	var built: Dictionary = _welder_unit()
	var wired: Dictionary = _panel_with_selection(built.unit)
	var panel: InspectPanel = wired.panel

	panel._open_debug_menu([built.target, built.welder], Vector2.ZERO)

	for i in range(panel._debug_menu.item_count):
		assert_ne(panel._debug_menu.get_item_id(i), InspectPanel.REPAIR_ITEM_ID)


## Inspecting some OTHER unit than the one currently selected/acting must
## never let a right-click here queue an action against the wrong unit.
func test_repair_menu_item_absent_when_inspecting_a_non_selected_unit() -> void:
	var built: Dictionary = _welder_unit()
	var bystander := Part.new()
	bystander.id = &"bystander_root"
	bystander.hp = 5
	bystander.max_hp = 5
	var other := Unit.new(Matrix.new(), Shell.new(bystander), Vector2i(1, 0), 0)

	var state := CombatState.new(Grid.new(5, 5), [built.unit, other])
	var mission := MissionState.new(RunState.new(), state)
	mission.gather_resource(&"steel", 5)
	var selection := SelectionController.new(state, mission)
	selection.select(built.unit)  # built.unit is selected, NOT other
	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(DataLibrary.material_table(), selection)
	panel.open(other)  # inspecting a DIFFERENT unit than the selected one

	panel._open_debug_menu([built.target], Vector2.ZERO)

	for i in range(panel._debug_menu.item_count):
		assert_ne(panel._debug_menu.get_item_id(i), InspectPanel.REPAIR_ITEM_ID)


func test_repair_menu_item_disabled_without_enough_scrap() -> void:
	var built: Dictionary = _welder_unit()
	var wired: Dictionary = _panel_with_selection(built.unit, 1)  # needs 3
	var panel: InspectPanel = wired.panel

	panel._open_debug_menu([built.target], Vector2.ZERO)

	assert_true(panel._debug_menu.is_item_disabled(0))


func test_repair_menu_item_disabled_with_a_drained_battery() -> void:
	var built: Dictionary = _welder_unit()
	built.battery.battery_charge = 0.0
	var wired: Dictionary = _panel_with_selection(built.unit)
	var panel: InspectPanel = wired.panel

	panel._open_debug_menu([built.target], Vector2.ZERO)

	assert_true(panel._debug_menu.is_item_disabled(0))


## Choosing it queues a REAL RepairAction through the selection controller
## — never a debug-style direct HP write.
func test_choosing_repair_queues_a_real_repair_action() -> void:
	var built: Dictionary = _welder_unit()
	var wired: Dictionary = _panel_with_selection(built.unit)
	var panel: InspectPanel = wired.panel
	var selection: SelectionController = wired.selection

	panel._open_debug_menu([built.target], Vector2.ZERO)
	panel._on_debug_menu_id_pressed(InspectPanel.REPAIR_ITEM_ID, [built.target], [], built.target)

	assert_eq(selection.current_queue().actions.size(), 1)
	assert_true(selection.current_queue().actions[0] is RepairAction)
	assert_eq(built.target.hp, 5, "queuing alone must never mutate the part directly")


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
