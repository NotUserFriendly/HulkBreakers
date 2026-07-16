class_name WeaponPanel
extends Node

## runNotes.md: "add a UI element to the right of the inventory, that just
## displays a list of weapons the unit has attached. Gray out 'inactive'
## weapons, with a 'why' attached." Pure presentation, same split as
## InventoryPanel/InventoryRows: every row's active/why already comes from
## WeaponRows.build() — this only turns them into bbcode text.
##
## docs/10 taskblock04 E2: reads `tactics.selection.selected_unit`, the
## same "currently controlled shell, and nothing else" scope the inventory
## panel now reads — an enemy's weapons are the combat readout's job (via
## hover), same as the rest of their status.

var tactics: TacticsController
var label: RichTextLabel


func setup(p_tactics: TacticsController, p_label: RichTextLabel) -> void:
	tactics = p_tactics
	label = p_label
	tactics.selection_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var unit: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
	if unit == null:
		label.text = ""
		return

	var rows: Array[WeaponRow] = WeaponRows.build(unit)
	if rows.is_empty():
		label.text = "[color=#%s]no weapons attached[/color]" % HulkTheme.DIM.to_html(false)
		return

	var lines: Array[String] = []
	for row: WeaponRow in rows:
		lines.append(_line(row))
	label.text = "\n".join(lines)


func _line(row: WeaponRow) -> String:
	var part: Part = row.part
	var name: String = part.display_name if part.display_name != "" else String(part.id)
	if row.active:
		return name
	return "[color=#%s]%s — %s[/color]" % [HulkTheme.DIM.to_html(false), name, row.why]
