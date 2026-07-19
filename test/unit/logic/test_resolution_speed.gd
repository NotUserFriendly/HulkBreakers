extends GutTest

## taskblock-18 A2: ResolutionSpeed.resolve() — the single ordering axis
## every contender in the future re-validating resolver (Pass B) sorts by.
## Lower resolves first; personal_speed and action_family_bonus both
## subtract from base_action_speed.


func _unit_with_personal_speed(personal_speed: float, id: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	var matrix := Matrix.new()
	matrix.personal_speed = personal_speed
	var unit := Unit.new(matrix, Shell.new(torso), Vector2i(0, 0))
	unit.id = id
	return unit


func test_personal_speed_subtracts_from_the_actions_own_base_speed() -> void:
	var unit: Unit = _unit_with_personal_speed(15.0)
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var face := FaceAction.new(unit, 0.0)  # base speed 100.0

	var result: StatValue = ResolutionSpeed.resolve(face, state)

	assert_almost_eq(result.base, 100.0, 0.0001)
	assert_almost_eq(result.current, 85.0, 0.0001, "100 base - 15 personal_speed = 85")


func test_a_higher_personal_speed_unit_resolves_an_identical_action_sooner() -> void:
	var slow_unit: Unit = _unit_with_personal_speed(0.0, 0)
	var fast_unit: Unit = _unit_with_personal_speed(20.0, 1)
	var state := CombatState.new(Grid.new(5, 5), [slow_unit, fast_unit])

	var slow_face := FaceAction.new(slow_unit, 0.0)
	var fast_face := FaceAction.new(fast_unit, 0.0)

	var slow_speed: float = ResolutionSpeed.resolve(slow_face, state).current
	var fast_speed: float = ResolutionSpeed.resolve(fast_face, state).current

	assert_lt(
		fast_speed, slow_speed, "lower resolution_speed resolves sooner — the faster matrix wins"
	)


func test_zero_personal_speed_contributes_no_source() -> void:
	var unit: Unit = _unit_with_personal_speed(0.0)
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var face := FaceAction.new(unit, 0.0)

	var result: StatValue = ResolutionSpeed.resolve(face, state)

	assert_false(result.changed(), "a placeholder-default (0.0) matrix must not fake a bonus")


## A3: "action_family_bonus is present, returns 0, and is read through the
## formula" — the hook exists and is queried, even though no perk exists
## yet to make it return anything else.
func test_action_family_bonus_hook_is_present_and_returns_zero() -> void:
	var unit: Unit = _unit_with_personal_speed(0.0)
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var face := FaceAction.new(unit, 0.0)

	assert_almost_eq(ResolutionSpeed.action_family_bonus(face, unit), 0.0, 0.0001)
	assert_almost_eq(
		ResolutionSpeed.resolve(face, state).current,
		100.0,
		0.0001,
		"with no perks and no personal_speed, resolution_speed is just the base"
	)


## docs/08: "the tooltip and the damage must come from the same call" —
## resolution_speed is no different. A non-zero personal_speed must show
## up as a real, named, subtractive ModSource, not just a bare number.
func test_resolves_through_stat_resolver_with_real_provenance() -> void:
	var unit: Unit = _unit_with_personal_speed(12.0)
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var face := FaceAction.new(unit, 0.0)

	var result: StatValue = ResolutionSpeed.resolve(face, state)

	assert_true(result.changed())
	assert_eq(result.sources.size(), 1)
	assert_eq(result.sources[0].source_kind, Enums.ModSourceKind.SKILL)
	assert_almost_eq(result.sources[0].delta, -12.0, 0.0001)


## An action whose unit_id() doesn't resolve to a real unit (the base
## CombatAction's own -1 default) must not crash — base_action_speed
## alone still resolves, with no personal_speed/family_bonus term.
func test_an_action_with_no_resolvable_unit_still_resolves_the_base_speed() -> void:
	var state := CombatState.new(Grid.new(5, 5), [])
	var bare_action := CombatAction.new()

	var result: StatValue = ResolutionSpeed.resolve(bare_action, state)

	assert_almost_eq(result.current, 0.0, 0.0001)
	assert_false(result.changed())
