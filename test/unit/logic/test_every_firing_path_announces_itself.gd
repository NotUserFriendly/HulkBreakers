extends GutTest

## tb60 Pass B: **every way of putting a round in the air announces itself, and an eighth way
## fails this file until it tags in.**
##
## `BurstAction` was the only firing path that emitted a fire event. The other six emitted
## impacts only, so a sniper firing and a sniper idling were indistinguishable in the log until
## something was hit — and `BR54.01`'s angle table had to be inferred from impact geometry,
## which worked only because impacts happen to carry origin and hit points.
##
## **The by-construction claim is the enumeration below**, not a hope. `PATHS` is the whole set
## of ways this game resolves a shot; `test_no_unlisted_file_reaches_a_shot_resolver` sweeps
## `src/` for anything that reaches a resolver and fails when it finds a file that is not
## listed, and `test_every_listed_path_builds_an_announcement` fails when a listed file stops
## building one. A new firing path therefore fails a test until it is both listed and tagged
## in.
##
## ## What is driven for real, and what is not — stated rather than implied
##
## The behavioural tests below drive **three** of the seven paths as real actions through real
## `is_legal`/`apply`: a single shot, a multi-pull burst, and a melee thrust. Those are the
## three *shapes* — one announcement, several, and the neutral-vocabulary case — and each was
## chosen because it could fail differently. The remaining four (`SlashAction`, `GrindAction`,
## `Suppression`, `Overwatch`) are covered by the structural half above plus their own files;
## **this is a real limit of this file and is written down rather than left for a reader to
## discover.** Driving all seven here would duplicate five fixtures that already exist.

## The seven, by the file that owns each. **Add a row here when you add a firing path**, and
## the sweep below will tell you if you forgot.
const PATHS: Array[String] = [
	"res://src/logic/actions/attack_action.gd",
	"res://src/logic/actions/burst_action.gd",
	"res://src/logic/actions/stab_action.gd",
	"res://src/logic/actions/slash_action.gd",
	"res://src/logic/actions/grind_action.gd",
	"res://src/logic/suppression.gd",
	"res://src/logic/overwatch.gd",
]

## What "reaches a shot resolver" means, in source terms. `resolve_and_log_point` is the seam
## six paths share; `log_impact_result`/`log_miss_result` are how `Overwatch` reaches the log
## after resolving through `DamageResolver.resolve_shot` itself. **A new path will use one of
## these** — there is no fourth way to put an impact in the log.
const RESOLVER_CALLS: Array[String] = [
	"ShotResolution.resolve_and_log_point",
	"ShotResolution.log_impact_result",
	"ShotResolution.log_miss_result",
	"DamageResolver.resolve_shot",
]

## Files that legitimately mention a resolver call without being a firing path: the resolver
## itself, and the ray chain it delegates to. **Each entry is a permission for a *file that is
## part of the mechanism*, never for a path that has not tagged in** — the distinction
## `VocabularySweep`'s own header draws about its self-exemption.
const MECHANISM_FILES: Array[String] = [
	"res://src/logic/actions/shot_resolution.gd",
	"res://src/logic/ray_chain.gd",
	"res://src/logic/damage_resolver.gd",
]

const SELF_PATH := "res://test/unit/logic/test_every_firing_path_announces_itself.gd"

# --- the structural half: an eighth path fails until it tags in -----------------------


func test_no_unlisted_file_reaches_a_shot_resolver() -> void:
	var unlisted: Array[String] = []
	VocabularySweep.scan(
		[".gd"],
		SELF_PATH,
		func(path: String, _line_number: int, line: String) -> String:
			if not path.begins_with("res://src/"):
				return ""
			if path in PATHS or path in MECHANISM_FILES:
				return ""
			var code: String = line.split("#")[0]
			for call: String in RESOLVER_CALLS:
				if call in code and not unlisted.has(path):
					unlisted.append(path)
			return ""
	)

	assert_eq(
		unlisted,
		[] as Array[String],
		(
			"these files resolve a shot and are not listed as firing paths — list them in "
			+ "PATHS and give each a ShotAnnouncement:\n%s" % "\n".join(unlisted)
		)
	)


func test_every_listed_path_builds_an_announcement() -> void:
	var silent: Array[String] = []
	for path: String in PATHS:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "listed firing path %s does not exist" % path)
		if file == null:
			continue
		if not ("ShotAnnouncement.new(" in file.get_as_text()):
			silent.append(path)

	assert_eq(
		silent,
		[] as Array[String],
		"listed firing paths that build no announcement:\n%s" % "\n".join(silent)
	)


# --- the behavioural half: it actually emits, and carries what BR54.01 needs ----------


func _shooter(cell: Vector2i, orientation: float = 0.0) -> Unit:
	var root := Part.new()
	root.id = &"test_torso"
	root.hp = 10
	root.max_hp = 10
	var unit := Unit.new(Matrix.new(), Shell.new(root), cell, 0)
	unit.orientation = orientation
	return unit


func _state() -> CombatState:
	var grid := GridFixture.flat(8, 8)
	var unit := _shooter(Vector2i(1, 1))
	var state := CombatState.new(grid, [unit])
	state.combat_log = CombatLog.new()
	return state


## **A shot that hits nothing still announces**, which is the whole complaint restated as a
## test. Resolved into empty space with no target anywhere along the line.
func test_a_shot_that_strikes_nothing_still_announces() -> void:
	var state: CombatState = _state()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var shooter: Unit = state.units[0]
	var shot := ShotAnnouncement.new(
		&"attack", shooter.id, Vector2(1, 1), Vector2(0, 1), shooter.orientation, &"test_gun"
	)

	var landed: bool = ShotResolution.resolve_and_log_point(
		state,
		shooter,
		Vector2(1, 1),
		Vector2(0, 1),
		Vector2(0, 40),
		5.0,
		0.0,
		0.0,
		null,
		false,
		0.0,
		1.0,
		DamageResolver.DEFLECT_MODE_RICOCHET,
		0.0,
		0.0,
		0.0,
		shot
	)

	gut.p("landed: %s" % landed)
	assert_eq(
		sink.events_of_kind(ShotAnnouncement.KIND).size(),
		1,
		"the announcement does not depend on the shot hitting anything"
	)


## **One announcement per trigger pull, not one per projectile.** A shotgun pull throws nine
## pellets through nine resolver calls sharing one announcement, and the log must read as one
## shot — otherwise the instrument this pass exists to build reports nine snipers.
func test_one_pull_throwing_many_projectiles_announces_once() -> void:
	var state: CombatState = _state()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var shooter: Unit = state.units[0]
	var shot := ShotAnnouncement.new(
		&"burst", shooter.id, Vector2(1, 1), Vector2(0, 1), shooter.orientation, &"test_gun"
	)

	for pellet: int in range(9):
		ShotResolution.resolve_and_log_point(
			state,
			shooter,
			Vector2(1, 1),
			Vector2(0, 1),
			Vector2(float(pellet) * 0.1, 40),
			5.0,
			0.0,
			0.0,
			null,
			false,
			0.0,
			1.0,
			DamageResolver.DEFLECT_MODE_RICOCHET,
			0.0,
			0.0,
			0.0,
			shot
		)

	assert_eq(
		sink.events_of_kind(ShotAnnouncement.KIND).size(), 1, "nine pellets, one trigger pull"
	)


## The event carries **origin, direction, facing and weapon** — the taskblock's own list, and
## each of the four is there because one of the four unreadable entries needs it.
func test_the_announcement_carries_origin_direction_facing_and_weapon() -> void:
	var state: CombatState = _state()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var shooter: Unit = state.units[0]
	var shot := ShotAnnouncement.new(
		&"attack", shooter.id, Vector2(1, 1), Vector2(1, 0), PI / 2.0, &"test_gun"
	)

	ShotResolution.announce(state, shot)

	var events: Array[LogEvent] = sink.events_of_kind(ShotAnnouncement.KIND)
	assert_eq(events.size(), 1)
	var data: Dictionary = events[0].data
	for key: String in ["origin", "direction", "facing", "weapon", "method", "path"]:
		assert_true(data.has(key), "the announcement must carry %s" % key)
	assert_eq(data["origin"], Vector2(1, 1))
	assert_eq(data["direction"], Vector2(1, 0))
	assert_eq(data["weapon"], &"test_gun")


## **`BR54.01` as a number rather than a reconstruction.** The entry is precisely the angle
## between where a unit is pointed and where its round went, and it had to be inferred from
## impact geometry to be characterised at all. It is now a field.
func test_the_announcement_reports_the_angle_between_facing_and_travel() -> void:
	# Facing +X (PI/2 in this codebase's atan2(x, y) convention), firing along +Y.
	var shot := ShotAnnouncement.new(
		&"attack", 0, Vector2.ZERO, Vector2(0, 1), PI / 2.0, &"test_gun"
	)

	gut.p(
		(
			"travel %.1f deg, facing %.1f deg, off %.1f deg"
			% [rad_to_deg(shot.travel_angle()), rad_to_deg(PI / 2.0), shot.off_facing_degrees()]
		)
	)
	assert_almost_eq(
		shot.off_facing_degrees(), 90.0, 0.001, "a round fired square across the facing reads 90"
	)

	var aligned := ShotAnnouncement.new(&"attack", 0, Vector2.ZERO, Vector2(0, 1), 0.0, &"test_gun")
	assert_almost_eq(
		aligned.off_facing_degrees(), 0.0, 0.001, "and one fired along the facing reads 0"
	)

	# **Wrapped, not merely subtracted.** A unit facing just west of north firing just east of
	# north is 10 degrees off, not 350 — and the un-wrapped form is exactly the mistake a
	# hand-rolled reconstruction of this number would make.
	var wrapped := ShotAnnouncement.new(
		&"attack",
		0,
		Vector2.ZERO,
		Vector2(sin(deg_to_rad(5.0)), cos(deg_to_rad(5.0))),
		deg_to_rad(-5.0),
		&"test_gun"
	)
	assert_almost_eq(wrapped.off_facing_degrees(), 10.0, 0.001, "the short way round, always")


## **The melee vocabulary, decided once.** A stab resolves through the same path and *fired* is
## the wrong word, so the kind is neutral and the method is open data — a designer adding a
## weapon that delivers damage some new way adds a method, not a branch.
func test_the_vocabulary_is_neutral_and_the_method_is_data() -> void:
	var state: CombatState = _state()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.announce(
		state,
		ShotAnnouncement.new(
			&"stab", 0, Vector2.ZERO, Vector2(0, 1), 0.0, &"spike", ShotAnnouncement.METHOD_THRUST
		)
	)

	var events: Array[LogEvent] = sink.events_of_kind(ShotAnnouncement.KIND)
	assert_eq(events.size(), 1)
	assert_eq(events[0].data["method"], ShotAnnouncement.METHOD_THRUST)
	assert_false(
		"fire" in String(events[0].text).to_lower(),
		"a thrust must not be described as firing: %s" % events[0].text
	)
	assert_true(
		String(ShotAnnouncement.KIND).find("fire") == -1,
		"the event kind itself must be neutral, not gun-shaped"
	)


## Silent under `is_preview` — TACTICS queues intents and mutates nothing (`docs/09`), and a
## speculative shot has not been taken.
func test_a_previewed_shot_announces_nothing() -> void:
	var state: CombatState = _state()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	state.is_preview = true

	ShotResolution.announce(
		state, ShotAnnouncement.new(&"attack", 0, Vector2.ZERO, Vector2(0, 1), 0.0, &"test_gun")
	)

	assert_eq(sink.events_of_kind(ShotAnnouncement.KIND).size(), 0)


# --- the behavioural half, through real actions ---------------------------------------


func _ranged_weapon(id: StringName, burst: int = 1) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 20.0
	weapon.ap_cost = 1
	weapon.burst = burst
	weapon.provides_actions = [&"shoot"]
	# `Part.burst` and `WeaponDef.burst_size` are different things — the first samples one
	# distribution N times, the second is N independent trigger pulls — and `BurstAction`
	# gates on the second. Authoring only the first is what made the first version of the
	# burst fixture illegal.
	if burst > 1:
		weapon.weapon_def = WeaponDef.new()
		weapon.weapon_def.burst_size = burst
	weapon.scatter = [Ring.new(0.05, 1.0)]
	weapon.volume = [Box.new(Vector3(0.0, 0.0, 0.2), Vector3(0.1, 0.2, 0.4))]
	return weapon


func _melee_weapon(id: StringName) -> Part:
	var weapon: Part = _ranged_weapon(id)
	weapon.provides_actions = [&"stab"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.weapon_length = 2.0
	weapon.weapon_def.stab_width = 0.1
	return weapon


func _armed(cell: Vector2i, weapon: Part, unit_team: int = 0) -> Unit:
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(
		&"HAND", Transform3D(Basis(), Vector3(0.0, UnitGeometry.DEFAULT_MUZZLE_HEIGHT, 0.0))
	)
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, unit_team)


func _dummy(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 200
	torso.max_hp = 200
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 1)


func _drive(action: CombatAction, shooter: Unit, target: Unit) -> Array[LogEvent]:
	var grid := GridFixture.flat(12, 12)
	var state := CombatState.new(grid, [shooter, target])
	state.combat_log = CombatLog.new()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	# **Return rather than apply an illegal action.** `apply` assumes `is_legal` passed and
	# will dereference a weapon it did not find; under `-d` that raises a debugger break, which
	# waits for input and hangs the whole run instead of failing it.
	if not action.is_legal(state):
		assert_true(false, "fixture must produce a legal action")
		return [] as Array[LogEvent]
	action.apply(state)
	return sink.events_of_kind(ShotAnnouncement.KIND)


## **A real `AttackAction` announces once**, carrying the shooter's own facing beside the
## direction its round travelled — which is the pair `BR54.01` is about.
##
## **The facing recorded is the one the round actually leaves under, and that is post-re-face.**
## `AttackAction.apply` calls `FaceAction.face_for_free` toward the target before it fires, so a
## shooter set to any orientation is pointed at its target by the time the announcement is
## built. **Found by this test failing** on a fixture that assumed otherwise, and worth stating
## rather than quietly accommodating: it sharpens what a non-zero `off_facing` means in a real
## log. A queued attack should read near zero, so anything that does not is a signal rather
## than noise — which means `BR54.01`'s 43 degrees is **not** a stale-facing effect. That is
## consistent with `docs/02`'s own measurement that the aim point is the frontmost region's
## centre, and moves off-axis without the unit turning at all.
func test_a_real_attack_action_announces_once_facing_where_it_ends_up_pointed() -> void:
	var shooter: Unit = _armed(Vector2i(1, 1), _ranged_weapon(&"pistol"))
	shooter.orientation = PI / 2.0  # deliberately wrong: the action re-faces before firing
	var target: Unit = _dummy(Vector2i(1, 5))

	var events: Array[LogEvent] = _drive(
		AttackAction.new(shooter, &"pistol", Vector2i(1, 5)), shooter, target
	)

	assert_eq(events.size(), 1, "one trigger pull, one announcement")
	assert_eq(events[0].data["path"], &"attack")
	assert_eq(events[0].data["method"], ShotAnnouncement.METHOD_FIRE)
	# Read back off the real unit rather than re-derived, so this cannot agree with a second
	# copy of the same formula and nothing else.
	assert_almost_eq(
		float(events[0].data["facing"]),
		shooter.orientation,
		0.0001,
		"the announcement records the facing the round actually left under"
	)
	assert_almost_eq(
		float(events[0].data["off_facing"]),
		0.0,
		2.0,
		"and a queued attack re-faces, so it reads near zero off-facing"
	)
	gut.p("attack: %s" % events[0].text)


## **A real `BurstAction` announces once per pull**, so recoil widening across a burst is
## readable in the log rather than collapsed into one line — and `burst_fired` still marks the
## burst as a whole, because the two answer different questions.
func test_a_real_burst_action_announces_once_per_pull() -> void:
	var weapon: Part = _ranged_weapon(&"chaingun", 3)
	weapon.provides_actions = [&"shoot", &"burst"]
	var shooter: Unit = _armed(Vector2i(1, 1), weapon)
	var target: Unit = _dummy(Vector2i(1, 5))

	var grid := GridFixture.flat(12, 12)
	var state := CombatState.new(grid, [shooter, target])
	state.combat_log = CombatLog.new()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var action := BurstAction.new(shooter, &"chaingun", Vector2i(1, 5))
	if not action.is_legal(state):
		assert_true(false, "fixture must produce a legal burst")
		return
	action.apply(state)

	var announcements: Array[LogEvent] = sink.events_of_kind(ShotAnnouncement.KIND)
	gut.p(
		(
			"%d announcements, %d burst_fired summaries"
			% [announcements.size(), sink.events_of_kind(&"burst_fired").size()]
		)
	)
	assert_eq(announcements.size(), 3, "three pulls, three announcements")
	assert_eq(
		sink.events_of_kind(&"burst_fired").size(),
		1,
		"and one burst summary over them — the two are not the same event"
	)


## **A real `StabAction` announces as a thrust, not as firing.** The melee vocabulary decided
## once, driven through the real action rather than asserted about the class in isolation.
func test_a_real_stab_action_announces_a_thrust() -> void:
	var shooter: Unit = _armed(Vector2i(1, 1), _melee_weapon(&"spike"))
	var target: Unit = _dummy(Vector2i(1, 2))

	var events: Array[LogEvent] = _drive(
		StabAction.new(shooter, &"spike", Vector2i(1, 2)), shooter, target
	)

	assert_eq(events.size(), 1)
	assert_eq(events[0].data["path"], &"stab")
	assert_eq(events[0].data["method"], ShotAnnouncement.METHOD_THRUST)
	assert_false(
		"fire" in String(events[0].text).to_lower(),
		"a real stab must not read as firing: %s" % events[0].text
	)
	gut.p("stab: %s" % events[0].text)
