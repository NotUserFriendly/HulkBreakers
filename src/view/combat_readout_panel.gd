class_name CombatReadoutPanel
extends Node

## docs/10 taskblock04 E2/E3: "the other [panel] is everything else — enemy
## status, tile contents, part detail... one readout, three sources." Two
## live inputs, `tactics.hovered_cell` (terrain/unit/field-object, via
## TileInspection — E1: full enemy status, no knowledge gating) and
## `tactics.inspected_part` (a clicked inventory row) — `inspected_part`
## wins when set, since a fresh board hover already clears it
## (TacticsController.update_hover). Pure presentation: every number here
## is a raw Part/Grid field, never a derived stat this panel computed
## itself — nothing shown needs StatResolver (armor/damage), because
## nothing shown here is one of those numbers.

var tactics: TacticsController
var label: RichTextLabel


func setup(p_tactics: TacticsController, p_label: RichTextLabel) -> void:
	tactics = p_tactics
	label = p_label
	label.bbcode_enabled = true
	tactics.hover_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if tactics == null:
		label.text = ""
		return
	if tactics.inspected_part != null:
		label.text = _part_text(tactics.inspected_part)
		return
	if tactics.hovered_cell == null or tactics.selection == null:
		label.text = ""
		return

	var info: Dictionary = TileInspection.inspect(
		tactics.selection.state, tactics.hovered_cell, tactics.selection.selected_unit
	)
	if info.is_empty():
		label.text = ""
		return
	label.text = _tile_text(info)


func _part_text(part: Part) -> String:
	var name: String = part.display_name if part.display_name != "" else String(part.id)
	var lines: Array[String] = [name]
	lines.append("condition: %d/%d" % [part.hp, part.max_hp])
	lines.append("material: %s" % String(part.material))
	lines.append("mass: %.1f   bulk: %.1f" % [part.mass, part.bulk])
	if not part.salvage_yield.is_empty():
		var yields: Array[String] = []
		for resource_id: StringName in part.salvage_yield:
			yields.append("%s x%s" % [resource_id, part.salvage_yield[resource_id]])
		lines.append("salvage: %s" % ", ".join(yields))
	return "\n".join(lines)


func _tile_text(info: Dictionary) -> String:
	var cell: Vector2i = info.cell
	var lines: Array[String] = ["cell (%d, %d)" % [cell.x, cell.y]]
	lines.append("terrain: %s" % Enums.TerrainType.keys()[info.terrain])
	if info.cover_value > 0.0:
		lines.append("cover: %.1f" % info.cover_value)
	if info.visible_from_selected != null:
		lines.append("visible from selected: %s" % info.visible_from_selected)

	var unit: Variant = info.unit
	if unit != null:
		lines.append("")
		lines.append("unit %d — squad %d" % [(unit as Unit).id, (unit as Unit).squad_id])
		var root: Part = (unit as Unit).shell.root
		if root != null:
			lines.append("root: %d/%d" % [root.hp, root.max_hp])

	var field_object: Variant = info.field_object
	if field_object != null:
		lines.append("")
		lines.append(_part_text(field_object as Part))

	return "\n".join(lines)
