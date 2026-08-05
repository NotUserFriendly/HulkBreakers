class_name UiButton
extends Button

## **A square chrome control with a short abbreviation and a hover description.**
##
## The supervisor's review of the taskblock-57 layout: *"All toggles and descriptive text should be
## replaced with square BUTTONS with an up-to three letter abbreviation on them. Hovering them for
## 1.5 seconds should show a description of what they do (i.e. Toggles the Inspect Module)."*
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
## `TooltipView.show_data` already waits `HoverDwell.DELAY_SEC` before showing anything — the same
## 1.5 s clock the combat log's overflow preview runs on, which taskblock-57 required them to share.
## So this shows a tooltip the way every other hovering surface does and gets the delay for free.
## **A second timer here would be the third clock**, which is exactly what that requirement existed
## to prevent.
##
## A null `TooltipView` is legal and means no description — a mode that declares no `tooltip` module
## gets working buttons and no hover text, which is the stand-alone posture every module takes.

## The side of the square, in pixels before UI scale. **A starting position, not a decision** — big
## enough for three capital letters at `HulkTheme.FONT_SIZE` with room around them.
const SIDE := 44.0

## What the button says when it is hovered: the full name, and a sentence under it.
var description: String = ""
var full_name: String = ""

var tooltip_view: TooltipView = null


## A square button labelled `abbrev`, describing itself as `full` / `description` on hover.
##
## `toggle` gives it a pressed state, which is what a module toggle needs and what a one-shot verb
## like Inspect does not.
static func build(
	abbrev: String, full: String, description: String, view: TooltipView, toggle: bool = false
) -> UiButton:
	var button := UiButton.new()
	button.text = abbrev
	button.full_name = full
	button.description = description
	button.tooltip_view = view
	button.toggle_mode = toggle
	# Square, and the same square whatever the label's own width would have been.
	var side: float = UiLayout.scaled(SIDE)
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
	tooltip_view.show_data(data, get_viewport().get_mouse_position())


func _on_unhover() -> void:
	if tooltip_view != null:
		tooltip_view.hide_tooltip()
