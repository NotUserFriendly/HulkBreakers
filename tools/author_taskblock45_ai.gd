extends SceneTree

## taskblock-45 Pass B: one-time authoring pass — the utility planner's starting
## action pool and profile table, written to `res://data/utility_actions/` and
## `res://data/utility_profiles/`.
##
## **Deliberately small.** Four actions and two profiles at opposite ends of one
## axis, because a tier or a profile that silently does nothing is the failure this
## design is most exposed to, and that is far easier to catch on four actions than
## on twenty. `PLAN.md`'s *AI v2 — fill in the tier table* is the rest, and it
## needs no code: a fifth action is a fifth `.tres` in the same directory.
##
## **Every number here is a flagged placeholder, not a balance decision**
## (CLAUDE.md: never invent balance numbers and present them as design). What IS
## designed is the shape — which considerations an action reads, and which
## direction each profile leans. The magnitudes exist so the two profiles decide
## differently; they have not been tuned against play, and nothing downstream
## treats them as authority.
##
## ## Profile weights and the direction an input is read in
##
## `consideration_weights` deliberately carries only inputs that ONE action reads,
## in ONE direction. `own_integrity` is read forwards by `approach` ("I am healthy,
## so charge") and backwards by `take_cover` ("I am hurt, so hide"), so a single
## profile weight on it would push both readings the same way and mean two opposite
## things at once — "aggressive cares less about being hurt" would make an
## aggressive unit BOTH charge less and hide less. There is no weight that says
## what was wanted. The personality therefore lives in `action_weights`, which is
## unambiguous, and a future profile that genuinely needs to weight harm separately
## from health must have `UtilityContext` publish it as its own input rather than
## reusing this one inverted.
##
## Run once via `godot --headless -s res://tools/author_taskblock45_ai.gd`; kept
## afterward as a historical record, same posture as every other
## `tools/author_*.gd` one-time pass. Re-running it overwrites the `.tres` files
## with these values, which is how an accidental edit is undone.

const ACTIONS_DIR := "res://data/utility_actions"
const PROFILES_DIR := "res://data/utility_profiles"
const OBJECTIVES_DIR := "res://data/batch_objectives"
## How far a batch objective may damp an action that does not serve it. **A floor,
## never a veto**: an objective biases a follower, it does not forbid it anything,
## because a follower that cannot shoot while the squad is withdrawing is a squad
## planner wearing a consideration's clothes. Flagged, not tuned.
##
## **It has to be low enough to outweigh the base-weight spread, or the objective
## is inert.** This was 0.5 for one commit and did nothing measurable: `shoot`
## carries `base_weight` 1.5 and is served by `hold` alone, so under both `advance`
## and `withdraw` it was damped by the same 0.5 and still beat the action each of
## those objectives was boosting. The batch had an objective, the log recorded it,
## every follower read it, and not one decision changed — the exact "a tier that
## silently does nothing" failure this block is most exposed to, arriving on the
## batch axis instead. At 0.25 the three cases separate: dormant shoots, `advance`
## approaches, `withdraw` takes cover.
const OBJECTIVE_FLOOR := 0.25
## How far a maximum predicted threat may pull a score down. Flagged, not tuned —
## see `_predicted_threat` for why it is deliberately gentle.
const THREAT_FLOOR := 0.6

## taskblock-46 Pass E: `docs/11`'s tier table, as the membership lists
## `UtilityActionDef.tiers` takes. **Empty means every tier**, so a row absent from
## both of these is available to `MINDLESS` too.
##
## Written as "and above" lists rather than a rank because `intelligence_tier` is an
## open `StringName` with no defined ordering — the same reason `WorldView`'s own
## gates are lists. A fifth tier joins the lists it belongs to.
const GRUNT_AND_ABOVE: Array[StringName] = [&"GRUNT", &"TRAINED", &"ELITE"]
const TRAINED_AND_ABOVE: Array[StringName] = [&"TRAINED", &"ELITE"]


func _initialize() -> void:
	var written := 0
	written += _write_actions()
	written += _write_profiles()
	written += _write_objectives()
	print("Authored %d utility AI resources." % written)
	quit()


func _write_actions() -> int:
	var count := 0
	for action: UtilityActionDef in _actions():
		var path: String = "%s/%s.tres" % [ACTIONS_DIR, action.id]
		if ResourceSaver.save(action, path) != OK:
			push_error("Failed to save %s" % path)
			continue
		count += 1
	return count


func _write_profiles() -> int:
	var count := 0
	for profile: UtilityProfile in _profiles():
		var path: String = "%s/%s.tres" % [PROFILES_DIR, profile.id]
		if ResourceSaver.save(profile, path) != OK:
			push_error("Failed to save %s" % path)
			continue
		count += 1
	return count


func _write_objectives() -> int:
	var count := 0
	for objective: UtilityActionDef in _objectives():
		var path: String = "%s/%s.tres" % [OBJECTIVES_DIR, objective.id]
		if ResourceSaver.save(objective, path) != OK:
			push_error("Failed to save %s" % path)
			continue
		count += 1
	return count


func _consideration(input_id: StringName, weight: float, curve: ResponseCurve) -> ConsiderationDef:
	return ConsiderationDef.new(input_id, curve, weight)


## A linear curve that never reaches zero — the floor is what separates a
## PREFERENCE from a REQUIREMENT in a product model.
##
## **This is the single easiest way to author a bug into this system.** Every
## consideration multiplies, so an input that can legitimately reach 0.0 vetoes the
## whole action, however good everything else is. A plain linear `standoff_match`
## therefore does not mean "prefer this distance" — it means **"refuse to act more
## than eight cells off the preferred standoff"**, which would stop a rifleman with
## a thirty-cell weapon from ever taking a long shot. Nothing about the arithmetic
## announces that; the action simply never gets chosen.
##
## So: a consideration expressing a preference is floored, and only a consideration
## expressing a genuine impossibility (`line_of_fire`) is left able to reach zero.
## `slope` is reduced to match, keeping the top of the range at 1.0 rather than
## clipping a band of high inputs into an indistinguishable ceiling.
##
## `invert` reads the same input backwards — high input, low utility — which is far
## clearer at the authoring site than a negative slope plus a compensating offset.
func _floored(floor_value: float, invert: bool = false) -> ResponseCurve:
	return ResponseCurve.new(ResponseCurve.LINEAR, 1.0 - floor_value, floor_value, 2.0, 0.5, invert)


## The opposite of `_floored`, and the one place a zero is WANTED: maps the
## "0.5 means no change" progress inputs onto 0.0-at-no-change, 1.0-at-arrival.
##
## **A move that makes no progress must be worth nothing, or a unit oscillates
## forever.** `closes_to_objective`/`closes_to_extraction` publish 0.5 for "no
## closer than I already am", which is correct for a combat reposition — sidestep
## and you have still done something. It is wrong for an action whose entire
## purpose is to ARRIVE somewhere: at 0.5 a sideways step still scored above the
## veto floor, so a unit whose destination was blocked or occupied kept taking one
## every turn and never finished.
##
## That is not a hypothetical. `test_a_winning_bout_runs_to_a_terminal_state`
## caught it — two units, one extraction cell, the second unit shuffling beside its
## occupied destination until the 200-turn cap — and it is the most likely
## explanation for the `TERMINATED` seeds behind taskblock-45 Pass D's completion
## drop, since those failed the same way: not dying, not finishing.
##
## `slope 2, offset -1` is the whole change: 0.5 maps to 0.0 and vetoes, 1.0 maps
## to 1.0, and everything below 0.5 clamps to 0.0.
func _progress_only() -> ResponseCurve:
	return ResponseCurve.new(ResponseCurve.LINEAR, 2.0, -1.0)


## taskblock-46 Pass E: the Elite lookahead's own consideration — **read inverted,
## and floored hard.**
##
## `predicted_threat` is "share of known enemies that can put a shot on this cell
## next turn", so it is inverted: more threat, lower score. The floor is what stops
## it becoming a veto. An Elite unit that has walked into a crossfire predicts high
## threat EVERYWHERE it can reach, and an unfloored inversion would take every
## candidate to zero — the unit would score nothing above the floor and `Panic`,
## which is the exact opposite of what a lookahead is for. The smartest tier must
## not be the one that freezes.
##
## The floor is high (0.6) on purpose: a prediction is a guess about a turn that
## has not happened, and it should tilt a choice between comparable options, never
## overrule a good one. `docs/11`'s compensation factor already amplifies a
## many-consideration action's sensitivity, so a small tilt here is not a small
## effect on the final score.
##
## **Every non-Elite tier reads `NO_PREDICTION` (0.0) here, which inverts to 1.0 and
## multiplies out to nothing.** Adding this consideration therefore cannot change how
## any lower tier plays, which is the property that makes it safe to put on actions
## every tier is offered. Asserted rather than assumed — a drift in `NO_PREDICTION`
## would silently re-score every Grunt and Trained unit in the game because of a
## capability they do not have, and nothing else would report it.
func _predicted_threat() -> ConsiderationDef:
	return _consideration(UtilityContext.INPUT_PREDICTED_THREAT, 1.0, _floored(THREAT_FLOOR, true))


func _actions() -> Array[UtilityActionDef]:
	# --- approach: close on a known enemy ------------------------------------
	#
	# The one action a MINDLESS unit is still fully effective at, which is the
	# point: with no memory it only ever has a target it can currently see, and
	# walking at something you can see needs no cognition.
	var approach := UtilityActionDef.new(&"approach", UtilityExecutors.MOVE)
	approach.display_name = "Approach"
	approach.base_weight = 1.0
	approach.preconditions = [
		UtilityContext.PRED_ENEMY_KNOWN, UtilityContext.PRED_CELL_IS_ELSEWHERE
	]
	approach.considerations = [
		# Same progress-only shape as the seek actions: an "approach" that does not
		# approach is not an approach, and at 0.5 it still outscored standing still.
		_consideration(UtilityContext.INPUT_CLOSES_DISTANCE, 1.0, _progress_only()),
		# A hurt unit is less keen to charge — floored, so it damps rather than
		# vetoes. See the FLOORS note at the bottom of this file.
		_consideration(UtilityContext.INPUT_OWN_INTEGRITY, 1.0, _floored(0.3)),
		# Charging into the one lane three guns cover is the classic AI blunder, and
		# it is invisible without a lookahead: the cell scores perfectly on distance.
		_predicted_threat(),
		# tb45 Pass C: the batch's call, injected as a consideration rather than as
		# a destination to copy. Floored, so an objective BIASES a follower rather
		# than forbidding it anything — the follower keeps individual agency, which
		# is the difference between squad coordination and a squad planner.
		_consideration(BatchObjective.input_id_for(&"advance"), 1.0, _floored(OBJECTIVE_FLOOR)),
	]

	# --- shoot: fire on a known enemy from this cell --------------------------
	var shoot := UtilityActionDef.new(&"shoot", &"shoot")
	shoot.display_name = "Shoot"
	# `docs/11`'s tier table gives ranged attack to Grunt and above. A MINDLESS unit
	# closes and swings; it does not shoot. That is the tier reading as *dumb*
	# rather than merely limited, which is the whole design.
	shoot.tiers = GRUNT_AND_ABOVE
	# The only repeatable entry in the pool: a turn spends its AP on as many shots
	# as it can pay for, decided by re-scoring and by `ActionQueue.enqueue`
	# refusing the one it cannot afford — never by a `MAX_SHOTS_PER_TURN` constant.
	shoot.repeatable = true
	# Shooting is what a fight is FOR, so it starts ahead of the movement actions
	# rather than tying with them. Flagged, not tuned.
	shoot.base_weight = 1.5
	shoot.preconditions = [
		UtilityContext.PRED_HAS_WEAPON,
		UtilityContext.PRED_ENEMY_KNOWN,
		UtilityContext.PRED_WEAPON_REACHES,
		UtilityContext.PRED_LOF_POSSIBLE,
	]
	shoot.considerations = [
		# The one UNFLOORED consideration in the pool, and deliberately so: with no
		# line there is no shot, so a zero here SHOULD veto outright. It is also a
		# precondition, which makes this the belt to that braces — the precondition
		# stops the action being offered, and this stops it scoring if the two ever
		# disagree.
		_consideration(UtilityContext.INPUT_LINE_OF_FIRE, 1.0, ResponseCurve.new()),
		_consideration(UtilityContext.INPUT_STANDOFF_MATCH, 1.0, _floored(0.25)),
		# Prefer shooting from here, or from a short step, over crossing the board
		# to do it — a long walk spends the AP the shot needs.
		_consideration(UtilityContext.INPUT_MOVE_ECONOMY, 1.0, _floored(0.2)),
		_consideration(BatchObjective.input_id_for(&"hold"), 1.0, _floored(OBJECTIVE_FLOOR)),
	]

	# --- take_cover: move somewhere with something in the way -----------------
	var take_cover := UtilityActionDef.new(&"take_cover", UtilityExecutors.MOVE)
	take_cover.display_name = "Take cover"
	# "Cover" is Grunt's row in the table. Using cover is a learned thing.
	take_cover.tiers = GRUNT_AND_ABOVE
	take_cover.base_weight = 1.0
	take_cover.preconditions = [
		UtilityContext.PRED_ENEMY_KNOWN,
		UtilityContext.PRED_CELL_IS_ELSEWHERE,
		UtilityContext.PRED_CELL_IS_COVERED,
	]
	take_cover.considerations = [
		_consideration(UtilityContext.INPUT_COVER, 1.0, ResponseCurve.new()),
		# Cover that the enemy can walk around is not cover. This is the action the
		# lookahead was worth building for: "is this cell safe" and "will this cell
		# still be safe" are different questions, and only Elite asks the second.
		_predicted_threat(),
		# `invert` reads the SAME `own_integrity` input as "how hurt am I" — far
		# clearer at the authoring site than a negative slope plus a compensating
		# offset, and it keeps the vocabulary to one entry rather than two that
		# must be kept in sync.
		_consideration(UtilityContext.INPUT_OWN_INTEGRITY, 1.0, _floored(0.25, true)),
		_consideration(UtilityContext.INPUT_STANDOFF_MATCH, 1.0, _floored(0.25)),
		_consideration(BatchObjective.input_id_for(&"withdraw"), 1.0, _floored(OBJECTIVE_FLOOR)),
	]

	# --- hold_position: defer to the next unit --------------------------------
	#
	# `&"hold_position"`, never `&"hold"` — `ActionCatalog`'s `&"hold"` is
	# taskblock-25's melee grind (`UtilityExecutors`' own doc comment has the
	# collision written out).
	var hold := UtilityActionDef.new(&"hold_position", UtilityExecutors.HOLD_POSITION)
	hold.display_name = "Hold position"
	# Well below the others: holding is what wins when nothing else clears the
	# floor, not something to aspire to. Flagged, not tuned.
	hold.base_weight = 0.3
	# Holding IS the end of the turn — nothing may be queued behind it.
	hold.ends_turn = true
	# `enemy_known` matters more than it looks. Holding means "defer to the next
	# ally, who may open a line for me" — a COMBAT reason. With no enemy known there
	# is nothing to defer FOR, and offering it there actively broke extraction:
	# `HoldAction` ends the turn itself, so a unit standing on its extraction cell
	# that chose to hold never reached the trailing `EndTurnAction` whose own
	# hold-check is what matures a hold into a real extraction. It sat on the cell
	# holding, correctly, forever.
	# **`lof_blocked` is what stops holding being the default answer.** The retired
	# planner only ever held when the shot was genuinely blocked (`final_blocked`);
	# offered unconditionally, hold wins by forfeit whenever the candidate scan is
	# short — and the view's own pacer budget shortens it, so a watched bout could
	# livelock where a headless one did not. `HoldAction` keeps the unit CURRENT, so
	# an AI that holds every turn never hands the turn on at all.
	hold.preconditions = [
		UtilityContext.PRED_ENEMY_KNOWN,
		UtilityContext.PRED_CELL_IS_CURRENT,
		UtilityContext.PRED_CAN_DEFER_TURN,
		UtilityContext.PRED_LOF_BLOCKED,
	]
	hold.considerations = [
		# The `offset` floor is what stops a healthy unit's hold from scoring a
		# hard zero: holding is a weak option, not an impossible one, and a veto
		# would mean a unit with nothing else available ends its turn rather than
		# deferring to an ally who might open a line for it.
		_consideration(UtilityContext.INPUT_OWN_INTEGRITY, 1.0, _floored(0.2, true)),
		_consideration(BatchObjective.input_id_for(&"hold"), 1.0, _floored(OBJECTIVE_FLOOR)),
	]

	# --- the mission actions --------------------------------------------------
	#
	# taskblock-45 Pass D. The head-to-head found the combat-only pool completing
	# 0% of bouts against the old planner's 75%, because completion means EXTRACTED
	# and nothing in the pool could gather or walk to an extraction cell. These four
	# rows are the whole fix — no new machinery, which is the claim `PLAN.md` makes
	# about this architecture and the first time it has been tested.
	#
	# All four require `is_player_squad`: the old planner returned early from
	# `_plan_non_combat_turn` for every other squad, and an enemy bot walking to the
	# player's extraction zone was never correct.

	# Walk toward the resource node.
	var seek_objective := UtilityActionDef.new(&"seek_objective", UtilityExecutors.MOVE)
	seek_objective.display_name = "Seek objective"
	seek_objective.base_weight = 1.0
	seek_objective.preconditions = [
		UtilityContext.PRED_IS_PLAYER_SQUAD,
		UtilityContext.PRED_OBJECTIVE_OPEN,
		UtilityContext.PRED_CELL_IS_ELSEWHERE,
	]
	seek_objective.considerations = [
		_consideration(UtilityContext.INPUT_CLOSES_TO_OBJECTIVE, 1.0, _progress_only())
	]

	# Take it, once standing on it. Weighted well above everything else: a unit
	# standing on the objective with the AP to gather has no better idea available,
	# and this is the one action that actually advances the mission state.
	var gather := UtilityActionDef.new(&"gather", UtilityExecutors.GATHER)
	gather.display_name = "Gather"
	gather.base_weight = 3.0
	gather.repeatable = true
	gather.preconditions = [
		UtilityContext.PRED_IS_PLAYER_SQUAD,
		UtilityContext.PRED_OBJECTIVE_OPEN,
		UtilityContext.PRED_CELL_IS_OBJECTIVE,
	]
	gather.considerations = [_consideration(UtilityContext.INPUT_OWN_INTEGRITY, 1.0, _floored(0.6))]

	# Objectives done — leave. The player's own squad has no extract BUTTON: it
	# walks onto its cell and ends its turn, and `EndTurnAction`'s own hold-check
	# matures that into an extraction. So there is deliberately no `extract` action
	# for squad 0; walking there is the whole behaviour.
	var seek_extraction := UtilityActionDef.new(&"seek_extraction", UtilityExecutors.MOVE)
	seek_extraction.display_name = "Seek extraction"
	seek_extraction.base_weight = 1.2
	seek_extraction.preconditions = [
		UtilityContext.PRED_IS_PLAYER_SQUAD,
		UtilityContext.PRED_OBJECTIVE_DONE,
		UtilityContext.PRED_CELL_IS_ELSEWHERE,
	]
	seek_extraction.considerations = [
		_consideration(UtilityContext.INPUT_CLOSES_TO_EXTRACTION, 1.0, _progress_only())
	]

	# --- overwatch: hold a shot for whoever walks into the arc --------------
	#
	# taskblock-45 Pass E. The retired planner reached this through
	# `_consider_overwatch`, a hand-written branch below the firing checks with its
	# own hardcoded "AGGRESSIVE never" exclusion. Here it is a row like any other,
	# and the exclusion is a WEIGHT: the aggressive profile scores it near zero,
	# which is the same behaviour expressed as data instead of as a branch.
	#
	# `OverwatchAction.is_legal` is the real gate on whether it can actually be
	# declared, so nothing here re-derives arc or range.
	var overwatch := UtilityActionDef.new(&"overwatch", &"overwatch")
	overwatch.display_name = "Overwatch"
	# Holding a shot for someone who has not arrived yet is Trained's row.
	overwatch.tiers = TRAINED_AND_ABOVE
	# Below `shoot`: taking the shot now beats waiting for it, and a unit that can
	# fire should. This wins when firing is not on offer. Flagged, not tuned.
	overwatch.base_weight = 0.9
	overwatch.preconditions = [
		UtilityContext.PRED_HAS_WEAPON,
		UtilityContext.PRED_ENEMY_KNOWN,
		UtilityContext.PRED_CELL_IS_CURRENT,
	]
	overwatch.considerations = [
		# Waiting is worth most when a shot is NOT available from here — `invert`,
		# so a clear line makes overwatch less attractive rather than more.
		_consideration(UtilityContext.INPUT_LINE_OF_FIRE, 1.0, _floored(0.3, true)),
		_consideration(UtilityContext.INPUT_STANDOFF_MATCH, 1.0, _floored(0.3)),
		_consideration(BatchObjective.input_id_for(&"hold"), 1.0, _floored(OBJECTIVE_FLOOR)),
	]

	# --- the four search verbs (taskblock-46 Pass C) --------------------------
	#
	# **The hole BR45.03 named.** Every combat action gated on `enemy_known` and
	# every mission action on `is_player_squad`, so a non-player squad that had seen
	# nobody matched neither and was offered nothing at all. These fill it.
	#
	# One verb per unit, chosen by `Unit.search_behaviour` as a PRECONDITION, so
	# exactly one is ever offered — no mode flag and no branch. That is the
	# diagnostic as much as the design: if patrol misbehaves, only patrolling units
	# do, and the failure names a verb.
	#
	# Roam, hunt and putter are the same `travel_fraction` input under three curves.
	# Three behaviours out of one published number, with no code between them, is
	# the clearest demonstration in the pool of what the model is for.
	var roam := _search_verb(&"roam", &"ROAM", "Roam")
	# Cover ground steadily. Floored so a short step is still worth something when a
	# long one is not available.
	roam.considerations.append(
		_consideration(UtilityContext.INPUT_TRAVEL_FRACTION, 1.0, _floored(0.3))
	)
	# **Distance alone is memoryless, and memoryless search oscillates.** The farthest
	# cell from A is B and the farthest from B is A, so a unit with nothing in sight
	# walks to the edge of its reach and then bounces between two cells until the turn
	# cap — seen live across a whole bout, both squads. Unfloored on purpose: ground
	# it just left must be able to score zero, or the oscillation survives at reduced
	# amplitude and looks like indecision instead of a loop.
	roam.considerations.append(
		_consideration(UtilityContext.INPUT_UNVISITED, 1.0, ResponseCurve.new())
	)

	var hunt := _search_verb(&"hunt", &"HUNT", "Hunt")
	# Roam at speed: quadratic, so the far cells pull much harder than the near ones.
	hunt.base_weight = 1.2
	hunt.considerations.append(
		_consideration(
			UtilityContext.INPUT_TRAVEL_FRACTION,
			1.0,
			ResponseCurve.new(ResponseCurve.QUADRATIC, 0.85, 0.15)
		)
	)
	# Same memory as roam, and needed harder: a steeper distance curve pulls to the
	# extremes more strongly, which is exactly what makes the two-cell loop tighter.
	hunt.considerations.append(
		_consideration(UtilityContext.INPUT_UNVISITED, 1.0, ResponseCurve.new())
	)

	var putter := _search_verb(&"putter", &"PUTTER", "Putter")
	# Stay local without idling — the same input read backwards.
	putter.considerations.append(
		_consideration(UtilityContext.INPUT_TRAVEL_FRACTION, 1.0, _floored(0.25, true))
	)
	# **Floored, where roam and hunt read it raw.** Puttering is *supposed* to stay
	# in one place, so an unfloored memory would fight the verb's whole purpose and
	# turn it into a slow roam. It only needs enough pressure to stop the unit
	# standing on one cell forever, not enough to send it anywhere.
	putter.considerations.append(_consideration(UtilityContext.INPUT_UNVISITED, 1.0, _floored(0.5)))

	var patrol := _search_verb(&"patrol", &"PATROL", "Patrol")
	# Progress-only: a step that does not close on the point it is heading for is
	# not patrolling, it is milling about. Same curve the seek actions use, and the
	# same reason - see `_progress_only`.
	patrol.considerations.append(
		_consideration(UtilityContext.INPUT_CLOSES_TO_PATROL, 1.0, _progress_only())
	)

	# --- flank and suppress (taskblock-46 Pass E) -----------------------------
	#
	# **The two rows of Trained's tier entry that map onto executors that already
	# exist.** `flank` is a move, `suppress` is a burst. `call for help`, `use item`,
	# and Elite's `bait`/`ambush` have no executor in `src/logic/actions/` and are
	# NOT authored here — inventing one would be exactly the new machinery
	# `PLAN.md` says the tier table does not need, and a `.tres` naming an executor
	# that does not exist would silently never build.

	var flank := UtilityActionDef.new(&"flank", UtilityExecutors.MOVE)
	flank.display_name = "Flank"
	flank.base_weight = 1.1
	flank.tiers = TRAINED_AND_ABOVE
	flank.preconditions = [
		UtilityContext.PRED_ENEMY_KNOWN,
		UtilityContext.PRED_CELL_IS_ELSEWHERE,
		UtilityContext.PRED_LOF_POSSIBLE,
	]
	flank.considerations = [
		# Unfloored on purpose: a cell squarely in front of the target is not a
		# flank at all, and scoring it as a weak one would let `flank` win the
		# ordinary approach it is supposed to be an alternative to.
		_consideration(UtilityContext.INPUT_FLANK_ANGLE, 1.0, ResponseCurve.new()),
		_consideration(UtilityContext.INPUT_LINE_OF_FIRE, 1.0, ResponseCurve.new()),
		_consideration(UtilityContext.INPUT_STANDOFF_MATCH, 1.0, _floored(0.25)),
		# A flank is a bet that the angle is worth the walk. The lookahead is what
		# tells an Elite unit whether the flanking cell is also the cell that puts it
		# in front of everyone else.
		_predicted_threat(),
	]

	var suppress := UtilityActionDef.new(&"suppress", &"burst")
	suppress.display_name = "Suppress"
	suppress.base_weight = 1.3
	suppress.repeatable = true
	suppress.tiers = TRAINED_AND_ABOVE
	suppress.preconditions = [
		UtilityContext.PRED_HAS_WEAPON,
		UtilityContext.PRED_ENEMY_KNOWN,
		UtilityContext.PRED_WEAPON_REACHES,
		UtilityContext.PRED_LOF_POSSIBLE,
		UtilityContext.PRED_CELL_IS_CURRENT,
	]
	suppress.considerations = [
		_consideration(UtilityContext.INPUT_LINE_OF_FIRE, 1.0, ResponseCurve.new()),
		_consideration(UtilityContext.INPUT_STANDOFF_MATCH, 1.0, _floored(0.25)),
		_consideration(BatchObjective.input_id_for(&"hold"), 1.0, _floored(OBJECTIVE_FLOOR)),
	]

	return [
		approach,
		flank,
		gather,
		hold,
		hunt,
		overwatch,
		patrol,
		putter,
		roam,
		seek_extraction,
		seek_objective,
		shoot,
		suppress,
		take_cover,
	]


## The shared shape of a search verb: it moves, it only applies when this unit is
## the one assigned that behaviour, and it only applies when there is nobody to
## fight. What differs between the four is the consideration the caller appends.
func _search_verb(id: StringName, behaviour: StringName, display: String) -> UtilityActionDef:
	var verb := UtilityActionDef.new(id, UtilityExecutors.MOVE)
	verb.display_name = display
	# Below the combat and mission actions: searching is what a unit does when it
	# has nothing better, and "nothing better" is already expressed by those
	# actions' own gates failing. Flagged, not tuned.
	verb.base_weight = 0.8
	verb.preconditions = [
		UtilityContext.PRED_ENEMY_UNKNOWN,
		UtilityContext.PRED_FREE_TO_SEARCH,
		UtilityContext.PRED_CELL_IS_ELSEWHERE,
		UtilityContext.search_predicate_for(behaviour),
	]
	return verb


## The four coarse calls a batch LEADER picks between, scored from the leader's own
## cell against the same scorer and the same profile as everything else.
##
## **`flank` has no consumer in the Pass B action pool and that is stated rather
## than hidden.** Nothing here serves it, so a batch under a flank objective is
## damped roughly uniformly and behaves close to an unled one. Its consumer is a
## `flank` ACTION, which `PLAN.md`'s *fill in the tier table* adds as a `.tres`
## alongside suppress and call-for-help; the objective ships now because Pass C's
## requirement is that the mechanism stand up on its own the moment bouts assign
## batches, not that every objective already have somewhere to land.
func _objectives() -> Array[UtilityActionDef]:
	var advance := _objective(&"advance", "Advance")
	# A healthy squad pushes.
	advance.considerations = [
		_consideration(UtilityContext.INPUT_OWN_INTEGRITY, 1.0, _floored(0.2))
	]

	var hold := _objective(&"hold", "Hold")
	# Already at a workable distance with a line — stay and shoot.
	hold.considerations = [
		_consideration(UtilityContext.INPUT_STANDOFF_MATCH, 1.0, _floored(0.2)),
		_consideration(UtilityContext.INPUT_LINE_OF_FIRE, 1.0, _floored(0.2)),
	]

	var withdraw := _objective(&"withdraw", "Withdraw")
	# A hurt squad pulls back.
	withdraw.considerations = [
		_consideration(UtilityContext.INPUT_OWN_INTEGRITY, 1.0, _floored(0.15, true))
	]

	var flank := _objective(&"flank", "Flank")
	# No line from where the leader stands — go around rather than trade.
	flank.considerations = [
		_consideration(UtilityContext.INPUT_LINE_OF_FIRE, 1.0, _floored(0.15, true))
	]

	return [advance, flank, hold, withdraw]


## An objective row. `executor_id` is `&"objective"` and is never built — see
## `DataLibrary.TYPE_BATCH_OBJECTIVES` for why the action type is reused.
func _objective(id: StringName, display_name: String) -> UtilityActionDef:
	var objective := UtilityActionDef.new(id, &"objective")
	objective.display_name = display_name
	objective.base_weight = 1.0
	objective.preconditions = [UtilityContext.PRED_ENEMY_KNOWN]
	return objective


func _profiles() -> Array[UtilityProfile]:
	# Two profiles at opposite ends of one axis, for the same reason the block
	# picks two tiers at opposite ends of theirs: the gap has to be large enough
	# that "these decide differently" is a real assertion rather than a rounding
	# difference. The middle of the table is `PLAN.md`'s, not this block's.
	var aggressive := UtilityProfile.new(&"aggressive", "Aggressive")
	aggressive.action_weights = {
		&"approach": 1.6,
		&"flank": 0.9,
		&"shoot": 1.4,
		&"suppress": 1.2,
		&"take_cover": 0.35,
		&"hold_position": 0.2,
		# The retired planner's "AGGRESSIVE never overwatches — closes and fires,
		# doesn't wait" was a hard `if` in the planner. It is this number now.
		&"overwatch": 0.05,
	}
	aggressive.consideration_weights = {
		UtilityContext.INPUT_CLOSES_DISTANCE: 1.0,
		UtilityContext.INPUT_COVER: 0.5,
		# **An aggressive unit is indifferent to range.** A weight above 1.0 clamps
		# the consideration toward 1.0 and therefore toward being a no-op, which is
		# how "ignore this input" is expressed in a product model — there is no
		# other way to say it, since every factor can only damp.
		#
		# The retired planner said the same thing with `AGGRESSIVE_PREFERRED_RANGE =
		# 0`: close to contact, do not hold a standoff. Losing that is what dropped
		# the completion rate below its floor — units hung back at their weapon's
		# effective range trading shots instead of closing, so fights neither
		# resolved nor ended.
		UtilityContext.INPUT_STANDOFF_MATCH: 4.0,
	}

	var cautious := UtilityProfile.new(&"cautious", "Cautious")
	cautious.action_weights = {
		&"approach": 0.45,
		&"flank": 1.4,
		&"shoot": 1.0,
		&"suppress": 1.0,
		&"take_cover": 1.8,
		&"hold_position": 0.9,
		&"overwatch": 1.3,
	}
	cautious.consideration_weights = {
		UtilityContext.INPUT_CLOSES_DISTANCE: 0.6,
		UtilityContext.INPUT_COVER: 1.0,
	}

	# taskblock-46 Pass E: two more rows, on the axis that can actually carry them.
	#
	# **All four differ in `action_weights` and barely at all in
	# `consideration_weights`**, which is not laziness — it is the trap documented at
	# the top of this file. A weight on an input two actions read in opposite
	# directions says two contradictory things at once, and most of the interesting
	# inputs (`own_integrity` above all) are read in both directions somewhere in the
	# pool. Action weights are unambiguous, so that is where personality lives until
	# `UtilityContext` publishes a harm input separate from a health one.

	var defensive := UtilityProfile.new(&"defensive", "Defensive")
	# Holds ground and makes the enemy come. The distinguishing move is overwatch:
	# it is the only profile that would rather wait with a shot than take a worse
	# one now.
	defensive.action_weights = {
		&"approach": 0.3,
		&"flank": 0.4,
		&"shoot": 1.0,
		&"suppress": 1.1,
		&"take_cover": 1.5,
		&"overwatch": 2.0,
		&"hold_position": 1.4,
		# **Holding ground means not leaving it**, and that has to be said out loud.
		# Left unstated this defaulted to 1.0, and a hurt defensive unit withdrew
		# exactly as readily as a cowardly one — the two profiles came out
		# indistinguishable, which the tier/profile table test caught. An absent
		# weight is a neutral opinion, and "defensive" is not neutral about retreat.
		&"seek_extraction": 0.4,
	}
	defensive.consideration_weights = {UtilityContext.INPUT_COVER: 1.0}

	var cowardly := UtilityProfile.new(&"cowardly", "Cowardly")
	# Wants out. Cover over everything, closing barely at all, and the only profile
	# that weights leaving the map above fighting on it.
	cowardly.action_weights = {
		&"approach": 0.1,
		&"flank": 0.15,
		&"shoot": 0.6,
		&"suppress": 0.5,
		&"take_cover": 2.2,
		&"overwatch": 0.8,
		&"hold_position": 1.2,
		&"seek_extraction": 2.0,
	}
	cowardly.consideration_weights = {
		UtilityContext.INPUT_CLOSES_DISTANCE: 0.3,
		UtilityContext.INPUT_COVER: 1.0,
	}

	return [aggressive, cautious, defensive, cowardly]
