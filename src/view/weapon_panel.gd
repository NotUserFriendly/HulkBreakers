class_name WeaponPanel
extends Node

## runNotes.md: "add a UI element to the right of the inventory, that just
## displays a list of weapons the unit has attached. Gray out 'inactive'
## weapons, with a 'why' attached." Pure presentation, same split as
## InventoryPanel/InventoryRows: every row's active/why already comes from
## WeaponRows.build() — this only turns them into bbcode text. Reads
## `tactics.inspected_unit`, the same sticky, any-squad selection the
## inventory panel reads, so clicking either team's units shows their
## weapons too.

var tactics: TacticsController
var label: RichTextLabel


func setup(p_tactics: TacticsController, p_label: RichTextLabel) -> void:
	tactics = p_tactics
	label = p_label
	tactics.selection_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var unit: Unit = tactics.inspected_unit if tactics != null else null
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
