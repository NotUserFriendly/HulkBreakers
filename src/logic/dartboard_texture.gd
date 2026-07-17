class_name DartboardTexture
extends RefCounted

## docs/09 taskblock06 Pass H: "an image of a dartboard" — the ring
## image's own pixel math. Pure and headless-testable (TracerGeometry's own
## precedent, src/logic/tracer_geometry.gd: the only consumer is rendering,
## but the placement math itself has nothing to do with a live renderer).
## Returns a plain Image; the view wraps it in an ImageTexture — nothing
## here touches a Texture2D or a live GPU.

const DEFAULT_SIZE := 128
## Alternating band alpha (docs/09: "clearly shows what's being targeted")
## — adjacent rings must read as visually distinct bands, not one solid
## disc blurring every ring together.
const BAND_ALPHA_A := 0.6
const BAND_ALPHA_B := 0.35


## One RGBA Image, `size` x `size` pixels: alpha-only concentric ring bands
## (transparent outside the outermost ring) over `color`'s own RGB. Rings
## are assumed ascending by radius (Dartboard.resolve_scatter's own
## convention). The outermost ring exactly touches the image edge (radius
## = size/2 in pixels) — a caller sizes the world quad/Decal to
## `2 * rings.back().radius` so texture space maps 1:1 onto world space,
## no separate scale factor to keep in sync.
static func build(rings: Array[Ring], color: Color, size: int = DEFAULT_SIZE) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	if rings.is_empty():
		return image
	var outer_radius: float = rings[rings.size() - 1].radius
	if outer_radius <= 0.0:
		return image
	var center: float = size / 2.0
	var px_per_unit: float = center / outer_radius
	for y in range(size):
		for x in range(size):
			var dx: float = (x + 0.5) - center
			var dy: float = (y + 0.5) - center
			var world_dist: float = sqrt(dx * dx + dy * dy) / px_per_unit
			var ring_index: int = _ring_index_at(rings, world_dist)
			if ring_index < 0:
				continue
			var alpha: float = BAND_ALPHA_A if ring_index % 2 == 0 else BAND_ALPHA_B
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha * color.a))
	return image


## The index of the first ring whose radius >= dist, or -1 outside every
## ring entirely.
static func _ring_index_at(rings: Array[Ring], dist: float) -> int:
	for i in range(rings.size()):
		if dist <= rings[i].radius:
			return i
	return -1
