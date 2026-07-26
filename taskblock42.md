# Taskblock 42 — Bug hunt: the hitch, then a batch

*Addresses BR27.09 and a clustered follow-up sweep. Depends on taskblock-41's diagnostics.*

**This block has a hard pause in the middle.** Passes A–D are the turn-boundary hitch and nothing else.
When D lands, **stop and report** — the supervisor measures the hitch on a clean build before any other
bug is touched, because a hitch fix mixed in with eight unrelated changes cannot be attributed. Passes
E–G are hands-off and only start on a go.

The follow-up passes are clustered by **shared cause**, not by severity. Each pass is one subsystem, so
a fix that turns out to be structural fixes several entries at once rather than one.

---

# PART ONE — the hitch

# PASS A — Fix the instrument before measuring with it

**BR26.02 carries a supervisor revision from 2026-07-23 that was never built.** `FpsDumpSink` was last
touched in taskblock-35 and still fires a single dump at `create_timer(0.2)`, labelled "200ms after turn
start." The revision:

- **Add a turn dump at 0ms** — capture the boundary cost *itself* rather than deliberately stepping past
  it. **This is the number BR27.09 is actually about,** and it does not currently exist.
- **Move the 200ms dumps to 2000ms.** 200ms proved too close to the transient to read as settled; two
  seconds in is the honest steady-state sample. Applies to the aim-entry dump in
  `TacticsController._enter_aim_mode()` as well.
- **Keep both samples.** 0ms and 2000ms together are what separate BR27.09's boundary spike from
  BR26.02's settled rate. Either alone conflates them.

Nothing else in this pass. Every later measurement in this block reads these numbers, so they land first
and land alone.

**TESTS:** both dumps fire per turn with distinguishable labels; the 0ms dump is not silently deferred a
frame by the await path; existing `FpsDumpSink` assertions updated rather than deleted.

---

# PASS B — Cost #2: `HitVolumeView.refresh()` rebuilds what didn't change

`refresh()` calls `queue_free()` on every child, clears `_meshes_by_part`, and rebuilds every box and
mesh from `UnitGeometry.placements()`. It is called:

- once per touched unit after every AI batch (`BattleScene.refresh_unit_views`),
- on **every** `preview_orientation` change while aiming (`squad_control_overlay.gd:782`),
- on hit-volume toggle and from the inspect panel.

A unit that moved has the same parts, the same boxes, and the same meshes — only a transform changed.
The teardown is fully wasted for the most common case.

**The fix is granularity, not micro-optimization.** Separate the reasons a view becomes stale:

- **Transform-only** (a move) — update node transforms; rebuild nothing.
- **Orientation/pose** — placements genuinely change, but the *node set* usually doesn't. Reuse the
  existing `MeshInstance3D`s and rewrite their transforms rather than freeing and re-instancing.
- **Structural** (part destroyed, mangled, attached, detached) — the full rebuild, which is what
  `refresh()` does today and is correct for this case only.

**Measure against Pass A's 0ms dump before and after, and put both numbers in the report.**

**This also sits in BR26.02's path.** The aim-time call at `squad_control_overlay.gd:782` fires on every
orientation preview change. That bug has now absorbed three fixes that were reasoned rather than
measured; this is the first chance to put a number on the aiming path. **Measure it, report it, and do
not close BR26.02** — it's `SUPERVISOR`-owned and the supervisor has already said aiming is tolerable.

**TESTS:** a transform-only refresh instantiates zero new nodes (assert on the count, not on timing); a
structural change still rebuilds fully; the rendered result after a cheap refresh is identical to what a
full rebuild produces — pin the equivalence, since the entire risk of this pass is a view that stops
updating in a case nobody enumerated.

---

# PASS C — Cost #3: the turn-start power recompute

BR27.09 records the turn-start power recompute re-walking the part graph 5–6 times. Locate it, confirm
the count, and collapse it to one walk with the results cached for the turn.

Ordinary optimization work. If the measured cost turns out to be small next to Pass B and Pass D, **say
so and stop** — the entry stays open with a number attached, which is a better outcome than a
speculative refactor of the power path.

**TESTS:** the graph walk happens once per turn-start (assert the call count); power and surplus values
are identical before and after; cache invalidates on any structural change to the part tree.

---

# PASS D — Cost #4: the AI batch never yields

```
while not runner.finished and not wants_turn_for(battle.combat_state.current_unit()):
    var run_finished: bool = runner.step()
    ...
battle.refresh_unit_views(touched_ids.keys())
```

`ControlOverlay.advance_ai_turns` is a bare `while` loop with **no `await` anywhere in it**. Each
`step()` runs a full `UnitAI.plan_turn` — pathfinding, LOS, cover scoring. The main thread is blocked
for the entire batch, so nothing renders, no input is processed, and the window is unresponsive. This is
the several-second half of the hitch.

**The supervisor's own instinct here is the right one:** decouple UI rendering from whatever is blocking
it. **taskblock-41 already did exactly this for the combat log** — the sink marks itself dirty on
`emit()` and a `_process` tick draws at most once per frame, so render cost stopped scaling with event
count. Same shape, larger scope: the sim advances, the view draws on its own clock, and neither waits on
the other.

**One real design fork, and it needs deciding before coding rather than during:**

> The batch currently coalesces its view refresh — `touched_ids` accumulates across every step and
> `refresh_unit_views` fires **once** at the end, deliberately (taskblock-19 Pass I2 notes a full-board
> refresh per batch was measured waste). Yielding between steps reopens that question. Yield without
> refreshing and the player watches a frozen board for several seconds, just an interactive one. Refresh
> per step and the coalescing is undone and Pass B's savings are spent.
>
> The likely answer is that these are separate frequencies — yield every step so input and rendering
> stay alive, but refresh on the frame tick rather than per step, exactly as the log sink does. State
> the choice and its reasoning in the report before implementing it.

**Determinism is not negotiable.** A yielding batch must produce the identical bout from the identical
seed. If yielding introduces any ordering dependence on frame timing, stop and report rather than
shipping a faster non-deterministic sim.

**TESTS:** a seeded bout produces byte-identical results with and without yielding — this is the pass's
real acceptance and it is worth more than the perf number; input is processed during a long AI batch;
`runner.finished` and the `wants_turn_for` handoff behave identically across a yield boundary; the
existing `advance_ai_turns` coverage passes untouched.

---

# ⏸ HARD PAUSE — report and stop

**Do not begin Pass E.** Report:

- The 0ms and 2000ms dumps, before and after each of B, C, and D **individually** — the point is to know
  which cost dominated, and the supervisor's prior is that #2 leads with #4 a strong second. A combined
  number cannot settle that.
- The Pass D coalescing decision and its reasoning.
- Whatever BR26.02's aiming path measured, unclosed.
- BR27.09 stays `Active` unless the supervisor closes it. Append; do not change status.

The supervisor measures on a clean build, then gives a go.

---

# PART TWO — the clustered sweep

Hands-off after the go. Each pass is one shared cause.

# PASS E — Refresh granularity, the rest of it

**Same defect as Pass B, so this is nearly free once B lands** — a rebuild where something small changed,
or no rebuild where something did.

- **BR35.03** — every debug-panel verb rebuilds the entire board view, not only what changed. Pass B's
  granularity distinction applies directly.
- **BR30.02** — debug `move_object` mutates state but the model never visually moves. The inverse
  failure: state changed and nothing refreshed at all. Same axis, opposite sign, and worth fixing
  alongside because the fix is "which change requires which refresh," answered once.
- **BR35.01** — `PartPicker.hit` scans every `grid.blockers`/`field_items` entry on every call. Not a
  refresh bug, but the same "does work proportional to the whole board for a local question" shape, and
  it's `CC`-owned and small.

# PASS F — Tracers and hit visuals

Six entries, all in `ResolutionPlayer` and the tracer-drawing path. Treat as one investigation, not six
fixes — the suspicion is that several share a root in how a shot's endpoint and hop sequence are turned
into drawn geometry.

- **BR34.05** — misses vanish instead of striking anything.
- **BR35.04** — a DEFLECT's bounce tracer is a decorative fixed-range projection rather than the real
  path.
- **BR35.07** — `STOP_DEAD` tracers are drawn past their own hit point, reading as penetration.
- **BR34.01** — every penetration/deflection hop replays the full bright hit-flash.
- **BR35.08** — detonations are invisible; nothing is drawn when an explosion resolves.
- **BR27.03** — other shots appear to resolve before an earlier shot's deflect finishes (ordering rather
  than geometry, but the same player-facing subsystem and worth holding in view while the rest is open).

**Note for this pass:** taskblock-40 Pass A renamed `void_range` to `miss_range` under an explicit
rename-only fence, because the supervisor believed the area had a live bug. **BR34.05 and BR35.04 are
that bug.** The fence is lifted for this pass.

# PASS G — Raised rooms generate at level 0

- **BR40.03** — scattered cover generates at level 0 inside raised rooms.
- **BR40.04** — extraction and spawn tiles recessed to level 0 inside raised rooms.

Two entries, one cause: `MapGen` placing objects without reading the room's level. Almost certainly a
single fix. Cheap, and it removes a class of nonsense from every generated multi-level map, which
matters because generated maps are the test surface for everything else.

**TESTS:** across a seed sweep, no cover, extraction tile, or spawn tile sits at a level below the room
containing it.

---

# Not this block's job

- **BR27.04, BR32.09, BR35.02** — lighting differs between spectator and player view, spectator's
  current-unit indicator jumps early, spectator tile-inspect resolves to a hidden cell. All three are
  spectator-versus-player divergence, which is the motivation for `PLAN.md`'s *One view, toggleable
  modules*. Fixing them individually produces work that refactor discards. **Leave them.**
- **BR32.04, BR32.05, BR32.08** — the wall cutout. Well-diagnosed by taskblock-40 Pass C, but BR32.05
  needs a real ray test in the shader, which is a rewrite rather than a sweep item, and BR32.04's fix
  turns on override lifecycle. They want a pass of their own.
- **BR26.02** — measure it in Pass B, report the number, leave it open.
- Closing any `SUPERVISOR`-owned entry. Append findings; the supervisor closes.
