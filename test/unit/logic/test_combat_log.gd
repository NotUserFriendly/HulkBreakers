extends GutTest


func test_memory_sink_collects_events() -> void:
	var stream := CombatLog.new()
	var sink := MemorySink.new()
	stream.add_sink(sink)

	var event := LogEvent.new(
		1, Enums.Phase.RESOLUTION, 3, &"shot_fired", {"target": 7}, "unit 3 fired at unit 7"
	)
	stream.emit(event)

	assert_eq(sink.events.size(), 1)
	assert_eq(sink.events[0], event)


func test_events_of_kind_filters() -> void:
	var sink := MemorySink.new()
	sink.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 1, &"shot_fired"))
	sink.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 1, &"deflection"))
	sink.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 1, &"shot_fired"))

	var shots: Array[LogEvent] = sink.events_of_kind(&"shot_fired")
	assert_eq(shots.size(), 2)


func test_log_dispatches_to_multiple_sinks() -> void:
	var stream := CombatLog.new()
	var sink_a := MemorySink.new()
	var sink_b := MemorySink.new()
	stream.add_sink(sink_a)
	stream.add_sink(sink_b)

	stream.emit(LogEvent.new(1, Enums.Phase.TACTICS, 0, &"queued"))

	assert_eq(sink_a.events.size(), 1)
	assert_eq(sink_b.events.size(), 1)


func test_remove_sink_stops_further_dispatch_to_it() -> void:
	var stream := CombatLog.new()
	var temp := MemorySink.new()
	stream.add_sink(temp)
	stream.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"turn_start"))

	stream.remove_sink(temp)
	stream.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"turn_end"))

	assert_eq(temp.events.size(), 1, "events emitted after removal must not reach it")


func test_remove_sink_is_a_no_op_for_a_sink_never_added() -> void:
	var stream := CombatLog.new()
	stream.remove_sink(MemorySink.new())  # must not error
	stream.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"turn_start"))
	pass_test("remove_sink on an unknown sink did not error, and the log still dispatches")


## turn/phase/unit are deliberately NOT echoed per line anymore — a
## scrolling repeat of "what turn/unit this is" on every single line is
## exactly the noise this format change removes; each unit's own turn
## already announces itself once via its own turn_start line
## (CombatState._start_turn). `kind` is the one label still worth
## repeating, since unlike turn/unit it actually varies line to line.
func test_log_event_to_string_is_readable() -> void:
	var event := LogEvent.new(
		2, Enums.Phase.RESOLUTION, 5, &"penetration", {}, "round penetrates plate"
	)
	var text: String = event._to_string()
	assert_false(text.contains("T2"), "the turn number must not be echoed per line")
	assert_false(text.contains("unit 5"), "the acting unit must not be echoed per line")
	assert_true(text.contains("penetration"))
	assert_true(text.contains("round penetrates plate"))


func test_file_sink_writes_and_appends_line() -> void:
	var path := "user://tmp_test_combat_log.log"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var sink := FileSink.new(path)
	sink.emit(LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"shot_fired", {}, "test line"))
	sink.close()

	assert_true(FileAccess.file_exists(path))
	var contents: String = FileAccess.get_file_as_string(path)
	assert_true(contents.contains("test line"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Phase 0 acceptance: "a FileSink log appears at out/combat.log" — a real,
## reviewable artifact of running the suite, left behind on purpose (unlike
## the hermetic test above).
func test_file_sink_default_path_produces_out_combat_log() -> void:
	var sink := FileSink.new()
	sink.emit(
		LogEvent.new(0, Enums.Phase.RESOLUTION, 0, &"suite_run", {}, "run_tests.sh wrote this")
	)
	sink.close()

	assert_true(FileAccess.file_exists("res://out/combat.log"))


# --- taskblock-61 Pass E5 (BR51.16): retained history and the replay floor ----------------


## A sink that asks for replay, for testing the floor without a whole overlay in the way.
class ReplayingSink:
	extends MemorySink

	func wants_replay() -> bool:
		return true


## **The first replay-wanting sink sets the floor and receives nothing.** That is what keeps a
## freshly-mounted panel from being handed events emitted before any panel existed — `CombatState`
## logs its own construction and `BattleScene.load_battle` attaches the panel afterwards, on
## purpose, so those events were never the panel's to show.
func test_the_first_replaying_sink_receives_no_history() -> void:
	var stream := CombatLog.new()
	for i in range(3):
		stream.emit(LogEvent.new(0, Enums.Phase.RESOLUTION, -1, &"diagnostic", {}, "before %d" % i))

	var first := ReplayingSink.new()
	stream.add_sink(first)

	assert_eq(
		first.events.size(), 0, "it saw nothing before it existed and must keep seeing nothing"
	)


## **A later one is brought level with its predecessor** — the overlay-swap case, which is the whole
## defect: the panel is destroyed and rebuilt while the log carries on.
func test_a_later_replaying_sink_receives_everything_since_the_floor() -> void:
	var stream := CombatLog.new()
	stream.emit(LogEvent.new(0, Enums.Phase.RESOLUTION, -1, &"diagnostic", {}, "before the panel"))
	var first := ReplayingSink.new()
	stream.add_sink(first)
	for i in range(4):
		stream.emit(LogEvent.new(0, Enums.Phase.RESOLUTION, -1, &"diagnostic", {}, "live %d" % i))
	stream.remove_sink(first)

	var rebuilt := ReplayingSink.new()
	stream.add_sink(rebuilt)

	var texts: Array[String] = []
	for event: LogEvent in rebuilt.events:
		texts.append(event.text)
	gut.p("replayed: %s" % str(texts))
	assert_eq(rebuilt.events.size(), 4, "exactly what the first sink saw, no more and no less")
	assert_false(texts.has("before the panel"), "and nothing from before the first panel attached")


## **Replay is opt-in, and the default is what protects every other sink.** A plain `MemorySink` —
## the shape used to capture one turn's events for playback — must not be handed the whole bout.
func test_an_ordinary_sink_is_never_replayed_into() -> void:
	var stream := CombatLog.new()
	stream.add_sink(ReplayingSink.new())
	for i in range(3):
		stream.emit(
			LogEvent.new(0, Enums.Phase.RESOLUTION, -1, &"diagnostic", {}, "earlier %d" % i)
		)

	var plain := MemorySink.new()
	stream.add_sink(plain)

	assert_eq(plain.events.size(), 0, "a default sink receives only what is emitted after it joins")


## **The floor is an index into a trimming array, so it has to move with the trim.** Left alone it
## drifts forward through the surviving history and a re-attached panel silently loses its oldest
## rows — a defect that only appears in a bout long enough to trim, which is the worst kind to ship.
func test_the_replay_floor_survives_a_history_trim() -> void:
	var stream := CombatLog.new()
	var first := ReplayingSink.new()
	stream.add_sink(first)
	# Past twice the bound, which is where `_remember` slices.
	var emitted: int = CombatLog.MAX_HISTORY * 2 + 10
	for i in range(emitted):
		stream.emit(LogEvent.new(0, Enums.Phase.RESOLUTION, -1, &"diagnostic", {}, "e%d" % i))
	stream.remove_sink(first)

	var rebuilt := ReplayingSink.new()
	stream.add_sink(rebuilt)

	gut.p(
		(
			"%d emitted, %d retained, %d replayed"
			% [emitted, stream.history().size(), rebuilt.events.size()]
		)
	)
	assert_eq(
		rebuilt.events.size(),
		stream.history().size(),
		"the floor trimmed to 0 with the history, so the whole surviving log replays"
	)
	assert_lte(stream.history().size(), CombatLog.MAX_HISTORY * 2, "and the history stayed bounded")
