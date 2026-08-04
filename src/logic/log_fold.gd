class_name LogFold
extends RefCounted

## taskblock-22 Pass F: folds the flat LogEvent stream into a hierarchical
## VIEW only — every event still reaches every LogSink unchanged (F2:
## "folding is presentation only," CombatLog/MemorySink/FileSink are
## untouched by this file). `ingest()` is the single entry point: feed it
## events in emission order, it returns the LogFoldGroup each one landed
## in (a brand-new group, or the still-open one from the previous call)
## so a sink can decide whether to add a new row or just re-render the
## last one.
##
## Grouping is inferred entirely from existing event shape — no new
## LogEvent kind was added to do this. FaceAction's own `reason` field
## already distinguishes "this face is part of a move" from "this face is
## part of an attack" from "this face was a standalone, player-queued
## FaceAction" — reused here verbatim rather than inventing a second
## classification signal.
##
## Known simplifications (flagged, not silently handled):
## - Two separate plain AttackActions by the same unit back to back, with
##   no move/face between them, fold into ONE attack group — nothing in
##   the event stream marks "a new action started" for a bare AttackAction
##   the way &"burst_fired" does for BurstAction. The combined summary's
##   own hit/miss counts stay accurate; only the grouping is coarser.
## - A fragmenting round's own child impacts (ImpactResult.fragment_hits)
##   log recursively BETWEEN their parent's own cascade events (see
##   ShotResolution.log_impact_result) — this folder attaches every cascade
##   event to whichever impact/miss most recently opened, so a parent
##   impact's post-fragment cascade (meltdown_armed, matrix_ejected, ...)
##   can attach to its last fragment's Hit line instead of its own. Rare
##   (needs a fragmenting round AND a matrix/meltdown consequence on the
##   very same impact) and cosmetic only — every event is still in
##   `events`, nothing lost, just occasionally on the "wrong" Hit line.
## - "unit N down" is derived by checking `state.find_unit(id).alive` at
##   render time (`state` is optional) rather than adding a new LogEvent
##   kind from CombatState.kill_unit() — the more surgical long-term fix,
##   but a change to the event stream itself, which F2 says not to make
##   for this pass.

const MAX_GROUPS := 200

## Cascade-kind events that belong to whichever impact/miss most recently
## opened — see ShotResolution.log_impact_result's own emission order.
const CASCADE_KINDS: Array[StringName] = [
	&"wound_inflicted",
	&"part_destroyed",
	&"salvage_credited",
	&"part_mangled",
	&"part_disabled",
	&"detonate",
	&"meltdown_armed",
	&"matrix_ejected",
	&"surrogate_ejected",
	&"surrogate_demoted",
	&"subtree_dropped",
]

## taskblock-41 Pass D: the high-volume plumbing kinds Passes B–D added, folded
## into one counted row per consecutive run (`_ingest_plumbing`). An open
## vocabulary, like every other kind list here — a new diagnostic event kind
## joins this array and needs no other code edit to stop flooding the panel.
##
## `diagnostic` is deliberately absent: an error must not be collapsed into a
## quiet counted row.
const PLUMBING_KINDS: Array[StringName] = [
	&"command",
	&"command_outcome",
	&"build_step",
	&"wall_cutout",
	&"unit_assembled",
	&"overlay_activated",
	&"overlay_deactivated",
	# Added after rendering the spectator log (post-tb41): `FpsDumpSink` emits
	# one of these per turn, and a spectated bout runs turns continuously, so
	# eleven identical "Turn FPS ... 74.0" rows were filling the panel and
	# pushing every real combat event out of view. Exactly the flooding this
	# array exists to stop — it just predates this kind being high-volume
	# enough to notice. Folded, not dropped: the numbers are still drillable,
	# and `out/combat.log` is unaffected either way (folding is presentation
	# only, tb22 F2).
	&"fps_dump",
	# taskblock-57 Pass D: **the queuing fold the taskblock asks for by name.** `queue_panel`
	# retires this block and its confirmation role — "what I clicked registered" — moves here. A
	# five-leg move plan is five events; folded, it is one counted row that opens into five, rather
	# than five rows pushing the fight off the top of the panel. Reset Turn is the same shape in
	# reverse. Drillable, never dropped, and `out/combat.log` is unaffected either way.
	QueueLog.QUEUED,
	QueueLog.CANCELLED,
]

var groups: Array[LogFoldGroup] = []
## Optional — enables "unit N down" in an attack summary and nothing
## else. A null state just omits that suffix; every other fold behavior
## is identical (test_log_fold.gd covers both).
var state: CombatState = null

var _open: LogFoldGroup = null
## Index into `_open.raw_lines` of the impact currently accumulating
## cascade detail, or -1 once the open group's last detail line is a
## finished Miss (or nothing has landed yet).
var _open_hit_line: int = -1
var _open_targets_hit: Array[int] = []
var _open_move_cells: int = 0
## `BR51.13`: which plumbing kind the open plumbing group is accumulating, so a run only ever
## folds events of ONE kind together. `&""` whenever no plumbing group is open.
var _open_plumbing_kind: StringName = &""


func _init(p_state: CombatState = null) -> void:
	state = p_state


func ingest(event: LogEvent) -> LogFoldGroup:
	if event.kind == &"burst_fired":
		return _ingest_attack_start(event)
	if event.kind == &"burst_pull":
		return _ingest_attack_marker(event)
	if event.kind == &"impact" or event.kind == &"miss":
		return _ingest_attack_detail(event)
	if event.kind == &"faced":
		return _ingest_faced(event)
	if event.kind == &"move":
		return _ingest_move(event)
	if CASCADE_KINDS.has(event.kind):
		return _ingest_attack_cascade(event)
	if PLUMBING_KINDS.has(event.kind):
		return _ingest_plumbing(event)
	return _ingest_admin(event)


func _ingest_attack_start(event: LogEvent) -> LogFoldGroup:
	var group: LogFoldGroup = _open_attack(event.unit_id)
	group.weapon_label = "%s Burst" % _weapon_label(event.data.get("weapon", &""))
	group.events.append(event)
	group.summary = _attack_summary(group)
	return group


func _ingest_attack_marker(event: LogEvent) -> LogFoldGroup:
	var group: LogFoldGroup = _open_attack(event.unit_id)
	group.events.append(event)
	group.summary = _attack_summary(group)
	return group


func _ingest_attack_detail(event: LogEvent) -> LogFoldGroup:
	var group: LogFoldGroup = _open_attack(event.unit_id)
	group.events.append(event)
	if event.kind == &"miss":
		group.misses += 1
		group.raw_lines.append("Miss")
		_open_hit_line = -1
	else:
		group.hits += 1
		var target: int = event.data.get("target_unit_id", -1)
		if target != -1 and not _open_targets_hit.has(target):
			_open_targets_hit.append(target)
		group.raw_lines.append(_format_hit(event))
		_open_hit_line = group.raw_lines.size() - 1
	group.summary = _attack_summary(group)
	return group


func _ingest_attack_cascade(event: LogEvent) -> LogFoldGroup:
	if _open == null or _open.kind != &"attack" or _open_hit_line == -1:
		return _ingest_admin(event)
	_open.events.append(event)
	var suffix: String = _cascade_suffix(event)
	if suffix != "":
		_open.raw_lines[_open_hit_line] += suffix
	_open.summary = _attack_summary(_open)
	return _open


func _ingest_faced(event: LogEvent) -> LogFoldGroup:
	var reason: StringName = event.data.get("reason", &"")
	if reason == &"free_with_move":
		var move_group: LogFoldGroup = _open_move(event.unit_id)
		move_group.events.append(event)
		return move_group
	if reason == &"free_with_action":
		var attack_group: LogFoldGroup = _open_attack(event.unit_id)
		attack_group.events.append(event)
		attack_group.summary = _attack_summary(attack_group)
		return attack_group
	_close()
	var standalone := LogFoldGroup.new(&"face", event.unit_id)
	standalone.summary = event._to_string()
	standalone.events.append(event)
	_add(standalone)
	return standalone


func _ingest_move(event: LogEvent) -> LogFoldGroup:
	var group: LogFoldGroup = _open_move(event.unit_id)
	group.events.append(event)
	var path: Array = event.data.get("path", [])
	_open_move_cells += maxi(0, path.size() - 1)
	var dest: Vector2i = event.data.get("destination", Vector2i.ZERO)
	group.summary = (
		"Unit %d moved %d cell%s (→ %s)"
		% [event.unit_id, _open_move_cells, "" if _open_move_cells == 1 else "s", dest]
	)
	return group


## taskblock-41 Pass D: the deliberately-verbose kinds Passes B–D added fold
## into ONE row per consecutive run, drillable into the individual lines —
## otherwise a board build alone would push seven admin rows through the panel
## before the first shot, and every debug verb two more.
##
## `diagnostic` (tb41 Pass B — a real engine or script error) is pointedly NOT
## in this set. Collapsing an error into a quiet counted row is the opposite of
## what an error is for; it keeps its own admin row and stays loud.
## `BR51.13`: **a plumbing run folds one kind, not any plumbing at all.**
##
## The supervisor read `fps_dump` rows disappearing inside `wall_cutout` reports. Both kinds
## are listed as plumbing, and this folded any consecutive stretch of *any* plumbing kinds
## into a single group — so a framerate measurement landing between two wall-cutout events was
## swallowed by their counted row and had to be drilled into to be seen at all.
##
## **A passing test sat right beside this the whole time.**
## `test_a_diagnostic_keeps_its_own_row_and_is_never_folded_into_plumbing` protects the kind
## literally named `diagnostic`, which is absent from `PLUMBING_KINDS` and therefore never
## reached this function. Its name claims a general rule; it asserts a membership check. That
## is the failure taskblock-49's audit was built to find, arriving from the other direction —
## the assertion was narrower than its name, and the gap it left was a live defect.
##
## Breaking the run by kind keeps the anti-flooding purpose intact — eleven consecutive
## `fps_dump` events still fold into one row — while a measurement never hides inside
## something unrelated.
func _ingest_plumbing(event: LogEvent) -> LogFoldGroup:
	if _open == null or _open.kind != &"plumbing" or _open_plumbing_kind != event.kind:
		_close()
		_open = LogFoldGroup.new(&"plumbing", event.unit_id)
		_open_plumbing_kind = event.kind
		_add(_open)
	_open.events.append(event)
	_open.summary = _plumbing_summary(_open)
	return _open


## "12× command". **Always uniform since `BR51.13`** — a group is broken whenever the plumbing
## kind changes, so the old "12 log events" fallback for a mixed run can no longer be reached.
## It is kept as the honest answer if a future edit ever lets kinds share a group again: a
## single label that lies about its contents is worse than a vaguer one.
static func _plumbing_summary(group: LogFoldGroup) -> String:
	var kinds: Dictionary = {}
	for event: LogEvent in group.events:
		kinds[event.kind] = true
	var count: int = group.events.size()
	if kinds.size() == 1:
		return "%d× %s" % [count, group.events[0].kind]
	return "%d log events" % count


func _ingest_admin(event: LogEvent) -> LogFoldGroup:
	_close()
	var group := LogFoldGroup.new(&"admin", event.unit_id)
	group.summary = event._to_string()
	group.events.append(event)
	_add(group)
	return group


func _open_attack(unit_id: int) -> LogFoldGroup:
	if _open != null and _open.kind == &"attack" and _open.unit_id == unit_id:
		return _open
	_close()
	_open = LogFoldGroup.new(&"attack", unit_id)
	_open_hit_line = -1
	_open_targets_hit = []
	_add(_open)
	return _open


func _open_move(unit_id: int) -> LogFoldGroup:
	if _open != null and _open.kind == &"move" and _open.unit_id == unit_id:
		return _open
	_close()
	_open = LogFoldGroup.new(&"move", unit_id)
	_open_move_cells = 0
	_add(_open)
	return _open


func _close() -> void:
	_open = null
	_open_hit_line = -1
	_open_plumbing_kind = &""


func _add(group: LogFoldGroup) -> void:
	groups.append(group)
	if groups.size() > MAX_GROUPS:
		groups.pop_front()


func _format_hit(event: LogEvent) -> String:
	var outcome_index: int = event.data.get("outcome", 0)
	var outcome: String = String(Enums.Outcome.keys()[outcome_index]).to_lower()
	if event.data.get("bypassed_armor", false):
		outcome = "bypass"
	var part: String = event.data.get("part", "")
	var target: int = event.data.get("target_unit_id", -1)
	var target_label: String = " unit %d" % target if target != -1 else ""
	var damage: float = event.data.get("damage", 0.0)
	return "Hit  %s  %s%s  %.1f dmg" % [outcome, part, target_label, damage]


func _cascade_suffix(event: LogEvent) -> String:
	match event.kind:
		&"part_mangled":
			return ", mangled"
		&"part_disabled":
			return ", disabled"
		&"part_destroyed":
			return ", destroyed"
		&"wound_inflicted":
			return ", %s" % event.data.get("wound", "wounded")
		&"detonate":
			return ", detonated"
		&"meltdown_armed":
			return ", meltdown armed"
		&"matrix_ejected":
			return ", matrix ejected"
		&"surrogate_ejected":
			return ", surrogate ejected"
		&"surrogate_demoted":
			return ", demoted"
	# &"subtree_dropped"/&"salvage_credited": bookkeeping, not part of the
	# struck part's own outcome — still recorded in `events`, just not
	# appended to the Hit line's text.
	return ""


func _attack_summary(group: LogFoldGroup) -> String:
	var down_suffix: String = ""
	if state != null:
		var down: Array[String] = []
		for target_id: int in _open_targets_hit:
			var unit: Unit = state.find_unit(target_id)
			if unit != null and not unit.alive:
				down.append(str(target_id))
		if down.size() == 1:
			down_suffix = ", unit %s down" % down[0]
		elif down.size() > 1:
			down_suffix = ", units %s down" % ", ".join(down)
	return (
		"Unit %d · %s · %d hits, %d miss%s"
		% [group.unit_id, group.weapon_label, group.hits, group.misses, down_suffix]
	)


static func _weapon_label(weapon_id: StringName) -> String:
	if weapon_id == &"":
		return "Attack"
	var part: Part = DataLibrary.get_part(weapon_id)
	if part != null and part.display_name != "":
		return part.display_name
	return str(weapon_id)
