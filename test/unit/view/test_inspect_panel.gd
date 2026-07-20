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


## taskblock-22 Pass G1: "the panel stays within the viewport" — an
## artificially oversized/off-screen rect must come back inside real
## bounds, re-centered, not just smaller.
func test_clamp_to_viewport_shrinks_and_recenters_an_oversized_panel() -> void:
	var panel: InspectPanel = _panel()
	var real_viewport_size: Vector2 = panel.get_viewport_rect().size
	panel.size = real_viewport_size + Vector2(500, 500)
	panel.position = Vector2(-200, -200)

	panel._clamp_to_viewport()

	# Godot itself never allows a Control's size below its own combined
	# minimum (a real floor this panel's own content sets, e.g. the bot
	# viewer's fixed VIEWER_WIDTH/HEIGHT) — the achievable target is
	# whichever is LARGER, the real viewport or that floor. A real game
	# window (project.godot's own 1920x1080 MIN_WINDOW_SIZE) comfortably
	# clears this panel's own minimum, so in practice this is simply
	# "fits the viewport"; this test's own headless viewport can be
	# smaller than that floor, which is an environment quirk, not a
	# regression in the clamp itself.
	var achievable: Vector2 = real_viewport_size.max(panel.get_combined_minimum_size())
	assert_true(panel.position.x >= 0.0)
	assert_true(panel.position.y >= 0.0)
	assert_true(panel.size.x <= achievable.x + 0.01)
	assert_true(panel.size.y <= achievable.y + 0.01)


## Content that legitimately grows past 600px (enough wounds) must not
## push the panel taller than the real viewport either — this is the
## actual reproducible cause behind "falls off the bottom," not just a
## small monitor (project.godot's own MIN_WINDOW_SIZE floor already rules
## that out at runtime).
func test_open_with_many_wounds_still_fits_the_viewport_after_clamping() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	var weapon: Part = unit.shell.find_part(&"weapon")
	for i in range(200):
		WoundEffects.inflict(weapon, StringName("synthetic_wound_%d" % i))

	panel.open(unit)

	# 200 wound rows, unscrolled, would each need real height — hundreds
	# to thousands of pixels between them. The ScrollContainer wrapping
	# _status_wound_column (_build_status_wound_column) caps what it
	# actually DEMANDS from the panel's own layout regardless of row
	# count; this fixed, generous bound sits well above the panel's
	# normal non-wound content but far below what 200 unscrolled rows
	# would force if the wrap weren't there.
	assert_true(panel.get_combined_minimum_size().y < 1000.0)


## taskblock-22 Pass G1: "the right-click menu appears at the cursor" —
## both real click paths (the bot viewer, an inventory row) resolve to
## the ACTUAL screen position clicked, not the panel's own corner plus a
## coordinate local to some other control.
func test_right_click_on_the_bot_viewer_opens_the_menu_at_the_cursor() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)

	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	mb.position = Vector2(40, 60)
	panel._on_preview_gui_input(mb)

	# Godot's own Popup clamps its FINAL on-screen position to stay inside
	# the real screen — a tiny headless test screen clamps far more
	# aggressively than any real game window would, so this checks the
	# exact value `popup()` was actually asked for (see
	# `_last_requested_menu_position`'s own doc comment), not wherever it
	# visually landed.
	var expected: Vector2 = panel._preview_container.get_screen_position() + mb.position
	assert_eq(panel._last_requested_menu_position, expected)


func test_right_click_on_a_tree_row_opens_the_menu_at_the_cursor() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)
	panel._inventory_tree.size = Vector2(400, 300)
	var weapon: Part = unit.shell.find_part(&"weapon")
	var weapon_item: TreeItem = _find_item(panel._inventory_tree, weapon)
	var rect: Rect2 = panel._inventory_tree.get_item_area_rect(weapon_item)

	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	mb.position = rect.position + Vector2(5, rect.size.y / 2.0)
	panel._on_tree_gui_input(mb)

	var expected: Vector2 = panel._inventory_tree.get_screen_position() + mb.position
	assert_eq(panel._last_requested_menu_position, expected)


## taskblock-22 Pass G3: non-debug (Repair with Scrap) sorts first and
## stays unmarked; every debug tool sorts after, `[*]`-prefixed.
func test_debug_items_are_marked_and_sorted_after_non_debug() -> void:
	var built: Dictionary = _welder_unit()
	var wired: Dictionary = _panel_with_selection(built.unit)
	var panel: InspectPanel = wired.panel

	panel._open_debug_menu([built.target], Vector2.ZERO)

	assert_eq(panel._debug_menu.get_item_id(0), InspectPanel.REPAIR_ITEM_ID)
	assert_false(panel._debug_menu.get_item_text(0).begins_with("[*]"))
	for i in range(1, panel._debug_menu.item_count):
		assert_true(
			panel._debug_menu.get_item_text(i).begins_with("[*]"),
			"item %d (%s) must be marked debug" % [i, panel._debug_menu.get_item_text(i)]
		)


## taskblock-22 Pass G4: "fires the status hook with the chosen stack
## count" — 1/5/10 Stacks cross BURN_THRESHOLD and inflict the wound; 0.5
## Stacks deliberately does not, exercising the hook's own gate rather
## than always firing.
func test_burn_submenu_at_or_above_threshold_inflicts_the_wound() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)
	var weapon: Part = unit.shell.find_part(&"weapon")

	panel._on_burn_submenu_id_pressed(1, weapon)  # index 1 -> 1.0 stacks

	assert_true(weapon.wounds.has(InspectPanel.BURN_WOUND_ID))


func test_burn_submenu_below_threshold_does_not_inflict_the_wound() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()
	panel.open(unit)
	var weapon: Part = unit.shell.find_part(&"weapon")

	panel._on_burn_submenu_id_pressed(0, weapon)  # index 0 -> 0.5 stacks

	assert_false(weapon.wounds.has(InspectPanel.BURN_WOUND_ID))


## taskblock-22 Pass G4: "create-part lists only valid attachments" —
## checked against PartGraph.is_legal_attachment directly, not re-derived.
func test_create_part_submenu_lists_only_legal_attachments() -> void:
	var panel: InspectPanel = _panel()
	var host := Part.new()
	host.id = &"host"
	host.hp = 5
	host.max_hp = 5
	var empty_grip := Socket.new(&"GRIP")
	host.sockets = [empty_grip]
	var unit := Unit.new(Matrix.new(), Shell.new(host), Vector2i(0, 0), 0)
	panel.open(unit)

	panel._open_debug_menu([host], Vector2.ZERO)

	var submenu: PopupMenu = null
	for i in range(panel._debug_menu.item_count):
		if panel._debug_menu.get_item_text(i) == "[*] Create Part":
			submenu = panel._debug_menu.get_item_submenu_node(i)
	assert_not_null(submenu, "a part with an empty GRIP socket must offer Create Part")

	var expected_ids: Array[StringName] = []
	for part_id: StringName in DataLibrary.resources_of_type(DataLibrary.TYPE_PARTS):
		if PartGraph.is_legal_attachment(DataLibrary.get_part(part_id), empty_grip):
			expected_ids.append(part_id)
	assert_gt(expected_ids.size(), 0, "sanity: at least one real part must attach to GRIP")
	assert_eq(submenu.item_count, expected_ids.size())


func test_choosing_create_part_attaches_a_real_part_at_the_socket() -> void:
	var panel: InspectPanel = _panel()
	var host := Part.new()
	host.id = &"host"
	host.hp = 5
	host.max_hp = 5
	var empty_grip := Socket.new(&"GRIP")
	host.sockets = [empty_grip]
	var unit := Unit.new(Matrix.new(), Shell.new(host), Vector2i(0, 0), 0)
	panel.open(unit)

	var candidates: Array[Part] = []
	for part_id: StringName in DataLibrary.resources_of_type(DataLibrary.TYPE_PARTS):
		var candidate: Part = DataLibrary.get_part(part_id)
		if PartGraph.is_legal_attachment(candidate, empty_grip):
			candidates.append(candidate)
	assert_gt(candidates.size(), 0, "sanity: at least one real part must attach to GRIP")

	panel._on_create_part_submenu_id_pressed(0, host, empty_grip, candidates)

	assert_eq(empty_grip.occupant, candidates[0])


## _armed_unit's own torso/weapon carry no `volume` boxes (fine for the
## tree/menu tests above — no geometry, no mesh instances) — the isolate-
## camera tests below need at least one real MeshInstance3D to tag.
func _unit_with_geometry() -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)


## taskblock-22 Pass G2: "the bot viewer renders via the isolate camera
## without showing the model on the field" — set_isolated tags/clears the
## real render layer on every mesh instance the live view actually owns.
func test_set_isolated_toggles_the_render_layer_on_every_mesh_instance() -> void:
	var unit: Unit = _unit_with_geometry()
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())
	assert_false(view._meshes_by_part.is_empty(), "sanity: the torso must have produced a mesh")

	view.set_isolated(true)
	for meshes: Array in view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			assert_true(mesh_instance.get_layer_mask_value(HitVolumeView.ISOLATE_LAYER))

	view.set_isolated(false)
	for meshes: Array in view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			assert_false(mesh_instance.get_layer_mask_value(HitVolumeView.ISOLATE_LAYER))


## `_live_view_lookup`'s real contract is `Callable(int) -> HitVolumeView`
## (BattleScene.find_unit_view's own signature) — open() must call it with
## `unit.id`, never the `Unit` object itself. A lambda that ignores its
## argument (every OTHER test below) can't catch a caller passing the
## wrong type; this one actually asserts what was received.
func test_open_calls_the_live_view_lookup_with_the_units_own_id() -> void:
	var unit: Unit = _unit_with_geometry()
	var received: Array = []
	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(
		DataLibrary.material_table(),
		null,
		func(id: int) -> HitVolumeView:
			received.append(id)
			return null
	)

	panel.open(unit)

	assert_eq(received, [unit.id])


## A live-view lookup (real hosts, SquadControlOverlay/SpectatorOverlay)
## must isolate the ACTUAL live view — never build a disconnected copy —
## restricting the preview camera's own cull_mask to just that layer.
func test_open_with_a_live_view_lookup_isolates_the_real_view_not_a_fresh_copy() -> void:
	var unit: Unit = _unit_with_geometry()
	var live_view := HitVolumeView.new()
	add_child_autofree(live_view)
	live_view.setup(unit, DataLibrary.material_table())

	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(
		DataLibrary.material_table(), null, func(_id: int) -> HitVolumeView: return live_view
	)

	panel.open(unit)

	assert_eq(panel._isolated_view, live_view)
	assert_false(
		panel._preview_viewport.own_world_3d, "must share the live World3D, not isolate it"
	)
	assert_true(panel._preview_camera.get_cull_mask_value(HitVolumeView.ISOLATE_LAYER))
	assert_false(
		live_view._meshes_by_part.is_empty(), "sanity: the torso must have produced a mesh"
	)
	for meshes: Array in live_view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			assert_true(mesh_instance.get_layer_mask_value(HitVolumeView.ISOLATE_LAYER))


func test_closing_clears_isolation_on_the_previously_focused_view() -> void:
	var unit: Unit = _unit_with_geometry()
	var live_view := HitVolumeView.new()
	add_child_autofree(live_view)
	live_view.setup(unit, DataLibrary.material_table())

	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(
		DataLibrary.material_table(), null, func(_id: int) -> HitVolumeView: return live_view
	)
	panel.open(unit)

	panel.close()

	assert_null(panel._isolated_view)
	assert_false(
		live_view._meshes_by_part.is_empty(), "sanity: the torso must have produced a mesh"
	)
	for meshes: Array in live_view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			assert_false(mesh_instance.get_layer_mask_value(HitVolumeView.ISOLATE_LAYER))


## No live board to isolate against (every caller before this pass, and
## still every bare/standalone test) — the panel must fall back to its
## own fresh-copy assembly, now in its OWN isolated World3D (G2's actual
## fix for "renders at ~0,0 on the actual field": that leak was the
## fallback's own preview viewport silently SHARING the main World3D by
## never overriding own_world_3d at all).
func test_the_fallback_path_still_works_and_is_its_own_isolated_world() -> void:
	var panel: InspectPanel = _panel()
	var unit: Unit = _armed_unit()

	panel.open(unit)

	assert_null(panel._isolated_view, "no lookup wired -> falls back to the fresh-copy path")
	assert_true(
		panel._preview_viewport.own_world_3d, "the fresh copy must be its OWN isolated world"
	)
