class_name ApMpPipRow
extends Node

## taskblock-07 Pass G: "above the action bar: pips, not numbers." Two
## rows of colored pips — AP (yellow, HulkTheme.HIGHLIGHT) fixed at
## `max_ap` slots so a spent pip stays visible and dim rather than
## disappearing; MP (lime green, HulkTheme.MP_PIP) sized to the current
## pool itself (Unit has no `max_mp` to compare against — see
## ApMpPips's own doc comment). Reads `tactics.selection.previewed_unit()`
## — the same "given whatever's already queued" speculative state
## QueuePanel/reachable-cells highlighting already key off — so queuing a
## move that burns AP for MP updates both rows the instant it's queued,
## in TACTICS, before RESOLUTION ever runs (Pass G/TESTS: "burning 1 AP
## for MP updates both rows in one step").
##
## Pure presentation: every pip's lit/dim state already comes from
## ApMpPips; hoverable (Pass F) via TooltipBuilder.for_ap_pips()/
## for_mp_pips() — one tooltip per row, not per pip (the pips in one row
## are fungible; nothing distinguishes pip 3 from pip 4).

const PIP_SIZE := Vector2(14, 14)

var tactics: TacticsController
var tooltip_view: TooltipView
var _ap_container: HBoxContainer
var _mp_container: HBoxContainer


func setup(
	p_tactics: TacticsController,
	ap_container: HBoxContainer,
	mp_container: HBoxContainer,
	p_tooltip_view: TooltipView
) -> void:
	tactics = p_tactics
	tooltip_view = p_tooltip_view
	_ap_container = ap_container
	_mp_container = mp_container
	_ap_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_mp_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_ap_container.mouse_entered.connect(_on_ap_entered)
	_ap_container.mouse_exited.connect(_on_row_exited)
	_mp_container.mouse_entered.connect(_on_mp_entered)
	_mp_container.mouse_exited.connect(_on_row_exited)
	tactics.selection_changed.connect(refresh)
	refresh()


func _current_unit() -> Unit:
	if tactics == null or tactics.selection == null or tactics.selection.selected_unit == null:
		return null
	var previewed: Unit = tactics.selection.previewed_unit()
	return previewed if previewed != null else tactics.selection.selected_unit


func refresh() -> void:
	var unit: Unit = _current_unit()
	var ap_states: Array[bool] = []
	if unit != null:
		ap_states = ApMpPips.ap_pip_states(unit)
	_rebuild(_ap_container, ap_states, HulkTheme.HIGHLIGHT)

	var mp_count: int = ApMpPips.mp_pip_count(unit) if unit != null else 0
	var mp_states: Array[bool] = []
	for i in range(mp_count):
		mp_states.append(true)
	_rebuild(_mp_container, mp_states, HulkTheme.MP_PIP)


func _rebuild(container: HBoxContainer, states: Array[bool], lit_color: Color) -> void:
	for child: Node in container.get_children():
		child.queue_free()
	for lit: bool in states:
		var pip := PanelContainer.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = lit_color if lit else HulkTheme.DIM
		pip.add_theme_stylebox_override("panel", style)
		container.add_child(pip)


func _on_ap_entered() -> void:
	var unit: Unit = _current_unit()
	if tooltip_view == null or unit == null:
		return
	tooltip_view.show_data(
		TooltipBuilder.for_ap_pips(unit), _ap_container.get_viewport().get_mouse_position()
	)


func _on_mp_entered() -> void:
	var unit: Unit = _current_unit()
	if tooltip_view == null or unit == null:
		return
	tooltip_view.show_data(
		TooltipBuilder.for_mp_pips(unit), _mp_container.get_viewport().get_mouse_position()
	)


func _on_row_exited() -> void:
	if tooltip_view != null:
		tooltip_view.hide_tooltip()
