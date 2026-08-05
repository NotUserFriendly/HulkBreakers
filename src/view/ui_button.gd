class_name UiButton
extends Button

## **A square chrome control with a short abbreviation and a hover description.**
##
## The supervisor's review of the taskblock-57 layout: *"All toggles and descriptive text should be
## replaced with square BUTTONS with an up-to three letter abbreviation on them... should show a
## description of what they do (i.e. Toggles the Inspect Module)."* The follow-up review shortened
## the wait and collapsed the two button feels into one — see `HOVER_SEC` and `build`.
##
## ## Why a class rather than a helper each module calls
##
## Three modules put controls in the UI-buttons cluster — `UiButtonsModule` (the module toggles and
## the debug menu), `InspectModule` (its own button, because it owns the enabled state that follows
## the selection) and `ControlsLegendModule` (keybindings). **A row of controls that do not agree on
## their own shape is what the review found**, and a helper each of them calls is a shape three
## files can drift from. A button that knows it is square and knows how to describe itself cannot.
##
## ## The dwell is not implemented here
##
## `TooltipView.show_data` runs the wait on the one `HoverDwell` clock the combat log's overflow
## preview also uses, which taskblock-57 required them to share. This passes its own *duration*
## (`HOVER_SEC`) and nothing else. **A second timer here would be the third clock**, which is what
## that requirement existed to prevent — sharing the mechanism was the point, not sharing one
## number for every surface that hovers.
##
## A null `TooltipView` is legal and means no description — a mode that declares no `tooltip` module
## gets working buttons and no hover text, which is the stand-alone posture every module takes.

## The side of the square, in pixels before UI scale. **A starting position, not a decision** — big
## enough for three capital letters at `HulkTheme.FONT_SIZE` with room around them.
const SIDE := 44.0

## How long the cursor rests on a chrome button before it says what it does.
##
## **Shorter than the shared 1.5 s, and stated rather than inherited.** The UI review: *"Hover on UI
## buttons is too long, should probably be 0.5 seconds. You'll almost always want this info."* A
## three-letter abbreviation is not self-explanatory, so its description is closer to a label than
## to a detail panel, and the 1.5 s wait is calibrated for the latter. Still the one `HoverDwell`
## clock; only the duration is this caller's.
const HOVER_SEC := 0.5

## How much smaller a secondary control is than the rest of the row. The UI review asked for the
## bar's own toggle at *"~70% the size of the other UI buttons"* — it is chrome about the chrome,
## and reading as slightly apart from the module toggles is the point.
const SECONDARY_SCALE := 0.7

## The colour of the "this is open" border.
##
## **A 50% grey, not `HulkTheme.HIGHLIGHT`.** The review: *"Highlight border is too aggressive of a
## color, can it be replaced with a 50% gray?"* The highlight tier is the game's alert yellow and is
## used for an armed action and a live announcement; a row of chrome saying "these panels are open"
## competing with those is the surface shouting about itself.
const ACTIVE_BORDER_COLOR := Color(0.5, 0.5, 0.5)

## How thick the "this is open" border is, in pixels before UI scale.
##
## The UI review asked for the state to be visible: *"Buttons which have something open should be
## highlighted with a border. Button 'on', button is highlighted and module is visible. Button
## 'off', button is un-highlighted and module is disabled/hidden."* A summon/dismiss button with no
## state is a button you have to press to find out what it did.
const ACTIVE_BORDER := 2

## What the button says when it is hovered: the full name, and a sentence under it.
var description: String = ""
var full_name: String = ""

var tooltip_view: TooltipView = null

## Whether the thing this button summons is currently up. **Drawn as a border**, not as a pressed
## state — `toggle_mode` is what the review collapsed away, and a `Button` that looks held down is
## the disable/enable feel it asked to be rid of.
var active: bool = false:
	set(value):
		active = value
		_apply_border()


## A square button labelled `abbrev`, describing itself as `full` / `description` on hover.
##
## **There is one kind of button here and it is summon/dismiss.** The UI review: *"I seem to have
## two different 'classes' of buttons, a 'summon/dismiss' style button and then a 'disable/enable'?
## There should be one, and the 'summon/dismiss' seems to be the better feeling option."* The module
## toggles used to be `toggle_mode` buttons carrying a stuck pressed state while Inspect, the debug
## menu and the keybindings legend were plain presses — two feels in one row. Every one of them is a
## plain press now: you press it to summon the thing and press it again to dismiss it.
static func build(
	abbrev: String, full: String, description: String, view: TooltipView, scale: float = 1.0
) -> UiButton:
	var button := UiButton.new()
	button.text = abbrev
	button.full_name = full
	button.description = description
	button.tooltip_view = view
	# Square, and the same square whatever the label's own width would have been. `scale` is for a
	# secondary control — see `SECONDARY_SCALE`.
	var side: float = UiLayout.scaled(SIDE) * scale
	button.custom_minimum_size = Vector2(side, side)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# **No focus ring.** These are chrome, and a control that keeps keyboard focus after a click
	# swallows the next key the player presses at the board.
	button.focus_mode = Control.FOCUS_NONE
	return button


## **Up to three letters, derived from the id rather than listed.**
##
## Multi-word ids give their initials (`action_bar` → `AB`, `inspect_viewer` → `IV`); a single word
## gives its first three letters (`inspect` → `INS`, `editor` → `EDI`). Capped at three either way.
##
## Derived so a module added later gets a label the day it is added, which is the same rule
## `UiButtonsModule` already follows for its full names — **no module is named in either file.**
## Two modules can collide on an abbreviation, and that is what the hover description is for; a
## uniqueness rule here would mean a table, and a table is the thing being avoided.
static func abbreviate(id: StringName) -> String:
	var words: PackedStringArray = String(id).split("_", false)
	if words.size() >= 2:
		var initials: String = ""
		for word: String in words:
			if initials.length() >= 3:
				break
			initials += word.substr(0, 1)
		return initials.to_upper()
	return String(id).substr(0, 3).to_upper()


func _init() -> void:
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	# Motion re-enters so the tooltip keeps tracking the cursor while it is still over this button —
	# `TooltipView.show_data` repositions on a repeat call with the same content and never restarts
	# the wait, which is the pattern every other hovering surface in the project uses.
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_hover()


func _on_hover() -> void:
	if tooltip_view == null or description == "":
		return
	var data := TooltipData.new(full_name, [] as Array[Dictionary], description)
	tooltip_view.show_data(data, get_viewport().get_mouse_position(), HOVER_SEC)


func _on_unhover() -> void:
	if tooltip_view != null:
		tooltip_view.hide_tooltip()


## Draws (or clears) the "open" border. A `StyleBoxFlat` on all four button states, so the border
## survives hovering and pressing rather than flickering off under the cursor.
func _apply_border() -> void:
	for state: String in ["normal", "hover", "pressed", "focus"]:
		if not active:
			remove_theme_stylebox_override(state)
			continue
		var box := StyleBoxFlat.new()
		box.bg_color = (
			Color(HulkTheme.BACKGROUND, 0.0) if state == "normal" else HulkTheme.BACKGROUND
		)
		var width: int = int(UiLayout.scaled(ACTIVE_BORDER))
		box.border_width_left = width
		box.border_width_right = width
		box.border_width_top = width
		box.border_width_bottom = width
		box.border_color = ACTIVE_BORDER_COLOR
		add_theme_stylebox_override(state, box)
