class_name EditorTools
extends RefCounted

## **What a board click can mean, and what each meaning authors.** taskblock-58 Pass D.
##
## The vocabulary lived on `EditorModule` while it was a list of verbs the bar read back. It is
## logic: which tools exist, and what `MapPlacement` kind each one produces for a given part, are
## questions with no widget in them — and `EditorModule` was over the file-size cap (`gdlintrc`'s
## `max-file-lines`, then at a lower value), the same split `InspectPanel` took when `BotViewer`
## came out of it.
##
## ## Ten became seven, grouped by what a click MEANS
##
## The old list was grouped by what a click *touched* — a verb per marker, a verb per flag — which
## is why it needed ten entries for what an author experiences as three gestures: put something
## down, take something away, grab something.
##
## | was | is |
## |---|---|
## | `place`, plus a separate kind choice | the three `place_*` tools; the kind is **derived** |
## | `spawn_a`/`b`/`none`, `chance`, `claim` | `place_map_thing`, with which thing a selection |
## | `remove` | `delete` |
## | `gizmo`, `height` | `select` and `scale` — the gizmo's two handle sets, armed separately |
## | `sight_blocking` | retired in Pass C along with `Grid.opacity` |
##
## **`height` folding into `select` loses nothing**, and that was checked rather than assumed:
## `GizmoModule._drag_to` already moves a placement on a Y-axis drag of a
## placement, so the verb's whole behaviour is what the translate handles do — by direct
## manipulation instead of a spinbox and a click.
##
## **The two handle sets become two tools** rather than a click that toggles between them. Arming
## *Scale* and arming *Select* are different intentions, and a mode you reach by clicking the same
## thing twice is a mode you leave by accident.

## Every meaning a board click can carry. Open `StringName`s, and the bar generates a button per
## entry, so the buttons and the router cannot disagree about which tools exist.
const TOOLS: Array[StringName] = [
	&"select",
	&"place_terrain",
	&"scale",
	&"delete",
	&"place_map_thing",
	&"place_big_part",
	&"place_part",
]

## The placing tools whose kind is fixed by the tool itself.
##
## **`place_terrain` is absent on purpose.** Terrain spans two kinds — `ship_floor` is a surface,
## `wall` is a blocker — so its kind is derived per part by `kind_for`. The other two *are* their
## kind, which is what makes them separate tools at all.
const PLACE_TOOL_KINDS: Dictionary = {
	&"place_big_part": MapPlacement.KIND_BLOCKER,
	&"place_part": MapPlacement.KIND_FIELD_ITEM,
}

## The two tools the manipulation gizmo answers to — its translate set and its resize set. Rows of
## `TOOLS` like every other verb; `GizmoModule` reads these rather than declaring its own.
const GIZMO_TOOLS: Array[StringName] = [&"select", &"scale"]

## Everything *Place Map Thing* can put down — the things a player never sees. Open, so a later
## scripted-tile marker is an entry here rather than an eighth tool.
const MAP_THINGS: Array[StringName] = [
	&"claim",
	&"spawn_a",
	&"spawn_b",
	&"spawn_none",
	&"chance",
]

## taskblock-59 Pass B: **what *Place Map Thing* offers, as one flat list.**
##
## The tool had a selection (`MAP_THINGS`) and no way to make it, so every click came out as the
## default — an `Interior` claim, which is what *"Map Thing places only lime-green volumes"* was:
## not a missing feature but a missing picker in front of one. The taskblock: *"give it the same
## selection the Place tools have — the claim kinds already exist as a vocabulary."*
##
## **`claim` expands into one entry per claim kind**, because picking *claim* and then picking
## *which claim* is two questions where the author has one intention. The composed ids are the only
## thing here that is not already a vocabulary elsewhere, and `map_thing_choice` is the single
## place that composes or decodes them — so adding a claim kind or a map thing still needs no edit
## in this file.
const CLAIM_CHOICE_PREFIX := "claim_"


## Every choice, in `MAP_THINGS` order with the claim kinds in `kinds`' order where `claim` sat.
static func map_thing_choices(kinds: Array[StringName]) -> Array[StringName]:
	var offered: Array[StringName] = []
	for thing: StringName in MAP_THINGS:
		if thing != &"claim":
			offered.append(thing)
			continue
		for kind: StringName in kinds:
			offered.append(StringName(CLAIM_CHOICE_PREFIX + String(kind)))
	return offered


## `{thing, claim_kind}` for one entry of `map_thing_choices`. `claim_kind` is `&""` for everything
## that is not a claim.
static func map_thing_choice(choice: StringName) -> Dictionary:
	var text: String = String(choice)
	if not text.begins_with(CLAIM_CHOICE_PREFIX):
		return {"thing": choice, "claim_kind": &""}
	return {
		"thing": &"claim",
		"claim_kind": StringName(text.substr(CLAIM_CHOICE_PREFIX.length())),
	}


## True when `tool` puts a `Part` on the board, as opposed to a marker or a manipulation.
static func is_place_tool(tool: StringName) -> bool:
	return tool == &"place_terrain" or PLACE_TOOL_KINDS.has(tool)


## True when `tool` is one the manipulation gizmo belongs to.
##
## taskblock-59 follow-up: **the two that keep a subject when you swap between them.** Arming
## anything else lets go of it — a handle set left over a part while the author is placing is a
## claim that something is selected when nothing is (`EditorModule._release_gizmo`).
##
## **Named from `GIZMO_TOOLS` here rather than from `GizmoModule`'s own constants**, which was the
## first cut and is a `src/logic/` class reaching into `src/view/` — the golden rule this project is
## built on. The vocabulary is logic; the module that draws handles for it is not.
static func arms_the_gizmo(tool: StringName) -> bool:
	return GIZMO_TOOLS.has(tool)


## True when `tool` picks what it places from a list. The place tools and *Place Map Thing*, which
## differ in what they offer and not in whether they offer it.
static func picks_from_a_list(tool: StringName) -> bool:
	return is_place_tool(tool) or tool == &"place_map_thing"


## The `MapPlacement` kind `tool` authors for `part_id`.
##
## **Terrain is the case that needs the part**, because it spans two kinds: a terrain part that
## attaches to `GROUND` is the ground, and one that does not is standing on it. That is the rule
## `GridPlacement` already enforces, asked here rather than restated — offering a wall as a surface
## would author a placement the loader refuses.
static func kind_for(tool: StringName, part_id: StringName) -> StringName:
	if PLACE_TOOL_KINDS.has(tool):
		return PLACE_TOOL_KINDS[tool]
	var part: Part = DataLibrary.get_part(part_id)
	if part != null and GridPlacement.GROUND in part.attaches_to:
		return MapPlacement.KIND_SURFACE
	return MapPlacement.KIND_BLOCKER


## The subset of `pool` that `tool` offers.
##
## **Terrain is answerable from the data and the rest is not**, which is the honest state of this
## and is worth stating at the filter rather than in a report. `MapPlacement.TERRAIN_TAG` is a real
## tag on a real part, so *Place Terrain* offers exactly the parts that carry it. *Place Big Part*
## and *Place Part* get everything else — which is still every arm, head and battery in
## `DataLibrary.parts_pool()`, because nothing in the data says which parts belong on a board
## rather than on a body. **Pass D split the verbs; it did not close that gap**, and pretending
## otherwise by inventing a second content tag is the thing the standing rule forbids.
static func part_ids_for(tool: StringName, pool: Array[StringName]) -> Array[StringName]:
	if not is_place_tool(tool):
		return [] as Array[StringName]
	var offered: Array[StringName] = []
	for id: StringName in pool:
		if is_terrain(id) == (tool == &"place_terrain"):
			offered.append(id)
	return offered


## Whether the part with this id is board rather than something standing on it.
static func is_terrain(part_id: StringName) -> bool:
	var part: Part = DataLibrary.get_part(part_id)
	return part != null and MapPlacement.TERRAIN_TAG in part.tags
