class_name FileSink
extends LogSink

## Appends to a real file so a human can `tail -f` it during a run.
##
## `BR52.04`: **it now does what that line always said it did.** `_init` opened with
## `FileAccess.WRITE`, which **truncates**, and the mismatch between the comment and
## the code was the bug. Two `FileSink`s alive on one path — a new bout attaching
## one while the old is still open — meant the second truncated the file to zero
## while the first still held a handle positioned tens of kilobytes in; the first's
## next write landed at that stale offset and the kernel zero-filled the gap.
##
## **Measured on a real session log before the fix: 49 403 of 138 436 bytes were
## NUL**, one contiguous run starting at byte 1073. That is worse than it sounds,
## because `file` classifies such a log as `data` and **`grep` then silently
## declines to match it** while `tail` still renders fine — so the log reads as
## healthy to a human skimming it and returns nothing to every tool CC uses. The
## combat log is this project's monitoring channel for both of us; a corrupt one is
## a troubleshooting obstacle rather than a cosmetic fault.
##
## **A new bout appends; a new SESSION rotates** (supervisor's call, 2026-08-02).
## A bout is not a session: several bouts in one run share one log, and the *next
## run* starts a clean one rather than piling on forever. The previous session's
## file is moved into `out/logs/` under its own timestamp before the new one opens,
## so old sessions are kept and separated without the live path moving.
##
## **The live path deliberately does not change.** `out/combat.log` stays where
## `tail -f`, `grep`, and the startup "log: <path>" line already point; naming the
## *live* file per session would break every one of those for no gain, since there
## is only ever one live session. It is the archive that needs distinct names.
##
## Two defences, because they answer different halves:
## - opening **without truncating**, which is what makes appending true at all;
## - `seek_end()` **before every write**, which is what keeps two live handles
##   interleaving whole lines instead of overwriting each other at stale offsets.
##   Opening at the end alone would not survive a second sink, since each handle
##   carries its own position.

## Where a rotated session's log is kept. A subfolder rather than a sibling, so
## `out/` keeps exactly one obvious file in it and the history is one directory
## listing away.
const ARCHIVE_DIR := "res://out/logs"

## Which paths this process has already rotated. **Per path, not one global flag**,
## because a test writing to `user://…` must not consume the rotation that belongs
## to the real log — and because rotating on every construction would defeat the
## append rule the moment a second sink attached mid-session.
static var _rotated: Dictionary = {}

## docs/09 taskblock03 Pass B: exposed so a caller (BattleScene's own "log:
## <path>" line, Pass J's controls overlay) can tell the human where their
## session actually went, without hand-duplicating the default elsewhere.
var path: String

var _file: FileAccess


## Test seam: forget which paths have been rotated, so one process can act out more
## than one session. Never called by the game, which genuinely has one session per
## run — that is the whole definition being relied on.
static func reset_session() -> void:
	_rotated.clear()


func _init(p_path: String = "res://out/combat.log") -> void:
	path = p_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if not _rotated.has(path):
		_rotated[path] = true
		_archive_previous_session(path)
	# `READ_WRITE` opens without truncating but fails outright if the file is not
	# there yet, so a first run falls back to `WRITE` purely to create it.
	_file = FileAccess.open(path, FileAccess.READ_WRITE)
	if _file == null:
		_file = FileAccess.open(path, FileAccess.WRITE)
	if _file != null:
		_file.seek_end()


func emit(event: LogEvent) -> void:
	if _file == null:
		return
	# Re-seeked per line, not once at open — see this class's own doc comment.
	_file.seek_end()
	_file.store_line(event._to_string())
	_file.flush()


func close() -> void:
	if _file != null:
		_file.close()
		_file = null


## Moves a previous session's log into `ARCHIVE_DIR`, named for **when that session
## ran** rather than when it was rotated — the file's own modification time, so an
## archived name describes its contents.
##
## A missing or empty file is nothing to keep and is left alone; a name collision
## keeps the existing archive rather than overwriting it, because losing an old
## log to a same-second rename would be exactly the data loss this rotation exists
## to prevent.
static func _archive_previous_session(live_path: String) -> void:
	if not FileAccess.file_exists(live_path):
		return
	var probe := FileAccess.open(live_path, FileAccess.READ)
	if probe == null:
		return
	var size: int = probe.get_length()
	probe.close()
	if size == 0:
		return

	DirAccess.make_dir_recursive_absolute(ARCHIVE_DIR)
	var stamp: String = _stamp_for(FileAccess.get_modified_time(live_path))
	var base: String = live_path.get_file().get_basename()
	var extension: String = live_path.get_extension()
	var target: String = "%s/%s-%s.%s" % [ARCHIVE_DIR, base, stamp, extension]
	var suffix := 1
	while FileAccess.file_exists(target):
		target = "%s/%s-%s-%d.%s" % [ARCHIVE_DIR, base, stamp, suffix, extension]
		suffix += 1
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(live_path), ProjectSettings.globalize_path(target)
	)


## `YYYYMMDD-HHMMSS`, sortable so a directory listing is already in session order.
static func _stamp_for(unix_time: int) -> String:
	var at: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return (
		"%04d%02d%02d-%02d%02d%02d"
		% [at["year"], at["month"], at["day"], at["hour"], at["minute"], at["second"]]
	)
