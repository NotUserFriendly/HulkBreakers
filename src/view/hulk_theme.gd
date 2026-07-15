class_name HulkTheme
extends RefCounted

## docs/08: the terminal is monospace, text-first, six colors, one Theme
## resource — no per-scene styling, no CRT/scanline fakery (that's a later
## shader pass). The actual OFL monospace font file (JetBrains Mono et al,
## docs/08) is an art-pass asset (Phase 12); until it's added, build() uses
## Godot's built-in default font so the Theme is fully wired and testable
## today, and swapping in the real font later is a one-line change here.

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

	return theme
