class_name AnnouncementFeed
extends LogSink

## taskblock-57 Pass E: **the announcement position's view of the combat-log stream.**
##
## *"The only thing the log lacks is a lifetime, and it belongs to the view. The announcement
## position shows tagged entries newer than N seconds; the log keeps them forever."*
##
## This is that lifetime, and nothing else. It is an ordinary `LogSink`, so it receives exactly the
## same events every other sink does — **the same single emit** — and simply forgets them after a
## while. The `CombatLog`, the file sink and `out/combat.log` are untouched.
##
## ## Logic, with the clock injected
##
## `RefCounted` in `src/logic`, no SceneTree, and `tick(delta)` takes an explicit elapsed time — so
## expiry is asserted by advancing a number rather than by sleeping through it. The view calls
## `tick` from its own frame; a test calls it with 4.0.
##
## ## `wants` declines everything untagged
##
## `CombatLog.emit` checks `wants` before handing an event over, which is exactly the seam for this:
## the announcement position sees only what was tagged for it, and declining costs nothing. Without
## it this sink would hold every event in the battle and filter on read.

## The live entries, oldest first, as `{"event": LogEvent, "remaining": float}`. **Public and read
## directly** — a view wants the list and the colours, and hiding it behind an accessor that returns
## a copy would allocate once a frame for nothing.
var entries: Array[Dictionary] = []
## True when `entries` has changed since the last `tick`. **Set by arrivals as well as expiries** —
## the first version reported only expiries, so a new announcement did not draw until an unrelated
## one aged out. The same dirty-flag discipline `UiLogSink` keeps, for the same reason: exactly one
## redraw per frame no matter how many events landed.
var dirty: bool = false


## Only tagged events. See the class note.
func wants(event: LogEvent) -> bool:
	return Announcement.tagged(event)


func emit(event: LogEvent) -> void:
	entries.append({"event": event, "remaining": Announcement.seconds_for(event)})
	dirty = true


## Ages every entry, drops the expired ones, and **returns whether the view needs redrawing** —
## which covers arrivals since the last tick as well as expiries during this one.
func tick(delta: float) -> bool:
	var changed: bool = dirty
	dirty = false
	if entries.is_empty():
		return changed
	var kept: Array[Dictionary] = []
	for entry: Dictionary in entries:
		entry["remaining"] = float(entry["remaining"]) - delta
		if float(entry["remaining"]) > 0.0:
			kept.append(entry)
	changed = changed or kept.size() != entries.size()
	entries = kept
	return changed


## Everything currently showing, oldest first.
func active() -> Array[LogEvent]:
	var out: Array[LogEvent] = []
	for entry: Dictionary in entries:
		out.append(entry["event"] as LogEvent)
	return out


## Drops everything without waiting for it to expire — a new bout starts with a clear position
## rather than the last one's death notices still counting down.
func clear() -> void:
	entries.clear()
	dirty = true
