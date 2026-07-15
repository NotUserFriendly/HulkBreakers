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
## Prototype-scope defaults for a randomly assembled frame (docs/07 owns
## the real economy) — generous enough that a random pool of small parts
## essentially never blows the budget, so mass/RAM violations mean a real
## bug, not an expected fuzz outcome.
const DEFAULT_MAX_MASS := 500.0
const DEFAULT_MAX_RAM := 50.0


## A modest, prototype-scope pool (docs/04: "skip vat simulation, growth
## time, appearance generation" — content stays utilitarian): one root
## torso, one pair of arm variants (a normal arm and a saw arm), one hand
## variant, one leg, and three weapons spanning the capability rules
## docs/01 calls out (pistol/rifle/two-handed).
static func default_part_pool() -> Array[Part]:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 12
	torso.max_hp = 12
	torso.mass = 20.0
	torso.ram_cost = 5.0
	torso.tags = [&"ROOT"]
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	torso.sockets = [
		Socket.new(&"SHOULDER"), Socket.new(&"SHOULDER"), Socket.new(&"HIP"), Socket.new(&"HIP")
	]

	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 6
	arm.max_hp = 6
	arm.mass = 4.0
	arm.attaches_to = [&"SHOULDER"]
	arm.sockets = [Socket.new(&"WRIST")]

	var saw_arm := Part.new()
	saw_arm.id = &"saw_arm"
	saw_arm.hp = 6
	saw_arm.max_hp = 6
	saw_arm.mass = 5.0
	saw_arm.attaches_to = [&"SHOULDER"]
	saw_arm.capabilities = [&"SUPPORT"]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.mass = 1.0
	hand.ram_cost = 1.0
	hand.attaches_to = [&"WRIST"]
	hand.capabilities = [&"TRIGGER", &"GRIP", &"POWER"]
	hand.sockets = [Socket.new(&"GRIP")]

	var leg := Part.new()
	leg.id = &"leg"
	leg.hp = 6
	leg.max_hp = 6
	leg.mass = 6.0
	leg.attaches_to = [&"HIP"]

	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.mass = 1.5
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 4.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0), Ring.new(0.5, 2.0)]

	var rifle := Part.new()
	rifle.id = &"rifle"
	rifle.hp = 4
	rifle.max_hp = 4
	rifle.mass = 3.0
	rifle.attaches_to = [&"GRIP"]
	rifle.requires = {&"TRIGGER": 1, &"SUPPORT": 1}
	rifle.damage = 6.0
	rifle.ap_cost = 2
	rifle.scatter = [Ring.new(0.05, 1.0), Ring.new(0.3, 1.5)]

	var two_handed_sword := Part.new()
	two_handed_sword.id = &"two_handed_sword"
	two_handed_sword.hp = 5
	two_handed_sword.max_hp = 5
	two_handed_sword.mass = 4.0
	two_handed_sword.attaches_to = [&"GRIP"]
	two_handed_sword.requires = {&"GRIP": 1, &"POWER": 1}
	two_handed_sword.damage = 8.0
	two_handed_sword.ap_cost = 2
	two_handed_sword.scatter = [Ring.new(0.2, 1.0)]

	return [torso, arm, saw_arm, hand, leg, pistol, rifle, two_handed_sword]


## Fires `base_matrix` into a random frame drawn from `part_pool`: picks a
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
	root.hosts_matrix = true
	root.hosted_matrix = link

	_fill_sockets(root, part_pool, rng, 0)

	var frame := Frame.new(root)
	frame.max_mass = DEFAULT_MAX_MASS
	frame.max_ram = DEFAULT_MAX_RAM
	return Unit.new(link, frame, cell, squad_id)


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


## Socket/mass/RAM/bulk invariants (Phase 7 fuzz test): every violation
## found, or an empty array if the assembly is sound.
static func validate_assembly(unit: Unit) -> Array[String]:
	var violations: Array[String] = []

	var mass: float = unit.frame.carried_mass()
	if mass > unit.frame.max_mass:
		violations.append("mass %.1f exceeds max_mass %.1f" % [mass, unit.frame.max_mass])

	var ram: float = unit.frame.total_ram()
	if ram > unit.frame.max_ram:
		violations.append("ram %.1f exceeds max_ram %.1f" % [ram, unit.frame.max_ram])

	for part: Part in unit.frame.all_parts():
		if not part.is_container:
			continue
		var direct_bulk: float = 0.0
		for child: Part in part.contents:
			direct_bulk += child.bulk
		if direct_bulk > part.max_bulk:
			violations.append(
				"%s: bulk %.1f exceeds max_bulk %.1f" % [part.id, direct_bulk, part.max_bulk]
			)

	if not (unit.frame.root.hosts_matrix and unit.frame.root.hosted_matrix != null):
		violations.append("root part must host the deep-struck matrix")

	return violations


## True if some living, damage-dealing part can actually be fired given
## the rest of the assembly's manipulators (docs/01 capability matching) —
## never a crash, always a definite yes/no.
static func is_armed(unit: Unit) -> bool:
	var living: Array[Part] = unit.frame.living_parts()
	for weapon: Part in living:
		if weapon.damage <= 0.0:
			continue
		var manipulators: Array[Part] = []
		for part: Part in living:
			if part != weapon:
				manipulators.append(part)
		if PartGraph.can_operate(weapon, manipulators):
			return true
	return false
