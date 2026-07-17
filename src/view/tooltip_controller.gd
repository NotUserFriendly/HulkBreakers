class_name TooltipController
extends Node

## taskblock-07 Pass F2: replaces combat_readout_panel.gd — "hovering a
## tile or an enemy now produces a tooltip instead of filling a panel."
## Same two live inputs combat_readout_panel.gd read (`tactics.hovered_cell`
## via TileInspection, `tactics.inspected_part` — inspected wins, since a
## fresh board hover already clears it, TacticsController.update_hover()),
## now built into a TooltipData via TooltipBuilder and shown through the
## one shared TooltipView instead of filling a RichTextLabel. The
## inventory panel remains its own dedicated thing (taskblock-04 E2, still
## unchanged) — this is everything else.

var tactics: TacticsController
var tooltip_view: TooltipView
var material_table: MaterialTable


func setup(
	p_tactics: TacticsController, p_tooltip_view: TooltipView, p_material_table: MaterialTable
) -> void:
	tactics = p_tactics
	tooltip_view = p_tooltip_view
	material_table = p_material_table
	tactics.hover_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if tactics == null or tooltip_view == null:
		return
	if tactics.inspected_part != null:
		tooltip_view.show_data(
			TooltipBuilder.for_part(tactics.inspected_part, material_table),
			tooltip_view.get_viewport().get_mouse_position()
		)
		return
	if tactics.hovered_cell == null or tactics.selection == null:
		tooltip_view.hide_tooltip()
		return

	var info: Dictionary = TileInspection.inspect(
		tactics.selection.state, tactics.hovered_cell, tactics.selection.selected_unit
	)
	if info.is_empty():
		tooltip_view.hide_tooltip()
		return
	tooltip_view.show_data(
		TooltipBuilder.for_tile(info, material_table),
		tooltip_view.get_viewport().get_mouse_position()
	)
