extends GutTest

## taskblock-21 Pass H — data-only fixes, authoring not code. Locks the
## re-authored values so a future edit that silently drifts them gets
## caught: H1 (three weighted scatter rings, middle heaviest) and H2
## (per-gun ap_cost/burst_ap_cost). Flagged placeholders, not tuned design
## numbers — this test exists to catch drift, not to bless these exact
## figures as final.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## H1: "the reference guns are authored with two rings... re-author each
## gun's scatter as three: outer (few, low weight), middle (most, high
## weight), inner (few, low weight)."
func test_every_reference_gun_has_three_scatter_rings_middle_heaviest() -> void:
	for gun_id: StringName in [
		&"sniper_rifle", &"chaingun", &"pump_shotgun", &"auto_shotgun", &"rifle"
	]:
		var gun: Part = DataLibrary.get_part(gun_id)
		assert_eq(gun.scatter.size(), 3, "%s must have exactly three scatter rings" % gun_id)
		var inner: Ring = gun.scatter[0]
		var middle: Ring = gun.scatter[1]
		var outer: Ring = gun.scatter[2]
		assert_lt(inner.radius, middle.radius, "%s: inner must be the smallest ring" % gun_id)
		assert_lt(middle.radius, outer.radius, "%s: outer must be the largest ring" % gun_id)
		assert_gt(
			middle.weight, inner.weight, "%s: the middle ring must carry the most weight" % gun_id
		)
		assert_gt(
			middle.weight, outer.weight, "%s: the middle ring must carry the most weight" % gun_id
		)


## H2: "sniper 3 AP/shot, chaingun 4 AP/burst, shotgun 2 AP/shot."
func test_authored_ap_costs_match_the_taskblocks_own_numbers() -> void:
	var sniper: Part = DataLibrary.get_part(&"sniper_rifle")
	assert_eq(sniper.ap_cost, 3)

	var chaingun: Part = DataLibrary.get_part(&"chaingun")
	assert_eq(chaingun.weapon_def.burst_ap_cost, 4)

	var pump_shotgun: Part = DataLibrary.get_part(&"pump_shotgun")
	assert_eq(pump_shotgun.ap_cost, 2)


## The authored ap_cost is what actually gets spent on fire — not a
## display-only number sitting unread. Reuses the real AttackAction path,
## never a hand re-derivation of the spend.
func test_sniper_rifles_ap_cost_is_what_attack_action_actually_spends() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var sniper: Part = DataLibrary.get_part(&"sniper_rifle")
	var grip := Socket.new(&"GRIP")
	grip.occupant = sniper
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [grip, wrist]

	var shooter := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var target := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(1, 0))
	var state := CombatState.new(Grid.new(5, 5), [shooter, target])
	shooter.ap = 10
	var before_ap: int = shooter.ap

	AttackAction.new(shooter, &"sniper_rifle", target.cell).apply(state)

	assert_eq(shooter.ap, before_ap - 3)


## A burst spends burst_ap_cost, not the single-shot ap_cost.
func test_chainguns_burst_spends_burst_ap_cost() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var chaingun: Part = DataLibrary.get_part(&"chaingun")
	var grip := Socket.new(&"GRIP")
	grip.occupant = chaingun
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [grip, wrist]

	var shooter := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var target := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(1, 0))
	var state := CombatState.new(Grid.new(5, 5), [shooter, target])
	shooter.ap = 10
	var before_ap: int = shooter.ap

	BurstAction.new(shooter, &"chaingun", target.cell).apply(state)

	assert_eq(shooter.ap, before_ap - 4)
