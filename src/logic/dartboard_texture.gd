class_name DartboardTexture
extends RefCounted

## docs/09 taskblock06 Pass H / taskblock07 Pass D: "an image of a
## dartboard" — the ring image's own pixel math, plus (Pass D) the
## majority-ring weighting and central aiming dot that make it read as an
## actual dartboard rather than a stack of uniform bands. Pure and
## headless-testable (TracerGeometry's own precedent, src/logic/
## tracer_geometry.gd: the only consumer is rendering, but the placement
## math itself has nothing to do with a live renderer). Returns a plain
## Image; the view wraps it in an ImageTexture — nothing here touches a
## Texture2D or a live GPU.

const DEFAULT_SIZE := 128

## docs/09 taskblock07 Pass D: "ring weight should read visually... weight
## it in line thickness or fill, not just radius." Each ring's own fill
## alpha scales with its own weight relative to the heaviest ring in the
## array (the "majority" ring the player's eye should land on) — never a
## fixed alternation blind to the actual probability, and never assuming
## any particular ring count (the standing rule: read the array's size).
## Clamped to this floor/ceiling so even a vanishingly light ring still
## reads as present, and the majority ring never fully occludes the
## geometry behind it.
const MIN_BAND_ALPHA := 0.18
const MAX_BAND_ALPHA := 0.65
## A crisp, brighter rim at each ring's own outer edge — legible band
## separation even between two rings whose weights happen to be close,
## never relying on fill alone.
const EDGE_ALPHA := 0.85
const EDGE_WIDTH_FRACTION := 0.05

## docs/09 taskblock07 Pass D: "a central aiming dot, distinct from the
## rings... [that] casts a more distinct shadow on the target than the
## rings do." Full opacity, and its own radius is a FRACTION of the outer
## ring's (not a fixed pixel/world size) so it scales with the reticle
## the same way the rings do, rather than visually detaching from them at
## a different weapon's scatter scale.
const DOT_ALPHA := 1.0
const DOT_RADIUS_FRACTION := 0.06

## tb34 Pass B: burst recoil's own outer bound — the widest pull's ring
## (`AimController.recoil_bound_radius`), drawn as a crisp OUTLINE only
## (no probability fill), visually distinct from the weighted bands so it
## reads as a bound, not one more band. Weapon-constant (its ratio to the
## weighted rings' own outer radius never varies with range — see that
## function's own doc comment), so baking it into this same cached
## texture is safe, unlike Pass B's OTHER new element (the pellet-spread
## circle), whose ratio to the outer ring genuinely does vary with range
## and must stay a separate, un-cached overlay instead.
const BOUND_RING_ALPHA := 0.9
const BOUND_RING_WIDTH_FRACTION := 0.02


## One RGBA Image, `size` x `size` pixels: a central aiming dot plus
## alpha-weighted concentric ring bands (transparent outside the
## outermost ring) over `color`'s own RGB. Rings are assumed ascending by
## radius (Dartboard.resolve_scatter's own convention). The outermost
## ring exactly touches the image edge (radius = size/2 in pixels) UNLESS
## `bound_radius` reaches farther, in which case bound_radius does instead
## (0.0, the default, means "no bound to draw" — every ratio/edge
## computation below collapses to the pre-tb34-Pass-B behavior exactly).
## A caller sizes the world quad/Decal to `2 * max(rings.back().radius,
## bound_radius)` so texture space maps 1:1 onto world space, no separate
## scale factor to keep in sync.
static func build(
	rings: Array[Ring], color: Color, size: int = DEFAULT_SIZE, bound_radius: float = 0.0
) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	if rings.is_empty():
		return image
	var rings_outer: float = rings[rings.size() - 1].radius
	if rings_outer <= 0.0:
		return image
	var canvas_radius: float = maxf(rings_outer, bound_radius)
	var center: float = size / 2.0
	var px_per_unit: float = center / canvas_radius
	var max_weight: float = _max_weight(rings)
	var dot_radius: float = rings_outer * DOT_RADIUS_FRACTION
	var draw_bound: bool = bound_radius > rings_outer
	var bound_band: float = bound_radius * BOUND_RING_WIDTH_FRACTION

	for y in range(size):
		for x in range(size):
			var dx: float = (x + 0.5) - center
			var dy: float = (y + 0.5) - center
			var world_dist: float = sqrt(dx * dx + dy * dy) / px_per_unit

			if world_dist <= dot_radius:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, DOT_ALPHA * color.a))
				continue

			if draw_bound and absf(world_dist - bound_radius) <= bound_band:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, BOUND_RING_ALPHA * color.a))
				continue

			var ring_index: int = _ring_index_at(rings, world_dist)
			if ring_index < 0:
				continue
			var alpha: float = _alpha_at(rings, ring_index, world_dist, max_weight)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha * color.a))
	return image


## tb34 Pass B: a plain, fully-opaque filled circle exactly touching the
## image edge (radius = size/2) — the pellet-spread overlay's own texture,
## kept deliberately separate from `build()`'s own ring machinery. The
## overlay's WORLD size (the caller's own quad sizing) is what encodes
## `SpreadPattern.pattern_radius`, never this image's own content, which
## never varies — cacheable once, forever, unlike the range-aware ring
## texture above (which is exactly why the pellet circle can't just be a
## bigger baked-in dot: its ratio to the range-scaled outer ring isn't
## constant, but this image never needs a ratio at all).
static func build_solid_dot(color: Color, size: int = DEFAULT_SIZE) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = size / 2.0
	for y in range(size):
		for x in range(size):
			var dx: float = (x + 0.5) - center
			var dy: float = (y + 0.5) - center
			if sqrt(dx * dx + dy * dy) <= center:
				image.set_pixel(x, y, color)
	return image


## `ring_index`'s own fill alpha, weighted by its probability relative to
## the heaviest ring — except within EDGE_WIDTH_FRACTION of its own outer
## boundary, which always renders at the same crisp EDGE_ALPHA regardless
## of weight (the band-separation guarantee).
static func _alpha_at(
	rings: Array[Ring], ring_index: int, world_dist: float, max_weight: float
) -> float:
	var ring: Ring = rings[ring_index]
	var inner: float = 0.0 if ring_index == 0 else rings[ring_index - 1].radius
	var band_span: float = maxf(ring.radius - inner, 0.001)
	if ring.radius - world_dist <= band_span * EDGE_WIDTH_FRACTION:
		return EDGE_ALPHA
	return _fill_alpha(ring, max_weight)


static func _fill_alpha(ring: Ring, max_weight: float) -> float:
	if max_weight <= 0.0:
		return MIN_BAND_ALPHA
	var fraction: float = clampf(ring.weight / max_weight, 0.0, 1.0)
	return lerpf(MIN_BAND_ALPHA, MAX_BAND_ALPHA, fraction)


static func _max_weight(rings: Array[Ring]) -> float:
	var result: float = 0.0
	for ring: Ring in rings:
		result = maxf(result, ring.weight)
	return result


## The index of the first ring whose radius >= dist, or -1 outside every
## ring entirely.
static func _ring_index_at(rings: Array[Ring], dist: float) -> int:
	for i in range(rings.size()):
		if dist <= rings[i].radius:
			return i
	return -1
