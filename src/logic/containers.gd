class_name Containers
extends RefCounted

## docs/05 taskblock04 D: "cover could be a pile of metal scrap... containers
## are a design space, not a ladder." Both attach to BACK; neither is an
## upgrade of the other — they're better at DIFFERENT things (D1's own
## table), not ranked. Do not add a third that's just a bigger number.

const BACKPACK_MAX_BULK := 40.0
const TRASH_BARREL_MAX_BULK := 110.0


## Soft: swells with what's actually inside it (Inventory.external_bulk) —
## nearly free packed light, at capacity full. The better mass discount
## (0.5) of the two, at the cost of never holding as much.
static func backpack() -> Part:
	var part := Part.new()
	part.id = &"backpack"
	part.display_name = "Backpack"
	part.attaches_to = [&"BACK"]
	part.material = &"hull_plate"
	part.hp = 4
	part.max_hp = 4
	part.mass = 0.8
	part.volume = [Box.new(Vector3(0.0, 0.0, -0.15), Vector3(0.35, 0.5, 0.2))]
	part.is_container = true
	part.rigid = false
	part.bulk = 2.0
	part.max_bulk = BACKPACK_MAX_BULK
	part.mass_multiplier = 0.5
	return part


## Rigid: docs/00's "Jerry with an empty barrel on his back" — a fixed
## 110L drum whether it's empty or full (Inventory.external_bulk). Holds
## far more than a backpack, at the D1 discount floor (0.8) rather than a
## backpack's better one.
static func trash_barrel() -> Part:
	var part := Part.new()
	part.id = &"trash_barrel"
	part.display_name = "Trash Barrel"
	part.attaches_to = [&"BACK"]
	part.material = &"sheet_steel"
	part.hp = 6
	part.max_hp = 6
	part.mass = 3.0
	part.volume = [Box.new(Vector3(0.0, 0.0, -0.2), Vector3(0.5, 0.7, 0.5))]
	part.is_container = true
	part.rigid = true
	part.bulk = TRASH_BARREL_MAX_BULK
	part.max_bulk = TRASH_BARREL_MAX_BULK
	part.mass_multiplier = 0.8
	return part
