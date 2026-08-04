class_name AnnouncementsModule
extends ViewModule

## taskblock-57 Pass E: **the announcement position — a second view of the combat-log stream.**
##
## Pass C's table: *"Announcements | top, centred, invisible and click-through."* Invisible meaning
## the surface itself draws nothing — there is no panel, no background, no frame. What appears is
## the text, and only while it is live.
##
## ## It does not receive announcements; it reads the log
##
## `AnnouncementFeed` is a `LogSink` on the same `CombatLog` every other sink is on, so a tagged
## event reaches the log and this position **from one emit**. There is no announce path to call and
## therefore no way for the two to disagree — which the taskblock asks for by name: *"sequential,
## not double-rendered."*
##
## ## Left-aligned, always, on the supervisor's instruction
##
## The taskblock offers a choice: *"centred when the inspect panels are closed, left-aligned when
## open. **If that cross-module read is awkward, left-align always** — the supervisor has said so
## explicitly, so take the simpler option rather than building a dependency for it."* It is awkward
## — it would make this module read Inspect's visibility every frame, and Inspect is a module that
## may not be mounted at all (it is absent from the aim set). So: left-aligned, always.

## Rebuilding the labels costs nothing at this scale and keeps "what is on screen" a pure function
## of the feed, so there is no incremental-update path to get wrong.
var column: VBoxContainer = null
var feed := AnnouncementFeed.new()

## The `CombatLog` this feed is attached to, so teardown detaches from the one it actually joined
## rather than from whatever `context.battle` holds by then — a replay swaps `combat_state` under a
## live surface, which is exactly when those differ.
var _attached_to: CombatLog = null


func module_id() -> StringName:
	return &"announcements"


func preferred_slot() -> StringName:
	return ModuleSlots.ANNOUNCEMENTS


func _mount() -> void:
	column = VBoxContainer.new()
	# **Invisible and click-through**, both of which the table states outright. This sits over the
	# top of the board, so a container that took clicks would eat camera drags across the whole
	# upper strip of the screen.
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	var slot: Control = context.slot(preferred_slot(), null)
	if slot != null:
		slot.add_child(column)
	else:
		add_child(column)
	rebind()


func _unmount() -> void:
	if _attached_to != null:
		_attached_to.remove_sink(feed)
	_attached_to = null


## Points the feed at whichever `CombatLog` is current, and clears what the last one left showing.
##
## **Idempotent**: `remove_sink` is a documented no-op on a sink that was never added, so the call
## from `_mount` is safe and so is a re-load under an already-mounted module.
func rebind() -> void:
	var state: CombatState = context.battle.combat_state if context.battle != null else null
	if state == null or state.combat_log == null:
		return
	if _attached_to != null:
		_attached_to.remove_sink(feed)
	# A new bout starts with a clear position rather than the last one's notices still counting down.
	feed.clear()
	_render()
	state.combat_log.add_sink(feed)
	_attached_to = state.combat_log


## Ages the feed and redraws only when the list actually moved — the same dirty-flag discipline
## `UiLogSink.render_if_dirty` keeps for the log, and for the same reason.
func tick(delta: float) -> void:
	if feed.tick(delta):
		_render()


## **Rebuilt from the feed, never patched.** What is on screen is a pure function of what is live,
## so there is no add/remove bookkeeping that can drift from the list it is meant to mirror.
func _render() -> void:
	if column == null:
		return
	for child: Node in column.get_children():
		child.queue_free()
	for event: LogEvent in feed.active():
		var line := Label.new()
		line.text = event.text
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# The colour comes from the priority table, so it and the duration cannot disagree about how
		# important the same line is.
		line.add_theme_color_override("font_color", Announcement.color_for(event))
		column.add_child(line)
