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
## **A new bout appends** (supervisor's call, 2026-08-02): *"New bout should append.
## That may not stay true, but it's the better option now."* So a session's log is
## the whole session, not just its last bout.
##
## Two defences, because they answer different halves:
## - opening **without truncating**, which is what makes appending true at all;
## - `seek_end()` **before every write**, which is what keeps two live handles
##   interleaving whole lines instead of overwriting each other at stale offsets.
##   Opening at the end alone would not survive a second sink, since each handle
##   carries its own position.

## docs/09 taskblock03 Pass B: exposed so a caller (BattleScene's own "log:
## <path>" line, Pass J's controls overlay) can tell the human where their
## session actually went, without hand-duplicating the default elsewhere.
var path: String

var _file: FileAccess


func _init(p_path: String = "res://out/combat.log") -> void:
	path = p_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
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
