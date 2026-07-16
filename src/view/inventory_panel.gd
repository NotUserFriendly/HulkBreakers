class_name InventoryPanel
extends Node

## docs/10 taskblock03 H: the selected unit's inventory, nested exactly as
## InventoryRows.build() says — sockets (structural) and contents
## (inventory) render as visibly different relationships (H1), never
## flattened together. Pure presentation: every number already comes from
## InventoryRows (a MaterialTable DT lookup) or Shell's own
## carried_mass()/total_ram() — this Node only builds TreeItems and sets
## column text/color from them, no arithmetic of its own.

const COLUMN_TITLES: Array[String] = ["Part", "Condition", "Material", "DT", "Mass", "Bulk"]
const COL_PART := 0
const COL_CONDITION := 1
const COL_MATERIAL := 2
const COL_DT := 3
const COL_MASS := 4
const COL_BULK := 5

## docs/10 taskblock03 H2: "colour by fraction (WARN/DAMAGE)" — flagged
## placeholder thresholds, same status as every other tuning number in this
## codebase, not a design decision.
const CONDITION_DAMAGE_FRACTION := 0.25
const CONDITION_WARN_FRACTION := 0.5
## docs/10 taskblock03 H1: "contents... visually distinct" from the
## socket/body tree — a distinct indent glyph plus a dimmed row, rather than
## a second icon set this terminal-styled panel has no room for.
const CONTENTS_PREFIX := "» "

var tactics: TacticsController
var tree: Tree
var footer: Label
var material_table: MaterialTable


func setup(
	p_tactics: TacticsController, p_tree: Tree, p_footer: Label, p_material_table: MaterialTable
) -> void:
	tactics = p_tactics
	tree = p_tree
	footer = p_footer
	material_table = p_material_table
	tree.columns = COLUMN_TITLES.size()
	tree.column_titles_visible = true
	for i in range(COLUMN_TITLES.size()):
		tree.set_column_title(i, COLUMN_TITLES[i])
	tactics.selection_changed.connect(refresh)
	refresh()


func refresh() -> void:
	tree.clear()
	var unit: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	if unit == null:
		footer.text = ""
		return

	var rows: Array[InventoryRow] = InventoryRows.build(unit, material_table)
	# tree.clear() also drops the tree's own root, so the first row needs a
	# fresh one; a stack of "the item currently open at each depth" gives
	# every later row the right parent no matter how deep it nests, without
	# InventoryRows having to hand back anything but a flat, depth-tagged list.
	var stack: Array[TreeItem] = [tree.create_item()]
	for row: InventoryRow in rows:
		while stack.size() > row.depth + 1:
			stack.pop_back()
		var item: TreeItem = tree.create_item(stack[stack.size() - 1])
		_fill_row(item, row)
		stack.append(item)

	footer.text = _footer_text(unit.shell)


func _fill_row(item: TreeItem, row: InventoryRow) -> void:
	var part: Part = row.part
	var name: String = part.display_name if part.display_name != "" else String(part.id)
	var label: String
	if row.kind == InventoryRow.Kind.CONTENTS:
		label = CONTENTS_PREFIX + name
	elif row.socket_label != &"":
		label = "[%s] %s" % [row.socket_label, name]
	else:
		label = name
	if row.inert:
		label += "  (inert)"

	item.set_text(COL_PART, label)
	item.set_text(COL_CONDITION, "%d/%d" % [part.hp, part.max_hp])
	item.set_custom_color(COL_CONDITION, _condition_color(part))
	item.set_text(COL_MATERIAL, String(part.material))
	item.set_text(COL_DT, "%.1f" % row.dt)
	item.set_text(COL_MASS, "%.1f" % part.mass)
	item.set_text(COL_BULK, "%.1f" % part.bulk)

	if row.kind == InventoryRow.Kind.CONTENTS:
		for col in [COL_PART, COL_MATERIAL, COL_DT, COL_MASS, COL_BULK]:
			item.set_custom_color(col, HulkTheme.DIM)


func _condition_color(part: Part) -> Color:
	if part.max_hp <= 0:
		return HulkTheme.FOREGROUND
	var fraction: float = float(part.hp) / float(part.max_hp)
	if fraction <= CONDITION_DAMAGE_FRACTION:
		return HulkTheme.DAMAGE
	if fraction <= CONDITION_WARN_FRACTION:
		return HulkTheme.WARN
	return HulkTheme.FOREGROUND


## docs/10 taskblock03 H2: "the three constraints (docs/05)" — mass and RAM,
## straight from Shell's own resolvers, never re-summed here.
func _footer_text(shell: Shell) -> String:
	return (
		"mass %.1f/%.1f   ram %.1f/%.1f"
		% [shell.carried_mass(), shell.max_mass, shell.total_ram(), shell.max_ram]
	)
