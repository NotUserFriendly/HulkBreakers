class_name LogScrollHandoff
extends RefCounted

## taskblock-41 Pass F: "scrolling while hovered scrolls the log; at the top or
## bottom of the content it falls through to the camera rather than
## dead-stopping."
##
## The threshold rule, split out from the panel so it is testable without a
## scene tree, a mouse, or a camera — the panel does the plumbing, this decides.
##
## The failure this prevents is subtle: a panel that always consumes the wheel
## turns "I scrolled to the bottom and kept scrolling" into a dead zone over
## part of the screen, and the user's next instinct is that zoom is broken.

## Scrolling UP means moving toward the START of the content.
enum Direction { UP, DOWN }


## True if the log itself should consume this wheel event; false if it should
## fall through to whatever is behind it (the camera).
##
## `scroll_value` is the scrollbar's current position, `max_value` its maximum,
## `page` the visible span (Godot's `ScrollBar.page` — the scrollbar reaches
## `max_value - page` when it is at the bottom, NOT `max_value`, which is the
## detail this rule exists to get right).
static func consumes(
	direction: Direction, scroll_value: float, max_value: float, page: float
) -> bool:
	# Content shorter than the viewport: there is nothing to scroll, so every
	# wheel event belongs to the camera. Without this, a nearly-empty log would
	# silently eat the wheel over its own rect.
	if max_value <= page:
		return false
	if direction == Direction.UP:
		return scroll_value > 0.0
	return scroll_value < max_value - page


## Convenience for the panel: reads the live scrollbar rather than making every
## call site pull three numbers off it in the right order.
static func consumes_scrollbar(direction: Direction, bar: ScrollBar) -> bool:
	if bar == null:
		return false
	return consumes(direction, bar.value, bar.max_value, bar.page)
