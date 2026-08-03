extends SceneTree

## taskblock-54 Pass D: authors the project's first sections into `res://data/sections/`. Run via
## `godot --headless -s res://tools/author_taskblock54_sections.gd`; kept afterward as the record
## of what each section is *for*, which the `.tres` cannot say.
##
## ## Three sections, chosen to prove the edge metadata says something true
##
## The taskblock asks for "at minimum one with an open edge, one that satisfies it, and one that
## deliberately does not". These are those three, and nothing more — proving a join needs a pair
## that fits and a third that provably does not.
##
## ```
##   west_hall (6x4)          east_hall (6x4)         sealed_bay (6x4)
##   +------+                 +------+                +------+
##   |......|                 |......|                |######|   # wall
##   |......|== corridor_4w ==|......|                |......|   . floor
##   |......|   (east/west)   |......|                |......|
##   +------+                 +------+                +------+
##   east edge: open          west edge: open         west edge: EXTERIOR
##   tag corridor_4w          tag corridor_4w         (refuses everything)
## ```
##
## **The openings are a subset of the side, not the whole side.** Both halls open only on rows 1
## and 2 of their four — a corridor mouth in an otherwise solid edge. A whole-side opening would
## have joined just as well and would have proved less: `_openings_of` expands an empty list to
## the entire span, so two sections that each said "all of it" would match without the opening
## comparison ever doing work.
##
## **`sealed_bay` is the same size and the same shape and still cannot join**, which is the point
## of it. If a refusal only ever happened for sections that looked obviously different, the edge
## metadata would not be carrying the decision — geometry would.

const OUT_DIR := "res://data/sections"
const WIDTH := 6
const ROWS := 4
## Rows 1 and 2 of 4 — the corridor mouth. Deliberately not the whole side; see above.
const MOUTH: Array[int] = [1, 2]
const CORRIDOR_TAG: StringName = &"corridor_4w"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var wrote := 0
	wrote += _write(_hall("West Hall", SectionEdge.SIDE_EAST), "%s/west_hall.tres" % OUT_DIR)
	wrote += _write(_hall("East Hall", SectionEdge.SIDE_WEST), "%s/east_hall.tres" % OUT_DIR)
	wrote += _write(_sealed_bay(), "%s/sealed_bay.tres" % OUT_DIR)
	print("wrote %d section(s) into %s" % [wrote, OUT_DIR])
	quit(0 if wrote == 3 else 1)


## A plain hall: floor throughout, one open side carrying the corridor mouth, everything else
## exterior.
func _hall(name: String, open_side: StringName) -> SectionFile:
	var section := SectionFile.new()
	section.section_name = name
	section.width = WIDTH
	section.rows = ROWS
	for y: int in range(ROWS):
		for x: int in range(WIDTH):
			section.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor", 0.0)
			)
	section.edges = [
		SectionEdge.new(open_side, SectionEdge.KIND_OPEN, CORRIDOR_TAG, MOUTH.duplicate()),
		SectionEdge.new(SectionEdge.opposite(open_side), SectionEdge.KIND_EXTERIOR),
		SectionEdge.new(SectionEdge.SIDE_NORTH, SectionEdge.KIND_EXTERIOR),
		SectionEdge.new(SectionEdge.SIDE_SOUTH, SectionEdge.KIND_EXTERIOR),
	]
	return section


## The one that deliberately does not join: same size, same floor, and a **west edge that is
## exterior**. `can_join` reads both sides, so this refuses `West Hall` even though `West Hall`
## is perfectly willing.
func _sealed_bay() -> SectionFile:
	var section := SectionFile.new()
	section.section_name = "Sealed Bay"
	section.width = WIDTH
	section.rows = ROWS
	for x: int in range(WIDTH):
		section.placements.append(
			MapPlacement.new(Vector2i(x, 0), MapPlacement.KIND_BLOCKER, &"wall")
		)
	for y: int in range(1, ROWS):
		for x: int in range(WIDTH):
			section.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor", 0.0)
			)
	section.edges = [
		SectionEdge.new(SectionEdge.SIDE_WEST, SectionEdge.KIND_EXTERIOR),
		SectionEdge.new(SectionEdge.SIDE_EAST, SectionEdge.KIND_EXTERIOR),
		SectionEdge.new(SectionEdge.SIDE_NORTH, SectionEdge.KIND_EXTERIOR),
		SectionEdge.new(SectionEdge.SIDE_SOUTH, SectionEdge.KIND_EXTERIOR),
	]
	return section


func _write(section: SectionFile, path: String) -> int:
	for problem: String in SectionSerializer.describe_problems(section):
		print("authoring warning (%s): %s" % [section.section_name, problem])
	var err: Error = ResourceSaver.save(section, path)
	if err != OK:
		printerr("failed to write %s: %d" % [path, err])
		return 0
	print("  %s — %s" % [path, section.section_name])
	return 1
