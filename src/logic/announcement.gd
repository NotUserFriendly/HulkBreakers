class_name Announcement
extends RefCounted

## taskblock-57 Pass E: **an announcement is a tagged combat-log event, not a second message.**
##
## *"One emit, two views. Anything tagged as an announcement lands in the combat log **and** is
## shown at the announcement position. **Sequential, not double-rendered** — it can never appear in
## one and not the other, which is exactly what two calls would eventually produce."*
##
## So there is no announcement API to call. A caller emits **one** `LogEvent` with a priority in its
## `data`, `CombatLog` fans it out to its sinks as it already does, and the announcement position is
## simply another sink reading the same stream. The combat log keeps it forever; the position shows
## it for a while. **Nothing can put a line in one and not the other**, because nothing chooses.
##
## ## The priority table is data
##
## `CLAUDE.md`: open `StringName` vocabularies for content. A priority is a row here — duration,
## colour, and a `sound` — and a new one is a row, never a code edit. Nothing branches on a specific
## priority id anywhere.
##
## ## `sound` is authored and unread, deliberately
##
## *"There is no audio system — the priority carries a `sound` field and nothing consumes it,
## exactly as `encounter_types` is authored and unread. Do not build audio here."* So the field
## round-trips and no code reads it. A test asserts exactly that, because a field nobody reads is
## one somebody later assumes is wired.

## The `LogEvent.data` key carrying the priority id. **In `data`, not in `kind`** — an announcement
## is not a kind of event, it is an ordinary event someone wanted shown twice. A `unit_down` is
## still a `unit_down` whether or not it is announced.
const PRIORITY_KEY := "announce"

## Shown briefly, in the ordinary foreground. The default for anything tagged without saying more.
const NOTICE := &"notice"
## Longer and highlighted — something the player would be annoyed to have missed.
const ALERT := &"alert"
## Longest and loudest. Reserved for the handful of things that end or change a mission.
const CRITICAL := &"critical"


## Every priority, as `id -> {seconds, color, sound}`.
##
## **The numbers are flagged starting positions, not design** (`CLAUDE.md`: never invent a balance
## number and present it as one). Durations are ordered rather than tuned; the colours reuse
## `HulkTheme`'s existing tiers rather than inventing a palette.
static func table() -> Dictionary:
	return {
		NOTICE: {"seconds": 3.0, "color": HulkTheme.FOREGROUND, "sound": &"ui_notice"},
		ALERT: {"seconds": 5.0, "color": HulkTheme.HIGHLIGHT, "sound": &"ui_alert"},
		CRITICAL: {"seconds": 8.0, "color": HulkTheme.MP_PIP, "sound": &"ui_critical"},
	}


## The row for `id`, or `NOTICE`'s. **An unknown priority is shown, not dropped**: a tagged event
## naming a priority nobody authored is still something someone wanted the player to see, and the
## failure mode of silence is worse than the failure mode of a plain line.
static func priority(id: StringName) -> Dictionary:
	var rows: Dictionary = table()
	return rows.get(id, rows[NOTICE])


## True if `event` was tagged for the announcement position.
static func tagged(event: LogEvent) -> bool:
	return event != null and event.data.has(PRIORITY_KEY)


## The priority id `event` was tagged with, or `&""` for an untagged one.
static func priority_of(event: LogEvent) -> StringName:
	if not tagged(event):
		return &""
	return StringName(event.data[PRIORITY_KEY])


## How long `event` stays at the announcement position, in seconds.
static func seconds_for(event: LogEvent) -> float:
	return float(priority(priority_of(event))["seconds"])


static func color_for(event: LogEvent) -> Color:
	return priority(priority_of(event))["color"] as Color


## **Authored and unread.** See the class note: there is no audio system, and this exists so the
## table is complete when one arrives rather than being retrofitted onto every priority later.
static func sound_for(event: LogEvent) -> StringName:
	return StringName(priority(priority_of(event))["sound"])


## Tags `data` with `id`, for a caller building a `LogEvent` to emit.
##
## **A helper on the event's data, not an emit path of its own** — the whole point is that there is
## exactly one emit and this does not add a second. Returns the same dictionary for chaining at a
## call site that is already building one.
static func tag(data: Dictionary, id: StringName = NOTICE) -> Dictionary:
	data[PRIORITY_KEY] = id
	return data
