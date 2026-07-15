class_name Targeting
extends RefCounted

## Appendix C: exposure-weighted part selection first, then cover interception.


static func resolve_hit(
	attacker: Unit, target: Unit, grid: Grid, rng: RandomNumberGenerator
) -> HitResult:
	var parts: Array[Part] = target.chassis.living_parts()
	var part: Part = _weighted_choice(parts, rng)
	var hit := HitResult.new()
	if part == null:
		return hit  # no selectable (living, positive-exposure) parts

	var cov: CoverInfo = Cover.between(grid, attacker.cell, target.cell)
	if cov.object != null and part.slot_type in cov.profile:
		if cov.object.is_destructible:
			hit.cover_object = cov.object
			hit.cover_cell = cov.cell
		else:
			hit.blocked = true
		return hit

	hit.part = part
	return hit


## Rolls a single part from `parts`, weighted by exposure_weight. Zero-weight
## (or all-zero) parts are excluded from selection, per Appendix C.
static func _weighted_choice(parts: Array[Part], rng: RandomNumberGenerator) -> Part:
	var total: float = 0.0
	for p: Part in parts:
		total += maxf(p.exposure_weight, 0.0)
	if total <= 0.0:
		return null

	var roll: float = rng.randf() * total
	var cumulative: float = 0.0
	for p: Part in parts:
		cumulative += maxf(p.exposure_weight, 0.0)
		if roll < cumulative:
			return p
	return parts[parts.size() - 1]
