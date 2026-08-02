extends GutTest

## taskblock-52 Pass C: **ties, and the evidence that any of these stages ever
## run.**
##
## Neither the supervisor nor CC knew the tie rate when this was specified. That
## is the point of the log line: a stage that fires once in ten thousand shots is
## a path nobody ever sees run, which is exactly the failure this project keeps
## producing. `test_the_tie_rate_across_a_dense_sweep_is_reported` measures it and
## prints it rather than asserting a number nobody has grounds for.
##
## **A tie is an attribution question, never a hit-or-miss one.** Two adjacent
## wall cells share a face plane, so a ray crossing that plane hits at least one
## of them; what is being decided is which cell takes the damage.

const AIM_HEIGHT := 1.0


class Recorder:
	extends LogSink

	var events: Array[LogEvent] = []

	func emit(event: LogEvent) -> void:
		events.append(event)

	func ties() -> Array[LogEvent]:
		var result: Array[LogEvent] = []
		for event: LogEvent in events:
			if event.kind == &"ray_tie":
				result.append(event)
		return result


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"shooter_torso"
	torso.material = &"steel"
	torso.hp = 40
	torso.max_hp = 40
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


## Two wall cells side by side, sharing the face plane at z = 5.5. A ray aimed at
## exactly that plane meets both at one `t` — the realistic tie, constructed.
func _shared_face_board() -> CombatState:
	var grid: Grid = GridFixture.flat(15, 15)
	GridFixture.place_wall(grid, Vector2i(10, 5))
	GridFixture.place_wall(grid, Vector2i(10, 6))
	return CombatState.new(grid, [_shooter(Vector2i(3, 5))])


## The tie exists at all. Without this, every assertion below could be passing
## over a set of one.
func test_two_adjacent_walls_sharing_a_face_plane_genuinely_tie() -> void:
	var state: CombatState = _shared_face_board()
	# Aimed at the shared edge: x = 9.5 (the near faces) and z = 5.5 (the seam).
	var from := Vector3(3.0, AIM_HEIGHT, 5.5)
	var tied: Array[RayHit] = RayCaster.tied_candidates(state, from, Vector3(1, 0, 0))
	var cells: Array[Vector2i] = []
	for hit: RayHit in tied:
		cells.append(hit.cell)
	print("  axis-aligned at the seam: %d tied candidates %s" % [tied.size(), str(cells)])
	assert_eq(tied.size(), 2, "both wall cells are met at the same distance")
	assert_almost_eq(tied[0].t, tied[1].t, 0.0001, "at genuinely the same t")


## An axis-aligned tie falls past stage 2, and then **past stage 3 as well** —
## which is not what the design predicted, and is a real finding rather than a
## fixture accident.
##
## The taskblock's reasoning for closest root was that "the gun is offset from
## the unit's centreline and the two cells' centres differ, so root-to-root
## distance separates them." **The condition that creates an axis-aligned tie
## defeats that.** To meet two side-by-side cells at one `t` with an axis-aligned
## ray, the ray must lie exactly on their shared plane — and every point on that
## plane is equidistant from both cells' roots, whatever the muzzle offset. So
## stage 3 is symmetric in precisely the case stage 2 defers to it in, and the
## geometric stable order is what actually decides.
##
## Kept as an assertion of what happens, with the reason, rather than quietly
## letting a stage nobody has seen run look like it works.
func test_an_axis_aligned_tie_falls_past_the_box_cast_and_past_closest_root() -> void:
	var state: CombatState = _shared_face_board()
	var recorder := Recorder.new()
	state.combat_log.add_sink(recorder)
	var from := Vector3(3.0, AIM_HEIGHT, 5.5)

	var hit: RayHit = RayCaster.cast(state, from, Vector3(1, 0, 0), [], INF, state.combat_log)
	assert_not_null(hit, "a tie still resolves to something — that is the whole point")
	var ties: Array[LogEvent] = recorder.ties()
	assert_eq(ties.size(), 1, "one tie, one log line")
	print("  %s" % ties[0].text)
	assert_eq(
		ties[0].data["stage"],
		RayTiebreak.STAGE_STABLE_ORDER,
		"both the probe and the two roots are symmetric about a ray on the shared plane"
	)
	assert_eq(ties[0].data["candidates"], 2)

	# The reason, asserted directly rather than argued: the roots really are
	# equidistant, so closest root has nothing to separate.
	var roots: Array[float] = []
	for candidate: RayHit in RayCaster.tied_candidates(state, from, Vector3(1, 0, 0)):
		roots.append(from.distance_to(candidate.root_origin))
	print("  root distances: %s" % str(roots))
	assert_almost_eq(roots[0], roots[1], 0.0001, "equidistant, which is why stage 3 declines")


## Angled, and stage 2 earns its place: the leading corner separates the two
## cells and the box cast resolves it. **This is the evidence that stage 2 is
## something other than insurance.**
func test_an_angled_tie_is_resolved_by_the_box_cast() -> void:
	var state: CombatState = _shared_face_board()
	var recorder := Recorder.new()
	state.combat_log.add_sink(recorder)
	var resolved_by_box := 0
	var seen := 0
	# Sweep the approach angle: the ray must still arrive at the shared seam, so
	# the origin moves with the angle rather than the aim.
	for degrees in range(2, 40, 2):
		var rad: float = deg_to_rad(float(degrees))
		var dir := Vector3(cos(rad), 0.0, sin(rad))
		var from: Vector3 = Vector3(9.5, AIM_HEIGHT, 5.5) - dir * 6.0
		var tied: Array[RayHit] = RayCaster.tied_candidates(state, from, dir)
		if tied.size() < 2:
			continue
		seen += 1
		recorder.events.clear()
		RayCaster.cast(state, from, dir, [], INF, state.combat_log)
		var ties: Array[LogEvent] = recorder.ties()
		assert_eq(ties.size(), 1, "every tie logs, at %d degrees" % degrees)
		if ties[0].data["stage"] == RayTiebreak.STAGE_BOX_CAST:
			resolved_by_box += 1
			if resolved_by_box == 1:
				print("  first box-cast resolution at %d degrees: %s" % [degrees, ties[0].text])
	print("  %d of %d angled ties resolved by the box cast" % [resolved_by_box, seen])
	assert_gt(seen, 0, "the sweep must actually produce angled ties")
	assert_gt(resolved_by_box, 0, "stage 2 must actually resolve something, or it is dead code")


## **The property that keeps stage 2 an arbiter rather than a second cast.** The
## taskblock asks for this one by name: the box stage never returns a body the
## raycast did not find.
func test_the_box_stage_never_returns_a_body_the_raycast_did_not_find() -> void:
	var state: CombatState = _shared_face_board()
	var checked := 0
	for degrees in range(0, 90, 3):
		var rad: float = deg_to_rad(float(degrees))
		var dir := Vector3(cos(rad), 0.0, sin(rad))
		var from: Vector3 = Vector3(9.5, AIM_HEIGHT, 5.5) - dir * 6.0
		var tied: Array[RayHit] = RayCaster.tied_candidates(state, from, dir)
		if tied.is_empty():
			continue
		var winner: RayHit = RayCaster.cast(state, from, dir)
		assert_not_null(winner)
		var found := false
		for candidate: RayHit in tied:
			if candidate.part == winner.part and candidate.cell == winner.cell:
				found = true
		assert_true(
			found, "at %d degrees the winner must be one of the raycast's own candidates" % degrees
		)
		checked += 1
	print("  checked %d resolutions against their own candidate sets" % checked)
	assert_gt(checked, 10, "the sweep must actually exercise the property")


## Ties resolve the same way twice. A tiebreak that wobbles is worse than no
## tiebreak, because it makes a whole seeded battle irreproducible.
func test_a_tie_resolves_identically_across_runs() -> void:
	for degrees in range(0, 90, 5):
		var rad: float = deg_to_rad(float(degrees))
		var dir := Vector3(cos(rad), 0.0, sin(rad))
		var from: Vector3 = Vector3(9.5, AIM_HEIGHT, 5.5) - dir * 6.0
		var first: RayHit = RayCaster.cast(_shared_face_board(), from, dir)
		var second: RayHit = RayCaster.cast(_shared_face_board(), from, dir)
		assert_eq(first == null, second == null, "same answer at %d degrees" % degrees)
		if first != null:
			assert_eq(first.cell, second.cell, "same cell at %d degrees" % degrees)


## The last-resort order is **geometric, not dictionary order**. Built by handing
## the stage two candidates whose roots are exactly equidistant, which is the only
## way stage 3 can decline.
func test_the_last_resort_sorts_on_the_cell_rather_than_on_insertion_order() -> void:
	var state: CombatState = _shared_face_board()
	var far: RayHit = RayHit.new()
	far.part = state.grid.blockers[Vector2i(10, 6)]
	far.cell = Vector2i(10, 6)
	far.root_origin = Vector3(1.0, 0.0, 0.0)
	var near: RayHit = RayHit.new()
	near.part = state.grid.blockers[Vector2i(10, 5)]
	near.cell = Vector2i(10, 5)
	near.root_origin = Vector3(-1.0, 0.0, 0.0)

	# Equidistant roots, so stages 2 and 3 both decline (no placements either).
	var recorder := Recorder.new()
	var log := CombatLog.new()
	log.add_sink(recorder)
	var forward: RayHit = RayTiebreak.resolve(
		[far, near] as Array[RayHit], Vector3.ZERO, Vector3(1, 0, 0), log
	)
	var backward: RayHit = RayTiebreak.resolve(
		[near, far] as Array[RayHit], Vector3.ZERO, Vector3(1, 0, 0), log
	)
	assert_eq(forward.cell, backward.cell, "the order it was handed them in cannot matter")
	assert_eq(forward.cell, Vector2i(10, 5), "lowest cell wins, deterministically")
	assert_eq(
		recorder.ties()[0].data["stage"],
		RayTiebreak.STAGE_STABLE_ORDER,
		"and it says which stage decided"
	)


## **The tie rate, measured rather than guessed.** Reported, not asserted against
## a threshold: nobody has grounds for a number here yet, and inventing one would
## be exactly the balance-number-as-design move this project forbids. What *is*
## asserted is that ties never swallow a shot.
func test_the_tie_rate_across_a_dense_sweep_is_reported() -> void:
	var grid: Grid = GridFixture.enclosed_room(21, 21)
	var shooter: Unit = _shooter(Vector2i(10, 10))
	var state := CombatState.new(grid, [shooter])
	var recorder := Recorder.new()
	state.combat_log.add_sink(recorder)
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	var from := Vector3(10.0, AIM_HEIGHT, 10.0)
	var shots := 0
	var empties := 0
	for a in range(720):
		var angle: float = TAU * float(a) / 720.0
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var hit: RayHit = RayCaster.cast(state, from, dir, excluded, INF, state.combat_log)
		shots += 1
		if hit == null:
			empties += 1

	var by_stage: Dictionary = {}
	for event: LogEvent in recorder.ties():
		var stage: StringName = event.data["stage"]
		by_stage[stage] = int(by_stage.get(stage, 0)) + 1
	print(
		(
			"  %d shots, %d ties (%.2f%%), by stage: %s"
			% [
				shots,
				recorder.ties().size(),
				100.0 * float(recorder.ties().size()) / shots,
				str(by_stage)
			]
		)
	)
	assert_eq(empties, 0, "a tie is an attribution question — it never loses the shot")
	# **Reported, not asserted against a threshold.** Nobody has grounds for a
	# target tie rate yet, and inventing one would be a balance number presented
	# as design. What the sweep may assert is that the breakdown is not empty — a
	# log that never fires proves nothing about any stage.
	assert_gt(recorder.ties().size(), 0, "a dense sweep of a walled room does produce ties")


## **Closest root has never fired, across everything measured.** Stage 2 takes
## every angled tie and the geometric stable order takes every axis-aligned one,
## because both the probe and the root pair are symmetric about a ray lying on the
## shared plane.
##
## This is exactly what the combat-log line was specified to reveal — the
## taskblock's own words are that a stage firing once in ten thousand shots is a
## path nobody ever sees run.
##
## **Supervisor's decision (2026-08-02): the stage stays, as cheap insurance.** So
## this is a measurement of the current state, deliberately not a rule and
## deliberately not an argument for deletion. If a later change makes closest root
## fire, update this test to say so — it stops being dead code and that is good
## news, not a regression.
func test_closest_root_does_not_fire_in_any_tie_that_can_currently_be_constructed() -> void:
	var grid: Grid = GridFixture.enclosed_room(21, 21)
	var shooter: Unit = _shooter(Vector2i(10, 10))
	var state := CombatState.new(grid, [shooter])
	var recorder := Recorder.new()
	state.combat_log.add_sink(recorder)
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	var from := Vector3(10.0, AIM_HEIGHT, 10.0)
	for a in range(1440):
		var angle: float = TAU * float(a) / 1440.0
		RayCaster.cast(
			state, from, Vector3(cos(angle), 0.0, sin(angle)), excluded, INF, state.combat_log
		)
	var by_stage: Dictionary = {}
	for event: LogEvent in recorder.ties():
		var stage: StringName = event.data["stage"]
		by_stage[stage] = int(by_stage.get(stage, 0)) + 1
	print("  1440-ray sweep, ties by stage: %s" % str(by_stage))
	assert_eq(
		int(by_stage.get(RayTiebreak.STAGE_CLOSEST_ROOT, 0)),
		0,
		"recording the measured fact, not blessing it — see this test's own doc comment"
	)
