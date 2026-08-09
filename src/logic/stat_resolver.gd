class_name StatResolver
extends RefCounted

## The single entry point for every final stat number (docs/08). The
## renderer, the AI, and the damage resolver all call resolve() — nothing
## else may compute a final stat (see test_stat_resolver_is_the_only_place_
## that_reads_stat_mods, a literal grep test on the source tree). Pure and
## deterministic: same inputs, same StatValue, always.


static func resolve(stat_id: StringName, context: ResolverContext) -> StatValue:
	var sources: Array[ModSource] = gather_part_sources(stat_id, context.parts)
	sources.append_array(context.extra_sources)

	var current: float = context.base
	for source: ModSource in sources:
		current = _apply(current, source)

	return StatValue.new(context.base, current, sources)


## Every part in `parts` whose stat_mods mentions `stat_id` contributes one
## PART-kind source. `Part.stat_mods` stays simple flat data — this is the one
## (and only) place it's ever read to compute a number.
##
## tb62 Pass A: **`op` moved onto the gather rather than onto the data.** It defaults
## to `ADD`, which is every caller that existed before and every stat but one. What it
## is NOT is a per-part authored field: how a stat combines is a property of the
## *stat*, not of the part offering it, and letting two legs author different
## combination rules for the same number would make `resolve()`'s answer depend on
## part order. `Unit.step_height` is the one caller that asks for something else, and
## it asks for `MAX` because a stride is set by the longest leg rather than by how
## many legs there are.
static func gather_part_sources(
	stat_id: StringName, parts: Array[Part], op: Enums.ModOp = Enums.ModOp.ADD
) -> Array[ModSource]:
	var result: Array[ModSource] = []
	for part: Part in parts:
		if part.stat_mods.has(stat_id):
			var label: String = part.display_name if part.display_name != "" else String(part.id)
			result.append(
				ModSource.new(label, Enums.ModSourceKind.PART, op, part.stat_mods[stat_id])
			)
	return result


static func _apply(current: float, source: ModSource) -> float:
	match source.op:
		Enums.ModOp.ADD:
			return current + source.delta
		Enums.ModOp.MULTIPLY:
			return current * source.delta
		Enums.ModOp.OVERRIDE:
			return source.delta
		Enums.ModOp.MAX:
			return maxf(current, source.delta)
	return current
