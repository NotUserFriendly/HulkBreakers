extends GutTest

## **No two surfaces in a mode overlap, except where the layout says they may.**
##
## From the review chat, and it is the note that matters most of the three passes' worth:
##
## > *Collision testing is per-case, not general. `test_the_readout_sits_clear_of_the_debug_panel`
## > and `test_the_debug_panels_stay_inside_the_viewport` are specific pairs. There is no test
## > asserting that no two surfaces overlap in a given mode.*
## >
## > *CC's own finding shows why that matters: `SuiteRunPanel` had reached into the action bar's
## > band for two passes, invisible until the spectator cluster moved into the same space. That was
## > caught by a test written for a different pair, by luck of adjacency.*
##
## **That is exactly what happened**, and it is worth being precise about how close it came to not
## being caught: the panel had overlapped the bar's band since the band existed, and the pair that
## noticed was `TopLeftControls` versus the debug panels — a test about a different corner, which
## only fired because taskblock-57 G1 moved a third thing into the space. Nothing was watching the
## pair that was actually wrong.
##
## ## The exception list is the valuable part
##
## A blanket "nothing overlaps" would be false, and making it pass would mean moving surfaces the
## table deliberately stacks. So the exceptions are declared, each with the reason it is one — and
## **an exception is a pair, not a surface**, so a module excused for lying under the announcement
## band is not thereby excused for landing on the combat log.
##
## `EXPECTED_OVERLAPS` is the thing to read when this fails. A new entry is a decision; adding one
## without a reason beside it is how the check stops meaning anything.
##
## ## What it can and cannot see, said plainly
##
## It measures **the rect a surface actually occupies on screen**, read off the real node after two
## frames, in whichever modes the table declares. It does not see a surface that is correct at
## 1920x1080 and wrong at another size — headless has one viewport, and `docs/TEST-AUDIT.md` records
## what happens when a test pretends otherwise. Ratio coverage stays `test_battle_layout.gd`'s,
## headlessly, over the arithmetic.

## The viewport headless actually has (`project.godot`). Asserted against the real `ui_root.size`
## rather than forced onto it — see `test_battle_placements.gd` for why forcing does not work.
const SCREEN := Vector2(1920, 1080)

## A rect this small is not a surface — an unmounted or empty container reports a few pixels and
## would generate noise rather than findings.
const MIN_REAL_SIZE := 8.0

## Overlap under this many pixels on either axis is a layout rounding artefact, not a collision.
const SLOP := 2.0

## **Pairs that are allowed to overlap, and why.** Keys are sorted `"a|b"` module-id pairs.
##
## Every entry is a deliberate stacking decision from taskblock-57's placement table. Read the
## reason before adding a fourth.
const EXPECTED_OVERLAPS: Dictionary = {
	# *"Announcements — top, centred, invisible and click-through."* It is a **position**, not a
	# panel: it spans the safe width at the top of the screen and draws nothing until something is
	# announced, so anything that legitimately sits up there is under it by design.
	"announcements|debug_panel": "the announcement position is invisible and click-through",
	"announcements|inspect": "same — Inspect is top-right and the band spans the safe width",
	"announcements|inspect_viewer": "same — the viewer is top-left, under the same band",
	"announcements|replay": "same — the run panels sit below the band and reach into it",
	# *"Performance monitor — true bottom-right corner, no padding, click-through and mostly
	# transparent."* The table asks for it to sit over whatever is in that corner.
	"combat_log|perf_monitor": "the perf readout is click-through and mostly transparent",
	"perf_monitor|turn_controls": "same",
	"action_bar|perf_monitor": "same",
	"control_toggle|perf_monitor": "same",
}


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _overlay(mode: ViewMode) -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(mode)
	battle.set_overlay(overlay)
	# Two frames: the first lets the chrome's regions take their sizes, the second lets the panels
	# inside them settle against those sizes.
	await get_tree().process_frame
	await get_tree().process_frame
	return overlay


## The first `Control` a module actually built, wherever it put it — the same probe
## `test_battle_placements.gd` uses, and for the same reason: modules place different kinds of node,
## so ancestry is asked of whatever they made rather than of a field named per module.
func _surface_of(module: ViewModule) -> Control:
	for field: StringName in [&"panel", &"frame", &"column", &"row", &"backing", &"bar_root"]:
		var found: Variant = module.get(field)
		if found is Control and (found as Control).is_visible_in_tree():
			var rect: Rect2 = (found as Control).get_global_rect()
			if rect.size.x >= MIN_REAL_SIZE and rect.size.y >= MIN_REAL_SIZE:
				return found as Control
	return null


static func _pair_key(a: StringName, b: StringName) -> String:
	var names: Array[String] = [String(a), String(b)]
	names.sort()
	return "%s|%s" % [names[0], names[1]]


## Two rects overlap only if they share more than `SLOP` on **both** axes — a one-pixel seam where
## two surfaces abut is not a collision, and the layout deliberately abuts several.
static func _really_overlaps(a: Rect2, b: Rect2) -> bool:
	var shared_x: float = minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var shared_y: float = minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	return shared_x > SLOP and shared_y > SLOP


## Every visible surface pair in `mode`, checked against the exception list.
func _assert_no_overlaps(mode: ViewMode) -> void:
	var overlay: ControlOverlay = await _overlay(mode)
	assert_eq(
		overlay.ui_root.size, SCREEN, "the headless viewport is not the size this file assumes"
	)

	# **The node as well as the rect**, because two modules may legitimately share one `Control` —
	# `ControlToggleModule` puts its button into `TurnControlsModule`'s own column rather than
	# building a second one beside it, so both report the same rect. A node cannot collide with
	# itself, and excusing that as a declared *pair* would have hidden a real collision between them
	# if they ever stopped sharing.
	var surfaces: Dictionary = {}
	var nodes: Dictionary = {}
	for id: StringName in overlay.module_context.modules:
		var found: Control = _surface_of(overlay.module_context.modules[id])
		if found != null:
			surfaces[id] = found.get_global_rect()
			nodes[id] = found

	gut.p("%s: %d visible surfaces" % [mode.id, surfaces.size()])
	assert_gt(
		surfaces.size(), 1, "%s produced nothing to compare, so this proved nothing" % mode.id
	)

	var ids: Array = surfaces.keys()
	ids.sort()
	var collisions: Array[String] = []
	for i: int in range(ids.size()):
		for j: int in range(i + 1, ids.size()):
			var a: StringName = ids[i]
			var b: StringName = ids[j]
			if nodes[a] == nodes[b]:
				continue
			if EXPECTED_OVERLAPS.has(_pair_key(a, b)):
				continue
			if _really_overlaps(surfaces[a] as Rect2, surfaces[b] as Rect2):
				collisions.append(
					(
						"%s %s overlaps %s %s"
						% [a, str(surfaces[a] as Rect2), b, str(surfaces[b] as Rect2)]
					)
				)
	for line: String in collisions:
		gut.p(line)
	assert_eq(
		collisions.size(),
		0,
		(
			(
				"%s has overlapping surfaces; either move one or declare the pair in "
				+ "EXPECTED_OVERLAPS with the reason: %s"
			)
			% [mode.id, ", ".join(collisions)]
		)
	)


# ---------------------------------------------------------------- the modes


func test_the_player_mode_has_no_undeclared_overlaps() -> void:
	await _assert_no_overlaps(ViewModes.player())


func test_the_spectator_mode_has_no_undeclared_overlaps() -> void:
	await _assert_no_overlaps(ViewModes.spectator())


func test_the_editor_mode_has_no_undeclared_overlaps() -> void:
	await _assert_no_overlaps(ViewModes.editor())


# ---------------------------------------------------------------- the check's own honesty


## **The exception list must not be able to hide a real collision by accident.** Every declared pair
## has to name two modules some shipped mode actually mounts — an entry naming something that no
## longer exists is an excuse nobody can evaluate, and it would sit there excusing a pair that had
## quietly become a different pair.
func test_every_declared_exception_names_modules_that_exist() -> void:
	var known: Dictionary = {}
	for mode: ViewMode in ViewModes.all():
		for id: StringName in mode.modules:
			known[id] = true

	for key: String in EXPECTED_OVERLAPS:
		var reason: String = EXPECTED_OVERLAPS[key]
		assert_ne(reason.strip_edges(), "", "%s is excused with no reason given" % key)
		for name: String in key.split("|"):
			assert_true(
				known.has(StringName(name)),
				"the exception '%s' names '%s', which no mode declares" % [key, name]
			)


## **And the check must be able to fail.** A geometry test that cannot report a collision is the
## shape this file exists to replace, so the comparison is exercised directly on rects it should
## reject and rects it should not.
func test_the_overlap_comparison_actually_reports_an_overlap() -> void:
	var a := Rect2(Vector2(0, 0), Vector2(100, 100))
	assert_true(_really_overlaps(a, Rect2(Vector2(50, 50), Vector2(100, 100))), "a real overlap")
	assert_false(_really_overlaps(a, Rect2(Vector2(100, 0), Vector2(100, 100))), "abutting is not")
	assert_false(
		_really_overlaps(a, Rect2(Vector2(99, 0), Vector2(100, 100))),
		"and a one-pixel seam is a layout artefact, not a collision"
	)
