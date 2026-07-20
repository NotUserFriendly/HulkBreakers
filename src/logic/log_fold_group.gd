class_name LogFoldGroup
extends RefCounted

## One row in the folded combat log (taskblock-22 Pass F) — owned and
## mutated by LogFold, never constructed directly. `kind`:
## &"attack" (a plain shot or a burst — drillable into per-hit lines),
## &"move" (a folded run of move/faced-for-travel pairs — drillable into
## its own raw move/faced events), &"face" (a standalone, player-queued
## FaceAction — one line, nothing to drill into), &"admin" (any other
## event kind, rendered exactly as CombatLog's own flat sinks already do,
## via LogEvent._to_string() — the catch-all that keeps an unrecognized
## future LogEvent kind visible rather than silently dropped).

var kind: StringName
var unit_id: int
var summary: String = ""
var events: Array[LogEvent] = []
var hits: int = 0
var misses: int = 0
var weapon_label: String = "Attack"
## Attack-group-only: one line per impact/miss, in emission order, each
## rewritten in place as that impact's own cascade (part_mangled, ...)
## lands — never a second line for the same hit.
var raw_lines: Array[String] = []


func _init(p_kind: StringName, p_unit_id: int) -> void:
	kind = p_kind
	unit_id = p_unit_id


## F1: "fold identical adjacent results with a count" for an attack
## group's own hit/miss lines; "expanding shows every underlying event"
## for everything else multi-event (a folded move/face run, say). A
## single-event group has nothing to drill into — its summary line
## already is the whole story.
func detail_lines() -> Array[String]:
	if kind == &"attack":
		return _fold_adjacent(raw_lines)
	if events.size() <= 1:
		return []
	var lines: Array[String] = []
	for event: LogEvent in events:
		lines.append(event._to_string())
	return lines


static func _fold_adjacent(lines: Array[String]) -> Array[String]:
	var folded: Array[String] = []
	var i := 0
	while i < lines.size():
		var j := i
		while j < lines.size() and lines[j] == lines[i]:
			j += 1
		var count: int = j - i
		folded.append("%d× %s" % [count, lines[i]] if count > 1 else lines[i])
		i = j
	return folded
