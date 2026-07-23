extends GutTest

## taskblock-16 Pass B: `FieldObjects` (hardcoded factory functions) is
## retired — every field object is a real `.tres` loaded through
## `DataLibrary`, same as any other part. These prove each one is shaped
## the way the rest of the system (shot plane, cook-off, salvage,
## movement blocking) expects, and that the three previously-missing
## covers (`pillar`/`forklift`/`barrel_pallet`) exist and assemble.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func test_no_field_objects_factory_file_remains() -> void:
	assert_false(ResourceLoader.exists("res://src/logic/field_objects.gd"))


func test_scrap_pile_has_real_geometry_material_and_salvage() -> void:
	var part: Part = DataLibrary.get_part(&"scrap_pile")
	assert_not_null(part, "must load from .tres through DataLibrary")
	assert_eq(part.id, &"scrap_pile")
	assert_true(part.volume.size() > 0)
	assert_ne(part.material, &"")
	assert_true(part.hp > 0)
	assert_eq(part.salvage_yield, {&"metals": 4})


func test_goo_barrel_is_volatile_and_detonates() -> void:
	var part: Part = DataLibrary.get_part(&"goo_barrel")
	assert_not_null(part)
	assert_true(&"VOLATILE" in part.tags)
	assert_eq(part.failure_mode, &"DETONATE")
	assert_gt(part.detonate_damage, 0.0)
	assert_gt(part.detonate_radius, 0.0)
	assert_eq(part.salvage_yield, {&"reactives": 2})


## taskblock-16 B1: goo_barrel must be able to plug into barrel_pallet's
## own BARREL_SLOT sockets — it never declared an attaches_to before this
## pass because nothing ever attached it to anything.
func test_goo_barrel_can_attach_to_a_barrel_slot() -> void:
	var part: Part = DataLibrary.get_part(&"goo_barrel")
	assert_true(&"BARREL_SLOT" in part.attaches_to)


func test_crate_has_real_geometry_material_and_salvage() -> void:
	var part: Part = DataLibrary.get_part(&"crate")
	assert_not_null(part)
	assert_true(part.volume.size() > 0)
	assert_ne(part.material, &"")
	assert_eq(part.salvage_yield, {&"organics": 3})


func test_every_starter_field_object_is_destructible_by_default() -> void:
	# Distinct from MapGen's own randomly-scattered terrain cover, which is
	# deliberately permanent (is_destructible = false) — a field object is
	# meant to be cut apart or destroyed for its salvage.
	for id: StringName in [&"scrap_pile", &"goo_barrel", &"crate"]:
		var part: Part = DataLibrary.get_part(id)
		assert_true(part.is_destructible, "%s must be destructible" % part.id)


## taskblock-16 B1: "the plain non-interactable cover — tall, masks
## torso, just blocks."
func test_pillar_exists_and_masks_torso_height() -> void:
	var part: Part = DataLibrary.get_part(&"pillar")
	assert_not_null(part)
	assert_true(part.volume.size() > 0)
	var height: float = part.volume[0].size.y
	assert_gt(
		height, MapGen.FULL_COVER_HEIGHT, "a pillar must be tall enough to mask torso and head"
	)


## taskblock-16 B1: "a shell with no matrix docked, carrying a
## battery/POWER socket."
func test_forklift_exists_hosts_no_matrix_and_carries_a_power_socket() -> void:
	var part: Part = DataLibrary.get_part(&"forklift")
	assert_not_null(part)
	assert_false(part.hosts_matrix(), "a forklift must never host a matrix")
	var power_sockets: Array = part.sockets.filter(
		func(s: Socket) -> bool: return s.socket_type == &"POWER"
	)
	assert_eq(power_sockets.size(), 1)
	assert_null(
		power_sockets[0].occupant, "the socket ships empty — occupying it is a real follow-up"
	)


## taskblock-16 B1: "generates with 0-4 goo_barrels on it (seeded)" — the
## template itself ships with four empty slots for MapGen to fill.
func test_barrel_pallet_exists_with_four_empty_barrel_slots() -> void:
	var part: Part = DataLibrary.get_part(&"barrel_pallet")
	assert_not_null(part)
	var slots: Array = part.sockets.filter(
		func(s: Socket) -> bool: return s.socket_type == &"BARREL_SLOT"
	)
	assert_eq(slots.size(), 4)
	for slot: Socket in slots:
		assert_null(slot.occupant, "the template itself must ship with no barrels attached")


## taskblock-16 B1: a barrel actually attaches into a pallet's own slot —
## the real mechanism MapGen will drive at generation time.
func test_a_goo_barrel_can_actually_attach_into_a_barrel_pallet_slot() -> void:
	var pallet: Part = DataLibrary.get_part(&"barrel_pallet")
	var barrel: Part = DataLibrary.get_part(&"goo_barrel")
	var slot: Socket = PartGraph.find_free_socket(pallet, &"BARREL_SLOT")

	assert_true(PartGraph.attach(barrel, pallet, slot))

	assert_eq(slot.occupant, barrel)


## taskblock-16 B1: "each barrel is a real goo_barrel (so shooting the
## pallet can cook them off)" — an attached barrel must appear as its own
## hittable Region in the shot plane, not just ride along inside the
## pallet's own box (`BodyProjector.project_assembly` walks `sockets`,
## exactly why B1 attaches barrels there and never into `contents`,
## which the shot plane never sees).
func test_an_attached_barrel_projects_into_the_shot_plane_as_its_own_hittable_region() -> void:
	var pallet: Part = DataLibrary.get_part(&"barrel_pallet")
	var barrel: Part = DataLibrary.get_part(&"goo_barrel")
	var slot: Socket = PartGraph.find_free_socket(pallet, &"BARREL_SLOT")
	PartGraph.attach(barrel, pallet, slot)

	var grid := Grid.new(5, 5)
	grid.blockers[Vector2i(2, 2)] = pallet
	var state := CombatState.new(grid)

	var plane: Array[Region] = ShotPlane.build(Vector3(2, 0.0, 0), Vector3(0, 0.0, 1), state)
	var hit_the_barrel := false
	for region: Region in plane:
		if region.part == barrel:
			hit_the_barrel = true
	assert_true(hit_the_barrel, "the attached barrel must project as its own Region")

	# The mechanism that fires once a shot actually reduces the barrel to 0
	# hp (VOLATILE + failure_mode DETONATE) is proven generically in
	# test_damage_resolver.gd::test_the_goo_barrel_field_object_detonates —
	# what's new here is only that an ATTACHED barrel is reachable at all.
	var affected: Array[Unit] = DamageResolver.detonate(barrel, state)
	assert_eq(affected, [] as Array[Unit], "no units in radius: cooking off must still run cleanly")
