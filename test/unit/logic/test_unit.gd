extends GutTest


func _make_frame(agility: float) -> Shell:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.stat_mods = {"agility": agility}
	return Shell.new(root)


func test_mp_per_ap_uses_base_plus_agility() -> void:
	var matrix := Matrix.new()
	var shell := _make_frame(3.0)
	var unit := Unit.new(matrix, shell, Vector2i(0, 0))
	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP + 3.0, 0.0001)


func test_mp_per_ap_defaults_to_base_with_no_agility_stat() -> void:
	var matrix := Matrix.new()
	var shell := Shell.new(Part.new())
	var unit := Unit.new(matrix, shell, Vector2i(0, 0))
	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP, 0.0001)


func test_mp_per_ap_reflects_live_part_swaps() -> void:
	var matrix := Matrix.new()
	var shell := _make_frame(1.0)
	var unit := Unit.new(matrix, shell, Vector2i(0, 0))
	var before: float = unit.mp_per_ap()

	# Simulate a swap by mutating the root's stats directly (SwapPartAction
	# proper is rebuilt in Phase 6 against the socket model).
	shell.root.stat_mods = {"agility": 5.0}

	assert_almost_eq(unit.mp_per_ap(), Unit.BASE_MP + 5.0, 0.0001)
	assert_true(unit.mp_per_ap() > before)


func test_new_unit_starts_alive_with_no_held_matrix() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(1, 1), 2)
	assert_true(unit.alive)
	assert_null(unit.held_matrix)
	assert_eq(unit.squad_id, 2)
	assert_eq(unit.id, -1)


func test_new_unit_starts_at_the_top_of_the_surrogate_ladder() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(0, 0))
	assert_eq(unit.surrogate_tier.id, &"FULL")
	assert_eq(unit.exposed_turns, 0)


func test_demote_surrogate_steps_one_rung_and_starts_the_exposure_clock() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(0, 0))
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()

	unit.demote_surrogate(ladder)

	assert_eq(unit.surrogate_tier.id, &"PERIPHERAL")
	assert_eq(unit.exposed_turns, 1)


## docs/04 taskblock03 Pass A1: PERIPHERAL demotes to SPINAL (its one real
## upstream branch on the DAG) — never sideways to TORSIC, the mutually
## exclusive sibling branch taskblock02 D2's line-shaped ladder wrongly
## allowed.
func test_tick_organics_decay_demotes_further_every_decay_turns() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(0, 0))
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	unit.demote_surrogate(ladder)  # PERIPHERAL, exposed_turns 1

	for i in range(Unit.DECAY_TURNS - 1):
		unit.tick_organics_decay(ladder)
	assert_eq(unit.surrogate_tier.id, &"PERIPHERAL", "must not demote before DECAY_TURNS elapse")

	unit.tick_organics_decay(ladder)
	assert_eq(unit.surrogate_tier.id, &"SPINAL", "PERIPHERAL's one real branch, not sideways")


func test_tick_organics_decay_is_a_no_op_while_never_exposed() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(0, 0))
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	for i in range(10):
		unit.tick_organics_decay(ladder)
	assert_eq(unit.surrogate_tier.id, &"FULL")


## docs/09 taskblock06 Pass C: "poses are sampled at instants — nothing is
## ever integrated." pose_at() must never blend between poses; it always
## returns the exact same pose for any progress value.
func test_pose_at_returns_the_same_pose_regardless_of_progress() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(0, 0))
	unit.pose = Poses.aiming()

	assert_eq(unit.pose_at(0.0), unit.pose)
	assert_eq(unit.pose_at(0.5), unit.pose)
	assert_eq(unit.pose_at(1.0), unit.pose)
