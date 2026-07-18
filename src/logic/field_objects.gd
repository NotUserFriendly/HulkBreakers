class_name FieldObjects
extends RefCounted

## docs/10 taskblock04 C3: "cover could be a pile of metal scrap, barrels of
## radioactive goo, or a forklift... Cover is a Part (or a part tree) sitting
## at a cell — the same category as a dropped assembly and an inert shell."
## Starter set — data rows, no code: every one of these is a plain
## destructible Part with real volume/material/hp/salvage_yield, plugging
## into pre-existing systems (shot-plane projection, cook-off, salvage
## crediting) rather than inventing new ones.
##
## A forklift — "a functional mechanical body with no matrix docked" — is
## already expressible as a bare Shell (taskblock-02 A) and needs no
## factory here; it's a Unit/Shell concern, not a field-object one.
##
## Special actions tied to a field object (docs/10 taskblock04 C3: "cut
## apart for resources... potentially special actions") are explicitly a
## hook, not built here — ask before adding one.


static func scrap_pile() -> Part:
	var part := Part.new()
	part.id = &"scrap_pile"
	part.display_name = "Scrap Pile"
	part.material = &"steel"
	part.hp = 6
	part.max_hp = 6
	part.volume = [Box.new(Vector3(0.0, 0.4, 0.0), Vector3(0.9, 0.8, 0.9))]
	part.salvage_yield = {&"metals": 4}
	return part


## docs/03/taskblock-09 A3: failure_mode == DETONATE (renamed from
## "cook-off") is the entire "explodes on failure" mechanic — already
## built, never reimplemented per field object. VOLATILE stays as a
## descriptor tag, not the trigger.
static func goo_barrel() -> Part:
	var part := Part.new()
	part.id = &"goo_barrel"
	part.display_name = "Goo Barrel"
	part.material = &"reactive"
	part.hp = 3
	part.max_hp = 3
	part.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.5, 1.0, 0.5))]
	part.tags = [&"VOLATILE"]
	part.failure_mode = &"DETONATE"
	part.detonate_damage = 12.0
	part.detonate_radius = 2.0
	part.salvage_yield = {&"reactives": 2}
	return part


static func crate() -> Part:
	var part := Part.new()
	part.id = &"crate"
	part.display_name = "Crate"
	part.material = &"hull_plate"
	part.hp = 3
	part.max_hp = 3
	part.volume = [Box.new(Vector3(0.0, 0.35, 0.0), Vector3(0.7, 0.7, 0.7))]
	part.salvage_yield = {&"organics": 3}
	return part


## docs/10 taskblock05 E1: what a mangling part (cladding, structure)
## becomes on destruction — this is where the "wreckage carries
## salvage_yield" half of the rule actually lives; the part it replaced
## typically carries none of its own.
static func twisted_sheet_metal() -> Part:
	var part := Part.new()
	part.id = &"twisted_sheet_metal"
	part.display_name = "Twisted Sheet Metal"
	part.material = &"sheet_steel"
	part.hp = 1
	part.max_hp = 1
	part.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.1))]
	part.salvage_yield = {&"metals": 2}
	return part


## What a mangling plate becomes on destruction.
static func metal_scraps() -> Part:
	var part := Part.new()
	part.id = &"metal_scraps"
	part.display_name = "Metal Scraps"
	part.material = &"steel"
	part.hp = 1
	part.max_hp = 1
	part.volume = [Box.new(Vector3.ZERO, Vector3(0.25, 0.25, 0.1))]
	part.salvage_yield = {&"metals": 3}
	return part


## docs/10 taskblock05 E1: every wreckage kind a mangling Part.mangles_into
## can name, as templates — the same "array of templates, duplicate the
## one you want by id" pattern DeepStrike.default_part_pool() already
## uses. Adding a new wreckage kind is one more row here, no other code
## changes (open StringName vocabulary, not a closed engine state).
static func wreckage_pool() -> Array[Part]:
	return [twisted_sheet_metal(), metal_scraps()]
