class_name InventoryPanel
extends Node

## docs/10 taskblock04 E2: "Inventory... shows the currently controlled
## shell — and nothing else." Reads `tactics.selection.selected_unit`
## (never any other unit, friend or foe — that's the combat readout's job
## now, via hover: CombatReadoutPanel). Nested exactly as
## InventoryRows.build() says — sockets (structural) and contents
## (inventory) render as visibly different relationships (H1), never
## flattened together. Pure presentation: every number already comes from
## InventoryRows (a MaterialTable DT lookup) or Shell's own
## carried_mass()/total_ram() — this Node only builds TreeItems and sets
## column text/color from them, no arithmetic of its own.
##
## docs/10 taskblock04 E3: "clicking a part in the inventory panel fills
## the same readout with that part's detail" — clicking a row calls
## `tactics.inspect_part()` with that row's own Part (stashed on the
## TreeItem via `set_metadata`), never a second copy of the stat text.
##
## runNotes.md: only Part/Condition/Mass show as columns, with the full
## stat block (Material, DT, Bulk, socket, inert) in a hover tooltip —
## Godot's own built-in per-item tooltip IS "a new small window," no
## custom popup control needed.

const COLUMN_TITLES: Array[String] = ["Part", "Condition", "Mass"]
const COL_PART := 0
const COL_CONDITION := 1
const COL_MASS := 2

## runNotes.md: "Mass and Condition are both 5 or less characters, while
## part names are long, adjust the columns to fit that behavior better."
## Condition/Mass get a small fixed width and don't expand at all; Part
## takes whatever's left.
const COL_CONDITION_WIDTH := 90
const COL_MASS_WIDTH := 70

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
	# runNotes.md: "there's a dead top level tree... that doesn't need to be
	# shown" — Tree.create_item() with no parent always makes an internal
	# root object (tree.get_root() still returns it either way); hide_root
	# just stops it from also rendering as a blank row above the shell's
	# own top-level part.
	tree.hide_root = true
	for i in range(COLUMN_TITLES.size()):
		tree.set_column_title(i, COLUMN_TITLES[i])
	tree.set_column_expand(COL_PART, true)
	tree.set_column_expand(COL_CONDITION, false)
	tree.set_column_custom_minimum_width(COL_CONDITION, COL_CONDITION_WIDTH)
	tree.set_column_expand(COL_MASS, false)
	tree.set_column_custom_minimum_width(COL_MASS, COL_MASS_WIDTH)
	tree.item_selected.connect(_on_item_selected)
	# docs/10 taskblock05 C: "hovering a part in the inventory panel
	# highlights that part's actual boxes in 3D" — a plain mouse-motion
	# read via gui_input (Tree has no dedicated per-item hover signal),
	# cleared the instant the cursor leaves the tree entirely.
	tree.gui_input.connect(_on_tree_gui_input)
	tree.mouse_exited.connect(func() -> void: tactics.hover_part(null))
	tactics.selection_changed.connect(refresh)
	tactics.highlight_changed.connect(_on_highlight_changed)
	refresh()


func _on_item_selected() -> void:
	var item: TreeItem = tree.get_selected()
	if item == null:
		return
	var part: Variant = item.get_metadata(COL_PART)
	if part is Part:
		tactics.inspect_part(part)


func _on_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	var item: TreeItem = tree.get_item_at_position((event as InputEventMouseMotion).position)
	if item == null:
		tactics.hover_part(null)
		return
	var part: Variant = item.get_metadata(COL_PART)
	tactics.hover_part(part if part is Part else null)


## docs/10 taskblock05 C: bidirectional — a 3D hover highlights this row.
## Walks every row rather than tracking one "currently highlighted" item,
## since refresh() rebuilds the tree wholesale and any cached TreeItem
## reference from a previous highlight would already be stale.
func _on_highlight_changed() -> void:
	var item: TreeItem = tree.get_root()
	while item != null:
		var is_highlighted: bool = (
			tactics.highlighted_part != null
			and item.get_metadata(COL_PART) == tactics.highlighted_part
		)
		if is_highlighted:
			# docs/08 "two palettes": this is UI-layer, so HulkTheme's own
			# HIGHLIGHT (never WorldPalette's) — darkened so row text stays
			# legible over it.
			item.set_custom_bg_color(COL_PART, HulkTheme.HIGHLIGHT.darkened(0.6))
		else:
			item.clear_custom_bg_color(COL_PART)
		item = item.get_next_in_tree()


func refresh() -> void:
	tree.clear()
	var unit: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
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
	item.set_metadata(COL_PART, part)
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
	item.set_text(COL_MASS, "%.1f" % part.mass)

	var tooltip: String = _tooltip_text(row)
	for col in range(COLUMN_TITLES.size()):
		item.set_tooltip_text(col, tooltip)

	if row.kind == InventoryRow.Kind.CONTENTS:
		for col in [COL_PART, COL_MASS]:
			item.set_custom_color(col, HulkTheme.DIM)


## runNotes.md: "show all the stats of parts on hover, drawing a new small
## window" — the columns this dropped (Material, DT, Bulk), plus the
## relationship/attach details a column can't show at all.
func _tooltip_text(row: InventoryRow) -> String:
	var part: Part = row.part
	var name: String = part.display_name if part.display_name != "" else String(part.id)
	var lines: Array[String] = [name]
	lines.append("condition: %d/%d" % [part.hp, part.max_hp])
	lines.append("material: %s (DT %.1f)" % [String(part.material), row.dt])
	lines.append("mass: %.1f   bulk: %.1f" % [part.mass, part.bulk])
	if row.kind == InventoryRow.Kind.SOCKET and row.socket_label != &"":
		lines.append("socket: %s" % row.socket_label)
	elif row.kind == InventoryRow.Kind.CONTENTS:
		lines.append("carried, not attached")
	if row.inert:
		lines.append("inert: requires unmet")
	return "\n".join(lines)


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
