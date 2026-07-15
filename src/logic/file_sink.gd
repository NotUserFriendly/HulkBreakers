class_name FileSink
extends LogSink

## Appends to a real file so a human can `tail -f` it during a run.

var _file: FileAccess


func _init(path: String = "res://out/combat.log") -> void:
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
