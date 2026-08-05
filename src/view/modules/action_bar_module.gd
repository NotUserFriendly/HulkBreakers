class_name ActionBarModule
extends BarModule

## taskblock-56 Pass C: the action bar — bottom, centred, half a 16:9 screen wide.
##
## **An INPUT module.** `ActionBar` arms an action and `TacticsController` turns the next click into
## a queued `CombatAction`. It is the only INPUT bar of the three: the spectator's watches and the
## editor's authors a board, and neither goes near `ActionQueue.enqueue`.
##
## **taskblock-57 Pass C: the AP/MP pips left.** They were built here on the argument that splitting
## a two-line label row into its own module would be structure for its own sake. Pass C's table
## overrules that for a stated reason rather than a stylistic one: G2 replaces this exact surface
## with a coordinate readout in editor mode — *"same slot, different module"* — and two modules
## cannot share a slot if one of them is welded inside a third. They are `UnitResourcesModule` now,
## mounted into `action_bar_top_left`, which is a slot this module publishes: the pips still sit
## above the bar and still move with it.
##
## **taskblock-57 Pass G1: the scaffolding left too.** Building the bar's root and publishing its
## four satellite slots is `BarModule`'s job now, because the spectator and the editor have bars in
## the same slot with the same satellites and entirely different contents. What is left here is the
## player's own shape.
##
## ## The player's shape, as the taskblock states it
##
## *"Player — square items, left-aligned, two rows, small padding."* All four are here and each is a
## departure from what shipped in Pass C, which was one row of ten:
##
## - **Two rows**, so ten 108 px boxes take 540 px rather than 1080 — against a bar the table gives
##   960 px. The single row overhung its own bar by 120 px at 1x, and by more at any UI scale above
##   it. Measured, not assumed: `ActionBar.BOX_SIZE` is 108 and `SLOT_COUNT` is 10.
## - **Square items** are `ActionBar.BOX_SIZE`'s own business and are unchanged.
## - **Left-aligned**, which is what `SHRINK_BEGIN` on the grid means here: the boxes start at the
##   bar's left edge instead of being centred in whatever width the row happens to have.
## - **Small padding**, as the grid's own separation.

## The rows the ten boxes are dealt into. **Two, from the taskblock**; the per-row count is derived
## so `ActionBar.SLOT_COUNT` changing does not silently produce a third row.
const BOX_ROWS := 2

## Small padding, in pixels before UI scale. A starting position the supervisor's tuning pass owns,
## not a decision — it is deliberately smaller than `BattleLayout.PADDING`, which separates whole
## surfaces rather than items within one.
const BOX_SPACING := 4

var action_bar: ActionBar = null
## The grid the ten boxes sit in. Exposed because a test confirms the row/column split structurally
## rather than by eye.
var action_grid: GridContainer = null


func module_id() -> StringName:
	return &"action_bar"


## Arming an action is the first half of queueing one.
func kind() -> Kind:
	return Kind.INPUT


## Ten square boxes over two rows, left-aligned, with small padding.
func _fill_bar(column: VBoxContainer) -> void:
	action_grid = GridContainer.new()
	# **Columns, from the row count** — ten boxes over two rows is five columns, and a `SLOT_COUNT`
	# that is not a multiple of `BOX_ROWS` rounds up so the last row is short rather than a third row
	# appearing. `GridContainer` fills left to right, top to bottom, so slot 0 is top-left.
	action_grid.columns = int(ceilf(float(ActionBar.SLOT_COUNT) / float(BOX_ROWS)))
	action_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left-aligned: the boxes start at the bar's left edge rather than being centred in the leftover
	# width. The grid is exactly as wide as its content, and its content is the bar.
	action_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var spacing: int = int(UiLayout.scaled(BOX_SPACING))
	action_grid.add_theme_constant_override("h_separation", spacing)
	action_grid.add_theme_constant_override("v_separation", spacing)
	column.add_child(action_grid)

	action_bar = ActionBar.new()
	add_child(action_bar)
	if context.tactics != null:
		action_bar.setup(context.tactics, action_grid, _tooltip_view())
