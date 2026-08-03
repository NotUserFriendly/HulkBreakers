class_name SectionRoller
extends RefCounted

## taskblock-55 Pass C/E: **turns a section's declarations into one concrete example of it.**
##
## Pure logic, zero SceneTree. A section declares *what may be*; this rolls it once, against a
## seeded `RandomNumberGenerator`, into *what is*. After it runs there are no declarations left —
## a board has a barrel or it does not.
##
## ## Determinism, and the specific way this gets got wrong
##
## Same seed, same example, always (CLAUDE.md). The hazard is not the RNG, it is the **iteration
## order**: roll over a `Dictionary` keyed by cell and the draw order follows insertion, which
## follows authoring, which changes when someone moves a barrel. The board then changes for a
## reason nobody can see, and the seed stops meaning anything.
##
## **`SectionFile.spawns` is an `Array`, and that is the whole defence** — authored order is
## stable, serialised, and reviewable in the `.tres`. Nothing here iterates a dictionary while
## drawing. `_ordered` re-sorts by cell anyway, so a section that is re-authored with its spawns
## in a different order still rolls identically for a given seed.


## Rolls one section's per-cell declarations.
##
## Returns `{"clutter": Array[Dictionary], "garrison": Array[Vector2i]}` — clutter entries are
## `{"cell": Vector2i, "tag": StringName}`. **Tags, not part ids**: what a tag resolves to is the
## content library's business, and there is no such library yet (see `part_for_tag`).
static func roll(section: SectionFile, rng: RandomNumberGenerator) -> Dictionary:
	var clutter: Array[Dictionary] = []
	var garrison: Array[Vector2i] = []
	if section == null or rng == null:
		return {"clutter": clutter, "garrison": garrison}

	for spawn: SectionSpawn in _ordered(section.spawns):
		# **Every candidate draws, including ones that cannot possibly land.** A banned tag and a
		# capped-out cell still consume their draw, so adding a ban to a section does not shift
		# every later cell's result — the seed keeps meaning the same thing.
		var roll_value: float = rng.randf()
		if roll_value >= spawn.chance:
			continue
		match spawn.kind:
			SectionSpawn.KIND_CLUTTER:
				if spawn.tag in section.banned_clutter:
					continue
				if section.maximum_clutter >= 0 and clutter.size() >= section.maximum_clutter:
					continue
				clutter.append({"cell": spawn.cell, "tag": spawn.tag})
			SectionSpawn.KIND_SPAWNER:
				if section.maximum_garrison >= 0 and garrison.size() >= section.maximum_garrison:
					continue
				garrison.append(spawn.cell)

	# **All-or-nothing, not a minimum topped up.** A cavernous room never contains one lonely
	# guard: either it is held or it is empty. Topping the roll up to the minimum would make the
	# declaration a floor on the *number*, when what it actually declares is that a thin garrison
	# is not a thing this room can be.
	if garrison.size() < section.minimum_garrison:
		garrison.clear()

	return {"clutter": clutter, "garrison": garrison}


## **Encounters roll per room, and a room may be several sections.**
##
## Crossing an invisible seam inside one large hold must not trigger anything, so this groups the
## placed sections into rooms first and draws once per room — never once per section.
##
## `sections` is in placement order. A section that declares `is_room` starts a room; one that
## does not is part of a larger one and joins the room already open, because that is what the
## declaration means. **A real adjacency graph arrives with the generator** — with two sections
## there is only one possible adjacency, and inventing a graph to express it would be inventing
## the generator's job.
##
## Returns one entry per room: `{"sections": Array[int], "encounter": StringName}`. `encounter` is
## empty when the room's sections whitelist nothing between them.
static func roll_encounters(
	sections: Array[SectionFile], rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	if rng == null:
		return rooms

	for index: int in range(sections.size()):
		var section: SectionFile = sections[index]
		if section == null:
			continue
		if rooms.is_empty() or section.is_room:
			rooms.append({"sections": [index] as Array[int], "encounter": &""})
		else:
			(rooms[rooms.size() - 1]["sections"] as Array[int]).append(index)

	for room: Dictionary in rooms:
		# The room's whitelist is the union of its sections', in section order then authored
		# order — one draw against one list, which is what makes a two-section room roll once.
		var whitelist: Array[StringName] = []
		for index: int in room["sections"]:
			for encounter: StringName in (sections[index] as SectionFile).encounter_types:
				if not whitelist.has(encounter):
					whitelist.append(encounter)
		if whitelist.is_empty():
			continue
		room["encounter"] = whitelist[rng.randi_range(0, whitelist.size() - 1)]
	return rooms


## **A flagged, tunable hook, not a design decision** (CLAUDE.md). A clutter tag names a *kind* of
## thing — `barrel`, `logistic`, `machine` — and choosing which part a kind resolves to is the
## content library's job. There is no content library, so this resolves a tag to a part of the
## same id when one exists and to nothing otherwise.
##
## That is deliberately the dullest possible rule: it lets an authored section produce real
## geometry today without this function quietly becoming the place where content selection lives.
static func part_for_tag(tag: StringName) -> StringName:
	return tag if DataLibrary.get_part(tag) != null else &""


## Authored spawns in a stable order regardless of how they were authored — by cell, then by the
## fields that can distinguish two spawns sharing one cell. See this class's own note on why the
## order is the thing that has to be defended rather than the RNG.
static func _ordered(spawns: Array[SectionSpawn]) -> Array[SectionSpawn]:
	var sorted: Array[SectionSpawn] = []
	for spawn: SectionSpawn in spawns:
		if spawn != null:
			sorted.append(spawn)
	sorted.sort_custom(
		func(one: SectionSpawn, other: SectionSpawn) -> bool:
			if one.cell.y != other.cell.y:
				return one.cell.y < other.cell.y
			if one.cell.x != other.cell.x:
				return one.cell.x < other.cell.x
			if one.kind != other.kind:
				return String(one.kind) < String(other.kind)
			return String(one.tag) < String(other.tag)
	)
	return sorted
