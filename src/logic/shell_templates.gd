class_name ShellTemplates
extends RefCounted

## docs/10 taskblock05 G: named ShellTemplates the builder's own template
## dropdown can pick from — open StringName vocabulary, a new template is
## one more row here, no other code changes. Today there's exactly one
## real body shape in the game (docs/01's reference humanoid); more are
## content, not architecture.

const DEFAULT_ID := &"reference_humanoid"


static func by_id(id: StringName) -> ShellTemplate:
	match id:
		&"reference_humanoid":
			return DeepStrike.reference_humanoid_template()
		JunkBot.TEMPLATE_ID:
			return JunkBot.template()
		_:
			return null


## Every known template id, for a UI dropdown to list.
static func all_ids() -> Array[StringName]:
	return [&"reference_humanoid", JunkBot.TEMPLATE_ID]
