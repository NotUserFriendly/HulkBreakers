class_name WeaponRows
extends RefCounted

## runNotes.md: builds the weapons-list panel's rows from a Unit's shell —
## pure and headless-testable, same split as InventoryRows/InventoryRow:
## this computes every row's active/why, the view only renders them.


## One row per attached, damage-dealing part (docs/01: "weapon" has no
## closed vocabulary — anything with `damage > 0.0` qualifies, same test
## DeepStrike.find_operable_weapon() uses), in shell-tree order.
static func build(unit: Unit) -> Array[WeaponRow]:
	var rows: Array[WeaponRow] = []
	if unit.shell.root == null:
		return rows
	var operable: Array[Part] = unit.shell.operable_parts()
	for part: Part in unit.shell.all_parts():
		if part.damage <= 0.0:
			continue
		rows.append(_row(part, operable))
	return rows


static func _row(weapon: Part, operable: Array[Part]) -> WeaponRow:
	if weapon.hp <= 0:
		return WeaponRow.new(weapon, false, "destroyed")
	if WoundEffects.is_disabled_by_wounds(weapon):
		return WeaponRow.new(weapon, false, _wound_reason(weapon))
	var manipulators: Array[Part] = []
	for part: Part in operable:
		if part != weapon:
			manipulators.append(part)
	if PartGraph.can_operate(weapon, manipulators):
		return WeaponRow.new(weapon, true)
	return WeaponRow.new(weapon, false, _unmet_requirements(weapon))


static func _unmet_requirements(weapon: Part) -> String:
	var needs: Array[String] = []
	for capability: StringName in weapon.requires:
		var count: int = int(weapon.requires[capability])
		needs.append("%dx %s" % [count, capability])
	return "needs %s, no free manipulator to operate it" % ", ".join(needs)


## taskblock-20 Pass D: the first disabling wound `weapon` carries, named —
## same "shows its reason" contract `_unmet_requirements` already gives the
## panel, just for a wound instead of a missing manipulator.
static func _wound_reason(weapon: Part) -> String:
	for wound_id: StringName in weapon.wounds:
		var def: WoundDef = DataLibrary.get_wound_def(wound_id)
		if def != null and def.disables:
			return "wound: %s" % wound_id
	return "wounded"
