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
