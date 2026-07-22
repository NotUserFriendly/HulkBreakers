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
// BR32.02: `FRAGCOORD` here matches GLSL's own `gl_FragCoord` — BOTTOM-
// left origin, Y increasing UPWARD (confirmed against Godot's own docs:
// "FRAGCOORD... use[s] the same coordinate system" as gl_FragCoord).
// `Camera3D.unproject_position()`, what `BoardView` projects every unit
// with, returns the opposite: TOP-left origin, Y-DOWN (the same
// convention mouse/UI positions use). `unit_screen_positions` therefore
// arrives here ALREADY Y-flipped by `update_wall_cutout` to match this
// fragment coordinate system — comparing the two unflipped mirrors the
// cutout vertically, so it never lands where the wall/unit actually
// overlap on screen (confirmed live: no cutout ever visibly appeared
// near a real unit standing next to a wall). No headless test can catch
// this class of bug at all — dummy/headless rendering never executes a
// fragment shader; every fragment-side claim here is a live-rendering
// fact, not something GUT verified.

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

	// View-space distance from the camera to this fragment — the same
	// Euclidean "depth" convention `WallLegibility`/`BoardView` already
	// use on the GDScript side (`camera.global_position.distance_to(...)`),
	// not a raw view-space Z, so the two sides of the depth compare agree.
	float frag_depth = length(VERTEX);
	int dither_index = int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4;
	float dither_value = DITHER[dither_index];

	for (int i = 0; i < unit_count; i++) {
		// Depth compare: don't cut a wall that's behind the unit it would
		// be "protecting" — only a wall nearer the camera than the unit
		// can be hiding it.
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
