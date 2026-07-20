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
## Humanoid") now live in `res://data/parts/*.tres` (taskblock-10 Pass C) —
## `DataLibrary.parts_pool()` is the read path; this file no longer
## constructs them. Regenerated once by `tools/migrate_data.gd`; that
## script's own header explains why it can't be re-run after this point.


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
				Mount.new(&"LEG_ARMOR", &"plate_medium_sheet_steel"),
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


## `DataLibrary.parts_pool()` plus `hand_l`/`hand_r`: the same `hand`
## template, split into two so their GRIP sockets carry distinct ids —
## needed only for `Loadout`-addressed assembly
## (`reference_humanoid_template`), so kept out of the shared pool
## `assemble_random` scavenges from (which is blind to socket ids and
## would only be diluted by two extra near-duplicates).
static func reference_humanoid_pool() -> Dictionary:
	var pool: Dictionary = {}
	for template: Part in DataLibrary.parts_pool():
		pool[template.id] = template

	var hand_l: Part = (pool[&"hand"] as Part).duplicate(true)
	hand_l.id = &"hand_l"
	hand_l.sockets[0].id = &"GRIP_L"
	pool[&"hand_l"] = hand_l

	var hand_r: Part = (pool[&"hand"] as Part).duplicate(true)
	hand_r.id = &"hand_r"
	hand_r.sockets[0].id = &"GRIP_R"
	pool[&"hand_r"] = hand_r

	# taskblock-17 bot content: leg's own ARMOR socket used to share the
	# bare "ARMOR" id with arm/forearm's — a flat Loadout can't otherwise
	# address "both legs' armor" independently of the arms'. Same fix as
	# hand_l/hand_r above: rename just this pool copy's socket id, never
	# leg.tres itself on disk (nothing outside reference_humanoid
	# assembly reads "leg" through this pool, and both HIP_L/HIP_R mounts
	# share this one renamed copy — legs don't need L/R distinction from
	# each other, only from arms).
	var leg_armored: Part = (pool[&"leg"] as Part).duplicate(true)
	for socket: Socket in leg_armored.sockets:
		if socket.socket_type == &"ARMOR":
			socket.id = &"LEG_ARMOR"
	pool[&"leg"] = leg_armored

	# taskblock-28 Pass B: neither container (docs/05 D1's own two) was ever
	# loadout-addressable on the reference humanoid before this — both are
	# real, already-tested `Part`s (`test_inventory.gd`/`test_shell.gd`),
	# just never reachable through this pool. A kit needs a real container
	# to stock into (BACK's own default Mount occupant, `ammo_rack`, isn't
	# one — it's a `failure_mode == DETONATE` payload, not `is_container`).
	pool[&"backpack"] = Containers.backpack()
	pool[&"trash_barrel"] = Containers.trash_barrel()

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
		reference_humanoid_pool(),
		matrix,
		cell,
		squad_id
	)


## taskblock-14 Pass A2: spawns a NAMED `BotPreset` (a bot profile) at a
## cell/squad, through the same `BodyAssembler` every other assembly path
## uses — no parallel path. Distinct from `assemble_random`'s "scrap-heap
## landing" (a different algorithm on purpose, not rehomed onto
## BodyAssembler either — see that function's own header) and from
## `assemble_reference_humanoid`'s one hardcoded template/loadout: this
## reads BOTH off the preset. `null` if `preset.template_id` doesn't
## resolve (DataValidator._validate_preset already catches this at
## authoring time; this is the runtime mirror of that same check, same
## "never crash, never silently invent" posture every assembly path
## already has).
static func assemble_from_preset(
	preset: BotPreset, matrix: Matrix, cell: Vector2i, squad_id: int = 0
) -> Unit:
	var template: ShellTemplate = ShellTemplates.by_id(preset.template_id)
	if template == null:
		return null
	var unit: Unit = BodyAssembler.assemble(
		template, preset.loadout, reference_humanoid_pool(), matrix, cell, squad_id
	)
	if unit != null:
		unit.pose = Poses.by_id(preset.pose_id)
	return unit


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
