class_name Blocker
extends RefCounted

## taskblock-63 Pass D3: **one placed blocker at a cell — the record surfaces have had
## since taskblock-38 and blockers never got.**
##
## ## The defect this closes is that a blocker's placement context was a dictionary key
##
## The three placement kinds were unequal, and only one of them was poorer at runtime
## than the format describing it:
##
## | placement kind | context | carried |
## |---|---|---|
## | body part | the socket-tree walk | a full `Transform3D` |
## | surface | `Surface(part, height, facing)` | height, facing |
## | **blocker** | **a dictionary key** | **a cell, and nothing else** |
##
## **A `Part` is a template; the transform lives in the placement context.** So a wall
## authored at height 4.0 had nowhere to keep that fact between being loaded and being
## drawn, and `MapSerializer` dropped `height`, `size`, `offset` and `facing` on load
## (`grid.blockers[placement.cell] = part`) *and* on save (reconstructing a placement
## from the cell and the part id alone). **It round-tripped because both ends discarded
## the same fields**, which is `BR62.05`.
##
## **It was invisible because nothing authored a non-zero blocker height.** A third
## fixed generation height (+4) is exactly what surfaces it: a floor at +4 sits above
## every wall on the board, so an exterior wall has to follow its neighbours up.
##
## ## Why the same four field names as `MapPlacement`, not a new idea
##
## `MapPlacement` already carries `height`, `size`, `offset` and `facing`. This is the
## runtime half of that record and nothing more — the serializer maps one to the other
## field for field, so there is exactly one vocabulary for where a placed thing sits.
## **A second transform concept for blockers is how the surface and blocker paths came
## to disagree in the first place**, and inventing one (quarter turns baked into boxes,
## say) is the thing this deliberately is not.
##
## ## `size` and `offset` are the authored intent; the part's boxes are the result
##
## `MapSerializer._sized` bakes both into the part's own `volume` at load, so everything
## downstream — `BoardView`, `RayCaster`, `SightSpans`, `DamageResolver` — works on real
## geometry with no idea a size was involved. That is deliberate and unchanged. What was
## missing is that **the intent had nowhere to survive**, so a save could only re-emit
## what it could see, and what it could see was already baked. Keeping both here is what
## makes the round trip lossless rather than merely symmetric.

## The part standing here. Live and mutable — hp, `is_mangled` — exactly as it was when
## `Grid.blockers` held it bare.
var part: Part
## This blocker's own real world elevation, in world units. `0.0` is "on the floor plane",
## which is every blocker authored before this record existed.
var height: float
## The size it was authored at, or `Vector3.ZERO` for "the part's own". Already applied to
## `part.volume`; kept so a save can say what was asked for rather than measuring what came
## out.
var size: Vector3
## How far it sits from its cell's centre, or `Vector3.ZERO` for "centred". Already applied
## to `part.volume`, same as `size`.
var offset: Vector3
## Radians, the convention `Surface.facing` and `Unit.orientation` use.
##
## **Carried but not yet drawn.** `BoardView._spawn_blocker` renders at facing 0.0, and
## `PLAN`'s *Blockers need a real transform* item is where the drawing half lives — a
## placement carrying a facing that nothing renders is the visual/logic disagreement
## taskblock-59 spent a block removing. It is stored here so the round trip is lossless
## and so that item has somewhere to put its answer, and that limit is stated rather than
## left to be discovered.
var facing: float


func _init(
	p_part: Part,
	p_height: float = 0.0,
	p_size: Vector3 = Vector3.ZERO,
	p_offset: Vector3 = Vector3.ZERO,
	p_facing: float = 0.0
) -> void:
	part = p_part
	height = p_height
	size = p_size
	offset = p_offset
	facing = p_facing


## A copy carrying its own duplicated part — what `Grid.dup()`'s speculative preview needs,
## since a preview attack that destroys cover must never touch the real `Part`.
func duplicated() -> Blocker:
	return Blocker.new(part.duplicate(true) if part != null else null, height, size, offset, facing)
