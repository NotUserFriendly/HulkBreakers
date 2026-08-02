# Taskblock 53 Report — Ladders, an authored map, and a suite that stops keeping score

Passes A–D landed in order and are green. **Pass E landed one of its two halves** — a climb can
now be interrupted; no AI path queues one yet. Suite green throughout, 2711 tests at the end.

## Decisions made without asking

- **The audit's deliberate staleness could not be preserved, and the reason is structural.**
  `suite_audit.csv` and `suite_profile.json` must agree — the sum assertion checks per-test
  counters against the profile's global totals — so a fresh profile and a stale CSV cannot both
  hold. The alternative was reverting the tests that forced the regeneration.
- **The bout seed went on `CombatState` rather than into its constructor.** 733 call sites,
  almost none of them bouts anyone replays. A required constructor argument is stricter and
  would have touched every one.
- **`session_start` was renamed `bout_start`** rather than left accurate-sounding. A file holds
  several bouts now; keeping the old name was cheaper and would have reproduced the same
  misattribution under a familiar word.
- **The map format stores parts by id and excludes runtime state.** A map is the pristine
  authored board, not a savegame. Embedding part copies would freeze a balance number into every
  map ever saved. The alternative — one format for both — acquires fields that are meaningless
  half the time.
- **One `MapPlacement` class with an open `kind`**, not three Resources. Kind is content, so it
  is an open vocabulary; three classes would be three places to update.
- **A Resource per placement, not parallel arrays.** Pass B needs the `.tres` hand-authorable,
  and parallel arrays are one transposed row from a silent hole in the floor.
- **Loading never enforces the placement grammar.** The grammar gates the *act* of placing;
  replaying it at load would reject a legitimate saved stack whose cell is no longer empty by the
  time the second surface loads. `describe_problems()` warns instead.
- **The first map is authored by a script**, the same convention every `tools/author_*` uses. The
  map is designed there and the `.tres` is its serialization; typing several hundred
  `sub_resource` blocks would express the same data with none of the intent.
- **Orientation stays out of the attachment vocabulary** (Pass C2's question). Direction is
  geometry and geometry is already on the socket. Putting it in the type would double every
  socket name and repeat the "one word carrying unrelated axes" mistake `SUPERSEDED.md` records
  against the retired playstyles.
- **A ladder replaces the climb rise cap with its own reach** rather than raising it.
  `MAX_CLIMB_LEVELS` exists because a bare face is only climbable so far; a ladder removes that
  by construction. Without this a three-segment ladder is unusable, defeating "tileable to
  arbitrary height".
- **The generator's measured-dead ladder branch was kept, not deleted** — the same call
  taskblock-52 made about its tiebreak stage — with a test that fails if the constants stop
  making it dead and says to update rather than delete.
- **Pass E was split.** The interruption half is self-contained; the planner half touches action
  construction where a regression is hardest to attribute. Landing both together would have made
  them inseparable.

## Tests that failed, then were corrected

1. **A test hung a 300-second run instead of failing it.** Indexing an empty `Array[LogEvent]` is
   a runtime error, and under `-d` that opens a debugger break — `BR52.02`. The underlying
   mistake was assuming `BoutInjector` emits an event named after the verb; it emits a uniform
   `inject` event carrying the verb in its data. Fixed by bailing before the index, with the
   reason written down.
2. **My height rule broke tb38's own grammar tests.** Requiring a side attachment's host to be at
   a *different* height also rejected a catwalk spanning horizontally from a neighbour at the
   same height, which is precisely what side attachment was built for. Narrowed to exclude only
   the same cell at the same height — the ground under your feet.
3. **`LADDER_COST_SCALE` was backwards.** 1.5 made a ladder the most expensive way up, so nobody
   would build one, and made tall ladders fail affordability outright because `ClimbAction`
   charges the whole rise as one action — a four-level ladder cost 16. The number looked
   defensible until a test climbed something tall.
4. **Two navigability fixtures were wrong the same way.** A pit deep enough to look dramatic is
   *unreachable*, not one-way. The stranding window is exactly
   `(MAX_CLIMB_LEVELS, MAX_HOP_DOWN_LEVELS]` — free to fall into, impossible to climb out of.
5. **The guard I wrote against reading the audit tree flagged itself, twice** — once in its own
   doc comment and once in an assertion message. It strips comment lines now rather than
   excluding itself by name, which would have stopped it policing itself.

## Open questions

- **The ladder branch of the generator rule cannot currently fire**, and that is arithmetic, not
  luck: a drop is capped at `MAX_HOP_DOWN_LEVELS` (2.0) and the way out is the same face, so the
  repair's rise never exceeds `RAMP_MAX_RISE` (2.0). **Is 2.0/2.0 the intended relationship?** If
  hop-down should exceed what a ramp repairs, the branch wakes up and the test says so.
- **A unit on a destroyed ladder should fall** (C3). Not built. The interruption work landed the
  hook a fall would ride on, but "the drop as an ordinary hop-down would" needs deciding at the
  point a surface is destroyed mid-action, which nothing currently models.
- **`LADDER_SEGMENT_RISE` (2.0) and `LADDER_COST_SCALE` (0.5) are flagged, not designed.** The
  first wants to come from authored ladder art's box height; the second wants a real answer when
  movement economy is tuned.
- **The attachment graph is real but nothing reads it.** A placed part occupies a socket via
  `PartGraph.attach`, yet reach is computed from placed heights. Those can disagree if a map
  authors a segment at a height its host does not support — an editor warning, not a grammar rule.
