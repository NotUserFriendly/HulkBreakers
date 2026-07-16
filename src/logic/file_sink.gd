class_name FileSink
extends LogSink

## Appends to a real file so a human can `tail -f` it during a run.

## docs/09 taskblock03 Pass B: exposed so a caller (BattleScene's own "log:
## <path>" line, Pass J's controls overlay) can tell the human where their
## session actually went, without hand-duplicating the default elsewhere.
var path: String

var _file: FileAccess


func _init(p_path: String = "res://out/combat.log") -> void:
	path = p_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)


func emit(event: LogEvent) -> void:
	if _file == null:
		return
	_file.store_line(event._to_string())
	_file.flush()


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
