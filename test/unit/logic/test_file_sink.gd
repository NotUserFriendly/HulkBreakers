extends GutTest

## docs/09 taskblock03 Pass B: "one stream, many sinks — never two
## streams." A UISink and a FileSink registered on the same CombatLog must
## receive event-for-event identical streams; nothing about wiring one
## changes what the other gets.

const TEST_PATH := "user://test_file_sink.log"


func _event(kind: StringName, text: String) -> LogEvent:
	return LogEvent.new(0, Enums.Phase.RESOLUTION, 1, kind, {}, text)


func _file_line_count(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	var lines: PackedStringArray = file.get_as_text().split("\n", false)
	file.close()
	return lines.size()


func _file_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return bytes


func _nul_count(bytes: PackedByteArray) -> int:
	var count := 0
	for byte: int in bytes:
		if byte == 0:
			count += 1
	return count


func before_each() -> void:
	FileSink.reset_session()
	_clear_archive()


func after_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	FileSink.reset_session()
	_clear_archive()


## Only ever removes archives of THIS test's own log — never anything belonging to
## a real session, which is why it matches on the test file's basename.
func _clear_archive() -> void:
	var dir := DirAccess.open(FileSink.ARCHIVE_DIR)
	if dir == null:
		return
	for name: String in dir.get_files():
		if name.begins_with(TEST_PATH.get_file().get_basename()):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path("%s/%s" % [FileSink.ARCHIVE_DIR, name])
			)


func _archived_files() -> PackedStringArray:
	var dir := DirAccess.open(FileSink.ARCHIVE_DIR)
	if dir == null:
		return PackedStringArray()
	var mine := PackedStringArray()
	for name: String in dir.get_files():
		if name.begins_with(TEST_PATH.get_file().get_basename()):
			mine.append(name)
	return mine


func test_uisink_and_filesink_receive_an_equal_line_count_event_for_event() -> void:
	var log := CombatLog.new()
	var ui_sink := UISink.new()
	var file_sink := FileSink.new(TEST_PATH)
	log.add_sink(ui_sink)
	log.add_sink(file_sink)

	log.emit(_event(&"move", "unit 1 moved"))
	log.emit(_event(&"impact", "PENETRATE on torso"))
	log.emit(_event(&"turn_end", "unit 1 ended turn"))
	file_sink.close()

	assert_eq(ui_sink.lines.size(), 3)
	assert_eq(_file_line_count(TEST_PATH), 3)
	assert_eq(
		ui_sink.lines.size(), _file_line_count(TEST_PATH), "event for event, not just a count"
	)


func test_removing_one_sink_does_not_change_what_the_other_receives() -> void:
	var log := CombatLog.new()
	var ui_sink := UISink.new()
	var file_sink := FileSink.new(TEST_PATH)
	log.add_sink(ui_sink)
	log.add_sink(file_sink)

	log.emit(_event(&"move", "first"))
	log.remove_sink(file_sink)
	log.emit(_event(&"move", "second"))
	file_sink.close()

	assert_eq(
		ui_sink.lines.size(), 2, "the UISink kept receiving events after FileSink was removed"
	)
	assert_eq(_file_line_count(TEST_PATH), 1, "the FileSink stopped exactly where it was removed")


func test_removing_the_other_sink_does_not_change_what_filesink_receives() -> void:
	var log := CombatLog.new()
	var ui_sink := UISink.new()
	var file_sink := FileSink.new(TEST_PATH)
	log.add_sink(ui_sink)
	log.add_sink(file_sink)

	log.emit(_event(&"move", "first"))
	log.remove_sink(ui_sink)
	log.emit(_event(&"move", "second"))
	file_sink.close()

	assert_eq(ui_sink.lines.size(), 1, "the UISink stopped exactly where it was removed")
	assert_eq(_file_line_count(TEST_PATH), 2, "the FileSink kept receiving events regardless")


## `BR52.04`: **a second sink on the same path must not truncate the first's log,
## and the two must not corrupt it between them.**
##
## Measured on a real session log before the fix: **49 403 of 138 436 bytes were
## NUL**, one contiguous run. `_init` opened with `FileAccess.WRITE`, which
## truncates, so a second sink reset the file to zero while the first still held a
## handle tens of kilobytes in — its next write landed at that stale offset and the
## kernel zero-filled the gap.
##
## **A NUL byte is the assertion because of what it costs**: `file` then classifies
## the log as `data` and `grep` silently declines to match it, while `tail` still
## renders fine. The log reads as healthy and returns nothing to every tool.
func test_a_second_sink_on_one_path_neither_truncates_nor_corrupts_the_log() -> void:
	var first := FileSink.new(TEST_PATH)
	first.emit(_event(&"move", "from the first sink"))

	# A new bout attaching its own sink while the old one is still open.
	var second := FileSink.new(TEST_PATH)
	second.emit(_event(&"move", "from the second sink"))
	first.emit(_event(&"move", "the first sink is still alive"))

	first.close()
	second.close()

	var bytes: PackedByteArray = _file_bytes(TEST_PATH)
	assert_eq(_nul_count(bytes), 0, "no NUL bytes — a log grep refuses to read is not a log")

	var text: String = bytes.get_string_from_utf8()
	assert_string_contains(text, "from the first sink")
	assert_string_contains(text, "from the second sink")
	assert_string_contains(text, "the first sink is still alive")
	assert_eq(_file_line_count(TEST_PATH), 3, "every line survives, none overwritten")


## The supervisor's call, 2026-08-02: **a new bout appends.** A session's log is the
## whole session rather than only its last bout. Flagged as a decision that may not
## stay true — *"That may not stay true, but it's the better option now."*
func test_a_new_sink_appends_to_an_existing_log_rather_than_replacing_it() -> void:
	var earlier := FileSink.new(TEST_PATH)
	earlier.emit(_event(&"turn_start", "an earlier bout"))
	earlier.close()

	var later := FileSink.new(TEST_PATH)
	later.emit(_event(&"turn_start", "a later bout"))
	later.close()

	var text: String = _file_bytes(TEST_PATH).get_string_from_utf8()
	assert_string_contains(text, "an earlier bout")
	assert_string_contains(text, "a later bout")
	assert_eq(_file_line_count(TEST_PATH), 2, "the earlier bout is still there")
	assert_lt(
		text.find("an earlier bout"),
		text.find("a later bout"),
		"and it is still first — appended, not prepended or interleaved"
	)


## **A new session rotates; a new bout does not.** The supervisor's two rules pull
## in opposite directions and both have to hold: several bouts in one run share one
## log, and the next run starts clean rather than piling on forever.
func test_a_new_session_archives_the_previous_log_and_starts_clean() -> void:
	var earlier := FileSink.new(TEST_PATH)
	earlier.emit(_event(&"turn_start", "an earlier session"))
	earlier.close()

	# A new process would forget which paths it had rotated; this is that.
	FileSink.reset_session()
	var later := FileSink.new(TEST_PATH)
	later.emit(_event(&"turn_start", "a later session"))
	later.close()

	var live: String = _file_bytes(TEST_PATH).get_string_from_utf8()
	assert_string_contains(live, "a later session")
	assert_false(
		live.contains("an earlier session"), "the live log is this session's, not a running total"
	)

	var archived: PackedStringArray = _archived_files()
	assert_eq(archived.size(), 1, "and the earlier session was kept, not discarded")
	var kept := FileAccess.open("%s/%s" % [FileSink.ARCHIVE_DIR, archived[0]], FileAccess.READ)
	var kept_text: String = kept.get_as_text()
	kept.close()
	assert_string_contains(kept_text, "an earlier session")
	print("  archived as %s" % archived[0])


## The other half, and the one a naive "rotate on open" would break: a second sink
## **within** one session still appends. `BR52.04` is the reason this matters —
## that is exactly when two sinks share a path.
func test_a_second_sink_within_one_session_still_appends_and_does_not_rotate() -> void:
	var first := FileSink.new(TEST_PATH)
	first.emit(_event(&"move", "from the first sink"))
	var second := FileSink.new(TEST_PATH)
	second.emit(_event(&"move", "from the second sink"))
	first.close()
	second.close()

	var live: String = _file_bytes(TEST_PATH).get_string_from_utf8()
	assert_string_contains(live, "from the first sink")
	assert_string_contains(live, "from the second sink")
	assert_eq(_archived_files().size(), 0, "a second sink is not a second session")


## An empty log is nothing to keep. Without this a run that opened a log and wrote
## nothing would leave a zero-byte file in the archive every time.
func test_an_empty_previous_log_is_not_archived() -> void:
	FileSink.new(TEST_PATH).close()
	FileSink.reset_session()
	FileSink.new(TEST_PATH).close()
	assert_eq(_archived_files().size(), 0, "nothing was written, so there is nothing to keep")
