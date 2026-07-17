class_name WorldPalette
extends RefCounted

## docs/10: the 3D board's own palette — distinct from HulkTheme, which
## governs the terminal UI only (docs/08). Two channels, never mixed:
## MATERIAL colour is the mesh albedo (MaterialTable.color_for, the
## truthful "what is this made of" reading — see docs/01/03); ALLEGIANCE
## colour is an overlay (team ring/rim, see `team_color`/`overlay_material`
## below) that never touches albedo, so a steel plate reads as steel on
## any team, any unit, or lying on the floor as loot.

const VOID := Color("#050506")
const GROUND := Color("#2E4A32")
const TEAM_A := Color("#3A7BD5")
const TEAM_B := Color("#D53A3A")
## docs/10 taskblock05 C: the hover-highlight rim (inventory row <-> 3D
## part, bidirectional) — its own overlay colour, not a reach into
## HulkTheme (docs/08's "two palettes" rule: this file is the 3D board's
## own). Deliberately the same value as HulkTheme.HIGHLIGHT so both
## palettes read "this is highlighted" the same way, without either file
## depending on the other.
const HOVER_HIGHLIGHT := Color(0.95, 0.82, 0.25)

## ~45 degrees elevation, off-axis — enough that adjacent box faces catch
## different light and read as distinct surfaces instead of merging into
## one unshaded blob.
const LIGHT_ELEVATION_DEG := 45.0
const LIGHT_AZIMUTH_DEG := 35.0
## docs/10 taskblock02 G1: a soft neutral fill, NOT a tint of the ground —
## the original spec's "~0.25 of the ground hue" was the error (docs/04's
## own dark green at a quarter energy is nearly nothing, so any face away
## from the key light still reads as pure black). A light cool grey at
## higher energy: no face reads as pure black, tuned against
## cyborg_closeup.png (checkpoint 6) — that image is the actual test.
const AMBIENT_COLOR := Color("#8A93A0")
const AMBIENT_ENERGY := 0.35


## A flat dark backdrop plus soft ambient — otherwise Godot's default
## procedural sky paints the void a stock light grey with no relation to
## the theme, and unlit shadow faces read as pure black holes.
static func world_environment() -> WorldEnvironment:
	var node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = VOID
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	node.environment = environment
	return node


## The one real light in the scene (docs/10: "why nothing was legible" —
## unshaded same-colour boxes have no edges without one).
static func directional_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-LIGHT_ELEVATION_DEG, LIGHT_AZIMUTH_DEG, 0.0)
	return light


## Binary team mapping (squad_id 0 -> A, anything else -> B) — a flagged
## placeholder for exactly the 2-squad battles Phase 12 builds; more squads
## than that is a real design question, not an oversight to paper over here.
static func team_color(squad_id: int) -> Color:
	return TEAM_A if squad_id == 0 else TEAM_B


## Lit material for real geometry — parts, blockers — so adjacent same-
## coloured boxes separate under `directional_light()` instead of merging
## into one silhouette. Never use this for overlays; see `overlay_material`.
static func lit_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.albedo_color = color
	return material


## Unshaded flat material for UI-adjacent 3D overlays ONLY — reachable
## highlight, ghost paths, aim rings, team rings/rims. Never for real part
## or blocker geometry (docs/10: "Part and blocker meshes: SHADING_MODE_
## PER_PIXEL, not unshaded"). Named apart from lit_material so it can't be
## reached for by accident.
static func overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


## docs/10 taskblock03 F1: the end-position ghost — same unshaded
## convention as overlay_material, but alpha-blended, since a ghost has to
## read as "not really there" at a glance, never as an opaque duplicate
## unit sitting on the board.
static func translucent_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = overlay_material(color)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## docs/09 taskblock06 Pass H: the aim window — same unshaded, alpha-blended
## convention as translucent_material, but carrying a texture (the ring
## image) instead of a flat color. cull_mode disabled: an orbit camera can
## end up looking at the window from either side, and a one-sided quad
## would just vanish rather than "read as a window," the whole point of it.
static func translucent_textured_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Team flagging, layer 2 of 2 (docs/10) — a hull outline via a single
## grown, back-face-only extra pass, no custom shader. Assign to a real
## part material's `next_pass`; never used standalone.
static func rim_outline_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.grow = true
	material.grow_amount = 0.02
	return material
