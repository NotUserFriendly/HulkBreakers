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


## docs/03: VOLATILE + a real cook_off_damage is the entire "cooks off"
## mechanic — already built, never reimplemented per field object.
static func goo_barrel() -> Part:
	var part := Part.new()
	part.id = &"goo_barrel"
	part.display_name = "Goo Barrel"
	part.material = &"reactive"
	part.hp = 3
	part.max_hp = 3
	part.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.5, 1.0, 0.5))]
	part.tags = [&"VOLATILE"]
	part.cook_off_damage = 12.0
	part.cook_off_radius = 2.0
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
