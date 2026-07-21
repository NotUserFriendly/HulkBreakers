extends GutTest

## taskblock-08 E1/TESTS: "the action bar has 10 square slots." Pips,
## action provisioning, and enable/disable logic are already covered
## (test_action_catalog.gd, test_tactics_controller_arm.gd) — this is
## layout only (E4).


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


## torso -[HAND]- hand(TRIGGER) -[GRIP]- pistol — the same shape
## test_tactics_controller_arm.gd uses, so the unit actually provides
## &"shoot" through a real, `ap_cost`-bearing part.
func _make_armed_unit(cell: Vector2i, ap_cost: int, squad: int = 0) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.ap_cost = ap_cost
	pistol.scatter = [Ring.new(0.1, 1.0)]
	pistol.provides_actions = [&"shoot"]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## BR30.xx: same shape as `_make_armed_unit`, but the weapon only provides
## `&"burst"` and authors a `weapon_def.burst_ap_cost` HIGHER than its own
## plain `ap_cost` — matching `data/parts/chaingun.tres`
## (`ap_cost = 2`, `weapon_def.burst_ap_cost = 4`). Real burst weapons
## charge the burst cost, not the plain one.
func _make_burst_armed_unit(
	cell: Vector2i, ap_cost: int, burst_ap_cost: int, squad: int = 0
) -> Unit:
	var chaingun := Part.new()
	chaingun.id = &"chaingun"
	chaingun.hp = 3
	chaingun.max_hp = 3
	chaingun.attaches_to = [&"GRIP"]
	chaingun.requires = {&"TRIGGER": 1}
	chaingun.damage = 5.0
	chaingun.ap_cost = ap_cost
	chaingun.scatter = [Ring.new(0.1, 1.0)]
	chaingun.provides_actions = [&"burst"]
	chaingun.weapon_def = WeaponDef.new()
	chaingun.weapon_def.max_range = 12.0
	chaingun.weapon_def.burst_size = 12
	chaingun.weapon_def.burst_ap_cost = burst_ap_cost

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = chaingun
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## tb31 Pass D: a welder-shaped part providing `&"repair"` — no `ap_cost`
## authored (matching the real `arc_welder.tres`, which authors none
## either, silently falling back to `Part.gd`'s own bare default of 1).
## `RepairAction` always charges the real, fixed `RepairResolver.
## REPAIR_AP_COST` (4) regardless.
func _make_repair_capable_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var welder := Part.new()
	welder.id = &"welder"
	welder.hp = 4
	welder.max_hp = 4
	welder.attaches_to = [&"GRIP"]
	welder.requires = {&"TRIGGER": 1}
	welder.provides_actions = [&"repair"]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = welder
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func _setup_bar(unit: Unit) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), [unit])
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	var tooltip_view := TooltipView.new()
	var container := HBoxContainer.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	add_child_autofree(tooltip_view)
	add_child_autofree(container)
	controller.setup(state, board_view, camera_rig)
	controller.selection.select(unit)

	var bar := ActionBar.new()
	add_child_autofree(bar)
	bar.setup(controller, container, tooltip_view)
	return {"bar": bar, "controller": controller, "container": container}


func test_slot_count_is_ten() -> void:
	assert_eq(ActionBar.SLOT_COUNT, 10)


func test_box_size_is_square() -> void:
	assert_eq(ActionBar.BOX_SIZE.x, ActionBar.BOX_SIZE.y)


func test_setup_builds_ten_square_panels() -> void:
	var state := CombatState.new(Grid.new(10, 10), [_make_unit(Vector2i(0, 0))])
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	var tooltip_view := TooltipView.new()
	var container := HBoxContainer.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	add_child_autofree(tooltip_view)
	add_child_autofree(container)
	controller.setup(state, board_view, camera_rig)

	var bar := ActionBar.new()
	add_child_autofree(bar)
	bar.setup(controller, container, tooltip_view)

	assert_eq(container.get_child_count(), ActionBar.SLOT_COUNT)
	for i in range(ActionBar.SLOT_COUNT):
		var panel: PanelContainer = container.get_child(i)
		assert_eq(panel.custom_minimum_size, ActionBar.BOX_SIZE)
		assert_eq(
			panel.custom_minimum_size.x, panel.custom_minimum_size.y, "slot %d must be square" % i
		)


## taskblock-27 Pass D3: "actions clickable without enough AP." An
## unaffordable action's own slot must dim, distinct from both an armed
## slot (HIGHLIGHT) and an ordinary affordable one (FOREGROUND) — but its
## initials still show, unlike a genuinely empty slot.
func test_an_unaffordable_action_dims_but_still_shows_its_initials() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 3)
	var built: Dictionary = _setup_bar(unit)  # CombatState resets ap to max_ap on add
	var bar: ActionBar = built.bar
	var container: HBoxContainer = built.container
	unit.ap = 1  # below the pistol's own ap_cost (3)
	bar.refresh()

	var label: Label = (container.get_child(0) as PanelContainer).get_child(0)
	assert_eq(label.text, "SH", "sanity: shoot's own initials still show")
	assert_eq(label.modulate, HulkTheme.DIM, "unaffordable must dim, not read as ordinarily usable")


func test_an_affordable_action_shows_at_full_foreground() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 1)
	var built: Dictionary = _setup_bar(unit)
	var container: HBoxContainer = built.container

	var label: Label = (container.get_child(0) as PanelContainer).get_child(0)
	assert_eq(label.modulate, HulkTheme.FOREGROUND)


## Clicking an unaffordable slot must not arm it — the disable is real,
## not just cosmetic dimming.
func test_clicking_an_unaffordable_action_does_not_arm_it() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 3)
	var built: Dictionary = _setup_bar(unit)
	var bar: ActionBar = built.bar
	var container: HBoxContainer = built.container
	var controller: TacticsController = built.controller
	unit.ap = 1
	bar.refresh()

	var panel: PanelContainer = container.get_child(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)

	assert_null(controller.armed_action, "an unaffordable action must never arm")


## BR27.05: "action bar items still selectable without enough AP." An
## action already QUEUED this turn (never resolved — docs/09: "queuing
## mutates nothing") must still count against a LATER slot's own
## affordability check. Before the fix, refresh()/the click guard read
## the raw un-queued `unit.ap`, so a queued move that burned AP into
## movement (0 MP: every step converts 1 AP) left the shoot slot reading
## "still affordable" against the unit's full starting AP, even though
## the honestly-previewed unit has less left.
func test_an_action_already_queued_this_turn_counts_against_a_later_affordability_check() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 3)
	var built: Dictionary = _setup_bar(unit)
	var bar: ActionBar = built.bar
	var controller: TacticsController = built.controller
	var container: HBoxContainer = built.container
	unit.ap = 3
	unit.mp = 0.0

	var moved: bool = controller.selection.queue_move(Vector2i(1, 0))
	assert_true(moved, "sanity: a one-cell move with 0 mp must still queue by burning ap")
	var preview_ap: int = controller.selection.previewed_unit().ap
	assert_lt(preview_ap, unit.ap, "sanity: the queued move actually spent ap in preview")
	assert_lt(preview_ap, 3, "sanity: not enough ap left for the pistol's own 3-ap cost")

	bar.refresh()

	var label: Label = (container.get_child(0) as PanelContainer).get_child(0)
	assert_eq(
		label.modulate,
		HulkTheme.DIM,
		"must dim once the queued (not yet resolved) move used up the remaining ap"
	)

	var panel: PanelContainer = container.get_child(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)

	assert_null(
		controller.armed_action, "must not arm once the queued move used up the remaining ap"
	)


## BR30.xx: "actions selectable when not enough AP available still" —
## `_can_afford` compared the unit's AP against the weapon's plain
## `ap_cost` (2) regardless of action id, but a `&"burst"`-providing
## weapon actually charges its own, higher `weapon_def.burst_ap_cost` (4,
## `BurstAction._ap_cost`). 3 AP covers the plain cost but not the real
## one — before the fix this showed (and let you arm) BURST as
## affordable anyway, only to have it silently rejected at enqueue time.
func test_burst_dims_using_its_own_higher_ap_cost_not_the_weapons_plain_one() -> void:
	var unit: Unit = _make_burst_armed_unit(Vector2i(0, 0), 2, 4)
	var built: Dictionary = _setup_bar(unit)  # CombatState resets ap to max_ap on add
	var bar: ActionBar = built.bar
	var container: HBoxContainer = built.container
	unit.ap = 3  # covers the plain ap_cost (2) but not burst_ap_cost (4)
	bar.refresh()

	var label: Label = (container.get_child(0) as PanelContainer).get_child(0)
	assert_eq(label.text, "BR", "sanity: burst's own initials still show")
	assert_eq(
		label.modulate,
		HulkTheme.DIM,
		"burst must dim against its own real (higher) AP cost, not the weapon's plain ap_cost"
	)


## tb31 Pass D: same bug class, found giving repair its first real action-
## bar UI call site — a welder's own `ap_cost` (unauthored, falls back to
## `Part.gd`'s bare default of 1) is NOT what `RepairAction` actually
## charges (`RepairResolver.REPAIR_AP_COST`, 4). 2 AP covers the plain
## default but not the real cost.
func test_repair_dims_using_its_own_real_ap_cost_not_the_weapons_plain_one() -> void:
	var unit: Unit = _make_repair_capable_unit(Vector2i(0, 0))
	var built: Dictionary = _setup_bar(unit)
	var container: HBoxContainer = built.container
	unit.ap = 2  # covers the welder's own unauthored default (1) but not REPAIR_AP_COST (4)
	built.bar.refresh()

	var label: Label = (container.get_child(0) as PanelContainer).get_child(0)
	assert_eq(label.text, "RP", "sanity: repair's own initials still show")
	assert_eq(
		label.modulate,
		HulkTheme.DIM,
		"repair must dim against its own real AP cost, not the welder's unauthored plain ap_cost"
	)


func test_clicking_an_affordable_action_still_arms_it() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 1)
	var built: Dictionary = _setup_bar(unit)
	var container: HBoxContainer = built.container
	var controller: TacticsController = built.controller

	var panel: PanelContainer = container.get_child(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)

	assert_not_null(controller.armed_action)
	assert_eq(controller.armed_action.id, &"shoot")


## tb31 Pass D: a `TargetingMode.NONE` action (overwatch) queues
## immediately on click — never arms (there's nothing to click a board
## target for). `provides_actions = [&"shoot", &"overwatch"]` on the same
## pistol part puts overwatch at slot 0 (`_sort_by_id`'s own alphabetical
## order within one part), same fixture shape
## `test_a_shell_with_a_pistol_shows_shoot_and_overwatch` already proves.
func test_clicking_a_none_mode_action_queues_immediately_never_arms() -> void:
	var unit: Unit = _make_armed_unit(Vector2i(0, 0), 1)
	var pistol: Part = unit.shell.find_part(&"pistol")
	pistol.provides_actions = [&"shoot", &"overwatch"]
	var built: Dictionary = _setup_bar(unit)
	var container: HBoxContainer = built.container
	var controller: TacticsController = built.controller

	var panel: PanelContainer = container.get_child(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)

	assert_null(controller.armed_action, "a NONE-mode action never arms")
	var queued: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(queued.size(), 1, "it queues immediately instead")
	assert_true(queued[0] is OverwatchAction)
