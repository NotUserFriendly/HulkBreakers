extends SceneTree

## taskblock-55 Pass E: authors the sections that exercise the **authoring vocabulary**, as
## opposed to taskblock-54's three, which exercise the **format**. Run via
## `godot --headless -s res://tools/author_taskblock55_sections.gd`; kept afterward as the record
## of what each section is *for*, which the `.tres` cannot say.
##
## ## Meaningful names, because these get read far more than they get run
##
## taskblock-54's `east_hall` and `west_hall` are identical and their names say nothing — fine as
## format fixtures, useless as vocabulary fixtures. Every section below is named for the **thing
## it demonstrates**, so a reader looking for the merge case can find it without opening files.
##
## ```
##   pump_room ==== reactor_walk        cutting_yard      hull_breach_lip
##   (clutter,       (the merge          (Empty claim     (Exterior claim --
##    garrison       partner: their      over the         conflicts with
##    that can       shared wall         neighbour's      pump_room's
##    fail)          becomes one)        floor)           Interior)
##
##   coolant_stack_lower  --up-->  coolant_stack_upper
##   (the stacked pair; the upper deck rests on the lower's ceiling)
##
##   service_crawl                    grand_hold_north / grand_hold_south
##   (an entry connecting to          (one room in two sections -- the south
##    nothing; becomes a wall)         half declares is_room = false)
##
##   blast_door_narrow  <-->  blast_door_wide
##   (a small door whose entry claim is expanded, and the larger door that
##    overwrites it -- the intersection is what decides, not a ranking)
## ```

const OUT_DIR := "res://data/sections"
const CORRIDOR: StringName = &"corridor_4w"
const SHAFT: StringName = &"coolant_shaft"
const BLAST: StringName = &"blast_door"

## Deck thickness, read from the part rather than written as a number here — a stacked section's
## lift depends on it, and a constant copied into this file would be the second place it lives.
var deck: float = 0.0


func _initialize() -> void:
	deck = DataLibrary.get_part(&"ship_floor").volume[0].size.y
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var written: Array[String] = []
	written.append(_write(_pump_room(), "pump_room"))
	written.append(_write(_reactor_walk(), "reactor_walk"))
	written.append(_write(_cutting_yard(), "cutting_yard"))
	written.append(_write(_hull_breach_lip(), "hull_breach_lip"))
	written.append(_write(_coolant_stack_lower(), "coolant_stack_lower"))
	written.append(_write(_coolant_stack_upper(), "coolant_stack_upper"))
	written.append(_write(_service_crawl(), "service_crawl"))
	written.append(_write(_grand_hold_north(), "grand_hold_north"))
	written.append(_write(_grand_hold_south(), "grand_hold_south"))
	written.append(_write(_blast_door_narrow(), "blast_door_narrow"))
	written.append(_write(_blast_door_wide(), "blast_door_wide"))

	var failed: Array[String] = written.filter(func(name: String) -> bool: return name == "")
	print("wrote %d section(s) into %s" % [written.size() - failed.size(), OUT_DIR])
	quit(1 if not failed.is_empty() else 0)


# --- helpers --------------------------------------------------------------------------------


func _floored(name: String, width: int, rows: int, height: float = 0.0) -> SectionFile:
	var section := SectionFile.new()
	section.section_name = name
	section.width = width
	section.rows = rows
	for y: int in range(rows):
		for x: int in range(width):
			section.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor", height)
			)
	return section


func _claim(kind: StringName, center: Vector3, size: Vector3) -> SectionClaim:
	return SectionClaim.new(kind, Box.new(center, size))


func _exterior_except(
	open_side: StringName, tag: StringName, at: float = 0.0
) -> Array[SectionEdge]:
	var edges: Array[SectionEdge] = []
	for side: StringName in [
		SectionEdge.SIDE_NORTH, SectionEdge.SIDE_SOUTH, SectionEdge.SIDE_EAST, SectionEdge.SIDE_WEST
	]:
		if side == open_side:
			edges.append(SectionEdge.new(side, SectionEdge.KIND_OPEN, tag, [] as Array[int], at))
		else:
			edges.append(SectionEdge.new(side, SectionEdge.KIND_EXTERIOR))
	return edges


# --- the sections ---------------------------------------------------------------------------


## **Clutter and spawners with real chances, and a garrison that can fail.**
##
## Four clutter cells at varying odds against a cap of two, so the cap does work rather than
## being decoration; three spawner cells against a `minimum_garrison` of three, so an unlucky roll
## produces **none** rather than a lonely guard. `goo_barrel` is banned even though nothing offers
## it — the ban is a statement about the room, not a reaction to its cells.
func _pump_room() -> SectionFile:
	var section: SectionFile = _floored("Pump Room", 4, 4)
	# **Tags that name parts which actually exist.** A first draft used `barrel`, which no part
	# answers to — `part_for_tag` skipped every one of them, the section quietly produced half the
	# clutter it declared, and the cap below was never reached in forty seeds. A tag naming nothing
	# is legitimate (the library may catch up with it) and is exactly why it must not be the only
	# thing a demo fixture exercises.
	section.spawns = [
		SectionSpawn.new(Vector2i(0, 0), SectionSpawn.KIND_CLUTTER, &"barrel_pallet", 0.8),
		SectionSpawn.new(Vector2i(3, 0), SectionSpawn.KIND_CLUTTER, &"crate", 0.8),
		SectionSpawn.new(Vector2i(0, 3), SectionSpawn.KIND_CLUTTER, &"scrap_pile", 0.8),
		SectionSpawn.new(Vector2i(3, 3), SectionSpawn.KIND_CLUTTER, &"metal_scraps", 0.8),
		SectionSpawn.new(Vector2i(1, 1), SectionSpawn.KIND_SPAWNER, &"guard", 0.6),
		SectionSpawn.new(Vector2i(2, 1), SectionSpawn.KIND_SPAWNER, &"guard", 0.6),
		SectionSpawn.new(Vector2i(1, 2), SectionSpawn.KIND_SPAWNER, &"guard", 0.6),
	]
	section.maximum_clutter = 2
	section.banned_clutter = [&"goo_barrel"]
	section.minimum_garrison = 3
	section.encounter_types = [&"patrol", &"maintenance_crew"]
	# Its interior is asserted, which is what `hull_breach_lip` collides with.
	section.claims = [
		_claim(SectionClaim.KIND_INTERIOR, Vector3(1.5, 1.2, 1.5), Vector3(4, 2.4, 4))
	]
	section.edges = _exterior_except(SectionEdge.SIDE_EAST, CORRIDOR)
	return section


## **The merge partner.** Its west wall sits in the same column as `pump_room`'s east wall, and a
## merge volume over that column is what makes the two into one wall instead of two.
func _reactor_walk() -> SectionFile:
	var section: SectionFile = _floored("Reactor Walk", 4, 4)
	for y: int in range(4):
		section.placements.append(
			MapPlacement.new(Vector2i(0, y), MapPlacement.KIND_BLOCKER, &"wall", 0.0)
		)
	section.claims = [
		_claim(SectionClaim.KIND_MERGE, Vector3(0.0, 1.2, 1.5), Vector3(1.0, 2.4, 4.0)),
		_claim(SectionClaim.KIND_INTERIOR, Vector3(1.5, 1.2, 1.5), Vector3(4, 2.4, 4)),
	]
	section.encounter_types = [&"patrol"]
	section.edges = _exterior_except(SectionEdge.SIDE_WEST, CORRIDOR)
	return section


## **An `Empty` claim over the space a neighbour wants.** The claim reaches a full column east of
## this section's own footprint, so any neighbour placing a floor there is refused by name.
func _cutting_yard() -> SectionFile:
	var section: SectionFile = _floored("Cutting Yard", 4, 4)
	section.claims = [_claim(SectionClaim.KIND_EMPTY, Vector3(4.0, 1.2, 1.5), Vector3(1, 2.4, 4))]
	section.is_room = true
	section.encounter_types = [&"salvage_crew"]
	section.edges = _exterior_except(SectionEdge.SIDE_EAST, CORRIDOR)
	return section


## **The Interior/Exterior conflict.** It asserts that the space `pump_room` calls interior is
## outside the hulk. Both cannot be true, and the refusal names both.
func _hull_breach_lip() -> SectionFile:
	var section: SectionFile = _floored("Hull Breach Lip", 4, 4)
	section.claims = [
		_claim(SectionClaim.KIND_EXTERIOR, Vector3(1.5, 1.2, 1.5), Vector3(4, 2.4, 4))
	]
	# Not a room on its own: it is the torn edge of one, and an encounter must not roll here.
	section.is_room = false
	section.edges = _exterior_except(SectionEdge.SIDE_WEST, CORRIDOR)
	return section


## **The stacked pair, lower half.** Its `up` edge is what `coolant_stack_upper` joins through.
func _coolant_stack_lower() -> SectionFile:
	var section: SectionFile = _floored("Coolant Stack, Lower", 3, 3)
	section.claims = [_claim(SectionClaim.KIND_INTERIOR, Vector3(1, 1.5, 1), Vector3(3, 3.0, 3))]
	section.encounter_types = [&"patrol"]
	section.edges = [
		SectionEdge.new(SectionEdge.SIDE_UP, SectionEdge.KIND_OPEN, SHAFT, [] as Array[int], 0.0)
	]
	return section


## **The stacked pair, upper half.** Placed at its own local ground; `stitch` computes the lift
## from both intervals, so this file does not have to know how tall the lower one is.
func _coolant_stack_upper() -> SectionFile:
	var section: SectionFile = _floored("Coolant Stack, Upper", 3, 3)
	section.claims = [_claim(SectionClaim.KIND_INTERIOR, Vector3(1, 1.0, 1), Vector3(3, 2.0, 3))]
	section.encounter_types = [&"observation_post"]
	section.edges = [
		SectionEdge.new(SectionEdge.SIDE_DOWN, SectionEdge.KIND_OPEN, SHAFT, [] as Array[int], 0.0)
	]
	return section


## **An entry that connects to nothing.** Its entry volume points east into open space, so
## assembling it beside anything that does not answer turns the opening into a wall — the rule
## that stops a door opening into the back of an oven.
func _service_crawl() -> SectionFile:
	var section: SectionFile = _floored("Service Crawl", 2, 2)
	section.claims = [_claim(SectionClaim.KIND_ENTRY, Vector3(1.5, 0.6, 0.0), Vector3(0.4, 1.2, 1))]
	section.is_room = false
	section.edges = _exterior_except(SectionEdge.SIDE_EAST, CORRIDOR)
	return section


## **One room in two sections, north half.** Declares itself a room; the south half does not, so
## the pair rolls **one** encounter between them.
func _grand_hold_north() -> SectionFile:
	var section: SectionFile = _floored("Grand Hold, North", 6, 4)
	section.encounter_types = [&"patrol", &"ambush", &"salvage_crew"]
	section.is_room = true
	section.edges = _exterior_except(SectionEdge.SIDE_SOUTH, CORRIDOR)
	return section


## **One room in two sections, south half — the `is_room = false` case.** Crossing the seam
## inside the hold must not trigger a second encounter, and nothing about this section's contents
## could have said so.
func _grand_hold_south() -> SectionFile:
	var section: SectionFile = _floored("Grand Hold, South", 6, 4)
	section.encounter_types = [&"patrol", &"ambush", &"salvage_crew"]
	section.is_room = false
	section.edges = _exterior_except(SectionEdge.SIDE_NORTH, CORRIDOR)
	return section


## **A small door whose entry claim is deliberately expanded past its own face.** Expanding it is
## the invitation: a neighbour's larger door may now overwrite it. The claim is adjusted on the
## door itself rather than added beside it, which is the rule that stops two entries describing
## one opening and disagreeing.
func _blast_door_narrow() -> SectionFile:
	var section: SectionFile = _floored("Blast Door, Narrow", 3, 3)
	section.placements.append(
		MapPlacement.new(Vector2i(2, 1), MapPlacement.KIND_BLOCKER, &"wall", 0.0)
	)
	# The door's own face would be 1.0 tall and one cell wide; this reaches 2.4 and three cells.
	section.claims = [_claim(SectionClaim.KIND_ENTRY, Vector3(2.5, 1.2, 1.0), Vector3(0.4, 2.4, 3))]
	section.edges = _exterior_except(SectionEdge.SIDE_EAST, BLAST)
	return section


## **The larger door that overwrites it.** Nothing ranks the two: the shared opening is the
## intersection of the two claims, and the smaller one is smaller — so the result is the small
## door's own extent, arrived at by geometry rather than by a comparison.
func _blast_door_wide() -> SectionFile:
	var section: SectionFile = _floored("Blast Door, Wide", 3, 3)
	section.placements.append(
		MapPlacement.new(Vector2i(0, 1), MapPlacement.KIND_BLOCKER, &"wall", 0.0)
	)
	section.claims = [
		_claim(SectionClaim.KIND_ENTRY, Vector3(-0.5, 1.6, 1.0), Vector3(0.4, 3.2, 3))
	]
	section.edges = _exterior_except(SectionEdge.SIDE_WEST, BLAST)
	return section


func _write(section: SectionFile, file_name: String) -> String:
	var path := "%s/%s.tres" % [OUT_DIR, file_name]
	var problems: Array[String] = SectionSerializer.describe_problems(section)
	if not problems.is_empty():
		# **Authoring warnings are printed, not fatal** — a demo section that deliberately
		# conflicts with another is the point of several of these.
		print("  %s: %s" % [file_name, "; ".join(problems)])
	if ResourceSaver.save(section, path) != OK:
		printerr("failed to write %s" % path)
		return ""
	return file_name
