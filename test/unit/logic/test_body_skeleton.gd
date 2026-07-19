extends GutTest

## taskblock-20 Pass A: "the torso is a skeleton, not a solid box." The
## real torso.tres (tools/author_taskblock20_skeleton.gd) — a thin strut
## skeleton (spine, shoulder brace, hip brace) replacing the old single
## solid box that hid the reactor/matrix behind geometry instead of
## behind cladding. Every claim here is read off the real, composed
## ShotPlane geometry (CLAUDE.md: never re-derive a second copy of the
## same formula on paper) — a live probe confirmed each fixture's own
## numbers before this file was written.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## A real torso, reactor mounted at its own BACK socket, cladding at its
## own CLADDING_TORSO socket — the exact "internals already exist,
## already socketed" state Pass A's own header describes.
func _armored_torso() -> Dictionary:
	var torso: Part = DataLibrary.get_part(&"torso")
	var reactor: Part = DataLibrary.get_part(&"reactor")
	var cladding: Part = DataLibrary.get_part(&"torso_cladding")
	PartGraph.attach(reactor, torso, PartGraph.find_free_socket(torso, &"BACK"))
	PartGraph.attach(cladding, torso, PartGraph.find_free_socket(torso, &"CLADDING_TORSO"))
	return {"torso": torso, "reactor": reactor, "cladding": cladding}


## Shooting from the FRONT (the ARMOR_FRONT/cladding side) — the
## direction "internals sit behind cladding" is actually meaningful for;
## the reactor's own BACK-socket placement pokes slightly past
## cladding's own rear coverage, so a shot from directly behind finds it
## already exposed regardless — a pre-existing mounting detail, not
## something this pass touches.
func _front_shot_plane(state: CombatState) -> Array[Region]:
	return ShotPlane.build(Vector2(0, 1), Vector2(0, -1), state)


func test_the_torso_is_a_real_strut_skeleton_not_one_solid_box() -> void:
	var torso: Part = DataLibrary.get_part(&"torso")

	assert_gt(torso.volume.size(), 1, "a real skeleton, several thin struts, never one solid box")
	# "Thin" — the old solid box was 0.5 x 0.7 x 0.28 (volume 0.098); the
	# whole skeleton together must be a small fraction of that.
	var total_volume: float = 0.0
	for box: Box in torso.volume:
		total_volume += box.size.x * box.size.y * box.size.z
	assert_lt(total_volume, 0.098 * 0.25, "thinned to struts, not a re-shaped solid")


## "confirm internals (reactor, matrix socket) mounted in sockets" — the
## sockets (and the organs mounted in them) already existed; Pass A never
## touches the socket graph itself, only the structural volume around it.
func test_reactor_and_matrix_are_mounted_in_real_torso_sockets() -> void:
	var built: Dictionary = _armored_torso()
	var torso: Part = built.torso

	assert_not_null(PartGraph.find_socket(torso, &"BACK"), "the reactor's own mounting socket")
	assert_not_null(PartGraph.find_socket(torso, &"MATRIX"), "the matrix's own mounting socket")
	var back_socket: Socket = PartGraph.find_socket(torso, &"BACK")
	assert_eq(back_socket.occupant, built.reactor)


## "internals sit in the shot plane behind cladding" — from the front,
## with cladding present, cladding (not the reactor) must be the
## frontmost thing at the reactor's own aim point.
func test_internals_sit_behind_cladding_in_the_shot_plane() -> void:
	var built: Dictionary = _armored_torso()
	var unit := Unit.new(Matrix.new(), Shell.new(built.torso), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var plane: Array[Region] = _front_shot_plane(state)

	var reactor_region: Region = null
	for region: Region in plane:
		if region.part == built.reactor:
			reactor_region = region
	assert_not_null(reactor_region, "sanity: the reactor must actually appear in the plane")

	var hit: Region = ShotPlane.resolve_projectile(plane, reactor_region.rect.get_center())
	assert_eq(hit.part, built.cladding, "cladding occludes the reactor from the front while intact")


## "stripping cladding leaves the skeleton and internals directly
## hittable" — once cladding is gone, a real point within the reactor's
## own footprint (clear of the thin spine strut passing in front of part
## of it — a real, expected, and much narrower occlusion than the old
## solid box's own total block) resolves to the reactor itself.
func test_stripping_cladding_leaves_the_reactor_directly_hittable() -> void:
	var built: Dictionary = _armored_torso()
	built.cladding.hp = 0
	var unit := Unit.new(Matrix.new(), Shell.new(built.torso), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var plane: Array[Region] = _front_shot_plane(state)

	# The reactor's own right edge (x=0.07), clear of the 0.1-wide spine
	# strut (spans x -0.05..0.05) passing through its center — verified
	# live before writing this assertion, not assumed from the box math.
	var hit: Region = ShotPlane.resolve_projectile(plane, Vector2(0.07, 1.3))

	assert_not_null(hit)
	assert_eq(hit.part, built.reactor)


## The torso's own struts themselves must be real, separate, hittable
## regions once cladding is gone — "the ribcage... is visible and
## directly targetable," not just empty space where the box used to be.
func test_the_skeletons_own_struts_are_directly_hittable_once_stripped() -> void:
	var built: Dictionary = _armored_torso()
	built.cladding.hp = 0
	var unit := Unit.new(Matrix.new(), Shell.new(built.torso), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var plane: Array[Region] = _front_shot_plane(state)

	var strut_regions: Array[Region] = []
	for region: Region in plane:
		if region.part == built.torso:
			strut_regions.append(region)
	assert_eq(strut_regions.size(), 3, "spine + shoulder brace + hip brace, each its own region")

	# The spine's own center — must resolve to the torso (the strut
	# itself), not fall through to empty space.
	var hit: Region = ShotPlane.resolve_projectile(plane, Vector2(0.0, 1.25))
	assert_not_null(hit)
	assert_eq(hit.part, built.torso)


## "existing assemblies still build" — DeepStrike's own random assembly
## path (every real combat unit goes through this) must still produce a
## valid, no-error torso every time, skeleton and all.
func test_deep_strike_assembly_still_builds_with_the_new_torso_skeleton() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var pool: Array[Part] = DataLibrary.parts_pool()

	for i in range(10):
		var unit: Unit = DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, Vector2i(0, 0), 0)
		assert_not_null(unit)
		assert_not_null(unit.shell.root)
		var violations: Array[String] = DeepStrike.validate_assembly(unit)
		assert_eq(violations, [] as Array[String], "seed %d must assemble with no violations" % i)
