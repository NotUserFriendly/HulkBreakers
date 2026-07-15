class_name StdoutSink
extends LogSink

## Prints every event so it lands in the (headless) test log CC reads.


func emit(event: LogEvent) -> void:
	print(event._to_string())
