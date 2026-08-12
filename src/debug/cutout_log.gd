class_name CutoutLog
extends RefCounted

## **"cutout drawn to (x, y)", and since taskblock-61 Pass C1, why.** Lifted out of `BoardView`,
## which had reached `gdlint`'s file-size cap (`gdlintrc`'s `max-file-lines`, then at a lower
## value) with no room for the `BR32.05` diagnostic
## this class exists to add. Emission policy is a combat-log concern rather than a board-geometry
## one, so it reads better here anyway.
##
## **Deliberately not per frame.** `BoardView.update_wall_cutout` runs every frame, on every wall,
## while the camera orbits — and `FileSink.emit()` flushes to disk per line, so a genuine per-frame
## event here would cost more than the effect it documents and would bury every other event in the
## log. Emitted only when the cutout meaningfully CHANGES: how many units are being cut for, or any
## of them crossing into a different `GRID` block of screen space. Holding still logs nothing; a
## real change logs once. Stated here rather than silently narrowed — the volume ceiling is the
## design, not an oversight.
##
## **The blame half is the `BR32.05` diagnostic.** The supervisor reported the cutout still firing
## when zoomed out with, as they read it, nothing between camera and unit. CC's headless sweep
## could not reproduce a gate that invents occlusion (an empty board and a wall off to the side
## stay clear at every zoom, `test_cutout_gate_over_zoom.gd`) — so what is missing is not another
## theory but the gate naming the cell it actually blamed, in the log, where the next live session
## turns the disagreement into evidence. `docs/00`: get it into the combat log as a named decision
## so it stops being an adjudication.

## taskblock-41 Pass D: how coarsely a cut unit's screen position is quantised before deciding the
## cutout "changed". Big enough that a slow orbit produces a readable trickle rather than one event
## per frame, small enough that a real repositioning still registers. Flagged and tunable
## (CLAUDE.md: never invent a final number).
const GRID := 64.0

var _last_fingerprint := ""


## Forget what was last logged, so a fresh board never suppresses its own first line as a repeat
## of the previous one's.
func reset() -> void:
	_last_fingerprint = ""


## `blamed` is one entry per fed unit, parallel to `screen_positions`: the cell the sight gate
## found in the way, or `null` for a unit fed without the gate having been consulted (no grid).
func emit(log: CombatLog, screen_positions: PackedVector2Array, count: int, blamed: Array) -> void:
	if log == null:
		return
	var blocks := PackedStringArray()
	for i in range(count):
		var position: Vector2 = screen_positions[i]
		blocks.append("%d,%d" % [int(position.x / GRID), int(position.y / GRID)])
	var current: String = "|".join(blocks)
	if current == _last_fingerprint:
		return
	_last_fingerprint = current

	var blame := PackedStringArray()
	for entry: Variant in blamed:
		blame.append("-" if entry == null else "%d.%d" % [entry.x, entry.y])
	var blame_text: String = "|".join(blame)
	log.emit(
		LogEvent.new(
			0,
			Enums.Phase.TACTICS,
			-1,
			&"wall_cutout",
			{"units": count, "blocks": current, "blocked_by": blame_text},
			(
				"wall cutout: %d unit(s) at screen blocks [%s] blocked by cells [%s]"
				% [count, current, blame_text]
			)
		)
	)
