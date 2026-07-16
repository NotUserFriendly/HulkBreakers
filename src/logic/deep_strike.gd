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
	leg.sockets = [Socket.new(&"ARMOR", Transform3D(Basis(), Vector3(0.0, -0.45, 0.09)), &"ARMOR")]

	# Plates are FACINGS, not shells (docs/01): a thin box on one face of
	# their parent, authored part-local at the part's own origin — the
	# hosting ARMOR socket's transform is what actually places them.
	var torso_plate_front := Part.new()
	torso_plate_front.id = &"torso_plate_front"
	torso_plate_front.hp = 8
	torso_plate_front.max_hp = 8
	torso_plate_front.mass = 4.0
	torso_plate_front.attaches_to = [&"ARMOR"]
	torso_plate_front.material = &"steel"
	torso_plate_front.volume = [Box.new(Vector3.ZERO, Vector3(0.54, 0.66, 0.05))]

	var torso_plate_rear := Part.new()
	torso_plate_rear.id = &"torso_plate_rear"
	torso_plate_rear.hp = 5
	torso_plate_rear.max_hp = 5
	torso_plate_rear.mass = 2.0
	torso_plate_rear.attaches_to = [&"ARMOR"]
	torso_plate_rear.material = &"sheet_steel"
	torso_plate_rear.volume = [Box.new(Vector3.ZERO, Vector3(0.54, 0.66, 0.03))]

	var head_plate := Part.new()
	head_plate.id = &"head_plate"
	head_plate.hp = 4
	head_plate.max_hp = 4
	head_plate.mass = 1.0
	head_plate.attaches_to = [&"ARMOR"]
	head_plate.material = &"ceramic"
	head_plate.volume = [Box.new(Vector3.ZERO, Vector3(0.24, 0.20, 0.04))]

	# Shared by both the arm's own ARMOR socket and its forearm's (docs/01):
	# one template, reused wherever an ARMOR socket wants arm-tier plating.
	var arm_plate := Part.new()
	arm_plate.id = &"arm_plate"
	arm_plate.hp = 4
	arm_plate.max_hp = 4
	arm_plate.mass = 1.5
	arm_plate.attaches_to = [&"ARMOR"]
	arm_plate.material = &"steel"
	arm_plate.volume = [Box.new(Vector3.ZERO, Vector3(0.16, 0.30, 0.04))]

	var leg_plate := Part.new()
	leg_plate.id = &"leg_plate"
	leg_plate.hp = 5
	leg_plate.max_hp = 5
	leg_plate.mass = 2.0
	leg_plate.attaches_to = [&"ARMOR"]
	leg_plate.material = &"sheet_steel"
	leg_plate.volume = [Box.new(Vector3.ZERO, Vector3(0.18, 0.70, 0.04))]

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
		torso_plate_front,
		torso_plate_rear,
		head_plate,
		arm_plate,
		leg_plate,
		ammo_rack,
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
					Mount.new(&"ARMOR", &"arm_plate"),
					Mount.new(
						&"FOREARM",
						&"forearm",
						[Mount.new(&"ARMOR", &"arm_plate"), Mount.new(&"WRIST", hand_part_id)]
					),
				]
			)
		)
	var leg_mount := func(hip_id: StringName) -> Mount:
		return Mount.new(hip_id, &"leg", [Mount.new(&"ARMOR", &"leg_plate")])

	return (
		ShellTemplate
		. new(
			&"torso",
			[
				Mount.new(&"NECK", &"head", [Mount.new(&"ARMOR", &"head_plate")]),
				arm_mount.call(&"SHOULDER_L", &"hand_l"),
				arm_mount.call(&"SHOULDER_R", &"hand_r"),
				leg_mount.call(&"HIP_L"),
				leg_mount.call(&"HIP_R"),
				Mount.new(&"ARMOR_FRONT", &"torso_plate_front"),
				Mount.new(&"ARMOR_REAR", &"torso_plate_rear"),
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
