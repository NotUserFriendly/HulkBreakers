class_name HulkTheme
extends RefCounted

## docs/08: the terminal is monospace, text-first, six colors, one Theme
## resource — no per-scene styling, no CRT/scanline fakery (that's a later
## shader pass).
##
## Font: docs/08 names JetBrains Mono/IBM Plex Mono/Share Tech Mono/VT323 as
## examples of the actual criterion — OFL/free, monospace. None of those
## four ship with this repo and there's no network fetch available at
## Phase 12.5 build time; Anonymous Pro (OFL, monospace, already vendored
## under addons/gut/fonts for GUT's own UI) satisfies the same criterion, so
## its .ttf is copied into res://assets/fonts/ (with its OFL.txt) rather
## than left pointing into a third-party addon's private folder. Swapping
## in one of the docs-named fonts later is the one-line change this
## comment used to promise before any font existed at all.
const FONT_PATH := "res://assets/fonts/AnonymousPro-Regular.ttf"
const FONT_SIZE := 16

const BACKGROUND := Color(0.06, 0.06, 0.08)
const FOREGROUND := Color(0.85, 0.85, 0.82)
const DIM := Color(0.45, 0.45, 0.44)
const HIGHLIGHT := Color(0.95, 0.82, 0.25)
const WARN := Color(0.95, 0.55, 0.15)
const DAMAGE := Color(0.85, 0.2, 0.2)


## docs/10 Phase 12.1: "material -> colour from HulkTheme" — a part's
## rendered box is colored by its material's DT band, not a per-material
## color (materials stay open data; the palette stays six colors). An
## unarmored/empty material reads as bare organic tissue; DT climbs through
## the same six colors armor already uses for warnings/damage elsewhere.
static func color_for_material(material: StringName, table: MaterialTable) -> Color:
	if material == &"":
		return DIM
	var dt: float = table.get_entry(material).dt
	if dt <= 0.0:
		return FOREGROUND
	if dt < 6.0:
		return DIM
	if dt < 9.0:
		return HIGHLIGHT
	return WARN


## docs/08: "HL2-era budgets... no CRT/scanline fakery" — flat, unlit color
## is the intended look, not a placeholder for missing lighting. Every 3D
## mesh (board tiles, blockers, unit boxes) uses this so a color always
## renders exactly as authored, with no scene light required.
static func flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


## A flat dark backdrop matching the terminal palette (docs/08: six colors,
## no per-scene styling) — otherwise Godot's default procedural sky would
## paint the world background a stock light gray with no relation to the
## theme.
static func world_environment() -> WorldEnvironment:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	world_environment.environment = environment
	return world_environment


static func build() -> Theme:
	var theme := Theme.new()

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = BACKGROUND
	theme.set_stylebox("panel", "PanelContainer", panel_style)

	theme.set_color("default_color", "RichTextLabel", FOREGROUND)
	theme.set_color("font_color", "Label", FOREGROUND)
	theme.set_color("font_color", "Button", FOREGROUND)

	var font: FontFile = load(FONT_PATH)
	if font != null:
		theme.default_font = font
		theme.default_font_size = FONT_SIZE

	return theme
