class_name DeepStrike
extends RefCounted

## docs/00/04/07: matrices fired in as a missile, assembled from whatever
## frames/parts the hulk happens to have — zero loadout control. Pulled
## forward deliberately as the project's stress test: it forces randomized
## socket assembly through the whole stack, and anything malformed
## (crashes, dangling sockets, an unresolvable shot plane) surfaces here
## instead of three months from now.

const MAX_DEPTH := 6
## Not every free socket fills — a scrap-heap assembly is allowed to be
## incomplete. A flagged, tunable placeholder, not a design decision.
const EMPTY_SOCKET_CHANCE := 0.15
## Prototype-scope defaults for a randomly assembled shell (docs/07 owns
## the real economy) — generous enough that a random pool of small parts
## essentially never blows the budget, so mass/RAM violations mean a real
## bug, not an expected fuzz outcome.
const DEFAULT_MAX_MASS := 500.0
const DEFAULT_MAX_RAM := 50.0


## The reference humanoid's part templates (docs/01 "The Reference
## Humanoid"): a real body shape, not a shapeless placeholder — legs low,
## torso mid, head high, plates as thin facings on one side of their
## parent, never a shell. Every part carries a real material (docs/10:
## no pool part may have `material == ""`) and a part-local volume, so a
## random deep-struck assembly is never a floating torso and its plates
## are never bare structure wearing nothing.
static func default_part_pool() -> Array[Part]:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 12
	torso.max_hp = 12
	torso.mass = 20.0
	torso.ram_cost = 5.0
	torso.tags = [&"ROOT"]
	torso.material = &"artificial_bone"
	# docs/01a's socket transforms are authored relative to the torso's own
	# origin, and its own worked example ("legs 0.00-0.90, torso 0.90-1.60")
	# only holds if that origin sits at world y=1.25 — but the torso is the
	# shell ROOT, and UnitGeometry places a root at exactly the unit's cell
	# height (y=0) with no separate "standing height" concept. ROOT_ELEVATION
	# bridges that gap: leg height (0.90) + the HIP socket's own drop below
	# torso's origin (0.35) = 1.25, derived from docs/01a's own numbers, not
	# invented — bake it into torso's volume and every socket torso itself
	# hosts so the composed skeleton actually stands with its feet at y=0
	# instead of a copy of the pre-Phase-12.0/1a "legs below the floor" bug.
	const ROOT_ELEVATION := 1.25
	torso.volume = [Box.new(Vector3(0.0, ROOT_ELEVATION, 0.0), Vector3(0.50, 0.70, 0.28))]
	# Every socket that could collide with a same-typed sibling on this same
	# part gets its own id (docs/01 taskblock02 Pass B) — ARMOR_FRONT vs.
	# ARMOR_REAR, SHOULDER_L vs. SHOULDER_R, HIP_L vs. HIP_R — so an
	# assembler targets exactly one by `PartGraph.find_socket`, never
	# "whichever is free first." Reversing this array changes nothing about
	# where anything lands.
	torso.sockets = [
		Socket.new(
			&"ARMOR", Transform3D(Basis(), Vector3(0.0, ROOT_ELEVATION, 0.15)), &"ARMOR_FRONT"
		),
		Socket.new(
			&"ARMOR", Transform3D(Basis(), Vector3(0.0, ROOT_ELEVATION, -0.15)), &"ARMOR_REAR"
		),
		Socket.new(
			&"SHOULDER",
			Transform3D(Basis(), Vector3(-0.31, ROOT_ELEVATION + 0.28, 0.0)),
			&"SHOULDER_L"
		),
		Socket.new(
			&"SHOULDER",
			Transform3D(Basis(), Vector3(0.31, ROOT_ELEVATION + 0.28, 0.0)),
			&"SHOULDER_R"
		),
		Socket.new(
			&"HIP", Transform3D(Basis(), Vector3(-0.14, ROOT_ELEVATION - 0.35, 0.0)), &"HIP_L"
		),
		Socket.new(
			&"HIP", Transform3D(Basis(), Vector3(0.14, ROOT_ELEVATION - 0.35, 0.0)), &"HIP_R"
		),
		Socket.new(
			&"NECK", Transform3D(Basis(), Vector3(0.0, ROOT_ELEVATION + 0.40, 0.0)), &"NECK"
		),
		Socket.new(
			&"BACK", Transform3D(Basis(), Vector3(0.0, ROOT_ELEVATION + 0.05, -0.17)), &"BACK"
		),
		Socket.new(&"MATRIX", Transform3D.IDENTITY, &"MATRIX"),
		# Cladding vs. plates (docs/01 taskblock02 Pass C): the skin layer a
		# part is FOUND wearing, hugging every face at once. Same pattern as
		# a plate's ARMOR socket: the socket carries the part's own local
		# volume-center offset, and the cladding part's own box is authored
		# at local zero — it wraps the part's own position rather than
		# standing off one face.
		#
		# docs/10 taskblock05 D1: keyed by kind of part — a leg's skin does
		# not fit a skull. CLADDING_TORSO here, CLADDING_HEAD/_ARM/_FOREARM/
		# _LEG below, each attaches_to only its own kind (open StringNames,
		# one row each, no code — the socket's own `id` stays plain
		# `&"CLADDING"`, since Mount targets sockets by id, never type, and
		# there's only ever one cladding socket per part to disambiguate).
		Socket.new(
			&"CLADDING_TORSO", Transform3D(Basis(), Vector3(0.0, ROOT_ELEVATION, 0.0)), &"CLADDING"
		),
	]

	var head := Part.new()
	head.id = &"head"
	head.hp = 6
	head.max_hp = 6
	head.mass = 3.0
	head.ram_cost = 1.0
	head.attaches_to = [&"NECK"]
	head.material = &"artificial_bone"
	head.volume = [Box.new(Vector3(0.0, 0.12, 0.0), Vector3(0.22, 0.24, 0.22))]
	head.sockets = [
		Socket.new(&"ARMOR", Transform3D(Basis(), Vector3(0.0, 0.12, 0.12)), &"ARMOR"),
		Socket.new(&"MATRIX", Transform3D.IDENTITY, &"MATRIX"),
		Socket.new(&"CLADDING_HEAD", Transform3D(Basis(), Vector3(0.0, 0.12, 0.0)), &"CLADDING"),
	]

	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 6
	arm.max_hp = 6
	arm.mass = 3.0
	arm.attaches_to = [&"SHOULDER"]
	arm.material = &"artificial_bone"
	arm.volume = [Box.new(Vector3(0.0, -0.17, 0.0), Vector3(0.14, 0.34, 0.14))]
	arm.sockets = [
		Socket.new(&"ARMOR", Transform3D(Basis(), Vector3(0.0, -0.17, 0.09)), &"ARMOR"),
		Socket.new(&"FOREARM", Transform3D(Basis(), Vector3(0.0, -0.34, 0.0)), &"FOREARM"),
		Socket.new(&"CLADDING_ARM", Transform3D(Basis(), Vector3(0.0, -0.17, 0.0)), &"CLADDING"),
	]

	var forearm := Part.new()
	forearm.id = &"forearm"
	forearm.hp = 5
	forearm.max_hp = 5
	forearm.mass = 2.5
	forearm.attaches_to = [&"FOREARM"]
	forearm.material = &"artificial_bone"
	forearm.volume = [Box.new(Vector3(0.0, -0.17, 0.0), Vector3(0.12, 0.34, 0.12))]
	forearm.sockets = [
		Socket.new(&"ARMOR", Transform3D(Basis(), Vector3(0.0, -0.17, 0.08)), &"ARMOR"),
		# FOREARM_TOOL (docs/01: folding_sword etc.) is open vocabulary with no
		# authored occupant yet — left unfilled, not a gap to force content into.
		Socket.new(
			&"FOREARM_TOOL", Transform3D(Basis(), Vector3(0.0, -0.17, 0.09)), &"FOREARM_TOOL"
		),
		Socket.new(&"WRIST", Transform3D(Basis(), Vector3(0.0, -0.34, 0.0)), &"WRIST"),
		Socket.new(
			&"CLADDING_FOREARM", Transform3D(Basis(), Vector3(0.0, -0.17, 0.0)), &"CLADDING"
		),
	]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.mass = 1.0
	hand.ram_cost = 1.0
	hand.attaches_to = [&"WRIST"]
	hand.capabilities = [&"TRIGGER", &"GRIP", &"POWER"]
	hand.material = &"artificial_muscle"
	hand.volume = [Box.new(Vector3(0.0, -0.05, 0.0), Vector3(0.10, 0.10, 0.10))]
	hand.sockets = [Socket.new(&"GRIP", Transform3D(Basis(), Vector3(0.0, -0.05, 0.08)), &"GRIP")]

	# docs/01's own worked example: a saw REPLACES the hand at the wrist
	# (hand replacement is emergent, not an arm-level special case) — it
	# advertises SUPPORT but no TRIGGER/GRIP/POWER, so a rifle still fires
	# with one good hand and one saw, but a pistol or sword cannot.
	var saw_hand := Part.new()
	saw_hand.id = &"saw_hand"
	saw_hand.hp = 4
	saw_hand.max_hp = 4
	saw_hand.mass = 1.2
	saw_hand.attaches_to = [&"WRIST"]
	saw_hand.capabilities = [&"SUPPORT"]
	saw_hand.material = &"artificial_muscle"
	saw_hand.volume = [Box.new(Vector3(0.0, -0.05, 0.0), Vector3(0.10, 0.10, 0.10))]

	var leg := Part.new()
	leg.id = &"leg"
	leg.hp = 6
	leg.max_hp = 6
	leg.mass = 6.0
	leg.attaches_to = [&"HIP"]
	leg.material = &"artificial_bone"
	leg.volume = [Box.new(Vector3(0.0, -0.45, 0.0), Vector3(0.16, 0.90, 0.16))]
	leg.sockets = [
		Socket.new(&"ARMOR", Transform3D(Basis(), Vector3(0.0, -0.45, 0.09)), &"ARMOR"),
		# Y-shifted up by half the cladding's own padding (0.015): the leg is
		# the one floor-contact limb, so its cladding's extra 0.03 of height
		# goes entirely upward — the sole stays flush with y=0 instead of
		# clipping through the floor the way a symmetric pad would.
		Socket.new(&"CLADDING_LEG", Transform3D(Basis(), Vector3(0.0, -0.435, 0.0)), &"CLADDING"),
	]

	# Plates are FACINGS, not shells (docs/01): a thin box on one face of
	# their parent, authored part-local at the part's own origin — the
	# hosting ARMOR socket's transform is what actually places them.
	#
	# docs/10 taskblock05 D2: plates keep the generic ARMOR socket (any
	# plate legally attaches to any ARMOR socket — a big plate on a head is
	# legal, looks absurd, and that's correct), so naming them after a body
	# part implied a constraint the design doesn't have. Renamed by what
	# actually varies: size (small/medium/large, by footprint) and
	# material — the old front/rear torso split falls out of that for
	# free, since they already differ in material.
	var plate_large_steel := Part.new()
	plate_large_steel.id = &"plate_large_steel"
	plate_large_steel.hp = 8
	plate_large_steel.max_hp = 8
	plate_large_steel.mass = 4.0
	plate_large_steel.attaches_to = [&"ARMOR"]
	plate_large_steel.material = &"steel"
	plate_large_steel.volume = [Box.new(Vector3.ZERO, Vector3(0.54, 0.66, 0.05))]

	var plate_large_sheet_steel := Part.new()
	plate_large_sheet_steel.id = &"plate_large_sheet_steel"
	plate_large_sheet_steel.hp = 5
	plate_large_sheet_steel.max_hp = 5
	plate_large_sheet_steel.mass = 2.0
	plate_large_sheet_steel.attaches_to = [&"ARMOR"]
	plate_large_sheet_steel.material = &"sheet_steel"
	plate_large_sheet_steel.volume = [Box.new(Vector3.ZERO, Vector3(0.54, 0.66, 0.03))]

	var plate_small_ceramic := Part.new()
	plate_small_ceramic.id = &"plate_small_ceramic"
	plate_small_ceramic.hp = 4
	plate_small_ceramic.max_hp = 4
	plate_small_ceramic.mass = 1.0
	plate_small_ceramic.attaches_to = [&"ARMOR"]
	plate_small_ceramic.material = &"ceramic"
	plate_small_ceramic.volume = [Box.new(Vector3.ZERO, Vector3(0.24, 0.20, 0.04))]

	# Shared by both the arm's own ARMOR socket and its forearm's (docs/01):
	# one template, reused wherever an ARMOR socket wants arm-tier plating.
	var plate_small_steel := Part.new()
	plate_small_steel.id = &"plate_small_steel"
	plate_small_steel.hp = 4
	plate_small_steel.max_hp = 4
	plate_small_steel.mass = 1.5
	plate_small_steel.attaches_to = [&"ARMOR"]
	plate_small_steel.material = &"steel"
	plate_small_steel.volume = [Box.new(Vector3.ZERO, Vector3(0.16, 0.30, 0.04))]

	var plate_medium_sheet_steel := Part.new()
	plate_medium_sheet_steel.id = &"plate_medium_sheet_steel"
	plate_medium_sheet_steel.hp = 5
	plate_medium_sheet_steel.max_hp = 5
	plate_medium_sheet_steel.mass = 2.0
	plate_medium_sheet_steel.attaches_to = [&"ARMOR"]
	plate_medium_sheet_steel.material = &"sheet_steel"
	plate_medium_sheet_steel.volume = [Box.new(Vector3.ZERO, Vector3(0.18, 0.70, 0.04))]

	# Cladding vs. plates (docs/01 taskblock02 Pass C): the skin layer a
	# part is FOUND wearing, not bolted-on armor — a thin shell hugging
	# EVERY face at once (docs/01: civilian sheet metal vs. combat ceramic),
	# so it's the frontmost thing on an unplated face and sits directly
	# behind a plate on a plated one. Each one's box is the same center as
	# its bare part's own volume, padded +0.015 on every axis — attached via
	# an identity-transform CLADDING socket (it wraps the part's own
	# position; nothing pushes it out to one face the way a plate's ARMOR
	# socket does). Pre-attached in the ShellTemplate, never a Loadout
	# choice: "the arm you found is already plated" is structure.
	var torso_cladding := Part.new()
	torso_cladding.id = &"torso_cladding"
	torso_cladding.hp = 6
	torso_cladding.max_hp = 6
	torso_cladding.mass = 3.0
	torso_cladding.attaches_to = [&"CLADDING_TORSO"]
	torso_cladding.material = &"sheet_steel"
	torso_cladding.volume = [Box.new(Vector3.ZERO, Vector3(0.53, 0.73, 0.31))]

	var head_cladding := Part.new()
	head_cladding.id = &"head_cladding"
	head_cladding.hp = 3
	head_cladding.max_hp = 3
	head_cladding.mass = 0.5
	head_cladding.attaches_to = [&"CLADDING_HEAD"]
	head_cladding.material = &"sheet_steel"
	head_cladding.volume = [Box.new(Vector3.ZERO, Vector3(0.25, 0.27, 0.25))]

	var arm_cladding := Part.new()
	arm_cladding.id = &"arm_cladding"
	arm_cladding.hp = 3
	arm_cladding.max_hp = 3
	arm_cladding.mass = 1.0
	arm_cladding.attaches_to = [&"CLADDING_ARM"]
	arm_cladding.material = &"sheet_steel"
	arm_cladding.volume = [Box.new(Vector3.ZERO, Vector3(0.17, 0.37, 0.17))]

	var forearm_cladding := Part.new()
	forearm_cladding.id = &"forearm_cladding"
	forearm_cladding.hp = 3
	forearm_cladding.max_hp = 3
	forearm_cladding.mass = 0.8
	forearm_cladding.attaches_to = [&"CLADDING_FOREARM"]
	forearm_cladding.material = &"sheet_steel"
	forearm_cladding.volume = [Box.new(Vector3.ZERO, Vector3(0.15, 0.37, 0.15))]

	var leg_cladding := Part.new()
	leg_cladding.id = &"leg_cladding"
	leg_cladding.hp = 4
	leg_cladding.max_hp = 4
	leg_cladding.mass = 1.5
	leg_cladding.attaches_to = [&"CLADDING_LEG"]
	leg_cladding.material = &"sheet_steel"
	leg_cladding.volume = [Box.new(Vector3.ZERO, Vector3(0.19, 0.93, 0.19))]

	# docs/01a: the BACK socket's own worked example — cook off a flanked
	# ammo rack (docs/03), or carry a backpack/body there instead.
	# cook_off_damage/radius are flagged placeholders, not tuned design —
	# ask before changing.
	var ammo_rack := Part.new()
	ammo_rack.id = &"ammo_rack"
	ammo_rack.hp = 4
	ammo_rack.max_hp = 4
	ammo_rack.mass = 3.0
	ammo_rack.attaches_to = [&"BACK"]
	ammo_rack.material = &"sheet_steel"
	ammo_rack.tags = [&"VOLATILE"]
	ammo_rack.cook_off_damage = 5.0
	ammo_rack.cook_off_radius = 2.0
	ammo_rack.volume = [Box.new(Vector3.ZERO, Vector3(0.20, 0.30, 0.10))]

	# docs/04 taskblock02 Pass D4: the power hook. POWER_SOURCE is what
	# Shell.is_powered() looks for; VOLATILE means shooting it out also
	# cooks off — killing a docked surrogate's life support and starting a
	# fire in the same shot, from one tag each, not two systems to keep in
	# sync. cook_off numbers are the same flagged placeholder as ammo_rack's.
	var reactor := Part.new()
	reactor.id = &"reactor"
	reactor.hp = 5
	reactor.max_hp = 5
	reactor.mass = 4.0
	reactor.attaches_to = [&"BACK"]
	reactor.material = &"sheet_steel"
	reactor.tags = [&"POWER_SOURCE", &"VOLATILE"]
	reactor.cook_off_damage = 6.0
	reactor.cook_off_radius = 2.0
	reactor.volume = [Box.new(Vector3.ZERO, Vector3(0.18, 0.26, 0.10))]

	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.mass = 1.5
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.material = &"steel"
	pistol.damage = 4.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0), Ring.new(0.5, 2.0)]
	pistol.volume = [Box.new(Vector3(0.0, 0.0, 0.2), Vector3(0.1, 0.2, 0.4))]

	var rifle := Part.new()
	rifle.id = &"rifle"
	rifle.hp = 4
	rifle.max_hp = 4
	rifle.mass = 3.0
	rifle.attaches_to = [&"GRIP"]
	rifle.requires = {&"TRIGGER": 1, &"SUPPORT": 1}
	rifle.material = &"steel"
	rifle.damage = 6.0
	rifle.ap_cost = 2
	rifle.scatter = [Ring.new(0.05, 1.0), Ring.new(0.3, 1.5)]
	rifle.volume = [Box.new(Vector3(0.0, 0.0, 0.3), Vector3(0.12, 0.15, 0.7))]

	var two_handed_sword := Part.new()
	two_handed_sword.id = &"two_handed_sword"
	two_handed_sword.hp = 5
	two_handed_sword.max_hp = 5
	two_handed_sword.mass = 4.0
	two_handed_sword.attaches_to = [&"GRIP"]
	two_handed_sword.requires = {&"GRIP": 1, &"POWER": 1}
	two_handed_sword.material = &"steel"
	two_handed_sword.damage = 8.0
	two_handed_sword.ap_cost = 2
	two_handed_sword.scatter = [Ring.new(0.2, 1.0)]
	two_handed_sword.volume = [Box.new(Vector3(0.0, 0.0, 0.35), Vector3(0.1, 0.1, 1.0))]

	return [
		torso,
		head,
		arm,
		forearm,
		hand,
		saw_hand,
		leg,
		plate_large_steel,
		plate_large_sheet_steel,
		plate_small_ceramic,
		plate_small_steel,
		plate_medium_sheet_steel,
		torso_cladding,
		head_cladding,
		arm_cladding,
		forearm_cladding,
		leg_cladding,
		ammo_rack,
		reactor,
		pistol,
		rifle,
		two_handed_sword,
	]


## Fires `base_matrix` into a random shell drawn from `part_pool`: picks a
## ROOT-tagged template to host it, then fills free sockets recursively
## with whatever templates fit, some left empty (a real scrap-heap landing
## doesn't guarantee a complete body). All randomness draws from `rng`.
static func assemble_random(
	base_matrix: Matrix,
	tier_ratio: float,
	part_pool: Array[Part],
	rng: RandomNumberGenerator,
	cell: Vector2i,
	squad_id: int = 0
) -> Unit:
	var link := Matrix.new()
	link.id = StringName("link_%d" % rng.randi())
	link.base = base_matrix
	link.tier_ratio = tier_ratio

	var roots: Array[Part] = []
	for template: Part in part_pool:
		if &"ROOT" in template.tags:
			roots.append(template)
	var root: Part = (roots[rng.randi() % roots.size()] as Part).duplicate(true)
	# Not a silent fallback: if the chosen root has no MATRIX socket, docking
	# fails and validate_assembly() below flags it as a violation instead.
	root.dock_matrix(link)

	_fill_sockets(root, part_pool, rng, 0)

	var shell := Shell.new(root)
	shell.max_mass = DEFAULT_MAX_MASS
	shell.max_ram = DEFAULT_MAX_RAM
	return Unit.new(link, shell, cell, squad_id)


static func _fill_sockets(
	part: Part, pool: Array[Part], rng: RandomNumberGenerator, depth: int
) -> void:
	if depth >= MAX_DEPTH:
		return
	for socket: Socket in part.sockets:
		if socket.occupant != null:
			continue
		if rng.randf() < EMPTY_SOCKET_CHANCE:
			continue
		var candidates: Array[Part] = []
		for template: Part in pool:
			if socket.socket_type in template.attaches_to:
				candidates.append(template)
		if candidates.is_empty():
			continue
		var chosen: Part = (candidates[rng.randi() % candidates.size()] as Part).duplicate(true)
		socket.occupant = chosen
		_fill_sockets(chosen, pool, rng, depth + 1)


## The reference humanoid's fixed skeleton (docs/01 "The Reference
## Humanoid"), as data: every Mount is exact — `find_socket` by id, never
## "whichever ARMOR socket is free first" — so both arms, both legs, both
## plates, head, head plate, and the back-mounted ammo rack always land
## exactly where docs/01 says, regardless of pool declaration order.
## GRIP is deliberately left unmounted here: which weapon (if any) sits in
## each hand is `default_loadout()`'s job, not the skeleton's, so a second
## armament is a second `Loadout`, not a second template.
static func reference_humanoid_template() -> ShellTemplate:
	var arm_mount := func(shoulder_id: StringName, hand_part_id: StringName) -> Mount:
		return (
			Mount
			. new(
				shoulder_id,
				&"arm",
				[
					Mount.new(&"ARMOR", &"plate_small_steel"),
					Mount.new(&"CLADDING", &"arm_cladding"),
					(
						Mount
						. new(
							&"FOREARM",
							&"forearm",
							[
								Mount.new(&"ARMOR", &"plate_small_steel"),
								Mount.new(&"CLADDING", &"forearm_cladding"),
								Mount.new(&"WRIST", hand_part_id),
							]
						)
					),
				]
			)
		)
	var leg_mount := func(hip_id: StringName) -> Mount:
		return Mount.new(
			hip_id,
			&"leg",
			[
				Mount.new(&"ARMOR", &"plate_medium_sheet_steel"),
				Mount.new(&"CLADDING", &"leg_cladding")
			]
		)

	return (
		ShellTemplate
		. new(
			&"torso",
			[
				(
					Mount
					. new(
						&"NECK",
						&"head",
						[
							Mount.new(&"ARMOR", &"plate_small_ceramic"),
							Mount.new(&"CLADDING", &"head_cladding"),
						]
					)
				),
				arm_mount.call(&"SHOULDER_L", &"hand_l"),
				arm_mount.call(&"SHOULDER_R", &"hand_r"),
				leg_mount.call(&"HIP_L"),
				leg_mount.call(&"HIP_R"),
				Mount.new(&"ARMOR_FRONT", &"plate_large_steel"),
				Mount.new(&"ARMOR_REAR", &"plate_large_sheet_steel"),
				Mount.new(&"CLADDING", &"torso_cladding"),
				Mount.new(&"BACK", &"ammo_rack"),
			],
			DEFAULT_MAX_MASS,
			DEFAULT_MAX_RAM
		)
	)


## A pistol in each hand — docs/01's "known-good, fully armed" default.
## `GRIP_L`/`GRIP_R` (not a bare `GRIP` shared by both hands) is exactly why
## `hand_l`/`hand_r` exist as distinct pool ids: a flat Loadout can't
## otherwise address "the left hand's grip" independently of the right's.
static func default_loadout() -> Loadout:
	return Loadout.new({&"GRIP_L": &"pistol", &"GRIP_R": &"pistol"})


## `default_part_pool()` plus `hand_l`/`hand_r`: the same `hand` template,
## split into two so their GRIP sockets carry distinct ids — needed only for
## `Loadout`-addressed assembly (`reference_humanoid_template`), so kept out
## of the shared pool `assemble_random` scavenges from (which is blind to
## socket ids and would only be diluted by two extra near-duplicates).
static func _reference_humanoid_pool() -> Dictionary:
	var pool: Dictionary = {}
	for template: Part in default_part_pool():
		pool[template.id] = template

	var hand_l: Part = (pool[&"hand"] as Part).duplicate(true)
	hand_l.id = &"hand_l"
	hand_l.sockets[0].id = &"GRIP_L"
	pool[&"hand_l"] = hand_l

	var hand_r: Part = (pool[&"hand"] as Part).duplicate(true)
	hand_r.id = &"hand_r"
	hand_r.sockets[0].id = &"GRIP_R"
	pool[&"hand_r"] = hand_r

	return pool


## The complete, deterministic reference humanoid — no randomness anywhere.
## Distinct from assemble_random's "scrap-heap landing," which is allowed
## to be incomplete: body-shape-driven mechanics (cover masking, flanking,
## armor-as-facings) can't be tested against a shapeless or partial body,
## so this is the known-good one they're tested against. A thin convenience
## over `BodyAssembler` — the actual structure lives in
## `reference_humanoid_template()`/`default_loadout()`, not here.
static func assemble_reference_humanoid(matrix: Matrix, cell: Vector2i, squad_id: int = 0) -> Unit:
	return BodyAssembler.assemble(
		reference_humanoid_template(),
		default_loadout(),
		_reference_humanoid_pool(),
		matrix,
		cell,
		squad_id
	)


## Socket/mass/RAM/bulk invariants (Phase 7 fuzz test): every violation
## found, or an empty array if the assembly is sound.
static func validate_assembly(unit: Unit) -> Array[String]:
	var violations: Array[String] = []

	var mass: float = unit.shell.carried_mass()
	if mass > unit.shell.max_mass:
		violations.append("mass %.1f exceeds max_mass %.1f" % [mass, unit.shell.max_mass])

	var ram: float = unit.shell.total_ram()
	if ram > unit.shell.max_ram:
		violations.append("ram %.1f exceeds max_ram %.1f" % [ram, unit.shell.max_ram])

	for part: Part in unit.shell.all_parts():
		if not part.is_container:
			continue
		var direct_bulk: float = 0.0
		for child: Part in part.contents:
			direct_bulk += child.bulk
		if direct_bulk > part.max_bulk:
			violations.append(
				"%s: bulk %.1f exceeds max_bulk %.1f" % [part.id, direct_bulk, part.max_bulk]
			)

	# A living part with no geometry can't be hit — it's invisible to the
	# shot plane, not armored.
	for part: Part in unit.shell.living_parts():
		if part.volume.is_empty():
			violations.append(
				"%s: hp > 0 with no volume, cannot appear in the shot plane" % part.id
			)
		# docs/10: material color is data, and an empty material can't be
		# looked up — the same class of violation as a missing volume.
		if part.material == &"":
			violations.append("%s: hp > 0 with no material, cannot be colored or armored" % part.id)

	if not (unit.shell.root.hosts_matrix() and unit.shell.root.hosted_matrix != null):
		violations.append("root part must host the deep-struck matrix")

	return violations


## The first living, damage-dealing part that can actually be fired given
## the rest of the assembly's manipulators (docs/01 capability matching), or
## null if none can — the same check the aim UI (docs/10 Phase 12.3) uses to
## pick what a confirmed shot actually fires.
static func find_operable_weapon(unit: Unit) -> Part:
	var living: Array[Part] = unit.shell.living_parts()
	for weapon: Part in living:
		if weapon.damage <= 0.0:
			continue
		var manipulators: Array[Part] = []
		for part: Part in living:
			if part != weapon:
				manipulators.append(part)
		if PartGraph.can_operate(weapon, manipulators):
			return weapon
	return null


## True if some living, damage-dealing part can actually be fired given
## the rest of the assembly's manipulators — never a crash, always a
## definite yes/no.
static func is_armed(unit: Unit) -> bool:
	return find_operable_weapon(unit) != null
