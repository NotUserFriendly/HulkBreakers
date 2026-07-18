class_name LootTable
extends RefCounted

## docs/07: merchant_pool and hulk_pool are mostly exclusive with a
## deliberate small overlap — the handful of designs that have been in
## continuous production for thousands of years. Most of each pool stays
## exclusive; the overlap is a seasoning, not a merge. Stat differences on
## the overlap are explicitly backlog (docs/99: "loot randomization with
## affixes and small stat rolls") — this phase only builds the tagging.

const MERCHANT_SOURCE := &"merchant"
const HULK_SOURCE := &"hulk"


## Manufactured goods you'd expect from a working economy — never found on
## a hulk.
static func merchant_only_pool() -> Array[Part]:
	var civilian_pistol := Part.new()
	civilian_pistol.id = &"civilian_pistol"
	civilian_pistol.hp = 3
	civilian_pistol.max_hp = 3
	civilian_pistol.attaches_to = [&"GRIP"]
	civilian_pistol.requires = {&"TRIGGER": 1}
	civilian_pistol.damage = 3.0
	civilian_pistol.ap_cost = 1
	civilian_pistol.scatter = [Ring.new(0.15, 1.0), Ring.new(0.6, 2.0)]

	var sheet_steel_plate := Part.new()
	sheet_steel_plate.id = &"sheet_steel_plate"
	sheet_steel_plate.hp = 6
	sheet_steel_plate.max_hp = 6
	sheet_steel_plate.material = &"sheet_steel"
	sheet_steel_plate.attaches_to = [&"ARMOR"]
	sheet_steel_plate.mass = 4.0

	return [civilian_pistol, sheet_steel_plate]


## Millennia-old finds — never sold by a merchant.
static func hulk_only_pool() -> Array[Part]:
	var salvaged_reactor_core := Part.new()
	salvaged_reactor_core.id = &"salvaged_reactor_core"
	salvaged_reactor_core.hp = 4
	salvaged_reactor_core.max_hp = 4
	salvaged_reactor_core.attaches_to = [&"INTERNAL"]
	salvaged_reactor_core.material = &"sheet_steel"
	salvaged_reactor_core.mass = 8.0
	salvaged_reactor_core.tags = [&"VOLATILE", &"SALVAGE"]
	salvaged_reactor_core.failure_mode = &"DETONATE"
	salvaged_reactor_core.detonate_damage = 10.0
	salvaged_reactor_core.detonate_radius = 2.0

	var xeno_alloy_plate := Part.new()
	xeno_alloy_plate.id = &"xeno_alloy_plate"
	xeno_alloy_plate.hp = 10
	xeno_alloy_plate.max_hp = 10
	xeno_alloy_plate.material = &"reactive"
	xeno_alloy_plate.attaches_to = [&"ARMOR"]
	xeno_alloy_plate.mass = 6.0
	xeno_alloy_plate.tags = [&"SALVAGE"]

	return [salvaged_reactor_core, xeno_alloy_plate]


## The designs that appear in both pools (docs/07's "same rifle" example):
## `standard` from a merchant, `original_pattern` / `prototype` from a
## hulk — draw() sets variant_tag, this is otherwise a plain Part.
static func overlap_pool() -> Array[Part]:
	var combat_rifle := Part.new()
	combat_rifle.id = &"combat_rifle"
	combat_rifle.hp = 5
	combat_rifle.max_hp = 5
	combat_rifle.attaches_to = [&"GRIP"]
	combat_rifle.requires = {&"TRIGGER": 1, &"SUPPORT": 1}
	combat_rifle.damage = 6.0
	combat_rifle.ap_cost = 2
	combat_rifle.scatter = [Ring.new(0.05, 1.0), Ring.new(0.3, 1.5)]

	return [combat_rifle]


static func merchant_pool() -> Array[Part]:
	return merchant_only_pool() + overlap_pool()


static func hulk_pool() -> Array[Part]:
	return hulk_only_pool() + overlap_pool()


## Draws one item from `source`'s pool, tagging it if it's one of the
## overlap designs. All randomness (item pick, and which of the two hulk
## variant tags) draws from the passed seeded `rng`.
static func draw(source: StringName, rng: RandomNumberGenerator) -> Part:
	var pool: Array[Part] = merchant_pool() if source == MERCHANT_SOURCE else hulk_pool()
	var chosen: Part = (pool[rng.randi() % pool.size()] as Part).duplicate(true)
	_tag_if_overlap(chosen, source, rng)
	return chosen


static func _tag_if_overlap(part: Part, source: StringName, rng: RandomNumberGenerator) -> void:
	var is_overlap := false
	for candidate: Part in overlap_pool():
		if candidate.id == part.id:
			is_overlap = true
			break
	if not is_overlap:
		return
	if source == MERCHANT_SOURCE:
		part.variant_tag = &"standard"
	else:
		part.variant_tag = &"original_pattern" if rng.randf() < 0.5 else &"prototype"
