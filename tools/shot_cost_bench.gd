class_name ShotCostBench
extends RefCounted

## taskblock-52 Pass A2: **what the shot plane costs, per shot and per burst.**
##
## `BR26.02`'s hot path measured `ShotPlane.build` at **35 258 usec**. That figure
## is the one thing standing in the ray chain's way — the taskblock's own framing
## is that the plane's genuine win is amortisation: *one build serves a whole
## burst, then N cheap point-in-rect tests*, where a ray chain pays per round. A
## trade that big deserves a measurement rather than an argument, and the
## historical number predates several blocks of change, so it is re-taken here.
##
## ## The amortisation claim is measured, not assumed
##
## `planes per burst` is read straight off `ShotPlane.builds`, the static counter
## the plane already keeps. It is reported first because it is the number the
## whole trade rests on: if a burst genuinely builds one plane, the plane wins on
## bursts by a wide margin; if it builds one per projectile, the amortisation
## being weighed is not one the code actually performs.
##
## ## Two entry points, one implementation
##
## Same shape as `AiPlanningBench` and for the same reason — an export template
## ignores `-s res://...`, so the release half of any release-versus-debug figure
## has to come in through a main scene. A bench whose two builds could drift
## measures nothing.
##
##     godot --headless --path . -s res://tools/bench_shot_cost.gd
##     ./tools/bench_release.sh shot_cost
##
## ## Why the timed shots carry zero damage
##
## Repetition needs a board that does not change underneath it. A real 20-round
## chaingun burst chews walls, and by the tenth repetition the geometry being
## measured is a different, holier room — the measurement would drift downward
## and read as an optimisation. Damage does not affect the plane build at all
## (the dominant term) and affects the walk only by continuing a penetration
## cascade, so the walk figure is a floor rather than an average, and says so.
## **The one real burst below is fired at full damage**, once, precisely because
## it is not repeated.

const MAP_SEED := 31337
const BUILD_REPEATS := 40
const SHOT_REPEATS := 40
## The muzzle height an ordinary standing shooter fires from — used only to give
## the timed builds a realistic, genuinely 3D origin rather than a flat one.
const AIM_HEIGHT := 1.25


func run(_argv: PackedStringArray) -> void:
	var built: Dictionary = _board()
	if built.get("error", "") != "":
		print("=== shot cost bench ===")
		print("%s" % BuildIdentity.describe())
		print("FAILED to build a board: %s" % built["error"])
		return

	var state: CombatState = built["state"]
	var shooter: Unit = state.units[0]
	var target: Unit = _first_enemy(state, shooter)

	print("=== shot cost bench ===")
	print("%s" % BuildIdentity.describe())
	if not BuildIdentity.is_representative_of_play():
		print("  ^ NOT an exported release build — carries GDScript debug per-line overhead")
	print("map seed         : %d" % MAP_SEED)
	print(
		(
			"board            : %dx%d, %d blockers, %d field-item cells, %d placements"
			% [
				state.grid.width,
				state.grid.rows,
				state.grid.blockers.size(),
				state.grid.field_items.size(),
				state.grid.placements().size(),
			]
		)
	)
	print(
		(
			"units            : %d, %d parts on the shooter"
			% [state.units.size(), shooter.shell.all_parts().size()]
		)
	)

	var geometry: Dictionary = _geometry(state, shooter, target)
	var build: Dictionary = _time_plane_build(state, geometry)
	var build_usec: float = build["usec"]
	var shot_usec: float = _time_one_shot(state, shooter, geometry)
	var ray_usec: float = _time_one_ray_shot(state, shooter, geometry)
	var burst: Dictionary = _one_real_burst(state, shooter, target)

	print("")
	print("plane regions    : %10d" % [int(build["regions"])])
	print("plane build      : %10.1f usec  (x%d)" % [build_usec, BUILD_REPEATS])
	print("one shot         : %10.1f usec  (x%d, build + walk)" % [shot_usec, SHOT_REPEATS])
	print(
		(
			"  of which walk  : %10.1f usec  (floor — a zero-damage round stops at hit one)"
			% [shot_usec - build_usec]
		)
	)
	print("")
	if burst.get("ok", false):
		print("burst size       : %d rounds (%s)" % [burst["rounds"], burst["weapon"]])
		print(
			(
				"one burst        : %10.1f usec  (one real burst, full damage, fired once)"
				% [float(burst["usec"])]
			)
		)
		print(
			"planes per burst : %10d  <-- the amortisation claim, measured" % [int(burst["planes"])]
		)
		print(
			"usec per plane   : %10.1f" % [float(burst["usec"]) / maxf(1.0, float(burst["planes"]))]
		)
	else:
		print("burst            : not measured — %s" % burst.get("why", "no burst weapon found"))
	print("")
	print("--- ray chain (taskblock-52) ---")
	print("one shot         : %10.1f usec  (x%d, march + resolve)" % [ray_usec, SHOT_REPEATS])
	if ray_usec > 0.0:
		print(
			(
				"vs plane         : %10.2fx  (%.0f%% of the plane's per-shot cost)"
				% [shot_usec / ray_usec, 100.0 * ray_usec / shot_usec]
			)
		)
	if burst.get("ok", false):
		print(
			(
				"a %d-round burst : %10.1f usec plane  ->  %10.1f usec ray (est., %d x one shot)"
				% [
					int(burst["rounds"]),
					float(burst["usec"]),
					ray_usec * float(burst["rounds"]),
					int(burst["rounds"]),
				]
			)
		)
	print("")
	print("ms per shot      : %.3f" % (shot_usec / 1000.0))
	print("ms per ray shot  : %.3f" % (ray_usec / 1000.0))


## A real generated board with real assembled bodies — never a synthetic room.
## The plane's cost scales with what is actually on the map, and a hand-built
## fixture with four walls would report a number no player will ever pay.
func _board() -> Dictionary:
	var shooter_preset: BotPreset = DataLibrary.get_preset(&"combat_tester_chaingun")
	var target_preset: BotPreset = DataLibrary.get_preset(&"combat_tester_sniper_rifle")
	if shooter_preset == null or target_preset == null:
		return {"error": "the combat tester presets are not loaded"}
	return BoutSetup.build_bout(
		[BoutRosterEntry.new(shooter_preset, &"aggressive")] as Array[BoutRosterEntry],
		[BoutRosterEntry.new(target_preset, &"aggressive")] as Array[BoutRosterEntry],
		MAP_SEED
	)


func _first_enemy(state: CombatState, shooter: Unit) -> Unit:
	for unit: Unit in state.units:
		if unit != shooter and unit.alive:
			return unit
	return shooter


## The origin/direction an `AttackAction` would actually build the plane from —
## re-derived here through `ShotPlane.elevation_for`, the same shared seam every
## production firing action goes through, so the timed call is the production one.
##
## **`build_origin`/`build_direction` are exactly what `DamageResolver.resolve_shot`
## reconstructs internally**, not a second nearby pair. The first version of this
## bench timed `elevation_for`'s tilted direction against a shot fired flat, and
## reported a whole shot as *cheaper* than the plane build inside it — an
## impossible result that came from measuring two different builds. Face-visibility
## culling in `BodyProjector` is direction-dependent, so "roughly the same heading"
## is not the same work.
func _geometry(state: CombatState, shooter: Unit, target: Unit) -> Dictionary:
	var origin := Vector2(shooter.cell)
	var elevation: Dictionary = ShotPlane.elevation_for(
		origin, AIM_HEIGHT, shooter.cell, target.cell, state.grid
	)
	var flat_direction: Vector2 = Vector2(target.cell) - origin
	var vertical_slope: float = elevation["vertical_slope"]
	var dir: Vector2 = flat_direction.normalized()
	elevation["flat_origin"] = origin
	elevation["flat_direction"] = flat_direction
	elevation["vertical_slope"] = vertical_slope
	elevation["build_origin"] = Vector3(origin.x, AIM_HEIGHT, origin.y)
	elevation["build_direction"] = Vector3(dir.x, vertical_slope, dir.y).normalized()
	return elevation


func _time_plane_build(state: CombatState, geometry: Dictionary) -> Dictionary:
	var origin: Vector3 = geometry["build_origin"]
	var direction: Vector3 = geometry["build_direction"]
	var warm: Array[Region] = ShotPlane.build(origin, direction, state)
	var started: int = Time.get_ticks_usec()
	for _i in range(BUILD_REPEATS):
		ShotPlane.build(origin, direction, state)
	return {
		"usec": float(Time.get_ticks_usec() - started) / float(BUILD_REPEATS),
		"regions": warm.size(),
	}


## One projectile end to end: `DamageResolver.resolve_shot`, which builds its own
## plane and then walks it. Zero damage — see this class's own doc comment.
##
## `origin_height`/`vertical_slope` are passed so this shot builds the **same**
## plane `_time_plane_build` times; without them the shot builds a flat one and the
## two figures are not comparable.
func _time_one_shot(state: CombatState, shooter: Unit, geometry: Dictionary) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	var origin: Vector2 = geometry["flat_origin"]
	var direction: Vector2 = geometry["flat_direction"]
	var vertical_slope: float = geometry["vertical_slope"]
	var point := Vector2(0.0, AIM_HEIGHT)
	var fire: Callable = func() -> void:
		DamageResolver.resolve_shot(
			origin,
			direction,
			point,
			0.0,
			0.0,
			state,
			state.material_table,
			rng,
			0,
			DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
			DamageResolver.DEFAULT_DAMAGE_FLOOR,
			DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
			excluded,
			0.0,
			vertical_slope,
			AIM_HEIGHT
		)
	fire.call()  # warm
	var started: int = Time.get_ticks_usec()
	for _i in range(SHOT_REPEATS):
		fire.call()
	return float(Time.get_ticks_usec() - started) / float(SHOT_REPEATS)


## The same shot through the ray chain, for the like-for-like per-shot figure the
## hard pause is judged on. Zero damage for the same reason the plane's timed shot
## carries none: a repeated real shot would chew the board being measured.
##
## **The burst figure for the ray chain is an estimate and is labelled as one.** A
## chain has nothing to amortise across a burst by construction, so N rounds cost N
## shots — which is exactly the property the plane was credited with beating and,
## measured, does not.
func _time_one_ray_shot(state: CombatState, shooter: Unit, geometry: Dictionary) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	var origin: Vector2 = geometry["flat_origin"]
	var from := Vector3(
		origin.x * UnitGeometry.CELL_SIZE, AIM_HEIGHT, origin.y * UnitGeometry.CELL_SIZE
	)
	var direction: Vector3 = geometry["build_direction"]
	var toward: Vector3 = from + direction * 20.0
	var fire: Callable = func() -> void:
		RayChain.resolve(state, from, toward, 0.0, 0.0, state.material_table, rng, excluded)
	fire.call()  # warm
	var started: int = Time.get_ticks_usec()
	for _i in range(SHOT_REPEATS):
		fire.call()
	return float(Time.get_ticks_usec() - started) / float(SHOT_REPEATS)


## One genuine `BurstAction`, at full damage, fired exactly once — the only
## honest way to read `planes per burst`, since that number is a property of how
## the action is written rather than of how fast it runs.
##
## `apply()` is called directly rather than through `is_legal()`/the queue: this
## is a cost probe, not a rules probe, and gating on legality would make the
## measurement depend on whose turn it happens to be.
func _one_real_burst(state: CombatState, shooter: Unit, target: Unit) -> Dictionary:
	var weapon: Part = _burst_weapon(shooter)
	if weapon == null:
		return {"ok": false, "why": "the shooter carries no multi-round weapon"}
	var before: int = ShotPlane.builds
	var started: int = Time.get_ticks_usec()
	BurstAction.new(shooter, weapon.id, target.cell).apply(state)
	var elapsed: int = Time.get_ticks_usec() - started
	return {
		"ok": true,
		"usec": float(elapsed),
		"planes": ShotPlane.builds - before,
		"rounds": weapon.weapon_def.burst_size,
		"weapon": String(weapon.id),
	}


func _burst_weapon(shooter: Unit) -> Part:
	for part: Part in shooter.shell.all_parts():
		if part.weapon_def != null and part.weapon_def.burst_size > 1:
			return part
	return null
