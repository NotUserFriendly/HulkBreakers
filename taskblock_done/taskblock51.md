# Taskblock 51 — The bug hunt

*Acts on taskblock-50 Pass F's triage. 31 open entries, seven clusters, three loners.*

**This block is expected to run out before the list does.** Work the clusters in order; whatever is
untouched at the end passes to the next hunt. **Do not thin a cluster to fit** — a half-diagnosed
cluster is worse than an untouched one, because the next hunt inherits a partial theory it has to
re-verify.

**23 of 31 entries are `SUPERVISOR`-owned.** CC may append findings and mark `Pending`; it may not
close them. The block's real output is a **`Pending` digest** — *"here is what I think I fixed, please
confirm"* — not a shorter ledger.

**Every fix needs a test that fails without it.** Fifth block running, the story has been a check that
couldn't fail. A fix landing with no regression test is a fix that leaves the same hole open.

---

# PASS A — The repro session, supervisor at the wheel

**21 of 31 entries have no repro path**, and most are `SUPERVISOR`-sourced visual observations — which
is *why* they lack one, not neglect. That gap is the single biggest tax on this block: an entry that
cannot be reproduced is a bug to **re-observe**, not a bug to fix, and finding out which is which costs
more during a hunt than before one.

**The supervisor drives; CC records.** Watch, reproduce, and capture the route back to each symptom.

- **A route, not a description.** What to load, what to click, what to watch for. "Spectate a bout with
  two squads on different levels, click a wall tile" is a route; "the cutout misbehaves" is not.
- **Record failures to reproduce as findings.** An entry that will not reproduce in a session is
  information — it may be fixed, environment-dependent, or wrongly described. **Say which was tried.**
- **Do not invent plausible routes for entries not reproduced.** taskblock-50 declined to and was right:
  an invented route reads as verified and sends the next session down it.
- **The replay baseline and the finish chime landed in taskblock-50** — a failing test now queues its
  script's known-good fixture directly after it. Use that during this session; it is the first block
  where an anomaly can be seen next to a normal.

**Deliverable:** every one of the 31 entries carries either a repro route or a stated reason it lacks
one. That is the pass's acceptance and it does not require fixing anything.

---

# PASS B — Two ledger repairs and a caching win

## B1. `HulkTheme.build()` caching

`test_spectator_overlay.gd` costs 32.4 s across 37 real scene builds and zero bouts — the largest
non-bout file in the suite. Caching the theme collapses it.

**It costs the `ui_builds` counter**, which taskblock-48 added specifically to make view-only cost
visible, dropping it from ~344 to ~1. **The supervisor has accepted that trade.** Record in
`CHANGELOG.md` that the counter's meaning changed, so a later reader does not take a low `ui_builds` as
evidence the view got cheaper.

The suite runs many times during a hunt; this pays for itself inside this block.

## B2. Split `BR27.01`

**Four bugs in one entry** ("Player Step Out: four bugs, one system"). One ID standing for four
independent outcomes means it can never be closed honestly — three fixed and one open is neither
`Active` nor `Resolved`.

Split into four entries, each with its own status. **Changes no statuses and closes nothing**; it makes
closure possible.

## B3. Confirm or merge `BR35.04` and `BR35.07`

taskblock-50's triage judged these "almost certainly one defect stated twice" — a deflection's bounce
tracer drawn as a fixed-range decoration, and a `STOP_DEAD` tracer drawn past its hit point. Both are
one drawing path projecting a decorative line instead of replaying resolved geometry.

**Confirm before merging.** If one defect, say so and mark the duplicate `Obsolete` with a pointer. If
two, the cluster in Pass C now knows they are separate.

---

# PASS C — Tracers and impact drawing

**BR27.03 · BR34.01 · BR35.04 · BR35.07 · BR35.08**, and **BR34.05** belongs with them.

**Suspected shared root:** a drawing path that projects a **decorative fixed-range line** rather than
replaying the geometry the resolver produced. Every symptom in the cluster is that one substitution
seen from a different angle — misses vanishing, deflection bounces going nowhere real, `STOP_DEAD`
rounds drawn through their own stopping point, detonations drawing nothing.

**Diagnose the cluster before fixing any member.** Five entries with one root is a single fix with five
regression tests; five entries fixed separately is five patches over one defect.

**This cluster unblocks BR30.10** (`Pending`, "shots resolve straight through walls"). That entry's
evidence is read off drawn beams and **cannot be signed off while any of BR35.07, BR34.05 or BR35.04 is
open** — a round correctly stopping at a wall is currently *drawn* continuing through it, which is
BR30.10's exact symptom produced by a different bug. Re-check it after this pass, not before.

`docs/02` and `docs/08` govern: **whatever is drawn comes from the same computation the resolver used**,
never a second approximation authored to look right. A tracer that looks correct but is independently
computed is the defect, not the fix.

---

# PASS D — Wall cutout and occlusion

**BR32.04 · BR32.05 · BR32.08 · BR35.02**

**Shared root:** the cutout's coarse screen-space heuristic — *a wall fades when it is near the focal
point on screen and in front of it* — which cannot distinguish vertical from horizontal separation and
has no real ray test against the camera-to-unit line.

Two have worked fix shapes already recorded:

- **BR32.04** — a display-position dictionary written by `_set_slide_anchor` and read by
  `update_wall_cutout`; the real difficulty is override lifecycle, not the change.
- **BR32.05** — needs a genuine ray or angle test in the shader. A rewrite, not a tweak.

**BR32.08 is `Suspected`** (dead/KO shells behaving strangely) and should be **confirmed or dropped** in
the same session — it costs nothing extra once the cutout is already on screen.

**Shader defects are invisible to CC.** taskblock-32 established that the only way these get cracked is
the supervisor running the real game and testing diagnostic builds. Plan for that rather than
discovering it.

---

# PASS E — Queue and action legality

**BR27.01 (four, after Pass B2) · BR30.04 · BR32.07 · BR34.03**

The step-out and queue path. The known pattern here, from BR27.05/06, is **reading raw state where
previewed state is wanted**: `selected_unit.cell` is the turn-start cell until the queue resolves, so
anything position-dependent must read `selection.previewed_unit()`.

**The discriminator, and it matters — do not blind-fix:** does the read want the unit's *identity*
(which unit is selected — raw is correct) or its *previewed state* (position, AP, cover, reachability
after the queue — needs the preview)? Identity reads are fine and changing them introduces bugs.

Highest-value cluster after tracers, because it is player-facing and the pattern is already understood.

---

# PASS F — Aim and camera framing

**BR26.02 · BR33.01 · BR34.04 · BR40.01**

**BR26.02 (framerate while aiming) may not be its own defect.** taskblock-50's triage suspects it is a
symptom of **BR35.01**'s per-hover scan — `PartPicker.hit` walking every `blockers`/`field_items` entry
on every call. **Check that first**; if it is, this cluster loses its oldest entry and BR35.01 gains
urgency. That bug has already absorbed three fixes that were reasoned rather than measured, so
**measure before changing anything**.

**BR40.01** is the camera solving a position past the far edge of the shooter's own platform. It was
found by rendering, and the headless matrix passed every invariant it checks because the harness has no
scene geometry to occlude against — so **a fix has the same property** and needs eyes, not a test.

---

# PASS G — Map generation and movement

**BR46.02 · BR35.05**

**BR46.02 — 16 of 40 maps contain ground a unit walks into and never leaves.** Descent is free, ascent
is `CLIMBER`-gated, and no part carries the tag. Three directions, and the supervisor has already
chosen among them:

- **Penalise ungated descent, exempt ramps** — the fix. Weight a candidate cell *slightly* worse when
  reaching it means dropping a level, and not at all when the descent is via a ramp. Units then prefer
  ramps without any rule naming ramps, and a ramp is two-way. **"Slightly" is load-bearing:** a
  hop-down to reach an otherwise unreachable target must still win when the reason is good enough.
- Ramps-where-missing in the generator is low priority and rides along with other map-gen work.
- The pace/shutdown mitigation makes a stranded unit *legible*; it is not a fix and must not be logged
  as one.

**BR35.05** — approach and closing paths with no ally-awareness. Note that `LineOfFire.approach_path`
**survived taskblock-45 as code with no callers**; decide whether it is revived as a consideration input
or deleted with its tests. A function with no callers whose comment describes a branch that no longer
runs is what `SUPERSEDED.md` exists to prevent.

---

# PASS H — Performance

**BR27.09 · BR35.01 · BR35.03**

No shared cause; three independent hot paths.

- **BR27.09 — re-measure before touching it.** The AI planner went from ~1.7 s to ~412 ms release
  across taskblocks 43–45, and the last measurement predates the profile-id fix that changed every AI
  number. **It may already be closeable**, and that is a supervisor decision on a fresh number.
- **BR35.01** — `PartPicker.hit`'s full scan. Possibly BR26.02's cause; see Pass F.
- **BR35.03** — taskblock-50's triage believes it was already closed structurally by the
  `DebugVerbs.affects_board` work and **may only need confirming.** Cheapest entry in the block.

---

# PASS I — Spectator vs player divergence

**BR27.04 · BR27.07 · BR32.09**

**Fix the instances; do not restructure the hierarchy.** All three are one root — `SpectatorOverlay`
re-implements a subset of `SquadControlOverlay`'s panels because it cannot inherit them without
dragging in `TacticsController` and the whole unit-input path. `PLAN.md`'s *One view, toggleable
modules* dissolves that class, and **a structural fix here is work that item discards.**

So: cheap instance fixes are in scope; anything that wants to change the overlay hierarchy **stops and
reports** instead.

**BR27.07** has a diagnosis already: the active-turn highlight reads `combat_state.current_unit()` —
live state — while `ResolutionPlayer` is still drawing the previous unit's move. Two clocks, one
signal. `battle_scene.gd` already names the hazard in prose ("a caller might want to defer until an
animation finishes") across three call sites, and the defer is not happening on all of them. **Check
whether this is still the defect the entry describes** — the original was the *wrong unit*, this is the
right unit at the *wrong time*.

Ordered last deliberately: highest chance of being superseded, lowest chance of staying fixed.

---

# PASS J — The loners, and the digest

**BR45.01 · BR45.03 · BR48.01 · BR30.02 · BR30.10**

- **BR48.01** — the inspect panel leaving the background dimmed. Cheap, visual, and `SUPERVISOR`-owned.
  Two things worth checking rather than assuming: whether a second open/close makes it *darker*
  (stacking, not persisting — same symptom, different bug), and that all three close paths are covered
  (button, `Esc`, opening a second inspect over the first).
- **BR30.10** — re-check only after Pass C. Not before.
- **BR45.03** — the completion rate. `seeds_to_first_win` replaced the gate in taskblock-50, so **state
  what the entry now means** before touching it.

**The digest is the block's deliverable.** Every `SUPERVISOR`-owned entry moved to `Pending`, listed
with what was done and how to see it. A hunt that fixes eight things and hands back an unreadable
ledger has produced less than one that fixes five and says clearly which five.

---

# Acceptance

- Every entry carries a repro route or a stated reason it lacks one (Pass A).
- Every fix carries a regression test that fails without it.
- No `SUPERVISOR`-owned entry closed by CC.
- Untouched clusters named explicitly as untouched — **not silently carried**.

# Not this block's job

- **Restructuring the overlay hierarchy** (Pass I) or `BUGS.md`'s flat-list convention.
- **Authoring a `CLIMBER` part.** Own PLAN item, and using it to paper over BR46.02 hides both.
- **Retiring `MIN_COMPLETION_RATE`.** Proposed in taskblock-50; the supervisor disposes.
- **Chasing the five-minute suite further.** taskblock-50 got there with ~10 s of margin; B1 adds
  headroom and that is enough for this block.
