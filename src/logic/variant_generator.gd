class_name VariantGenerator
extends RefCounted

## taskblock-28 Pass A: seeded, deterministic structural variation over a
## base `BotPreset`, driven entirely by a `VariantFamily`'s own open data
## (docs/00 golden rule: this file knows nothing about "junk_bot" or
## "combat_tester" by name — every branch reads `family_def`, never a
## family id). A variant is a full, standalone `BotPreset` produced by
## copying the base and mutating the copy's own `Loadout` (the same
## "editing the base does NOT propagate" posture `BotPreset.variant_label`
## already documents) — never a diff/override layered at assembly time.
##
## Reuses `BodyAssembler`'s own `&""` "leave bare" sentinel (Pass A) for
## omission; a swap just overrides a socket's own entry to a different
## pool part id, no new mechanism.


## `rng` must be a caller-owned, seeded `RandomNumberGenerator` (docs/00
## determinism: never `randi()`/`randf()` directly) — same seed, same
## draws, every time.
static func generate(
	base: BotPreset, family_def: VariantFamily, rng: RandomNumberGenerator
) -> BotPreset:
	var varied_entries: Dictionary = _vary_entries(base.loadout, family_def, rng)
	return BotPreset.new(
		base.preset_name,
		base.template_id,
		Loadout.new(varied_entries),
		base.pose_id,
		base.profile_family,
		base.variant_label,
		base.kit
	)


static func _vary_entries(
	base_loadout: Loadout, family_def: VariantFamily, rng: RandomNumberGenerator
) -> Dictionary:
	var entries: Dictionary = base_loadout.entries.duplicate(true) if base_loadout != null else {}
	if family_def == null or family_def.variation_amount <= 0.0:
		return entries

	for socket_id: StringName in family_def.omittable_sockets:
		if rng.randf() < family_def.variation_amount:
			entries[socket_id] = &""
			continue
		_maybe_swap(entries, socket_id, family_def, rng)

	for socket_id: StringName in family_def.swap_pool:
		# Omission (above) already rolled + possibly swapped every
		# omittable socket; only handle a swap-pool socket here that ISN'T
		# also omittable, so it's never rolled twice.
		if socket_id in family_def.omittable_sockets:
			continue
		_maybe_swap(entries, socket_id, family_def, rng)

	return entries


static func _maybe_swap(
	entries: Dictionary,
	socket_id: StringName,
	family_def: VariantFamily,
	rng: RandomNumberGenerator
) -> void:
	var options: Array = family_def.swap_pool.get(socket_id, [])
	if options.is_empty():
		return
	if rng.randf() < family_def.variation_amount:
		entries[socket_id] = options[rng.randi() % options.size()]


## The zero-variation fallback for a `profile_family` with no authored
## `VariantFamily` at all — "never crash, never silently invent": an
## unauthored family generates uniform bots (the base preset back,
## untouched), never a made-up variation rule.
static func generate_for_family(base: BotPreset, rng: RandomNumberGenerator) -> BotPreset:
	var family_def: VariantFamily = DataLibrary.get_variant_family(base.profile_family)
	if family_def == null:
		family_def = VariantFamily.new()
	return generate(base, family_def, rng)
