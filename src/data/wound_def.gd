class_name WoundDef
extends Resource

## taskblock-20 Pass D: one row of the wound table — open StringName content,
## same posture as `MaterialEntry`/materials (DataLibrary-loaded, id-keyed,
## authored as data, never a code edit to add a new one). A wound is a
## non-terminal, per-part, repairable consequence: the state between "fine"
## and "failed" — distinct from `is_mangled`/`is_disabled` (whole-part, only
## ever at 0 hp) and from a future status effect (which decays; a wound
## persists until repaired or the part is removed).

@export var id: StringName = &""
## True if carrying this wound alone removes the part's own operability —
## `severed_controls`' "limb inert but pristine": the part stays attached,
## hp untouched, but can no longer act as a weapon or a manipulator
## (`WoundEffects.is_disabled_by_wounds`, `Shell.operable_parts`). False
## (the default) — most wounds are cosmetic/narrative flavor or affect only
## repair, not combat capability (`lodged_bullet`, `burnt_electronics`).
@export var disables: bool = false
## Flagged, tunable — no repair system exists yet to actually consume this
## (docs: "repair" is unbuilt), so it's storage only today, the same
## posture `MaterialEntry.ricochet_bias` already carries. 1.0 is the
## baseline "ordinary" difficulty; `burnt_electronics` authors something
## higher, per the taskblock's own "carries higher repair difficulty."
@export var repair_difficulty: float = 1.0
@export var description: String = ""


## taskblock-21 Pass A2: "each entry is a <5-char short blurb now (a square
## icon later — leave room for that)." A mechanical truncation of `id`, not
## an authored abbreviation — no icon/short-name system exists yet, this is
## the placeholder until one does. Same posture as `render_primitive`'s own
## "BOX default, no cutover needed" — every wound authored before this
## field existed still gets a usable (if blunt) blurb for free.
func short_label() -> String:
	return String(id).left(5).to_upper()
