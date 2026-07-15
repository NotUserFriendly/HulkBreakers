class_name ToolParts
extends RefCounted

## docs/05's tool tiers, priced in AP against the 6 AP baseline — "the same
## job, three ways; tier buys AP, not just numbers." These are the docs'
## own concrete numbers, not invented placeholders. Battlefield
## modification of a dropped assembly (docs/01) is priced the same way —
## SwapPartAction/ModifyAssemblyAction both take ap_cost directly, so a
## tool's own ap_cost is exactly what a caller passes through.


## Fits in a backpack; ~6 AP (a full turn) to remove a limb; limited uses.
static func angle_grinder() -> Part:
	var tool := Part.new()
	tool.id = &"angle_grinder"
	tool.hp = 2
	tool.max_hp = 2
	tool.bulk = 2.0
	tool.mass = 3.0
	tool.ap_cost = 6
	return tool


## Replaces a hand; ~2 AP to remove a limb; costs you a hand, runs off
## unit power.
static func metal_saw() -> Part:
	var tool := Part.new()
	tool.id = &"metal_saw"
	tool.hp = 4
	tool.max_hp = 4
	tool.mass = 2.0
	tool.ram_cost = 1.0
	tool.attaches_to = [&"WRIST"]
	tool.capabilities = [&"SUPPORT"]
	tool.ap_cost = 2
	return tool


## Requires a specialized torso; ~1 AP per limb (this part's own ap_cost),
## ~2 AP to render a whole unit — that whole-unit sweep is a separate mode
## a future multi-target action would choose, not a second Part; consumes
## an entire reactor's output.
static func power_saw() -> Part:
	var tool := Part.new()
	tool.id = &"power_saw"
	tool.hp = 6
	tool.max_hp = 6
	tool.mass = 5.0
	tool.ram_cost = 3.0
	tool.attaches_to = [&"INTERNAL"]
	tool.ap_cost = 1
	return tool
