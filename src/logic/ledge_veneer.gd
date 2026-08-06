class_name LedgeVeneer
extends RefCounted

## **A flat wall hung off a tile's edge, sized by what it reaches.** taskblock-58 Pass F.
##
## The taskblock: *"A flat wall attaching to a tile's top edge and sideways to tiles above it."* It
## is what turns a raised platform from a floating slab into something with a face — the vertical
## surface between one deck and the next.
##
## ## Its whole behaviour is "how tall am I", and it is answered by what is there
##
## *"It grows both ways and snaps to what it meets. Clicking a ledge's side grows it **down**; it
## can also grow **up**; and **if it connects at both ends it snaps to both**."*
##
## So a veneer is not authored with a height. It is grown in a direction from a tile's edge and
## takes whatever it reaches.
##
## **Two gestures, not one** — the taskblock states them as two sentences, and that is the shape the
## code takes:
##
## | gesture | meets something | meets nothing |
## |---|---|---|
## | grown **up** from a tile's top edge | snaps to it | `UNANCHORED_RISE` above the tile |
## | grown **down** from a tile's side | snaps to it | falls to the deck: its height is the tile's |
##
## **"Snaps to both" is not a third case.** It is what growing in a direction does when that
## direction finds something; the defaults exist only for when it does not. Collapsing the two
## gestures into one call was the first thing tried here and it is wrong — it makes a veneer grown
## down from a 2.5 tile with nothing under it zero tall, because "the tile" and "the anchor above"
## are the same number.
##
## ## The 0.8 default is deliberately odd, and that is the point
##
## *"Growing up from an edge, **0.8** — deliberately odd so it reads as a default rather than as
## intent."* A veneer that came up at 1.0 would be indistinguishable from one an author sized to a
## level; 0.8 is visibly not a level, so an unanchored veneer announces itself as unfinished rather
## than passing for a decision. **Flagged, not designed** — it is a legibility choice, and the real
## answer is authored ledge art whose own box height should drive it.
##
## ## The name is provisional
##
## The taskblock says so outright and asks for a better one if it turns up while building. It did
## not. *Veneer* is accurate — a facing over structure rather than structure itself — and the two
## alternatives considered were worse: *skirt* reads as decoration and would undersell a thing that
## has hp and stops shots, and *facade* carries "false front", which is exactly what this is not.

## How tall a veneer grows when nothing above it says otherwise. **Deliberately not a whole level**
## — see the class note. Flagged and tunable, not a balance figure.
const UNANCHORED_RISE: float = 0.8

## The world deck a veneer falls to when nothing under it stops it. Zero, because that is where the
## board's own ground plane is; a hulk with a floor below zero would want this asked of the board
## rather than assumed.
const DECK_HEIGHT: float = 0.0

## How close two heights have to be before they count as the same surface.
const _EPSILON: float = 0.001


## **Growing up from a tile's top edge**: `{bottom, top, height}`.
##
## `above` is the surface it meets, or `null` for nothing there — in which case it takes
## `UNANCHORED_RISE`, *"deliberately odd so it reads as a default rather than as intent."*
static func span_up(from_height: float, above: Variant) -> Dictionary:
	var top: float = above if above is float else from_height + UNANCHORED_RISE
	return _span(from_height, top)


## **Growing down from a tile's side**: `{bottom, top, height}`.
##
## `below` is the surface it lands on, or `null` for nothing there — in which case it falls to the
## deck, which makes its height *"match the picked floor tile's own height"*, the taskblock's own
## words for this case.
static func span_down(from_height: float, below: Variant) -> Dictionary:
	var bottom: float = below if below is float else DECK_HEIGHT
	return _span(bottom, from_height)


## The span for a veneer authored against `grid` at `cell`, grown from the tile at `from_height`.
##
## **The board answers the far end**, which is what *"snaps to what it meets"* means with a real
## board in front of it — and it is why *"snaps to both"* is not a third case: it is what growing in
## a direction does when that direction finds something. The defaults are only for when it does not.
static func span_at(grid: Grid, cell: Vector2i, from_height: float, grow_up: bool) -> Dictionary:
	if grow_up:
		return span_up(from_height, surface_above(grid, cell, from_height))
	return span_down(from_height, surface_below(grid, cell, from_height))


static func _span(bottom: float, top: float) -> Dictionary:
	var low: float = minf(bottom, top)
	var high: float = maxf(bottom, top)
	return {"bottom": low, "top": high, "height": high - low}


## The height of the lowest placed surface strictly above `height` at `cell`, or null.
static func surface_above(grid: Grid, cell: Vector2i, height: float) -> Variant:
	var found: Variant = null
	for surface: Surface in grid.surfaces_at(cell):
		if surface.height > height + _EPSILON:
			if found == null or surface.height < (found as float):
				found = surface.height
	return found


## The height of the highest placed surface strictly below `height` at `cell`, or null.
static func surface_below(grid: Grid, cell: Vector2i, height: float) -> Variant:
	var found: Variant = null
	for surface: Surface in grid.surfaces_at(cell):
		if surface.height < height - _EPSILON:
			if found == null or surface.height > (found as float):
				found = surface.height
	return found


## The `size` a veneer placement carries for a span, given the part's own footprint.
##
## Only the vertical is decided here — a veneer is as wide and as thick as its part says, and only
## its rise is a question about the board. `PlacedVolume` then gives it hp by volume like everything
## else in this pass, so a tall deck face is genuinely tougher than a low kerb without either being
## authored.
static func size_for(part: Part, span: Dictionary) -> Vector3:
	var natural: Vector3 = PlacedVolume.natural_size(part)
	return Vector3(natural.x, maxf(float(span["height"]), _EPSILON), natural.z)
