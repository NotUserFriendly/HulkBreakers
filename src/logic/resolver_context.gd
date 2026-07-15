class_name ResolverContext
extends RefCounted

## Everything StatResolver.resolve() draws on for one stat_id. Populate only
## what applies to the situation — empty fields contribute nothing.
##
## `parts` get mined for `stat_id` generically (any part whose flat modifier
## dictionary mentions this stat contributes a PART-kind ADD source) since
## that shape is uniform and already exists on Part (Phase 1). Perks, ammo,
## status effects, and stance (Phases 4/6/7 — none have a dedicated class
## yet) feed `extra_sources` directly as already-built ModSource entries,
## since each owns its own internal shape and StatResolver shouldn't need to
## know it.

var base: float = 0.0
var parts: Array[Part] = []
var extra_sources: Array[ModSource] = []
