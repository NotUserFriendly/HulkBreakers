class_name EditorPanel
extends PanelContainer

## **The editor's section-details panel — every widget, and nothing that decides anything.**
##
## taskblock-59 Pass A: **the third time `editor_module.gd` hit the 1000-line gate, and the first
## time the split was chosen rather than forced into the nearest gap.** taskblock-58 Pass D moved
## the tool vocabulary to `EditorTools` and Pass E moved `target_from` to `FacePlacement`; that
## block's own report flagged the pattern — *"both moves were triggered by a lint gate rather than
## by noticing, worth recording as a pattern, since a third one is likely and the file is near the
## limit again."* It was, and this is it.
##
## **What makes this the right cut rather than the cheapest one** is that the two halves want
## different things. `EditorModule` routes a click to a verb; this builds `SpinBox`es and reads them
## back. Nothing here knows what a tool is, nothing here calls `EditorController` except to write
## the field the author just typed into, and the module below it never touches a widget again. It is
## `InspectPanel`'s split — the same precedent both earlier moves cited — applied to the surface
## that had actually grown.
##
## **It buys the block room on purpose.** taskblock-59 has three more passes that all add to the
## editor, and a module that goes over the limit on every one of them is a module that gets carved
## up by whatever happens to be at the bottom of the file.
##
## ## What is here and what is on the bar
##
## taskblock-57 Pass G1 took the verbs to `EditorBarModule`: the tool, the placement kind, the part
## and the claim kind are its buttons; save, load, run-a-bout and undo are its second row. What is
## left is the *declarations* — the board's name, the numbers a placement carries, the section's
## edges and chance rolls, and the readout.

## *Declare Edge* was pressed. **A signal rather than a call back into the module**, because the
## panel owns where the button sits and the module owns what pressing it means — the one control
## here whose press is a verb rather than a field.
signal edge_declared

## The sides an edge can be declared on, in `SectionEdge`'s own order — index is identity, which is
## what `_selected_of` relies on.
const EDGE_SIDES: Array[StringName] = [
	SectionEdge.SIDE_NORTH,
	SectionEdge.SIDE_SOUTH,
	SectionEdge.SIDE_EAST,
	SectionEdge.SIDE_WEST,
	SectionEdge.SIDE_UP,
	SectionEdge.SIDE_DOWN,
]

## How much of a row a field's own name takes before the control gets the rest. A starting position,
## not a decision — see `_labelled`, which clips rather than widens.
const LABEL_WIDTH := 96.0

## How far the panel's content sits inside its own border, before UI scale. A starting position,
## from the UI review's *"Panel needs some padding all around it."*
const PANEL_PADDING := 10.0

var layout: VBoxContainer = null
var name_field: LineEdit = null
var height_field: SpinBox = null
var facing_field: SpinBox = null
var edge_side_dropdown: OptionButton = null
var edge_kind_dropdown: OptionButton = null
var join_tag_field: LineEdit = null
var chance_tag_field: LineEdit = null
var chance_field: SpinBox = null
var status_label: Label = null


## Builds every widget against `controller`, which is the only thing this panel writes to.
##
## **Clipped and scrolled, so the slot's width is the panel's width.** The supervisor's review:
## *"it's too wide. Should be roughly half as wide as it is tall."* The slot already is — the
## layout gives it half the viewer's height in width — but a `PanelContainer` takes the largest
## minimum width of its content, and a column of labelled `SpinBox` rows asks for more than that.
## So the panel grew past its own slot and the rect the placement table describes was never what
## was drawn.
##
## Scrolling rather than shrinking the rows: the fields have to stay usable, and an authoring
## panel with more in it than fits is a scroll, not a squeeze.
func build(controller: EditorController) -> void:
	clip_contents = true
	# **Padded all round**, which the UI review asked for: *"EDIT INSPECT VIEWER — Panel needs some
	# padding all around it."* Same treatment `InspectPanel` gets, for the same reason: a
	# `PanelContainer` hands its child the whole rect, so every labelled row ran into the border.
	var style: StyleBox = get_theme_stylebox("panel")
	if style != null:
		var padded: StyleBox = style.duplicate()
		for side: String in [
			"content_margin_left",
			"content_margin_right",
			"content_margin_top",
			"content_margin_bottom"
		]:
			padded.set(side, UiLayout.scaled(PANEL_PADDING))
		add_theme_stylebox_override("panel", padded)
	var scroll := ScrollContainer.new()
	# **Horizontal scrolling ENABLED, which is what actually lets the panel be narrow.** A
	# `ScrollContainer` reports its content's minimum size on any axis it cannot scroll, so with
	# horizontal scrolling off the whole panel still grew to the widest labelled row it held — 516 px
	# against a 360 px slot, measured. Allowing the axis to scroll drops that minimum to zero and the
	# panel finally fits the rect the placement table gives it.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	layout = VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(layout)

	var title := Label.new()
	title.text = "Editor"
	layout.add_child(title)

	name_field = LineEdit.new()
	name_field.placeholder_text = "board name"
	name_field.text_changed.connect(func(text: String) -> void: controller.board_name = text)
	layout.add_child(name_field)

	height_field = _number(0.0, -32.0, 32.0, 0.1)
	layout.add_child(_labelled("height", height_field))
	facing_field = _number(0.0, -TAU, TAU, 0.01)
	layout.add_child(_labelled("facing", facing_field))

	edge_side_dropdown = _dropdown(EDGE_SIDES)
	layout.add_child(_labelled("edge side", edge_side_dropdown))
	edge_kind_dropdown = _dropdown([SectionEdge.KIND_EXTERIOR, SectionEdge.KIND_OPEN])
	layout.add_child(_labelled("edge kind", edge_kind_dropdown))
	join_tag_field = LineEdit.new()
	join_tag_field.placeholder_text = "join_tag"
	layout.add_child(_labelled("join tag", join_tag_field))
	var edge_button := Button.new()
	edge_button.text = "Declare Edge"
	edge_button.pressed.connect(func() -> void: edge_declared.emit())
	layout.add_child(edge_button)

	chance_tag_field = LineEdit.new()
	chance_tag_field.placeholder_text = "clutter tag"
	layout.add_child(_labelled("chance tag", chance_tag_field))
	chance_field = _number(1.0, 0.0, 1.0, 0.05)
	layout.add_child(_labelled("chance", chance_field))

	layout.add_child(_section_field_rows(controller))

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(status_label)


## The one-line account of the board, put where the author is already looking.
func show_readout(controller: EditorController, cell: Variant) -> void:
	if status_label == null:
		return
	status_label.text = (
		"%dx%d | %d placed | %d claim(s) | %d edge(s) | cell %s | undo %d"
		% [
			controller.width,
			controller.rows,
			controller.placements.size(),
			controller.claims.size(),
			controller.edges.size(),
			str(cell) if cell != null else "-",
			controller.undo_depth(),
		]
	)


# --- what the widgets currently say ------------------------------------------------------------


func selected_edge_side() -> StringName:
	return _selected_of(edge_side_dropdown, EDGE_SIDES, SectionEdge.SIDE_NORTH)


func selected_edge_kind() -> StringName:
	var kinds: Array[StringName] = [SectionEdge.KIND_EXTERIOR, SectionEdge.KIND_OPEN]
	return _selected_of(edge_kind_dropdown, kinds, SectionEdge.KIND_EXTERIOR)


func height() -> float:
	return height_field.value if height_field != null else 0.0


func facing() -> float:
	return facing_field.value if facing_field != null else 0.0


func join_tag() -> StringName:
	return StringName(join_tag_field.text) if join_tag_field != null else &""


func chance_tag() -> StringName:
	return StringName(chance_tag_field.text) if chance_tag_field != null else &""


func chance_value() -> float:
	return chance_field.value if chance_field != null else 1.0


func board_name() -> String:
	return name_field.text if name_field != null else ""


## Puts the model's own name into the field after a load. The other direction of a deliberately
## one-way pair: the field pushes into the controller on edit, the controller pushes into the field
## on load, and neither is a write-back that could fight the other.
func show_name(named: String) -> void:
	if name_field != null:
		name_field.text = named


# --- internals ---------------------------------------------------------------------------------


## One row per whole-section declaration, **discovered from `SectionFile` rather than listed**. A
## new `@export` on that resource becomes an editable field here the day it is added, which is the
## open-vocabulary rule applied to an authoring surface.
func _section_field_rows(controller: EditorController) -> VBoxContainer:
	var rows := VBoxContainer.new()
	for name: StringName in EditorController.declaration_fields():
		var current: Variant = controller.section_field(name)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = String(name)
		row.add_child(label)
		if current is bool:
			var check := CheckBox.new()
			check.button_pressed = current
			check.toggled.connect(
				func(pressed: bool) -> void:
					controller.set_section_field(name, pressed)
					show_readout(controller, null)
			)
			row.add_child(check)
		elif current is int:
			var number := _number(float(current), -1.0, 999.0, 1.0)
			number.value_changed.connect(
				func(value: float) -> void:
					controller.set_section_field(name, int(value))
					show_readout(controller, null)
			)
			row.add_child(number)
		else:
			# An array field (`banned_clutter`, `encounter_types`) is a comma-separated list. Crude
			# and honest — a real tag picker wants a content library, which does not exist.
			var text := LineEdit.new()
			text.placeholder_text = "comma separated"
			text.text_submitted.connect(
				func(value: String) -> void:
					controller.set_section_field(name, _tag_list(value))
					show_readout(controller, null)
			)
			row.add_child(text)
		rows.add_child(row)
	return rows


static func _tag_list(text: String) -> Array[StringName]:
	var tags: Array[StringName] = []
	for piece: String in text.split(",", false):
		var trimmed: String = piece.strip_edges()
		if trimmed != "":
			tags.append(StringName(trimmed))
	return tags


## The selected entry of `options`, or `fallback` when the dropdown is absent or unselected. Every
## dropdown here is populated from its own constant list in order, so index *is* identity.
static func _selected_of(
	dropdown: OptionButton, options: Array[StringName], fallback: StringName
) -> StringName:
	if dropdown == null or options.is_empty():
		return fallback
	var index: int = dropdown.selected
	if index < 0 or index >= options.size():
		return fallback
	return options[index]


static func _dropdown(options: Array[StringName]) -> OptionButton:
	var dropdown := OptionButton.new()
	for option: StringName in options:
		dropdown.add_item(String(option))
	if not options.is_empty():
		dropdown.selected = 0
	return dropdown


static func _number(value: float, minimum: float, maximum: float, step: float) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = minimum
	box.max_value = maximum
	box.step = step
	box.value = value
	return box


## One labelled field, sized to whatever width the panel currently has.
##
## **The row shrinks with the panel rather than setting its width**, which the UI review found it
## doing: *"Looks like you just chopped the size of this panel, and the items within aren't set to
## resize with panel size."* The label is given a clip and a fixed share so a long field name cannot
## push the control it labels out of the panel, and the control expands into what is left.
static func _labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.size_flags_horizontal = Control.SIZE_FILL
	# Clipped rather than allowed to widen the row — a `Label` reports its full text as its minimum
	# width otherwise, which is what made the panel wider than the slot it was given.
	label.clip_text = true
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = 0.0
	row.add_child(control)
	return row
