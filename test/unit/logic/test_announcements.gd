extends GutTest

## taskblock-57 Pass E — **one emit, two views.**
##
## *"Anything tagged as an announcement lands in the combat log **and** is shown at the announcement
## position. **Sequential, not double-rendered** — it can never appear in one and not the other,
## which is exactly what two calls would eventually produce."*
##
## The load-bearing assertion in this file is therefore a *negative* one: there is no announce path.
## A tagged event goes through `CombatLog.emit` like everything else, and both surfaces are sinks on
## it — so "in one and not the other" is not a bug to test for, it is a state the design cannot
## reach. What is tested is that both sinks really do see the same single emit.


func _log() -> Dictionary:
	var log := CombatLog.new()
	var memory := MemorySink.new()
	var feed := AnnouncementFeed.new()
	log.add_sink(memory)
	log.add_sink(feed)
	return {"log": log, "memory": memory, "feed": feed}


func _event(text: String, priority: StringName = &"") -> LogEvent:
	var data: Dictionary = {}
	if priority != &"":
		Announcement.tag(data, priority)
	return LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"unit_down", data, text)


# ---------------------------------------------------------------- one emit, two views


## **THE STATED ACCEPTANCE**: *"a tagged event appears in both surfaces from one emit."*
func test_one_emit_puts_a_tagged_event_in_both_the_log_and_the_position() -> void:
	var built: Dictionary = _log()

	built.log.emit(_event("unit 3 is down", Announcement.ALERT))

	assert_eq(built.memory.events.size(), 1, "the log has it")
	assert_eq(built.feed.active().size(), 1, "and so does the announcement position")
	assert_eq(
		built.memory.events[0],
		built.feed.active()[0],
		"the SAME event object -- one emit, two views, not two messages"
	)


## An untagged event is the ordinary case and must not reach the position at all. `wants()` is what
## declines it, so the feed never holds the whole battle and filters on read.
func test_an_untagged_event_reaches_the_log_only() -> void:
	var built: Dictionary = _log()

	built.log.emit(_event("unit 3 took 4 damage"))

	assert_eq(built.memory.events.size(), 1, "the log takes everything, as it always has")
	assert_true(built.feed.active().is_empty(), "the position takes only what was tagged for it")


# ---------------------------------------------------------------- the lifetime belongs to the view


## **THE STATED ACCEPTANCE**: *"an expired announcement leaves the position and remains in the
## log."*
##
## This is the whole of what the position adds — *"the only thing the log lacks is a lifetime, and
## it belongs to the view"* — so it is asserted on both sides of the same emit.
func test_an_expired_announcement_leaves_the_position_and_stays_in_the_log() -> void:
	var built: Dictionary = _log()
	built.log.emit(_event("unit 3 is down", Announcement.NOTICE))
	var lifetime: float = float(Announcement.priority(Announcement.NOTICE)["seconds"])

	built.feed.tick(lifetime * 0.5)
	assert_eq(built.feed.active().size(), 1, "half way through, it is still showing")

	built.feed.tick(lifetime * 0.5 + 0.01)

	assert_true(built.feed.active().is_empty(), "past its lifetime, it has left the position")
	assert_eq(
		built.memory.events.size(), 1, "and the log still has it -- the log keeps them forever"
	)


## The feed reports when it needs redrawing, and **arrivals count as well as expiries.** The first
## version returned true only on expiry, so a new announcement did not draw until an unrelated one
## aged out — a bug that would have read as "announcements are late".
func test_the_feed_reports_a_redraw_for_an_arrival_not_only_an_expiry() -> void:
	var built: Dictionary = _log()

	built.log.emit(_event("something happened", Announcement.NOTICE))
	assert_true(built.feed.tick(0.0), "an arrival needs a redraw even with no time passing")
	assert_false(built.feed.tick(0.0), "and nothing further, once it has been drawn")


func test_a_new_bout_starts_with_a_clear_position() -> void:
	var built: Dictionary = _log()
	built.log.emit(_event("last bout's news", Announcement.CRITICAL))

	built.feed.clear()

	assert_true(built.feed.active().is_empty(), "the last bout's notices do not carry over")


# ---------------------------------------------------------------- priority is a data table


## **THE STATED ACCEPTANCE**: *"priority changes duration and colour."*
func test_priority_changes_both_duration_and_colour() -> void:
	var notice: LogEvent = _event("a", Announcement.NOTICE)
	var critical: LogEvent = _event("b", Announcement.CRITICAL)

	gut.p(
		(
			"notice %.1fs, critical %.1fs"
			% [Announcement.seconds_for(notice), Announcement.seconds_for(critical)]
		)
	)
	assert_gt(
		Announcement.seconds_for(critical),
		Announcement.seconds_for(notice),
		"a critical announcement stays longer"
	)
	assert_ne(
		Announcement.color_for(critical), Announcement.color_for(notice), "and reads differently"
	)


## **THE STATED ACCEPTANCE**: *"the `sound` field round-trips unread."*
##
## *"There is no audio system — the priority carries a `sound` field and nothing consumes it,
## exactly as `encounter_types` is authored and unread. Do not build audio here."*
##
## So this asserts both halves: the field is really there, and **nothing in `src/` reads it**. The
## second half is the one that matters — a field nobody reads is exactly the kind of thing a later
## pass assumes is already wired.
func test_the_sound_field_is_authored_and_nothing_consumes_it() -> void:
	for id: StringName in Announcement.table():
		var row: Dictionary = Announcement.table()[id]
		assert_true(row.has("sound"), "%s carries a sound" % id)
		assert_ne(StringName(row["sound"]), &"", "%s's sound is authored, not blank" % id)

	var readers: Array[String] = []
	for path: String in _gd_files("res://src"):
		var text: String = FileAccess.get_file_as_string(path)
		if text.contains("sound_for(") and not path.ends_with("announcement.gd"):
			readers.append(path)
	gut.p("sound readers: %s" % ("none" if readers.is_empty() else ", ".join(readers)))
	assert_eq(
		readers,
		[] as Array[String],
		"something consumes the sound field -- taskblock-57 says not to build audio here"
	)


## An unknown priority is shown rather than dropped: someone wanted the player to see it, and
## silence is a worse failure than a plain line.
func test_an_unknown_priority_still_shows_with_the_default_treatment() -> void:
	var odd: LogEvent = _event("from a later content pack", &"a_priority_nobody_authored")

	assert_true(Announcement.tagged(odd), "it is still tagged")
	assert_eq(
		Announcement.seconds_for(odd),
		float(Announcement.priority(Announcement.NOTICE)["seconds"]),
		"and falls back to the default treatment rather than vanishing"
	)


## The tag lives in `data`, not in `kind`. An announced `unit_down` is still a `unit_down` —
## anything folding or filtering on kind must not see a different event because someone shouted it.
func test_tagging_does_not_change_what_kind_of_event_it_is() -> void:
	var plain: LogEvent = _event("x")
	var shouted: LogEvent = _event("x", Announcement.ALERT)

	assert_eq(shouted.kind, plain.kind, "the kind is untouched by the tag")
	assert_eq(Announcement.priority_of(shouted), Announcement.ALERT)
	assert_eq(Announcement.priority_of(plain), &"", "and an untagged event has no priority")


func _gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var path: String = "%s/%s" % [root, name]
		if dir.current_is_dir():
			found.append_array(_gd_files(path))
		elif name.ends_with(".gd"):
			found.append(path)
		name = dir.get_next()
	dir.list_dir_end()
	return found
