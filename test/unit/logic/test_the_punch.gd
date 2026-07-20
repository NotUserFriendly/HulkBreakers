extends GutTest

## taskblock-25 Pass F (docs/PLAN.md "Phase M — Melee"): "the punch — the
## baseline melee every unit has, provided by the POWER capability...
## patches 'no weapon → nothing' alongside tb21 flee." Proven at the
## engine-mechanism level with a synthetic fixture, not by editing the
## real data/parts/hand.tres: that file's exact fields are pinned by
## test_data_migration_losslessness.gd's own snapshot, and giving it a
## nonzero `damage` collides with UnitAI._find_weapon_id (first living
## part with damage > 0 — the hand would win over the actual gripped gun
## for every existing ranged loadout, breaking test_full_mission.gd and
## test_combat_tester_presets.gd). A real "every shell gets a punching
## hand" content pass is unauthored balance work, not invented here — see
## MeleeReach's own posture on `shell_reach` for the same reasoning.


## A bare, POWER-capable hand — no GRIP occupant, no separate weapon Part
## anywhere — that provides its own stab directly. This is what "provided
## by the POWER capability" means mechanically: the part carrying POWER
## authors `&"stab"` in its own `provides_actions`, same convention any
## other weapon uses.
func _fist(shell_reach: float) -> Unit:
	var fist := Part.new()
	fist.id = &"fist"
	fist.hp = 5
	fist.max_hp = 5
	fist.attaches_to = [&"WRIST"]
	fist.capabilities = [&"POWER"]
	fist.provides_actions = [&"stab"]
	fist.damage = 2.0
	fist.ap_cost = 1
	fist.scatter = [Ring.new(0.15, 1.0)]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = fist
	torso.sockets = [wrist]

	var shell := Shell.new(torso)
	shell.shell_reach = shell_reach
	return Unit.new(Matrix.new(), shell, Vector2i(0, 0), 0)


func _make_target(cell: Vector2i, hp: int = 10) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = hp
	torso.max_hp = hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 1)


## "A weaponless unit can still punch" — no GRIP occupant at all, no
## weapon Part anywhere in the shell, and it's still a legal, damage-
## dealing StabAction, driven by ActionCatalog exactly like any weapon.
func test_an_unarmed_unit_can_punch() -> void:
	var striker: Unit = _fist(1.0)
	var target: Unit = _make_target(Vector2i(1, 0))
	var state := CombatState.new(Grid.new(10, 10), [striker, target])

	var provider: Part = ActionCatalog.provider_for(striker, &"stab")
	assert_not_null(provider, "the bare fist itself must provide the punch")
	assert_eq(provider.id, &"fist")

	var action := StabAction.new(striker, &"fist", target.cell)
	assert_true(action.is_legal(state))
	action.apply(state)

	assert_lt(target.shell.root.hp, 10, "the punch must deal real damage")


## The punch is available via `ActionCatalog.actions_for` — the same
## seam the action bar and the AI both read (tb24) — never a hardcoded
## "unarmed" branch anywhere else.
func test_the_punch_appears_on_the_action_bar_for_an_unarmed_unit() -> void:
	var striker: Unit = _fist(1.0)

	var ids: Array[StringName] = []
	for def: ActionDef in ActionCatalog.actions_for(striker):
		ids.append(def.id)

	assert_true(&"stab" in ids)
