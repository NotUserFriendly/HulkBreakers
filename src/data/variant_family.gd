class_name VariantFamily
extends Resource

## taskblock-28 Pass A: what a `profile_family` (BotPreset.profile_family)
## declares about how its own bots MAY generate-vary, as open data — never
## a hardcoded per-family branch in the generator. A designer adds a new
## variant family entirely by authoring one more `.tres` here; the
## generator (`VariantGenerator`) reads it generically.
##
## `id` matches a `BotPreset.profile_family` this family's own generation
## rules apply to (e.g. &"junk_bot") — the same open-StringName join key
## `BoutSetup.group_by_family` already uses to group presets, never a
## second, parallel vocabulary.

@export var id: StringName = &""

## 0.0 (the default) = uniform — every generated bot is identical to the
## base (a "combat_tester" family: zero variation, on purpose). Scales
## every per-socket draw below as a flat probability; a family author
## tunes one number to make its whole bot family more or less consistent.
@export var variation_amount: float = 0.0

## Socket ids (matching a `Mount.socket_id`/`Socket.id` already present on
## the base template) that MAY be left bare this roll — `variation_amount`
## is the per-socket chance of omission, independently rolled per socket
## so a generated bot can be missing armor on one limb and not another.
@export var omittable_sockets: Array[StringName] = []

## Socket id -> alternate pool part ids the generator may substitute for
## that socket's own default occupant, `variation_amount` chance per
## socket (independent of, and rolled before, `omittable_sockets` for that
## same socket — a socket can swap OR be omitted, never both in one roll,
## since omission is checked first and short-circuits the swap draw).
## Open StringName content on both sides — a designer's swap pool, never a
## closed enum.
@export var swap_pool: Dictionary = {}


func _init(
	p_id: StringName = &"",
	p_variation_amount: float = 0.0,
	p_omittable_sockets: Array[StringName] = [],
	p_swap_pool: Dictionary = {}
) -> void:
	id = p_id
	variation_amount = p_variation_amount
	omittable_sockets = p_omittable_sockets
	swap_pool = p_swap_pool
