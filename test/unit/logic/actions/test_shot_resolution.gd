extends GutTest

## taskblock-21 Pass F: "every fired shot draws its ray, hit or miss" — a
## genuine miss (the dartboard point landed nowhere any region in the whole
## shot plane covers) must still log something the view can draw a tracer
## from, not silently emit zero events the way it did before this pass.

## A point far outside any region's own rect in a mostly-empty shot plane —
## the shooter's own body is excluded at depth <= 0 (`resolve_and_log_point`
## always excludes the attacker), so nothing else is left to hit at all.
const MISS_POINT := Vector2(1000.0, 0.0)


func _make_unit(cell: Vector2i, squad_id: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


func test_a_genuine_miss_emits_a_miss_event() -> void:
	var shooter := _make_unit(Vector2i(0, 0))
	var bystander := _make_unit(Vector2i(10, 0), 1)
	var state := CombatState.new(Grid.new(20, 20), [shooter, bystander])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	var landed: bool = ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 0), Vector2(1, 0), MISS_POINT, 5.0, 0.0, 0.0, null
	)

	assert_false(landed, "sanity: this point really does miss everything")
	assert_eq(sink.events_of_kind(&"impact").size(), 0, "nothing was actually hit")
	assert_eq(sink.events_of_kind(&"miss").size(), 1, "a miss must still be logged")


func test_a_hit_never_also_emits_a_miss_event() -> void:
	var shooter := _make_unit(Vector2i(0, 0))
	var target := _make_unit(Vector2i(3, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	var landed: bool = ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 0), Vector2(1, 0), Vector2(0, 0), 5.0, 0.0, 0.0, null
	)

	assert_true(landed, "sanity: dead center on the target's own torso must land")
	assert_gt(sink.events_of_kind(&"impact").size(), 0)
	assert_eq(sink.events_of_kind(&"miss").size(), 0, "a real hit is never ALSO logged as a miss")


## The miss event must carry an endpoint genuinely downrange along the
## fired direction — not the origin, not some fixed placeholder.
func test_a_miss_events_endpoint_continues_along_the_fired_direction() -> void:
	var shooter := _make_unit(Vector2i(0, 0))
	var bystander := _make_unit(Vector2i(10, 0), 1)
	var state := CombatState.new(Grid.new(20, 20), [shooter, bystander])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 0), Vector2(1, 0), MISS_POINT, 5.0, 0.0, 0.0, null
	)

	var miss: LogEvent = sink.events_of_kind(&"miss")[0]
	var end_x: float = miss.data.get("end_x")
	assert_gt(end_x, 0.0, "the ray must continue forward along +x, not sit at the origin")


## When the firing weapon authored a real `max_range`, the void endpoint
## must respect it — never draw a "miss" tracer past where the round could
## ever have actually reached.
func test_a_miss_respects_the_weapons_own_authored_max_range() -> void:
	var shooter := _make_unit(Vector2i(0, 0))
	var bystander := _make_unit(Vector2i(20, 0), 1)
	var state := CombatState.new(Grid.new(40, 40), [shooter, bystander])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 0), Vector2(1, 0), MISS_POINT, 5.0, 0.0, 0.0, null, false, 5.0
	)

	var miss: LogEvent = sink.events_of_kind(&"miss")[0]
	assert_almost_eq(miss.data.get("end_x") as float, 5.0, 0.01)


## An unauthored weapon (`max_range` 0.0, the default) has no real cap to
## draw to — falls back to the map's own longest side so the void tracer
## still terminates somewhere on-board-ish, never grows unbounded.
func test_a_miss_with_no_authored_max_range_falls_back_to_the_map_size() -> void:
	var shooter := _make_unit(Vector2i(0, 0))
	var bystander := _make_unit(Vector2i(10, 0), 1)
	var state := CombatState.new(Grid.new(15, 9), [shooter, bystander])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 0), Vector2(1, 0), MISS_POINT, 5.0, 0.0, 0.0, null
	)

	var miss: LogEvent = sink.events_of_kind(&"miss")[0]
	assert_almost_eq(miss.data.get("end_x") as float, 15.0, 0.01)


## taskblock-22 Pass D: "the player reads the path" — a logged impact
## event must carry its own real muzzle/landing point, the same flat
## cell-space coords the miss event above already established, so the
## view can draw every tracer segment from the log directly.
func test_a_hit_logs_its_own_origin_and_hit_point() -> void:
	var shooter := _make_unit(Vector2i(0, 0))
	var target := _make_unit(Vector2i(3, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 0), Vector2(1, 0), Vector2(0, 0), 5.0, 0.0, 0.0, null
	)

	var impact: LogEvent = sink.events_of_kind(&"impact")[0]
	assert_almost_eq(impact.data.get("origin_x") as float, 0.0, 0.01, "the shooter's own muzzle")
	assert_almost_eq(impact.data.get("origin_y") as float, 0.0, 0.01)
	# The struck box's own real front surface, short of the target's cell
	# center at x=3 — never re-derived from the target's own cell directly.
	assert_gt(impact.data.get("hit_x") as float, 0.0, "landed somewhere downrange of the shooter")
	assert_lt(impact.data.get("hit_x") as float, 3.0, "short of the target's own cell center")
	assert_almost_eq(impact.data.get("hit_y") as float, 0.0, 0.01)
	assert_false(
		impact.data.has("deflect_end_x"), "a real penetrate never carries a deflect endpoint"
	)


## taskblock-26 Pass A1: "the bounced secondary ray is computed, logged,
## never drawn." A DEFLECT must always carry its own reflected void
## endpoint (the same convention a total miss's own endpoint already
## uses) — regardless of whether a real ricochet continuation happens to
## follow it, since a ricochet that finds nothing to hit produces no
## further event of its own.
func test_a_deflect_logs_its_own_reflected_void_endpoint() -> void:
	var shooter := _make_unit(Vector2i(2, 0))
	var cover := Part.new()
	cover.id = &"cover"
	cover.material = &"steel"
	cover.hp = 20
	cover.max_hp = 20
	cover.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var grid := Grid.new(6, 6)
	grid.blockers[Vector2i(2, 2)] = cover
	var state := CombatState.new(grid, [shooter])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	# incidence ~37 deg: clears steel's default 30-degree deflect
	# threshold — the exact fixture test_damage_resolver.gd's own DEFLECT
	# tests already use and prove.
	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(2, 0), Vector2(3, 4), Vector2(2.0, 0.5), 3.0, 0.0, 0.0, null
	)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_gt(impacts.size(), 0, "sanity: the fixture must actually hit something")
	var deflect: LogEvent = impacts[0]
	assert_eq(
		deflect.data.get("outcome"), Enums.Outcome.DEFLECT, "sanity: the fixture must deflect"
	)
	assert_true(deflect.data.has("deflect_end_x"))
	assert_true(deflect.data.has("deflect_end_y"))
	assert_true(deflect.data.has("deflect_end_height"))


## taskblock-28 Pass C: BR27.02 (the backward-burst report) was
## undiagnosable from `out/combat.log` — the geometry was already in
## `data`, but `LogEvent._to_string()` renders only `text`, which never
## showed it. An impact's own `text` must now carry the same real
## origin/hit numbers `data` does, not a re-derivation — read the SAME
## `LogEvent` back, never a second computation.
func test_a_hits_own_text_carries_its_real_origin_and_hit_geometry() -> void:
	var shooter := _make_unit(Vector2i(0, 0))
	var target := _make_unit(Vector2i(3, 0), 1)
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 0), Vector2(1, 0), Vector2(0, 0), 5.0, 0.0, 0.0, null
	)

	var impact: LogEvent = sink.events_of_kind(&"impact")[0]
	var expected_origin := (
		"(%.2f, %.2f)@%.2f"
		% [
			impact.data.get("origin_x"),
			impact.data.get("origin_y"),
			impact.data.get("origin_height")
		]
	)
	var expected_hit := (
		"(%.2f, %.2f)@%.2f"
		% [impact.data.get("hit_x"), impact.data.get("hit_y"), impact.data.get("hit_height")]
	)
	assert_true(
		impact.text.contains(expected_origin), "text must contain the SAME origin data carries"
	)
	assert_true(
		impact.text.contains(expected_hit), "text must contain the SAME hit point data carries"
	)


## A miss's own text must carry its real origin, same posture as a hit's.
func test_a_miss_own_text_carries_its_real_origin_and_end_geometry() -> void:
	var shooter := _make_unit(Vector2i(0, 0))
	var bystander := _make_unit(Vector2i(10, 0), 1)
	var state := CombatState.new(Grid.new(20, 20), [shooter, bystander])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(0, 0), Vector2(1, 0), MISS_POINT, 5.0, 0.0, 0.0, null
	)

	var miss: LogEvent = sink.events_of_kind(&"miss")[0]
	var expected_end := (
		"(%.2f, %.2f)@%.2f"
		% [miss.data.get("end_x"), miss.data.get("end_y"), miss.data.get("end_height")]
	)
	assert_true(
		miss.text.contains(expected_end), "text must contain the SAME endpoint data carries"
	)


## A shot fired toward -x must never log the same hit geometry a shot
## fired toward +x would — the BR27.02 class (a burst reading as though
## half of it travelled backward) made log-visible: since the prior test
## proves `text` mirrors `data` verbatim, a real directional difference in
## `data` (this test) is a real directional difference readable in
## `out/combat.log` text, not only in live playback.
func test_a_backward_and_forward_shot_are_distinguishable_by_their_own_logged_geometry() -> void:
	var shooter := _make_unit(Vector2i(5, 0))
	var forward_target := _make_unit(Vector2i(8, 0), 1)
	var backward_target := _make_unit(Vector2i(2, 0), 1)

	var forward_state := CombatState.new(Grid.new(20, 20), [shooter, forward_target])
	var forward_sink := MemorySink.new()
	forward_state.combat_log.add_sink(forward_sink)
	ShotResolution.resolve_and_log_point(
		forward_state, shooter, Vector2(5, 0), Vector2(1, 0), Vector2(0, 0), 5.0, 0.0, 0.0, null
	)
	var forward_hit_x: float = (
		(forward_sink.events_of_kind(&"impact")[0] as LogEvent).data.get("hit_x") as float
	)

	var backward_state := CombatState.new(Grid.new(20, 20), [shooter, backward_target])
	var backward_sink := MemorySink.new()
	backward_state.combat_log.add_sink(backward_sink)
	ShotResolution.resolve_and_log_point(
		backward_state, shooter, Vector2(5, 0), Vector2(-1, 0), Vector2(0, 0), 5.0, 0.0, 0.0, null
	)
	var backward_hit_x: float = (
		(backward_sink.events_of_kind(&"impact")[0] as LogEvent).data.get("hit_x") as float
	)

	assert_gt(forward_hit_x, 5.0, "a forward shot must land downrange of the shooter's own muzzle")
	assert_lt(backward_hit_x, 5.0, "a backward shot must land the OTHER way — visible, not guessed")


## docs/00 determinism: the exact same call, twice, must log the exact
## same geometry both times.
func test_the_same_shot_logs_identical_geometry_every_time() -> void:
	var runs: Array[Dictionary] = []
	for _i in range(2):
		var shooter := _make_unit(Vector2i(0, 0))
		var target := _make_unit(Vector2i(3, 0), 1)
		var state := CombatState.new(Grid.new(10, 10), [shooter, target])
		var sink := MemorySink.new()
		state.combat_log.add_sink(sink)
		ShotResolution.resolve_and_log_point(
			state, shooter, Vector2(0, 0), Vector2(1, 0), Vector2(0, 0), 5.0, 0.0, 0.0, null
		)
		var impact: LogEvent = sink.events_of_kind(&"impact")[0]
		runs.append(impact.data)

	assert_eq(runs[0], runs[1])
