extends GutTest

## taskblock-17 Pass E: structural/assembly checks for the rebuilt wedge/
## half-cylinder plates and the new thigh parts — deflection BEHAVIOR
## (does a wedge's own two faces actually reflect a shot differently, does
## a half-cylinder's own facets span a wide normal range) lives in
## test_ricochet_stress.gd; this file is "does the part tree itself exist
## and assemble the way E1/E2/E3 describe."


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## "Provide a torso-sized wedge — taskblock-13's were small."
func test_a_torso_sized_wedge_exists_and_assembles() -> void:
	var wedge: Part = DataLibrary.get_part(&"wedge_plate_torso")
	assert_not_null(wedge)
	assert_true(&"ARMOR" in wedge.attaches_to, "a wedge plate must still mount through ARMOR")
	assert_eq(wedge.sockets.size(), 2, "a wedge is exactly two angled faces")
	for socket: Socket in wedge.sockets:
		assert_not_null(socket.occupant, "both of the wedge's own faces must ship pre-attached")

	# "torso-sized": each face must actually be bigger than the original,
	# small taskblock-13 wedges (shallow's own face was 0.2 x 0.3).
	var face: Part = wedge.sockets[0].occupant
	assert_gt(face.volume[0].size.x, 0.2)
	assert_gt(face.volume[0].size.y, 0.3)


## "thigh parts exist and assemble" — sized between torso and the small
## limb parts (leg/arm), HIP-attachable like leg, with a real ARMOR
## socket a plate can actually mount into.
func test_thigh_exists_between_torso_and_limb_size_and_assembles_a_plate() -> void:
	var thigh: Part = DataLibrary.get_part(&"thigh")
	var leg: Part = DataLibrary.get_part(&"leg")
	var torso: Part = DataLibrary.get_part(&"torso")
	assert_not_null(thigh)
	assert_true(&"HIP" in thigh.attaches_to, "a thigh must mount the same way a leg does")

	var thigh_volume: float = (
		thigh.volume[0].size.x * thigh.volume[0].size.y * thigh.volume[0].size.z
	)
	var leg_volume: float = leg.volume[0].size.x * leg.volume[0].size.y * leg.volume[0].size.z
	var torso_volume: float = (
		torso.volume[0].size.x * torso.volume[0].size.y * torso.volume[0].size.z
	)
	assert_gt(thigh_volume, leg_volume, "a thigh must be chunkier than a full leg segment")
	assert_lt(thigh_volume, torso_volume, "a thigh must stay well short of torso scale")

	var socket: Socket = PartGraph.find_free_socket(thigh, &"ARMOR")
	assert_not_null(socket, "a thigh needs a real mounting point for the plate tests")
	assert_true(
		PartGraph.attach(DataLibrary.get_part(&"wedge_plate_shallow"), thigh, socket),
		"a real plate must actually mount onto a thigh's own ARMOR socket"
	)


## "The half-cylinder's flat face sits flush with its host (no geometry
## inside the host part)." Mount it on a real torso's own ARMOR_FRONT
## socket and read the composed world position back — every facet's own
## world Z must be at or in FRONT of the mounting socket's own world Z,
## never behind it (taskblock-17's own regression: the first version of
## this authoring pass had the offset sign backwards, receding the arc's
## edges INTO the host instead of flush with it — caught by this exact
## check before it ever shipped).
func test_half_cylinder_plate_sits_flush_with_its_host_never_inside_it() -> void:
	var torso: Part = DataLibrary.get_part(&"torso")
	var socket: Socket = PartGraph.find_socket(torso, &"ARMOR_FRONT")
	assert_true(PartGraph.attach(DataLibrary.get_part(&"half_cylinder_plate"), torso, socket))

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var mount_world_z: float = socket.current_transform().origin.z

	var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)
	var facet_count := 0
	for placement: BoxPlacement in placements:
		if not String(placement.part.id).begins_with("half_cylinder_plate_facet_"):
			continue
		facet_count += 1
		var world_z: float = (placement.transform * placement.box.center).z
		assert_true(
			world_z >= mount_world_z - 0.001,
			(
				"facet %s sits at z=%.4f, behind the mount at z=%.4f (clipping into the host)"
				% [placement.part.id, world_z, mount_world_z]
			)
		)
	assert_eq(facet_count, 5, "every facet must actually be present in the assembled tree")
