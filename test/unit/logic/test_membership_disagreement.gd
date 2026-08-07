extends GutTest

## tb61 Pass B (`BR60.02`): **the membership disagreement, characterised — and NOT fixed.**
##
## `BodyProjector.projects` returns `hp > 0 or is_mangled or is_disabled`;
## `UnitGeometry.assembly_placements` emits boxes under a bare `hp > 0`. A part that failed under
## MANGLE or DISABLE is admitted by one and produces no geometry from the other.
##
## ## The obvious fix is wrong, and this file exists so nobody spends another session finding out
##
## Making the view defer to the projector looks correct: the projector's own doc comment claims to
## be *"the only answer"*, `Part.is_disabled` promises a part that *"still occludes shots as
## geometry"*, and `docs/10`'s pillar is render-is-hitbox. **It was tried in this pass and it
## resurrects every destroyed blocker on the board.**
##
## `Part.failure_mode` **defaults to `&"MANGLE"`** and `wall.tres` authors none — so a destroyed
## wall is `is_mangled`, the projector admits it, and giving it boxes again means it goes on
## blocking line of sight and stopping rounds. `test_los.gd` went red on
## *"a destroyed wall must stop blocking LOS"*, and `docs/02`'s settled rule is explicit that
## destroying a wall clears its cell to fully passable ground.
##
## ## So they are not two answers to one question
##
## They are two different questions applied in series, and the series is load-bearing. The
## projector asks **may this part be considered at all**; `assembly_placements` asks **does it
## still have volume**. Collapsing them conflates "not excluded" with "still solid".
##
## **The real disagreement is upstream of both.** `MANGLE` as the *default* failure mode means
## almost everything is mangled at 0 hp, which is not what `Part.is_mangled` describes — "the
## wreckage look", a part that "isn't simply gone". A rule that tells a wrecked cladding plate
## from a demolished wall has to come from `mangles_into` or from failure-mode semantics, not
## from a boolean over `is_mangled`. **That decision is `BR60.02`'s and is not made here.**


func _part(hp: int, mangled: bool = false, disabled: bool = false) -> Part:
	var part := Part.new()
	part.id = &"test_limb"
	part.max_hp = 10
	part.hp = hp
	part.is_mangled = mangled
	part.is_disabled = disabled
	part.volume = [Box.new(Vector3(0.0, 0.4, 0.0), Vector3(0.3, 0.8, 0.3))]
	return part


func _boxes_for(limb: Part) -> int:
	return UnitGeometry.assembly_placements(limb, Vector2i(3, 3), 0.0, null, 0.0).size()


## **The disagreement itself, measured.** Read off both real functions rather than re-derived, so
## this cannot agree with a third copy of the rule and nothing else.
##
## **These assertions describe a DEFECT, not a desired behaviour.** The mangled and disabled rows
## are `BR60.02`. When that entry is decided, those rows change and this test wants rewriting
## rather than patching.
func test_the_projector_and_the_view_disagree_and_this_is_br60_02() -> void:
	var rows: Array = [
		{"name": "healthy", "part": _part(10), "projects": true, "boxes": 1},
		{"name": "destroyed", "part": _part(0), "projects": false, "boxes": 0},
		{"name": "mangled at 0 hp", "part": _part(0, true, false), "projects": true, "boxes": 0},
		{"name": "disabled at 0 hp", "part": _part(0, false, true), "projects": true, "boxes": 0},
	]
	for row: Dictionary in rows:
		var limb: Part = row["part"]
		var projects: bool = BodyProjector.projects(limb)
		var boxes: int = _boxes_for(limb)
		gut.p("%-16s projects=%-5s boxes=%d" % [row["name"], str(projects), boxes])
		assert_eq(projects, bool(row["projects"]), "%s: projector" % row["name"])
		assert_eq(boxes, int(row["boxes"]), "%s: boxes emitted" % row["name"])


## **The consequence, and why `BR52.06` is probably this.** A part the projector admits and the
## geometry gives no boxes for is struck by nothing: `RayCaster` gates on `projects` and then
## marches `assembly_placements`, so an empty box list is an un-hittable part. A mangled leg is
## invisible *and* intangible — which matches *"a leg appears to have no model"* exactly.
func test_a_mangled_part_is_admitted_and_then_has_no_geometry_to_strike() -> void:
	var limb: Part = _part(0, true, false)

	assert_true(BodyProjector.projects(limb), "the projector admits it")
	assert_eq(
		_boxes_for(limb),
		0,
		(
			"and it has no boxes, so every consumer that gates on the projector and then asks "
			+ "for geometry finds nothing — invisible AND intangible"
		)
	)


## **The fact that made the wall failure findable, kept because it is what any fix must not
## break.** A destroyed wall carries `is_mangled` purely because `failure_mode` defaults to
## `MANGLE`, so any rule keyed on that flag alone resurrects it.
func test_a_destroyed_wall_is_mangled_only_because_mangle_is_the_default_failure_mode() -> void:
	var wall := Part.new()
	wall.id = &"wall"
	wall.max_hp = 60
	wall.hp = 0

	assert_eq(
		wall.failure_mode,
		&"MANGLE",
		"an unauthored failure_mode is MANGLE — which is why this flag cannot carry the rule"
	)
	DamageResolver.resolve_part_failure(wall, null, null)
	assert_true(wall.is_mangled, "so a destroyed wall is 'mangled' without anyone choosing that")
	assert_true(
		BodyProjector.projects(wall),
		(
			"and the projector therefore admits a demolished wall — giving it boxes again would "
			+ "contradict docs/02's settled rule that destroying a wall clears its cell"
		)
	)
