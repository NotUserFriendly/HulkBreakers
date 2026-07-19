class_name DeterminismCheck
extends RefCounted


## The standing rule (Appendix A / docs/09), as a reusable check: same seed,
## same output, always — for any generator. Returns a result Dictionary
## rather than asserting directly, so it stays engine/GUT-agnostic; the
## calling test asserts on `result.ok`.
##
## `generator_fn(seed: int) -> Variant` — anything comparable.
## `compare_fn(a, b) -> bool` — optional; defaults to `==`. Supply one for
## types whose `==` means reference identity (RefCounted/Resource), e.g. a
## Grid compared by its terrain/opacity/occupant_id arrays and blockers dict.
static func check(
	generator_fn: Callable, seeds: Array[int], compare_fn: Callable = Callable()
) -> Dictionary:
	var failed_seeds: Array[int] = []
	for seed: int in seeds:
		var a: Variant = generator_fn.call(seed)
		var b: Variant = generator_fn.call(seed)
		var same: bool = compare_fn.call(a, b) if compare_fn.is_valid() else (a == b)
		if not same:
			failed_seeds.append(seed)
	return {"ok": failed_seeds.is_empty(), "failed_seeds": failed_seeds}
