# Taskblock 62 — The AI learns to go up

*Closes `PLAN.md` NEXT 1–4: *Author `step_height` onto parts*, *Multi-level cleanup*, *A climb needs a
position along it*, *The AI can queue a vertical move*. Depends on taskblock-60's `step_height` and
taskblock-53's ladders.*

**The gap this closes: no AI path queues `ClimbAction` or `HopDownAction`.** Both exist, are
cost-correct, and are reachable only by a human or an injector. The pathfinder takes a per-mover step
height, the generator places ladders, and `BR60.01` records maps with raised ground reachable only by
ladder — **so the AI is playing a flat game on a multi-level board.**

**Four items, one subject, and the order is a dependency chain.** A step height that no part authors is
a constant; a climb the AI never queues is unreachable code; a climb with no position along it cannot
be paid for across turns or interrupted honestly.

---

# PASS A — `step_height` is a part's, not a constant

taskblock-60 gave `Pathfinder` a per-mover `step_height` defaulting to `Unit.BASE_STEP_HEIGHT`.
**Nothing authors one**, so every unit steps the same height and the parameter is a constant with extra
steps.

- **Author it on parts** — legs, and whatever else plausibly changes a stride. **Long legs step higher**
  is the thing a ramp could never express and the reason this stopped being a global.
- **`Unit.step_height()` derives from the shell**, the way `can_climb()` derives from the `CLIMBER` tag.
- **The generator's navigability invariant must run against the *lowest* step height in play**, not
  against the default. A 0.6 rise being free for some units and not others is the point, and the
  invariant has to assume the worst case or it will certify maps that strand short-legged units.
- **Balance-adjacent, so state the values rather than inventing them.** One authored height and a stated
  reason beats four invented ones.

**TESTS:** a unit with taller legs walks a rise a default unit cannot; the navigability flood uses the
minimum step height present and fails a map that only the tallest unit could cross; a shell with no
authoring gets `BASE_STEP_HEIGHT`.

---

# PASS B — The Mag Lift

**A third way up, and it costs AP where the others cost MP.** Ladders and steps both spend movement;
this spends an action, so it slots beside them as a real alternative rather than a strictly better one.

- **Two surfaces, lower and upper.** A unit that steps onto the lower surface and spends **1 AP** is
  moved to the upper one. **Effectively a teleport between the pair** — not a traversal, no path
  between them.
- **Neither surface blocks shots.** The upper one "floats" the unit high enough to step onto a higher
  point; it is a platform to stand on, not a wall.
- **It drops in where ladders currently go in map generation.** Same slot, same job, different cost
  currency.

**Why it is worth building now rather than later: facing is not playing nice with ladders**, and a mag
lift has no facing to get wrong. **A pair of surfaces and a teleport uses only machinery that exists** —
`Surface` placement, an AP-costing action, and the same generator branch that places ladders.

**Do not make it free.** Free vertical movement makes ladders and steps pointless, and the AP cost is
what keeps three routes up meaningfully different: **steps are cheap and need short rises, ladders are
slow and need MP, a lift is instant and needs AP.**

**TESTS:** stepping onto the lower surface and spending AP places the unit on the upper one; with no AP
the lift refuses **and says why** (see `PLAN`'s bare-boolean item — a silent refusal here is the same
defect); neither surface blocks a shot that passes through its cell; a shot fired from the upper surface
originates there; the generator places a lift where it would have placed a ladder.

---

# PASS C — A climb has a position along it

`ClimbAction` charges the whole rise as **one atomic action**, which is why a four-level ladder priced
at 16 MP and was unaffordable outright until `LADDER_COST_SCALE` was corrected.

**taskblock-53 made a climb interruptible. It is still not payable in parts.** If it can be interrupted
midway it should be payable midway — **pay what this turn affords, finish next turn.**

- **That is the real fix for tall ladders**, not a cheaper scale factor. A tall climb costing several
  turns is correct; a tall climb being unpurchasable is not.
- **It sharpens the intended contrast.** A **ladder is direct but exposed**; a **step route is indirect
  but safe**; **a mag lift is instant but costs an action.** Paying for a ladder across turns while
  standing on it is exactly the exposure that should cost something.
- **A unit occupying a position partway up** is also what the destroyed-ladder fall needs, so this pass
  builds one of that feature's four dependencies rather than a one-off.

**TESTS:** a climb longer than this turn's MP leaves the unit partway up and resumes next turn; the
partial position is a real board position — visible, shootable, and pathable *from*; an interrupted
climb resolves consistently with an interrupted move (**the same rule, not a parallel one**); a seeded
bout with a partial climb is reproducible.

---

# PASS D — Hop-down is interruptible and known to be one-way

Two gaps flagged when these actions were built in taskblock-37 and still open.

- **`HopDownAction` checks nothing.** taskblock-53 Pass E gave `ClimbAction` the same mid-move overwatch
  check an ordinary move has; the hop-down still has none. **Every real exposure the same** (`docs/09`),
  and a unit dropping off a ledge is exposed.
- **The planner does not know a hop-down is one-way.** Descent is free; ascent needs a step, a ladder, a
  lift, or a capability nothing authors. **A unit that drops off a ledge to reach something can strand
  itself.** *"Can I get back?"* belongs in the decision rather than being discovered afterwards.

**Stranding is a legitimate outcome** — a player knocking someone into a pit is the game working — **but
a unit choosing it unknowingly is not.**

**TESTS:** an overwatching unit triggers on a unit mid-hop-down; the planner declines a hop-down whose
destination has no route back, and takes one when the reason is good enough (**assert both, or the rule
is a prohibition rather than a cost**).

---

# PASS E — The AI queues a vertical move

**The pass the other four exist for.** With step heights authored, lifts placed, climbs payable and
hop-downs known one-way, the planner can finally reach the rest of the board.

- **`ClimbAction` and `HopDownAction` become things the planner emits**, not just things a human can
  trigger. They are executors already; what is missing is the utility actions that select them.
- **Follow the framework** — a `.tres` per action with preconditions and considerations, not a branch in
  the planner. Tier-gate them the way everything else is gated.
- **The mag lift needs one too**, and it is the interesting one: it competes for AP against shooting, so
  its consideration set has to weigh *going up* against *acting*.

**Acceptance is behavioural**: a target reachable only by ladder, lift or step gets reached. **Report
`seeds_to_first_win` before and after** — the AI gaining half a board is the kind of change that moves
it, and if it does not, that is a finding about whether generated maps use their verticality at all.

**TESTS:** a planner given a target reachable only by ladder queues a climb; only by lift, queues the
lift; only by a step, walks it; a unit with no route up does not queue a vertical action it cannot pay
for; `MINDLESS` does not get actions its tier excludes.

---

# When to stop and report

- **Pass A's authored heights change generated-map navigability.** The invariant runs against the
  minimum; if existing seeds fail it, that is a finding, not a number to tune.
- **The mag lift needs more than a surface pair and an action.** It is specified as cheap; if it is not,
  say so before building a mechanism.
- **Pass C's partial climb needs a new state concept.** A position along a climb is a real board
  position, and if the existing model cannot express one, report rather than approximating.
- **Pass E's vertical actions do not change `seeds_to_first_win`.** Worth knowing whether that is the AI
  or the maps.

# Acceptance

- A part authors a step height and a taller unit steps higher.
- A mag lift moves a unit up for 1 AP, blocks no shots, and generates where ladders do.
- A tall climb is paid across turns and the unit is a real target partway up.
- A hop-down triggers overwatch, and the planner knows it is one-way.
- **An AI unit reaches a target it could only reach by going up.**

# Not this block's job

- **Authoring a `CLIMBER` part.** Maps must work without one — that is what steps, ladders and lifts are
  for. `Shell.can_climb()` reading a tag no part carries is correct, not a gap.
- **The destroyed-ladder fall.** Pass C builds one of its four dependencies; the rest need forced
  movement.
- **`BR60.01`'s repair** — unreachable raised ground is detected and nothing repairs it. Its own item and
  a decision between three shapes.
- **The ramp subsystem.** Retired taskblock-60; do not reintroduce a special case for a slope.
