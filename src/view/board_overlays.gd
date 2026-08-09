class_name BoardOverlays
extends RefCounted

## **The board's static annotations, built from data rather than from parts.** tb62 Pass B.
##
## Distinct from what `BoardView._build_tiles` draws: those are real placed `Part` geometry,
## the same boxes a ray marches. These are *statements about cells* — where a team extracts,
## where a lift pair stands — drawn on the ordered ground-overlay height ladder and never
## claiming to be solid.
##
## ## The mag lift pad, to the supervisor's spec (2026-08-09)
##
## *"The top and bottom surfaces both a 50% opacity navy blue square, with a 100% opacity,
## narrow, navy blue border."* Two elements per pad — a translucent fill under an opaque
## outline — built from `OverlayMarkers`' existing `flat_box`/`hollow_box` pair rather than
## from new geometry.
##
## ## Why this is its own file
##
## `board_view.gd` sat at **exactly** `gdlint`'s 1000-line cap, and this is the third
## extraction that file has needed — the cutout logger (`src/debug/cutout_log.gd`) and marker
## construction (`OverlayMarkers`) preceded it. It is not filed under `OverlayMarkers`
## because that class states outright that it *"deliberately knows nothing about grids"*, and
## these do: a pad's position and its **height** both come from the placement store, so
## reading the grid is the whole job.
##
## The extraction cells came along because they are the same kind of thing and were the only
## other resident of that category — one home for "annotations about cells", rather than a
## file per annotation.
##
## ## This is the pad's ONLY appearance
##
## `mag_lift_pad` authors no `volume`, so `BoardView._build_tiles` draws nothing for it and
## `RayCaster`/`ShotPlane` find no geometry — which is what makes *"neither surface blocks
## shots"* structurally true instead of measured-thin. There is no box for these markers to
## be a second drawing of, so the co-planar pairing taskblock-55 Pass B deleted cannot recur.

## Literal navy, flagged and tunable like every other palette entry. The pad reads against
## the tile colour beneath it, never against the backdrop.
const COLOR := Color("#000080")
const FILL_ALPHA := 0.5

## Two rungs on the ordered ground-overlay height ladder enumerated at
## `BoardView.EXTRACTION_CELL_HEIGHT` — the next free pair, above the ghost rung (0.03) and
## below the field-item marker (0.045), rather than values picked independently. **The border
## sits above the fill** because a hollow outline's bars overlap the fill's outer band, and
## the 100% opacity edge is what has to win there.
const FILL_HEIGHT := 0.035
const BORDER_HEIGHT := 0.040

## Narrow, per the spec — about a third of `OverlayMarkers.RING_THICKNESS`, which is sized to
## read as a waypoint outline rather than as a trim line.
const BORDER_THICKNESS := 0.03

const PAD_SIZE := 0.8

## `BoardView.EXTRACTION_CELL_HEIGHT`'s own rung, and `BoardView.OVERLAY_SIZE`'s own size —
## named here rather than reached for across the boundary so this class needs no `BoardView`
## at all. The ladder those numbers belong to is still enumerated in that file.
const EXTRACTION_HEIGHT := 0.010
const EXTRACTION_SIZE := 0.8


## **Team-coded extraction cells, drawn in their team's colour** — one flat marker per cell,
## `WorldPalette.team_color(squad_id)` like every other team-coded visual (docs/10). Returns
## how many it drew (taskblock-41 Pass D).
##
## `heights` maps a cell to the world height its marker should sit on, so a marker over
## raised ground rides its own tile rather than floating below it. `BoardView` resolves it
## from the grid; this class does not need to know how.
static func extraction_cells_into(
	parent: Node3D, team_extraction_cells: Dictionary, heights: Callable
) -> int:
	var count := 0
	for squad_id: int in team_extraction_cells:
		var color: Color = WorldPalette.team_color(squad_id)
		var cells: Array = team_extraction_cells[squad_id]
		for cell: Vector2i in cells:
			var world_y: float = float(heights.call(cell)) + EXTRACTION_HEIGHT
			parent.add_child(OverlayMarkers.flat_box(cell, color, world_y, EXTRACTION_SIZE))
			count += 1
	return count


## Adds one holder per placed mag lift pad to `parent`, and returns how many it added.
##
## **Driven off the placements, never off a cell sweep.** A pad is a real `Surface` at a real
## height, and the pair's two ends genuinely sit at different elevations — a per-cell walk
## asking `true_height_for_cell` would flatten the upper pad onto the floor beneath it, which
## is precisely the elevation the lift exists to express.
static func mag_lift_pads_into(parent: Node3D, grid: Grid) -> int:
	var added := 0
	for surface: Surface in grid.placements():
		if not Surface.MAG_LIFT_TAG in surface.part.tags:
			continue
		parent.add_child(pad(surface.cell, surface.height))
		added += 1
	return added


## One pad's marker: the translucent fill and the opaque border, parented together so a
## caller adds and counts a *pad* rather than two loose meshes.
##
## `world_y` is the pad's own placed height, taken straight from its `Surface`.
static func pad(cell: Vector2i, world_y: float) -> Node3D:
	var holder := Node3D.new()
	var fill: Color = COLOR
	fill.a = FILL_ALPHA
	holder.add_child(OverlayMarkers.flat_box(cell, fill, world_y + FILL_HEIGHT, PAD_SIZE))
	holder.add_child(
		OverlayMarkers.hollow_box(
			cell, COLOR, world_y + BORDER_HEIGHT, PAD_SIZE, BORDER_THICKNESS
		)
	)
	return holder
