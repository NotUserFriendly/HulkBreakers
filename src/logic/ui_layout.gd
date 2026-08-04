class_name UiLayout
extends RefCounted

## taskblock-57 Pass A: **the two coordinate spaces every surface is placed against.**
##
## Logic, not view (CLAUDE.md): where a panel *should* sit is arithmetic over a screen size, and
## arithmetic is headless-testable. `ModeChrome` and the modules read this and build nodes; nothing
## here touches a `Control`.
##
## ## `safe_rect` is always 16:9; `screen_rect` is whatever the window is
##
## **All sizing is against a 16:9 reference rect.** `safe_rect` is the largest 16:9 rect that fits
## inside the screen, centred — so it is 16:9 at every screen ratio and never exceeds the screen,
## which is exactly what the layout can rely on when it places something "half a screen wide".
##
## ## Ultrawide letterboxes; narrower ratios crush
##
## The two ends are handled differently on purpose, and the difference is `crush_factor` rather
## than a second rect:
##
## - **Wider than 16:9** (ultrawide) — the safe rect is inset horizontally and the bars stay bars.
##   `crush_factor` is `(1, 1)`: nothing is stretched, because a 21:9 player has *more* room than
##   the layout was authored for and spreading the UI into it would only push things apart.
## - **Narrower than 16:9** (4:3, 16:10) — the safe rect is inset vertically, and leaving those
##   bars would waste the one axis a square-ratio player is short of. So `crush_factor` reports how
##   far to stretch back over them. **Crush, never clip:** a narrow screen shows every surface,
##   squashed, rather than showing most of them whole and cutting the rest off.
##
## **A tension in the spec, resolved and flagged.** taskblock-57 A1 says narrower ratios "crush
## rather than clip", and its own test says `safe_rect` "is 16:9 inside any screen ratio and never
## exceeds it". Those cannot both be true of one rect, so the rect keeps the 16:9 guarantee the test
## names and the crush becomes a factor applied to what is drawn into it. That is the reversible
## reading — a later pass that wants the rect itself to fill can change one function — and it is the
## one the stated test pins.
##
## ## Escaping is a property of a slot
##
## Three surfaces deliberately leave the safe rect (Inspect, the Inspect Viewer, the performance
## monitor). **That is declared on the slot rather than written as a comment in the panel**, so it
## is checkable: `rect_for` takes the slot's own answer and resolves against `screen_rect` instead.

## The aspect every size in the layout is authored against.
const REFERENCE_ASPECT := 16.0 / 9.0

## Floating-point slack when comparing aspects. A screen one pixel off 16:9 is 16:9.
const ASPECT_EPSILON := 0.0001

## **A multiplier on every pixel size in the UI**, replacing the bare constants standing in for it.
##
## Not settable yet — it belongs to an options menu that does not exist (`PLAN.md`), so this is a
## variable with a default and one place that reads it, which is the whole of taskblock-57 A2. It is
## what makes "every side-pinned surface is collapsible" mean something: a square-ratio player
## toggles a panel off instead of being pushed into shrinking the entire UI to play.
##
## `static var` rather than a constant precisely so the options menu has something to write to.
static var scale: float = 1.0


## The whole window, in pixels. The space a slot resolves against when it escapes.
static func screen_rect(screen: Vector2) -> Rect2:
	return Rect2(Vector2.ZERO, screen)


## The largest 16:9 rect that fits inside `screen`, centred. **16:9 at every ratio, never larger
## than the screen** — the two properties everything else here depends on.
static func safe_rect(screen: Vector2) -> Rect2:
	if screen.x <= 0.0 or screen.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var aspect: float = screen.x / screen.y
	if aspect > REFERENCE_ASPECT:
		# Wider than the reference: the height is the binding constraint.
		var width: float = screen.y * REFERENCE_ASPECT
		return Rect2(Vector2((screen.x - width) * 0.5, 0.0), Vector2(width, screen.y))
	# Narrower than (or equal to) the reference: the width binds.
	var height: float = screen.x / REFERENCE_ASPECT
	return Rect2(Vector2(0.0, (screen.y - height) * 0.5), Vector2(screen.x, height))


## How far content drawn into the safe rect stretches to fill the screen it sits in.
##
## `(1, 1)` on a 16:9 screen and on anything wider — an ultrawide keeps its bars. On a narrower
## screen the Y factor exceeds 1, which is the crush: the vertical bars the safe rect would
## otherwise leave are reclaimed by squashing rather than by cutting anything off.
static func crush_factor(screen: Vector2) -> Vector2:
	var safe: Rect2 = safe_rect(screen)
	if safe.size.y <= 0.0 or screen.x / screen.y >= REFERENCE_ASPECT - ASPECT_EPSILON:
		return Vector2.ONE
	return Vector2(1.0, screen.y / safe.size.y)


## The rect a slot resolves against: `screen_rect` if it escapes, `safe_rect` otherwise.
##
## **The whole point of escaping being a slot property rather than a convention.** A caller asks the
## slot and gets an answer; it never has to know which three surfaces are the special ones.
static func rect_for(escapes_safe_rect: bool, screen: Vector2) -> Rect2:
	return screen_rect(screen) if escapes_safe_rect else safe_rect(screen)


## `pixels` at the current UI scale. **The one place `scale` is read**, so a size that forgot to go
## through it is a size that does not move when the option does.
static func scaled(pixels: float) -> float:
	return pixels * scale


static func scaled_size(size: Vector2) -> Vector2:
	return size * scale


## A fraction of the safe rect's width, scaled. The action bar is "half a 16:9 screen wide at 1x",
## and this is that sentence as a call.
static func safe_width(screen: Vector2, fraction: float) -> float:
	return safe_rect(screen).size.x * fraction * scale


static func safe_height(screen: Vector2, fraction: float) -> float:
	return safe_rect(screen).size.y * fraction * scale
