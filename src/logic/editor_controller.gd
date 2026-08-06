class_name EditorController
extends RefCounted

## taskblock-56 Pass F1: **the whole editing model, headless.**
##
## `BuilderController` is the precedent and this follows it exactly — 161 lines of pure controller
## against a scene that *only reads it and draws*, with its own header calling the builder "the best
## test the assembler will ever get." The same claim applies here: an editor that authors boards
## through the real formats is the best test those formats will ever get, and none of that needs a
## SceneTree to be true.
##
## ## One editor, two save buttons
##
## **A section is a small map**, so there is one model and two ways to write it out — `to_map_file`
## and `to_section_file`. Everything section-specific (claims, edges, per-cell chance, the
## whole-section declarations) lives on this one model and is simply *not written* by the map save.
## Two controllers would be two answers to "what did the author place", and the first thing to
## drift.
##
## `target` picks which of the two `warnings()` is asked about, because the two formats disagree
## about what a defect is: a board with nothing walkable on it is a broken **map** and a perfectly
## legitimate **section** (`SectionFile`'s own worked example — a square of empty cells with one
## exterior wall). Asking both questions at once would bury the real warning under the other
## format's opinion.
##
## ## Warn, never block — and that is why nothing here validates on the way in
##
## Every verb below places what it was asked to place. `GridPlacement.can_place` gates *authoring*
## in the generator; replaying it here would refuse a deliberately broken board, and taskblock-53
## already settled that question for the load path in `MapSerializer`'s own header: *"an authored
## map may be broken on purpose: the editor's later job is to warn, never to block."* This is that
## editor, so `warnings()` is where every check lives and no verb has a refusal branch for a
## legality question. The refusals that remain are all "you named something that is not there" —
## an out-of-range claim index, a cell with nothing on it — which is a caller mistake rather than
## an authoring opinion.
##
## ## Undo is a snapshot stack, deliberately
##
## Every verb takes a full copy of the model before mutating and `undo()` restores it. A board is a
## few hundred placements, so a snapshot is cheap; the alternative — an inverse operation per verb —
## is a second implementation of every verb, and the one that is wrong is the one nobody exercises.
## **The acceptance is that undo restores the prior state exactly**, and a snapshot makes that true
## by construction rather than by twelve careful inverses.
##
## Addressing is by **cell**, never by a held `MapPlacement` reference, for the same reason: a
## restore builds fresh resources, so a reference taken before an undo would point at a placement
## the model no longer contains.

## Which format the two save buttons and `warnings()` are talking about. Open `StringName`s rather
## than an enum: the formats are content vocabulary (a third authored format is a `.tres` schema and
## a serializer, not an engine state), and this is the same posture `MapPlacement.kind` takes.
const TARGET_MAP: StringName = &"map"
const TARGET_SECTION: StringName = &"section"

## How many steps back `undo()` can go. Flagged and tunable, not derived from anything.
const UNDO_DEPTH := 64

## The `SectionFile` properties this model holds explicitly, and which therefore are *not*
## whole-section declaration fields. Everything else `SectionFile` exports is discovered rather
## than listed — see `declaration_fields()`.
const STRUCTURAL_FIELDS: Array[StringName] = [
	&"section_name",
	&"width",
	&"rows",
	&"placements",
	&"edges",
	&"claims",
	&"spawns",
]

## Human-facing, and the only field with no mechanical effect — `MapFile.map_name` /
## `SectionFile.section_name` are the same field wearing two names.
var board_name: String = ""
var width: int = 12
var rows: int = 12

## Every placed surface, blocker and field item, **in authored order**. Order within a cell is
## meaningful (`Surface.first_walkable` takes the first match), and authored order is what preserves
## it — the same reason `MapFile.placements` is an ordered array rather than a per-cell map.
var placements: Array[MapPlacement] = []

## `Vector2i` -> `Enums.SpawnMarker`. A dictionary rather than `MapFile`'s parallel arrays because a
## cell holds exactly one marker and the editor should not be able to express otherwise; the
## parallel form is produced at save time, in row-major order so the same board always saves to the
## same file.
var spawn_markers: Dictionary = {}

var claims: Array[SectionClaim] = []
var edges: Array[SectionEdge] = []
## Per-cell "something may appear here" declarations — the per-cell chance half of the authoring
## vocabulary.
var spawns: Array[SectionSpawn] = []

## Whole-section declarations by property name, applied to a `SectionFile` at save time. A field
## with no entry keeps the resource's own default, which is what every `SectionFile` is written to
## work with.
var section_fields: Dictionary = {}

## Which format `warnings()` answers about. See the class note.
var target: StringName = TARGET_MAP

var _undo_stack: Array[Dictionary] = []


## The whole-section declaration fields, discovered from `SectionFile` itself rather than listed.
##
## **Adding a declaration to the section format must not require a code edit here** — that is the
## standing open-vocabulary rule applied to an authoring surface. A new `@export` on `SectionFile`
## becomes an editable field the moment it exists, and the only thing this file knows is which
## properties it already models itself.
static func declaration_fields() -> Array[StringName]:
	var found: Array[StringName] = []
	for entry: Dictionary in SectionFile.new().get_property_list():
		if not (int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name := StringName(entry["name"])
		if STRUCTURAL_FIELDS.has(name):
			continue
		found.append(name)
	return found


# --- placement -----------------------------------------------------------------------------


## Appends a placement at `cell`. **Never refuses on a legality question** — see the class note.
## Null only when the board has nowhere to put it; see `blocks_placement`.
func place(
	cell: Vector2i,
	part_id: StringName,
	kind: StringName = MapPlacement.KIND_SURFACE,
	height: float = 0.0,
	facing: float = 0.0
) -> MapPlacement:
	if blocks_placement(cell, kind) != "":
		return null
	_push_undo()
	var placement := MapPlacement.new(cell, kind, part_id, height, facing)
	placements.append(placement)
	return placement


## taskblock-59 Pass A: **why a placement is one the board cannot hold**, or `""` when it can.
##
## **This is not the legality question the class note refuses to ask.** A board with no walkable
## surface, a pit nobody can climb out of, a floor whose grammar does not hold — those are authoring
## opinions and `warnings()` states them without blocking anything. This is narrower and it is the
## line `MapSerializer` already drew for the load path: *"two blockers on one cell... not authoring
## opinions, they are files that do not describe a map."* `Grid.blockers` is one part per cell, so a
## second one has nowhere to go — there is no board on which the author's click could be honoured.
##
## **Accepting it anyway is what produced the corruption Pass A deletes.** The model took the second
## blocker, the serializer refused the model, and the view stayed frozen at the last board that
## built — so every later placement was authored invisibly. Refusing at the verb keeps the model
## inside what the board can draw, which is what makes *"the model and the view never disagree"* a
## property of the code rather than of a redraw remembering to happen.
##
## Deliberately **not** extended to a second surface on one cell: `Grid` holds an ordered stack per
## cell, a catwalk over a floor is exactly that, and `GridPlacement`'s one-per-cell `GROUND` rule is
## an authoring opinion that `_grammar_warnings` already reports.
func blocks_placement(cell: Vector2i, kind: StringName) -> String:
	if kind != MapPlacement.KIND_BLOCKER:
		return ""
	for placement: MapPlacement in placements:
		if placement != null and placement.cell == cell and placement.kind == kind:
			return (
				"%s already has a '%s' on it; a cell holds one blocker" % [cell, placement.part_id]
			)
	return ""


## Every placement at `cell`, in authored order. A read, so it takes no undo step.
func placements_at(cell: Vector2i) -> Array[MapPlacement]:
	var found: Array[MapPlacement] = []
	for placement: MapPlacement in placements:
		if placement != null and placement.cell == cell:
			found.append(placement)
	return found


## Removes the **last** placement authored at `cell` — the one just placed, which is what an
## author reaching for an undo-shaped gesture means by "remove". False when the cell is empty.
func remove_top(cell: Vector2i) -> bool:
	for index: int in range(placements.size() - 1, -1, -1):
		var placement: MapPlacement = placements[index]
		if placement != null and placement.cell == cell:
			_push_undo()
			placements.remove_at(index)
			return true
	return false


## Removes everything at `cell`. False when there was nothing there.
func clear_cell(cell: Vector2i) -> bool:
	var kept: Array[MapPlacement] = []
	for placement: MapPlacement in placements:
		if placement != null and placement.cell == cell:
			continue
		kept.append(placement)
	if kept.size() == placements.size():
		return false
	_push_undo()
	placements = kept
	return true


## Sets the elevation of the last surface authored at `cell`. False when the cell has no surface.
##
## Surfaces only, because height is a surface's own field: a blocker or a field item sits on
## whatever surface the cell already has (`MapPlacement`'s own note), and letting an author set a
## number the loader ignores would be a control that silently does nothing.
func set_height(cell: Vector2i, height: float) -> bool:
	var surface: MapPlacement = _top_surface(cell)
	if surface == null:
		return false
	_push_undo()
	_top_surface(cell).height = height
	return true


## taskblock-59 Pass C: **the size and offset of the last thing authored at `cell`.** False when the
## cell is empty.
##
## `MapPlacement.size` landed in taskblock-58 — tested, serialised, hp following volume — and
## **nothing wrote it except a hand-authored `.tres`.** The Scale tool, the gizmo and face picking
## all landed too; they were simply not connected to the field. This is the connection.
##
## **The top placement, not the top surface.** `set_height` deliberately takes only surfaces,
## because height is a surface's own field and a blocker sits on whatever the cell has. Size is not
## like that: a wall, a crate and a floor can all be authored at a size, and the thing an author
## just clicked is the thing they mean.
##
## Refuses a size with a non-positive component rather than clamping it. A placement thinner than
## nothing is not a smaller placement, and `Gizmo.resized_box` already established that a drag which
## would collapse a volume is refused rather than silently clamped — an author can tell a refusal
## from a laggy drag, and cannot tell a clamp from one.
func set_placement_size(cell: Vector2i, size: Vector3, offset: Vector3 = Vector3.ZERO) -> bool:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return false
	var placements_here: Array[MapPlacement] = placements_at(cell)
	if placements_here.is_empty():
		return false
	_push_undo()
	var top: MapPlacement = placements_at(cell)[placements_here.size() - 1]
	top.size = size
	top.offset = offset
	return true


## The facing half of the same. What makes a ramp directional.
func set_facing(cell: Vector2i, facing: float) -> bool:
	var surface: MapPlacement = _top_surface(cell)
	if surface == null:
		return false
	_push_undo()
	_top_surface(cell).facing = facing
	return true


## `Enums.SpawnMarker.NONE` clears it, which is why this never needs a separate erase verb.
func set_spawn_marker(cell: Vector2i, marker: int) -> void:
	_push_undo()
	if marker == Enums.SpawnMarker.NONE:
		spawn_markers.erase(cell)
	else:
		spawn_markers[cell] = marker


## Resizes the board. **Placements outside the new bounds are kept, not dropped** — dropping them
## would be the editor deciding an author's mistake for them, and `warnings()` names every one.
func set_size(p_width: int, p_rows: int) -> void:
	_push_undo()
	width = p_width
	rows = p_rows


# --- the section-specific model ------------------------------------------------------------


## Appends a claim and returns its index.
func add_claim(kind: StringName, box: Box) -> int:
	_push_undo()
	claims.append(SectionClaim.new(kind, box))
	return claims.size() - 1


## Resizes claim `index` in place. False for an index nobody authored.
func resize_claim(index: int, box: Box) -> bool:
	if index < 0 or index >= claims.size():
		return false
	_push_undo()
	claims[index].box = box
	return true


func set_claim_kind(index: int, kind: StringName) -> bool:
	if index < 0 or index >= claims.size():
		return false
	_push_undo()
	claims[index].kind = kind
	return true


func remove_claim(index: int) -> bool:
	if index < 0 or index >= claims.size():
		return false
	_push_undo()
	claims.remove_at(index)
	return true


## Declares this section's edge on `side`, **replacing** whatever was there.
##
## Replacement rather than append, because `SectionSerializer.describe_problems` treats a second
## edge on one side as an authoring defect ("a side has one") — an editor whose only verb produced
## that state would be an editor that makes the mistake for you.
func set_edge(
	side: StringName,
	kind: StringName,
	join_tag: StringName = &"",
	openings: Array[int] = [],
	opening_height: float = 0.0
) -> void:
	_push_undo()
	for index: int in range(edges.size() - 1, -1, -1):
		if edges[index] != null and edges[index].side == side:
			edges.remove_at(index)
	edges.append(SectionEdge.new(side, kind, join_tag, openings, opening_height))


func clear_edge(side: StringName) -> bool:
	for index: int in range(edges.size() - 1, -1, -1):
		if edges[index] != null and edges[index].side == side:
			_push_undo()
			edges.remove_at(index)
			return true
	return false


## Declares that `tag` may appear at `cell` with probability `chance`, replacing any declaration
## already at that cell of the same `kind`. Clutter and spawners are different statements about one
## cell and both are legitimate there, which is why the kind is part of the identity.
func set_cell_chance(
	cell: Vector2i, kind: StringName, tag: StringName, chance: float
) -> SectionSpawn:
	_push_undo()
	for index: int in range(spawns.size() - 1, -1, -1):
		var spawn: SectionSpawn = spawns[index]
		if spawn != null and spawn.cell == cell and spawn.kind == kind:
			spawns.remove_at(index)
	var declared := SectionSpawn.new(cell, kind, tag, chance)
	spawns.append(declared)
	return declared


func clear_cell_chance(cell: Vector2i, kind: StringName) -> bool:
	for index: int in range(spawns.size() - 1, -1, -1):
		var spawn: SectionSpawn = spawns[index]
		if spawn != null and spawn.cell == cell and spawn.kind == kind:
			_push_undo()
			spawns.remove_at(index)
			return true
	return false


## Sets a whole-section declaration by property name. False for a name `SectionFile` does not
## export — the same degrade-visibly posture `ViewModule.configure` takes, except that this one
## answers, because an authoring surface writing a field nothing reads is exactly the silent no-op
## this project keeps deleting.
func set_section_field(name: StringName, value: Variant) -> bool:
	if not declaration_fields().has(name):
		return false
	_push_undo()
	section_fields[name] = value
	return true


func section_field(name: StringName) -> Variant:
	if section_fields.has(name):
		return section_fields[name]
	return SectionFile.new().get(name)


# --- undo ----------------------------------------------------------------------------------


## Restores the model to the state before the last mutating verb. False when there is nothing to
## go back to.
func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_restore(_undo_stack.pop_back())
	return true


func undo_depth() -> int:
	return _undo_stack.size()


# --- save and load -------------------------------------------------------------------------


## The authored board as a `MapFile`. Sparse arrays are emitted in row-major order so the same
## board always saves to the same file — `MapSerializer.to_map_file`'s own reasoning, and half of
## what a committed map is for.
func to_map_file() -> MapFile:
	var map := MapFile.new()
	map.map_name = board_name
	map.width = width
	map.rows = rows
	map.placements = _copied_placements()
	for y: int in range(rows):
		for x: int in range(width):
			var cell := Vector2i(x, y)
			if spawn_markers.has(cell):
				map.spawn_cells.append(cell)
				map.spawn_markers.append(int(spawn_markers[cell]))
	return map


## The authored board as a `SectionFile`, carrying claims, edges and the authoring vocabulary.
##
## **Spawn markers are deliberately not written.** `SectionFile` has nowhere to put
## either, and a section's "a unit may start here" is `SectionSpawn`'s spawner kind rather than a
## map's squad marker — writing one as the other would be a second meaning for the same authoring
## gesture.
func to_section_file() -> SectionFile:
	var section := SectionFile.new()
	section.section_name = board_name
	section.width = width
	section.rows = rows
	section.placements = _copied_placements()
	for claim: SectionClaim in claims:
		section.claims.append(claim.duplicate(true))
	for edge: SectionEdge in edges:
		section.edges.append(edge.duplicate(true))
	for spawn: SectionSpawn in spawns:
		section.spawns.append(spawn.duplicate(true))
	for name: StringName in section_fields:
		section.set(name, section_fields[name])
	return section


## Replaces the model with `map`'s contents. **Clears the undo stack** — undoing across a load
## would restore a board the author is no longer editing, which reads as the editor losing their
## work rather than as an undo.
func load_map(map: MapFile) -> bool:
	if map == null:
		return false
	_reset()
	board_name = map.map_name
	width = map.width
	rows = map.rows
	for placement: MapPlacement in map.placements:
		if placement != null:
			placements.append(placement.duplicate(true))
	for index: int in range(mini(map.spawn_cells.size(), map.spawn_markers.size())):
		spawn_markers[map.spawn_cells[index]] = map.spawn_markers[index]
	target = TARGET_MAP
	return true


func load_section(section: SectionFile) -> bool:
	if section == null:
		return false
	_reset()
	board_name = section.section_name
	width = section.width
	rows = section.rows
	for placement: MapPlacement in section.placements:
		if placement != null:
			placements.append(placement.duplicate(true))
	for claim: SectionClaim in section.claims:
		if claim != null:
			claims.append(claim.duplicate(true))
	for edge: SectionEdge in section.edges:
		if edge != null:
			edges.append(edge.duplicate(true))
	for spawn: SectionSpawn in section.spawns:
		if spawn != null:
			spawns.append(spawn.duplicate(true))
	for name: StringName in declaration_fields():
		section_fields[name] = section.get(name)
	target = TARGET_SECTION
	return true


## Writes the authored board to `path` in whichever format `target` names. `{"error": ""}` on
## success, `{"error": "<reason>"}` otherwise — never a crash and never a silent failure, the same
## shape `MapSerializer.to_grid` answers in.
func save_to(path: String) -> Dictionary:
	var resource: Resource = to_section_file() if target == TARGET_SECTION else to_map_file()
	var code: int = ResourceSaver.save(resource, path)
	if code != OK:
		return {"error": "could not write '%s' (error %d)" % [path, code]}
	return {"error": ""}


## The board this model describes, through `MapSerializer` exactly as a loaded map would be.
## `{"grid": Grid, "error": "", "skipped": Array[String]}` or `{"error": "<reason>"}`.
##
## **This is the one route from the model to a board**, which is what makes "run a test bout on it"
## honest: the bout gets the board the serializer produces, not a second construction that happens
## to look the same.
##
## taskblock-59 Pass A: **built leniently, which is what stops a preview freezing.** A strict build
## refuses the whole model over one placement it cannot hold, and the editor's redraw then had
## nothing to draw and left the previous board on screen — the state corruption where every later
## edit was authored invisibly. Leniently, everything drawable is drawn and the rest arrive in
## `skipped`, which `warnings()` puts in front of the author. **The bout path is untouched and still
## strict**: `run_test_bout` goes through `to_map_file` and the injector, which refuses a board it
## cannot build rather than playing a partial one.
func to_grid() -> Dictionary:
	return MapSerializer.to_grid(to_map_file(), true)


# --- warnings ------------------------------------------------------------------------------


## Everything wrong with the authored board, as sentences an author reads. **Never a gate** —
## taskblock-56 Pass F4: *"An authored board that fails the navigability invariant still loads.
## Authoring a deliberately broken board is legitimate; the editor says so and does not refuse."*
##
## Which questions get asked depends on `target`, because the two formats disagree about what a
## defect is — see the class note.
func warnings() -> Array[String]:
	var found: Array[String] = []
	found.append_array(_undrawn_warnings())
	if target == TARGET_SECTION:
		found.append_array(SectionSerializer.describe_problems(to_section_file()))
	else:
		found.append_array(MapSerializer.describe_problems(to_map_file()))
	found.append_array(_grammar_warnings())
	found.append_array(navigability_warnings())
	return found


## The cells an author can walk into and not back out of, as a sentence. Empty when the board is
## navigable or has no spawn to flood from.
##
## **A warning rather than a refusal, and that is the whole of F4.** `MapNavigability`'s own header
## says stranding is a legitimate outcome and unnavigable *generated* ground is not; an author is
## not a generator, so an authored pit is a choice the editor reports and does not overrule.
func navigability_warnings() -> Array[String]:
	var result: Dictionary = to_grid()
	if not result.has("grid"):
		return []
	var stranded: Array[Vector2i] = MapNavigability.stranding_cells(result["grid"] as Grid)
	if stranded.is_empty():
		return []
	return [
		(
			"%d cell(s) can be walked into and not back out of, starting at %s"
			% [stranded.size(), stranded[0]]
		)
	]


## **Everything in the model that is not on the board**, said in the render's own words.
##
## taskblock-59 Pass A: this used to be `_bounds_warnings`, a second sweep that re-derived
## out-of-bounds and unknown-part from the same placements `MapSerializer` was about to reject —
## two formulas answering *"is this placement drawable"*, which is the arrangement this project
## keeps deleting. The lenient build already returns exactly that list, so asking it is both
## shorter and **guaranteed to match what the author is looking at**: a warning that named a
## placement the board was drawing anyway, or missed one it had silently dropped, is worse than no
## warning at all.
##
## The board's own dimensions stay here, because a board with no cells has no render to ask.
func _undrawn_warnings() -> Array[String]:
	if width <= 0 or rows <= 0:
		return ["the board is %dx%d; nothing can be placed on it" % [width, rows]]
	var result: Dictionary = to_grid()
	if not result.has("grid"):
		return [str(result["error"])]
	var found: Array[String] = []
	found.assign(result["skipped"])
	return found


## Placements that violate the attachment grammar — a side-attaching part with nothing to attach
## to, or a `GROUND` part on a cell that already has a surface.
##
## **Replayed in authored order against a growing board**, because the grammar is about the act of
## placing: a catwalk is legal only once the thing it spans from exists. Built with
## `Grid.add_surface` rather than `GridPlacement.place`, so the board being checked is the one the
## loader actually produces — checking against a board built by a different call would be checking
## a board nobody loads.
func _grammar_warnings() -> Array[String]:
	if width <= 0 or rows <= 0:
		return []
	var found: Array[String] = []
	var grid := Grid.new(width, rows)
	for index: int in range(placements.size()):
		var placement: MapPlacement = placements[index]
		if placement == null or not grid.in_bounds(placement.cell):
			continue
		var part: Part = DataLibrary.get_part(placement.part_id)
		if part == null:
			continue
		if placement.kind != MapPlacement.KIND_SURFACE:
			continue
		if not GridPlacement.can_place(grid, placement.cell, part, placement.height):
			# **Two different refusals, and they used to read as one.** `GridPlacement.can_place`
			# rejects a GROUND part when the cell already has a surface, and a side-attaching part
			# when nothing is there to attach to — opposite problems. Reporting both as "has nothing
			# to attach to" is what made a second floor on one cell read as a broken floor part; the
			# UI review asked *"Shipfloor complaining that it doesn't have anything to attach to. Is
			# that expected?"* and the answer was yes, about the wrong thing.
			var reason: String = (
				"the cell already has a surface"
				if GridPlacement.GROUND in part.attaches_to
				else "nothing to attach to at height %.2f" % placement.height
			)
			found.append(
				"placement %d ('%s') at %s: %s" % [index, placement.part_id, placement.cell, reason]
			)
		grid.add_surface(placement.cell, Surface.new(part, placement.height, placement.facing))
	return found


# --- internals -----------------------------------------------------------------------------


func _top_surface(cell: Vector2i) -> MapPlacement:
	for index: int in range(placements.size() - 1, -1, -1):
		var placement: MapPlacement = placements[index]
		if (
			placement != null
			and placement.cell == cell
			and placement.kind == MapPlacement.KIND_SURFACE
		):
			return placement
	return null


## Copies, never the model's own resources. A saved file that shares placement instances with the
## live model is a file that keeps changing after it was written.
func _copied_placements() -> Array[MapPlacement]:
	var copies: Array[MapPlacement] = []
	for placement: MapPlacement in placements:
		if placement != null:
			copies.append(placement.duplicate(true))
	return copies


func _reset() -> void:
	placements = []
	spawn_markers = {}
	claims = []
	edges = []
	spawns = []
	section_fields = {}
	_undo_stack = []


## The whole model, deep-copied. `duplicate(true)` throughout: a `SectionClaim` holds a `Box` and a
## `SectionEdge` holds an `openings` array, so a shallow copy would restore a claim whose extent
## kept changing under it.
func _snapshot() -> Dictionary:
	var snapshot_claims: Array[SectionClaim] = []
	for claim: SectionClaim in claims:
		snapshot_claims.append(claim.duplicate(true) if claim != null else null)
	var snapshot_edges: Array[SectionEdge] = []
	for edge: SectionEdge in edges:
		snapshot_edges.append(edge.duplicate(true) if edge != null else null)
	var snapshot_spawns: Array[SectionSpawn] = []
	for spawn: SectionSpawn in spawns:
		snapshot_spawns.append(spawn.duplicate(true) if spawn != null else null)
	return {
		"board_name": board_name,
		"width": width,
		"rows": rows,
		"placements": _copied_placements(),
		"spawn_markers": spawn_markers.duplicate(true),
		"claims": snapshot_claims,
		"edges": snapshot_edges,
		"spawns": snapshot_spawns,
		"section_fields": section_fields.duplicate(true),
		"target": target,
	}


func _restore(snapshot: Dictionary) -> void:
	board_name = snapshot["board_name"]
	width = snapshot["width"]
	rows = snapshot["rows"]
	placements = snapshot["placements"]
	spawn_markers = snapshot["spawn_markers"]
	claims = snapshot["claims"]
	edges = snapshot["edges"]
	spawns = snapshot["spawns"]
	section_fields = snapshot["section_fields"]
	target = snapshot["target"]


## Deliberately called by every mutating verb *before* it mutates, including the ones that turn out
## to change nothing measurable. The alternative — only pushing when something really changed —
## makes undo's step count depend on the model's contents, so an author's third undo lands
## somewhere different depending on what their second edit happened to hit.
func _push_undo() -> void:
	_undo_stack.append(_snapshot())
	if _undo_stack.size() > UNDO_DEPTH:
		_undo_stack.remove_at(0)
