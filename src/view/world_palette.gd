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

## ~45 degrees elevation, off-axis — enough that adjacent box faces catch
## different light and read as distinct surfaces instead of merging into
## one unshaded blob.
const LIGHT_ELEVATION_DEG := 45.0
const LIGHT_AZIMUTH_DEG := 35.0
## Modest ambient so shadow-side faces aren't pure black, not a second key
## light.
const AMBIENT_ENERGY := 0.25


## A flat dark backdrop plus soft ambient — otherwise Godot's default
## procedural sky paints the void a stock light grey with no relation to
## the theme, and unlit shadow faces read as pure black holes.
static func world_environment() -> WorldEnvironment:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = VOID
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = GROUND
	environment.ambient_light_energy = AMBIENT_ENERGY
	world_environment.environment = environment
	return world_environment


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
