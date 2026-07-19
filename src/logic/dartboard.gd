class_name Dartboard
extends RefCounted

## docs/02: aiming picks an aim point on the shot plane, never a body part.
## Per projectile: pick a ring by weight, sample uniformly within its
## annulus, offset from the aim point. All sampling draws from the passed
## seeded RandomNumberGenerator — never randi()/randf() directly (CLAUDE.md
## determinism rule).


## Resolves `weapon`'s authored scatter rings through StatResolver (docs/08):
## ring i's radius/weight are read as stats `scatter_radius_i`/
## `scatter_weight_i`, so a modifier like "Spin Up" shrinking one ring is
## provenance-tracked the same way any other stat is, never a raw tweak.
##
## taskblock-19 Pass C1: `radius_multiplier` folds the range-accuracy band
## (`RangeModel.accuracy_multiplier`) in as a uniform post-resolve scale on
## every ring's RADIUS only — deliberately NOT threaded through
## `extra_sources` (which `_context` hands to BOTH the radius and weight
## resolves below): a range penalty widens how far a shot can land, it
## must never also reweight which ring gets picked in the first place.
static func resolve_scatter(
	weapon: Part, extra_sources: Array[ModSource] = [], radius_multiplier: float = 1.0
) -> Array[Ring]:
	var resolved: Array[Ring] = []
	for i in range(weapon.scatter.size()):
		var ring: Ring = weapon.scatter[i]
		var radius_id := StringName("scatter_radius_%d" % i)
		var weight_id := StringName("scatter_weight_%d" % i)
		var radius: float = (
			StatResolver.resolve(radius_id, _context(ring.radius, weapon, extra_sources)).current
		)
		var weight: float = (
			StatResolver.resolve(weight_id, _context(ring.weight, weapon, extra_sources)).current
		)
		resolved.append(Ring.new(radius * radius_multiplier, weight))
	return resolved


static func _context(base: float, weapon: Part, extra_sources: Array[ModSource]) -> ResolverContext:
	var context := ResolverContext.new()
	context.base = base
	context.parts = [weapon]
	context.extra_sources = extra_sources
	return context


## Samples `count` impact points offset from `aim_point`. `scatter` must
## already be resolved (see resolve_scatter) and ordered inner -> outer.
static func sample(
	aim_point: Vector2, scatter: Array[Ring], rng: RandomNumberGenerator, count: int
) -> Array[Vector2]:
	var total_weight := 0.0
	for ring: Ring in scatter:
		total_weight += ring.weight

	var points: Array[Vector2] = []
	for i in range(count):
		var ring_index: int = _pick_ring(scatter, total_weight, rng)
		var inner: float = 0.0 if ring_index == 0 else scatter[ring_index - 1].radius
		var outer: float = scatter[ring_index].radius
		# Uniform-in-area sampling within the annulus, not uniform-in-radius:
		# r = sqrt(u * (outer^2 - inner^2) + inner^2) keeps density even
		# across the ring rather than bunching toward the inner edge.
		var r: float = sqrt(rng.randf() * (outer * outer - inner * inner) + inner * inner)
		var theta: float = rng.randf_range(0.0, TAU)
		points.append(aim_point + Vector2(r * cos(theta), r * sin(theta)))
	return points


static func _pick_ring(
	scatter: Array[Ring], total_weight: float, rng: RandomNumberGenerator
) -> int:
	var roll: float = rng.randf() * total_weight
	var cumulative := 0.0
	for i in range(scatter.size()):
		cumulative += scatter[i].weight
		if roll < cumulative:
			return i
	return scatter.size() - 1
