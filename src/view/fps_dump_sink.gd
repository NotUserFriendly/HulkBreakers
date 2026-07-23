class_name FpsDumpSink
extends LogSink

## tb35 Pass A1: "the reason BR26.02 has survived three passes is that CC
## cannot see a framerate, so every fix has been reasoned rather than
## measured." Watches the combat log for `&"turn_start"` and dumps
## `Engine.get_frames_per_second()` back into the SAME log 200ms later —
## past the turn-boundary hitch itself, into the settled steady state —
## so "the game is slow" becomes a greppable number in `out/combat.log`
## instead of a felt impression. `_host` only supplies `get_tree()`; this
## class does no logic of its own worth testing headless (there is no
## real framerate without a running SceneTree) — the aim-entry counterpart
## lives directly in `TacticsController._enter_aim_mode()` instead of
## here, since that trigger isn't a combat-log event at all.

var _host: Node
var _combat_log: CombatLog


func _init(host: Node, combat_log: CombatLog) -> void:
	_host = host
	_combat_log = combat_log


func emit(event: LogEvent) -> void:
	if event.kind != &"turn_start":
		return
	_dump_after_delay(event.turn, event.unit_id)


func _dump_after_delay(turn: int, unit_id: int) -> void:
	await _host.get_tree().create_timer(0.2).timeout
	if not is_instance_valid(_host) or not _host.is_inside_tree():
		return
	var fps: float = Engine.get_frames_per_second()
	_combat_log.emit(
		LogEvent.new(
			turn,
			Enums.Phase.RESOLUTION,
			unit_id,
			&"fps_dump",
			{"context": "turn", "fps": fps},
			"Turn FPS (200ms after turn start): %.1f" % fps
		)
	)
