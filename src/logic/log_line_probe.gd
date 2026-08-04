class_name LogLineProbe
extends RefCounted

## taskblock-57 Pass C: **which combat-log line is under the cursor, and is it cut off.**
##
## The table asks for an overflow preview: *"a combat-log overflow preview is revealing (what
## does this line say, shown in place over the text)"*. Deciding **which** line and **whether** it
## needs revealing is arithmetic over line offsets and widths, so it lives here and is asserted
## headlessly. `CombatLogPanel` does the part only Godot can do — measuring a font and reading a
## scrollbar — and then asks these two questions.
##
## Splitting it this way is what makes the behaviour testable at all. A preview that only exists
## once a `RichTextLabel` has laid itself out inside a live window is a behaviour nobody can check.

## The width slack, in pixels. A line that measures a hair wider than the visible area because of
## font hinting is not "cut off", and revealing it would flicker a preview over text that is
## already fully readable.
const OVERFLOW_EPSILON := 1.0


## The index of the line containing `content_y`, or -1 when there is none.
##
## `offsets[i]` is the top of line `i` in content space — what `RichTextLabel.get_line_offset`
## returns — so the answer is the last line whose top is at or above the point. `content_y` is
## already scroll-corrected by the caller; this function knows nothing about scrolling.
##
## **Returns -1 rather than clamping** for a point above the first line: "the cursor is not on a
## line" is a real answer, and clamping it to line 0 would reveal the top line whenever the cursor
## sat in the padding above it.
static func line_at(offsets: PackedFloat32Array, content_y: float) -> int:
	if offsets.is_empty() or content_y < offsets[0]:
		return -1
	var found: int = -1
	for i in range(offsets.size()):
		if offsets[i] <= content_y:
			found = i
		else:
			break
	return found


## True if a line that wide cannot be read in a viewport that wide.
static func overflows(line_width: float, visible_width: float) -> bool:
	return line_width > visible_width + OVERFLOW_EPSILON


## The plain text of line `index`, or `""` for an index outside `lines`.
##
## **Bounds-checked rather than trusted**, because the two inputs come from different places: the
## offsets are the label's current layout and the text is the label's parsed content, and a render
## landing between the two reads would otherwise index past the end.
static func text_of(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]
