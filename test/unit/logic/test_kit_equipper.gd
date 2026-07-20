extends GutTest

## taskblock-28 Pass B: "a bout starts by units equipping themselves from
## their kit." Small, purpose-built fixtures (CLAUDE.md: "if a test needs
## a concrete list, the test authors it as a fixture") exercise the
## mechanism in isolation; real shipped content (`kitted_chaingun.tres`)
## is proven separately through the real `BoutSetup` path.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _matrix_socket() -> Socket:
	return Socket.new(&"MATRIX", Transform3D.IDENTITY, &"MATRIX")


func _container_part(id: StringName, max_bulk: float = 20.0) -> Part:
	var p := Part.new()
	p.id = id
	p.attaches_to = [&"BACK"]
	p.is_container = true
	p.max_bulk = max_bulk
	p.hp = 1
	p.max_hp = 1
	return p


func _weapon_part(id: StringName, weapon_def: WeaponDef = null) -> Part:
	var p := Part.new()
	p.id = id
	p.attaches_to = [&"GRIP"]
	p.hp = 1
	p.max_hp = 1
	p.weapon_def = weapon_def
	return p


## torso: MATRIX + BACK (holding a real container) + GRIP (bare, ready to
## be equipped into).
func _build_unit(container_id: StringName = &"container") -> Dictionary:
	var container := _container_part(container_id)
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	var back_socket := Socket.new(&"BACK", Transform3D.IDENTITY, &"BACK")
	back_socket.occupant = container
	torso.sockets = [back_socket, Socket.new(&"GRIP", Transform3D.IDENTITY, &"GRIP"), _matrix_socket()]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	return {"unit": unit, "container": container}


func test_stock_is_a_noop_when_kit_is_null() -> void:
	var built: Dictionary = _build_unit()
	assert_true(KitEquipper.stock(built.unit, null, {}))
	assert_eq((built.container as Part).contents.size(), 0)


func test_stock_fills_the_kits_own_container_with_its_own_items() -> void:
	var built: Dictionary = _build_unit()
	var weapon := _weapon_part(&"pistol")
	var pool := {&"pistol": weapon}
	var kit := Kit.new(&"BACK", [&"pistol"], &"pistol", &"GRIP")

	assert_true(KitEquipper.stock(built.unit, kit, pool))

	var contents: Array[Part] = (built.container as Part).contents
	assert_eq(contents.size(), 1)
	assert_eq(contents[0].id, &"pistol")
	assert_ne(contents[0], weapon, "stock must duplicate, never attach the pool template itself")


func test_stock_errors_by_name_on_an_unknown_pool_id() -> void:
	var built: Dictionary = _build_unit()
	var kit := Kit.new(&"BACK", [&"nonexistent"], &"nonexistent", &"GRIP")

	assert_false(KitEquipper.stock(built.unit, kit, {}))
	assert_push_error("nonexistent")


func test_stock_errors_when_the_container_socket_does_not_exist() -> void:
	var built: Dictionary = _build_unit()
	var kit := Kit.new(&"NO_SUCH_SOCKET", [], &"", &"")

	assert_false(KitEquipper.stock(built.unit, kit, {}))
	assert_push_error("NO_SUCH_SOCKET")


func test_equip_instant_moves_the_weapon_from_its_container_into_its_socket() -> void:
	var built: Dictionary = _build_unit()
	var pool := {&"pistol": _weapon_part(&"pistol")}
	var kit := Kit.new(&"BACK", [&"pistol"], &"pistol", &"GRIP")
	KitEquipper.stock(built.unit, kit, pool)

	assert_true(KitEquipper.equip(built.unit, kit))

	var grip: Socket = PartGraph.find_socket(built.unit.shell.root, &"GRIP")
	assert_not_null(grip.occupant)
	assert_eq(grip.occupant.id, &"pistol")
	assert_eq(
		(built.container as Part).contents.size(),
		0,
		"the weapon must leave the container once it's in hand, not sit in both places"
	)


func test_equip_is_a_noop_when_kit_is_null() -> void:
	var built: Dictionary = _build_unit()
	assert_true(KitEquipper.equip(built.unit, null))


func test_equip_defaults_to_instant_mode() -> void:
	var built: Dictionary = _build_unit()
	var pool := {&"pistol": _weapon_part(&"pistol")}
	var kit := Kit.new(&"BACK", [&"pistol"], &"pistol", &"GRIP")
	KitEquipper.stock(built.unit, kit, pool)

	# No equip_mode argument at all — must resolve exactly like an explicit
	# INSTANT call (the seam's own default, taskblock-28 Pass B).
	KitEquipper.equip(built.unit, kit)

	assert_eq(PartGraph.find_socket(built.unit.shell.root, &"GRIP").occupant.id, &"pistol")


func test_an_unimplemented_equip_mode_fails_named_never_crashes() -> void:
	var built: Dictionary = _build_unit()
	var pool := {&"pistol": _weapon_part(&"pistol")}
	var kit := Kit.new(&"BACK", [&"pistol"], &"pistol", &"GRIP")
	KitEquipper.stock(built.unit, kit, pool)

	var equipped: bool = KitEquipper.equip(built.unit, kit, Enums.EquipMode.VISIBLE)

	assert_false(equipped)
	assert_push_error("has no implementation yet")
	# the weapon must be left exactly where stock() put it — an
	# unimplemented mode is a refusal, never a partial mutation.
	assert_eq((built.container as Part).contents[0].id, &"pistol")


func test_equip_instant_chambers_the_kits_own_ammo() -> void:
	var built: Dictionary = _build_unit()
	var weapon_def := WeaponDef.new()
	weapon_def.accepts_family = &"9mm"
	weapon_def.max_case_length = 20.0
	var pool := {&"pistol": _weapon_part(&"pistol", weapon_def)}
	var kit := Kit.new(&"BACK", [&"pistol"], &"pistol", &"GRIP", &"9mm_fmj")
	KitEquipper.stock(built.unit, kit, pool)

	assert_true(KitEquipper.equip(built.unit, kit))

	var equipped_weapon: Part = PartGraph.find_socket(built.unit.shell.root, &"GRIP").occupant
	assert_eq(equipped_weapon.ammo_id, &"9mm_fmj")


func test_equip_fails_named_when_the_weapon_never_made_it_into_the_kit() -> void:
	var built: Dictionary = _build_unit()
	# stored_item_ids never actually names the weapon — a malformed kit.
	var kit := Kit.new(&"BACK", [], &"pistol", &"GRIP")

	assert_false(KitEquipper.equip(built.unit, kit))
	assert_push_error("pistol")
