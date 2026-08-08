extends GutTest

## taskblock-56 Pass B: **there is one aiming implementation, and this is what keeps it that way.**
##
## `docs/02` says a shot resolves from the shooter's real angle, so the player's path and the AI's
## path should agree. They do — and the reason is structural rather than lucky:
## `ActionCatalog.build_firing_action` is the only place in `src/` that constructs a firing action,
## and every firing action resolves its aim point through the identical expression
## `ShotPlane.center_of(plane, target) + aim_offset`. The AI simply never supplies an offset; the
## player may. **A default left alone is not a second implementation.**
##
## The tests here are the "so a later change cannot silently separate them" half of that pass. Three
## things have to stay true:
##
## 1. Both paths hand the same four values to the same constructor (below).
## 2. Nothing else in `src/` constructs a firing action, so there is no other door in.
## 3. The aim point is what `docs/02` now says it is — the centre of the target's **frontmost
##    projected region**. That one is pinned because it is a *finding*, not a design choice, and a
##    doc claim nobody tests goes stale in one taskblock.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## **Both bodies get an arm, and the target's is the point.** A bare `torso` is a single symmetric
## box, so its frontmost region sits dead on the muzzle-to-target axis and the off-axis effect
## these tests are about is exactly zero — a fixture that would let
## `test_the_off_axis_angle_grows_as_range_shrinks` pass while proving nothing, which is the
## vacuous-test failure `docs/TEST-AUDIT.md` keeps finding. A real assembled body has parts hanging
## off its centreline; one arm on one shoulder is the smallest fixture with that property.
##
## The arm goes on a `SHOULDER` socket because that is the only place it fits — a `torso` has no
## `HAND` socket, the chain is torso → arm → forearm → hand → weapon. Attaching to a socket type a
## part does not have fails silently, which is how the first version of this fixture ended up
## symmetric.
func _shooter_and_target() -> Dictionary:
	var shooter_torso: Part = _torso_with_an_arm()
	var weapon: Part = DataLibrary.get_part(&"pistol")
	var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(2, 5))
	var target := Unit.new(Matrix.new(), Shell.new(_torso_with_an_arm()), Vector2i(6, 5))
	# **Turned side-on, deliberately.** The shot runs along +X here, so the plane's lateral axis is
	# Z — and an arm hung off a shoulder is displaced along the body's own X. Facing the shooter,
	# that displacement lands in DEPTH and the lateral is exactly zero. A quarter turn puts it in
	# the lateral, which is the geometry a real bout produces constantly and the whole subject of
	# these tests.
	target.orientation = PI * 0.5

	var grid: Grid = GridFixture.flat(10, 10)
	return {
		"shooter": shooter,
		"target": target,
		"weapon": weapon,
		"state": CombatState.new(grid, [shooter, target]),
	}


func _torso_with_an_arm() -> Part:
	var torso: Part = DataLibrary.get_part(&"torso")
	var shoulder: Socket = PartGraph.find_free_socket(torso, &"SHOULDER")
	assert_not_null(shoulder, "fixture: a torso must have a shoulder to hang an arm from")
	PartGraph.attach(DataLibrary.get_part(&"arm"), torso, shoulder)
	return torso


## **The agreement, asserted on the values that reach the resolver.** The player path is
## `TacticsController.confirm_shot`'s own call — `build_firing_action(id, shooter, weapon.id,
## target.cell, reticle_offset)` with the reticle untouched — and the AI path is
## `UtilityExecutors.build`, which omits the offset entirely. Same class, same target, same weapon,
## same offset. If someone gives the AI its own aiming rule, this is what fails.
func test_the_player_and_the_ai_build_the_same_shot() -> void:
	var built: Dictionary = _shooter_and_target()
	var shooter: Unit = built.shooter
	var target: Unit = built.target
	var weapon: Part = built.weapon

	# The player, having clicked fire without touching the reticle — docs/10's "default burst at
	# the target's centre", which is the case the AI is being compared against.
	var player: CombatAction = ActionCatalog.build_firing_action(
		&"shoot", shooter, weapon.id, target.cell, Vector2.ZERO
	)
	# The AI, through its own executor table.
	var action_def := UtilityActionDef.new()
	action_def.id = &"shoot"
	action_def.executor_id = &"shoot"
	var ai: CombatAction = UtilityExecutors.build(action_def, shooter, target, [], weapon.id)

	assert_not_null(player, "sanity: the player's own call builds an action")
	assert_not_null(ai, "sanity: the AI's own call builds an action")
	assert_eq(
		player.get_script().resource_path,
		ai.get_script().resource_path,
		"the two paths must build the same class"
	)
	assert_eq(player.get(&"target_cell"), ai.get(&"target_cell"), "same target cell")
	assert_eq(player.get(&"weapon_id"), ai.get(&"weapon_id"), "same weapon")
	assert_eq(
		player.get(&"aim_offset"),
		ai.get(&"aim_offset"),
		"same aim offset -- the AI leaves the default the player also starts from"
	)


## **The AI never supplies an offset**, stated as its own fact rather than implied by the equality
## above. This is the actual answer to "does aiming differ between player and AI control": the
## player has a knob and the AI leaves it at zero. If the AI ever grows deliberate aiming — through
## `InternalTargeting`, say, which computes exactly this value and today has no production caller —
## this is the test that should be rewritten rather than deleted.
func test_the_ai_leaves_the_aim_offset_at_centre() -> void:
	var built: Dictionary = _shooter_and_target()
	var action_def := UtilityActionDef.new()
	action_def.id = &"shoot"
	action_def.executor_id = &"shoot"
	var ai: CombatAction = UtilityExecutors.build(
		action_def, built.shooter, built.target, [], built.weapon.id
	)
	assert_eq(ai.get(&"aim_offset"), Vector2.ZERO, "the AI aims at the resolver's own default")


## **One door in.** `build_firing_action` is a seam only while it is the *only* seam — a second
## `AttackAction.new` somewhere in `src/` would be a parallel path that the equality test above
## could not see, because it would never be asked. Swept in the shape of
## `test_retired_planner_sweep.gd`.
##
## `src/` only. A test fixture constructing an action directly is legitimate — CLAUDE.md's rule is
## that the *test* authors its own concrete cases — and `tools/` benches likewise.
func test_only_the_catalog_constructs_a_firing_action() -> void:
	var constructors: Array[String] = [
		"AttackAction.new(",
		"BurstAction.new(",
		"StabAction.new(",
		"SlashAction.new(",
		"GrindAction.new(",
	]
	var allowed := "res://src/logic/action_catalog.gd"
	var offenders: Array[String] = []
	for path: String in _gd_files("res://src"):
		if path == allowed:
			continue
		var text: String = _read(path)
		for constructor: String in constructors:
			if text.contains(constructor):
				offenders.append("%s constructs %s" % [path, constructor])
	for offender: String in offenders:
		gut.p(offender)
	assert_eq(
		offenders.size(),
		0,
		"a firing action is constructed outside ActionCatalog -- that is a second aiming path"
	)


## **Reversed at taskblock-61 on the supervisor's call, and the old text is kept in the reversal so
## the change is legible.** This used to pin the opposite: *"the aim point is not the target's
## centre ... it is `best.rect.get_center()` for the target's frontmost region — whichever single
## part projects nearest the shooter. An outstretched weapon or a raised arm therefore IS the aim
## point."* That was `docs/02`'s finding and `BR54.01`'s cause.
##
## **Now it is the TORSO's centre** — *"aiming at the torso's center is likely the best aim point
## for a unit to use"* — with per-body-part targeting arriving later for smarter units. The torso
## is the shell's `root`, which needs no new tag and no authoring.
##
## Asserted against the root's own region computed here from the same plane, so this says "the aim
## point is the torso's centre" rather than re-deriving a projection formula and agreeing with
## itself. **The frontmost region is read too, and asserted to be a DIFFERENT point** — otherwise
## this fixture could pass while the change did nothing.
func test_the_aim_point_is_the_torso_centre_not_the_frontmost_region() -> void:
	var built: Dictionary = _shooter_and_target()
	var shooter: Unit = built.shooter
	var target: Unit = built.target
	var state: CombatState = built.state
	var muzzle: Vector3 = UnitGeometry.shouldered_muzzle_point(shooter, built.weapon)
	var origin := Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE
	var elevation: Dictionary = ShotPlane.elevation_for(
		origin, muzzle.y, shooter.cell, target.cell, state.grid
	)
	var plane: Array[Region] = ShotPlane.build(elevation.origin, elevation.direction, state)

	var target_parts: Array[Part] = target.shell.all_parts()
	var frontmost: Region = null
	var torso: Region = null
	for region: Region in plane:
		if not target_parts.has(region.part):
			continue
		if frontmost == null or region.depth < frontmost.depth:
			frontmost = region
		if region.part == target.shell.root and (torso == null or region.depth < torso.depth):
			torso = region
	assert_not_null(frontmost, "sanity: the target projects into the plane at all")
	assert_not_null(torso, "sanity: the torso (the shell root) projects too")

	var aim: Vector2 = ShotPlane.center_of(plane, target)
	gut.p(
		(
			"aim %+.3f,%+.3f -- torso %s %+.3f,%+.3f -- frontmost %s %+.3f,%+.3f"
			% [
				aim.x,
				aim.y,
				torso.part.id,
				torso.rect.get_center().x,
				torso.rect.get_center().y,
				frontmost.part.id,
				frontmost.rect.get_center().x,
				frontmost.rect.get_center().y
			]
		)
	)
	assert_almost_eq(aim.x, torso.rect.get_center().x, 0.0001, "lateral is the torso's own")
	assert_almost_eq(aim.y, torso.rect.get_center().y, 0.0001, "height is the torso's own")
	# **The fixture has to be able to tell the two apart**, or this passes on a body where the
	# torso happens to be frontmost and proves nothing.
	assert_gt(
		torso.rect.get_center().distance_to(frontmost.rect.get_center()),
		0.05,
		"sanity: on this body the torso and the frontmost region are genuinely different points"
	)


## **Reversed at taskblock-61, and this one had gone rotten before it was reversed.**
##
## It used to read: *"the aim point carries a lateral offset from the muzzle-to-target-cell axis,
## and that offset is a fixed distance in the body rather than an angle — so the angle it subtends
## grows without limit as range shrinks"*, asserted as `readings[0] > readings[1]`.
##
## **With the torso as the aim point that offset is zero, and the old assertion kept passing on
## floating-point noise.** Both readings came out at 3.7e-9 cells, and `atan2(3.7e-9, 1.93)` is
## fractionally larger than `atan2(3.7e-9, 7.93)`, so a strict `>` was satisfied by a quantity that
## is numerically nothing. **A test claiming to confirm `BR54.01`'s range effect, passing because
## of the last bits of a float.** Caught only because the sibling test above went red and this one
## was read while fixing it.
##
## What it asserts now is the property that actually holds and that the change was made for: **the
## aim point sits on the muzzle-to-target axis at every range**, so there is no fixed lateral
## offset left for range to amplify.
##
## **The residual in `BR54.01` is not gone and is not this.** A real assembled body carries its
## muzzle on an outstretched arm, so the muzzle-to-target-*cell* axis and the muzzle-to-*torso*
## line still differ — measured at 7.35 degrees at one cell on a `combat_tester` preset. That is
## muzzle geometry, not aim-point choice, and it wants its own measurement rather than this
## fixture's centred one.
func test_the_aim_point_sits_on_the_axis_at_every_range() -> void:
	var readings: Array[float] = []
	for distance: int in [2, 8]:
		var built: Dictionary = _shooter_and_target()
		var shooter: Unit = built.shooter
		var target: Unit = built.target
		target.cell = Vector2i(shooter.cell.x + distance, shooter.cell.y)
		var state: CombatState = built.state
		var muzzle: Vector3 = UnitGeometry.shouldered_muzzle_point(shooter, built.weapon)
		var origin := Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE
		var elevation: Dictionary = ShotPlane.elevation_for(
			origin, muzzle.y, shooter.cell, target.cell, state.grid
		)
		var plane: Array[Region] = ShotPlane.build(elevation.origin, elevation.direction, state)
		var aim: Vector2 = ShotPlane.center_of(plane, target)
		var depth: float = ShotPlane.depth_of(plane, target)
		var degrees: float = absf(rad_to_deg(atan2(aim.x, depth)))
		readings.append(degrees)
		gut.p(
			(
				"range %d cells: aim point %.3f off axis at depth %.2f = %.2f deg"
				% [distance, aim.x, depth, degrees]
			)
		)
	# **An absolute bound, not a comparison between the two.** Comparing them is what let noise
	# satisfy this test; a bound cannot be met by a number that is merely smaller than another
	# number that is also nothing.
	for i: int in range(readings.size()):
		assert_lt(
			readings[i],
			0.01,
			(
				"reading %d: the torso aim point must sit on the axis, not merely near it (%.6f deg)"
				% [i, readings[i]]
			)
		)


func _gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			var full: String = "%s/%s" % [dir_path, entry]
			if dir.current_is_dir():
				pending.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	found.sort()
	return found


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()
