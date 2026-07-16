class_name StatPanel
extends Node

## docs/08/10 Phase 12.5: the selected unit's stat block. `damage` and
## `crit_chance` are resolved through WeaponResolver — the exact call
## AttackAction itself makes — so this number and whatever the combat log
## reports for that shot can never drift apart (docs/08's transparency
## proof). Pure presentation: computes nothing, just renders what
## WeaponResolver/DescriptionBuilder/StatBlockView already resolved.

var tactics: TacticsController
var label: RichTextLabel
var drill_down_label: RichTextLabel


func setup(
	p_tactics: TacticsController, p_label: RichTextLabel, p_drill_down_label: RichTextLabel
) -> void:
	tactics = p_tactics
	label = p_label
	drill_down_label = p_drill_down_label
	tactics.selection_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var unit: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	if unit == null:
		label.text = ""
		drill_down_label.text = ""
		return

	var weapon: Part = DeepStrike.find_operable_weapon(unit)
	if weapon == null:
		label.bbcode_enabled = false
		label.text = "[UNARMED]"
		drill_down_label.text = ""
		return

	var damage: StatValue = WeaponResolver.resolve_damage(weapon)
	var crit_chance: StatValue = WeaponResolver.resolve_crit_chance(weapon)
	var entries: Array = [
		{"label": "damage", "value": damage}, {"label": "crit_chance", "value": crit_chance}
	]
	StatBlockView.render(entries, label)
	StatBlockView.render_drill_down(damage, drill_down_label)
