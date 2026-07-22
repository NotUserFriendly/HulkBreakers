shader_type spatial;

// tb32 Pass A: the wall occlusion cutout — supersedes tb31 Pass C's
// per-object GDScript alpha (`BoardView.WALL_FADE_ALPHA`/_set_wall_alpha,
// one focal unit at a time). This is a normal LIT spatial shader —
// ALBEDO/lighting untouched (docs/10: real geometry stays lit) — that
// `discard`s fragments inside a dithered porthole around every unit
// GDScript feeds it, instead of Godot's built-in Alpha Hash mode (still
// routes through the transparent pipeline and drops shadows, a known
// engine issue). GDScript's only job per frame
// (`BoardView.update_wall_cutout`) is projecting each relevant unit's
// screen position/depth/radius via `WallLegibility.pixel_radius_for_tiles`
// and feeding them here — this fragment function is the only place that
// decides whether a given pixel is inside the hole.
//
// BR32.02, settled entirely by live testing — no headless test can
// exercise a fragment shader at all (dummy/headless rendering never
// executes one), so every claim below was confirmed against a real,
// rendered build, not GUT:
// - `FRAGCOORD.xy` is TOP-left origin, Y-DOWN, matching
//   `Camera3D.unproject_position()` NATIVELY (confirmed via a hardcoded-
//   corner diagnostic — a fixed hole at (200, 200) landed at the
//   window's own top-left corner) — no Y-flip is needed between the two,
//   despite documentation suggesting `FRAGCOORD` matches GLSL's
//   bottom-left-origin `gl_FragCoord` default (a flip tried on that
//   basis made things worse, not better, and was reverted).
// - `VERTEX`, despite being documented to already arrive in view space
//   by the time `fragment()` reads it, did NOT behave that way here:
//   `length(VERTEX)` compared against the fed `unit_depths[i]` was wrong
//   in BOTH comparison directions (ruling out a simple sign flip).
//   Depth is instead reconstructed directly from the hardware depth
//   buffer (`FRAGCOORD.z` + `INV_PROJECTION_MATRIX`, Godot's own
//   standard recipe for this) below — confirmed live to correctly gate
//   the cutout on which side of a wall the camera is on.
// Still open (deferred, not a regression from this fix): with the
// camera and unit on the SAME side of a wall (nothing should occlude at
// all), the cutout still fires and over-cuts neighboring wall segments.
// Likely inherent to this shader's own 2D screen-space heuristic ("is
// this fragment nearer than the unit AND within its screen radius") —
// see `taskblock_done/Report-Taskblock32.md` for the fuller writeup and
// a candidate cause.

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);

const int MAX_UNITS = 32;
uniform vec2 unit_screen_positions[MAX_UNITS];
uniform float unit_depths[MAX_UNITS];
uniform float unit_radii_px[MAX_UNITS];
uniform int unit_count = 0;

// 4x4 ordered (Bayer) dither, normalized to [0, 1) — the "grainy edge"
// the taskblock asks for, not a hard-edged ring.
const float DITHER[16] = float[](
	0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
	3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
	15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0
);
// The last few pixels of a unit's own radius ramp from solid hole to
// fully opaque instead of cutting off hard.
const float DITHER_BAND_PX = 6.0;

void fragment() {
	ALBEDO = albedo.rgb;

	// BR32.02: true view-space depth, reconstructed from the hardware
	// depth buffer rather than trusting `VERTEX` (which did not behave
	// as documented here — see this file's own header comment). Matches
	// the Euclidean "camera to point" convention `WallLegibility`/
	// `BoardView` already use on the GDScript side
	// (`camera.global_position.distance_to(...)`) for `unit_depths[i]`,
	// so the two sides of the depth compare below agree.
	vec2 ndc_xy = (FRAGCOORD.xy / VIEWPORT_SIZE) * 2.0 - 1.0;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc_xy, FRAGCOORD.z, 1.0);
	view_pos.xyz /= view_pos.w;
	float frag_depth = length(view_pos.xyz);
	int dither_index = int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4;
	float dither_value = DITHER[dither_index];

	for (int i = 0; i < unit_count; i++) {
		// Depth compare: don't cut a wall that's behind the unit it would
		// be "protecting" — only a wall nearer the camera than the unit
		// can be hiding it. Same-side-of-wall over-cutting is a known,
		// deferred limitation of this screen-space-only heuristic — see
		// this file's own header comment.
		if (frag_depth >= unit_depths[i]) {
			continue;
		}
		float d = distance(FRAGCOORD.xy, unit_screen_positions[i]);
		float radius = unit_radii_px[i];
		if (d <= radius - DITHER_BAND_PX) {
			discard;
		} else if (d <= radius) {
			float t = (radius - d) / DITHER_BAND_PX;
			if (dither_value < t) {
				discard;
			}
		}
	}
}
