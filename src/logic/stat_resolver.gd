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
## PART-kind ADD source. Part.stat_mods stays simple flat-additive data —
## this is the one (and only) place it's ever read to compute a number.
static func gather_part_sources(stat_id: StringName, parts: Array[Part]) -> Array[ModSource]:
	var result: Array[ModSource] = []
	for part: Part in parts:
		if part.stat_mods.has(stat_id):
			var label: String = part.display_name if part.display_name != "" else String(part.id)
			result.append(
				ModSource.new(
					label, Enums.ModSourceKind.PART, Enums.ModOp.ADD, part.stat_mods[stat_id]
				)
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
	return current
