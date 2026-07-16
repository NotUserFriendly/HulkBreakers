class_name HulkTheme
extends RefCounted

## docs/08: the terminal is monospace, text-first, six colors, one Theme
## resource — no per-scene styling, no CRT/scanline fakery (that's a later
## shader pass). **This governs the terminal UI only** — panels, log, stat
## blocks (docs/08/10's "two palettes" rule). The 3D board and everything on
## it is WorldPalette's — its own colours, lit and shaded, never this one.
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
