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

## taskblock-07 Pass G names two EXPLICIT pip colors: "MP: lime green...
## AP: yellow." AP pips reuse HIGHLIGHT above (already this palette's
## yellow — no reason to duplicate it under a second name). MP has no
## existing match anywhere in the six; this is a genuine 7th color, not
## an invented one — the taskblock states the hex-adjacent name directly,
## same footing as every other named color here. Flagged for whoever
## reconciles this against docs/08's own "six colors, no more" line
## (written before Pass G existed).
const MP_PIP := Color(0.4, 0.9, 0.2)

## runNotes.md: "make [the inventory panel] partially transparent" — the
## Tree's own panel background only; text stays fully opaque so it's still
## legible over the 3D board behind it.
const PANEL_ALPHA := 0.75


static func build() -> Theme:
	var theme := Theme.new()

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = BACKGROUND
	theme.set_stylebox("panel", "PanelContainer", panel_style)

	theme.set_color("default_color", "RichTextLabel", FOREGROUND)
	theme.set_color("font_color", "Label", FOREGROUND)
	theme.set_color("font_color", "Button", FOREGROUND)

	# docs/10 taskblock03 H2: the inventory panel's Tree — same monospace,
	# same six colors, no separate styling of its own. runNotes.md: the
	# panel itself is translucent (PANEL_ALPHA) so it reads as an overlay
	# over the board rather than an opaque sidebar.
	theme.set_color("font_color", "Tree", FOREGROUND)
	theme.set_color("title_button_color", "Tree", FOREGROUND)
	var tree_panel := StyleBoxFlat.new()
	tree_panel.bg_color = Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, PANEL_ALPHA)
	theme.set_stylebox("panel", "Tree", tree_panel)

	# runNotes.md: "the 'highlight' meant to show more details on a body
	# part isn't showing at all" — the tooltip itself (Godot's own built-in
	# per-item mechanism, wired in InventoryPanel) was actually firing, but
	# with no TooltipPanel/TooltipLabel entry of its own, it fell back to
	# Godot's stock light-on-dark tooltip skin sitting on top of this
	# panel's OWN near-identical dark, half-translucent background — text
	# with no real backing box, easy to mistake for not there at all. A
	# solid, high-contrast panel with a HIGHLIGHT border fixes that
	# regardless of whatever row happens to be underneath it.
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 0.97)
	tooltip_style.border_width_left = 1
	tooltip_style.border_width_top = 1
	tooltip_style.border_width_right = 1
	tooltip_style.border_width_bottom = 1
	tooltip_style.border_color = HIGHLIGHT
	tooltip_style.content_margin_left = 6.0
	tooltip_style.content_margin_top = 4.0
	tooltip_style.content_margin_right = 6.0
	tooltip_style.content_margin_bottom = 4.0
	theme.set_stylebox("panel", "TooltipPanel", tooltip_style)
	theme.set_color("font_color", "TooltipLabel", FOREGROUND)

	# docs/10 taskblock05 A2: "the inspector's scrollbar is unreachable" —
	# the engine default grabber is a near-transparent sliver until
	# hovered, easy to miss entirely against this panel's own translucent
	# background. A flat, always-visible grabber fixes that; InventoryPanel
	# forcing the bar's own `visible` true is the other half (a Tree just
	# short of overflowing can otherwise hide the bar altogether).
	var scroll_track := StyleBoxFlat.new()
	scroll_track.bg_color = Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, PANEL_ALPHA)
	var scroll_grabber := StyleBoxFlat.new()
	scroll_grabber.bg_color = DIM
	var scroll_grabber_highlight := StyleBoxFlat.new()
	scroll_grabber_highlight.bg_color = FOREGROUND
	for corners in [scroll_grabber, scroll_grabber_highlight]:
		corners.corner_radius_top_left = 3
		corners.corner_radius_top_right = 3
		corners.corner_radius_bottom_left = 3
		corners.corner_radius_bottom_right = 3
	for scrollbar_type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", scrollbar_type, scroll_track)
		theme.set_stylebox("scroll_focus", scrollbar_type, scroll_track)
		theme.set_stylebox("grabber", scrollbar_type, scroll_grabber)
		theme.set_stylebox("grabber_highlight", scrollbar_type, scroll_grabber_highlight)
		theme.set_stylebox("grabber_pressed", scrollbar_type, scroll_grabber_highlight)

	var font: FontFile = load(FONT_PATH)
	if font != null:
		theme.default_font = font
		theme.default_font_size = FONT_SIZE

	return theme
