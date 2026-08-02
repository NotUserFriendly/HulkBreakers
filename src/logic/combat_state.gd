class_name CombatState
extends RefCounted

## taskblock-18 C2: "units within the same speed band resolve
## simultaneously for playback... a band tolerance (units within epsilon
## speed) groups them; tunable, flagged default." See simultaneous_group()
## below.
const SIMULTANEOUS_BAND_TOLERANCE := 1.0

## taskblock-47 Pass A: turns handed out since the last reset, across every
## `CombatState` in the process. **Diagnostics only, never read by a decision.**
##
## Counted at `advance_turn` rather than in `BoutRunner` on purpose: a turn is a
## turn whether a bout runner drove it or a test drove it by hand, and counting it
## in the runner would report zero for exactly the scripted tests taskblock-47 Pass
## E is trying to move work toward.
static var turns_resolved: int = 0
## Bouts built since the last reset — the coarse counterpart to `turns_resolved`.
static var bouts_built: int = 0
## taskblock-51 (`BR26.02`): **speculative state clones.**
##
## `ActionQueue.preview()` clones the whole state, and `Grid.dup()` deep-copies every
## blocker part and every surface with it — measured at **26 784 usec** on a 214-blocker
## board, more than twice a `ShotPlane.build`. That cost was invisible because nothing
## counted it, and it was reached from the aim view several times per mouse motion.
##
## Counted here for the same reason `bouts` and `turns` are: a cost nobody can see is a
## cost nobody can budget, and this one was large enough to take the framerate to 8 fps
## without ever appearing in a profile.
static var dups: int = 0

var grid: Grid
var units: Array[Unit] = []  # the roster — no longer literally turn order, see below
var squads: Dictionary = {}  # squad_id(int) -> Array[Unit]
## docs/10 taskblock02 F1 (tb31 Pass B): squad_id(int) -> Enums.
## SquadController. Absent entries default to UNASSIGNED (controller_for)
## — a bout must never actually run with one still unset
## (`BoutRunner._init()`'s own hard error). `assign_all_to_human()`/
## `assign_rest_to_ai()` below are the explicit authoring shortcuts for
## "Control All Squads"/"mostly AI," replacing the old silent HUMAN
## default.
var squad_controllers: Dictionary = {}
## The actual round number (docs/09 LogEvent.turn) — a round is "every
## living unit has acted once," not "one more unit acted"; incremented in
## advance_turn() only when the acted-this-round set exhausts, never on
## every single turn.
var round_number: int = 0
var action_log: Array[String] = []
var rng: RandomNumberGenerator
## Structured log (docs/09) — no sinks by default; the caller wires whichever
## it wants (Memory/Stdout/File/UI). Every impact and abort in resolve_turn()
## emits here.
var combat_log: CombatLog = CombatLog.new()
## taskblock-43 Pass C: the AI's own round-scoped batch plans (`BatchPlan`).
## Per-bout, like `combat_log` and `rng` above, because a batch's leader records
## a plan on its turn that a follower reads on a LATER turn in the same round —
## there is nowhere else with that lifetime. A planner memo only: nothing in
## resolution reads it, and it is empty for every bout that never assigns a
## `Unit.batch_id` (all of them, until one is assigned by hand).
var batch_plans: BatchPlan = BatchPlan.new()
## Shared across the whole battle (docs/03) so every attack resolves DT and
## ricochet against the same tuning, not a fresh default per shot.
var material_table: MaterialTable = DataLibrary.material_table()

## taskblock-52 `BR52.11`: **the ONE origin seed this whole bout was generated
## from** — map, spawns, loadouts and combat rolls all descend from it. Set by the
## two things that generate a playable bout (`BoutSetup.build_bout` and
## `BattleScene._seed_battle`); `BattleScene.load_battle` logs it unconditionally
## as the bout's first line, so no caller can produce a bout that failed to record
## how to reproduce it.
##
## **Deliberately not `rng.seed`.** Both generators seed a local RNG with the origin
## number and then hand `rng.randi()` to `CombatState.new` — so `rng.seed` is a
## *derived* value that cannot regenerate the map. Logging it would look correct and
## replay nothing, which is a worse failure than the missing line this replaced.
##
## Lives here rather than in the constructor because `CombatState.new` has 733 call
## sites and almost none of them are bouts anyone replays. **0 is a real seed**, not
## a sentinel — `GenerateBoutOverlay` uses it as the fallback for unparseable input —
## so a hand-built fixture state genuinely reports seed 0 rather than pretending to
## be unset.
var bout_seed: int = 0

## taskblock-52: which model resolves this bout's shots — `ShotResolution.
## RESOLVER_RAY` (the ray chain, **the default since Pass F**) or `RESOLVER_PLANE`
## (the shot plane, still built and still selectable by this one field). Per-bout
## rather than a global static so a differential run can put the same board through
## both without mutating shared state, and so a test that switches resolvers cannot
## leak into the next one.
##
## **The inversion landed in taskblock-52 Pass F.** The parity case it rests on:
## over 216 seeded shots, zero cases where the plane hit and the ray missed against
## 64 the other way; hit points lying on the surface they claim to strike 100/152
## against 216/216; release build 6 715 -> 2 021 usec per shot, and a 12-round burst
## 148 829 -> ~24 256 usec, because the amortisation the plane was credited with is
## not something it performs (a 12-round burst builds 20 planes).
##
## **The two model differences that moved fixtures, kept here because they are what a
## reader hits first when a shot behaves differently than an old comment claims:**
##
## **1. A round continues while it still has damage.** Floors are real geometry now,
## so a round punches through its target and goes on to strike the deck — a burst of
## 12 logs 36 impacts, not 12. It does **not** march forever: `RayChain` returns the
## moment `spill <= 0.0`. A pellet that penetrates that effectively is a **balance**
## question for when ammo types land, not a resolver one. The consequence for tests
## is that an impact **count** is no longer a proxy for "one attack fired" or "the
## round reached its target"; assert on which surface was met first.
##
## **2. A shot is no longer level.** **The plane modelled a shot as travelling at a
## constant height** — `_find_next` tested every region at the aim point's own `y`,
## so a round fired from a 1.25 muzzle at a 0.5 chest sat at 0.5 the whole way and
## clipped anything 0.6 tall in between. **The chain marches muzzle-to-aim-point,
## which slopes.** A real round does slope, so the chain is right and the old
## fixtures encoded the level-shot approximation.
##
## `ShotPlane.self_obstruction` (tb22 H2) was deleted rather than kept alongside the
## chain's geometric answer to the same question — two answers to one question is the
## parallel system this project keeps removing. `docs/SUPERSEDED.md` records both.
##
## Spelled as a literal rather than as `ShotResolution.RESOLVER_RAY` only to keep
## a class-level default free of a cross-class static read;
## `test_resolver_parity.gd` asserts the two spellings are the same value, so they
## cannot drift.
var shot_resolver: StringName = &"ray"
## docs/10 taskblock05 E1: what a mangling Part.mangles_into resolves
## against — shared across the whole battle, same convention as
## material_table above. taskblock-16 Pass B: FieldObjects (hardcoded
## factories) is retired — every wreckage kind is a real `.tres` loaded
## through DataLibrary now, same as any other part.
var wreckage_pool: Array[Part] = [
	DataLibrary.get_part(&"twisted_sheet_metal"), DataLibrary.get_part(&"metal_scraps")
]
## True only on a dup() built for a TACTICS-time preview (docs/09). An
## attack's hit/damage outcome is the one genuinely probabilistic effect a
## preview must never resolve — not because randomness is expensive, but
## because a preview that *did* accurately predict it would make "the world
## moved" abort case at RESOLUTION unreachable: queuing would already have
## rejected anything RESOLUTION could later invalidate, since both would
## agree. AttackAction checks this to skip real damage resolution here.
var is_preview: bool = false

## taskblock-29 Pass A: true only for the synchronous span of an active
## `resolve_until()` call — `BoutInjector`'s own guard against a
## mid-resolution mutation, the same "mutate only at a two-phase turn
## boundary" discipline docs/09 already states for TACTICS/RESOLUTION,
## applied to the debug injection channel too. Never set anywhere else.
var is_resolving: bool = false
## taskblock-29 Pass C: true the instant ANY `BoutInjector` verb has ever
## mutated this bout — injection is a deliberate determinism break
## (docs/00: "same seed = same battle, always" no longer holds once
## something outside the seed touched it), so this flags it for good,
## never cleared. False (the default, unchanged) for every ordinary,
## un-injected bout.
var was_injected: bool = false

var _next_id: int = 0
## taskblock-18 C1: "turn order within a round is by resolution speed —
## fastest unit acts first... the SAME speed the resolver uses, not a
## second stat," replacing the old squad-sequential array-index walk.
## The id of whichever unit currently has AP/MP live; -1 before the very
## first turn of a round ever starts (an empty roster). Never trust a
## stored Unit reference across states (docs/09) — `current_unit()` always
## re-resolves through `find_unit()`.
var _current_unit_id: int = -1
## Unit ids that have already had `_start_turn()` called on them THIS
## round (the current unit included, from the moment its turn began) —
## cleared the instant `advance_turn()` finds no living, not-yet-acted
## candidate left and starts a fresh round.
var _acted_this_round: Array[int] = []
## taskblock-19 Pass F: "take its turn after the next ally instead" — the
## id of a unit that declared Hold and is waiting to resume, or -1. Set by
## `begin_hold()`; `_hold_ready` flips true the instant ONE more unit's
## turn has been handed out after that, so the FOLLOWING `advance_turn()`
## call (that next unit ending ITS turn) resumes the held unit directly
## instead of picking by initiative again.
var _held_unit_id: int = -1
var _hold_ready: bool = false


## `combat_seed` seeds all rolls made during this fight (Appendix A: hit
## resolution must be reproducible from a seed).
static func reset_diagnostics() -> void:
	turns_resolved = 0
	bouts_built = 0
	dups = 0


func _init(p_grid: Grid, initial_units: Array[Unit] = [], combat_seed: int = 0) -> void:
	grid = p_grid
	rng = RandomNumberGenerator.new()
	rng.seed = combat_seed
	for unit: Unit in initial_units:
		add_unit(unit)
	var living: Array[Unit] = units.filter(_can_take_a_turn)
	if not living.is_empty():
		_begin_turn(_fastest_by_initiative(living))


## Registers a unit (assigning it an id if it doesn't have one), occupies its
## cell, and adds it to turn order and its squad. Used both for initial roster
## setup and for units spawned mid-combat (ImplantAction) — and for dup()'s
## own re-registration of every unit, dead ones included, onto a fresh
## clone's grid. A dead unit never occupies a cell (kill_unit's own rule),
## so this must not blindly re-mark one on a clone just because it's being
## re-added to a fresh `units` array.
func add_unit(unit: Unit) -> void:
	if unit.id == -1:
		unit.id = _next_id
		_next_id += 1
	units.append(unit)
	if not squads.has(unit.squad_id):
		squads[unit.squad_id] = []
	squads[unit.squad_id].append(unit)
	if unit.alive:
		grid.set_occupant_id(unit.cell, unit.id)
	# taskblock-37 Pass D: `height` — the real continuous world height
	# (ramp-aware), re-derived from THIS grid at registration time — the
	# same grid `dup()`'s own clone re-registration passes in, so a
	# cloned unit's height stays consistent with whatever its cell
	# actually carries on that specific grid.
	unit.height = UnitGeometry.true_height_for_cell(unit.cell, grid)
	# taskblock-39 Pass C: `level` derived FROM height now, not `Grid.
	# level` directly — the placement model's own Surface.height is the
	# real source of truth; `level` survives only as the whole-level-count
	# convenience tests and debug tooling read.
	unit.level = unit.height / UnitGeometry.LEVEL_HEIGHT
	_log_unit_assembled(unit)


## taskblock-41 Pass D: "bot constructed, part attached." Logged HERE, at the
## moment an assembled unit enters the world, rather than inside
## `DeepStrike`/`BodyAssembler`/`PartGraph.attach` — those are pure static
## logic with no `CombatLog` in reach, and threading one down into them would
## push a diagnostic concern into the deepest layer of the codebase to buy a
## per-socket event nobody asked for. The parts are listed in the order
## `all_parts()` walks the socket tree, so "what did this bot actually get
## built out of, and in what order" is answerable from the log alone.
func _log_unit_assembled(unit: Unit) -> void:
	var part_ids := PackedStringArray()
	for part: Part in unit.shell.all_parts():
		part_ids.append(String(part.id))
	combat_log.emit(
		LogEvent.new(
			round_number,
			Enums.Phase.TACTICS,
			unit.id,
			&"unit_assembled",
			{"unit": unit.id, "squad": unit.squad_id, "cell": unit.cell, "parts": part_ids},
			(
				"unit %d assembled for squad %d at %s from %d parts: %s"
				% [unit.id, unit.squad_id, unit.cell, part_ids.size(), ", ".join(part_ids)]
			)
		)
	)


## The one place a unit's alive flag flips to false (docs/09 "if it changed
## the world, it's in the log" — the world-state half of that: a dead unit
## stops occupying its cell, same as MoveAction vacates a cell it steps off
## of, so its corpse never permanently blocks the grid for `Pathfinder`.
## `grid.field_items`/`blockers` (loot, dropped subtrees, cover) are a
## separate overlay untouched by this — a cell can be walkable and still
## hold something to pick up.
## taskblock-51 (`BR51.04`/`BR51.05`): **killing the current unit advances the turn.**
##
## This marked the unit dead and cleared its cell and stopped, leaving `_current_unit_id`
## pointing at a corpse. Two symptoms followed from that one stranded pointer: the turn
## never ended, and — because `SelectionController.select` requires `unit ==
## current_unit()` — **nothing else could be selected either**, which is why the supervisor
## reported "cannot select a unit" alongside "the turn does not end".
##
## `EndTurnAction` was already documented as advancing *"even if the current unit just
## died"*, so the rule existed; what was missing was anything invoking it when the death
## happened outside an action's own resolution, which is exactly what a debug `kill` or a
## meltdown does.
##
## **Not while resolving.** A shot that kills the current unit mid-queue must not reorder
## the turn under the resolver's feet — `resolve_until` already stops on the death and the
## turn ends through the ordinary path. The guard is what keeps this a fix for the
## outside-an-action case rather than a second turn-advancing mechanism racing the first.
func kill_unit(unit: Unit) -> void:
	if not unit.alive:
		return
	unit.alive = false
	grid.set_occupant_id(unit.cell, -1)
	if not is_resolving and unit.id == _current_unit_id:
		advance_turn()


func current_unit() -> Unit:
	return find_unit(_current_unit_id)


## taskblock-29 Pass B: `BoutInjector`'s own "make a unit the current
## unit" trigger verb — deliberately distinct from `_begin_turn` (which
## also runs `_start_turn`'s own AP/MP/facing/overwatch reset): forcing
## whose turn it is must never silently ALSO refill the unit's resources,
## since a scenario may want to force a specific low-AP/mid-turn state
## and just needs the engine to agree who's acting. No other caller may
## use this — normal turn advancement always goes through `_begin_turn`/
## `advance_turn`.
func force_current_unit(unit_id: int) -> void:
	_current_unit_id = unit_id


## The unit with this id, or null. Actions resolve their target through
## this rather than holding a bare Unit reference across states — a
## preview's units are independent clones (docs/09) sharing the same id,
## not the same object, so an identity comparison against a stored
## reference would wrongly read as "not this state's unit."
func find_unit(id: int) -> Unit:
	for unit: Unit in units:
		if unit.id == id:
			return unit
	return null


## docs/10 taskblock02 F1 (tb31 Pass B): UNASSIGNED unless a squad was
## explicitly set — no silent side picked. `BoutRunner._init()` is where
## this actually gets enforced: running a bout with any squad still
## reading UNASSIGNED is a hard construction error, never a guess.
func controller_for(squad_id: int) -> Enums.SquadController:
	return squad_controllers.get(squad_id, Enums.SquadController.UNASSIGNED)


func set_squad_controller(squad_id: int, controller: Enums.SquadController) -> void:
	squad_controllers[squad_id] = controller


## Every distinct squad_id actually present on the board right now — the
## set `controller_for` assignment is checked against (a squad with no
## units doesn't need one).
func present_squad_ids() -> Array[int]:
	var seen: Dictionary = {}
	for unit: Unit in units:
		seen[unit.squad_id] = true
	var ids: Array[int] = []
	for squad_id: int in seen.keys():
		ids.append(squad_id)
	return ids


## True if every squad actually present has a real (non-UNASSIGNED)
## controller — what `BoutRunner._init()` requires before a bout may run.
func all_squads_assigned() -> bool:
	for squad_id: int in present_squad_ids():
		if controller_for(squad_id) == Enums.SquadController.UNASSIGNED:
			return false
	return true


## Authoring convenience (tb31 Pass B): "Control All Squads," explicit —
## every squad actually present becomes HUMAN. Replaces the old silent
## HUMAN default; a caller that wants that behavior now says so.
func assign_all_to_human() -> void:
	for squad_id: int in present_squad_ids():
		set_squad_controller(squad_id, Enums.SquadController.HUMAN)


## Authoring convenience (tb31 Pass B): the "mostly AI" shortcut —
## `human_squads` become HUMAN, every other squad actually present becomes
## AI. Where "far more AI than HUMAN units" belongs: a visible shortcut a
## caller opts into, not a hidden getter default.
func assign_rest_to_ai(human_squads: Array[int]) -> void:
	for squad_id: int in present_squad_ids():
		var controller: Enums.SquadController = (
			Enums.SquadController.HUMAN if squad_id in human_squads else Enums.SquadController.AI
		)
		set_squad_controller(squad_id, controller)


func log_action(text: String) -> void:
	action_log.append(text)


## A fully independent copy — grid, every unit's whole shell tree, ground
## items — for TACTICS-time speculative previews (docs/09): ActionQueue
## replays already-queued actions onto a dup() to preview the next one.
## Marked `is_preview` so a replayed AttackAction spends AP but skips real
## damage resolution — structural mutations (move, swap, pick up) still
## replay for real against this disposable copy, since those aren't
## probabilistic. `action_log`/`combat_log` start empty — a preview's own
## log noise is never worth keeping.
func dup() -> CombatState:
	dups += 1
	var cloned_units: Array[Unit] = []
	for unit: Unit in units:
		cloned_units.append(unit.dup())

	var cloned := CombatState.new(grid.dup(), [], rng.seed)
	cloned.is_preview = true
	cloned.squad_controllers = squad_controllers.duplicate()
	cloned.material_table = material_table
	cloned.wreckage_pool = wreckage_pool
	# taskblock-52: a preview must resolve shots the same way the real bout will,
	# or the number the UI shows and the number resolution produces come from two
	# different models — which is exactly the pillar docs/08 is built on.
	cloned.shot_resolver = shot_resolver
	cloned.bout_seed = bout_seed
	for unit: Unit in cloned_units:
		cloned.add_unit(unit)
	cloned._current_unit_id = _current_unit_id
	cloned._acted_this_round = _acted_this_round.duplicate()
	cloned.round_number = round_number
	cloned._held_unit_id = _held_unit_id
	cloned._hold_ready = _hold_ready
	# taskblock-29 Pass C: a preview built FROM an injected bout is still,
	# transitively, not a clean seed-replay — carried through for
	# consistency. `is_resolving` is deliberately NOT copied: a fresh dup()
	# is never itself mid-resolution, whatever the source state's own
	# instantaneous flag happened to read (dup() is only ever called
	# between resolve_until() calls in practice, but this makes it true by
	# construction rather than by calling convention).
	cloned.was_injected = was_injected
	# taskblock-44 Pass C: `batch_plans` is deliberately NOT copied, and this
	# comment is the point — taskblock-43 left it neither carried nor explained,
	# which is the state `is_resolving` above exists to demonstrate the fix for.
	# A dup() is a TACTICS-time speculative preview (docs/09). A batch plan is a
	# record of what the AI decided during a real turn, and a preview neither
	# takes turns nor leads a batch, so carrying one would let a throwaway clone
	# answer "who is leading this round" — a question only the real bout can
	# answer. A fresh, empty `BatchPlan` is correct by construction, not an
	# oversight. `WorldView` is likewise never cloned: it is built per plan from
	# whichever state is being planned against, so a preview gets a view over the
	# preview, which is exactly right.
	return cloned


## docs/09 taskblock06 Pass D: kept for every existing caller that just
## wants "run the queue" with no interest in the outcome — a thin wrapper
## over resolve_until(), which owns the real logic now. Discards the
## Outcome; the STOPPED case is already fully logged by resolve_until
## itself, so nothing is silently lost by ignoring the return value here.
func resolve_turn(queue: ActionQueue) -> void:
	resolve_until(queue)


## Executes `queue`'s actions in order against this (authoritative) state,
## re-validating each one first (docs/09): the world may have moved since
## it was queued against a mere preview.
##
## docs/09 taskblock06 D1/D2: RESOLUTION is a loop with re-entry now, not
## one atomic pass — TACTICS -> RESOLUTION -> (interrupt) -> TACTICS ->
## RESOLUTION -> .... Stops the instant the next thing to happen is no
## longer legal (never "abort this one and keep going," taskblock02 F's
## rule, reversed) and returns control to just this unit
## (docs/10 taskblock06 D4 — other units' own queues are unaffected,
## since each is resolved by its own separate call). A MoveAction is
## re-checked at cell granularity too (MoveAction.apply_stepwise,
## `mid_move_hook` — Pass F's Overwatch trigger plugs in there later),
## since a queued move can turn illegal partway through even though the
## path itself never changed (a lost leg lowering mp_per_ap, say).
##
## Returns `{"kind": Enums.ResolveOutcome.COMPLETED}` or
## `{"kind": STOPPED, "unit": Unit, "reason": StringName, "refund": {"ap":
## int, "mp": float}}` — docs/09 taskblock06 D3: AP always stays spent (it
## already bought whatever MP got used), MP is whatever the interrupted
## unit's own pool holds at the stopping point (there is nothing extra to
## credit — the AP-to-MP conversion only ever buys as much as the very
## next step needs).
func resolve_until(queue: ActionQueue, mid_move_hook: Callable = Callable()) -> Dictionary:
	# taskblock-29 Pass A: `is_resolving` wraps the WHOLE body regardless of
	# which of the three return paths below actually fires — GDScript has
	# no try/finally, so the body is split out into its own function and
	# the flag set/cleared once, here, around the single call to it.
	is_resolving = true
	var outcome: Dictionary = _resolve_until_body(queue, mid_move_hook)
	is_resolving = false
	return outcome


func _resolve_until_body(queue: ActionQueue, mid_move_hook: Callable) -> Dictionary:
	for action: CombatAction in queue.actions:
		if not action.is_legal(self):
			# taskblock-41 Pass C: the refused action is named, not just
			# counted. "stopped (next_action_illegal)" told you a queue died
			# without telling you which action killed it — the one thing you
			# actually need to reproduce it.
			return _stopped(queue.unit, &"next_action_illegal", action)
		if action is MoveAction:
			var result: Dictionary = (action as MoveAction).apply_stepwise(self, mid_move_hook)
			if result.stopped:
				return _stopped(queue.unit, &"mid_move_interrupt", action)
		else:
			action.apply(self)
	return {"kind": Enums.ResolveOutcome.COMPLETED}


func _stopped(unit: Unit, reason: StringName, action: CombatAction = null) -> Dictionary:
	var actual: Unit = find_unit(unit.id)
	var outcome: Dictionary = {
		"kind": Enums.ResolveOutcome.STOPPED,
		"unit": actual,
		"reason": reason,
		"refund": {"ap": 0, "mp": actual.mp if actual != null else 0.0},
	}
	var described: String = action.describe() if action != null else ""
	var text: String = "resolve_until: unit %d stopped (%s)" % [unit.id, reason]
	if described != "":
		text += " on %s" % described
	log_action(text)
	combat_log.emit(
		LogEvent.new(
			round_number,
			Enums.Phase.RESOLUTION,
			unit.id,
			&"resolution_stopped",
			{"reason": reason, "refund_mp": outcome.refund.mp, "action": described},
			"stopped (%s)%s" % [reason, "" if described == "" else " on %s" % described]
		)
	)
	return outcome


## Attempts an action: rejects (returns false, no mutation) if illegal,
## otherwise applies it and returns true.
##
## taskblock-41 Pass C: the refusal is no longer silent — this was one of the
## genuinely quiet `return false` paths, indistinguishable from an action that
## ran and did nothing. `is_legal()` is a plain bool across every action, so the
## reason available here is `action_illegal` plus the action's own
## `describe()`; a per-action legality REASON would mean changing `is_legal`'s
## signature everywhere, which is deliberately out of this pass's scope and
## flagged rather than half-done.
func try_apply(action: CombatAction) -> bool:
	var described: String = action.describe()
	CommandLog.issued(self, &"try_apply", {"action": described, "unit": action.unit_id()})
	if not action.is_legal(self):
		return CommandLog.refused(
			self, &"try_apply", &"action_illegal", {"action": described, "unit": action.unit_id()}
		)
	action.apply(self)
	CommandLog.accepted(self, &"try_apply", {"action": described, "unit": action.unit_id()})
	return true


func _start_turn(unit: Unit) -> void:
	# taskblock-20 Pass F: batteries recharge from the shell's own reactor
	# output BEFORE max_ap is recomputed from the now-topped-up state — "the
	# first bit of movement is free tempo," this is the power-side
	# equivalent, the same turn-start seam. A shell with no power system at
	# all (no reactor/battery ever attached — every shell built before this
	# pass) leaves `max_ap` completely untouched, so nothing not opted into
	# the power system changes behavior.
	# taskblock-42 Pass C (BR27.09 cost #3): ONE socket-tree walk, threaded
	# through everything below. Measured before this change: five full walks per
	# turn start (`recharge_batteries`, `has_power_system`, `max_ap_for` ×3
	# internally, `discharge_batteries`, `mp_per_ap`), which is exactly the
	# "5-6 times" BR27.09 recorded.
	var all_parts: Array[Part] = unit.shell.all_parts()
	var operable: Array[Part] = Shell.operable_from(all_parts)
	PowerResolver.recharge_batteries(unit.shell, operable)
	if PowerResolver.has_power_system(unit.shell, all_parts):
		unit.max_ap = PowerResolver.max_ap_for(unit, operable)
	unit.ap = unit.max_ap
	# taskblock-20 Pass F: batteries give up whatever they just contributed
	# to THIS turn's max_ap — a shell drawing on battery power has less
	# available next turn unless recharge offsets it (recharge already ran
	# above, using last turn's own charge, before this drains it).
	PowerResolver.discharge_batteries(unit.shell, operable)
	# taskblock-08 Pass C: leftover MP from a prior turn is discarded
	# (Appendix E), but every turn starts with one AP's worth of MP
	# already banked, free — a turn-start grant, not a permanent mp_per_ap
	# change, so the AP itself is never spent and stays fully available.
	# "The first bit of movement is free tempo."
	unit.mp = unit.mp_per_ap(operable)
	# docs/10 taskblock03 E2: the free-refacing unlock is a per-turn toll,
	# not a permanent one — a new turn always starts locked again.
	unit.facing_unlocked = false
	# docs/09 taskblock06 Pass F: overwatch is spent the instant it fires,
	# but an UNTRIGGERED watch also lapses once its own next turn comes
	# around — it was holding against threats that turn, not forever.
	unit.overwatch_weapon_id = &""
	var tier_before: SurrogateTier = unit.surrogate_tier
	LifeSupport.tick(unit, SurrogateLadder.default_ladder())
	# taskblock-09 A4: MELTDOWN countdowns tick on the same seam LifeSupport
	# already uses — the mutation (a part's own countdown, and detonate()'s
	# real damage if one expires) always runs, preview or not, exactly like
	# LifeSupport.tick() above; only the LOGGING below is preview-gated.
	var meltdowns: Array[Dictionary] = DamageResolver.tick_meltdowns(unit, self)

	if not is_preview:
		# The one place turn/unit gets announced at all now (LogEvent._to_
		# string() no longer echoes either per line) — everything else this
		# unit does for the rest of its turn is understood to still be it.
		combat_log.emit(
			LogEvent.new(
				round_number,
				Enums.Phase.RESOLUTION,
				unit.id,
				&"turn_start",
				{},
				"Turn %d — unit %d" % [round_number, unit.id]
			)
		)
		if unit.surrogate_tier != tier_before:
			combat_log.emit(
				LogEvent.new(
					round_number,
					Enums.Phase.RESOLUTION,
					unit.id,
					&"surrogate_demoted",
					{
						"from": tier_before.id,
						"to": unit.surrogate_tier.id,
						"cause": "organics_decay"
					},
					"%s -> %s (organics decay)" % [tier_before.id, unit.surrogate_tier.id]
				)
			)
		for entry: Dictionary in meltdowns:
			var part: Part = entry.part
			var affected: Array[Unit] = entry.units
			var affected_ids: Array = []
			for affected_unit: Unit in affected:
				affected_ids.append(affected_unit.id)
			combat_log.emit(
				LogEvent.new(
					round_number,
					Enums.Phase.RESOLUTION,
					unit.id,
					&"detonate",
					{"source_part": part.id, "units": affected_ids, "cause": "meltdown_expired"},
					"%s meltdown expired" % part.id
				)
			)


## Advances to the next living unit by INITIATIVE (taskblock-18 C1:
## fastest resolution speed first, not the old squad-sequential array
## walk), resetting its AP/MP. Bumps round_number and clears the
## acted-this-round set the instant every living unit has gone once —
## "everyone's had a turn," not "one more unit acted."
##
## taskblock-19 Pass F: a pending Hold takes priority the instant it's
## ready (`_hold_ready`, set once one more unit's turn has been handed
## out since the hold was declared) — resumed via `_resume_held_turn`,
## which skips `_start_turn` entirely so the held unit's own AP/MP carry
## forward untouched rather than regenerating. A held unit that died in
## the meantime is simply dropped; normal selection falls through.
func advance_turn() -> void:
	turns_resolved += 1
	if _held_unit_id != -1 and _hold_ready:
		var held: Unit = find_unit(_held_unit_id)
		_held_unit_id = -1
		_hold_ready = false
		if held != null and held.alive:
			_resume_held_turn(held)
			return

	var living: Array[Unit] = units.filter(_can_take_a_turn)
	if living.is_empty():
		return
	var candidates: Array[Unit] = living.filter(
		func(u: Unit) -> bool: return not _acted_this_round.has(u.id)
	)
	if candidates.is_empty():
		round_number += 1
		_acted_this_round.clear()
		candidates = living
	_begin_turn(_fastest_by_initiative(candidates))
	# A hold is still pending (this was the "next ally" it's waiting on) —
	# due on the very next advance_turn() call, whenever this unit's own
	# turn ends.
	if _held_unit_id != -1:
		_hold_ready = true


## taskblock-19 Pass F: "carries all held AP and MP forward... regenerates
## none." The one real difference from `_begin_turn`: no `_start_turn`
## call, so nothing about the held unit's own resources, facing lock, or
## overwatch state resets — it resumes in exactly the state it left off
## in. Still marks `_current_unit_id` for real, same as any other turn.
func _resume_held_turn(unit: Unit) -> void:
	_current_unit_id = unit.id
	var text: String = "Hold: unit %d resumes" % unit.id
	log_action(text)
	if not is_preview:
		combat_log.emit(
			LogEvent.new(round_number, Enums.Phase.RESOLUTION, unit.id, &"hold_resumed", {}, text)
		)


## taskblock-19 Pass F: `HoldAction`'s own entry point — defers the
## CURRENT unit (already mid-turn, already holding whatever AP/MP it has
## right now) to resume right after the next unit to act finishes THEIRS.
func begin_hold(unit: Unit) -> void:
	_held_unit_id = unit.id
	_hold_ready = false
	advance_turn()


func _begin_turn(unit: Unit) -> void:
	_current_unit_id = unit.id
	_acted_this_round.append(unit.id)
	_start_turn(unit)


## taskblock-22 Pass C: a shut-down unit stays `alive` (it still occludes/
## blocks as geometry — ShotPlane.build's own gate is untouched), but must
## never be handed another turn. The one place that actually excludes it.
static func _can_take_a_turn(unit: Unit) -> bool:
	return unit.alive and not unit.shutdown


## taskblock-18 C1: fastest-first — lower ResolutionSpeed.initiative()
## acts sooner (A2's own "lower resolves first" direction), tie-broken by
## unit.id ascending for deterministic replay. personal_speed is already
## the entirety of initiative() (no action is chosen yet at turn-start),
## so a tie on speed here is a tie on both of Pass B's own first two
## tie-break terms at once — id is the only thing left to break it with.
static func _fastest_by_initiative(candidates: Array[Unit]) -> Unit:
	var best: Unit = candidates[0]
	var best_speed: float = ResolutionSpeed.initiative(best).current
	for candidate: Unit in candidates.slice(1):
		var speed: float = ResolutionSpeed.initiative(candidate).current
		var better: bool = speed < best_speed
		if not better and is_equal_approx(speed, best_speed):
			better = candidate.id < best.id
		if better:
			best = candidate
			best_speed = speed
	return best


## taskblock-18 C2: "units within the same speed band resolve
## simultaneously for playback... a band tolerance (units within epsilon
## speed) groups them; tunable, flagged default." "Equal speed =
## simultaneous is not a separate feature — it's the ordering already
## expressing a tie," so this is a pure grouping query, not a second
## mechanism: LOGIC-level only (this pass's own scope) — actually
## skipping the inter-turn pause for a group during playback is a
## BoutRunner/ResolutionPlayer change flagged for later, untouched here.
##
## Every LIVING unit (this one included) whose own initiative value falls
## within SIMULTANEOUS_BAND_TOLERANCE of `unit`'s — ordered fastest-first,
## then by id, the same order `_fastest_by_initiative` would resolve them
## in one at a time, so a caller can present the group without changing
## what "next" means.
func simultaneous_group(unit: Unit) -> Array[Unit]:
	var living: Array[Unit] = units.filter(func(u: Unit) -> bool: return u.alive)
	var target_speed: float = ResolutionSpeed.initiative(unit).current
	var group: Array[Unit] = living.filter(
		func(u: Unit) -> bool:
			var speed: float = ResolutionSpeed.initiative(u).current
			return absf(speed - target_speed) <= SIMULTANEOUS_BAND_TOLERANCE
	)
	group.sort_custom(
		func(a: Unit, b: Unit) -> bool:
			var speed_a: float = ResolutionSpeed.initiative(a).current
			var speed_b: float = ResolutionSpeed.initiative(b).current
			if not is_equal_approx(speed_a, speed_b):
				return speed_a < speed_b
			return a.id < b.id
	)
	return group
