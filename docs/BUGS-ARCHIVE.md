# BUGS — Archive (closed entries)

Closed bug reports, moved out of `docs/BUGS.md` so the live ledger holds only what is still open.
**`docs/BUGS.md` is the working file; this is the history.** An entry lands here only once it is
`Resolved` — supervisor-confirmed for `SUPERVISOR`-sourced bugs, per the provenance gate. Nothing
is derived or generated: an entry is moved once, verbatim, and never edited again.

Full text is preserved for every entry — investigations, dead ends, and hypotheses included, since
those are exactly what a future session needs when a bug turns out not to be as dead as it looked.

---

### BR52.03 — Obsolete — owner: `CC`
**Terrain risers are drawn but have no geometry, so a round can pass under a raised floor**
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-01, taskblock-52 Pass D, while giving surfaces real volume.
- **`BoardView._build_terrain` draws two things.** A flat quad per cell at that cell's own height,
  **and** a vertical riser quad along every edge where two orthogonally-adjacent cells differ in
  height — "a stepped, XCOM-style terrace". The quad now has a Part behind it (`ship_floor`'s
  authored `volume`). **The riser has nothing behind it at all**: no `Surface`, no blocker, no Part.
- **So a round fired horizontally into the step passes straight through it** and travels on into the
  empty space beneath the higher cell's floor box, which is only 0.2 thick. That is a real hole in
  "render is hitbox" (`docs/10`) — visible geometry a shot ignores.
- **Only reachable on multi-level maps**, which is why it has never been seen: the riser is drawn
  only where adjacent heights differ.
- **Not fixed in taskblock-52.** The fix is a decision rather than a patch: a riser is either its own
  placed `Surface` (which makes it destructible terrain with a material, and needs a Part authored
  for it), or the floor box grows downward to meet the level below (cheap, but then "floor thickness"
  stops being a free parameter and starts being load-bearing). **Do not pick one without deciding
  what a shot into a step should do** — a round burrowing under a raised deck is arguably a feature.
- **`Obsolete` (`CC`, 2026-08-03, taskblock-54 Pass B1) — the code this entry describes is gone
  rather than fixed.** `BoardView._build_terrain` no longer emits riser quads at all, and
  `_add_riser` is deleted. There is nothing left to give geometry to.
- **`Obsolete`, deliberately not `Resolved`.** The entry's own framing was that the fix is a
  decision — either the riser becomes a placed `Surface` with a real material, or it stops being
  drawn. **Neither branch was taken as a repair; the feature was retired.** Writing `Resolved`
  would claim a riser now behaves, and there is no riser.
- **The deletion is what restores the pillar.** The entry's complaint is visible geometry a shot
  ignores; drawing nothing there makes the render and the geometry agree by both being absent. A
  step is one part at the height it needs to be, and the vertical gap between two heights is
  genuinely open space.
- **Verified by vertex count, not by eye:** a terraced board and a flat board of the same size now
  emit identical terrain (96 vertices each on a 4x4), so a height difference adds no geometry.
- **Consequence, expected and recorded rather than treated as a regression:** raised floors read
  as floating slabs. Filling a step's side is authored content — a wall, a strut, a bulkhead
  placed by a section — and there is nothing to author it into until sections exist.
- **`docs/SUPERSEDED.md` records the terrace model's retirement.**

### BR46.02 — Resolved — owner: `CC`
**16 of 40 generated maps contain ground a unit can walk into and never leave**
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-28, while checking the supervisor's report that "Squad 1 is trapped in a lowered
  section" during a real bout. It is a real and separate defect from `BR46.01`.
- **Descent is free and ascent is capability-gated.** Dropping to a lower level is legal for everyone;
  climbing back needs `Shell.can_climb()`, which reads a `CLIMBER` part tag, and **no part in the repo
  carries it.** So every lowered region is a one-way door for every unit that currently exists.
- **A symmetric connectivity check cannot see this, which is why it was missed.** Spawn zones are
  mutually reachable on **60 of 60** seeds — the map is connected in the ordinary sense. The defect
  only appears under *asymmetric* reachability: flood out from a spawn cell, then flood back from each
  cell reached and ask whether the spawn is still reachable.
- **Measured over 40 seeds at the real 32x24 bout size: 16 seeds contain at least one one-way cell,
  worst case seed 16 with 216 of them** (e.g. `(11,10)`). A unit that wanders in is out of the mission
  while still alive and still taking turns — which reads as `TERMINATED`, and is a plausible
  contributor to `BR45.03`'s dominant failure mode.
- **Not fixed, and deliberately not fixed by me: the direction is a design call.** Three options, none
  obviously right:
  (a) **author a `CLIMBER` part** — `PLAN.md` already carries this as its own item, and it makes the
  gate real rather than removing it, but it changes what every shell can do;
  (b) **make `MapGen` guarantee two-way connectivity** — ramp or raise any region whose only exits are
  descents, which keeps the movement rules alone and constrains the generator;
  (c) **make the planner refuse a one-way step** — cheapest, and wrong on its own, since a player can
  still walk in and the AI would be avoiding terrain rather than the terrain being fixed.
  The evidence points at (b) as the floor and (a) as the feature; (c) is a mitigation, not a fix.
- **Reproduction is `tools/`-free and cheap:** flood from any spawn cell with a non-climbing
  `Pathfinder`, then flood back from each reached cell and check the spawn is still in the set.
- **Resolved (`CC`, 2026-08-02, taskblock-53 Pass D) via option (b), the generator guarantee** —
  the direction the entry itself called "the floor". `MapGen.guarantee_navigability` runs last, on
  the finished `Grid`, and opens an upward edge out of every stranded cell.
- **Re-measured either side of the fix with the entry's own reproduction, at the same 32x24 bout
  size and the same 40 seeds: 16 of 40 -> 0 of 40.** The worst case the entry records, seed 16 with
  216 one-way cells, is among them and comes back clean.
- **The check is `MapNavigability`**, and it runs the flood the entry prescribed with one change
  that is worth stating: the naive form floods back from *every* reached cell, which is O(cells^2)
  and unusable across a sweep. The return flood runs **once** from the origin over reversed edges —
  a cell can reach the origin exactly when the origin can reach it backwards. Same answer, two
  floods instead of thousands, and it reproduces the recorded 16/40 exactly, which is what confirms
  the shortcut is equivalent rather than merely faster.
- **A finding that came out of the fix: the rule's ladder half is measured-dead.** taskblock-53
  specifies "rise <= 2 gets a ramp; anything higher gets a ladder", and nothing generated can reach
  the second half. A cell is one-way only if you can *fall into* it, capping the drop at
  `MAX_HOP_DOWN_LEVELS` (2.0); the way out is the same face, so the repair's rise never exceeds
  `RAMP_MAX_RISE` (2.0). Every stranded cell is ramp work. **The branch is kept rather than
  deleted** — it costs nothing and is one constant away from live — with a test that fails if the
  constants stop making it dead, and says to update rather than delete it.
- **Options (a) and (c) are untouched and still open on their own merits.** A `CLIMBER` part stays
  `PLAN.md`'s item, and the planner refusing a one-way step was never a fix — a player can still
  walk in.

### BR52.11 — Resolved — owner: `SUPERVISOR`
**A bout started from the Generate Bout overlay logs no seed at all, and the file's one seed line
misattributes it**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-02. *"The game starts on 2, but the bout I ran was a four digit seed. Bouts
  aren't printing their seed into the combat log."*
- **Confirmed, with the mechanism.** `BattleScene.load_battle(state, mission, header_event = null)`
  takes the `session_start` event as an **optional third argument**. `new_battle()` (the launch path)
  passes `_session_start_event(seed_value)` with `DEFAULT_SEED = 2`.
  **`GenerateBoutOverlay._on_start_bout_pressed` calls `battle.load_battle(result.state,
  result.mission)` with no header at all** — so the `map_seed` it read out of `_seed_field` and handed
  to `BoutSetup.build_bout` is used to generate the entire bout and then dropped.
- **It is worse than a missing line, because the file is per-session and a new bout appends**
  (`FileSink`, supervisor's call 2026-08-02, `BR52.04`). So the log opens with `session_start: seed=2`
  from the launch bout, and every later bout appends underneath it **with no seed of its own**. A
  reader takes line 1 as the seed for everything in the file.
- **It already caused exactly that error.** `out/logs/combat-20260802-164344.log` contains **two full
  board builds** — 1200 cells / 236 walls / 118 cover / 0 extraction tiles, then 768 cells / 154 walls
  / 66 cover / 8 extraction tiles — and **one `session_start`**. CC read seed 2 off line 1 and reported
  a whole play-by-play under it; the bout analysed was the second one, generated from a different,
  four-digit seed that appears nowhere.
- **`docs/09`'s stated contract is what is broken:** *"a `session_start` event carries the seed as the
  file's FIRST line, so a human session is a regression fixture too."* A session containing bouts whose
  seeds were never written is not replayable from its own log, which is the whole point of the rule.
- **The shape of the fix, not built:** the header should not be an optional argument a caller can
  forget. Either `load_battle` requires a seed, or the bout carries its own and emits it structurally —
  the same argument `load_battle`'s own comment already makes about emitting the header *"structurally,
  between attaching the sinks and building anything, rather than by whoever happens to call this and
  remembers to do it afterwards."* **The comment describes the right rule and the signature does not
  enforce it.** A per-bout event rather than a per-session one, since a file now holds several.
- **`Pending` (2026-08-02).** CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`. Fixed exactly as
  described above, both halves:
  - **The optional argument is gone.** `load_battle(state, mission)` is the only signature, and it
    emits the header itself from `CombatState.bout_seed` — the field is stamped by the two things that
    generate a playable bout (`BoutSetup.build_bout`, which covers the Generate Bout overlay,
    `CompletionSampler.build_for_seed`, `ReplayHandle.from_seed`, the watched-run panel and checkpoint
    9; and `BattleScene._seed_battle` for the launch path).
  - **`session_start` is now `bout_start`**, one per bout. Recorded in `docs/SUPERSEDED.md` and
    `docs/09`.
  - **The ORIGIN seed is what is carried, not `rng.seed`.** Both generators seed a local RNG with the
    origin number and hand `rng.randi()` to `CombatState.new`, so `rng.seed` is derived and would not
    regenerate the map. Logging it would have looked right and replayed nothing.
- **A second half, reported from play (2026-08-02): *"Seeds are showing in the file log, but not at the
  top of the combat log within the new bout. Looks like it's adding the new seed note, THEN clearing
  the ingame combat log."*** Correct diagnosis, and it is an ordering problem.
  - `load_battle()` emits the header into whichever panel is up. `GenerateBoutOverlay` **then** swaps
    the overlay (`load_battle()` first, then `set_overlay(SpectatorOverlay.new())` or
    `toggle_blue_control()`), so the panel that received the header is torn down and the fresh one
    starts empty. The **file** sink survives because `BattleScene` owns it; a **panel** does not,
    because the overlay owns it.
  - **The first fix made this visible rather than causing it.** Before it, that path emitted no header
    at all, so there was nothing for the swap to lose. `_ready()`'s own comment already warned about
    this exact hazard from the other direction — *"Reversing this order drops that first line silently
    — nothing was listening yet when it fired."*
  - **Fixed:** `BattleScene` keeps the current bout's header (`_bout_start`) and
    `_seed_overlay_log_with_the_bout_header()` hands it to a newly installed overlay's sink after
    `setup()`. **Pushed straight into the sink, not re-emitted through `CombatLog`** — a second
    `emit()` would reach the file sink too and write two `bout_start` lines for one bout, inventing a
    duplicate event to close a display gap. `wants()` is still honoured. Scoped to the header
    deliberately: replaying arbitrary history to any late-attaching sink would change what "one
    stream, many sinks" means and would hand a `MemorySink` capturing one turn a `bout_start` it never
    asked for.
  - **Both halves are covered, and the panel test was verified by re-breaking it**: with the call
    removed, `test_an_overlay_installed_after_the_bout_still_shows_the_bout_header` fails on exactly
    the two panel assertions while the duplicate-header test stays green. The test asserts through the
    real handoff — load, *then* swap — because asserting on the panel that was up during
    `load_battle()` passes while the bug is fully present.
- **To see it:** start a bout from Generate Bout with a seed you choose, then read `out/combat.log` —
  that bout's own `bout_start: seed=<yours>` should sit directly above its build steps, underneath the
  launch bout's header rather than replacing it. Starting a third bout should add a third header.
- **The regression test is the one the old shape could not have had**
  (`test_a_second_bout_logs_its_own_seed_not_the_first_bouts`): it asserts on the **second** bout in a
  scene, through the two-argument call, and demands its own distinct four-digit seed. A companion test
  rebuilds the board from the carried seed and asserts `rng.seed != bout_seed`, so the derived-versus-
  origin distinction cannot quietly regress.
- **Resolved by the owner (2026-08-02):** *"I verified it, you can also mark the seed ordering bug
  resolved."* Both halves confirmed in play — the seed reaching the file, and the header reaching the
  top of the in-game panel for a bout started from Generate Bout.
### BR35.05 — Obsolete — owner: `CC`
**`approach_path`/`closing_path` have no ally-awareness — squadmates converge into each other's own line of fire**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23, reading a real bout's own `out/combat.log` at the supervisor's own request
  ("units that are close all holding action"). On turn 0, units 1/2/3 (all sharing a similar start
  position and the same target) independently compute nearly identical `closing_fallback` paths —
  unit 1 and unit 3's own move sequences share the corridor `(6,14)→(7,13)→(7,11)→(11,7)` cell for
  cell — and end up bunched close together: unit 1 at (13,7), unit 3 at (13,8), **directly adjacent**.
  Unit 0's and unit 2's own `ai_decision` lines log `held: ally_in_line` — a squadmate is standing
  in their own intended shot.
- **Root cause:** `LineOfFire.approach_path` (tb33) and `LineOfFire.closing_path` (tb35 Pass A, this
  session) both compute "the nearest cell that gets a shot" (or "the nearest cell that closes
  distance") purely from grid/LOF geometry — **neither has any notion of where other allies already
  are or are heading.** `closing_path` inherited this blind spot from `approach_path` rather than
  fixing it. When several squadmates share a similar starting position and target, they independently
  converge on the same corridor/destination and end up close enough to block each other's own shots,
  which then makes every one of them hold.
- **Not fixed yet.** A real fix (giving the fallback pathing awareness of cells allies already occupy
  or are heading toward, so a squad spreads out instead of stacking) is a genuine design question —
  how much to weight "don't stack with an ally" against "get to a real shot as fast as possible" —
  not a one-line patch, and not guessed at here.
- **`Obsolete` (`CC`, 2026-08-02) — the code this entry describes no longer exists.**
  `docs/SUPERSEDED.md` records `LineOfFire.approach_path`/`closing_path` deleted in tb46 Pass C, with
  their tests and the `APPROACH_MARGIN`/`APPROACH_DEFAULT_RADIUS` constants, after the
  engagement-score planner they were the only caller of retired in tb45 Pass E. Neither function is in
  `src/`.
- **`Obsolete`, deliberately not `Resolved`.** Nobody verified the squads stopped blocking each other;
  the implementation was replaced underneath the report. Writing `Resolved` here would assert a
  verification that never happened.
- **The defect itself survived the rewrite and is now `BR52.10`**, described against the code that
  exists. The old branch planner logged `held: ally_in_line` — it genuinely refused a shot through a
  squadmate — and `UtilityPlanner` carries no consideration for it, so an AI unit now fires through an
  ally rather than holding. **This entry closes because its subject is gone, not because its symptom
  is.**

### BR52.04 — Resolved — owner: `SUPERVISOR`
**`out/combat.log` is corrupt — a third of the file is NUL bytes**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-02. *"Bug: Garbage output in combat log."*
- **Measured, not impressionistic:** 138 436 bytes on disk, **49 403 of them NUL** — one contiguous
  run starting at byte 1073, immediately after `command_outcome: accepted: force_current_unit`. `file`
  reports the log as `data` rather than text.
- **This is worse than cosmetic and it hid itself.** `grep` treats a file containing NULs as binary
  and **silently declines to match**, while `tail` still renders the readable lines — so the log looks
  fine to a human skimming it and returns nothing to every tool CC uses to read it. Several greps
  against this file came back empty during this session before the cause was found.
- **Root cause, from reading `file_sink.gd` (30 lines):** `_init` does
  `FileAccess.open(path, FileAccess.WRITE)`, which **truncates the file to zero**. If two `FileSink`s
  are ever alive on one path, the second truncates while the first still holds a handle positioned at
  ~50 KB; the first's next `store_line` writes at that stale offset and the kernel zero-fills the gap.
  That produces precisely this byte pattern — fresh content, one long NUL run, then the old writer's
  output resuming.
- **The boundary being a debug injection fits**: whatever a bout restart or re-setup does around
  `force_current_unit` is the likeliest place a second sink is attached without the first being
  closed.
- **`Pending` (2026-08-02).** CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`.
  **The supervisor answered the open question: a new bout appends.** *"New bout should append. That
  may not stay true, but it's the better option now."* So a session's log is the whole session.
- **Two defences, because they answer different halves.** `FileSink` opens with `READ_WRITE` (which
  does not truncate; `WRITE` is kept only as a create-if-missing fallback), **and** seeks to the end
  **before every write** — opening at the end alone would not survive a second sink, since each
  handle carries its own position.
- **The class's own doc comment already said "Appends to a real file".** The code truncated. The
  mismatch between the two *was* the bug.
- **The regression tests were verified by re-breaking the fix**, not just by passing: reverted to
  `FileAccess.WRITE`, both new tests fail. That also showed the corruption is not only the
  large-offset NUL case — at small scale the stale handle writes *mid-line*, producing
  `move: from the second sinkmove: the first sink is still alive`.
- **A corrupt log was also breaking the test suite, silently.** `FileAccess.get_as_text()` stops at
  the first NUL, so `test_battle_scene.gd` could not find the session header it had just written and
  went red until the poisoned `out/combat.log` was deleted. The blast radius was wider than "hard to
  read by hand".
- **Appending removed the only thing bounding the log's size, and the supervisor answered it the same
  day: per-session files, old ones subfoldered.** So the two rules are now *a new bout appends, a new
  session rotates* — several bouts in one run share a log, and the next run archives it into
  `out/logs/combat-YYYYMMDD-HHMMSS.log` before starting clean. The **live path deliberately does not
  move**: `tail -f`, `grep` and the startup "log: <path>" line all point at `out/combat.log`, and
  there is only ever one live session, so it is the archive that needs distinct names.
- **Rotation is per path and once per process**, not on every construction — otherwise a second sink
  attaching mid-session would rotate the log out from under the first, which is the very case this
  entry is about.
- **The archive itself will balloon**, and that is filed rather than solved: `PLAN.md`'s *Keep the
  rotated combat logs from ballooning*, to follow the same rolling-window rule `reports/` and
  `taskblock_done/` already use, as the supervisor suggested.
- **`Pending` rather than closed:** this entry is `SUPERVISOR`-owned. **To check:** play a session
  with more than one bout, then `grep` the log. It should match, `file out/combat.log` should say
  `ASCII text` rather than `data`, and the earlier bout should still be there above the later one.
- **Resolved by the owner (2026-08-02, `temp.md`):** *"52.04: Resolved"*. The fix was already
  verified by re-breaking it — reverting `FileSink` to `FileAccess.WRITE` fails both regression tests.
### BR34.05 — Resolved — owner: `SUPERVISOR`
**Misses vanish instead of striking anything**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (post-tb34 check, during the BR30.10 verification). A missed shot appears
  to travel into nothing — it strikes no obstacle at all on its way out, passing through an arena that
  is enclosed on every side.
- **Supervisor's stated rule for how this SHOULD work — a design statement, not just a repro:** a shot
  should **nearly always hit something**. The floor, or one of the many walls surrounding the arena.
  The only legitimate ways for a round to hit nothing are **through an already-broken wall** or **out
  through the ceiling**. Anything else vanishing is wrong.
- **Why this matters more than a visual nit:** it means "miss" is currently modelled as *terminate the
  round*, rather than *continue until something stops it*. That has real consequences now that walls
  are destructible and decompression is a planned hook — a missed burst that should be chewing a wall
  behind the target is instead doing nothing, and the arena never accumulates the damage a firefight
  should leave. It also interacts with **BR34.01** (per-hop playback): a miss that continues has hops,
  and hops are what that entry is about.
- Likely the same neighbourhood as tb35 Pass B's depth floor and the `&"miss"` handling in
  `ResolutionPlayer`/`shot_resolution.gd` — check whether a miss even builds a continuation ray, or
  simply stops.
- **2026-07-23 (tb35 Pass B2 — root-caused and reproduced, not fixed)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. `resolve_shot` does build a real continuation — the
  question was never "does it try," it genuinely finds nothing to hit in some cases. Reproduced
  directly: fired hundreds of simulated shots (`DamageResolver.resolve_shot`) from a unit standing in
  a fully-walled room (real `grid.blockers` Parts on every perimeter cell, both a hand-built room and
  real `BoutSetup`-generated maps) with a wide range of aim points. At an ordinary/tight lateral
  offset (|x| under ~1 unit — the range any single weapon's own authored scatter ring realistically
  produces), **zero** shots vanished, before or after this taskblock's own depth-floor fix — so this
  is a genuinely different defect from BR34.06/BR27.02, not the same one re-surfacing. Once the
  lateral offset is pushed wide (|x| beyond ~4-5 units), misses start appearing reliably (56/200 at
  |x| up to 8) — **`ShotPlane.build` projects each wall cell as its own independent rect; adjacent
  cells' projected rects are not guaranteed to tile edge-to-edge from an arbitrary shooter angle, so a
  sufficiently wide lateral offset can thread a real gap between them and pass clean through, even
  though the room is genuinely enclosed.**
  - **Why a real weapon can reach that range:** a burst's own scatter widens per pull
    (`RecoilResolver.widen`, `factor = 1.0 + resolved_step * recoil_step`) — a late pull in a long
    burst (the chaingun bursts logged elsewhere in this file routinely run 20-30 pulls) can multiply
    the base outer ring (chaingun: `0.6`) several times over, and `RangeModel.dartboard_radius_scale`
    widens it further at long range (up to `1.0 / ACCURACY_FLOOR ≈ 2.86x`). The two compound: a late
    pull of a long burst fired at range is exactly the shape of shot most likely to reach the lateral
    offsets that expose this gap — and exactly the shape of shot ("the most recent chaingun bursts")
    this ledger already has several live reports about.
  - **The supervisor's own "or the floor" half of the design rule has no geometry to hit at all** —
    `ShotPlane.build` only ever projects `state.units` and `state.grid.blockers`; there is no modeled
    floor/ground-plane Region anywhere in this system. That half of the fix is a real feature gap, not
    a bug in existing code.
  - **Not fixed this pass — needs a design call, not an invented number.** This touches `ShotPlane`/
    `BodyProjector`, the shared geometry every single shot in the game resolves against; three
    directions, not picked between: (a) make adjacent same-material blocker cells project as one
    contiguous rect run instead of independent per-cell boxes, closing the seam at the source: (b) cap
    dartboard scatter radius (post-recoil, post-range-widen) at some bound that guarantees plane
    coverage — a real balance number, not this session's to invent; (c) add a genuine floor Region so
    at least the "hits the floor" half of the design rule has something to resolve against. Flagging
    for supervisor/design input rather than guessing.
- **taskblock-51 third hunt — the supervisor re-reported this and CC mis-filed it as a new entry
  (`BR51.03`), now folded back here.** Their words: *"Misses still happening when there is something for
  a bullet to hit; damage should drop outside of range but the bullet should still hit something"*, and
  on being asked whether it was a design change rather than a defect: *"Leave it as a bug, I tried to
  have this changed before so if it's still occurring it's a bug."* — which is this entry, reported
  2026-07-23.
- **One nuance the re-report adds:** range should **attenuate damage**, not delete the projectile. That
  sharpens the fix: the termination is happening at the range gate, not only at the resolution.
- **Still open, still `SUPERVISOR`-owned. Nothing was closed by the merge** — a duplicate record was
  removed, not a bug.

- **taskblock-51 Pass C — investigated, not fixed, and it is bigger than the miss branch.** `ShotPlane.build`
  iterates units, `grid.blockers` and field items. **There is no floor in it**, so a round angled slightly
  down, or passing over and between everything, has nothing to intersect: "miss" is not a wrong branch
  being taken, it is the only branch that exists.
- **`Surface` already carries a `Part` (tb38 made floor and terrain into parts)**, so a floor Region needs
  no stand-in Part and no new outcome type — `ImpactResult.region.part` works with `surface.part` as it
  stands. That removes the design question CC raised about what a floor hit would *mean*.
- **There is a SECOND cause, recorded in `PLAN.md` under *Wide scatter passing through a wall seam*.**
  Wall cells are projected as independent rects that are **not guaranteed to tile edge-to-edge** from an
  arbitrary shooter angle, so a dartboard point can thread a real gap in an enclosed room — reproduced at
  56/200 empties at a lateral offset of ~8. **A floor Region alone would not fix this**; it would convert
  "vanishes" into "hits the floor behind the wall", which is visible but still wrong.
- **So this entry and that `PLAN.md` item are one decision.** Of its three candidates, merging contiguous
  same-material blocker cells addresses the seam, a floor Region addresses the absent backstop, and capping
  scatter radius papers over both with a balance number. **Supervisor's call, and it is queued as a design
  call rather than a code fix.**

- **2026-08-01 (taskblock-52 Pass A — the 56/200 reproduces exactly, and the seam explanation attached to
  it is wrong).** CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`. The harness is committed now
  (`SeamSweep`, `test_seam_sweep.gd`), so this is re-takeable rather than remembered.
  - **The number is real and the room is what produces it.** 56/200 reproduces to the shot — in an
    **11x11** room and no other. Room size sweep: 9-room **80/200**, 11-room **56/200**, 13-room
    **24/200**, and 17-, 21- and 31-rooms **0/200**. A count that tracks the room rather than the walls is
    not measuring a projection artifact.
  - **The threshold is the wall's own face, to the sample.** Along one axis in 0.25 steps, the last hit is
    at lateral **5.25** and the first miss at **5.50**; the perimeter wall box's outer face is at exactly
    **5.50**. A rect-tiling seam scatters empties across offsets and angles — this is one clean edge
    sitting precisely on the geometry.
  - **The real mechanism: a scattered round is modelled as a *parallel* ray.** `DamageResolver._find_next`
    tests every region at a **constant** lateral offset, so the modelled flight is
    `origin + perp * point.x + dir * t` — the whole round, muzzle included, translated sideways by the
    full dartboard displacement rather than diverging from the gun. At lateral 6.0 in an 11-room the
    flight begins at `(5.00, 11.00)`, **off the board**. It does not thread the wall; it never reaches it.
    Asserted directly: a round vanishes exactly when its own start point is out of bounds.
  - **And there is no measurable seam.** A 41x41 room swept at 90 angles x 41 offsets out to 15, every
    offset well inside the walls: **0/3690 empty.** If adjacent wall cells failed to tile edge-to-edge
    from an arbitrary angle, that is where it would show.
  - **What this changes:** the fix is not "merge contiguous blocker cells" (there is no gap to close) and
    not "cap scatter radius" (that would hide a modelling error behind a balance number). It is that
    resolution should march from the real muzzle to the aimed point, which is what taskblock-52 builds.
    The floor half of this entry is untouched and still real — there is still no floor to hit.
  - **Still `SUPERVISOR`-owned.** The corrected diagnosis above stands on its own measurements; what
    follows is the fix built on it.

- **NOT `Pending` — the fix is built and is not switched on** (taskblock-52, Passes A-F). CC session
  `c0dfa479-2b43-4d9c-832d-12a7fd232bce`. `RayChain` addresses both halves of this entry and is
  approved for adoption, **but `CombatState.shot_resolver` still defaults to the plane**, because
  flipping it red-lights 14 tests. Nothing a supervisor could look at has changed yet, so marking this
  `Pending` would be claiming a fix nobody can see. Recorded here so the work is not re-derived:
  - **The wide-offset half** — a round marches from the real muzzle to the aimed point, so it
    diverges from the gun instead of being translated sideways with it. A wide dartboard offset can
    no longer relocate the flight outside the building.
  - **The "or the floor" half** — `grid.surfaces` is in the march, and `ship_floor`/`ramp` carry real
    authored geometry. A round angled down finally has something to intersect; there was previously
    no branch for it to take.
  - **Measured:** the seam experiment **56/200 -> 0/200**; **0/360** empty across a 72-angle x
    5-offset sweep inside a closed room; **59/59** shallow downward shots landing.
- **To see it:** fire **wide** — a late pull of a long chaingun burst at range is exactly the shape
  that used to vanish — and fire **down at the deck**, which previously had no geometry at all. Every
  round should leave a mark on something.
- **What is still legitimately a miss**, so it does not read as a regression: a round that leaves an
  unenclosed board, or goes out through a broken wall or the ceiling. That is `docs/02`'s stated rule
  and it is asserted — on an open board a shot misses *exactly when* its own flight would run past the
  board before reaching the deck.
- **What still stands between this and `Pending`:** the flag flip, and the 14 failures it exposes.
  **Note `BR52.03`** too: terrain risers have no geometry behind them, so a round fired horizontally
  into a *step* on a multi-level map still passes through it — a known remaining hole, filed
  separately rather than folded in here.
- **Resolved by the owner (2026-08-02, `temp.md`):** *"34.05: you can put your evidence in, but it
  looks resolved. You can mark it as such"*.
- **The evidence, recorded on closure.** Under test: **0/360 empty** across a 72-angle x 5-offset sweep
  in a closed room, **59/59** shallow downward shots landing, and the seam experiment **56/200 -> 0/200**.
  This is live in the game rather than behind a flag since the taskblock-52 Pass F flag flip.
- **Confirmed against a real battle** (`out/combat.log`, seed 2, 2026-08-02): **156 impacts and zero
  `miss` events** across six full 12-round chaingun bursts. Every pull of every burst logged as landed
  (`12/12 landed so far`, six times). Nothing vanished.
- **This entry's original diagnosis was wrong and was corrected in place before closure**: the cause was
  the plane's parallel-ray scatter model relocating the whole flight, not wall rects failing to tile.
- **A ledger/report mismatch is recorded rather than hidden:** `reports/Report-Taskblock52.md` listed this
  entry as moved to `Pending`, and the move never landed here — the heading still read `Active` at
  closure time. The report is on a rolling five-block window and the ledger is not, so the ledger is what
  needed the mark.
### BR30.10 — Resolved — owner: `SUPERVISOR`
**Shots resolve straight through walls**
- **Source:** `SUPERVISOR`
- **2026-07-23 (supervisor check — NOT confirmable yet).** Rounds are definitely striking walls now,
  so the core of the fix is doing something — but there are enough remaining inconsistencies that the
  fix can't be signed off. Three specific findings came out of this check and are filed separately:
  **BR32.07** (burst can't engage a wall at all — symptom has since shifted, see that entry),
  **BR34.05** (misses vanish instead of striking anything), and the depth-floor defect that tb35 Pass B
  addresses. Leave `Pending Confirmation` until those are settled — several of them are probably the
  "inconsistencies" observed here rather than separate phenomena.
- **Reported:** 2026-07-21, live play testing BR27.01: an attack against an enemy on the opposite side
  of a wall tile connects as if the wall isn't there. Confirmed by the supervisor as their very first
  test case, deliberately, not an accidental cross-cover shot.
- **Root cause, confirmed by code:** `LoS.has_los()` (`src/logic/los.gd`) and `ShotPlane.build()`
  (`src/logic/shot_plane.gd:19-46`) read entirely disjoint data. `LoS` reads only `grid.opacity` (set
  to `1.0` for wall cells by `MapGen.generate()`, `map_gen.gd:52-56`) — correctly treats walls as
  opaque for TACTICAL gating (aim-mode/step-out decisions). `ShotPlane.build()` only ever projects
  `state.units` and `state.grid.blockers` (`shot_plane.gd:24,33`) into the depth-sorted hit plane —
  never `grid.opacity`. `MapGen` never writes a `blockers` entry for WALL cells — only
  `_scatter_cover()` (`map_gen.gd:201-208`) populates `blockers`, and only for scattered cover props on
  `OPEN` cells. So a real wall has an opacity flag but no Part, no mesh, nothing in `grid.blockers` —
  it is entirely invisible to the actual damage-resolution path, which only ever sees shooter, target,
  and scattered-cover Parts. `docs/02` (`docs/02-projection-and-targeting.md:82-84`) already documents
  the intended fix: terrain should be "a Part flagged indestructible" living in the same plane as
  everything else — never implemented for walls, only for scattered cover.
- **View-layer confirmation:** walls have no 3D volume either — `BoardView._build_wall_indicators()`
  (`src/view/board_view.gd:239-245`) only draws a flat floor decal (`WALL_INDICATOR_HEIGHT = 0.015`)
  plus a thin decorative cross; no `CollisionShape`/`StaticBody` exists for walls anywhere in
  `src/view/`. This matches the supervisor's own observation that walls are "visually nothing" beyond
  the debug 'x' marker.
- **Fix:** `MapGen._stamp_wall_geometry()` (new, runs last in `generate()`, after
  `_ensure_spawns_connected` so it sees the grid's final layout) gives every WALL cell that borders at
  least one non-WALL cell a real, indestructible `Part` in `grid.blockers` — `data/parts/wall.tres`
  (new: a full-cell box, `is_destructible = false`, matching docs/02's own "terrain is a Part flagged
  indestructible"). A WALL cell buried in solid, unreachable rock (no non-WALL neighbor) deliberately
  gets no blocker — it can never be the nearest hit along any real ray, so skipping it is a pure perf
  win (`ShotPlane.build`'s own per-shot scan is unculled), not a behavior change.
  `LoS.has_los()` is unchanged (opacity-only) — it already correctly treated walls as opaque; only the
  hit-resolution side was blind to them.
- **Side effect, expected and not chased further this pass:** as a direct consequence of walls now
  really blocking, this landed a follow-on discovery — a live seed-search on `test/integration/
  test_full_mission.gd` (whose own hardcoded `SEED` now fails, same "a real mechanics fix reshuffles
  the deterministic timeline" pattern that test's own header already documents five times over) showed
  **81% of all impacts in one full mission (368/457) landing on a wall instead of the intended
  target** — the AI appears to fire without ever verifying a genuinely clear line of fire, trusting
  `ShotPlane` alone to arbitrate (harmless before this fix, since nothing ever blocked a shot). Likely
  why missions now grind through more turns under the fix. Not filed as its own bug yet — flagged here
  as the reason `test_full_mission.gd`'s current failure may need more than a seed re-pick, and as a
  candidate follow-up investigation into AI engagement/target selection (taskblock-45 retired the
  planner named here; the successor is `UtilityContext`/`UtilityScorer` — `UnitAI._pick_engagement_
  position`/`_engagement_score`).
- **Verified:** `test_shot_plane.gd::test_a_wall_part_between_shooter_and_target_blocks_the_shot` (a
  wall Part between shooter and target intercepts the shot; the target is still there once the wall is
  excluded) and `test_map_gen.gd::test_exposed_wall_cells_carry_a_blocking_part_interior_walls_do_not`
  (every exposed wall cell across 50 seeds carries the blocker; every fully-interior one doesn't).
  1868/1869 green — the one remaining failure is `test_full_mission.gd` itself, above, a known,
  expected consequence, not chased this pass (supervisor's own call: "consider the full test failed
  for the moment, we have a couple other things to check").
- **RESOLVED-PENDING-CONFIRMATION** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit pending.
- **2026-07-28 (supervisor check — still blocked, left `Pending` deliberately).** Cannot be confirmed
  until the drawn beams are trustworthy: this entry's evidence is read off tracers, and
  `PLAN.md`'s **Tracers and hit visuals** covers the defects that make them unreliable.
- **Three of that cluster corrupt this entry's evidence specifically**, so it cannot be signed off
  while any of them is open:
  - **BR35.07** — `STOP_DEAD` tracers drawn *past* their own hit point. A round that correctly stops at
    a wall is drawn continuing through it, which is this entry's exact symptom rendered by a different
    bug.
  - **BR34.05** — misses vanish instead of striking anything, so a round that *should* mark a wall
    leaves no evidence either way.
  - **BR35.04** — a DEFLECT's bounce tracer is a decorative fixed-range projection rather than the real
    continuation, so a post-deflection path tells you nothing about what it actually hit.
- **Re-check after that cluster lands**, not before. Watching for wall strikes against tracers that
  misreport where rounds stopped is how this entry produced three spin-off findings and no closure last
  time.
- **Resolved by the owner (2026-08-02, `temp.md`), conditional on verification:** *"30.10: Looks
  resolved. Double check the current combat.log and verify."*
- **Verified against `out/combat.log`** (seed 2, real battle, 2026-08-02). The original symptom was that
  walls existed for `LoS` but not for resolution — no Part, nothing in `grid.blockers`, invisible to the
  damage path. Measured now:
  - **44 wall impacts** in one battle — 30 `DEFLECT`, 14 `STOP_DEAD`. A wall is struck more often than
    any other single object on the board.
  - **Every wall hit lands on a wall face plane** (`y=2.50` for the contested wall), not at a cell
    centre — so the round is meeting real geometry, not a cell flag.
  - **Zero `PENETRATE` outcomes anywhere in the battle** (78 `DEFLECT`, 78 `STOP_DEAD`). No round passed
    through anything, wall or otherwise. With the chaingun at 1.6 effective damage against steel's
    `dt` of 6.0, nothing fired in this battle *could* penetrate.
  - Rounds that deflect off a wall continue and strike real objects with a real second origin
    (`DEFLECT on wall -> STOP_DEAD on forklift`), which is the ricochet path working, not a pass-through.
- **Closed on the ray chain, not on the plane.** The taskblock-52 Pass F flip is what makes wall geometry
  the thing a shot actually marches through. The three findings this entry was held open for are settled:
  `BR32.07` shifted, `BR34.05` closes alongside this, and tb35 Pass B took the depth floor.
### BR35.01 — Resolved — owner: `CC`
**`PartPicker.hit` scans every `grid.blockers`/`field_items` entry on every hover, not just ones near the ray**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23 (tb35 Pass C, `Grid.blockers` audit sweep). `PartPicker.hit()`
  (`part_picker.gd:40,48`) iterates every entry in `grid.blockers` and `grid.field_items`
  unconditionally, running a full per-box ray test (`_nearest_t`) against each one regardless of the
  ray's own direction or distance from it. Before tb31 C, `blockers` held a handful of scattered cover
  props — cheap to fully scan. Now it holds every wall cell on the map (confirmed: real generated
  bouts run 200+ blocker entries), and this runs on **every mouse-move**, not just clicks
  (`TacticsController.update_hover()` calls `_cell_at()` → `PartPicker.hit()` on hover, per its own
  doc comment) — a real, newly-introduced per-frame cost, not hypothetical.
- **Not fixed this pass.** The safe fix (march only cells the ray plausibly crosses — a bounded
  grid-DDA walk along the ray's own 2D projection, the same shape `LoS.has_los` already bounds its own
  opacity walk to) touches core picking geometry with a real risk of silently skipping a genuine hit
  if the bound is gotten wrong, and this codebase has already been burned once by a plausible-looking
  formula nobody could verify without a live client (docs/00's own attack-camera yaw story). Flagging
  rather than guessing at a fix under time pressure.
- **2026-07-26 — NOT addressed (tb42 Pass E)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Named in
  the pass as a companion item and deliberately left: `PartPicker.hit` still scans every
  `grid.blockers`/`field_items` entry per call. Stated rather than quietly dropped — it is `CC`-owned
  and small, and belongs to whoever picks this up next.
- **taskblock-51 — measured, and it is NOT the aim-view framerate cause.** `PartPicker.hit` costs
  **1 559 usec** on a 214-blocker board against `ShotPlane.build`'s **10 889**. `BR26.02` was caused by
  the aim plane being rebuilt per mouse motion, not by this scan.
- **Still worth fixing on its own merits** — it is real waste on every hover — but this entry has now
  absorbed three reasoned-not-measured fixes, and the standing instruction to measure first applies
  with more force, not less, now that the obvious theory has been falsified once.

- **`Pending` (taskblock-51).** `hit` now rejects a cell whose perpendicular distance from the ray
  exceeds `SKIP_RADIUS`, before the per-box assembly test. **Measured on the same 216-blocker probe the
  rest of this block used: 18 454 -> 14 390 usec per mouse motion (54 -> 69 fps).**
- **The reject is deliberately conservative** — admitting a cell the real test then rejects costs a
  little time; rejecting one that would have been hit is a shot passing through a wall. `SKIP_RADIUS` is
  3 cells because a part's boxes can overhang the cell it sits in.
- **This is a mitigation, not the structural fix** the entry describes: the scan is still linear in the
  blocker count, just with a cheap reject in front. A spatial index is the real answer and is not
  attempted here.
- **`Pending` rather than closed:** the win is a framerate the supervisor can feel and CC cannot see, and
  `BR51.14` is still open on the same path.
- **What to look for (supervisor asked).** This one is **measured, not seen**: move the mouse across a
  board with many wall cells while a unit is selected and read the perf panel. The claim is
  **42 527 → 14 390 usec per mouse motion**, so it should feel like a partial recovery of the
  hover stutter, not a fix. **`BR51.14` is the entry for what you still feel** — it is the same symptom
  on the non-aim path and is still open, so if hovering still stutters that is expected and belongs
  there rather than here.
- **This is a mitigation, not the structural fix.** The scan is still linear with a cheap reject in
  front of it; a spatial index is the real answer and is not done.
- **Resolved (`CC`, 2026-08-02), re-measured on the owner's instruction** (*"35.01: Go ahead and
  remeasure now."*). `test_aim_cost_probe.gd`, 214-blocker board, 6 units:
  **`PartPicker.hit` = 774 usec**, against the **1 559 usec** recorded for the same probe in
  taskblock-51 before the `SKIP_RADIUS` reject. **A 2.0x improvement, and the fix holds.**
- **Context from the same run, so the number is not read alone:** `ShotPlane.build` 9 232 usec,
  `CombatState.dup` 27 478 usec, `Grid.dup` 21 564 usec. The picker is now roughly **3 percent** of what
  a single `CombatState.dup` costs, which is what retires it as a hover-cost suspect.
- **The falsified theory stays recorded**: this entry was blamed for the aim-view framerate and was not
  the cause — `BR26.02` was the aim plane being rebuilt per mouse motion. Three reasoned-not-measured
  fixes preceded the one that worked, which is why closure waited on a re-measurement rather than on
  the fix looking correct.

### BR52.08 — Resolved — owner: `CC`
**Every "muzzle height" test in `test_attack_action.gd` fires from 1.25 regardless of the height it
passes in**
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-02, taskblock-52 Pass F, while updating fixtures for the flag flip.
- **`_make_weapon` authors no `volume`.** So `UnitGeometry.muzzle_point` finds no placement for the
  weapon and falls back to `DEFAULT_MUZZLE_HEIGHT` (1.25). **`_make_shooter_with_grip_height`'s own
  `grip_y` argument therefore reaches nothing** — a test asking for a hip-height 0.3 muzzle gets a
  1.25 one.
- **Why it went unnoticed for five blocks, and this is the interesting half:** the shot plane resolves
  at the **aim point's** height rather than along the muzzle-to-aim line, so where the muzzle actually
  sat never affected the outcome. The fixture could be wrong and the test still green.
- **It stops being harmless under the ray chain**, which marches muzzle-to-aim: a round from 1.25 down
  to a 0.5 chest is at ~0.87 where 0.6 cover stands and correctly clears it. So
  `test_a_hip_height_muzzle_behind_low_cover_hits_the_cover_not_the_target` will invert the moment the
  resolver flips — and it is **not** a regression when it does.
- **Fix: give the fixture weapon a real `volume`.** Attempted in this pass and reverted: it moves the
  muzzle for every test in the file at once and cascaded into three further failures that wanted their
  own judgement. It is a contained job, just not a five-minute one, and doing it *before* the flip is
  what keeps that flip readable.
- **The affected tests are marked in place** rather than left to surprise whoever flips the flag.
- **Resolved (`CC`, 2026-08-02, taskblock-52 Pass F), and the entry above was wrong twice.**
  - **It was two cancelling defects, not one.** `_make_shooter`'s HAND socket was *also* an identity
    transform, putting the hand — and so the muzzle — at world Y=0, on the deck. The missing `volume`
    was hiding it, because `muzzle_point` returned its fallback before the socket chain was ever
    consulted. **That is why the first attempt cascaded**: fixing only the volume makes every test in
    the file fire from the floor. Fixing both is behaviour-preserving by construction — the weapon
    carries `data/parts/pistol.tres`'s own box verbatim, the HAND socket carries
    `DEFAULT_MUZZLE_HEIGHT`, so the baseline shooter genuinely produces the 1.25 it was accidentally
    producing before, and `grip_y` finally reaches the muzzle.
  - **The prediction that the hip-height cover test would invert was wrong.** It passes under both
    resolvers. The ~0.87 figure measured the *broken* fixture; at the real 0.3 grip height the round
    is at **0.4** where the 0.6 cover stands, and strikes it. The test now asserts what its name
    claims for the first time in five blocks. Verified with the full suite green under the flipped
    flag.

### BR51.05 — Resolved — owner: `SUPERVISOR`
**A dead or prone unit cannot be selected**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-30, taskblock-51 Pass A.
- **Repro:** attempt to click a downed or prone unit. Selection does not take.
- **Suspected same root as `BR51.04`:** if a dead unit is still the current unit, and selection is
  gated on *being* the current unit, then both symptoms follow from one stuck turn pointer. Check them
  together; fixing one blind may move the other without explaining it.
- **Worth separating deliberately:** *dead* and *prone* are different states, and it is not yet
  established that both fail. Confirm which.
- **Resolved by the owner (taskblock-51, third hunt):** *"Can't seem to force it, consider it resolved
  along with 51.04."* Recorded as owner-directed on a failure to re-provoke, not as a CC verification —
  the underlying `select()` rule that refuses dead units is unchanged and was never the thing fixed.

### BR51.04 — Resolved — owner: `SUPERVISOR`
**Killing a unit during its own turn does not end that turn**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-30, taskblock-51 Pass A.
- **Repro:** while a unit is the current unit, kill it (Inject `kill`, or in play). The turn does not
  advance.
- `EndTurnAction` is documented as legal and advancing *"even if the current unit just died"*, and
  `CombatState.advance_turn` skips the dead — so the rule exists and something is not reaching it.
  The likely gap is that nothing *invokes* the advance when the death happens outside an action's own
  resolution.
- **Probably one defect with `BR51.05`**, which the supervisor flagged as possibly related.

- **`Pending` (taskblock-51) — CC believes this fixed; the owner has not seen it work.**
  `CombatState.kill_unit` now advances the turn when the unit it kills is the current one. It was
  marking the unit dead and stopping, leaving `_current_unit_id` on a corpse.
- **Guarded against reordering the round for an incidental death:** killing a *non-current* unit leaves
  the turn exactly where it was, and the advance is suppressed while `is_resolving`, so a shot that
  kills the acting unit mid-queue still ends its turn through the ordinary path rather than through a
  second mechanism racing the first.
- **To see it work:** during a unit's own turn, Inject → `kill` on that unit. The turn should pass to
  the next living unit instead of sticking.
- **Resolved by the owner (taskblock-51, third hunt):** *"Bug as written resolved."* Killing the acting
  unit now passes the turn on. **A related defect was found in the same session and is filed separately
  as `BR51.09`** — the dead unit is no longer current, but it is still *selected*, so its movement
  overlay lingers into the next unit's turn.

### BR27.04 — Resolved — owner: `SUPERVISOR`
**Lighting differs between spectator and player view**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27 D1b: spectator and player view are said to light the board
  differently.
- **Investigated, no code fix applied:** `BattleScene._ready()` already builds
  `WorldPalette.world_environment()` and `WorldPalette.directional_light()` exactly once, as
  children of the shared `BattleScene` itself — strictly before either overlay
  (`SquadControlOverlay`/`SpectatorOverlay`) is installed via `set_overlay()`. Neither overlay
  constructs its own lighting anywhere; both render the same lights on the same world. The code
  does not support the premise of a divergence as currently written.
- **Status:** not resolved — needs the supervisor's own visual re-check (a real screenshot
  comparison) rather than a code claim, since no divergent lighting path was found to remove.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** re-confirms the prior
  pass's conclusion — no new code path found. Genuinely needs the supervisor's own visual/screenshot
  re-check, not further code digging.
- **Closed by the owner, taskblock-51 Pass A, on their instruction.** The supervisor re-checked and
  does not see it: *"I don't see this happening, however I don't remember reporting this bug this way,
  likely a misfile. Mark it resolved, if it shows again we'll move it back to active."*
- **Recorded as owner-directed rather than CC-verified.** CC did not reproduce or fix anything here —
  the entry closes because the person who owns it looked again and withdrew it, and the standing
  agreement is that it returns to `Active` if it reappears.

### BR49.01 — Resolved — owner: `CC`
**The turns budget still gates on luck — a second clock-seeded file was never excluded**
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-30, taskblock-49. A full gate went red on the work budget, and re-running it
  passed. **The retry is the symptom, not the fix** — three consecutive runs measured total turns of
  **970, 1305 and 961** with no code change between them.
- **taskblock-48 excluded `test_full_mission.gd`'s turns** because that file seeds from the clock on
  purpose, and gating on it is gating on luck. That exclusion is correct and incomplete:
  **`test_completion_sampler.gd` also runs a clock-seeded window** — 305 turns across 10 bouts in the
  committed profile, ~30 turns a bout — and it is not in `TURNS_EXCLUDED`.
- **The arithmetic, so the margin is visible rather than asserted:** baseline 772 turns × 1.15 headroom
  → limit **888**. A calm run counts 961 − 198 (excluded) = **763**, comfortably under. The 1305 run
  leaves roughly 1100 counted, which is over. The budget is therefore passing on the median draw and
  failing on an unlucky one, which is precisely the failure mode taskblock-48 set out to remove.
- **Do not simply add the file to `TURNS_EXCLUDED`.** Two of the four gated counters would then be
  measured over a shrinking slice of the suite, and an exclusion list that grows whenever it fires
  stops being a budget. The real question is whether that window needs its own clock-seeded sample at
  all now that `BoutCorpus` exists — which is the same 102.3 s row the taskblock-49 audit flagged as
  the suite's single biggest cut candidate. **Fixing the cost and fixing the flake are probably one
  change**, and it is queued in `PLAN.md` under acting on the audit.
- **Resolved (taskblock-50 Pass D), on a structural argument plus one measurement — stated so the
  evidence is not overread.** `BoutCorpus` no longer plays a fixed eight-seed sample; it stops
  at the first completion, so the healthy case plays one bout and the variance that caused this is gone
  at source rather than excluded from the budget: eight bouts became one, so whatever spread a single
  bout still has is about an eighth of what it was. Confirmed by one post-fix full gate (615 turns
  against a pre-fix 657/846/970/1305), not by a repeated series. The exclusion list was deliberately **not** grown —
  `SuiteBudget.TURNS_EXCLUDED` still names only `test_full_mission.gd`, and whether even that can now be
  removed is noted in the taskblock-50 report as wanting a few runs of evidence first.
- **Not the same as the tb48 finding, and worth keeping distinct:** that one was about which file the
  variance came from, this one is about the exclusion having been written against a file rather than
  against the property (*this test samples rather than pins*).

### BR26.01 — Resolved — owner: `SUPERVISOR`
**Opposing team teleports before the player's own attack lands**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the last blue unit took its turn and the opposing team
  appeared to jump to new positions before that unit's attack animation resolved."
- **Root cause:** `SquadControlOverlay._on_turn_ended` called `advance_ai_turns(battle)` — which
  fast-forwards every AI turn with NO animation at all, a single instant `refresh_unit_views` at its
  own end — BEFORE the human's own turn had even started its own animated `resolution_player.play()`,
  and that `play()` call wasn't even awaited.
- **Fix:** reordered so the human's own turn is fully awaited through its complete animated playback
  before `advance_ai_turns` runs at all.
- **2026-07-20:** supervisor could not verify — blocked by a separate, new issue encountered during
  the attempt. **Verification deferred to the next taskblock** (supervisor's own call) rather than
  chased now; still pending either way.
- **RESOLVED** 2026-07-21 — supervisor could not reproduce on retry. taskblock-26 Pass B1.
- **2026-07-21, follow-up:** the underlying "AI batch is one synchronous, unanimated block" mechanism
  this bug's own fix left in place resurfaced as a heavy hitch instead of a teleport — see **BR27.09**,
  which now carries the live investigation.

### BR27.05 — Resolved — owner: `SUPERVISOR`
**Action bar items still selectable without enough AP**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20 (tb27 review). The tb27 Pass D3 fix (dim/disable unaffordable action-bar
  slots) **did not hold** — slots are still clickable/armable when the unit can't afford them.
- **Root cause (2026-07-21, tb30):** `ActionBar.refresh()`/`_on_box_gui_input()` both compared against
  `tactics.selection.selected_unit.ap` — the raw, un-queued unit. Per docs/09's own "queuing mutates
  nothing," `unit.ap` never drops for an action that's merely queued this turn, only once it resolves
  — so any AP already committed to an earlier queued action (e.g. a move that burned AP once MP ran
  out) was invisible to a LATER slot's own affordability check, which kept comparing against the
  unit's full starting AP.
- **Fix:** both call sites now read `tactics.selection.previewed_unit()` instead — the same source
  `SelectionController.reachable_cells()` already uses for the identical reason (it replays the
  current queue and returns what's actually left).
- **RESOLVED** 2026-07-21 — supervisor confirms: "I just cleared it visually." Commit `1c13ae5`. New
  regression test queues a move that burns AP via 0 MP, confirmed it fails without the fix and passes
  with it (`test_action_bar.gd::test_an_action_already_queued_this_turn_counts_against_a_later_
  affordability_check`). 1861/1861 green.

### BR27.06 — Resolved — owner: `SUPERVISOR`
**Step Out no longer occurs at all**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20 (tb27 review). After the tb27 Pass B flow restructure (BR27.01), Step Out
  now **doesn't happen at all** for the player — a regression past the original four symptoms.
- **Status:** reopened, and likely *the* blocker that stopped the supervisor verifying BR27.01/BR26.01
  ("blocked by a new, separate bug encountered during the attempt"). The split-flow restructure
  (confirm-cell → free out-leg → aim mode → fire → free return) probably breaks such that no step-out
  path completes. High priority — it gates confirmation of two other pending bugs.
- **2026-07-21 (taskblock-30): could not reproduce through any headless path — logged as a real
  negative result, not a fix.** Three new regression tests, each a strictly more realistic
  reproduction of the reported click sequence than the last, all pass on the SAME covered-corridor
  geometry `test_tactics_controller_step_out.gd` already used:
  1. `test_a_real_mouse_click_on_a_covered_enemy_also_enters_step_out_mode` — a real
     `InputEventMouseButton` through a real camera raycast into `TacticsController._handle_mouse_
     button` (every pre-existing test in the file drove `click_cell()` directly instead — a real,
     previously-uncovered code path, just not the bug).
  2. `test_action_bar.gd::test_clicking_an_affordable_action_still_arms_it` (already existed, already
     green) — a real ActionBar slot click arms `&"shoot"` correctly.
  3. `test_squad_control_overlay.gd::test_the_real_production_wiring_enters_step_out_on_a_covered_
     enemy` — the full real `SquadControlOverlay`/`TacticsController`/`ActionBar`/`CameraRig` wiring
     (`_build_ui`'s own construction, not a bare `TacticsController.new()`), driven by a real
     action-bar click THEN a real raycast-driven board click, end to end.
  - **Every layer of the reported click sequence checks out correctly in isolation and combined.**
    Two live hypotheses left, neither confirmable headlessly: (a) the trigger condition
    (`UnitAI.is_covered_from` + at least one legal `StepOutPlanner` candidate) may simply be too rare
    on REAL `MapGen`-generated maps to ever fire in practice — reading as "never occurs" without being
    a code regression; (b) the supervisor's own repro used a different weapon/geometry/click sequence
    than this fixture reproduces. **Needs either a more specific repro (which map/weapon/exact
    clicks) or a real-map rarity sweep before further guessing is worth the cost** — not chased
    further this cycle, per tb30's "don't loop within a block" instruction. Still open.
- **2026-07-21 (taskblock-30, same-day follow-up): hypothesis (a) disproved, root cause found.** A
  60-seed sweep of real `MapGen` maps driven through full AI-vs-AI bouts (`BoutSetup.build_bout` +
  `BoutRunner`) found ~1850 genuine covered-with-a-legal-candidate encounters across those 60 seeds —
  not rare at all. `MapGen._scatter_cover` never sets `grid.opacity` (only `blockers`), so the
  overwhelming majority of those are also plainly LOS-visible and clickable, not "no LOS at all" edge
  cases. That ruled out (a) and pointed back at the code path itself — same bug class as BR27.05:
  `TacticsController._enter_aim_or_step_out_mode` read `selection.selected_unit` directly. Per
  docs/09's own "queuing mutates nothing," that stays at wherever the shooter started the turn until
  the queue resolves — so a player who moves toward/into cover and THEN arms a shot had cover
  evaluated from the STALE pre-move cell, silently falling through to ordinary aim mode instead of the
  step-out the shooter's real, about-to-be-true position warranted. Every existing test in
  `test_tactics_controller_step_out.gd` armed+clicked from the shooter's own turn-start cell, never
  after a queued move — the exact gap that let this ship unnoticed.
- **Fix:** swapped to `selection.previewed_unit()` — the same source `reachable_cells()` already
  reads for the identical reason.
- **RESOLVED** 2026-07-21 — supervisor confirms: "step-out is occurring." Commit `d42f744`. New
  regression test queues a move from an uncovered cell into the same covered cell every other test in
  the file starts at, then arms+clicks: confirmed it fails without the fix (falls into ordinary aim
  mode) and passes with it. 1862/1862 green.

### BR30.01 — Resolved — owner: `SUPERVISOR`
**Debug-spawned unit renders no visual model**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, live bout review). "Spawn unit does not create a visual
  model, but the inspect shows it, indicating something all the debug options use is the issue."
- **Root cause:** `BattleScene.unit_views` was only ever populated once, in `load_battle()`'s own build
  loop. `BoutInjector.spawn_unit` adds a unit straight into `combat_state.units` — real data, inspect
  panel reads it fine — but nothing ever constructed a `HitVolumeView` for it.
- **Fix:** new `BattleScene.sync_unit_views()` diffs `combat_state.units` against `unit_views` and
  builds the missing view(s), the exact same construction `load_battle()` runs. Both overlays'
  `_on_debug_panel_applied` call it before `refresh_unit_views()`.
- **RESOLVED** 2026-07-21 — supervisor confirms: "Fixed for spawning units."

### BR30.03 — Resolved — owner: `SUPERVISOR`
**Debug-removed unit never visually looks dead**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, same review as BR30.01/BR30.02): "clicking remove on a
  unit is removing it data side, but not visually."
- **Root cause:** `HitVolumeView.is_downed()` (the one check `refresh()` makes to pick the DOWN pose)
  reads `Unit.resolve_matrix() == null`, never `alive` directly — the same thing a REAL kill leaves
  behind (`DamageResolver.eject_matrix_if_needed` nulls the hosting part's own `hosted_matrix`, drops
  it as a loose `Grid.field_items` entry, THEN calls `kill_unit`). `BoutInjector.remove_unit` only ever
  did the `kill_unit` half — `resolve_matrix()` kept finding the still-docked matrix, so the view never
  changed.
- **Fix (first pass):** `remove_unit` now ejects the hosted matrix the same way first (drops it as a
  real field item at the unit's own cell), then kills as before.
- **Renamed to `kill` (2026-07-21, same-day follow-up):** the supervisor's own next request split debug
  removal into two distinct verbs — "Kill is a new feature, that forces matrix ejection the way you
  designed," separate from a generalized `remove_object` ("fully vanishing it," BR30.02's own report
  covers the move/spawn/remove-object round). This fix's own behavior is unchanged, just renamed
  `BoutInjector.kill` — `remove_object` (new) is debug-only cleanup with no matrix ejection at all.
- **RESOLVED** 2026-07-21 — supervisor confirms: "looks fixed." Commit `c930930` (original fix),
  renamed in `6f42a4f`, 1860/1860 green.

### BR31.01 — Resolved — owner: `SUPERVISOR`
**Bottom-right turn controls and tooltip popups fight over clicks**
- **Source:** `SUPERVISOR`
- **Confirmed fixed by the supervisor (2026-07-22).**
- **Reported:** 2026-07-22 (tb31 review), long-standing: "the controls on the bottom right of the
  player view don't block the tooltip popups, making them difficult to click."
- **Symptom (supervisor's words, exact interaction TBC before fixing):** the bottom-right controls
  (`turn_controls_column` — Resolve to Here / End Turn / Reset Turn) and the tooltip popup layer
  (`TooltipController`/`TooltipView`) overlap, and the tooltip's presence makes the controls hard to
  click. Not yet pinned to which layer intercepts which.
- **Candidate mechanism (do not blind-fix — confirm first):** a `mouse_filter`/z-order interaction
  between the tooltip layer and `turn_controls_column`, the same class as Pass A's own
  `TopLeftControls` STOP→IGNORE fix and BR30.05 (debug-panel click bleed-through). Likely the tooltip
  popup sits over the controls with a filter that swallows the click, or the controls' own hover
  raises a tooltip that then covers them. Reproduce and read the real node rects/filters back (docs/10
  standing rule 2) before changing anything.
- **2026-07-22 (tb32 Pass D) — reproduced, root cause is NOT mouse_filter:** a real synthetic click
  (`InputEventMouseButton` pushed through the real `Viewport`, `test_battle_scene_input.gd`, the one
  file that routes input through the actual Control tree rather than `click_cell()`) proves End Turn
  still receives the click even with the tooltip visually positioned directly over it —
  `TooltipView`/its label both already carry `MOUSE_FILTER_IGNORE`. The real bug: nothing ever hides a
  STALE tooltip left over from hovering the 3D board right before the cursor crosses onto a
  turn-control button. `TacticsController`'s own hover tracking (`update_hover()`, which would clear
  it) lives in `_unhandled_input`, which never fires while the cursor sits over a Control with the
  default `MOUSE_FILTER_STOP` (every `Button`) — Godot's GUI input layer consumes the motion event
  first. `QueuePanel`'s tree (`mouse_exited`) and `ApMpPipRow`'s AP/MP containers
  (`mouse_entered`/`mouse_exited`) already needed and got this exact fix for the same reason; the three
  `turn_controls_column` buttons never did. **Fix:** each button's own `mouse_entered` now calls
  `SquadControlOverlay._hide_stale_tooltip()`. Proven both ways in `test_battle_scene_input.gd`: a real
  click reaches End Turn regardless (confirms mouse_filter was never the problem), and a real
  `mouse_entered` on End Turn now hides a tooltip that was previously left stuck open.

### BR32.06 — Resolved — owner: `SUPERVISOR`
**Performance drop when orbiting the camera *and* a unit is selected**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). Framerate took a hit specifically when **both** were true:
  camera orbiting **and** a unit selected. Either alone was fine.
- **Resolved (supervisor-confirmed, 2026-07-22):** on re-check the hit is gone — it was incidentally
  knocked out during the BR32.02 cutout/shader troubleshooting (the depth-source rewrite changed the
  per-frame cutout work). Filed for the record; already fixed by the time it was written up. If aiming
  FPS regresses again, it belongs with the standing BR26.02 (low fps while aiming), same path.

### BR27.08 — Resolved — owner: `SUPERVISOR`
**"Resolve to here" has never worked**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 — RESOLVED, supervisor-confirmed [HBPaR2].** Worked through directly by the supervisor
  and confirmed working.
- **Reported:** 2026-07-20 (logged now; long-standing — backburnered since the button's introduction).
  The "Resolve to here" turn-control (resolve queued actions up to a chosen point) has never
  functioned. Logged here now that the ledger exists so it stops being an untracked known-broken.
- **Status:** open, not yet investigated.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** traces clean
  end-to-end now — button (`squad_control_overlay.gd:445-449`) → `QueuePanel._on_resolve_pressed`
  (`queue_panel.gd:104-107`) → `tactics.resolve_to_marker(_marker_index)`
  (`tactics_controller.gd:1006-1041`), which does slice the queue to a checkpoint index and resolve
  through it. Git history shows commit `888a25f` ("Resolve to Here now actually enables") already
  fixed the historical "button never enables" defect, with passing coverage in `test_queue_panel.gd`.
  **This ledger entry looks stale, not live — worth a quick supervisor re-check before spending
  further investigation on it.**
- **2026-07-22 (tb32 Pass D):** re-verified rather than blind-fixed — `resolve_to_marker()` still
  traces clean end-to-end, and `test_tactics_controller_resolve_to.gd::
  test_resolve_to_marker_applies_only_the_prefix_through_the_marker` is a real queue-then-resolve
  test (queues two move legs, resolves to the first marker, asserts the unit's own `.cell` actually
  only advanced one leg) — not a UI-state check that could pass while the real resolve silently
  no-ops. Nothing changed; this looks like it was already fixed by `888a25f` and the ledger simply
  never caught up. Marked pending, not `RESOLVED` outright, per the provenance gate (SUPERVISOR-sourced) —
  needs the supervisor to actually click the button and confirm.
- **2026-07-22 (supervisor correction): still active — the prior "already fixed" call was wrong.**
  `resolve_to_marker()` working correctly when called directly proves the RESOLUTION logic is fine,
  but says nothing about whether a real player can ever get a `_marker_index` set in the first place
  through the actual `QueuePanel` UI — that path was never exercised, in this session or (per
  `test_queue_panel.gd`) apparently ever with a real queue-then-resolve assertion. Re-opening for a
  real investigation of the click-to-select-a-row → `_marker_index` → resolve-button-enabled chain,
  not just the logic `resolve_to_marker()` itself already had coverage for.
- **2026-07-22, later: reproduced live by the supervisor** — "grayed out and unclickable," matching
  the original report exactly.
- **2026-07-22, follow-up investigation — a real, confirmed test-coverage gap found and closed, but
  the reported symptom itself still not reproduced:** every existing test in `test_queue_panel.gd`
  drove the marker via a helper explicitly documented as "the same path a real click does... without
  needing a live viewport" — `tree.get_root().get_child(index).select(...)` followed by manually
  calling `panel._on_item_selected()` directly. That is NOT the same path: it bypasses the `Tree`
  widget's own hit-testing and its `item_selected` signal entirely. **Nothing, ever, had verified that
  a real click on a real row in the real running game actually fires that signal at all** — exactly
  the class of gap that let BR27.06/BR30.02 hide before (a test that re-derives the behavior instead
  of reading the real thing back).
  - First built the naive version of this test against `test_queue_panel.gd`'s own bare fixture
    (`Tree.new()` with no size, added directly with no parent container) — it FAILED. Looked like a
    smoking gun, but turned out to be a fixture artifact, not the real bug: a bare `Tree` with no
    `custom_minimum_size` lays out at a tiny size, and `get_item_area_rect()` reported a row extending
    below the Tree's own visible rect — a click there falls outside `Control.has_point()`'s test and
    never reaches the Tree at all, regardless of any real production bug. Confirmed via a throwaway
    diagnostic (not committed): giving the same bare Tree the real production `custom_minimum_size =
    Vector2(320, 100)` (`squad_control_overlay.gd:397`) made the identical click resolve correctly.
  - Rebuilt the test against the FULL real `BattleScene`/`SquadControlOverlay` construction instead —
    real Tree sizing, real container hierarchy, a real `InputEventMouseButton` pushed through the real
    `Viewport` at the row's own real, laid-out screen rect (`test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_row_enables_resolve_to_here`). **This passes** — a real click on the
    first row of a freshly-queued single move correctly fires `item_selected` and enables the button.
    Also tried clicking the SECOND row of a 2-entry queue (a throwaway diagnostic, not committed,
    since "resolve to here" is presumably most useful mid-queue, not on the first entry) — also
    correctly selects/enables.
  - **So the click-to-enable mechanism itself checks out in every configuration tried so far, and the
    resolve-when-clicked logic already checked out in tb32 Pass D. Both halves work; the reported
    symptom still hasn't been reproduced by CC.** New regression coverage added either way (a real
    gap closes regardless of whether it's THIS bug): `test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_row_enables_resolve_to_here` (real click, full production wiring) and
    `test_queue_panel.gd::test_a_real_click_on_a_queue_row_enables_resolve_to_here` (same real-click
    proof against the bare fixture, given its own proper size this time — documents the fixture
    sizing gotcha inline so it isn't rediscovered blind next time).
  - **Not chased further blind — needs a few specific details to build a matching failing fixture:**
    (a) which overlay — ordinary `SquadControlOverlay`, or `SingleUnitOverlay`? (b) how many actions
    were queued, and which row (first / a later one) was clicked? (c) fresh turn, or after cycling
    through End Turn/Reset Turn at least once first? (d) does the ROW itself visibly highlight/select
    when clicked (proving the click reaches the Tree) while the button alone stays gray — or does
    NOTHING happen at all, row included? That last one matters most: if the row selects but the button
    doesn't, the bug is almost certainly cosmetic/redraw-timing in `_update_resolve_button()`'s effect
    on the real `Button` node — something no headless test can see (the FRAGCOORD/BR32.02 class of
    bug). If the row itself never highlights, the click isn't reaching the Tree at all in the live
    game, which every test above says shouldn't be possible — meaning something about the live render/
    input path differs from headless in a way not yet identified.
- **2026-07-22, supervisor's answers — every remaining code-level hypothesis ruled out:** (1) both
  `SquadControlOverlay` and `SingleUnitOverlay` show the identical symptom. (2) 1, 2, or 3 actions
  queued, moves interspersed with other action types or not — no difference. (3) fresh turn AND after
  cycling End Turn/Reset Turn — both. (4) **"I don't see any color, or opacity change" — nothing
  happens at all, including the row.** ("Grayed out" was also corrected to "alpha'd out" — the
  button's own look, not necessarily relevant to the row question, but the row-highlight answer is the
  load-bearing one.) This rules out queue length, action type, overlay variant, and turn-state as
  variables, and confirms it's the FIRST half (click never reaches Tree selection) rather than the
  second (selection works, only the button's own redraw is stuck) — narrowing but not yet solving it.
  - Tried two more hypotheses this round, both also ruled out by direct test:
    1. **A real mouse hover immediately before the click** (what an actual player does — move onto the
       row, which triggers `_on_tree_gui_input`'s own tooltip-on-hover, THEN click) rather than a cold
       click with no preceding motion event. Building this properly surfaced a real headless-testing
       limitation, not a game bug: `Viewport.get_mouse_position()` — which `_on_tree_gui_input` itself
       reads to position the tooltip (`tooltip_view.show_data(data, tree.get_viewport().
       get_mouse_position())`) — does **not** update from a synthetic `push_input()`-delivered
       `InputEventMouseMotion` the way a real OS cursor would; it read back `(0, 0)` regardless of the
       motion event's own `.position`. Worked around it by calling `tooltip_view.show_data()` directly
       with the row's real screen position instead, forcing the tooltip genuinely visible at (as close
       as achievable to) the real click point, THEN performing the real click. Still enables the
       button correctly — the (already `MOUSE_FILTER_IGNORE`) tooltip doesn't block the click, matching
       BR31.01's own finding for the turn-control buttons.
    2. Confirmed `HulkTheme` has **no override at all** for a `Tree` row's selection style
       (`selected`/`selected_focus`), nor for `Button`'s `disabled` state — both rely entirely on
       Godot's own default theme. Not a confirmed cause (the default selection highlight is normally a
       distinctly-colored fill, not something that should blend into this theme), but flagged as a
       secondary, unverified possibility: if the default highlight ever reads as visually identical to
       unselected in this specific dark theme, that alone could produce "I see no color change" even if
       the click IS registering underneath. Can't be ruled in or out without eyes on the real render.
  - **Genuinely exhausted what headless GUT can check here.** Every code-level variable tried
    (queue/overlay/turn-state/tooltip-overlap/theme-override-absence) either doesn't reproduce it or
    can't be tested without a real window. This now reads like the same class of bug as BR32.02's own
    shader saga — something only visible in a real, rendered, real-input build.
- **2026-07-22, decision: remove and rebuild rather than keep chasing an unreproducible root cause.**
  The `Tree`+marker+global-button mechanism was never conclusively root-caused despite an extensive
  investigation across several taskblocks, and the supervisor's own repeated live reproduction ruled
  out every code-level variable this session could construct — the strongest remaining signal was
  simply that nothing else in this codebase drives something this important through a `Tree`'s own
  click/selection signal, and every plain `Button`-based control in the same general screen region
  (End Turn, Reset Turn, action bar boxes) has never shown this class of problem. Rather than keep
  guessing at a live-only cause with no further lead, removed the whole `Tree`/marker mechanism and
  rebuilt the same capability on primitives with no such history: each queued action is now its own
  row with its own real "Resolve" button (`QueuePanel._entry_row()`), wired directly to
  `tactics.resolve_to_marker(index)` — no marker state, no `Tree`, no separate global button. Follows
  the same "clear every child, rebuild fresh from an array" convention
  `GenerateBoutOverlay._rebuild_team()`/`_entry_row()` already established, rather than inventing a new
  shape. Full design/rationale in `docs/SUPERSEDED.md`.
  - Verified with a real synthetic click (matching this session's own established rigor) against the
    FULL real `BattleScene`/`SquadControlOverlay` construction — `test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_rows_resolve_button_resolves_through_it` — and against a bare
    `QueuePanel` fixture — `test_queue_panel.gd`'s own suite, five tests covering empty-queue/N-rows/
    real-click-resolves-the-right-prefix/refresh-rebuilds-with-fresh-indices.
  - **Caught a real, separate layout bug while building this**, exactly the kind of thing only a real
    click test surfaces: the row's own expanding "what" label had no width bound inside its
    `ScrollContainer` (nothing forced a maximum, since `SIZE_EXPAND_FILL` is only well-defined once
    something bounds the available width), so the whole row — button included — landed hundreds of
    pixels past the right edge of a 1920-wide viewport. Fixed by disabling the `ScrollContainer`'s own
    horizontal scrolling, which makes it clamp its child to its own real width instead.
  - **A second, unrelated gotcha found and fixed in the test fixture itself, not the game:** the
    default headless GUT test viewport is tiny (64×64) — a row built wide enough to hold real text
    lands well outside that by construction, and a real click there is legitimately outside the
    viewport's own bounds, not a bug. Fixed by resizing the test viewport to `1920×1080`, matching the
    existing convention `test_tooltip_view.gd` already established for the identical reason.
  - **Not fixed in place — this is a replacement, not a patch**, precisely because the original bug's
    root cause was never conclusively identified. Marked `RESOLVED-PENDING-CONFIRMATION`, not plain
    `RESOLVED`, per the provenance gate — this still needs the supervisor's own live click to actually
    close it, since headless tests said the OLD mechanism should have worked too.
- **2026-07-22, supervisor review of the rebuild — two refinements, same session:**
  1. **"Resolving to an earlier point should keep the later queued items in the queue."** The prior
     behavior (inherited unchanged from the original `Tree`-based mechanism, itself dating to
     taskblock06/07) discarded EVERYTHING queued past the marker, not just the resolved prefix —
     `resolve_to_marker()`'s own `selection.reset_turn()` call erased the whole remaining queue.
     Replaced with new `SelectionController.keep_queue_suffix(from_index)`, which drops only the
     resolved prefix; the surviving suffix replays unmodified against the just-updated real state —
     safe since every `CombatAction` already re-validates itself against whatever `state` it's handed
     at apply time, never a captured reference (docs/09). A real design reversal, not a bug fix —
     logged in `docs/SUPERSEDED.md`.
  2. **"The coord info can be an on hover event for the MoveAction term... long paths make the readout
     stretch across the display."** New `CombatAction.short_describe()` (defaults to `describe()`
     unchanged for every action type) — `MoveAction` overrides it to drop only the unbounded `path=...`
     term (`"MoveAction(unit=%d)"`, matching every sibling action's own `ClassName(unit=%d, ...)` style
     — supervisor's own follow-up: "I'm okay with it saying MoveAction, it's just a stream of coords
     that look messy," so only the coordinate stream itself was cut, not the class-name format). The
     full `describe()` still surfaces as an extra "Detail" tooltip row whenever it actually differs
     (`TooltipBuilder.for_queue_entry()`) — the coordinate detail is still reachable, just on hover, not
     stretching every row by construction.
- **2026-07-22, supervisor report: "Hovering anywhere in the combat readout gives me the details of
  things behind it."** A real, confirmed bug in the rebuild, same class as the already-fixed action-bar
  case (`test_a_click_on_an_action_bar_box_never_reaches_the_board_underneath`) — a queue row's own
  `MOUSE_FILTER_PASS` correctly fired its own `mouse_entered`/`mouse_exited` (its own tooltip was never
  the problem), but PASS never marks a motion event handled, so it ALSO reached `TacticsController.
  _unhandled_input`'s `update_hover()` — a pure 3D ray-cast against the board at that screen position
  with no awareness of what UI is drawn there — showing whatever unit/tile sat behind the deliberately
  translucent readout panel instead of just the row's own tooltip. Confirmed live via a direct
  `mouse_moved` signal check (fires with PASS, silent with STOP) before touching anything. Fixed the
  same way the action bar was: `QueuePanel._entry_row()`'s own row is now `MOUSE_FILTER_STOP`, not
  PASS — still gets its own `mouse_entered`/`mouse_exited` (confirmed), never lets the same motion reach
  the board. `test_battle_scene_input.gd`'s own structural test (every non-interactive Control must not
  default to STOP) widened to also recognize a real `mouse_entered` connection as genuine interactivity,
  the same way it already recognized a real `gui_input` connection — a Control deliberately wired for
  hover is exactly as intentional as one wired for clicks. **Not fixed here, flagged as a related, not-
  yet-reported instance of the identical bug:** `ApMpPipRow`'s own AP/MP pip containers use the same
  `PASS` + `mouse_entered`/`mouse_exited` shape with no `gui_input` — likely has the same latent leak,
  just not yet reported, possibly because that row rarely sits over visible board content in practice.
### BR30.07 / BR30.08 — Resolved — owner: `CC`
**Pass D audit: `selected_unit` staleness, same class as BR27.05/BR27.06**
- **Source:** `CC`
- **Found:** 2026-07-21, taskblock-30 Pass D (a supervisor-authored audit task): "BR27.05 and BR27.06
  were the same bug in two places: view code read `selection.selected_unit` (raw, turn-start state)
  during the TACTICS phase, where — per docs/09's 'queuing mutates nothing' — `.cell`/`.ap` don't
  reflect queued-but-unresolved actions. ... Two instances days apart means this is a pattern, not two
  isolated bugs. Audit the rest." Every suspect read from the addendum's own list was checked (state vs
  identity), and none blind-fixed — each confirmed with a failing-then-passing test first.
- **BR30.07 — `TacticsController._confirm_step_out()` computed the outbound path from the stale
  cell:** `Pathfinder.astar(shooter.cell, firing_cell)` used `selection.selected_unit.cell` directly.
  `MoveAction.is_legal()` requires `path[0] == actual.cell` against wherever the unit's real
  (previewed) position is by validation time — so a move queued before triggering step-out silently
  failed `enqueue()` and fell through to `cancel_step_out()`, with no visible step-out at all. Every
  existing test armed+clicked from the shooter's own turn-start cell — the exact gap that also hid
  BR27.06 itself, in a spot BR27.06's own fix never reached (a different function). **State read,
  confirmed.** Fix: path from the queue's own preview instead, matching
  `_append_step_out_return_leg()`'s already-correct sibling pattern. Verified failing without the fix
  (silent cancel; queue only ever got 1 of the expected 2 entries) and passing with it.
  **RESOLVED** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit `8457ff0`, 1864/1864 green.
- **BR30.08 — `TooltipController.refresh()` showed LOS from the stale cell:** passed the raw
  `selected_unit` into `TileInspection.inspect()`, whose `visible_from_selected` field runs a real LOS
  check from `selected.cell` directly. A move queued toward a cell with different sightlines left the
  tooltip stuck showing visibility from the turn-start position. **State read, confirmed.** Fix:
  `previewed_unit()` instead. Verified failing without the fix and passing with it (an opaque cell
  blocks LOS from the start cell but not the queued destination). **RESOLVED**
  [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit `8457ff0`, 1864/1864 green.
- **Checked, not a bug:** `TacticsController.step_out_exposure()`/`_refresh_overlay()`'s
  `Overwatch.would_trigger_at()`/`all_threatened_cells()` calls also read `selected_unit` directly, but
  tracing `would_trigger_at()`'s own general-case branch shows it always re-resolves the mover by `id`
  and explicitly relocates the CLONE to the candidate cell before checking arc/range/LOS, regardless of
  what the passed reference's own `.cell` says — the stale reference only changes which internal branch
  runs, never the final answer. A direct empirical probe (temporary diagnostic, not committed) confirmed
  no output difference. No entry filed.
- **Confirmed correct as-is, no change needed:** `MoveHooks.new(selected_unit.cell)` (both call sites)
  — these run during REAL `resolve_until()`, where `selected_unit.cell` genuinely IS the live starting
  cell, not a preview concern; `confirm_shot()`'s own `shooter` reference and `_append_step_out_
  return_leg()` (both already use raw `selected_unit` ONLY for `.id`/identity, deferring all real
  geometry to previewed state — the correct split); `ap_mp_pip_row.gd` (already reads `previewed_unit()`
  — pre-existing correct pattern); `weapon_panel.gd` (purely structural shell/part reads — hp, wounds,
  manipulators — no position or queue dependency).
### BR30.11 — Resolved — owner: `SUPERVISOR`
**Burst: shown as affordable without enough AP; step-out silently drops the shot**
- **Source:** `SUPERVISOR`
- **2026-07-23 (supervisor confirmation — Resolved, both halves).** Confirmed fixed. *Process note
  from the supervisor: bundling two separately-observed symptoms into a single entry because they
  shared a root is "not really how a bug should be constructed" — the shared root belongs in the
  investigation notes, not in the entry's identity. File one entry per observed symptom in future,
  and cross-link.*
- **Reported:** 2026-07-21, two symptoms the supervisor flagged separately, turned out to be one root
  cause: (1) "actions selectable when not enough AP available still," and (2) "step out seems to be
  working with shoot, but not with burst."
- **Root cause:** `ActionBar._can_afford()` (`src/view/action_bar.gd`) compared the unit's AP against
  the providing weapon's plain `provider.ap_cost` for EVERY action id, but `BurstAction` has always
  charged its own, usually-higher `weapon.weapon_def.burst_ap_cost` when authored
  (`BurstAction._ap_cost`, e.g. `data/parts/chaingun.tres`: `ap_cost = 2`, `weapon_def.burst_ap_cost =
  4`). A unit with enough AP for the plain cost but not the real burst cost saw (and could arm) BURST
  as affordable — only to have the actual shot silently rejected at `enqueue()` time
  (`BurstAction.is_legal()` correctly checks the real cost), with no visible error either way.
- **Step-out's own part in this:** proved, not assumed — `_enter_aim_or_step_out_mode`'s entry into
  step-out mode is genuinely action-id-agnostic (a direct test arming `&"burst"` against the same
  covered-corridor fixture `test_tactics_controller_step_out.gd` already used for `&"shoot"` entered
  step-out mode correctly, no fix needed there). What actually "doesn't work" with burst: a shooter
  steps out for free (the outbound leg never costs AP), then the SAME `confirm_shot()` -> `enqueue()`
  gate silently drops the real attack for the reason above — the unit holds the stepped-out position
  with nothing ever firing, reading as "step out doesn't work" when the move itself queued fine.
- **Fix:** `ActionCatalog.ap_cost_for(action_id, provider)` (new) — the one seam: `&"burst"` returns
  `weapon_def.burst_ap_cost` when authored, else falls back to `provider.ap_cost`, same as every other
  action. `ActionBar._can_afford()` and `BurstAction._ap_cost()` (now a one-line delegate) both read
  this instead of duplicating the branch — the "two parallel systems" trap this project's own
  convention warns against.
- **Verified:** `test_action_bar.gd::test_burst_dims_using_its_own_higher_ap_cost_not_the_weapons_
  plain_one` (fails without the fix, passes with it — confirmed via `git stash`) and
  `test_tactics_controller_step_out.gd::test_firing_burst_after_step_out_is_silently_rejected_with_
  insufficient_real_ap` (documents the exact silent-rejection mechanism: queue stays at 1 action, the
  free out-leg, burst never gets added). 1868/1869 green (the one failure is the unrelated,
  already-flagged `test_full_mission.gd`, BR30.10 above).
- **RESOLVED-PENDING-CONFIRMATION** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit pending.

---
### BR31.02 — Resolved — owner: `SUPERVISOR`
**Wall/void generation cascaded through solid rock**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor confirmation — Resolved).** Confirmed fixed. *Process note: the write-up
  was "a very complicated description for a simple bug." Investigation depth is welcome in the notes;
  the description line should stay plain enough to recognise the bug from.*
- **Backfilled 2026-07-22** (retroactive ledger pass, CLAUDE.md rule 8 applied historically) —
  reported and fixed live during taskblock-31 itself; `docs/CHANGELOG.md` recorded the fix
  (`MapGen._finalize_walls_and_void()`'s own classify-then-mutate two-pass split) at the time, but it
  never got a `BR` id or an entry in this ledger. Filed now so a resolved bug's closure marker exists
  here too, per this file's own stated job.
- **Reported:** 2026-07-21, live play testing of tb31 Pass C's new wall/void model: "walls are
  generating where voids should [be]... there should be a single layer of walls."
- **Root cause:** `MapGen._finalize_walls_and_void()` classified AND mutated each `WALL` cell in the
  same scan pass — converting an exposed cell to `OPEN` made it read as a non-WALL neighbor for
  whatever `WALL` cell got scanned next, so exposure cascaded outward from every real opening through
  however much solid rock the scan order happened to reach. A real ASCII dump (seed 2, 40×30 —
  `BattleScene`'s own defaults) confirmed it: walls many tiles thick, effectively zero `VOID` anywhere
  on the map.
- **Fix:** split into two passes — classify every `WALL` cell's exposure against the grid's own
  untouched layout first, then apply every mutation in a second pass. Re-dumped the same seed: clean
  single-tile wall rings with real void space.
- **Verified:** re-confirmed via the same real ASCII dump technique, not just re-reading the code.
  Commit `9909d73`.
### BR31.03 — Obsolete — owner: `SUPERVISOR`
**Wall fading never visibly occluded anything**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 — closed OBSOLETE, not Resolved [HBPaR2].** This entry can no longer be confirmed,
  because the code it describes no longer exists: its fix was `BoardView._set_wall_alpha()` /
  `WALL_FADE_ALPHA`, the per-object alpha-blend fade, and **tb32 Pass A retired that mechanism
  entirely** in favour of the dither cutout shader (`docs/SUPERSEDED.md`; both symbols now survive
  only in comments describing what replaced them). Marking it `Resolved` would assert a verification
  that never happened. The question it asked — "does wall occlusion actually reveal anything?" — is
  now BR32.02's, with the live faults tracked by BR32.01/BR32.03.
- **Backfilled 2026-07-22** (retroactive ledger pass) — same gap as BR31.02 above: reported and fixed
  live during taskblock-31, never given a `BR` id or an entry here until now.
- **Reported:** 2026-07-21, live play testing tb31 Pass C's wall-fade legibility feature: "I can't see
  wall fading doing anything" — then again, after a first fix attempt, "the wall fading is still not
  occurring, is it drawing between the camera and the orbited point, or is it something else?"
- **First root cause, fixed:** the occlusion check was world-space — "is this wall within 1 unit of the
  straight 3D line from camera to the focal unit." The tactical camera sits well above/back from the
  board, so that line spends almost its whole length far above wall height; the check essentially
  never fired for any wall more than a cell or two from the unit, the exact case that matters. Rewrote
  `WallLegibility.occludes()` → `occludes_on_screen()`: project both the wall and the focal unit
  through the real camera (`Camera3D.unproject_position()`), compare 2D screen distance, require the
  wall nearer in depth — the question a player would actually answer by eye, independent of camera
  angle. Commit `662e8d2`.
- **Second root cause, found when the supervisor reported it still wasn't working:** traced the whole
  pipeline end to end through the real production path (real `BattleScene`/`SquadControlOverlay`, real
  click-to-select, real `CameraRig` framing) and confirmed every intermediate value was already correct
  — `focal_unit` wiring, camera ownership, `unproject_position()`/depth math all checked out. The one
  link never directly verified: whether `GeometryInstance3D.transparency` alone renders a visible
  effect against an otherwise-opaque, `SHADING_MODE_PER_PIXEL` (lit) material — it doesn't. Switched to
  real alpha blending (`BaseMaterial3D.TRANSPARENCY_ALPHA` + `albedo_color.a`), the same mechanism
  `show_unit_ghost()` already proves renders correctly in this project, just kept lit (docs/10: real
  geometry stays lit). New `BoardView._set_wall_alpha()`, `WALL_FADE_ALPHA := 0.25`. Commit `dda90d4`.
- **Verified:** confirmed working in player view after the second fix. Moot in practice either way —
  this whole alpha-blend mechanism is itself superseded by tb32 A's per-fragment discard shader
  (`docs/SUPERSEDED.md`).
### BR32.02 — Resolved — owner: `SUPERVISOR`
**Wall cutout never visibly appears near real units**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor confirmation — Resolved as written, but read the next line).** The cutout
  does now appear near real units; the bug as described is genuinely fixed. **However the underlying
  cause is not gone — it continues as BR32.03.** What was fixed here was the depth-source half; the
  feed-timing half (when `update_wall_cutout()` reads, and from what) is the same root and is still
  live. Closing this entry is not evidence the cutout system is healthy — BR32.01 and BR32.03 are.
- **Reported:** 2026-07-22 (same live-bout review as BR32.01). "I rotated the camera around the
  units, they were still in their original spawn locations, next to walls. No culling observed at
  all."
- **First theory, tried and EMPIRICALLY DISPROVEN:** hypothesized (from Godot's own documentation —
  "FRAGCOORD... use[s] the same coordinate system" as `gl_FragCoord`, bottom-left origin) that
  `FRAGCOORD` and `Camera3D.unproject_position()` (top-left origin) disagreed on Y and needed a flip.
  Added the flip; the supervisor tested live and reported the cutout became visible but **detached
  from any unit, drifting/spiraling independently as the camera orbited** — worse, not fixed. A real
  orbiting-camera test proved the GDScript-side feed (position/depth/radius) tracks the unit
  correctly and stably at every angle, ruling that layer out. Two live, hardcoded-position diagnostic
  builds (a fixed hole at viewport center, then at a corner) settled it empirically: **`FRAGCOORD` is
  actually top-left-origin, Y-down — the SAME convention `unproject_position()` already uses.** No
  flip was ever needed; documentation for a different rendering context/shader type doesn't
  necessarily transfer, and this class of bug is entirely invisible to headless testing (dummy
  rendering never executes a fragment shader) — only live, real rendering could have caught it, and
  did, twice. **The flip has been reverted** (`update_wall_cutout()` feeds `unproject_position()`'s
  own output unchanged).
- **Second theory, tried and confirmed via a sequence of live diagnostic builds (all uncommitted,
  shader-file-only, removed once each landed):**
  1. Unconditional discard whenever `unit_count > 0` (ignoring all per-fragment math) made ALL walls
     vanish, not just ones near units — expected, since every wall shares ONE material/uniform set;
     confirmed the uniform data genuinely reaches the shader (not a wiring bug).
  2. Disabling the depth-compare entirely produced a correctly-positioned, correctly-sized porthole
     at every unit — confirmed the distance/radius/dither math is correct, and narrowed the bug to
     depth-compare specifically.
  3. Flipping the depth-compare direction (`<=` instead of `>=`) was wrong in BOTH directions — ruled
     out a simple sign flip; the depth VALUE itself (`frag_depth = length(VERTEX)`) had to be wrong,
     not just its comparison.
  4. `VERTEX` is documented to already arrive in view space by the time `fragment()` reads it — that
     documentation already failed once this investigation (`FRAGCOORD`'s own origin), and evidently
     doesn't hold here either. Replaced with true view-space depth reconstructed directly from the
     hardware depth buffer (`FRAGCOORD.z` + `INV_PROJECTION_MATRIX`, Godot's own standard recipe) —
     confirmed live: culling from the correct side (wall genuinely between camera and unit) now works
     as expected.
- **Fix:** `wall_cutout.gdshader`'s `fragment()` now computes `frag_depth` via the depth-buffer
  reconstruction above instead of `length(VERTEX)`. No GDScript changes needed — this was entirely a
  shader-side depth source bug.
- **Deferred, not a regression from this fix — logged, not chased further per instruction:** with the
  camera and unit on the SAME side of a wall (nothing should occlude at all), the cutout still fires
  and over-cuts neighboring wall segments, confirmed live via screenshot — not a new bug introduced by
  this fix, inherent to the shader's own coarse occlusion heuristic. Tracked as its own entry,
  **BR32.05**, in `docs/BUGS.md`.
- **Both halves of this investigation (BR32.02's flip revert and this fix) were only possible because
  the supervisor tested live and reported back precisely** — no headless test can exercise a fragment
  shader at all (dummy/headless rendering never executes one), so every claim here was confirmed
  against a real, rendered build, not GUT.

## Legacy (predates the `BR<taskblock>.<seq>` ID convention; IDs assigned retroactively)
*(Kept in their own trailing block rather than resorted into the main ascending sequence above —
same relative order this ledger has always kept them in, oldest work first. All `Resolved`.)*

### BR26.03 — Resolved — owner: `SUPERVISOR`
**Muzzle origin inside the shooter's own armor**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the muzzle originates at the shoulder socket's center
  ('the literal shoulder, not *from* the shoulder'), so the ray starts inside the shooter's own
  geometry and can hit its own armor."
- **First attempt (taskblock-26 Pass A2):** `UnitGeometry.muzzle_point` returned the weapon's own box
  CENTER, not its forward emission point. **Reported still present.**
- **Second attempt (taskblock-27):** re-diagnosed — the first fix touched a function no real firing
  action actually consumed for its horizontal origin; every real attack built the shot plane from the
  shooter's own bare cell center instead. All five action files now anchor the shot plane on
  `Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE`, the shouldered muzzle position, computed
  before the plane is built.
- **RESOLVED** 2026-07-20 — supervisor confirms shots now consistently originate from outside the
  unit's own armor. taskblock-27 Pass A1 (fixing the chaingun-backward report, above) also removed a
  remaining anchor mismatch between `origin` and `direction` that had been obscuring a clean read on
  this one.

### BR26.04 — Resolved — owner: `SUPERVISOR`
**Extract-tile marker / facing-indicator z-fight**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26 (bout review), "same class as tb23's floor/indicator z-fighting."
- **First two attempts (taskblock-26 Pass A3, twice):** bumped `FACING_WEDGE_Y` in isolation each
  time. Both **reported still present.**
- **Third attempt (taskblock-27 Pass C2):** stopped bumping one marker in isolation and enumerated
  the whole ground-overlay height ladder instead. Found a real, previously unreported co-planar pair
  no prior test had ever checked: `TEAM_MARKER_Y` (0.01) was IDENTICAL to `EXTRACTION_TILE_HEIGHT`
  (0.010) — every unit standing on its own extraction tile z-fought, independent of the facing wedge
  entirely. Re-spaced all four named overlays as one ordered ladder with real clearance: extraction
  tile (0.010, unchanged) → team marker (0.06) → overwatch arc (0.09) → facing wedge (0.17).
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass C2.

### BR27.10 — Resolved — owner: `SUPERVISOR`
**Spectator combat log word-wraps**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27 D1a: the spectator's own log label wraps lines; the player view's log
  already doesn't.
- **Fix:** `log_label.autowrap_mode = TextServer.AUTOWRAP_OFF`, the same setting the player-view log
  already carried — a direct port, not a new mechanism.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D1a.

### BR27.11 — Resolved — owner: `SUPERVISOR`
**Inspect-on-hover missing in spectator view**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27 D1c (tb17-era note): inspect-on-hover should be on the shared control
  layer so both spectator and player view have it. Spectator view had none at all.
- **Fix:** `SpectatorOverlay._unhandled_input()` now routes `InputEventMouseMotion` to a new
  `_update_hover()`, reusing the same `UnitPicker.hit()` ray-pick the click handler already calls —
  whichever unit the cursor is actually over highlights (no "selected unit" gate; spectator view has
  no selection concept), mirroring `SquadControlOverlay._on_highlight_changed()`'s own
  clear-every-other-view behavior.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D1c.

### BR27.12 — Resolved — owner: `SUPERVISOR`
**Wall tiles inspectable → opens the tile inspector**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27 D5: clicking a wall tile opens the tile inspector.
- **Fix:** `SpectatorOverlay`'s tile-click path now guards on `TerrainType.WALL` before ever calling
  `open_tile()` — a wall click is a real no-op, the same posture a miss off the board already had.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D5. (The garbage-viewport
  symptom this report also showed was a distinct, deeper bug — see the next entry, found and closed
  by CC in the same pass.)

### BR27.13 — Resolved — owner: `CC`
**InspectPanel's null-root branch leaked stale isolate-viewport state ("garbage inspector")**
- **Source:** `CC`
- **Found:** while root-causing the wall-tile report above. `Grid.blockers` returns null identically
  for a wall cell and bare floor, so the tile lookup itself was never the bug. The real defect:
  `InspectPanel.open()`'s null-root branch (reached whenever `unit.shell.root == null`, which
  includes "no unit/object at this tile") never reset the preview viewport's own
  `own_world_3d`/isolate-focus state — so a "nothing to show" case could render an uncontrolled slice
  of the live board, carried over from whatever a PRIOR inspect had left the viewport in.
- **Fix:** the null-root branch now resets `_preview_viewport.own_world_3d = true` and calls
  `show_assembly(null, ...)`, so a "nothing to show" case can never leak the live-board state
  regardless of which caller reaches it.
- **RESOLVED** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — taskblock-27 Pass D5, proven both ways
  (fails without the fix, passes with it) by `test_inspect_panel.gd`'s new
  null-root-resets-viewport-state test. CC-sourced: found, fixed, and tested entirely by CC in one
  pass, no supervisor confirmation gate applies.

### BR51.22 — Resolved — owner: `CC`
**A detonation damages units only, never cover or other blockers**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-01, sixth hunt. *"Only seems to damage units, not cover."*
- **Confirmed in `DamageResolver.detonate`:** it iterates `state.units` and nothing else. Blockers and
  field items are never considered, so a barrel next to a barrel cannot chain, and an explosion beside a
  wall leaves it untouched.
- **Same root as `BR35.08`'s drawing gate**, which was fixed by recording that a part detonated rather
  than reading its casualty list: the blast list only ever contained `Unit`s. This is the mechanical half
  of that same assumption.
- **Chain reactions are the thing to decide before writing it:** a barrel that detonates a neighbouring
  barrel needs a recursion bound, and that is a design call, not an implementation detail.
- **RESOLVED** — commit `bd17685` (*"detonations reach cover, chain in waves, and centre on the
  exploding part"*), with its own `CHANGELOG.md` entry. `Detonation` was split out of `DamageResolver`
  when chaining pushed that file past its line cap; it resolves in **waves**, to the supervisor's
  stated shape — *"chain react simultaneously, then in order, they should never re-explode"* — and
  blockers and field items are in the blast now, not only `state.units`.
- **Archived 2026-08-04 by a review audit [CC `e5393c3a-bd26-4668-8905-c50cf31e04cb`].** The fix
  landed but the entry was **deleted from `BUGS.md` rather than moved here**, so a genuinely closed
  bug left no closure marker anywhere — exactly what this ledger exists to prevent. Text above
  restored verbatim from `a65f66d`; the two notes are new.

### BR51.23 — Resolved — owner: `CC`
**A detonation is centred on the owning unit's cell, not on the exploding part**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-01, sixth hunt, reviewing CC's own choice. *"Centered on the cell, or centered on the
  exploding part? For a barrel, cell center works, but an ammo rack on a unit's back may be higher up or
  offset."*
- **The supervisor is right and CC chose wrong.** `DamageResolver._locate_cell` returns the *unit's* cell
  for any part mounted on one, and the logged height is the cell's floor. So an ammo rack detonates at
  its wearer's feet — the drawn sphere is centred somewhere the exploding object is not.
- **A barrel is the case that hides it**, because a blocker's cell genuinely is its position.
- **The part's real world position already exists** — `UnitGeometry.assembly_placements` composes exactly
  this for rendering and for `PartPicker`, so the fix is to ask it rather than to derive a second answer.
- **RESOLVED** — commit `bd17685`, same commit as `BR51.22`. `Detonation._origin` asks
  `UnitGeometry.assembly_placements` for the exploding part's own composed world position rather than
  deriving a second answer, and `detonation.gd:108` cites this entry by id — so the fix names the bug
  it closes even though the entry had gone.
- **Archived 2026-08-04 by a review audit [CC `e5393c3a-bd26-4668-8905-c50cf31e04cb`]**, for the same
  reason as `BR51.22`: fixed, then deleted from `BUGS.md` instead of moved here. Text above restored
  verbatim from `a65f66d`; the two notes are new.

### BR27.16 — Resolved — owner: `SUPERVISOR`
**Step out: MP charged for the automated legs**
- **Source:** `SUPERVISOR`  ·  **Split from `BR27.01` part (2), 2026-08-04** — see that entry below
  for the original four-way framing and the full taskblock-27 Pass B history.
- **Reported:** taskblock-27, as part of *"Player Step Out: four bugs, one system"* — the automated
  outbound and return legs of a step-out charged MP like an ordinary move.
- **Fix:** `MoveAction.free` (new in taskblock-27 Pass B), applied to both automated legs. This
  reversed `StepOutPlanner`'s own original *"real MP/AP cost for both moves, no discount"* — recorded
  in `docs/SUPERSEDED.md`. **`free` applies to the AI's usage too**, not only the player's: the same
  shared maneuver, the same cost either way.
- **RESOLVED** 2026-07-21 — **confirmed by the supervisor**, in the same session as `BR27.06`'s
  confirmation: no more MP charged for the automated legs. *Status carried verbatim from `BR27.01`;
  the split transcribed it and closed nothing.*
- **CC note, `e5393c3a-bd26-4668-8905-c50cf31e04cb`, 2026-08-04 — the mechanism still exists.**
  `MoveAction.free` is present and consumed at three points (`is_legal`, the per-step cost path, and
  `_can_still_complete`), `StepOutPlanner` still passes it for both legs, and
  `test_step_out_planner.gd::test_the_triple_costs_no_mp_for_either_leg` still guards it. Checked
  because a fix reported done and absent from the code is a live pattern in this ledger (`BR55.03`);
  this one is genuinely there.

### BR27.17 — Resolved — owner: `SUPERVISOR`
**Step out: the ghost snaps back to the base cell instead of holding the step-out waypoint**
- **Source:** `SUPERVISOR`  ·  **Split from `BR27.01` part (3), 2026-08-04** — see that entry below
  for the original four-way framing and the full taskblock-27 Pass B history.
- **Reported:** taskblock-27, as part of *"Player Step Out: four bugs, one system"*.
- **Root cause, and it was a symptom rather than its own bug:** `_confirm_step_out()` used to queue
  the **whole** move+attack+move triple the instant a candidate cell was confirmed. The triple ends
  back at the origin, so it was queued and previewed in the same instant — there was never a
  sustained moment where the ghost held the stepped-out position for the player to see.
- **Fix:** splitting the flow (the same change that fixed part (1)'s original form). Confirming a
  cell now queues **only** the free outbound leg and hands into ordinary aim mode; the return leg is
  appended only when a real shot queues. **The ghost snapping back is now correct rather than a bug**
  — it happens once the return leg is genuinely queued, which is the truthful final resting position.
  During the aim phase it holds the stepped-out cell through the same queued-move preview machinery
  every other action already uses.
- **RESOLVED** 2026-07-21 — **confirmed by the supervisor**, same session as `BR27.16`: the ghost no
  longer snaps back. *Status carried verbatim from `BR27.01`; the split transcribed it and closed
  nothing.*
- **CC note, `e5393c3a-bd26-4668-8905-c50cf31e04cb`, 2026-08-04.** The split flow still stands:
  `_confirm_step_out()` enqueues one `MoveAction(..., true)` and `_append_step_out_return_leg()` is
  reached only from `confirm_shot()` after a firing action actually enqueues. Guarded by
  `test_confirming_a_step_out_cell_queues_only_the_free_outbound_leg_then_opens_aim` and
  `test_firing_after_a_step_out_completes_the_free_move_attack_move_triple`.

### BR27.01 — Obsolete — owner: `SUPERVISOR`
**Player Step Out: four bugs, one system**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27: Step Out works for the AI but the player's own path was broken four
  ways — (1) doesn't open the dartboard, always resolves a center-mass shot; (2) charges MP for the
  automated legs; (3) the ghost snaps back to the base cell instead of holding the step-out
  waypoint; (4) the intended sequence (pick step-out → ghost holds the cell → dartboard opens there
  → fire resolves the whole move/fire/return) wasn't followed.
- **Root cause:** `TacticsController._confirm_step_out()` called `StepOutPlanner.build_triple()`
  wholesale the instant the player confirmed a candidate cell — queuing the WHOLE move+attack+move
  triple (an automated center-mass shot) in one click, never entering ordinary aim mode at all. The
  ghost "snapping back" was a direct symptom of this: the entire triple (ending back at origin)
  was queued and previewed in the same instant the step-out cell was chosen, so there was never a
  sustained moment where the ghost held the stepped-out position for the player to see. `MoveAction`
  had no discount mechanism at all — `StepOutPlanner`'s own doc comment stated "real MP/AP cost for
  both legs, no discount" as a deliberate original design choice.
- **Fix:** split the flow. Confirming a step-out cell now queues ONLY the free outbound leg
  (`MoveAction.free`, new — no MP/AP either direction, docs/SUPERSEDED.md), then hands off into
  ORDINARY aim mode from the stepped-out position (`_framing_shooter()`/`aim_state()` already read
  the previewed unit, so the camera and dartboard follow the queued move for free). Firing
  (confirm_shot() again, now in aim mode) appends the free return leg once a real shot actually
  queues. Canceling aim mid-step-out (before firing) undoes the queued outbound leg. The ghost
  "snapping back" is now correct, not a bug — it only happens once the return leg is genuinely
  queued (after firing), the truthful final resting position; during the aim phase it holds the
  stepped-out cell via the same queued-move preview machinery every other action already uses.
  `free` applies to the AI's own `StepOutPlanner` usage too, not just the player's — the same shared
  maneuver, same cost either way.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — taskblock-27 Pass B,
  proven via `test_tactics_controller_step_out.gd`'s updated/new tests (cell-confirm queues only the
  free out-leg and opens aim; firing completes the free triple; canceling aim undoes the out-leg)
  and `test_step_out_planner.gd::test_the_triple_costs_no_mp_for_either_leg`.
- **2026-07-20:** supervisor could not verify — blocked by a new, separate bug (now logged as
  **BR27.06 — Step Out no longer occurs at all**, a regression from this very restructure). Until
  BR27.06 is fixed, BR27.01 can't be confirmed. **Verification deferred**; still pending, and now
  gated behind BR27.06.
- **2026-07-21:** BR27.06 now has a fix pending its own confirmation (commit `d42f744`). Worth
  re-attempting BR27.01's own verification alongside BR27.06's — same play session either way.
- **2026-07-21 (broken down by the supervisor, same session as BR27.06's confirmation):** parts (2)
  and (3) confirmed **RESOLVED** — no more MP charged for the automated legs, ghost no longer snaps
  back. Part (4) ("the intended sequence wasn't followed") was the supervisor's own original
  rephrasing of (1)-(3) together, not a distinct fourth symptom — folded in, not tracked separately.
  Part (1) has **mutated, not resolved** — reopened with a precise new repro: "clicking shoot, then
  clicking an enemy, doesn't bring up the dartboard if the unit had to step out; clicking again brings
  up the dartboard." Likely the two-step step-out flow itself (first click enters step-out-cell-choice
  mode, a second click/`confirm_shot()` is what actually opens ordinary aim mode per the Pass B fix
  above) reading as "doesn't work" without a clear in-between visual cue — not yet investigated
  code-side. **BR27.01 stays open for this one remaining piece.**
- **2026-07-22 (tb32 review — still reproduces):** unchanged — step-out after shooting still does not
  open the dartboard immediately on the step-out; a second click is required. tb32 didn't touch this.
  The one open piece (part 1) persists exactly as the 2026-07-21 repro describes.
- **2026-08-04 — split into `BR27.15`–`BR27.17`, one per outcome, and closed `Obsolete` here.** One id
  standing for several independent outcomes can never be closed honestly: some fixed and one open is
  neither `Active` nor `Resolved`. The split changes no statuses and fixes nothing — **it makes closure
  possible**, which is the whole argument for it.
- **Two corrections made while performing the split, both recorded rather than silently applied.**
  **The id range was `BR27.10`–`BR27.13`, which is already taken** — those four exist in this archive,
  `Resolved`, from taskblock-27 Pass D, and describe the spectator log wrap, inspect-on-hover, the
  wall-cell inspector and an `InspectPanel` viewport leak. `BR27.14` is used too, so the split took
  `BR27.15` onward. **And it is three entries, not four**: the 2026-07-21 breakdown above records part
  (4) as *"the supervisor's own original rephrasing of (1)-(3) together, not a distinct fourth
  symptom — folded in, not tracked separately"*, so splitting it out would have created an entry for
  something this ledger already says is not a separate thing.
- **Kept as a pointer rather than deleted, deliberately.** They share one system (player step-out)
  and there was a reason at the time for holding them together, which nobody can now reconstruct. If
  splitting turns out to be the mistake, this entry is where the original framing survives — the
  three new entries each point back here.
- **Held in `BUGS.md` only for ease of transport, and moved here on 2026-08-04.** `Obsolete` is a
  closing status, so the open ledger is not where it belongs; the pointer resolves from the archive
  exactly as well.


### BR11.01 — Resolved — owner: `SUPERVISOR`
**Resource Editor — four layout bugs (stale-report source)**
- **Source:** `SUPERVISOR`
- **Reported:** recurring through 2026-07-20 (arrived repeatedly as a `## User Request` to launch
  `run_resource_editor.sh` and screenshot the bugs). Era: taskblock 11 was the active block when
  first reported.
- **Symptoms:** (1) nothing resized/expanded on window resize; (2) no visible column-resize grab
  handles in the Tree header; (3) header bar changed height/width while interacting; (4) 3D preview
  z-fought the ground disc (needed zoom-in + upward offset).
- **RESOLVED** 2026-07-18, ~101 commits before the last stale re-report, in three commits:
  - `713f411` — layout never resized, columns wouldn't drag, preview mis-framed
  - `1bff29b` — garbage edits, silent save loss, header jitter
  - `944d019` — preview: drop the dummy-matrix carrier, add `show_assembly`
- **Verified** both in code and by direct supervisor observation of the corrected tool — so this
  `SUPERVISOR`-sourced bug is legitimately `RESOLVED` (the gate was satisfied: the supervisor
  confirmed it).
- **Why it kept recurring:** the fixes landed as plain bugfix commits *outside* the "Taskblock N Pass
  X" cadence, so the usual "update CHANGELOG on landing" never fired. With no closure marker anywhere,
  and the original tb11 spec's own acceptance criteria still discoverable, a fresh read of the living
  docs found nothing said "done" and re-derived "go verify the Resource Editor" as open. **This ledger
  is the fix for that class** — regardless of whether the originating spec is still on disk at all.

### BR16.01 — Resolved — owner: `CC`
**Cover-scatter could land a blocker on a cell about to become a spawn zone**
- **Source:** `CC`
- **Found:** while making cover movement-blocking (taskblock-16 Pass B) — `_scatter_cover` ran
  before spawn zones were placed, so a blocker could land on a cell that becomes a spawn a moment
  later, or survive `_ensure_spawns_connected`'s forced-corridor fallback and leave that "fix"
  corridor still impassable.
- **Fix:** clear any blocker that `_mark_zone`/`_set_open` touches.
- **RESOLVED** — taskblock-16 Pass B.

### BR16.02 — Resolved — owner: `CC`
**`_ensure_spawns_connected`'s fallback corridor used an unseeded RNG — real non-determinism**
- **Source:** `CC`
- **Found:** while making cover movement-blocking (taskblock-16 Pass B) — the forced-corridor
  fallback spun up its own unseeded `RandomNumberGenerator`, harmless while it almost never
  triggered, but movement-blocking cover trips it far more often, producing two different maps from
  the same seed across two calls.
- **Fix:** reuse the caller's own seeded rng.
- **RESOLVED** — taskblock-16 Pass B.

### BR16.03 — Resolved — owner: `CC`
**Wider corridors could carve straight through and erase a spawn zone's own tag**
- **Source:** `CC`
- **Found:** while widening corridors (taskblock-16 Pass C) — `_ensure_spawns_connected`'s forced-
  corridor fallback carves through the spawn cells themselves (its own `a`/`b` endpoints), and
  `_set_open` stamps every touched cell back to plain OPEN, including the SPAWN_A/SPAWN_B tag it was
  supposed to reconnect a path *to*. A single-cell corridor only clipped a corner rarely; a
  3–5-wide one reliably erased it outright (seed 40 on a 32×24 grid left zero SPAWN_A cells
  anywhere).
- **Fix:** snapshot every SPAWN_A/SPAWN_B cell before the fallback carve, re-stamp after.
- **RESOLVED** — taskblock-16 Pass C.

### BR17.01 — Resolved — owner: `CC`
**Map generation regressed to a single room, no hallways, since taskblock-16**
- **Source:** `CC`
- **Found:** taskblock-17 Pass A — taskblock-16 raised `MIN_ROOM_SIZE` 3→7 (correct), but neither
  real caller's own hardcoded grid size moved to match: `BattleScene.GRID_WIDTH/HEIGHT` was 12×10,
  `BoutSetup`'s was 20×14, both well under `MapGen.MIN_LEAF_SIZE * 2` (24) — the size a rect must
  clear before the BSP splitter will ever divide it. Every real battle and bout had been silently a
  single room since taskblock-16 landed.
- **Fix:** grew both grids (`BattleScene` → 40×30, `BoutSetup` → 32×24); new tests pin each caller's
  grid constants against `MapGen.MIN_LEAF_SIZE * 2` so a future `MIN_ROOM_SIZE` raise fails loudly
  instead of collapsing every map again, plus a seed-swept "the map actually splits" assertion.
- **RESOLVED** — taskblock-17 Pass A, confirmed live (screenshot of `BattleScene`'s default map
  showing four rooms + hallways, vs. one solid block before).

### BR17.02 — Resolved — owner: `CC`
**Bout facing off by up to 180° from target, not a flat 90°**
- **Source:** `CC`
- **Found:** diagnosing a live-play report ("bots face ~90° off their target") (taskblock-17 Pass
  B) — `FaceAction.orientation_toward` computed the target orientation via `Vector2.angle_to()`'s
  standard rotation convention, the exact one `BodyProjector.rotate_by_orientation`'s own doc
  comment says this codebase deliberately departs from since the taskblock-07 B1 fix;
  `orientation_toward` was never updated to match. Diagnosed against the real composed transform:
  error was 0° dead ahead, growing to 90° on the diagonals and a full 180° along the world X axis.
- **Fix:** new `BodyProjector.orientation_for(direction)` — the formal inverse of `forward_for`,
  solved directly from its own algebra (`atan2`, never `angle_to`); `orientation_toward` now
  delegates to it.
- **RESOLVED** — taskblock-17 Pass B.

### BR18.01 — Resolved — owner: `CC`
**A single-step move could trigger overwatch, spend the watch, and still complete the rest of the queue (latent since tb06 Pass F)**
- **Source:** `CC`
- **Found:** writing the step-out interrupt test (taskblock-18 Pass D) — `MoveAction.
  apply_stepwise`'s interrupt check excluded a move's own FINAL step from ever honoring a triggered
  hook's forced freeze. A single-step move — exactly what a step-out's own outbound/return leg
  always is — could trigger overwatch, spend the watch, and still sail on to complete the rest of
  the queue: the exact "ghost bullet" case the re-validating resolver (Pass B) exists to prevent.
  Undetected because every prior Overwatch test happened to trigger on an earlier, non-final step.
- **Fix:** `hook_forces_stop` now escapes the `is_final_step` gate unconditionally, matching the
  function's own pre-existing (and previously contradicted) doc comment.
- **RESOLVED** — taskblock-18 Pass D.

### BR22.01 — Resolved — owner: `SUPERVISOR`
**Waist-line of impacts — the shot-plane Z-discard**
- **Source:** `SUPERVISOR`
- **Reported:** through mid-2026-07 review passes ("a line of impacts across the waist"; "only seeing
  ~20% of shots"; "no ricochets").
- **Symptom:** projection collapsed `Vector3 → Vector2(x, z)`, dropping the height axis — so vertical
  scatter collapsed to a horizontal band and tracers/ricochets pinned to one height.
- **RESOLVED** in **taskblock 23** (true-3D shot resolution): projection retains height, the dartboard
  scatters in 3D, `resolve_ray` accepts vertical shots, tracers draw the real 3D path. Tagged in
  `docs/CHANGELOG.md`.

### BR23.01 — Resolved — owner: `CC`
**Isolate-camera lighting leaked a `WorldEnvironment` node on every `InspectPanel` construction**
- **Source:** `CC`
- **Found:** while wiring the isolate camera's own lighting fix (taskblock-23 Pass E2) —
  `WorldPalette.world_environment().environment` was read just to steal the resource, allocating and
  never freeing a full `WorldEnvironment` **node** per call (confirmed via GUT's own orphan count).
- **Fix:** `WorldPalette.environment()` factored out as a resource-only builder that
  `world_environment()` now delegates to.
- **RESOLVED** — taskblock-23 Pass E2.

### BR24.01 — Resolved — owner: `CC`
**Player could never queue `BurstAction` either — `confirm_shot` hardcoded `AttackAction`**
- **Source:** `CC`
- **Found:** while tracing the AI's own chaingun-fires-single-shot bug (taskblock-24 Pass A) —
  `TacticsController.confirm_shot()`/`_confirm_step_out()` and the shared
  `StepOutPlanner.build_triple` all hardcoded `AttackAction` regardless of `armed_action.id`;
  grepping the whole view layer, `BurstAction` was never constructed anywhere in `src/view/` at all.
  A player arming and clicking Burst silently fired a single shot instead.
- **Fix:** new `ActionCatalog.build_firing_action(action_id, ...)` is the one place an action id
  becomes a real `CombatAction`, used by both the tactics controller and the AI.
- **RESOLVED** — taskblock-24 Pass A (flagged and confirmed via a direct question mid-pass).

### BR24.02 — Resolved — owner: `CC`
**Overwatch structurally unable to trigger for a unit with an ordinary, volumed torso**
- **Source:** `CC`
- **Found:** while wiring the AI's own overwatch consideration (taskblock-24 Pass C) —
  `Overwatch._torso_visible`'s own `ShotPlane.resolve_ray` never excluded the overwatcher's own body,
  so any unit with a real torso was the first thing its own ray hit, before ever reaching a target
  downrange. Every overwatch fixture in the test suite already worked around this by building the
  overwatcher with NO torso volume at all, masking it completely — overwatch had never actually
  worked for a normally-bodied unit.
- **Fix:** new `exclude_parts` parameter on `ShotPlane.resolve_ray` (mirroring
  `resolve_projectile`'s existing one); a regression test proves it against a real, volumed
  overwatcher.
- **RESOLVED** — taskblock-24 Pass C.

### BR24.03 — Resolved — owner: `CC`
**Overwatch never checked during any AI-vs-AI bout — no `mid_move_hook` wired into `BoutRunner.step()`**
- **Source:** `CC`
- **Found:** while un-stranding overwatch for AI use (taskblock-24 Pass C) — `BoutRunner.step()`
  called `state.resolve_until(queue)` with no `mid_move_hook` at all, so `Overwatch.check_trigger`
  never ran during any bout, regardless of whether a unit had validly declared overwatch. The entire
  overwatch-vs-movement tension had been dormant in every bout ever run.
- **Fix:** wired `Overwatch.check_trigger` in, the same Callable `test_reaction_window.gd` already
  threads through by hand (flagged and confirmed mid-pass). Confirmed zero behavior change for every
  pre-existing bout fixture (AGGRESSIVE, the only playstyle any of them use, never declares
  overwatch).
- **RESOLVED** — taskblock-24 Pass C.

### BR00.01 — Resolved — owner: `CC`
**`los.gd` `range`-shadow (v1)**
- **Source:** `CC`
- **Symptom:** a param named `range` shadowed the builtin, failing at load/call time.
- **RESOLVED** in the v1 foundation work (noted historically in `docs/SUPERSEDED.md`). `gdlint` now
  catches this class faster than the engine does (see `docs/TOOLING.md` gotchas).

### BR26.05 — Resolved — owner: `SUPERVISOR`
**Deflect tracers never drawn**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the resolver produces DEFLECT outcomes (a review bout
  logged 25), but resolution_player.gd references DEFLECT zero times — the bounced secondary ray is
  computed, logged, never drawn."
- **Fix:** `taskblock-26 Pass A1` (commit `7c07445`) — every DEFLECT-outcome impact event now
  carries its own `deflect_end_x/y/height`, drawn as a second, visually distinct tracer segment.
- **RESOLVED** — confirmed by the supervisor.

### BR26.06 — Resolved — owner: `SUPERVISOR`
**Bout maker AI dropdown missing new playstyles**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26: tb24/tb25 added playstyles (overwatch-capable set, PSYCHOTIC, TURTLE)
  but the bout setup menu's own AI dropdown was a hardcoded, independently-maintained list.
- **Fix:** `taskblock-26 Pass C1` (commit `67c7ca8`) — `GenerateBoutOverlay.PLAYSTYLES` is now a
  direct reference to `UnitAI.PLAYSTYLES`, not a hardcoded copy.
- **RESOLVED** — confirmed by the supervisor.

### BR26.07 — Resolved — owner: `SUPERVISOR`
**Bout menu jumpy add/duplicate, not truly centered**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26: adding/duplicating a roster entry reflows jarringly; the menu reads as
  intended-centered but isn't.
- **Fix:** `taskblock-26 Pass C2` (commit `67c7ca8`) — anchors pinned to 0.5 with
  `GROW_DIRECTION_BOTH` (no baked offset); every row reserves the same `ROW_MIN_HEIGHT`.
- **RESOLVED** — confirmed by the supervisor.

### BR26.08 — Resolved — owner: `SUPERVISOR`
**Inspect header shows only the variant, not unit id/squad**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26: the inspect panel showed the bot's variant but not which unit/squad
  this actually was in the current bout — two units built from the same variant read identically.
- **Fix:** `taskblock-26 Pass C3` (commit `67c7ca8`) — the title bar now reads "INSPECT — Unit N
  (Squad M) — <variant>" once a unit is open.
- **RESOLVED** — confirmed by the supervisor.

### BR27.14 — Resolved — owner: `CC`
**Stab's slide-deflect could land back on the shooter's own body**
- **Source:** `CC`
- **Found:** while re-diagnosing A2 above (see that entry) — `DamageResolver._resolve_slide` (stab's
  own DEFLECT_MODE_SLIDE response) re-searches the WHOLE plane from index 0 with a lateral nudge, but
  hardcoded an EMPTY exclude list on that re-search, unlike every other plane lookup in `resolve_shot`.
  A stab that deflects and slides at point-blank range could therefore land back on the shooter's own
  body (which sits at the ray's own near-zero depth), the one lookup `resolve_shot`'s own first-hop
  exclusion never covered.
- **Fix:** `_resolve_slide` now takes `exclude_parts` and passes it through to its own `_find_next`
  call, the same shooter-parts list `resolve_shot` itself was given.
- **RESOLVED** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — proven both ways (fails without the fix,
  passes with it) by
  `test_damage_resolver_deflect_modes.gd::test_slide_deflect_never_lands_back_on_the_shooters_own_excluded_body`.

---

### BR32.01 — Resolved — owner: `SUPERVISOR`
**Stray wall-cutout hole at a cell with no unit**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor re-check — REOPENED, and merged in understanding with BR32.03).** Still
  reproduces. The description here is almost certainly the *same phenomenon* BR32.03 describes from
  the other side: a "stray cutout at a cell with no unit" is what a cutout that **carried over from a
  previous bout** looks like once the unit that justified it is gone. Treat BR32.01 and BR32.03 as one
  defect with two observed faces — fix the feed-refresh boundary (bout load, unit spawn, unit removal)
  once and both should fall. Do not fix them as separate bugs.
- **Reported:** 2026-07-22 (live bout, tb32 review). "A stray culling around cell 2,18, with no unit
  to produce that effect... that is the ONLY culling step I see, it's not showing on the units."
- **Root cause, confirmed by reading the code (no live repro available to me — this session has no
  Xvfb/GPU, so I can't run the actual bout myself):** `BoardView.wall_cutout_units` is a live
  reference to `CombatState.units`, fed unfiltered into the wall-cutout shader
  (`BoardView.update_wall_cutout`) every frame. Two ways a unit can leave the board while STAYING in
  that array at its own stale `.cell` forever: (a) **extraction** (`MissionState.extract_unit()` sets
  `alive = false`/`extracted = true` but never clears `.cell`, and nothing in the view layer ever
  read `.extracted` before this fix — the unit's own `HitVolumeView` doesn't even get hidden,
  a separate, more visible latent issue flagged below); (b) the **debug panel's "remove object" verb**
  on a unit (`BoutInjector.remove_object` → `CombatState.kill_unit` — same `alive = false`, cell
  untouched — plus `BattleScene.remove_unit_view()`, which DOES destroy the `HitVolumeView`,
  tracked in `_removed_unit_ids`). Either way, the cutout shader keeps cutting a hole at that unit's
  last position indefinitely, with nothing visibly there to explain it — exactly the reported
  symptom. ("Not showing on the units" is very likely just describing that no *currently on-board*
  unit happens to be behind a wall from the camera's current angle right now — not itself a bug,
  though unconfirmed without seeing the bout.)
- **Fix:** `update_wall_cutout()` now skips any unit with `.extracted == true`. A new
  `BoardView.exclude_unit_from_occlusion(unit_id)` (cleared on every `build()`, so a fresh battle
  never inherits a stale exclusion) is called from `BattleScene.remove_unit_view()` — the same
  `_removed_unit_ids` moment — and checked alongside `.extracted` in the cutout feed. Pass B's own
  `BattleScene._occluding_friendlies()` (same `wall_cutout_units` list, same class of bug for the
  friendly-fade effect) got the matching `.extracted` filter too, since an extracted friendly's own
  `HitVolumeView` stays live (extraction never calls `remove_unit_view`) and would otherwise visibly
  fade as if still standing there.
- **Separate, more visible latent issue flagged, not yet fixed:** nothing in the view layer reads
  `Unit.extracted` at all outside this fix — an extracted unit's own `HitVolumeView` never gets
  hidden or specially posed, so its body may just keep standing there, fully rendered, indefinitely.
  Worth a supervisor look independent of this ticket.
- **Not yet confirmed which of the two mechanisms (a)/(b) actually produced the (2,18) hole** — both
  are now fixed regardless, but knowing which would confirm the diagnosis. Did a unit get extracted
  or debug-removed near that cell?
- **2026-07-22 (supervisor):** if extraction/debug-removal was the cause, it happened on a PRIOR
  bout, not this one — the stray hole was already present on loading into the current bout. See
  **BR32.03** below — a distinct, not-yet-investigated angle (does something carry over across a
  "New Battle" that shouldn't?), since this fix's own `_excluded_from_occlusion` is cleared on every
  `BoardView.build()` and `wall_cutout_units` is reassigned fresh from the new `CombatState.units` on
  load, so neither of the mechanisms fixed here should be ABLE to survive a bout transition as
  currently understood — worth a real look, just not yet.
- **2026-07-23 (tb35 Pass D — the "should be impossible" gap found and fixed)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. The prior note's own "reassigned fresh from the new
  `CombatState.units` on load" premise was checked directly and is **false in the common case**:
  `wall_cutout_units` is set in exactly ONE place in the entire codebase —
  `SquadControlOverlay._on_battle_loaded()`. `SpectatorOverlay` (the DEFAULT overlay every fresh bout
  and every "New Battle" starts in, unless the Generate Bout menu's own "Assume Control" checkbox was
  ticked) has no `battle_loaded` handler at all and never touches it.
  `BattleScene.load_battle()` itself — the one function that runs for every bout, every overlay —
  rebuilds `board_view`'s static geometry (`board_view.build(...)`) but never re-points
  `wall_cutout_units`. So starting or reloading a bout while staying in Spectator mode (the ordinary,
  default path) leaves the feed pointing at whatever it held before: `null`/empty on first launch, or
  the PREVIOUS bout's own now-orphaned `combat_state.units` array on any later one — exactly "a stray
  cutout at a cell with no unit" (this entry) and "carried over from a previous bout" (BR32.03,
  confirmed the same defect). This is also precisely why clicking "Assume Control" (either the bout-
  start checkbox or a mid-bout control-assumption) "snaps the culls into place": either path installs
  a real `SquadControlOverlay` for the first time against the *current* `battle`, which is the ONLY
  code path that ever sets the feed — not a coincidence, the actual mechanism.
  - **Fix:** `board_view.wall_cutout_units = combat_state.units` moved into `BattleScene.
    load_battle()` itself, right after `board_view.build(...)` — set once, canonically, for every
    overlay, every bout. `SquadControlOverlay`'s own now-redundant assignment removed (one source of
    truth, not two agreeing by coincidence).
  - **Verified (headless):** new
    `test_battle_scene.gd::test_load_battle_repoints_the_wall_cutout_feed_even_in_spectator_mode` —
    loads a bout while in `SpectatorOverlay`, confirms the feed points at that bout's own units;
    loads a SECOND bout, confirms the feed re-points to the new state's units and the first bout's
    own (now-stale) array is no longer the feed.
  - Marked Pending, not Resolved — this needs a live look (start a bout, stay in Spectator, confirm no
    stray cutout) before promotion, same as every other `SUPERVISOR`-owned entry this session.
- **RESOLVED** [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — confirmed live by the supervisor (2026-07-23).

### BR32.03 — Resolved — owner: `SUPERVISOR`
**Wall cutout carries over across a bout transition; new units get none**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22. The supervisor noticed BR32.01's own "stray culling, no unit there"
  symptom immediately on loading into the current bout — if extraction/debug-removal was the actual
  cause (BR32.01's own fix), it would have happened on a PRIOR bout, meaning something about that
  stale state survived a "New Battle" transition into this fresh one.
- **Explicitly not investigated yet, by instruction** — do not look into this until the supervisor's
  own review pass. Filed only so it isn't lost.
- **Why this looks surprising against BR32.01's own fix (not a contradiction, just unexplained):**
  `BoardView.wall_cutout_units` is reassigned fresh from the NEW `CombatState.units` on every
  `_on_battle_loaded()`, and `_excluded_from_occlusion` is cleared on every `BoardView.build()` — on
  paper, neither of BR32.01's two mechanisms should be able to survive a bout transition at all. If
  this reproduces again, that gap between "should be impossible" and "was observed" is the actual
  bug.
- **2026-07-22 (supervisor review — confirmed, promoted Suspected→Active):** reproduces. The cutout
  from the *prior* match persists into a new bout — old culling never cleared, and the new bout's own
  units get no cutout at all (the only hole visible is the stale one). So it's not just a leftover: what
  survives the transition also prevents the fresh feed from taking effect.
- **Key diagnostic — clicking "Assume Control" snaps the culls to their proper location.** So the feed
  isn't permanently broken, it's *stale until an event forces a re-read*: whatever Assume-Control does
  (re-selects/re-projects the live units) is exactly the refresh the bout-load path is missing. Same
  feed-timing family as **BR32.04** (cutout jumps to the resolved cell ahead of the move animation) —
  both are "`update_wall_cutout()` reads/refreshes at the wrong moment." The bout-load path (and unit
  spawn) needs to trigger the same re-feed Assume-Control already does.
- **2026-07-23 (tb35 Pass D — confirmed as the SAME defect as BR32.01, one fix closes both)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. This entry's own diagnostic was exactly right: the
  bout-load path never re-fed `wall_cutout_units` at all unless `SquadControlOverlay` happened to be
  active — see BR32.01's own dated note above for the full mechanism and the fix
  (`BattleScene.load_battle()` now re-points the feed itself, for every overlay). Not a separate bug
  needing its own fix — merged, per this entry's own instruction to treat BR32.01/03 as one defect.
  Marked Pending alongside BR32.01, same reasoning.
- **RESOLVED** [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — confirmed live by the supervisor (2026-07-23).

### BR34.06 — Resolved — owner: `SUPERVISOR`
**AI passes its turn, in bout matches only — BLOCKER**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (post-tb34 check). Every AI unit passes its turn in bout matches. The
  qualifier matters: **bouts specifically**, which is the mode used for essentially all live
  verification.
- **This blocks confirmation of at least BR32.10 and BR27.07**, and makes bouts near-useless as a
  testing surface — which is why it should be treated as the highest-priority open entry rather than
  one bug among several.
- **Strong prior hypothesis — this is probably not new, and probably not a bout-setup bug.** CC's own
  tb33 follow-up investigation reported exactly this symptom while re-measuring the BR30.10 wall-hit
  ratio: *"zero impacts in 400 turns… every unit holds every turn, the whole mission long."* At the
  time it was attributed to one enemy spawning in a geometric nook with no clean line anywhere, and
  written off as a bad seed. The same symptom appearing across bout matches generally says it is
  **systemic, not seed-specific** — and the obvious candidate is tb33's own LOF work: either
  `has_clear_line_of_fire` returns false far more often than it should (walls are dense and
  full-height post-tb31, so a strict first-hit-must-be-the-target test may almost never pass), or the
  Pass B approach fallback isn't engaging when it should, leaving the unit with nothing to do and
  holding.
- **Where to start:** log the AI's own decision per unit per turn (which branch it took, and why LOF
  said no) — the intent/outcome logging idea in `docs/PLAN.md` is exactly the tool this needs. Do not
  fix by loosening the LOF gate until the log says that's the cause; tb33's correctness fix should not
  be undone to paper over a fallback that isn't firing.
- **2026-07-23 (tb35 Pass A/B, root cause found and fixed) — RESOLVED-PENDING-CONFIRMATION**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Confirmed the LOF-too-strict half of the prior
  hypothesis, not the fallback-not-engaging half: `ShotPlane.build`'s own depth-sort
  (`shot_plane.gd:45`) has no floor at zero, by design — a region behind the ray's own origin is
  legitimately present (the aim window reads it). But `LineOfFire._first_hit_excluding`,
  `ShotPlane.resolve_projectile`, and `DamageResolver._find_next` are three independent
  "walk the depth-sorted plane, return the first match" implementations that all inherited that
  same unfloored sort with no floor of their own — so a wall many tiles BEHIND the shooter (still
  in the plane on purpose) sorted first and won almost every resolution, including
  `has_clear_line_of_fire`'s own. That's why LOF read false almost everywhere post-tb31's dense
  walls: not because real geometry blocked every shot, but because the resolver was picking the
  wrong region. Live-diagnosed on a real `BoutSetup`-built bout (not a synthetic fixture): a unit
  reading zero clear cells even with an UNCAPPED search before the fix found one real cell
  (`(27, 16)`) after it.
  - **Fix, scoped as tight as possible:** `resolve_projectile` gained an opt-in `floor_at_zero`
    parameter (default false — every existing raw/body-local-plane caller, including this file's
    own test suite, is unaffected). `self_obstruction` and `region_at` opt in; `resolve_ray`'s own
    inline loop and `DamageResolver._find_next` (both always fed a real shooter-anchored
    `ShotPlane.build` plane, never a raw body-local one) floor unconditionally.
    `LineOfFire._first_hit_excluding` likewise floors unconditionally — a THIRD parallel
    implementation of the same rect-walk, not named in this taskblock's own audit list, found and
    fixed on the same pass.
  - **Second, distinct gap found and fixed once the LOF predicate was genuinely correct:**
    `LineOfFire.approach_path` (tb33 Pass B, BR32.10's own fix) is deliberately capped at
    `weapon.max_range + APPROACH_MARGIN` — a unit starting genuinely far from the nearest real LOF
    cell (more common than expected: mission-start positions are often tens of cells apart) found
    nothing within that cap and held forever even after the depth-floor fix, since nothing was
    LEFT to fall back to. Added `LineOfFire.closing_path`: real A* toward a cell adjacent to the
    enemy, no LOF requirement — deliberately NOT a greedy per-turn distance scorer (tried first,
    reverted: it reproduces BR32.10's own concave/U-shaped-wall freeze, since a one-step
    hill-climb can permanently stall the instant no reachable cell reduces raw distance further,
    where real A* just routes around).
  - **Verified live:** a 60-turn, 6-unit `BoutSetup` bout that previously showed 100% `held` turns
    (confirmed both before AND immediately after the depth-floor fix alone) now shows real
    movement, `burst_fired`/`impact`/`part_destroyed`/`part_mangled`/kills across the whole run
    once `closing_path` was added. Headless coverage:
    `test_shot_plane.gd::test_self_obstruction_never_resolves_to_a_wall_behind_the_shooter`,
    `test_shot_plane.gd::test_resolve_projectile_floor_at_zero_is_opt_in`,
    `test_line_of_fire.gd::test_first_hit_never_resolves_to_a_wall_behind_the_shooter` (a
    reconstructed BR27.02-shaped fixture), `test_line_of_fire.gd::test_closing_path_*` (progress
    toward a far enemy; routes around a concave wall instead of freezing).
  - **A1's decision log now exists** (`AiDecisionLog.emit`, `src/logic/ai/ai_decision_log.gd`): one
    `&"ai_decision"` event per unit-turn, branch taken + fired/held + hold reason, greppable off
    `combat.log` or a `MemorySink` in tests. **Not yet done:** the two framerate dumps (aim entry,
    turn start) A1 also called for are view-layer work, not logic, and remain open; so does BR27.09
    (A3). Marked Pending, not Resolved: this needs a live bout watched by the supervisor before
    promotion, same as BR32.10/BR27.07 below.
- **RESOLVED** [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — confirmed live by the supervisor (2026-07-23).

### BR27.02 — Resolved — owner: `SUPERVISOR`
**Chaingun bursts fire half-backward (visual only, hits are correct)**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20, observed watching a live bout play out — "the most recent two chaingun
  bursts look odd, both look like half the burst is going backward."
- **First fix (taskblock-27 Pass A1):** every attack action's shot-plane `direction` was cell-anchored
  while `origin` was muzzle-anchored — two different anchors for the same ray, which could resolve a
  target at negative depth and animate as the round travelling backward. Both now share the muzzle
  anchor. **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082-732a-4a4f-a726-04186087ef69] at the time,
  proven via a constructed overshoot-geometry test.
- **2026-07-20: supervisor reports still visually backward** — but with a key new detail: "those
  backwards shots do seem to be hitting the things they're drawn as hitting." The actual hit
  resolution (which part takes the damage) is correct; only the drawn tracer/animation direction
  still reads as backward. This means the Pass A1 fix (a `ShotPlane`/`AttackAction` geometry fix)
  either isn't the code path driving the visible tracer, or there's a second, separate anchor
  mismatch specifically in the rendering path (`resolution_player.gd`'s own tracer-drawing code, not
  yet audited against this same origin/direction-anchor class of bug). **Reopened — not
  investigated further this pass**, per instruction to just log and wait.
- **2026-07-20 (taskblock-28 Pass C):** not investigated or fixed this pass either — but
  `out/combat.log` now prints every impact/miss event's own real origin/hit geometry (was already in
  `data` since tb22/23; `LogEvent._to_string()` just never rendered it, and `Overwatch._fire`'s own
  separate impact path had no geometry at all until this pass routed it through the shared logger).
  A future session chasing this bug can read the geometry straight from the log text instead of
  re-deriving it or relying on live playback. Still open; still unconfirmed.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** primary tracer
  read/write anchors now match (post first-fix) — no mismatch there. Suspect is the DEFLECT
  bounce-continuation segment: `resolution_player.gd:464-478` draws from the hit point to
  `deflect_end_*`, computed in `shot_resolution.gd:225-232` as `hit_point + reflected_dir *
  void_range`. `reflected_dir`'s sign/normal convention (`damage_resolver.gd:118-131`) has not been
  audited against this bug class — a flipped convention there would draw a visibly backward secondary
  ray for DEFLECT-outcome shots while leaving the real hit correct, matching "half the burst backward,
  hits correct" exactly. **Bonus find (separate, same bug class):** `overwatch.gd:264-265` still
  computes `origin` as a raw cell-center — never migrated to the muzzle-anchor fix `AttackAction`
  received in Pass A1. A second live instance of the exact same anchor-mismatch class, in a different
  code path. Neither finding implemented or tested yet.
- **2026-07-23 (live playtest, `out/combat.log`, units 0/1/2 supervisor-controlled) — a new angle,
  not yet reconciled with the 2026-07-21 suspects above.** Unit 0's 12-round chaingun burst at
  `(6, 19)`, fired from roughly `(4, 17)`: **all 12 of 12 pulls resolve `DEFLECT on wall`**, every one
  clustering around hit point `~(0.3-0.8, 13.7-14.8)` —
  e.g. `DEFLECT on wall [origin (3.95, 17.26)@1.53 -> hit (0.67, 13.80)@1.71]`. That hit point sits in
  the OPPOSITE quadrant from the aimed target: origin-to-target is `+x, +y`; origin-to-hit is
  `-x, -y`. Every pull agrees on roughly the same wrong-direction spot (scatter alone wouldn't do
  that), and — unlike the two-hop chain logged minutes later for unit 2 (`DEFLECT` immediately
  followed by its own `STOP_DEAD` continuation, sharing an origin/hit boundary) — each of these 12
  pulls logs exactly ONE impact event, no continuation segment. That means the anomaly sits in the
  FIRST forward ray-cast (muzzle to first wall) itself, not in the `reflected_dir` bounce-continuation
  segment the 2026-07-21 note suspected (which only governs what happens AFTER the first hit) — a
  candidate for a still-live anchor mismatch in the primary ray itself, distinct from that suspect,
  not yet root-caused. Logged only — not investigated or fixed this pass.
- **2026-07-23 (follow-up, read-only code investigation — no fix attempted): a concrete hypothesis
  for the first-segment anomaly above, arithmetically consistent with the logged numbers.**
  `damage_resolver.gd::resolve_shot` computes each hop's own logged point as
  `origin + dir * region.depth + perp * point.x` (`dir`/`perp` from the outer call's own `direction`,
  never re-derived per hop). Solving that equation backward for the unit-0 example above
  (`origin (3.95, 17.26)`, `dir` normalized toward `(6, 19)` ≈ `(0.76, 0.65)`, `hit (0.67, 13.80)`)
  requires `region.depth ≈ -4.3 to -5.3` — genuinely **negative**, i.e. the resolved region sits
  BEHIND the shooter along this shot's own fire line, not in front of it.
  **Why a negative-depth region could win at all:** `ShotPlane.build` (`shot_plane.gd:45`) sorts the
  whole plane with a bare `a.depth < b.depth` — no floor at zero anywhere — and `_find_next`
  (`damage_resolver.gd:837`) just walks that sorted array and returns the FIRST region whose rect
  overlaps the aim point. Negative-depth regions are a known, INTENTIONAL part of the plane (`docs/09`
  taskblock06 Pass H's own `AimController.window_depth` doc comment: "a body positioned behind the
  shooter along the fire line still gets a Region... so its own frontmost depth can be small or even
  negative") — but that fact was only ever handled defensively on the AIM-WINDOW side
  (`window_depth`'s own `MIN_WINDOW_DEPTH` clamp) and the SHOOTER's-own-body self-exclusion
  (`_first_hit_excluding`/`self_obstruction`, by identity). Neither guard stops a DIFFERENT body's
  region — a wall, say — from sorting first purely because its projected depth happens to be more
  negative than every real, forward obstacle, then winning `_find_next`'s linear scan if the aim
  point's lateral/height coordinates happen to fall inside that region's rect (which a wide/tall wall
  segment's own rect can do regardless of which side of the shooter it's actually on). If real, this
  would be a genuine RESOLUTION bug (which region gets picked), not merely a rendering-direction one —
  which would refine, not just extend, the 2026-07-20 report's own claim that "hit resolution... is
  correct; only the drawn tracer direction is backward" (that may hold for whatever case prompted that
  original report, but doesn't appear to hold for this DEFLECT case). **Not verified against a
  constructed fixture — this is a read-through-the-code hypothesis from one live example's own
  arithmetic, not a proven root cause.** No fix attempted.
- **2026-07-23 (tb35 Pass B — this hypothesis confirmed and fixed, advancing but not closing)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. The 2026-07-23 read-only hypothesis above was exactly
  right: `_find_next` (and `ShotPlane.resolve_projectile`, and a third independent implementation,
  `LineOfFire._first_hit_excluding`, discovered on the same pass) all walked the unfloored,
  negative-depth-inclusive plane with no floor of their own. Fixed by flooring the RESOLVING path at
  `depth >= 0` (opt-in on `resolve_projectile`, unconditional on the other two, which are always fed
  a real shooter-anchored plane) while leaving `ShotPlane.build`'s own sort and the aim window's
  `window_depth` reading untouched, per this same bug's own 2026-07-23 note above. Headless
  regression: `test_line_of_fire.gd::test_first_hit_never_resolves_to_a_wall_behind_the_shooter`
  reconstructs this exact shape (real target ahead, wall several cells behind the shooter, present in
  the plane on purpose) and asserts the resolved hit is the target, not the wall. **Stays Active, one
  entry** (this taskblock's own scope fence, per the supervisor's ruling): this fixes the resolution
  mechanism the hypothesis named, but the original report was about the drawn TRACER direction
  specifically, and that rendering path (`resolution_player.gd`) has not been re-checked live against
  this fix — needs a live bout to confirm the visual symptom is actually gone, not just the
  resolution math underneath it.
- **2026-07-23 (supervisor request, `out/combat.log` read) — positive resolution-side evidence, not a
  closure.** The most recent chaingun burst in the log (12-round burst at cell (25,4), shooter muzzle
  (17.83, 5.47)): all 12 pulls landed, and every hit point clusters tightly around (24.7–26.9,
  4.0–4.3) — on and just past the aimed cell, `dx` ≈ +7 to +9 in the actual aimed direction. Several
  pulls deflect and continue on to a wall further in that SAME forward direction; none land in the
  opposite quadrant. This is the exact shape the depth-floor fix predicts, and the opposite of this
  entry's own original 12/12-pulls-in-the-wrong-quadrant case. Still only resolution data, not the
  drawn tracer — stays Active, one entry, pending a live look at an actual burst's own tracer.
- **RESOLVED** [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — confirmed live by the supervisor (2026-07-23), after watching a dozen real bursts post-depth-floor-fix.


### BR36.01 — Resolved — owner: `CC`
**A shooter's own `exclude_parts` list never covers its own joint regions — a self-hit is possible**
- **Source:** `CC`  ·  **CC session:** `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`
- **Found:** 2026-07-23, while building a supervisor-requested diagnostic for tb36 (raise a unit a
  level and shoot it). `BodyProjector._project_joint` emits one synthetic joint `Region` per occupied
  socket, identified by `region.part = socket.joint_handle()` — a `Part`-like object cached per
  socket, distinct from the real occupant `Part` and never walked by `PartGraph.walk`
  (`Shell.all_parts()`'s own backing). Every exclusion list built the obvious way
  (`shooter.shell.all_parts()`, the pattern `AttackAction`/`BurstAction`/melee actions/`Overwatch`
  all use to keep a shooter from self-intercepting its own shot) therefore **never excludes the
  shooter's own joint regions**. Reproduced directly: a shooter and target placed on the same
  lateral line, firing a ray built from a real muzzle point excluding `shooter.shell.all_parts()`,
  resolved to the shooter's OWN `"<part>_joint"` region at a near-zero flight distance instead of
  the target 8 cells downrange — confirmed by additionally collecting every `socket.joint_handle()`
  in the shooter's own tree, which made the same ray resolve correctly against the target instead.
- **Why this can reach a real shot, not just a synthetic test:** it requires the shooter's own real
  muzzle position to sit BEHIND one of its own occupied-socket joints along the firing axis — an
  idle (non-aiming) pose, where the weapon arm isn't extended forward of the torso/shoulder, is
  exactly the shape of geometry where that's plausible.
- **Not fixed at the time of discovery** — found investigating tb36's own multi-level work, not
  introduced by it (`joint_handle()`/`_project_joint` predate tb36 by several taskblocks, tb09 D).
  Flagged rather than guessed at under time pressure.
- **RESOLVED** taskblock-37 Pass B. Fixed at the source with a new
  `PartGraph.walk_with_joints()`/`Shell.all_parts_with_joints()` — deliberately a NEW method, not a
  change to `walk()`/`all_parts()` themselves (those back `living_parts()`'s hp>0 filter among other
  things, and a `joint_handle()` Part's own hp defaults to 1 and is never touched by joint damage,
  which lands on `socket.joint_hp` instead — repurposing `all_parts()` directly would make every
  unit's own joints read as permanently-living parts and break every `living_parts().is_empty()` kill
  check in the game). Used by all six self-exclusion call sites (`AttackAction`, `BurstAction`,
  `StabAction`, `Overwatch` x2, `ShotResolution`'s first-hop exclusion) and by
  `DamageResolver._body_of` (a ricochet's own continuation exclusion — the same self-re-hit gap,
  reached mid-flight instead of at the muzzle).
- **Live-fire finding, not just a synthetic repro:** the seeded all-level-0 regression bout
  (`test_full_mission.gd`) was NOT byte-identical after this pass — isolated to the `_body_of` fix
  alone (every other site is inert in this exact bout). The bug was reachable via ricochet all along,
  at level 0, with no elevation involved: a shot that deflects off a body could previously re-resolve
  to that SAME body's own joint region at point-blank range instead of continuing its flight. One
  early ricochet in the mission now travels much further before its next impact, cascading into a
  materially different (but more correct) mission outcome.

### BR40.02 — Obsolete — owner: `CC`
**`checkpoint_6.gd`/`checkpoint_7.gd` crash outright — both reference the retired `UnitView` class**
- **Source:** `CC`  ·  **CC session:** `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`
- **Reported:** 2026-07-25 (tb40 Pass D, discovered confirming this sandbox's GPU/X11 setup could
  run a visual checkpoint at all, before authoring checkpoint 8). `./checkpoint.sh 6` (and, by the
  same reference, 7) crashes with `Parser Error: Identifier "UnitView" not declared in the current
  scope`, a hard Godot debugger break followed by a signal-11 abort — no PNGs, no recording, nothing
  usable written.
- **Root cause:** `UnitView` was renamed to `HitVolumeView` in an earlier taskblock (grep finds no
  `class_name UnitView` anywhere in `src/` — `BattleScene`, `HitVolumeView` itself, and everything
  else already moved on). `checkpoint_6.gd`/`checkpoint_7.gd` were never updated, because visual
  checkpoints need a real GPU frame and are deliberately outside `run_tests.sh`'s own headless gate
  (`docs/00`) — nothing re-runs them automatically, so the rename silently orphaned both scripts and
  nobody noticed until this session ran one by hand. Both scripts also hand-roll the board/camera/
  unit-view wiring `BattleScene.load_battle()` now does in one call (added after these two were
  written) — the more durable fix is probably routing them through `load_battle()` the way
  `checkpoint_8.gd` (this same pass) does, not just swapping the class name.
- **Not fixed.** Out of taskblock-40 Pass D's own scope — flagged rather than silently repaired
  mid-pass. `checkpoint_8.gd` is unaffected (built fresh against `HitVolumeView`/`load_battle()`
  throughout), but 6 and 7 need their own pass before either will run again.
- **2026-07-26 — `Obsolete` (tb41 Pass E)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`].
  **Deliberately `Obsolete`, not `Resolved`: nobody verified a fix, because there was no fix.**
  `checkpoint_6.gd` and `checkpoint_7.gd` were **deleted**, per `docs/PLAN.md`'s own call — repairing
  two dead scripts to current APIs so they could then be removed is work with no product, and
  `checkpoint_8.gd` already demonstrates the pattern against the live
  `HitVolumeView`/`load_battle()` path. Git history keeps both. The code this entry describes no
  longer exists, so the entry can no longer be confirmed either way. `CC`-owned, so CC may close it.
- **What actually mattered here outlived the entry.** The root cause was never the rename — it was
  that nothing re-ran these scripts, so a rename could orphan them silently for ~15 taskblocks. That
  gap is now closed by `tools/checkpoints/parse_guard.gd`, run in `run_tests.sh` ahead of GUT:
  rendering can't happen in CI, but parsing can, and a scenario that stops parsing (or stops being a
  `SceneTree` entry point) fails the build. Verified by reintroducing this entry's exact `UnitView`
  reference into `checkpoint_8.gd`, watching the guard go red, then reverting.

### BR34.02 — Resolved — owner: `SUPERVISOR`
**Combat log is fully transparent but still eats clicks**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb34 review). Most of the combat log is fully transparent, yet the
  transparent area cannot be clicked through — so an invisible panel blocks board interaction. The
  supervisor's framing: **one of the two should change** — either the log gets a visible background
  (so it's honest about occupying that space), or the transparent region stops intercepting clicks.
- **Same class as BR31.01 and tb31 Pass A's `TopLeftControls` fix** — a container whose `mouse_filter`
  defaults to `STOP` swallowing input across its whole rect, including areas that render nothing.
  That's now the third instance of this exact failure; worth checking every full-rect UI container's
  filter in one sweep rather than one bug at a time.
- **Pairs with the log-window UX work in `docs/PLAN.md`** (title bar, minimize, resize, scroll
  hand-off). If that lands in the same pass, the "visible background vs click-through" decision is
  made naturally — a titled, resizable panel wants a real background, and the click question answers
  itself.
- **2026-07-26 — `Resolved` by the supervisor** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`].
  **Closed on the supervisor's explicit instruction, not by CC's own judgement** — this entry is
  `SUPERVISOR`-owned and the most CC may write toward closure on its own is `Pending`.
  taskblock-41 Pass F took the first of the two options this entry offered: the combat log is a real
  titled panel with a real background (`CombatLogPanel`), so it is honest about the space it occupies
  and blocking clicks over that space is no longer an invisible surprise.
- **The class of bug is not closed with it.** This entry also noted it was the third instance of a
  full-rect container at `mouse_filter = STOP` swallowing input (after BR31.01 and the
  `TopLeftControls` fix), and suggested sweeping every container at once. **That sweep has still not
  happened** and is not covered by this closure. `test_battle_scene_input.gd`'s own audit is the
  standing guard in the meantime — taskblock-41 Pass F taught it to distinguish a Control that renders
  nothing (still a bug) from one drawing a real background (legitimate), so it keeps its teeth.

### BR30.05 — Resolved — owner: `SUPERVISOR`
**Debug panel: clicks and scroll bleed through to the world board/camera**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21, live debug-panel use. Two related symptoms: (1) clicking within the debug
  menu itself can also select a world cell (the click reaches the board underneath, not just the
  panel widget); (2) once the verb list's own `ItemList` is scrolled to the bottom, further scroll
  input bleeds through and zooms the world camera instead of stopping at the list's own end.
- **Status:** not yet investigated. Likely candidates: (1) some region within `DebugControlPanel`'s
  own layout still has a plain `Control.MOUSE_FILTER_IGNORE` container gap that isn't actually
  covered by an interactive child, letting a click over that gap fall through to the 3D
  viewport/`_unhandled_input` underneath (the same class of bug `docs/09` taskblock07 Pass B4 already
  fixed once elsewhere); (2) `ItemList`'s own scroll wheel input isn't marked handled once it can't
  scroll further, so the same wheel event continues on to `CameraRig`'s own zoom handler. Both are
  UI-event-consumption gaps in the SAME panel, not two unrelated bugs.
- **2026-07-26 — `Pending` (post-tb41 supervisor request)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Both symptoms addressed, and the 2021 diagnosis above
  was right about symptom 2's mechanism and half-right about symptom 1's.
  - **Symptom 1 (clicks).** The panel was `MOUSE_FILTER_IGNORE`, set deliberately on docs/09
    taskblock-07 Pass B4's rule that "a plain container has no click of its own." **That rule does
    not fit this panel** — it is a `PanelContainer`, and `HulkTheme` gives every one an *opaque*
    `BACKGROUND` stylebox, so it visibly occupies its rect. `BR34.02`'s own resolution is the
    refinement: a container drawing a real background is not plain, and blocking clicks over it is
    honest. Now `STOP`. The B4 rule still stands for genuinely invisible containers, which is what it
    was written about.
  - **Symptom 2 (scroll).** Correct that the wheel wasn't being marked handled — but this is **not**
    specific to `ItemList` being at its end. **`MOUSE_FILTER_STOP` never blocks a wheel from
    `_unhandled_input` at all**, at any scroll position; it consumes ordinary clicks only. Measured
    with a spy at that exact input stage, after the identical defect was fixed in the combat log
    (`docs/SUPERSEDED.md`). The panel now consumes the wheel explicitly over its own rect.
  - **The wheel is forwarded before being consumed, not swallowed.** Consuming wholesale would have
    silently deleted `SpinBox`'s own wheel-to-adjust, which several verb forms use. The event is
    routed to whatever is actually under the cursor first — the verb list scrolls, a `Range` steps —
    and only then marked handled. Nothing reaches the camera either way.
  - **Regression tests** in `test_debug_control_panel.gd`, each spying on `_unhandled_input` (the
    stage `CameraRig` reads) rather than on a filter, with a deliberate control case asserting the
    spy DOES see a wheel that misses the panel, so they cannot pass vacuously.
  - **To confirm:** open `Inject...`, click around inside the panel (no world cell should get
    selected underneath), and spin the wheel over the verb list — past the bottom, past the top, and
    over a number field. The camera must not zoom in any of those; the number field must still step.
  - **Not covered by this:** the entry's own "worth checking every full-rect UI container's filter in
    one sweep" — that sweep still hasn't happened. `test_battle_scene_input.gd`'s audit is the
    standing guard, and it now distinguishes a container that renders nothing (still a bug) from one
    drawing a real background (legitimate).
- **2026-07-26 — `Resolved` by the supervisor**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`], confirmed live after the fix above. Both symptoms
  closed together, as this entry always argued they should be ("two UI-event-consumption gaps in the
  SAME panel, not two unrelated bugs") — that framing was right, and the shared cause turned out to
  be narrower than either half suggested: `MOUSE_FILTER_STOP` consumes clicks but never wheels.
- **The sweep this entry also asked for is NOT closed with it.** "Worth checking every full-rect UI
  container's filter in one sweep rather than one bug at a time" — that has still never been done,
  and this is now the fourth instance of the class (BR31.01, `TopLeftControls`, BR34.02, this).
  Carried forward to `docs/PLAN.md` rather than left buried in a closed entry.

### BR44.01 — Resolved — owner: `CC`
**An exported build loaded NO DATA AT ALL — no parts, ammo, presets, materials or variant families**
- **Source:** `CC`  ·  **CC session:** `a56eac1a-eddb-4d30-946a-4c8e594ef198`
- **Found by exporting the project for the first time** (taskblock-44 Pass A's release measurement).
  Nothing had ever been exported, so nothing had ever noticed.
- **Cause.** `DataLibrary._load_dir` filtered directory entries on `ends_with(".tres")`. That is true
  in the editor and false in **every** export: `editor/export/convert_text_resources_to_binary`
  defaults to true, so `crab.tres` ships as `crab.res` plus a `crab.tres.remap`. The filter matched
  neither form, every scan returned an empty list, and all five registries came back empty.
- **How it presented, which is the part worth remembering.** The first `i % pool.size()` downstream of
  an empty pool is an **integer modulo by zero**. A debug export reports it as a GDScript error with a
  backtrace; a **release export traps it as SIGFPE and dies with no message at all** — exit 136, no
  banner, no log line. A missing-data bug presenting as a bare hard crash cost most of the diagnosis
  time here. The earlier SIGSEGV (exit 139) seen while probing was a different symptom of the same
  emptiness reached through the real main scene.
- **Fix.** `_load_dir` normalises a directory entry to the authored `.tres` name it stands for
  (`_authored_resource_name`), accepting `crab.tres` and `crab.tres.remap` alike and deduping, since
  an exported directory legitimately contains both. It still loads by the **authored** path so
  `ResourceLoader` resolves the remap itself — one code path for editor and export, and `_load_file`'s
  existing checks are untouched. A bare `.res` with no remap is deliberately NOT handled: converted
  resources always ship with a remap, so that branch would be speculative.
- **Verified against a real export, not by inspection:** an exported debug build now runs the full AI
  bench and an exported release build produces a complete measurement (`tools/bench_release.sh`).
  Unit coverage for the name normalisation is in `test_data_library.gd`, because the bug itself is
  only reachable through an actual export.
- **`CC`-owned and resolved directly** — found by CC, fixed by CC, confirmed by the export that
  exposed it now working end to end.

### BR45.02 — Resolved — owner: `CC`
**The AI planning bench has been unable to parse since taskblock-44, and nothing noticed**
- **Source:** `CC`  ·  **CC session:** `cf5b0146-95d9-49cc-a683-28043425f65a`
- **Found 2026-07-27 during taskblock-45 Pass D**, by running `tools/bench_ai_planning.gd` — the
  instrument Pass D's whole head-to-head depends on. It does not run. It does not even compile:

  ```
  Parse Error: argument 2 should be "WorldView" but is "CombatState"   (ai_planning_bench.gd:195)
  Parse Error: "_pick_engagement_position()" is a coroutine, so it must be called with "await"
  ```

- **Two taskblock-44 changes broke it and neither was noticed.** Pass C changed the planner's
  helpers to take a `WorldView` instead of a `CombatState`; Pass D made
  `_pick_engagement_position` a coroutine. `AiPlanningBench` calls all of them directly and was
  updated for neither. **Every number taskblock-44 and taskblock-45 quote from this bench predates
  the break** — they are not wrong, but nothing has been measurable since, and the 251.2ms figure
  taskblock-45's own spec opens with cannot currently be re-taken.
- **This is BR40.02's failure mode exactly, one directory over.** A renamed identifier orphaned a
  tool, nothing re-ran it, and it rotted silently. taskblock-41 Pass E built a parse guard for
  precisely this — but scoped it to `tools/checkpoints/checkpoint_*.gd`, so `tools/` itself stayed
  unguarded. A guard that covers one directory is a guard that documents which directory was on
  someone's mind, not which ones can rot.
- **Fixed in taskblock-45 Pass D** by repairing the bench and by **widening `parse_guard.gd` to
  every `tools/*.gd`**, so the class of failure is closed rather than this instance of it.
- **The widened guard was wrong before it was right, and that is the part worth keeping.** `load()`
  returns a `GDScript` object for a script that failed to COMPILE — the resource loads and the compile
  fails, and those are separate events — so the first version reported "16 script(s) OK" with a
  deliberate syntax error sitting in the tree. It checks `reload() == OK` now, and it is verified in
  BOTH directions: a deliberate break makes it exit 1 and name the file, removing the break makes it
  pass. A guard that can only ever pass is worse than no guard.
- **`tools/migrate_data.gd` turned out to be broken too, and is meant to be.** Its own doc comment
  records that the generators it walks were deleted by the pass that landed its output, so it can
  never parse again. It carries an `@retired-tool` marker the guard skips — the marker lives in the
  retired file rather than in a list inside the guard, so the exemption and its reason cannot drift
  apart.
- **`Resolved`:** both halves are verified — the bench runs and produced taskblock-45 Pass D's numbers,
  and the guard demonstrably fails on a broken tool. `CC`-owned, closed by CC.

### BR35.06 — Obsolete — owner: `CC`
**A unit with a real available shot elsewhere can still get stuck holding a covered, blind position**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23, same log read as BR35.05. Unit 7 logs `repositioned (held: no_clear_lof)` on
  three consecutive turns (1, 2, 3) — `repositioned` means `_any_reachable_has_lof` found SOME
  reachable cell with a real shot this turn, yet the unit still resolves to a blocked position and
  holds anyway, turn after turn, making no progress. Unit 6 shows a compound case of the same family
  (`no_lof_no_route (held: ally_in_line)`, repeated across all three turns too).
- **Suspected mechanism, not confirmed:** `_engagement_score`'s own `COVER_SCORE_BONUS` can outscore
  the distance/LOF terms for a cell that's covered but blind, and `cell == self_unit.cell` is exempt
  from `NO_LOF_PENALTY` ("staying put is free") — so a unit already sitting somewhere covered has no
  scoring pressure to ever step into the open for the shot a `repositioned` branch says exists
  elsewhere. Consistent with, but not yet proven against, the actual per-candidate scores.
- **Not fixed yet.** Needs the actual `_engagement_score` breakdown for unit 7's own candidate set on
  one of these turns before concluding this is really the cover-bonus/self-exemption interaction and
  not something else — flagged rather than guessed at further.

- **2026-07-28 (review session `HBPaR3`) — description predates the planner it describes.** This was
  written against the engagement-score planner's hold branch, and taskblock-45 deleted that planner. It
  is being kept `Active` rather than closed because the *symptom* may well survive — but if it
  reproduces, it reproduces through the utility scorer returning `hold_position` as its best-scoring
  action, which is a different mechanism with a different fix. **Re-verify against the new planner and
  then either rewrite this entry or close it `Obsolete`;** do not fix it from the description above.
- **The decision log answers this directly.** `ai_utility_decision` records every candidate and its
  score, so "why did it hold when a shot existed" is now a question with a printed answer rather than
  an inference — check whether `shoot` was scored and lost, or never offered at all. If it was never
  offered, this is BR45.03 and not a separate defect.
- **The gates as currently authored (CC, 2026-07-28), so re-verification is cheap.**
  `data/utility_actions/hold_position.tres` requires **all four** of `enemy_known`, `cell_is_current`,
  `can_defer_turn` and `lof_blocked`, carries `base_weight` 0.3 — well below `shoot`'s 1.5 — and is
  marked `ends_turn`. The planner additionally refuses to offer any `ends_turn` action once the turn
  has already committed to something.
- **So a hold while a shot existed should now be impossible by construction**, since `lof_blocked` is
  the exact negation of the line-of-fire gate `shoot` requires. If it reproduces anyway, the
  interesting question is which of those two predicates disagreed with reality — not why the weights
  came out that way. Three of taskblock-45's own defects were holds winning for reasons that had
  nothing to do with weights.

- **2026-07-28 (taskblock-46 Pass F) — `Obsolete`, closed by CC (CC-owned) [CC `c0dfa479-2b43-4d9c-832d-12a7fd232bce`].**
  **`Obsolete`, not `Resolved`, and the distinction is the point:** nobody verified the described
  defect was fixed, because the code it describes — `_engagement_score`, `COVER_SCORE_BONUS`, the
  `cell == self_unit.cell` exemption from `NO_LOF_PENALTY`, the `repositioned (held: no_clear_lof)`
  log line — was deleted wholesale by taskblock-45. There is nothing left to reproduce against.
- **The symptom was checked anyway, and does not reproduce.**
  `test_utility_planner.gd::test_a_unit_in_blind_cover_takes_an_available_shot_rather_than_holding`
  builds the exact situation this entry describes — a unit whose own cell has no line, with reachable
  cells that do — and the planner moves and shoots rather than holding. The construction argument
  above holds up: `hold_position` requires `lof_blocked`, which is the exact negation of `shoot`'s own
  gate, so the two can never be offered for the same cell.
- **If this symptom is ever seen again it is a new entry**, not this one, and the first thing to read
  is the `ai_utility_decision` log for the turn: whether `shoot` was scored and lost, or never offered
  at all. Those are different defects and only one of them is about weights.

### BR40.03 — Resolved — owner: `SUPERVISOR`
**Scattered cover generates at level 0 inside raised rooms — each cover object sits at the bottom of
its own one-tile pit punched through the raised floor**
- **Source:** `SUPERVISOR`  ·  **CC session:** `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`
- **Reported:** 2026-07-26, post-taskblock-40, from looking at real generated maps. "Cover items are
  generating at 0 level, not up on top of lifted terrain."
- **Root cause, confirmed by re-running `MapGen.generate()`'s own steps in order with a level
  snapshot between each** (same private statics, same order, nothing simulated):
  `MapGen._repair_stranded_elevation` (`map_gen.gd:248`) floods with a real `Pathfinder` and flattens
  every unreached `OPEN` cell back to level 0. `Pathfinder._base_cost` (`pathfinder.gd:85`) returns
  `-1.0` for **any cell carrying a live blocker** — so every cell `_scatter_cover` (`map_gen.gd:426`,
  which runs first, at `map_gen.gd:80`) just dropped a crate/pillar/forklift on is *by construction*
  outside the reachable set, and gets `set_level(cell, 0)`. `_emit` then places that cell's
  `ship_floor` `Surface` at height 0, and `BoardView._spawn_blocker`/`_build_terrain` faithfully draw
  both the floor and the cover object down there — a `LEVEL_HEIGHT` (1.0) deep hole in an otherwise
  flat raised floor, with the cover item at the bottom of it. The view layer is innocent; the map is
  genuinely authored that way.
- **The pass is conflating two different questions.** Its documented job (its own doc comment) is
  "a raised room whose only ramp approach got sealed by cover shouldn't stay raised and stranded" —
  that requires flooding *with* blockers, which is correct and deliberate. But "a cell a mover cannot
  stand on" and "a cell that is stranded" are not the same question, and the blocker's **own** cell
  always answers the first one `false` for reasons that have nothing to do with connectivity.
- **Scale (40 seeds, 32×24 — `BoutSetup`'s own map size):** 30/40 maps author at least one raised
  room. **870 raised cells are flattened by this pass; 716 of them (82%) are cells that carry a
  scattered cover blocker.** Counting the visible symptom instead — a level-0 floored cell with 3+
  orthogonally raised neighbours — **483 of 2882 cover cells sit in such a pit, and *zero* cells with
  neither a blocker nor a spawn marker do.** Nothing else sinks. `_ensure_spawns_connected`'s own
  forced-corridor fallback (the other thing in `generate()` that can flatten terrain) fired on 0/40
  seeds and is not a contributor.
- **Same root cause as `BR40.04`** (spawn/extraction cells recessed) — one fix very likely closes
  both, but they are filed separately because the symptoms and the gameplay consequences differ and
  each wants confirming on its own.
- **Not fixed** — no fix attempted; reported for a call on direction first (CLAUDE.md: ask, don't
  invent). Candidate directions, none chosen: (a) exclude blocker-carrying cells from the *flatten*
  decision and give each one whatever level its own reachable neighbours ended up at, in a second
  pass — this keeps the sealed-room case working (the room behind the blocker is still unreachable
  and still flattens) while stopping the blocker's own tile from punching a hole, and it correctly
  lowers a cover object along with its room when the room really does get flattened; (b) flatten by
  *region* rather than per cell, so a single unstandable tile inside an otherwise reachable area is
  never treated as a stranded island. Naïvely re-flooding without blockers is **not** a fix — it
  would report a cover-sealed raised room as reachable and defeat the pass's whole purpose.
  `docs/PLAN.md`'s queued "Review pass over map generation" item is the natural home.
- **2026-07-28 (taskblock-46 Pass A) — fixed, `Pending` [CC `c0dfa479-2b43-4d9c-832d-12a7fd232bce`].** Option (a) above, taken as
  written: blocker cells are skipped by the flatten and levelled against their neighbours afterwards
  (`_flatten_stranded_blocker_cells` / `_has_reachable_neighbour`), so a cover-sealed raised room still
  flattens as a region while a crate's own tile no longer punches a hole through the floor it sits on.
- **Measured over this entry's own 40-seed sweep:** 9,279 cover cells, **0** in a pit, against the
  483-of-2,882 reported above. Also 0 floored cells anywhere in a pit, by the same
  below-three-or-more-orthogonal-neighbours metric this entry was reported with.
- **The fix was wrong once first, and the miss is worth recording.** The deferred pass checked only
  orthogonal neighbours while the flood is 8-way, which left **1 sunk crate out of 9,279** — a single
  cell across the whole sweep, invisible to anything but a total count. If a similar deferral is ever
  added, matching the flood's adjacency is not a detail.
- **The elevation itself survived the fix**, which is the half a "no pits" assertion cannot prove on
  its own: 30/40 maps still author a raised room and 3,996 of 22,938 floored cells sit above level 0.
  Pinned by `test_map_gen_raised_rooms.gd::test_the_generator_still_authors_raised_rooms`, because
  every other assertion in that file passes trivially on a map with no elevation at all.

### BR40.04 — Resolved — owner: `SUPERVISOR`
**Extraction/spawn tiles recessed to level 0 inside raised rooms — and a unit that spawns on one can
be permanently immobilised**
- **Source:** `SUPERVISOR`  ·  **CC session:** `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`
- **Reported:** 2026-07-26, post-taskblock-40. "Extract tiles that spawn without a unit atop them are
  recessed down to 0 level."
- **Root cause: the same `_repair_stranded_elevation` flatten as `BR40.03`, plus an ordering
  detail.** `_scatter_cover` (`map_gen.gd:80`) can drop a blocker on a cell that becomes a spawn zone
  a moment later; `_repair_stranded_elevation` (`map_gen.gd:88`) then flattens that cell to level 0
  because the blocker makes it unreachable; and only *afterwards* does `_place_spawn_zones` →
  `_mark_zone` (`map_gen.gd:90`, `map_gen.gd:531`) erase the blocker — deliberately, so spawns are
  guaranteed clear. The blocker goes away; **the level-0 flattening it caused does not.** What is left
  is a clean, empty, correctly-marked spawn/extraction cell sitting a full `LEVEL_HEIGHT` below the
  rest of its own raised room. `BoardView._build_extraction_tiles` draws the team-coloured marker at
  that cell's real floor height, so the marker is exactly where the map says it is — recessed.
- **The "without a unit atop them" qualifier is a visibility artifact, and the occupied case is the
  worse one.** `CombatState`'s constructor (`combat_state.gd:125`) sets `unit.height` from the same
  `UnitGeometry.true_height_for_cell`, so a unit spawned on a sunk tile sinks *with* it and its body
  hides the marker — the tile only *reads* as recessed when nothing is standing on it. Both cases are
  the same defect.
- **Gameplay consequence — a unit can spawn unable to move at all.** The pit is exactly one level
  deep, climbing is capability-gated on `Shell.can_climb()` (`shell.gd:105`, an open `CLIMBER` part
  tag), and **no part anywhere in the repo carries `CLIMBER` today** — so no unit that currently
  exists can climb out of anything. Asking a real non-climbing `Pathfinder` what a unit standing on
  each sunk spawn cell can reach: **seeds 17, 18 and 38 return exactly 1 cell — the one it is standing
  on.** Seed 32 returns 2 (the two sunk cells, both spawn tiles). It is a sealed hole, and the unit
  spends the whole battle in it. Hop-down *into* the pit is legal, so the tile still works as an
  extraction target; it is the spawning unit that is stuck.
- **Scale (same 40-seed, 32×24 sweep):** 8 of 80 spawn zones (10%) come out with non-uniform floor
  heights — always one or two of the four cells at 0.0 with the rest at 1.0. Which of the four sinks
  is uncorrelated with whether a unit spawns there (`BoutSetup._spawn_squad` takes cells in reading
  order): 4 of the 8 sank a cell a 2-unit roster would occupy, 4 sank one it would not.
- **Same root cause as `BR40.03`.** A fix there very likely closes this too. If it does not, the
  narrower fix available here is ordering — running `_place_spawn_zones` (which already erases spawn
  blockers) *before* `_repair_stranded_elevation` would make spawn cells blocker-free at flood time —
  but that only addresses spawn cells, leaves `BR40.03` untouched, and reorders a sequence whose
  current order is itself load-bearing and documented, so it is not obviously the right lever.
- **2026-07-28 (taskblock-46 Pass A) — fixed, `Pending` [CC `c0dfa479-2b43-4d9c-832d-12a7fd232bce`].** Closed by the `BR40.03` fix
  as predicted, with no ordering change needed — `_place_spawn_zones` still runs where it did.
- **The immobilisation half is asserted as gameplay**, with a real non-climbing `Pathfinder`, which is
  every unit that exists. Over this entry's own 40-seed sweep: **0 spawn cells with only their own cell
  reachable** (against seeds 17, 18 and 38 above), and **0 non-uniform spawn zones** against the 8 of 80
  reported.

### BR46.01 — Resolved — owner: `SUPERVISOR`
**A searching unit ping-pongs between two cells forever — `ROAM` and `HUNT` have no memory**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Reported:** 2026-07-28, from a real bout: "Squad 0 ping pongs in a small area without ever
  escaping the U shape." Found under `BR32.10`, but it is not that bug — see the split recorded there.
- **Confirmed from the supervisor's own combat log, and it is unambiguous.** Every unit on both squads
  decided `roam` on every single turn of the bout, and each one alternated between two or three cells
  for its whole length:

  | unit | squad | distinct cells | trail |
  |---|---|---|---|
  | 0 | 0 | 2 | (25,4) (13,4) (25,4) (13,4) (25,4) |
  | 4 | 1 | 2 | (30,17) (19,17) (30,17) (19,17) (30,17) |
  | 3 | 1 | 3 | (30,16) (19,18) (30,18) (19,18) (30,18) |

- **Mechanism: distance-from-here is memoryless.** `roam` scores `travel_fraction` — go as far as you
  can — and `hunt` scores the same input on a steeper curve. **The farthest reachable cell from A is B,
  and the farthest from B is A.** A unit with no enemy in sight walks to the edge of its reach and then
  oscillates until the turn cap. Reproduced on an open 32x24 board with no enemy present: **6 distinct
  cells over 14 turns, ten of them spent alternating between `(19,23)` and `(31,23)`.**
- **This is taskblock-46 Pass C's own bug, and the fix for it was already written down in that pass.**
  `SearchRoute`'s comment says oldest-visit-wins "cannot ping-pong between two while a third is
  ignored" — correct, and applied to `PATROL` only. The other three verbs had no route to hang a memory
  on and so got none. A verb-shaped fix would have missed it again; the fix is a published input.
- **Fixed 2026-07-28, `Pending` [CC `c0dfa479-2b43-4d9c-832d-12a7fd232bce`].** `Unit.recent_cells` is a bounded
  trail (`RECENT_CELLS` = 8, flagged) written for **every** unit every turn — not only while searching,
  because a unit that fought across a room and then lost its target must not treat that room as
  unexplored. `UtilityContext.INPUT_UNVISITED` grades it by recency rather than a binary visited/not:
  a binary makes every cell outside the trail identical and allows the same oscillation with a longer
  period. `roam` and `hunt` score it unfloored so ground just left can reach zero; `putter` scores it
  floored, because puttering is *meant* to stay local and an unfloored memory would turn it into a slow
  roam.
- **After the fix, the same probe covers 15 distinct cells in 14 turns.** Regression-tested as ground
  covered plus an explicit A-B-A-B alternation count, because "it moved a lot" and "it stopped looping"
  are different claims and only the second is the bug.
- **It did not improve completion, and saying otherwise would be the mistake this project keeps
  making.** The deterministic 100-seed escalation after the fix returns **56/100 (56.0%)**. The run
  that prompted this note showed 14/20 (70%) and that was a lucky draw — a 20-seed sample, exactly the
  kind of reading `BR45.03` records two earlier bad numbers for.
- **There is no clean before/after at n=100, and the honest reason is that the baseline is stale.** The
  last 100-seed reading was 60% and it predates taskblock-46 Pass E, so it measures a different action
  pool. Comparing 56% against it would be comparing two builds, not two behaviours.
- **What the fix demonstrably did is change the failure MODE**, which is the evidence that matters
  here: `TERMINATED` (bouts that simply never end — the oscillation's signature) fell **27 → 20**,
  while `STRANDED` rose **13 → 24**. Units that cover ground find each other, and some of those fights
  are lost. That is the same trade taskblock-46 Pass C recorded, and it points at combat quality rather
  than at another search gate.
- **To confirm:** watch a bout where the squads do not meet early. Units should sweep outward instead
  of shuttling between two tiles. The number to judge it by is the shuttle, not the completion rate.
- **2026-07-28 (supervisor check — RESOLVED).** Watched in a live bout: searching units sweep
  outward and cover ground instead of oscillating over two or three cells.

### BR32.10 — Resolved — owner: `SUPERVISOR`
**AI gets stuck on opposite sides of U-shaped / concave maps**
- **Source:** `SUPERVISOR`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **2026-07-23 (supervisor check — BLOCKED, not verifiable).** Cannot be checked: **BR34.06** (AI
  passes its turn in bout matches) means the AI does nothing observable in a bout, so there is no way
  to see whether approach-pathing works. Note this is the same symptom CC's own tb33 follow-up hit
  ("every unit holds every turn, the whole mission long") — which was written off as a boxed-in seed
  and now looks systemic. Re-check only after BR34.06 is fixed.
- **2026-07-23 (tb35 Pass A/B — BR34.06 marked Pending, unblocking this one too)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. `LineOfFire.closing_path` (added this pass for
  BR34.06's own second gap) is real A* to a cell next to the enemy specifically BECAUSE the greedy
  distance-scorer alternative reproduces this bug's own concave/U-shaped freeze — headless coverage
  (`test_line_of_fire.gd::test_closing_path_routes_around_a_concave_wall_instead_of_freezing`) proves
  it routes around a sealed column via a real gap rather than stalling. Live re-check in a supervised
  bout still needed before promotion — this entry stays Pending.
- **Reported:** 2026-07-22 (tb32 review; long-standing — logged now, wasn't in the ledger). On
  U-shaped / concave map geometry, opposing units end up stuck on opposite sides, unable to path
  around to engage.
- **Root is the known AI pathing gap, not a new defect.** `docs/PLAN.md` (Support & combat gaps): the
  AI does single-turn reachability, not a genuine multi-turn shortest-path-to-nearest-LOS search — so
  a concave wall between two units, where no single turn's reachable set reaches the other side, leaves
  the AI with nothing to move toward. Same family as the AI line-of-fire gap. The real fix is the
  multi-turn approach-pathing design in PLAN; this entry tracks the observable symptom against it.
- **Fix (tb33 Pass B):** when no cell reachable this turn has a real shot (`_any_reachable_has_lof`
  false), `_plan_ranged` no longer hands off to the greedy least-bad-reachable-cell scorer at all —
  `LineOfFire.approach_path` Dijkstra-floods (`Pathfinder.nearest_matching`, lazy — the real
  `ShotPlane`-based LOF check only runs on cells as they're popped) to the nearest cell that WOULD
  have a clear shot, capped at weapon range + margin, and queues a move truncated to this turn's own
  MP budget (`Pathfinder.truncate_to_budget`). The same fallback re-fires next turn, walking the rest
  of the path, until a reachable cell genuinely has LOF and the normal engagement scorer takes back
  over. This is what a concave map needs that the tb27 C1 `obstruction_count` fix (above) couldn't
  give it: a real multi-turn path to a target cell, including the step that moves farther from the
  enemy before it curves back in — the move a per-turn distance/obstruction scorer can't make no
  matter how it's weighted.
- **taskblock-45 note:** the verification named below ran against the engagement-score planner, which
  is now deleted, and its test file went with it. **The claim was never re-verified against the
  utility planner** — that planner has no `approach_path` fallback branch at all; it scores cells and
  a cell with no line simply scores low. Re-check before closing, or close as `Obsolete` naming the
  retirement, but do not read the verification below as current.
- **Verified (headless):** `test_unit_ai_lof_fallback.gd` — a concave-pocket fixture where the AI's
  queued move includes a genuine Chebyshev-distance increase before it decreases
  (`test_ai_takes_a_step_that_increases_chebyshev_distance_before_it_decreases`); the fallback reaches
  a real shot and fires within a bounded number of simulated turns
  (`test_the_approach_fallback_eventually_reaches_a_lof_cell_and_fires`); a fully walled-off enemy
  falls through to hold/end-turn instead of freezing or erroring; an open-field engagement never
  enters the fallback at all; same seed/fixture produces the same path (determinism).
- **Not live-verified** — headless-only per the taskblock's own design (no rendering needed: grid +
  `ShotPlane`). Needs the supervisor's own hands-on confirmation on a real U-shaped/concave bout
  before promotion to `RESOLVED`.

---
- **2026-07-28 (supervisor observation via review session `HBPaR3`) — REOPENED from `Pending`.** The
  behaviour was seen again in play: units still get stuck on opposite sides of concave geometry. The
  prior fix is therefore unconfirmed, not confirmed-and-regressed — `Pending` was never discharged.
- **Re-verify before re-fixing; it cannot reproduce for the old reason.** taskblock-45 deleted the
  engagement-score planner entirely, so whatever produces this now is new machinery reaching an old
  outcome. `LineOfFire.approach_path` survived the swap (`line_of_fire.gd:150`) and its own comment at
  :176 still names the concave/U-shaped-wall freeze as the thing it exists to avoid — so that is the
  first place to look, but the *caller* is completely different code.
- **Correction to the pointer above (CC, 2026-07-28, verified):** `LineOfFire.approach_path` and
  `closing_path` survived the swap as *code*, but **nothing calls them any more.** The retired planner
  was their only caller; today the sole references in the tree are in `test_line_of_fire.gd`, which
  exercises them directly. They are dead in production, so the comment at `line_of_fire.gd:176` is
  describing a branch that no longer runs and is the wrong place to start.
- **What replaced them is not a fallback at all.** The utility planner has no "nothing has a line, so
  walk toward somewhere that does" branch. It scores cells, and a cell with no line simply scores low
  — so a unit stuck behind concave geometry is a *scoring* outcome now, not a branch that failed to
  fire. Read `ai_utility_decision` for the stuck turn and see what actually won.
- **Do not diagnose this alongside BR45.03.** Both present as "the AI does nothing," and BR45.03 has a
  far better-evidenced mechanism (an action pool with a hole in it). Close that one first; if this
  survives it, it is genuinely separate.

- **2026-07-28 (taskblock-46 Pass C) — re-tested on concave geometry, new mechanism named, `Pending`
  [CC `c0dfa479-2b43-4d9c-832d-12a7fd232bce`].** The tb33/tb35 fix cited above — `LineOfFire.approach_path`/`closing_path`, a
  Dijkstra flood to the nearest cell with a real shot, invoked as an explicit BRANCH — **has been
  deleted**, along with its own concave test. Anything reading this entry for the current mechanism
  should stop at this line and not at the paragraph above.
- **What replaces it is not a branch.** `UtilityContext._closes_distance` reads **path distance from
  one flood rooted at the target** (`Pathfinder.reachable_costs`), so a cell on the far side of a wall
  is correctly further than one that is spatially nearer, and routing around a pocket falls out of
  ordinary scoring rather than out of a fallback that has to fire. That matters for this entry
  specifically: a branch that fails to fire leaves a unit stuck with nothing in the log to say why,
  where a scoring outcome is printed per candidate in `ai_utility_decision`.
- **Re-tested as behaviour, not as a distance metric**
  (`test_utility_planner.gd::test_a_unit_in_a_concave_pocket_works_its_way_to_a_cell_with_a_line`): a
  unit inside a U-shaped pocket with its target outside the opening reaches a cell with a real line
  within the turn budget, asserted as "it ends up somewhere with a line" rather than as a named cell,
  because the route around a pocket is a property of the map. The mechanism underneath has its own
  assertion — a cell nearer as the crow flies and further along a path must report the second.
- **Still headless only.** This entry's blocker was always that a supervised bout was needed to see it;
  that has not changed, and it is why this is `Pending` rather than anything stronger.
- **2026-07-28 (supervisor) — the concave-pathing cause is confirmed fixed; the observed symptom split
  into two other defects** [CC `c0dfa479-2b43-4d9c-832d-12a7fd232bce`]. The supervisor watched a bout that still got
  stuck and reported both halves: "Squad 1 is trapped in a lowered section, and Squad 0 ping pongs in a
  small area without ever escaping the U shape." Reading the combat log, **neither half is this bug**:
  - Squad 0's ping-ponging is `BR46.01` — `ROAM` and `HUNT` score distance-from-here with no memory, so
    a unit with nothing in sight alternates between two cells regardless of geometry. It looks like a
    U-shape problem because a U-shape is where a unit ends up with nothing in sight for long enough to
    notice. Fixed.
  - Squad 1 being trapped is `BR46.02` — descent is free and climbing needs a `CLIMBER` part that does
    not exist, so 16 of 40 generated maps contain ground a unit can enter and never leave. Open.
- **The lesson worth keeping, since this entry has now been misattributed twice:** "the AI is stuck on
  a concave map" is a *symptom* with at least three unrelated causes — no path to a firing cell (this
  entry, fixed), no memory of where it has been (`BR46.01`), and no way back out of where it went
  (`BR46.02`). The combat log distinguishes them and the screen does not.
- **2026-07-28 (supervisor check — RESOLVED).** Watched on concave geometry: units route around a
  pocket rather than freezing on the far side of it. This entry had been blocked on BR34.06 since
  2026-07-23; that entry is now `Resolved`, which is what made the check possible at all.

### BR51.13 — Resolved — owner: `CC`
**The combat log folds `fps_dump` into `wall_cutout` runs**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-31, taskblock-51 fourth hunt. *"Combat log is collapsing things that shouldn't
  collapse together. Notably, `fps_dump` lands inside `wall_cutout` reports."*
- **This contradicts a test that passes.** `test_log_fold.gd` asserts
  `test_a_diagnostic_keeps_its_own_row_and_is_never_folded_into_plumbing` — so either `fps_dump` is not
  classified as a diagnostic, or the plumbing fold swallows neighbours the test never feeds it.
  **Read the test before the code:** a green assertion beside a live defect means the assertion is
  testing something narrower than its name claims, which is exactly the failure taskblock-49's audit
  was built to find.
- Confirmed visible in `out/combat.log` across every session this block.

### BR51.10 — Resolved — owner: `CC`
**Inspect is offered when there is nothing to inspect**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-31, taskblock-51 third hunt.
- The supervisor first reported inspect as doing nothing under the player view, then diagnosed it
  themselves: *"Inspect should be disabled when it can't be selected, like when a unit isn't selected."*
- **So the defect is an affordance that lies**, not a broken action: the control is live when the thing
  it acts on does not exist, so pressing it correctly does nothing and reads as broken.
- **Resolved (taskblock-51 Pass K).** Enablement is driven by `SelectionController.can_inspect()` — whether the
  target has a body to describe — rather than by whether anything has been clicked. **Confirmed greying
  out correctly by the supervisor.**

### BR48.01 — Resolved — owner: `SUPERVISOR`
**Closing the inspect panel leaves the background permanently dimmed**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-29, while spectating.
- **Repro:** in the spectator view, click a tile or unit — the inspect panel opens as expected, with the
  background dimmed behind it. Close the panel. **The dim stays.** It does not block input; controls,
  camera and selection all keep working. It is purely visual and it persists for the rest of the
  session.
- **Reads as a dim layer whose visibility or `modulate` is set on open and never restored on close** —
  the one-way half of a two-way transition. Check every close path, not just the button: `Esc`, clicking
  away, and opening a second inspect while the first is up are three different exits and only one of
  them is obviously covered.
- **Cheap to confirm, and worth confirming rather than assuming:** if a second open/close cycle makes it
  *darker*, the dim is being stacked rather than left on, which is a different bug with the same
  symptom.
- **`SUPERVISOR`-owned because the evidence is visual.** CC can assert that a node's visibility flips,
  but "the screen still looks dark" is not something it can see.
- **taskblock-51 third hunt — RE-DIAGNOSED, and the title is now wrong.** *"The dimming on selecting
  unit bug is not unit related, it's cover/tile related. Selecting a bare tile or cover causes the
  screen to dim."*
- **That moves the suspect.** It is not the inspect panel failing to restore a dim on close; it is
  selecting a **non-unit** — bare tile or cover — dimming the screen in the first place. The two-way
  transition theory in the notes above was built on the wrong trigger and should not be worked from.
- **Likely one defect with `BR51.02`:** both are about what a click on cover or a bare tile resolves
  to. If cover resolves to the tile beneath and a tile selection dims the screen, one wrong resolution
  produces both symptoms.
- **taskblock-51 third hunt — CC mis-filed the re-diagnosis as a new entry (`BR51.08`), now folded
  back here.** The supervisor was correcting *this* entry's trigger, not reporting a second bug:
  *"The dimming on selecting unit bug is not unit related, it's cover/tile related. Selecting a bare
  tile or cover causes the screen to dim."*
- **So the trigger is a selection, not a close.** The heading still says "closing the inspect panel"
  and is now the least reliable line in the entry — work from the note above it. The two-way-transition
  theory recorded earlier was built on the wrong trigger.
- **Likely one defect with `BR51.02`:** both concern what a click on cover or a bare tile resolves to,
  and `BR51.02` has already turned up one real mis-resolution there (cover reading as its own tile).

- **`PENDING` (taskblock-51 Pass K) — CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`.** Your
  re-diagnosis was right and the heading is wrong: it is the **open** path. `Grid.blockers.get(cell)` is
  null for a bare tile and the spectator fallback passed it straight to `open_tile`, which renders its
  matrixless shape anyway — so clicking empty ground opened an empty 900x600 modal and paused the bout.
  Cover no longer reaches that branch at all (Pass K resolves it to a `PART`), and a bare tile now opens
  nothing.
- **CC's first diagnosis here was wrong and is retracted.** The bare-tile empty modal below is a real
  defect and its fix stands, but it is **not** what dims the board: the supervisor is clicking an *item*,
  which opens the inspector successfully and dims anyway.
- **Second diagnosis, from the supervisor: it is lighting, not UI.** `_preview_viewport` holds a
  `WorldEnvironment` and a `DirectionalLight3D`; the isolate path sets `own_world_3d = false` so the
  preview camera can see the real unit, which puts both into the **battle's** `World3D`. `_isolate_clear()`
  never touches `own_world_3d`, so it stays shared for the rest of the session — which is why closing
  does not lift it. Both nodes are now withdrawn whenever the world is shared, open or closed.
  **To see it:** click an item in spectator and watch the board's lighting while the panel is up, then
  close it.
- **The stacking question is answered: it does not stack** — independently confirmed by the supervisor.
- **THIRD diagnosis, and this one is evidenced by a dump rather than by reading code.** At rest the
  battle `World3D` had **four** lighting contributors — the board's environment and light, **plus the
  inspect panel's**, because `SubViewport.own_world_3d` defaults to false. After one inspect cycle it
  had two. The panel's lighting has been lighting the board all along; the first subject that takes the
  fallback path (cover, a loose item, a bare tile — anything with no live view) sets `own_world_3d =
  true`, removes both, and nothing puts them back. **`"starting a new bout does fix it"` is what proves
  it** — a rebuilt panel restores the accidental light, and neither earlier theory predicted that.
- The preview's lighting is now withdrawn whenever its viewport shares a world, so the battle's lighting
  is constant.
- **Resolved (taskblock-51), confirmed by the owner:** *"pre and post inspect are the same brightness."*
  The supervisor preferred the old, accidentally-doubled look, so `WorldPalette.BOARD_LIGHT_ENERGY = 2.0`
  restores exactly what was on screen — a measurement (two identical additive lights), not a new balance
  number. Ambient is untouched, because the two `WorldEnvironment` nodes were never additive.
- **Correction:** an earlier note here named `WorldPalette.LIGHT_ENERGY` as the tunable. No such constant
  existed; `directional_light()` never set `light_energy`, so the board ran on Godot's default 1.0. The isolate cull mask is restored from a
  value captured once at build time, never re-derived, asserted across two open/close cycles and across
  opening a second inspect over the first. **To see it:** click empty ground in spectator — the bout
  should keep playing and no panel should appear; then click a barrel, which should open on the barrel.

### BR51.09 — Resolved — owner: `CC`
**A unit killed during its turn stays selected, leaving its movement overlay on screen**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-31, taskblock-51 third hunt, immediately after `BR51.04` was fixed.
- **Repro:** kill a unit during its own turn. The turn now advances correctly (`BR51.04`), but the dead
  unit remains *selected* and its reachable-cell overlay stays drawn through the next unit's turn.
- **This is the other half of the fix I made and did not finish.** `kill_unit` advances the turn; it
  does not tell the selection to let go, and `SelectionController` holds its `selected_unit` reference
  independently of whose turn it is. Fixing the pointer without clearing the selection moved the
  symptom rather than removing it.
- **Resolved (taskblock-51 Pass L).** `SelectionController.selected_target` invalidates on read when the
  selected unit is not alive, and drops that unit's queue with it. Read-time rather than event-driven so
  no call site can forget to subscribe; asserted by killing a unit behind the controller's back.

### BR27.07 — Resolved — owner: `SUPERVISOR`
**Active-turn highlight lands on the wrong unit; change to facing-marker-only**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor check — looks right, BLOCKED on full confirmation).** The change reads as
  correct on inspection, but it cannot be properly verified while **BR34.06** (every AI unit passing
  every turn) is live — there aren't enough real turn transitions to watch. Re-check after BR34.06.
- **Reported:** 2026-07-20 (tb27 review). Two parts: (a) **design change** — instead of recoloring the
  active unit's facing wedge + team marker (tb27 D2), the supervisor wants *only the current unit to
  show a facing marker at all* (the marker's presence indicates whose turn it is, not a color). (b)
  **bug** — the current-unit highlight sometimes lands on the *next* or *prior* unit, not the active
  one.
- **Status:** open. Note the design change supersedes part of D2 (which shipped as a feature in
  CHANGELOG) — the "recolor" approach is being replaced by "only the active unit has a facing marker."
  The wrong-unit bug may be independent (an off-by-one in whichever index drives the highlight) and
  should be checked even after the design change, in case the change is built on the buggy selector.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here) — concrete ordering bug,
  confirmed:** `SquadControlOverlay._on_turn_ended()` (`squad_control_overlay.gd:573-582`) calls
  `refresh_unit_views()` — which flips the highlight to the new current unit — at line 574, BEFORE
  `await resolution_player.play(events)` at line 577 animates the unit whose turn just ended. The
  marker visually jumps to the next unit while the previous unit is still animating its own queued
  action. **Compounding bug:** `SingleUnitOverlay._on_turn_ended()` (`single_unit_overlay.gd:40-42`)
  calls `super._on_turn_ended(events)` WITHOUT `await` — since the parent implementation contains an
  internal `await`, this lets `_auto_select_if_current()` run immediately, racing ahead of the
  parent's own animation/AI-batch completion. **Candidate fix (not yet applied):** reorder so
  `refresh_unit_views()`'s highlight flip runs after the animation await completes; add the missing
  `await` in `SingleUnitOverlay`.
- **2026-07-22 (tb32 Pass D) — both parts done:** (a) design change — `HitVolumeView.set_active_turn()`
  no longer recolors anything (`ACTIVE_TURN_COLOR` retired); it toggles the facing wedge's own
  `.visible` instead, so only the current unit ever shows a facing marker at all, exactly as
  requested. (b) ordering bug — `BattleScene.refresh_unit_views()` gained an `apply_highlight: bool =
  true` parameter; `SquadControlOverlay._on_turn_ended()` now passes `false` and calls the (newly
  public) `battle.apply_active_turn_highlight()` itself AFTER `await resolution_player.play(events)`
  completes, so the marker no longer jumps to the next unit mid-animation. `SingleUnitOverlay._on_
  turn_ended()` now `await`s its `super` call, closing the compounding race. Every other existing
  caller (`advance_ai_turns`, `SpectatorOverlay`) keeps the old default (`apply_highlight` true, no
  deferral) unchanged.
- **2026-07-22 (supervisor tweak):** "facing marker" means the WHOLE disk/facing-pip assembly (the
  ground marker AND the wedge together), not the wedge alone — the first pass only toggled the
  wedge's own visibility, leaving every unit's ground disk always showing regardless of whose turn
  it is. `set_active_turn()` now toggles both `_team_marker.visible` and `_facing_wedge.visible`
  together.
- **2026-07-28 (supervisor check — REOPENED from `Pending`).** Now checkable, since BR34.06 is
  `Resolved`. Observed: **unit 1 holds the highlight, the highlight jumps to unit 2, and only then does
  unit 1 move.** Reads as if a turn is being passed before its animation finishes.
- **That symptom is consistent with the highlight reading live state rather than playback position.**
  `BattleScene.apply_active_turn_highlight` sets it from `combat_state.current_unit()`, and RESOLUTION
  advances `current_unit` when the *action* resolves — while `ResolutionPlayer` is still drawing the
  previous unit's move. Two clocks, one signal. `battle_scene.gd:472-478` already names the hazard in
  prose: the batch badge is unconditional in `refresh_unit_views` **unlike the active-turn highlight,
  which "a caller might want to defer until an animation finishes."** The defer appears not to be
  happening on every path — there are three call sites.
- **Check whether this is the same defect the entry originally described.** The original was the
  highlight landing on the *wrong* unit; this is the right unit at the *wrong time*. If the selector is
  now correct and only the timing is off, say so and rewrite the entry rather than carrying both
  descriptions forward.
- **The general fix is `PLAN.md`'s *Player view and sim view — render a snapshot*.** A view that draws
  the last resolved state cannot show a highlight for a turn whose animation has not played. The narrow
  fix is deferring the highlight until playback drains; the narrow fix is worth taking now, but it is an
  instance of the class that item dissolves.
- **taskblock-51 duplicate check — suspected the same defect as `BR32.09`, NOT merged.** The supervisor
  answered both with one observation: *"Indicator moves to next unit before animation completes when AI
  is controlling. Indicator moves with unit correctly when player is controlling."* That is one
  behaviour, and it is the *timing* description in `BR32.09` rather than the *wrong unit* this entry's
  title claims — so this heading may also be stale.
- **Both are `SUPERVISOR`-owned, so CC has flagged rather than combined them.** Merging is the owner's
  call; the useful finding is that the AI-driven path does not defer and the player-driven one does.
- **Resolved (taskblock-51 Pass L), on the owner's instruction.** `SpectatorOverlay._advance()` now
  defers the active-turn flip until after `resolution_player.play()` and applies it explicitly
  afterwards — the same shape tb32 Pass D gave the player path, which was the only call site it
  changed. The supervisor's AI-vs-player comparison was the diagnosis.


### BR32.09 — Resolved — owner: `SUPERVISOR`
**Spectator: current-unit indicator jumps to the next unit before the active turn resolves**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review, direct note). In spectator, the current-unit indicator
  advances to the next unit before the active unit has finished resolving its entire turn.
- **Likely the spectator-side sibling of BR27.07's ordering bug.** tb32 Pass D fixed the *player*-view
  early-flip by deferring `apply_active_turn_highlight()` until after the resolution animation
  (`SquadControlOverlay._on_turn_ended()`), but the spectator path wasn't touched — its indicator
  still flips ahead of resolution. Apply the same defer-until-animation-finishes fix on the spectator
  overlay's turn-end handler.
- **Resolved (taskblock-51 Pass L), on the owner's instruction.** `SpectatorOverlay._advance()` now
  defers the active-turn flip until after `resolution_player.play()` and applies it explicitly
  afterwards — the same shape tb32 Pass D gave the player path, which was the only call site it
  changed. The supervisor's AI-vs-player comparison was the diagnosis.

### BR51.11 — Resolved — owner: `SUPERVISOR`
**A unit refacing mid-move sometimes turns the long way around**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-31, taskblock-51 third hunt.
- **Repro:** watch a unit move along a path that changes direction. It sometimes rotates **270° one way
  rather than 90° the other**.
- **Visual only, as far as is known** — the facing it arrives at is presumably correct, so this is the
  interpolation choosing the wrong arc rather than the logic choosing the wrong facing. **Confirm that
  before touching the resolver:** if the *final* facing is ever wrong too, this is a different and much
  more serious entry.
- Suspect the shortest-arc handling where an orientation crosses the wrap point.

- **`PENDING` (taskblock-51) — CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`. Confirmed, and it was
  exactly that.** `ResolutionPlayer` tweened the facing with `tween_method`, which interpolates its two
  arguments as **plain numbers** — handed raw orientations it runs 0.1 -> 6.0 the long way, 336 degrees
  left instead of 24 right. It now tweens towards `from + angle_difference(from, to)`, an angle equal to
  the target but numerically adjacent to the start.
- **Your two observations were both diagnostic.** *"They end up facing in reasonable directions"* is why
  this was visual-only: only the path was wrong, never the arrival — so the regression test asserts the
  **arc**, because an endpoint test passes on the broken version too. *"The point to point animation has
  them facing the right way"* separates the facing tween from the slide, which is the other half.
- **Squad 1 and not squad 0 is a distribution of starting facings, not a squad rule.** The arithmetic has
  no idea whose unit it is turning; squad 1 simply starts facing the other way and so crosses the wrap
  point more often. Pinned in a test so the fix is not mistaken for a squad-specific patch.
- **To see it:** watch a path that changes direction. Every turn should now take the short way.
- **Resolved — confirmed by the owner:** *"Confirmed rotating is going the correct way now."*

### BR35.04 — Resolved — owner: `SUPERVISOR`
**A DEFLECT's drawn "bounce" tracer is a decorative fixed-range projection, not the real continuation**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **2026-07-23 (supervisor observation — independently seen, and a decision made).** Observed live as
  *"some drawn deflect raycasts are blue"* — the same defect from the visual side that this entry
  found in the log. The blue segments are exactly these decorative fixed-range projections; the real
  continuation, when one exists, is a separate `stop_dead` ray drawn independently.
- **Supervisor's call: remove the decorative projection entirely.** Do not try to make it agree with
  the real resolution — draw only geometry that corresponds to something that actually resolved.
  A tracer nobody can distinguish from a real hit, drawn to an arbitrary distance, is worse than no
  tracer: it invented the "wall impacts" the supervisor spent a whole review session investigating.
  **Owner promoted to `SUPERVISOR`** — the fix is visual, so closure needs a live look.

- **`PENDING` (taskblock-51 Pass C) — CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`.** Deleted, as
  instructed, rather than reconciled. `ShotResolution.log_impact_result` no longer stamps
  `deflect_end_*`, and `ResolutionPlayer._play_impact` no longer draws a second segment. A ricochet that
  hits something logs its own `impact` and draws through the ordinary path; one that hits nothing draws
  nothing. **Four tests asserted the old behaviour and were rewritten** — they were not wrong about the
  code, only about what it should do.
- **To see it:** fire until a deflect resolves. There should be **no blue segment**, and no line running
  off to an arbitrary distance from the deflection point.
- **See also BR35.07**, the same class of defect on the `STOP_DEAD` tracer (drawn past its own hit
  point). Filed separately per the supervisor's own rule that one entry tracks one observed symptom.
- **Found:** 2026-07-23, reading a real chaingun burst out of `out/combat.log` at the supervisor's own
  request. Every `DEFLECT` outcome logs a `deflect_end_x/y/height` (`shot_resolution.gd:225-232`),
  drawn by `ResolutionPlayer._play_impact` as a second, visually distinct segment
  (`resolution_player.gd:457-478`) — but that endpoint is `hit_point + reflected_dir * void_range`,
  where `void_range` is just the weapon's own authored max range (or the map's longest side,
  unauthored) — **a fixed-distance projection with zero awareness of whether anything is actually
  there.** The code's own doc comment says this is deliberate: drawn "regardless of whether a real
  ricochet hop happens to follow it." Meanwhile `DamageResolver` separately does a REAL recursive
  search along that same reflected direction, and when it finds something, that's its own
  independent, correctly-resolved `impact` event (a `STOP_DEAD`/`PENETRATE`/etc. a few lines later in
  the log) — with its own separately-drawn tracer.
- **The two are drawn as if they agree; they usually don't.** On a real burst read from the log: a
  deflect at (24.91, 4.01) had a REAL follow-up wall hit only ~3.7 units further on, at (25.65, 0.43)
  — but the cosmetic bounce line was drawn a full 12 units out (the chaingun's own max range) in the
  same direction, sailing straight through/past the real wall with no awareness it was there. Two
  visually distinct tracers, same origin, same direction, different endpoints, both drawn as if
  each were the truth. For pulls where the real recursive search found NOTHING (most of them, in
  that same burst), the "wall impact" the supervisor visually saw was **purely the decorative
  projection** — no wall actually took damage there, nothing mechanical happened at that point at
  all; whether it visually reads as a hit is coincidence.
- **Why this matters more than a visual nit (supervisor's own framing):** visible raycasts need to
  match under-the-hood behavior as closely as possible, specifically *because* CC's own debugging
  process depends on reading the log and reasoning about what the drawn scene must have looked like —
  a drawn tracer that routinely disagrees with the mechanically-resolved outcome breaks that
  correspondence, the same class of problem the whole `docs/00` "read the real node back" rule exists
  to prevent, just on the logging/replay side instead of the geometry side.
- **Not fixed yet.** Candidate fix: when the real recursive search succeeds, draw the bounce segment
  to THAT hit's own real coordinates (already logged as its own event) instead of the fixed
  `void_range` projection — the cosmetic projection should only ever be the fallback for the case
  where the recursive search genuinely finds nothing, mirroring `log_miss_result`'s own "void" ray
  exactly, not a separate always-drawn distance regardless of a real hit existing.
- **Resolved — confirmed by the owner**, together with the continuation-tracer work that replaced it:
  dull orange rather than blue, and flashing with its own initial hit rather than after it.

### BR27.03 — Resolved — owner: `SUPERVISOR`
**Other shots appear to resolve before an earlier shot's own deflect finishes**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20, correcting a taskblock-27 misdiagnosis: Pass A2 had assumed a shot and
  its own deflect were wrongly paused apart and inserted a fix for that — but they're SUPPOSED to
  resolve simultaneously, that was never broken. The real, still-open defect is different: a
  DIFFERENT, later shot can appear to resolve/animate before an EARLIER shot's own deflect segment
  has finished.
- **Status:** not yet investigated. taskblock-27 Pass A2's own `DEFLECT_BEAT_MS` fix (a deliberate
  pause between a primary hit and its own deflect) does not address this bug and is itself now a
  wrong implementation of the intended simultaneous behavior — not reverted, only reclassified.
  Likely candidate: `ResolutionPlayer`'s own inter-event sequencing between separate impact events,
  not the intra-event primary/deflect pairing `DEFLECT_BEAT_MS` targeted.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** confirmed not an
  intra-event bug — each `ResolutionPlayer.play()` call is fully await-serialized internally,
  primary+deflect included. The gap is a missing reentrancy guard: `play()` has no busy-flag, and
  `SpectatorOverlay.step_once()` (`spectator_overlay.gd:249-251`) calls `pause()` (only flips a bool,
  doesn't cancel anything in flight) then immediately awaits `_advance()` — so a Step/Play issued
  right after Pause can start a SECOND concurrent `play()` while an earlier turn's own deflect tracer
  is still animating. **Candidate fix (not yet applied):** add a busy/in-flight guard to
  `ResolutionPlayer.play()`, or have `pause()` actually await the in-flight `_advance()` before
  returning.
- **`PENDING` (taskblock-51 Pass C) — CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`.** `ResolutionPlayer`
  inserted `INTER_SHOT_BREAK_MS` between **every** consecutive impact, so a single trigger pull that hit and
  then deflected played as two gunshots a tenth of a second apart, and a later shot could begin while the
  earlier one's continuation was still to come. Impacts now carry a `hop_index`; only hop 0 takes the break,
  and a pull's hops are drawn without awaiting each other so they flash together. taskblock-27 Pass A2's
  `DEFLECT_BEAT_MS` — a deliberate pause built on the opposite assumption — is now unused.
- **To see it:** fire until a shot penetrates or deflects. It should read as one event, not two.
- **Resolved — the supervisor's instruction after seeing it in play.**


### BR34.01 — Resolved — owner: `SUPERVISOR`
**Every penetration/deflection hop replays the full bright hit-flash, not just the first**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (live playtest). A single queued shot that penetrates or deflects through
  several objects visually reads as multiple separate shots firing — "the bright raycast flashing
  should only play for the first hit," not for every subsequent hop of the same trigger pull.
- **Root cause, read-only investigation (quick look, not a fix):** `DamageResolver.resolve_shot`
  correctly returns one `Array[ImpactResult]` per trigger pull, one entry per hop (wall, then cover,
  then the target, say) — that's the right granularity for damage/consequence bookkeeping.
  `ResolutionPlayer.play()` (`resolution_player.gd:148`) reuses that SAME granularity directly for
  PLAYBACK: its own loop treats every `&"impact"`/`&"miss"` `LogEvent` as an independent "shot"
  (`is_shot := event.kind == &"impact" or event.kind == &"miss"`), inserting `INTER_SHOT_BREAK_MS`
  between them, and `_play_impact()` (`resolution_player.gd:440`) unconditionally calls
  `_spawn_tracer()` — the full bright-live-to-dull-fade flash — for every one of them. Nothing in
  `LogEvent.data`/`ImpactResult` distinguishes "the first hop of this trigger pull" from "hop 2+,
  the same round continuing forward" — the log's own per-hop granularity (correct for its own job) is
  being read as the playback's own per-shot granularity (wrong for this job), conflating two different
  concerns. A 3-hop PENETRATE chain from one queued attack currently plays THREE full bright flashes
  with pacing gaps between them, reading as three separate trigger pulls.
- **Distinct from BR27.02** (the backward-tracer-direction ticket) — this is about flash/pacing
  REPETITION per hop, not the direction of any single segment. Both live in the same playback/
  resolution-geometry neighborhood but are separate defects.
- **Not investigated further, no fix attempted** — logged per instruction. A real fix needs a design
  call on what SHOULD distinguish "first hit of a pull" from "continuation," which doesn't exist in
  the data today (candidate: thread a hop index/continuation flag through `ImpactResult`/`LogEvent`,
  then have `ResolutionPlayer` skip the live flash — or use a dimmer one — and skip the inter-shot gap
  for hop index > 0). That's a design/implementation question for whoever picks this up, not answered
  here.

---
- **`PENDING` (taskblock-51 Pass C) — CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`.** The entry's own
  diagnosis was right: playback reused the resolver's per-hop granularity as if each hop were a separate
  shot. **Hop 0 keeps the bright flash; every hop after it now draws in a dull orange** and appears at the
  same time as its own initial hit, so one trigger pull reads as one event with a tail rather than as
  several shots firing.
- **To see it:** a shot that penetrates several objects should flash bright once, with dull orange
  continuations alongside it.
- **Resolved — the supervisor's instruction after seeing it in play.**


### BR35.07 — Resolved — owner: `SUPERVISOR`
**`STOP_DEAD` tracers are drawn past their own hit point, reading as a penetration that never happened**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb35 review, live). A drawn `STOP_DEAD` ray continues visibly *beyond* the
  point where it actually stopped, so a round that was halted dead reads on screen as though it
  punched through and carried on.
- **Same class as BR35.04, different outcome type:** tracer geometry drawn from something other than
  what the resolver actually produced. Where BR35.04 is a deliberately decorative fixed-range
  projection on `DEFLECT`, this is a `STOP_DEAD` segment overshooting its own resolved endpoint —
  worth confirming whether it shares the same drawing path (`ResolutionPlayer._play_impact`) and the
  same "draw to a distance, not to the hit" habit, or is a separate length/endpoint error.
- **The reason this matters beyond looks:** it makes the two outcomes visually indistinguishable.
  `STOP_DEAD` and `PENETRATE` are mechanically different results, and if a stopped round is drawn
  like a penetrating one, the player cannot read what their weapon actually did — the same class of
  harm as the dartboard understating spread (tb34): the display teaching a rule the sim doesn't
  follow.
- Filed separately from BR35.04 per the supervisor's own convention — one entry per observed symptom,
  cross-linked, rather than bundling by shared root.
- **Resolved on the supervisor's report, and CC did not fix it directly.** No change was made
  targeting this entry. The most likely cause of its disappearance is Pass C's continuation work:
  a `STOP_DEAD` round's *next* hop used to be drawn as a separate bright flash a tenth of a
  second later, which reads exactly like one ray continuing past its own stopping point. That is
  a plausible explanation, **not a verified one** — recorded as such rather than claimed.

### BR35.03 — Resolved — owner: `CC`
**Every debug-panel verb rebuilds the entire board view, not just ones that touch blockers/field items**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23 (tb35 Pass C, view-layer `Grid.blockers` audit sweep). `SpectatorOverlay.
  _on_debug_panel_applied()` calls `battle.sync_board_view()` (a full teardown/rebuild of every
  static mesh — walls, field items, indicators) after **every** debug verb, including ones with no
  possible effect on board geometry (`set_ap`, `set_mp`, `force_current_unit`, ...). Before tb31 C
  this rebuilt a handful of props each time; now it rebuilds hundreds of wall meshes on every single
  debug action regardless of relevance. Debug-build-only (`OS.is_debug_build()`), so the blast radius
  is limited, but it's a real, newly-heavier cost every time.
- **Not fixed this pass.** The fix is straightforward in shape (gate the rebuild to verbs that can
  actually touch `grid.blockers`/`field_items` — `move_object`/`spawn_object`/`remove_object`) but
  getting the verb-id list exactly right (not missing one that can add/move/remove a blocker or field
  item) wants a careful pass of its own rather than a rushed guess at the end of an already-long one.
- **2026-07-26 — `Pending` (tb42 Pass E)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Both overlays'
  `_on_debug_panel_applied` called `sync_board_view()` — a full `BoardView.build()` of terrain, grid
  lines, every blocker and every field item — after **every** verb, including the ~20 that only ever
  touch one unit's AP, facing, pose or parts. `DebugVerbs.affects_board()` is now the one authority
  both overlays read; the same question answered separately in two files is how they drift.
  `move_object`/`remove_object` stay in the list unconditionally: either can target a cell or a unit,
  decided at call time, and a missed board rebuild is invisible-until-noticed while an extra one is
  merely slow.
  - A test checks the list against `DebugVerbs.all()`, and immediately earned it: my first draft
    listed `place_cover`/`clear_cover`, which are **not** panel verbs (the panel exposes
    `spawn_object`/`remove_object`, which front both). They matched nothing and would have quietly
    misled the next reader.
  - **To confirm:** open `Inject...`, apply a unit-only verb (Set AP, Set Facing), and check the board
    does not visibly rebuild; then apply Set Cell Level or Spawn Object and check it does.
- **2026-07-28 (review session `HBPaR3`) — moved from `Pending` back to `Active`.** A `CC`-owned
  `Pending` is not a stable state: `Pending` means the *owner* has not seen the fix work, and CC is the
  owner here. Either it is verifiable and should be closed, or it is not and CC is the wrong owner.
  Returned to `Active` so it is picked up in the next bug hunt rather than sitting in a status that
  nobody can discharge.
- **Resolved (taskblock-51) — confirmed, not fixed here.** taskblock-42 Pass E already gated the rebuild:
  **both** overlays now call `battle.sync_board_view()` only `if DebugVerbs.affects_board(verb_id)`. The
  entry's own triage predicted this ("may only need confirming"), and reading both handlers confirms it.
  `set_part_hp` was added to `BOARD_CHANGING_VERBS` in taskblock-51 once it could destroy things.

### BR51.02 — Resolved — owner: `CC`
**`set_part_hp` cannot target a part that is not on a unit**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-07-30, taskblock-51 Pass A, while trying to force a detonation.
- **Repro:** open Inject, choose `set_part_hp`, and try to target a goo barrel or any other field
  object or blocker. There is no way to name it — the verb's target is a unit part.
- **Filed as a bug, and half of it was not one.** "`set_part_hp` should accept things that are not unit
  parts" is a capability that never existed — a **design change**, and the supervisor's standing rule is
  that design changes live in the report and their notes until review, not in this ledger. That half
  landed and is recorded in `reports/Report-Taskblock51.md`; it should not have been an entry.
  **What remains below the reopen is a real defect** and is what this entry now means.
- It was blocking the hunt either way: forcing a detonation is the deterministic route to `BR35.08`,
  which otherwise needs a landed shot on a barrel that `BR51.01` is interfering with.

- **Resolved (taskblock-51).** `set_part_hp` takes the same `{kind, unit, cell}` object target
  `move_object` and `remove_object` already use, so a blocker or field object can be named by clicking
  it. An empty `part_id` means the blocker itself, so killing a barrel needs no id typed. A bare `Unit`
  still works unchanged — widening a target must not narrow an existing one, which is asserted.
- **Your detonation route is open:** spawn a goo barrel, click it, `set_part_hp` → 0.

- **REOPENED (taskblock-51, third hunt). The fix was real and insufficient, and the gap is upstream of
  it.** The injector now resolves a cell target to the blocker there — that part works and is tested.
  But the supervisor cannot *give* it that target: *"barrels aren't clickable. Selecting a barrel (or
  any cover) actually selects the tile beneath."*
- **So the defect is in what a board click resolves cover to**, not in the verb. `set_part_hp` was the
  visible symptom; the real entry is that cover cannot be made the panel's active target at all, which
  means every OBJECT-target verb has the same hole.
- **My error worth recording:** I tested the injector against a hand-built `{kind: CELL, cell: X}` dict
  and called the bug fixed without once driving the click that produces that dict. A test that
  constructs its own input cannot tell you the caller never produces it — the same shape as
  taskblock-48's "input tidier than reality is worse than no test".
- **Subsumed by the taskblock-51 addendum's Pass K**, which builds the selection target this needs.
  Every OBJECT-target verb has the same hole, so it is fixed there rather than per-verb here.

- **`Pending` (taskblock-51, after the reopen) — two defects, one symptom.**
  1. **The panel labelled cover as its tile.** `_refresh_active_label` special-cased units and called
     everything else "Active: Cell (x, y)", so a barrel click was indistinguishable from a floor click.
     It names the part now.
  2. **The injector re-derived what the click already knew.** A cover click resolves to a `PART` hit
     carrying the exact `Part` struck; `_object_target` ignored it and looked the cell up in `blockers`
     a second time. It uses the struck part directly — the same "never compute it twice" rule
     `docs/02` applies to shots.
- **To see it work:** click a barrel — the panel should read `Active: goo_barrel @ (x, y)`, not
  `Active: Cell`. Then `set_part_hp` with an empty `part_id` and 0.
- **Tested against the click shape this time**, not a hand-built dict — that omission is what let the
  first fix ship broken.
- **2026-07-31 (supervisor check — RESOLVED).** `set_part_hp` now reaches non-unit targets.

### BR51.20 — Resolved — owner: `CC`
**`set_part_hp` to zero never triggers the part's failure mode**
- **Source:** `SUPERVISOR`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-01, taskblock-51 sixth hunt. *"Setting part HP on a goo barrel to zero doesn't seem
  to cause a detonation."*
- **Confirmed by reading, not guessed:** `BoutInjector.set_part_hp` does `part.hp = hp` and nothing else.
  `DamageResolver.resolve_part_failure` — the only thing that runs MANGLE / DISABLE / DETONATE / FRAGMENT
  / MELTDOWN — has exactly one caller, inside impact resolution. So a part zeroed by the debug verb is at
  0 hp and has not *failed*.
- **This is the whole point of the verb.** `BR51.02` existed to make forcing a detonation possible; the
  targeting half landed in Pass K and this half was never there. Nothing in the block has actually forced
  a detonation.
- **Do not simply call `resolve_part_failure` from the injector without deciding what it needs.** It takes
  an `ImpactResult` and writes fragment/detonation results into it, so a debug-triggered failure needs a
  real impact to hang off or a deliberate answer for what to pass — inventing a hollow one would put a
  second failure path beside the resolver's.

- **`Pending` (taskblock-51).** `set_part_hp` now runs `resolve_part_failure` when hp reaches 0, with a
  nullable `ImpactResult` so no hollow stand-in is invented. The detonation event moved to
  `DamageResolver`, where the failure happens — one emitter for both the shot path and the forced one.
- **`Pending` rather than closed although CC owns it:** the deliverable is a sphere CC cannot see.
  **To check:** click a goo barrel, `Set Part HP` -> 0, and it should explode with a red sphere sized to
  its real radius.
- **2026-07-31 (supervisor check — RESOLVED).** Zeroing a part runs its failure mode.

### BR52.01 — Resolved — owner: `CC`
**`PartPicker` hit-tests blockers and field items at world height 0, while `BoardView` draws them at
the cell's real height**
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-01, taskblock-52 Pass A, reading the four collections the ray march has to cover.
- **Two callers, one geometry call, different arguments.** `UnitGeometry.assembly_placements(root,
  cell, orientation, pose, height)` defaults `height` to `0.0`.
  - `BoardView._spawn_blocker` passes `_height_for(cell)` — and its own comment says why: *"a cover
    object or wall on a raised cell now needs to actually sit ON that cell's own real ground, not
    float at world level 0"* (taskblock-37 Pass E).
  - `PartPicker._nearest_t` calls `UnitGeometry.assembly_placements(part, cell)` — no height at all.
- **So on any raised cell the clickable/aimable volume is not where the mesh is**, which contradicts
  `docs/10`'s "render is hitbox" directly. `ShotPlane.build` gets this right for the same objects
  (`UnitGeometry.true_height_for_cell`), so the picker is the odd one out of three.
- **Blast radius:** every hover, every aim reticle, every click that resolves to cover — the paths
  `BR51.02`/`BR51.25` were both found in. A flat map hides it completely, which is why it has survived.
- **Filed on a reading, not yet on a measurement.** taskblock-52 Pass D marches the same collections
  at their true heights and is where the proof and the fix land together; recorded here first so it is
  not lost between passes.

- **Resolved (taskblock-52 Pass D), and it was two defects rather than one.**
  1. **`PartPicker._nearest_t` took `assembly_placements`' default height of 0.0.** It passes
     `UnitGeometry.true_height_for_cell` now, the same value `BoardView._spawn_blocker` and
     `ShotPlane.build` already used.
  2. **`near_ray`'s cheap reject was height-blind too**, and this half was worse. It measured the
     perpendicular distance from the ray to a point on the **ground**, so a blocker on a cell raised
     by 2.0 was **rejected outright** for any ray passing above ~3.0 — never reaching the per-box
     test at all. That is exactly the failure the reject's own doc comment says must never happen
     ("it may admit a cell the real test then rejects, and must never do the reverse"). It takes the
     cell's real height now.
- **Found by a test, not by reading.** The second half only surfaced because
  `test_a_blocker_on_a_raised_cell_is_hit_where_it_is_drawn` fired at a raised wall *at the height
  `BoardView` draws it* and got nothing back. The reading alone had found only the first half.
- **Proved against the renderer's own placement call** — the test asks
  `UnitGeometry.assembly_placements(wall, cell, 0.0, null, true_height_for_cell(...))` where the box
  actually is and fires at that, rather than re-deriving an expected height. A second copy of the
  formula would have agreed with the broken code.
- `test_the_picker_and_the_march_agree_about_a_raised_blocker` pins the two answers together, since
  the aim UI and resolution asking the same question and getting different answers is the shape this
  entry was.

### BR35.08 — Resolved — owner: `SUPERVISOR`
- **2026-08-02 (supervisor, live): *"I saw an explosion trigger naturally, that likely clears a
  bug."*** Recorded, **not closed** — this entry is `SUPERVISOR`-owned and "likely" is the
  supervisor's word, so promoting it is theirs to do. A naturally triggered detonation is exactly what
  this entry has been waiting on: the previous blocker was that it could only be judged from a
  shot-driven blast (`BR51.21`: no injection ever animates), which needed a shot that reliably lands.
**Detonations are invisible — nothing is drawn when an explosion resolves**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb35 review, live). A detonation resolves mechanically but draws nothing
  at all, so neither the fact of the explosion nor its extent is visible.
- **Supervisor-specified presentation (a spec, not a suggestion):** draw a **translucent red sphere**
  originating at the detonation point that **grows outward**, its **final radius matching the actual
  explosion radius** — so the visual is a readout of the real mechanical extent, not decoration —
  then **fades out**.
  - **Grow : fade time ratio is 1 : 3.**
  - **Total time is exposed as a tunable in the same place bullet timing lives**, defaulting to
    **1000 ms**.
- **Read the radius from the resolved detonation, never a parallel constant.** The whole value here is
  that the sphere teaches the player the real blast extent; a separately-authored visual radius that
  drifts from the mechanical one would be BR35.04's mistake again in a new place — a drawn thing that
  looks authoritative and isn't.

- **taskblock-51 Pass A — blocked, not attempted.** The deterministic route (spawn a goo barrel, zero
  its HP) is unavailable because `set_part_hp` cannot target a non-unit part (`BR51.02`), and the
  fallback of shooting one is unreliable because of `BR51.01` and `BR51.03`. **Three bugs deep before
  this one can be looked at** — which is the argument for fixing `BR51.02` before anything else in the
  block.

- **`PENDING` (taskblock-51 Pass C) — CC session `c0dfa479-2b43-4d9c-832d-12a7fd232bce`.** Built to the
  stated spec: translucent red sphere, grows to the real `detonate_radius`, fades, grow : fade 1 : 3,
  `ResolutionPlayer.DETONATION_MS` defaulting to 1000 ms. A new `detonation` log event carries the centre
  and radius, emitted **once per explosion** rather than once per victim, so the drawn extent is a readout
  of the mechanical one.
- **Gap:** a detonation that harms nobody still draws nothing — `detonated_units` is empty and the
  resolver returns no separate "it detonated" fact. Same shape as `BR34.05`.
- **To see it:** detonate a goo barrel. `Set Part HP` can target one now (Pass K), so it no longer needs
  a landed shot.
- **2026-07-31 (supervisor check — REOPENED from `Pending`).** Detonations are still not being seen. Note
  `BR51.21`: **no injection ever animates** — `_on_debug_panel_applied` never calls
  `ResolutionPlayer.play()`, so a debug-forced blast cannot draw on that path at all. Until that is
  settled, this entry can only be judged from a **shot-driven** detonation, which needs `BR51.01`.

- **2026-08-02 — RESOLVED on the owner's instruction.** The supervisor saw an explosion trigger
  naturally in play and directed closure: *"Also mark 35.08 as resolved."*
- **Recorded as owner-directed rather than CC-verified**, the same way `BR27.04` was closed in
  taskblock-51. CC never saw a sphere drawn and made no change targeting this entry in taskblock-52;
  what changed underneath it was taskblock-51's work — the detonation event moved to `DamageResolver`
  so one emitter serves both the shot-driven and the forced path, cover began taking the blast, and a
  mounted part began detonating at its own composed position.
- **What this does not close:** `BR51.21` (no injection ever animates) is untouched, so a
  *debug-forced* detonation still cannot draw on that path. This entry closed on a **shot-driven**
  blast, which is exactly the route its own last note said it would have to be judged from.

### BR55.02 — Resolved — owner: `CC`
**Floor tile geometry is wound inside out — backfaces are what the camera sees**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-08-04.
- The tile parts render with **inverted winding order**: the outward faces are culled and the interior
  faces are drawn, so a tile reads as transparent from above and textured from beneath. Backface
  culling doing its job against geometry built the wrong way round, not a material or shader fault.
- **Introduced with the tile parts themselves** (taskblock-55 Pass B), which is the only geometry
  built in that pass — so the winding is in whatever emits a tile's box, not in the shared box
  primitive every other part has used for fifty blocks without this.
- **Check whether the normals disagree with the winding**, not just the winding. A box built with
  reversed vertex order *and* correct normals lights properly while culling backwards, which looks like
  a culling setting and is not one.
- **Do not fix it by disabling backface culling.** That hides it, doubles the fragment cost of every
  tile, and leaves the geometry wrong for anything that later reads a normal — the wall cutout shader
  among them.

**CC analysis, `e5393c3a-bd26-4668-8905-c50cf31e04cb`** — read from source, no code touched.

- **It is `BoardView._add_box`, and nothing else.** It is called from exactly one place,
  `_build_tiles`, and it is the **only hand-wound geometry in the file**. Every other box on the
  board — blockers, cover, dropped assemblies, overlay markers, unit ghosts — is a Godot `BoxMesh`,
  correct by construction. That is why fifty blocks of parts never showed this and the tiles do: the
  shared box primitive was never involved, exactly as suspected above.
- **On "check whether the normals disagree with the winding": there are no normals to disagree.**
  `_add_quad` calls `surface_add_vertex` and nothing else, and there is no `surface_set_normal`
  anywhere in `board_view.gd`. So this is **not** the reversed-winding-with-correct-normals case —
  the mesh carries no normal data at all, and culling is decided by winding alone. Worth confirming
  against a built mesh's `ARRAY_NORMAL` before fixing, since that is an engine-behaviour claim
  rather than a source-level one.
- **The vertex order, so nobody has to re-derive it.** Corners are built x-major then y then z, so
  index = `4*x + 2*y + z` with 0 = negative: `0=(-,-,-) 1=(-,-,+) 2=(-,+,-) 3=(-,+,+) 4=(+,-,-)
  5=(+,-,+) 6=(+,+,-) 7=(+,+,+)`. The top face is emitted as `c[2], c[3], c[7], c[6]`.
- **Fix the doc comment in the same edit.** It asserts the quads are "wound counter-clockwise seen
  from outside the box, so back-face culling keeps the faces that face the camera." That sentence is
  the bug, written down as if it were true — a later reader who trusts it will look elsewhere.
- **Do not assume the engine's front-face convention; check it.** Assuming it is what produced this.
- **Why the tests did not catch it, which is the reusable part.** `test_no_risers.gd` asserts vertex
  *counts* and `test_board_view.gd` asserts an *AABB* — both are winding-blind, and geometry in the
  right place facing the wrong way satisfies every assertion written in Pass B. **A test that would
  catch it reads the built mesh back and asserts an outward direction** (the top face resolving to
  +Y), which is the "read the real node back, do not re-derive it" rule CLAUDE.md already sets for
  view math. It was applied to placement in that pass and not to orientation.

**`Resolved` (`CC`, 2026-08-03, taskblock-56 Pass A) — `4ec878cf-1434-4676-8bd3-05c92eed071a`.**

- **The fix is the six quads in `BoardView._add_box`, reversed, and nothing else.** Culling is not
  touched; no material changed; `_add_quad` is untouched because it is shared with
  `_build_grid_lines`, which was already correct and would have been flipped into the ground by a
  "fix" applied one level down.
- **The convention was measured, not assumed** — which the entry asked for explicitly. A real
  `BoxMesh` emits every one of its twelve triangles with `(b - a).cross(c - a)` pointing **into**
  the solid: its dot with the mesh's own stored outward normal is `-1` on all twelve. So a front
  face runs clockwise seen from outside, and `_add_box`'s top face — computing to `+Y` against an
  outward `+Y` — was the exact reverse. **All six faces were wrong, consistently**, not a subset.
- **On "check whether the normals disagree with the winding": confirmed against a built mesh.**
  `ImmediateMesh`'s `ARRAY_NORMAL` slot is empty for this surface — `_add_quad` calls
  `surface_add_vertex` only. So culling was decided by winding alone and there was no normal to
  light it correctly while it culled backwards. The engine-behaviour claim in the analysis above
  now rests on a read-back rather than on reasoning.
- **The doc comment that asserted the opposite is rewritten in the same edit**, as the analysis
  asked. It had claimed the quads were "wound counter-clockwise seen from outside the box" — the
  bug written down as truth.
- **The test is `test/unit/view/test_board_view_winding.gd`, and it was checked against the bug.**
  It reads a real `BoxMesh` back to establish the convention and requires the tile mesh to agree
  with *that*, so the rule is never restated from memory. Reverted onto the old winding it reports
  `12 of 12 tile faces wound inside out` and fails three assertions; on the fix it passes 4/4. It
  also pins the grid lines as up-facing, so the shared-helper mistake fails a test.
- **What is verified and what is not.** Verified: the emitted vertex order now matches the
  primitive every other box on the board is built from. Not verified: that the board *looks* right
  — CC has no rasteriser and a headless run culls nothing. The supervisor seeing a tile from above
  is still the only confirmation of the symptom as reported.
- **Why the existing tests missed it, kept because it is the reusable part.** `test_no_risers.gd`
  asserts vertex counts and `test_board_view.gd` asserts an AABB; geometry in the right place
  facing the wrong way satisfies both. CLAUDE.md's "read the real node back, don't re-derive it"
  had been applied to placement and never to orientation.

### BR56.01 — Obsolete — owner: `SUPERVISOR`
**Navigability-repair ramps are stamped facing 45 degrees, across the corner of their own cell**
- **Source:** `SUPERVISOR`, 2026-08-04, observed in-game across several bouts ("ramps are generating
  rotated 45 degrees"), most clearly on `seed=339963260`.  ·  **CC session:**
  `8b76a838-a998-436a-9e35-b74c4927f811`
- **Confirmed, reproduced in isolation, and attributed to one of the two ramp-stamping paths.**

**The mechanism.** `MapGen` stamps ramps from two places, and only one of them restricts itself to
cardinal directions:
- `_stamp_ramp_pair` (the ordinary room ramp) takes its direction from `_outward_ring_direction`,
  which returns **only** N/S/E/W or `null`. Its own doc states the rule: *"a ramp only ever runs
  along a single N/S/E/W approach, never a corner graft (the same orthogonal-only posture
  `GridPlacement`'s own attachment grammar uses)."* These are always orthogonal.
- `_open_a_route_out` (taskblock-53 Pass D's navigability repair) iterates **`Grid.neighbors()`,
  which is 8-directional**, and hands whatever it picks to `_stamp_ramp`, which sets the facing to
  `atan2(direction.x, direction.y)`. A diagonal neighbour therefore yields exactly ±45 or ±135
  degrees. **The repair path violates the orthogonal-only posture the other path documents.**

**The formula is not the defect.** `_stamp_ramp`'s inline `atan2(x, y)` is the same expression
`BodyProjector.orientation_for` computes, and both paths point up-slope, so the two agree on every
cardinal case. It is the *input* that differs — 8 neighbours against 4. (That the repair path
open-codes the expression instead of calling the shared helper is a separate, smaller smell.)

**Isolated reproduction**, a 5x5 plateau at 3.0 with one cell dropped to 1.0:
- Wall off all four orthogonal neighbours, leaving only a diagonal escape → `guarantee_navigability`
  stamps a ramp at `(2, 2)` facing **+45.0 deg**.
- Leave the orthogonals open (control, same code path) → **+90.0 deg**, orthogonal.

**Measured incidence — 20 of 44 ramp cells across the five seeds in `out/combat.log` are diagonal:**

| seed | ramp cells | orthogonal | diagonal |
|---|---|---|---|
| 339963260 (the reported bout) | 12 | 5 | **7** |
| 6930958 | 8 | 4 | **4** |
| 208111853 | 15 | 7 | **8** |
| 334004531 | 6 | 6 | 0 |
| 2 | 3 | 2 | **1** |

The orthogonal ones come in height pairs (0.25/0.75) — `_stamp_ramp_pair`'s inner/outer stamp. The
diagonal ones are mostly lone cells at the stranded cell's own height, which is `_stamp_ramp`'s
signature.

**Why no test caught it.** The repair is judged on navigability alone, and a diagonal ramp *is*
traversable — `Pathfinder.move_cost` treats an edge with a ramp at either end as ordinary movement,
so `MapNavigability.stranding_cells` comes back clean and the sweep stays green. **Nothing anywhere
asserts a ramp's facing.** The defect is visible only by looking at the board, which is what the
supervisor did.

**DO NOT FIX — supervisor instruction, 2026-08-04.** *"It's likely I'll make distinct ramp tiles
obsolete in the next pass, so don't try and fix it."* The entry stays `Active` because the defect is
real and confirmed, **not because it is waiting for someone to repair it**. If distinct ramp tiles do
go away, this closes as `Obsolete` (the code it describes was replaced, and nobody verified a fix) —
which is the supervisor's call to make, not CC's.

**Not yet decided, and moot if the above lands:** whether the fix is to restrict `_open_a_route_out`
to the four orthogonals, or to keep the diagonal candidate and stamp the ramp along the nearest
cardinal axis. The first is simpler and matches the stated posture; the second preserves repair
coverage in topologies where the only uphill neighbour really is diagonal (the isolated repro above
is exactly that case, and under the first option that pit would get a **ladder** or stay stranded).
**Either way it changes generated boards for every seed**, so the map corpus, the navigability sweep
and any recorded measurement taken against a current seed move with it — which is why this is filed
rather than patched in place.

- **`Obsolete` (2026-08-06, taskblock-60 Pass A) — the code this entry describes was deleted, and
  nobody verified a fix.** The supervisor authorised this closing status directly, over the
  owner-gate rule, with the standing note that they will reopen it if they meet the defect again.
- **What went.** `_open_a_route_out`'s ramp branch, `_stamp_ramp`, `MapGen.RAMP_MAX_RISE`,
  `_stamp_ramp_pair`, `_connect_with_a_ramp`, `MapGenScratch.CellKind.RAMP` and
  `Surface.is_ramp_at`. The generator authors stairs — ordinary `ship_floor` tiles at evenly
  spaced heights — and repairs stranded ground with ladders. **No generated surface carries a
  facing at all now**, which is what makes this unverifiable rather than fixed: the field the
  entry is about is no longer written.
- **The entry's own diagnosis survives as the reason the deletion was cheap.** It found that the
  repair path took its direction from an 8-way neighbour list while the room path used 4, and that
  `Surface.facing` never reached the pathfinder — so a ramp was already traversable from any
  direction and the facing was a visual field nothing read. A ladder is vertical and faces
  nothing, so the question the entry asks has no place left to be asked.
- **The two options it left undecided — restrict the repair to four orthogonals, or stamp along
  the nearest cardinal — are both moot.** Neither was taken; the branch that would have hosted
  them is gone.
- **Ramps do return later**, as `PLAN.md` says, but as a chassis property (a unit with no step
  height at all, needing a continuous slope) rather than as a labelled cell. That is a different
  entry when it happens.

### BR51.12 — Obsolete — owner: `SUPERVISOR`
**Ramps may generate on top of other ramps facing the other way**
- **Source:** `SUPERVISOR`  ·  **Found:** 2026-07-31, taskblock-51 fourth hunt.
- Reported as a suspicion rather than a confirmed defect: ramps appearing stacked on one cell facing
  opposite directions. **`Suspected` deliberately** — it has not been reproduced deliberately and no
  route back to it is recorded.
- Cheap to test headlessly once described: `MapGen` places ramps through `connect_with_a_ramp`, and
  "at most one correctly typed floor surface per cell" is already asserted by
  `test_map_gen.gd`. **If that test passes while this reproduces, the assertion is narrower than its
  name** — which is the more interesting finding of the two.

- **`Obsolete` (2026-08-06, taskblock-60 Pass A) — the subsystem this entry suspects was deleted,
  and the suspicion was never reproduced.** Supervisor-authorised closing status, same as
  `BR56.01`, with the same standing note that it reopens if the behaviour is met again.
- **Ramps can no longer generate at all, stacked or otherwise.** `MapGenScratch.CellKind.RAMP` is
  gone and `MapGenScratch.place_surface` authors exactly one part id, `ship_floor`, at one height
  — so "two ramps on one cell facing opposite ways" has no mechanism behind it.
- **The interesting half of the entry was answered rather than deleted, and the answer was that
  the assertion was too narrow.** Its own note said: if `test_map_gen.gd`'s "at most one correctly
  typed floor surface per cell" passes while this reproduces, the assertion is narrower than its
  name. That assertion turned out to be counting *every* surface at a cell rather than every
  *walkable* one — which is why a repair ladder sharing a cell with its floor made it fail the
  moment ladders became the only repair. It now counts walkable surfaces, which is what its name
  always claimed. **A cell still cannot hold two floors; it can hold a floor and a ladder, and
  always could.**

### BR52.13 — Obsolete — owner: `CC`
**Nothing penetrated anything across an entire battle**
- **cluster:** `shot-geometry`
- **Source:** `CC`  ·  **CC session:** `c0dfa479-2b43-4d9c-832d-12a7fd232bce`
- **Found:** 2026-08-02, while investigating `BR52.09`. **Not reported by the supervisor**, and filed
  `Suspected` rather than `Active` because it may be entirely by design — it is a measurement looking
  for a decision, not a described defect.
- **Measured** in `out/logs/combat-20260802-164344.log`: **78 `DEFLECT`, 78 `STOP_DEAD`, zero
  `PENETRATE`** across 156 impacts and nine full chaingun bursts.
- **The arithmetic explains it and may simply be correct.** `chaingun.tres` is `damage 2.0` with
  `damage_multiplier 0.8` — **1.6 effective** — against `steel.tres`'s `dt` of **6.0**. A chaingun
  round cannot penetrate steel, so every steel object on the board can only ever be worn down by
  accumulated `STOP_DEAD` damage. An anti-personnel weapon failing to punch armour plate is a
  reasonable thing for the model to say.
- **What makes it worth recording anyway:** `steel.tres` authors no `deflect_threshold_deg`, so it
  takes `MaterialEntry`'s **30.0** default, and a representative engagement in that battle sat at
  **~31 degrees** incidence — one degree over. Combined with a damage figure that can never penetrate,
  a shipped material is relying entirely on two unauthored defaults for its whole feel. **The numbers
  are not invented here and no tuning is proposed**; this exists so the first person to touch weapon
  or armour balance sees the measurement rather than rediscovering it.

- **`Obsolete` (`CC`, 2026-08-07, taskblock-60 follow-up) — re-measured, and it does not
  reproduce.** Closed as `Obsolete` rather than `Resolved` deliberately: **nobody fixed anything**,
  and `Resolved` would assert a verification that never happened. What changed is that the
  measurement this entry *is* has been superseded by a better one.
- **Six real AI bouts, six map seeds, driven headlessly through `BoutRunner` end to end:**

| outcome | impacts | share |
|---|---|---|
| `PENETRATE` | **380** | **15.5%** |
| `STOP_DEAD` | 820 | 33.5% |
| `DEFLECT` | 1250 | 51.0% |
| total | 2450 | |

- **Against the original figure of zero penetrations in 156 impacts.** The entry's own arithmetic
  is what explains both readings and neither is wrong: that battle was chaingun-versus-steel, a
  pairing that *cannot* penetrate (1.6 effective damage against a `dt` of 6.0), so a sample drawn
  from it reports zero by construction. A broader sample penetrates about one impact in six. **The
  model was never broken; the sample was narrow.**
- **The balance observation survives this closure and has been moved to `PLAN.md`** rather than
  archived with the entry: `steel.tres` authors no `deflect_threshold_deg` and therefore leans on
  `MaterialEntry`'s 30.0 default, and the engagement measured sat at ~31 degrees — one degree over.
  A shipped material resting its whole feel on an unauthored default is a real thing for the first
  person touching armour balance to see, and a closed bug entry is the wrong place to keep it.

### BR57.01 — Resolved — owner: `SUPERVISOR`
**Units stand at their previous bout's cells in editor mode**
- **cluster:** `pending-confirmation`
- **Source:** `SUPERVISOR`, 2026-08-05, observed in-game during the post-taskblock-57 UI review
  ("some units spawn in edit mode at the places they were in the last bout").  ·  **CC session:**
  `cb234571-515f-4b21-bfe1-1abb38912aa0`
- **Reproduced, root-caused, and fixed at the view. Marked `Pending` because the entry is
  `SUPERVISOR`-owned — CC may not close it.**

**The mechanism, and the returned value nobody read.** The editor mode installs over whatever bout
`BattleScene` has already built; `EditorModule._refresh_board` rebuilds the live grid from the
authored model on every edit and calls `BoardSwap.swap_board(state, grid, true)` to relocate the
units standing on it.

`swap_board` places each living unit on the first free spawn marker, or failing that the first free
walkable cell — and **returns the ids of the ones it could place nowhere.** `EditorModule`
discarded that return value. A stranded unit keeps `unit.cell` from the previous bout, and its
`HitVolumeView` is still in the tree, so it is drawn at that cell over the board being authored.

**Why "some".** It is every unit the authored board cannot seat, which is all of them on a board
with no floor yet and none once spawn markers exist — so the count changes as you author, which
reads as an intermittent fault rather than a deterministic one.

**The fix, and what it deliberately is not.** `_refresh_board` now hides the views of exactly the
stranded ids. **Hiding rather than relocating is not a design choice** — a stranded unit has no cell
on this board, so drawing it anywhere is the view asserting something untrue, which is the rule this
project has already applied to risers (`tb54 B1`) and the ground quad (`tb55 B`). The units
themselves are untouched, and `run_test_bout` relocates them onto the finished board down the
ordinary injector path, which is when they reappear.

**The real answer is upstream and is already queued.** An authoring session should not be carrying a
bout's units at all; that wants an entry point which builds a world without a bout, which is
`PLAN.md`'s *Main menu* item and is flagged as a known limit in `EditorModule`'s own header. This
makes the editor honest in the meantime rather than closing that gap.

**To see it work:** open the editor with a bout on screen (`E`). Before, the previous bout's units
stood on the empty grid; now no bout unit is drawn at all until *Run Test Bout* seats them.

**taskblock-59 follow-up: the fix above was the wrong half, and this entry stays `Pending` on the
stronger one.** Hiding the *stranded* units left the **seated** ones alone — and
`BoardSwap.swap_board` seats on the first free walkable cell, so the author's very first floor tile
put a bout unit on the board. Reported again as two defects (*"a random unit stuck around in the
editor from the prior map, a squad 0 unit 0"* and *"something is causing a cutout or culling sphere
on wall parts"*, both noted as coming and going as more was placed) — **one unit, both symptoms.**
`EditorModule._hide_bout_units` now draws **no** bout unit in the editor and excludes every one of
them from the wall cutout, which does not depend on what has been placed. Pinned by
`test_editor_isolation.gd`.
- **2026-08-07 (supervisor check via review session `HBPaR3`) — RESOLVED.** Confirmed in the editor.

### BR59.01 — Resolved — owner: `SUPERVISOR`
**A refused placement freezes the editor's board: everything placed afterwards is invisible**
- **cluster:** `pending-confirmation`
- **Source:** `SUPERVISOR`, 2026-08-06, observed in-game ("clicking a support pillar on top of
  another support pillar makes an invisible pillar. Other items trigger it too. After that,
  everything placed was invisible").  ·  **CC session:**
  `1f23a1e1-f577-43e7-b5d9-356cd12249f7`
- **Reproduced, root-caused and fixed. Marked `Pending` because the entry is `SUPERVISOR`-owned —
  CC may not close it.** `BR59.02` is the same defect from the other side and closes with it.

**One site, and it was not a rendering fault.** `EditorModule._refresh_board` rebuilt the live board
by asking `MapSerializer.to_grid` for the model, and **returned silently whenever the serializer
refused it.** The model kept accepting edits; the view stayed frozen at the last board that built.
So the invisible pillar was never the bug — it was the first symptom of a view that had stopped
tracking the model *and would never start again for the rest of the session.*

The function's own comment argued for that behaviour: *"a board that cannot be built is left
standing and reported, never half-applied... far more use than an empty grid."* **Both halves were
wrong.** Nothing reported it — the serializer's refusals were errors no author ever saw, and
`describe_problems`, which is the list the editor actually shows, has never had a word to say about
a duplicate blocker. And a stale board that keeps taking edits is not a conservative fallback; it is
the view lying about the model.

**Why a pillar.** `pillar` carries no `attaches_to`, so *Place Terrain* derives `KIND_BLOCKER` for
it, and `Grid.blockers` is one part per cell. "Other items trigger it too" is exactly right: every
blocker does, and so does any placement pushed out of bounds by a later board resize.

**Three changes, and the first is the structural one.**
- `MapSerializer.to_grid` gained a **lenient** mode: build every placement that can be drawn, return
  the rest as sentences. Strict is now *"lenient, and refuse at the first thing skipped"* — one
  traversal, one rule set, no branch that only one caller exercises. The editor renders leniently
  and the bout path stays strict, so a test bout still refuses a board it cannot build rather than
  playing a partial one.
- `EditorController.place` refuses a second blocker on a cell and says why, so the model cannot hold
  what the board has nowhere to put. **Deliberately narrow**: this is not the legality question the
  editor's *warn, never block* rule covers — a stack of surfaces, an unwalkable board and a pit all
  stay authorable and merely warned about. It is the line `MapSerializer` already drew for the load
  path.
- **The ghost was an accomplice.** Hovering a wall's top face previewed a wall stacked on it, which
  is not expressible at all, and `test_parts_list.gd`'s *"what appears is what the ghost showed"*
  acceptance passed throughout because it compared the ghost against the **model** and never against
  the board. The ghost now asks the same refusal the click asks and declines to draw what will not
  land.

**Stacking blockers vertically is a real capability and it is queued, not deleted** (`PLAN.md`). The
author's route to a taller wall in this block is Pass C's *Scale* drag, which is the right verb for
it.

**To see it work:** open the editor (`E`), place a pillar, click a second onto the same cell. Before,
the pillar vanished and nothing you placed after it ever appeared again. Now the click authors
nothing, the combat log says *"(x, y) already has a 'pillar' on it; a cell holds one blocker"*, no
ghost is offered for that face, and every subsequent placement draws normally.
- **2026-08-07 (supervisor check via review session `HBPaR3`) — RESOLVED.** Confirmed in the editor.

### BR59.02 — Resolved — owner: `SUPERVISOR`
**`Delete` removes the record but not the mesh**
- **cluster:** `pending-confirmation`
- **Source:** `SUPERVISOR`, 2026-08-06, observed in-game ("Delete removes logically but not
  visually").  ·  **CC session:** `1f23a1e1-f577-43e7-b5d9-356cd12249f7`
- **The same defect as `BR59.01`, seen from the other side, and fixed by the same change. Marked
  `Pending` because the entry is `SUPERVISOR`-owned.**

`BoardView.build` clears its own statics, so a delete on a healthy board has always removed the node
along with the record. What it could not do is run at all: **once the board was frozen, `refresh()`
reached `_refresh_board`, the serializer refused the model, and the redraw returned before drawing
anything** — so the record went and the mesh stayed. The sequence in the report is the ordinary one,
because an author who cannot see what they just placed reaches for delete next.

Filed as its own entry rather than folded into `BR59.01` because it was reported separately and
because the two would have to be re-derived as one otherwise. **A model and a view that can disagree
about what exists will keep producing symptoms in whichever direction is exercised next** — which is
why the fix is at the disagreement rather than at either symptom.

**To see it work:** with a board authored, place and then delete a pillar — the mesh goes with the
record. Then repeat the `BR59.01` sequence and delete afterwards; the delete now draws.
- **2026-08-07 (supervisor check via review session `HBPaR3`) — RESOLVED.** Confirmed in the editor.

### BR30.02 — Resolved — owner: `SUPERVISOR`
**Debug move_object mutates state but the model never visually moves**
- **cluster:** `view-model-membership`
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, live bout review), tested BEFORE BR30.01 (spawn) in the
  same session — so NOT explained by testing move against an already-invisible just-spawned unit (an
  earlier CC theory here, now known wrong; see BR30.01's own history). Both "Move On Next Click" and
  manual cell-entry Apply are reported affected. `unit.cell` genuinely changes (confirmed via inspect);
  the rendered model does not.
- **Status:** could not reproduce through any headless path tried so far — logged as a real negative
  result, not a fix. Built a REAL `BattleScene` + `SpectatorOverlay`/`SquadControlOverlay`, drove the
  debug panel's actual `_on_apply_pressed()`/`applied` signal for real, and read `HitVolumeView`
  transforms (both the root and a child marker) back per CLAUDE.md's own view-math rule, across three
  scenarios: a fresh bout, a bout after driving several real AI turns through the normal animated
  `ResolutionPlayer` path first (in case a stale cosmetic offset from a real animation was leaking into
  a later debug move), and through both overlays. In all three, `battle.refresh_unit_views()` (already
  wired to the panel's own `applied` signal) correctly rebuilt the moved unit's mesh at the new cell —
  no bug found in `move_object`, `HitVolumeView.refresh()`, `UnitGeometry`, or the `applied` signal
  wiring itself.
- **Needs a more specific repro before further guessing is worth the cost** (per tb30's own "don't loop
  within a block" instruction): does the status label read "Move Object: applied"? Is the camera
  actually framing the destination cell (a correct-but-off-screen move would look identical to "nothing
  happened" without a wrong transform)? Does re-selecting/re-inspecting the same unit afterward show it
  at the new cell in the 3D view specifically (not just the inspect panel's own text)? Exact steps
  (verb used, source/destination cells, which overlay) would let this become a matching headless
  fixture instead of a fourth guess.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here) — concrete asymmetry,
  confirmed:** in `debug_control_panel.gd`, the "Move On Next Click" path's own
  `_begin_move_on_next_click` (:349-363) explicitly snapshots the active object BEFORE arming the
  destination-cell picker, specifically to dodge a signal race (a comment at :344-348 explains why).
  But `_on_apply_pressed`'s OBJECT-param resolution (`_resolve_param`, :414-415) has NO equivalent
  snapshot — it reads whatever `_active` is live at Apply time. Since `_start_picking`'s one-shot
  listener (:371-379) shares the same `board_clicked` signal as the panel's always-on tracker
  (`_arm_active_tracking`, :185-192), clicking "Pick" on the destination CELL field can silently
  overwrite `_active` and swap out the intended unit object before Apply resolves it — explaining
  "data mutates, model doesn't move" without any bug in `move_object`/`HitVolumeView`/the `applied`
  signal itself. This would specifically explain the manual cell-entry Apply path IF the supervisor's
  own workflow used that field's "Pick" button rather than typing coordinates by hand. **Candidate fix
  (not yet applied):** give `_on_apply_pressed`'s OBJECT resolution the same snapshot-before-arming
  treatment `_begin_move_on_next_click` already uses.

**taskblock-61 Pass B — not hunted, on the taskblock's own instruction** (*"do not hunt an
unreproduced entry"*). Still unreproduced; three real-scene scenarios were tried in taskblock-30 and
nothing since has added a route back to it.

**What it needs is one observation, not more code reading.** The recorded candidate — that
`_on_apply_pressed`'s OBJECT resolution reads a live `_active` that the destination-cell picker can
overwrite — predicts the fault **only if the supervisor's own workflow used the cell field's "Pick"
button rather than typing coordinates.** That is a yes/no question about how it was driven, and it
decides whether the candidate is the cause or a second, unrelated race worth fixing on its own
merits.

**The owner cannot reproduce it either, 2026-08-07:** *"I can't reproduce this, move on next,
setting a cell manually, and picking a cell all work."* **All three routes verified working by the
reporter**, which is the observation the entry had been waiting on since taskblock-30 — and it
answers the recorded candidate too: the picker-overwrites-`_active` race predicted a failure on the
Pick route specifically, and the Pick route works.

**So nothing reproduces it on either side.** CC could not reproduce it across three real-scene
scenarios; the supervisor now cannot reproduce it across the three input routes. **This is the
owner's to close** — CC may not, and a closing status is not being guessed at here. The `_active`
snapshot asymmetry noted above is still a real race and worth fixing on its own merits, but it is
evidently not what was reported.

- **`Resolved` (`SUPERVISOR`, 2026-08-07) — closed on the owner's instruction.** *"You can mark
  that 30.02 as resolved and archive it."*
- **Recorded plainly: nothing was fixed, and no fix was verified.** It closes because **neither
  side can reproduce it** — CC failed across three real-scene scenarios in taskblock-30, and the
  reporter has since confirmed all three input routes (Move On Next Click, typing a cell, and
  picking a cell) work. `Resolved` is the owner's word for it and the owner's to give; this note
  exists so a later reader does not infer a repair that never happened.
- **The `_active` snapshot asymmetry noted above was never demonstrated to be the cause** — it
  predicted a failure on the Pick route specifically, and the Pick route works. It remains a real
  race and is worth fixing on its own merits, independently of this entry.

### BR32.04 — Resolved — owner: `SUPERVISOR`
**Clicking Resolve snaps the wall-cutout hole to the destination before the move animation catches up**
- **cluster:** `wall-cutout`
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (BR27.08 rebuild review). "On clicking resolve, cull position moves to the
  right cell immediately, while animation plays separately, splitting them."
- **Explicitly not investigated yet, by instruction — "likely a process change so just flag it for
  now."** Filed only so it isn't lost.
- **Candidate mechanism, not confirmed:** `resolve_to_marker()` resolves the queued prefix against real
  `CombatState` synchronously — `unit.cell` (and whatever `BoardView.update_wall_cutout()` projects
  from `wall_cutout_units`, a live reference into `combat_state.units`) updates the very next frame.
  The visual slide itself (`ResolutionPlayer`, driven off the `queue_partially_resolved`/`turn_ended`
  event stream) plays out separately, over multiple frames, from wherever the model's own
  `HitVolumeView` transform currently sits. If the wall-cutout shader's own per-frame feed
  (`BattleScene._process()`/`BoardView.update_wall_cutout()`) reads the unit's real, already-resolved
  `.cell` rather than the model's own currently-animated transform, the cutout hole would jump to the
  destination instantly while the model is still visibly sliding toward it — a real position, but the
  WRONG one to be reading from mid-animation. Consistent with the supervisor's own "likely a process
  change" guess: whichever `_process()` feeds the cutout's unit positions would need to read the
  animated/rendered position (or hold the old one) until the slide finishes, not the authoritative
  logical cell the instant it changes.
- **Not yet reproduced or fixed.** Needs a live look, not guessed at further here.
- **2026-07-23 (tb35 Pass D — the candidate mechanism confirmed exactly, still not fixed)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Read `ResolutionPlayer._play_slide`/`_set_slide_anchor`
  (`resolution_player.gd:312-350`) directly: a move's own tween mutates `view.position`/`view.basis`
  (the `HitVolumeView` node's real, currently-animating transform) every tween step, over the slide's
  own duration. `BoardView.update_wall_cutout()` never reads that node at all — it recomputes each
  unit's own screen position fresh from `UnitGeometry.bounding_sphere(unit).center`, which is built
  from `unit.cell`, the model's own already-resolved, instantaneous cell. So the candidate mechanism
  above is exactly right: the cutout jumps to the destination the instant `resolve_to_marker()`
  mutates state, while the SAME unit's own visible body is still several tween-frames from actually
  arriving there.
  - **Fix direction (not implemented — real architectural surface, not a one-line change):**
    `BoardView` has no visibility into `HitVolumeView`'s own current transform at all today (only
    `BattleScene` holds `unit_views`); `update_wall_cutout()` needs to read the unit's own CURRENTLY
    RENDERED position (docs/00's own "read the real node back, don't re-derive it" rule, applied here)
    rather than recomputing from the logical model whenever an animation is in flight. The cleanest
    shape found by reading the code: a `Dictionary[int, Vector3]` of "current display position per
    unit," written by `_set_slide_anchor` every tween tick (it already computes the exact anchor
    needed) and consulted by `update_wall_cutout()` before falling back to the logical
    `bounding_sphere` position for a unit that isn't mid-animation. Not implemented this pass —
    correctly scoping the override's own lifecycle (when it's cleared, so a stale display position
    can't itself become a new staleness bug) wants its own careful pass, not a rushed one at the tail
    of an already-long taskblock.

- **2026-08-09 (taskblock-61 Pass C1 — fixed; `Pending`)** [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`].
  **The tb35 diagnosis was exactly right and its recorded fix shape is no longer the cheapest one.**
  That note proposed a `Dictionary[int, Vector3]` of display positions written by `_set_slide_anchor`
  every tween tick, and flagged the **override lifecycle** — when it is cleared, so a stale display
  position does not itself become a new staleness bug — as the reason it was not attempted.
  - **There is no lifecycle to manage, because the node already holds the answer.**
    `ResolutionPlayer._apply_display_transform` writes the real `HitVolumeView.position`/`basis` on
    every tween tick and leaves both at **identity** whenever nothing is animating. So
    `view.global_transform * logical_point` is the rendered position at all times, with nothing
    cached and nothing to invalidate — `docs/00`'s *"read the real node back, don't re-derive it"*
    applied literally, which is what the tb35 note itself argued for.
  - **`BoardView.wall_cutout_views` is a display-position source and explicitly not a membership
    one.** `wall_cutout_units` still decides who gets a cutout; a unit with no view falls back to
    its logical position, which is the pre-fix behaviour. An out-of-date entry therefore cannot
    remove a cutout or invent one — the worst it can do is draw the hole where the body already is.
    That asymmetry is deliberate, given `BR32.01`/`BR32.03` were both stale-feed defects.
  - **The array is shared with `BattleScene.unit_views`, not copied**, so units spawned later
    through `sync_unit_views()` are covered. Pinned by its own test, because a typed-array mismatch
    would have copied silently and brought this bug back for exactly the units nobody re-checks.
  - **Sample points are transformed individually, not the AABB.** A yaw-rotated AABB has to be
    re-enclosed and grows; three points transform exactly.
  - **Test fails without the fix**, and carries a sanity assertion that the at-rest and mid-slide
    screen positions genuinely differ (they were identical before, by 0.0).
  - **To see it:** queue a move of several cells and click Resolve. The porthole should travel with
    the body across the whole slide instead of appearing at the destination immediately. **A hole
    that leads the body, or one that no longer appears at all mid-move, is the regression.**
  - **The same defect exists next door and is filed as `BR61.05`, not fixed here** —
    `BattleScene._occluding_friendlies` reads logical positions for the friendly-fade ghost. Left
    alone deliberately so this entry can be verified on its own.
- **2026-08-09 — `Resolved` on the supervisor's own instruction** (*"all the 32. entries can be
  marked as resolved"*), after seeing the fix in a live session. Fixed by `1a1476c` (taskblock-61
  Pass C2): the cutout reads each body's **rendered** `HitVolumeView` transform instead of its
  already-resolved logical cell. [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]


### BR32.05 — Resolved — owner: `SUPERVISOR`
**Wall cutout cuts walls that aren't between camera and unit (coarse heuristic)**
- **cluster:** `wall-cutout`
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). The cutout shape mostly works, but the *shape* is wrong at
  the edges: looking at a unit with a wall **behind** them, a chunk is cut out of the top of that wall
  even though it's ordered behind the unit; and the cut exposes the interior (wall-to-wall) textures
  of each wall.
- **This is BR32.02's explicitly-deferred facet, now the supervisor's review item.** BR32.02 fixed the
  depth *source* so the cutout appears at all; this is the separate, deferred precision problem its
  report flagged: the shader's occlusion test is a coarse single-scalar heuristic — "fragment nearer
  the camera than the unit's reference depth AND within its screen-space radius" — with **no real 3D
  ray / line-of-sight check** against the camera-to-unit line. A wall merely *near* a unit (adjacent,
  or behind but close) satisfies both conditions by geometric coincidence, so walls that aren't
  actually occluding get cut. Same root as the same-side over-cutting BR32.02 deferred (multiple
  adjacent walls cut at once in a corridor).
- **2026-08-05 (tb58 Pass C) — noted, not fixed.** [CC `5b7ef20b-5059-45dd-bc08-da8dc537ad93`]
  The first candidate fix below asks for a real ray/line-segment test against the camera-to-unit line.
  A CPU one now exists (`RayCaster.obstructed`), which does **not** help a per-fragment shader test
  but does make a per-unit CPU pre-pass possible — cut only the walls a real ray from the camera to
  that unit actually meets, and hand the shader a shorter list. **A note about what became available,
  not a proposal**: the shape of the fix is still the supervisor's call.
- **Candidate fixes (from BR32.02's own analysis, not yet chosen):** a real per-fragment ray/line-
  segment test against the camera-to-unit line, or gate on the *angle* between camera→wall and
  camera→unit rather than screen-space pixel distance + a bare depth compare.
- **Interior-texture exposure** is a sub-symptom (the cut reveals unlit/placeholder wall interiors);
  it may largely resolve once the shape is corrected, and is otherwise shader-pass polish, not worth
  chasing separately before then.
- **2026-07-25 (tb40 Pass C — elevation diagnosis, reasoned from shader source, not run; no fix, per
  the pass's own scope)** [CC d0685fa0-63d7-4f3e-b29b-f52886a5e0bc]. Read `wall_cutout.gdshader`'s
  `fragment()` and `BoardView.update_wall_cutout`/`WallLegibility.pixel_radius_for_tiles` end to end
  against two named cases (unit on level 3, wall at level 0 in front and below, genuinely occluding —
  should cut; unit on level 0, wall at level 3 behind them, occluding nothing — should not cut).
  **Same root cause as the rest of this entry — no real ray/line-of-sight test — but elevation opens a
  genuinely new way for the SAME coarse heuristic to misfire, not just a bigger blast radius on the
  existing same-side over-cut:**
  - **The depth gate (`frag_depth >= unit_depths[i]` → skip) is itself already elevation-correct.**
    Both sides of the compare are real 3D Euclidean distances (`length(view_pos.xyz)` reconstructed
    from the hardware depth buffer on the shader side; `camera_position.distance_to(bounding_sphere(
    unit).center)` on the GDScript side, and `bounding_sphere` already reads `unit.height` — real
    elevation, not a flattened ground-plane read). Nothing here assumes a flat map.
  - **Case 1 (should cut) is not newly broken by elevation.** A fragment that is genuinely ON the
    camera-to-unit ray projects, by definition, to very nearly the SAME screen position as the unit
    itself — screen-space proximity is not a flat-map assumption, it's true of any real 3D projection
    regardless of height. Reasoned through; no failure mode found here.
  - **Case 2 (should not cut) exposes a case the depth gate cannot catch once height varies.** On a
    flat map, "positioned behind the unit relative to the camera" and "farther from the camera in
    Euclidean distance" are the same condition, because everything sits near one shared height — so
    the depth gate has always doubled as a correct "is this wall really between camera and unit" proxy
    *for that reason*, not because it's a real occlusion test. Once a wall can be elevated far above a
    low unit, that equivalence breaks: a wall that is horizontally BEHIND the unit (farther along the
    ground-plane line from camera through unit) can still be Euclidean-NEARER to an elevated camera
    than the low unit is, purely because it sits closer to the camera's own altitude — geometry no
    flat map can produce. `frag_depth >= unit_depths[i]` then evaluates false (wall reads as nearer),
    the screen-space radius check is the only remaining gate, and `WallLegibility`'s own doc comment
    already concedes that gate was sized for "the tactical camera sits well above and back... a wall
    within N world units of that [camera-to-ground-unit] ray almost never fires" — a premise about
    where walls and units sit relative to the camera that elevation is specifically what breaks.
  - **Conclusion: do not open a new BUGS.md entry** — the fix (a real ray/line-of-sight test, or
    gating on the angle between camera→wall and camera→unit, both already named above as candidate
    fixes) is the same fix this entry already wants; elevation just adds one more concrete geometry
    that motivates it, worth having on record for whoever picks the candidate fixes.
- **taskblock-51 Pass A — elevation is not the variable.** The supervisor set cell levels to vary the
  vertical separation and the misbehaviour was unchanged, which rules out the "cannot distinguish
  vertical from horizontal separation" half of the suspected cause and leaves the screen-space
  heuristic itself.
- **Supervisor's proposed fix, recorded as theirs:** the cutout is a 2D projection taken at the camera
  angle; **tilt that projection to vertical and align it with the grid tiles** and the problem is
  bypassed rather than tuned. This is a different shape from taskblock-51's own suggestion of a ray or
  angle test in the shader, and it is cheaper — worth trying first.
- **taskblock-51 duplicate check — not a duplicate, but the cutout has been "fixed" three times
  already.** `BR31.03` (*wall fading never visibly occluded anything*, `Obsolete`), `BR32.01` (*stray
  hole at a cell with no unit*, `Resolved`) and `BR32.02` (*never visibly appears near real units*,
  `Resolved`) are all archived against this same shader path.
- **That history is the finding.** Three closures and the subsystem still misbehaves suggests the
  heuristic itself is the defect rather than each symptom — which is what the supervisor's own proposed
  fix says: stop projecting at the camera angle, tilt to vertical and align to grid tiles. **Check the
  archived three before starting**, so a fourth symptom-level fix is not attempted.

- **2026-08-09 (taskblock-61 Pass C1 — the supervisor's own gate, built and measured; `Pending`)**
  [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]. **The fix shape is the supervisor's, and it is not the per-wall
  pre-pass CC proposed:** *"If a wall is detected between the camera and the unit, then continue
  doing what we're doing already, and if no wall is detected, then disable the cutout for that
  unit. One check to get the wanted behavior."* Per-unit, not per-wall — so **the shader is
  untouched**, and the change is a gate in front of the existing screen-space heuristic rather
  than a fourth attempt to tune it.
  - **What it deletes.** `wall_cutout.gdshader`'s own header has recorded the still-open symptom
    since tb32: *"with the camera and unit on the SAME side of a wall (nothing should occlude at
    all), the cutout still fires and over-cuts neighboring wall segments."* A unit with nothing
    between it and the camera is no longer fed to the shader at all, so that over-cut has nothing
    left to happen to.
  - **What it does NOT delete, and this is what to look for.** Once *one* wall genuinely occludes
    a unit, that unit is fed exactly as before and the per-fragment screen-space test still
    decides alone — so a second wall near it, nearer the camera, can still take a bite. This
    entry's own *"a chunk is cut out of the top of that wall behind them"* therefore disappears
    when nothing is occluding and survives when something is. The residual wants the per-wall-cell
    version; it is deliberately not attempted in the same change, on this entry's own reasoning
    that the subsystem has been "fixed" three times and a fourth simultaneous change would make
    the result unreadable.
  - **Implementation:** `WallLegibility.cuts_for`/`sight_blocked_to_unit` (pure logic, headless),
    called from `BoardView.update_wall_cutout`. Three rays per unit — the body AABB's centre and
    its top and bottom face centres — and *any* one blocked keeps the cutout, deliberately biased:
    a false "nothing is occluding" switches the hole off exactly when it is needed, and a single
    centre ray misses a wall that hides only the legs. Blockers only, not floors: only walls carry
    the cutout material, so a catwalk overhead is not something cutting a wall can help with.
  - **`taskblock-61`'s own premise for this entry was wrong and the ledger was right.** The
    taskblock says *"vertical separation is exactly what a screen radius cannot distinguish from
    horizontal, which is why elevation makes it worse."* taskblock-51 Pass A already recorded the
    supervisor varying cell levels with the misbehaviour unchanged. Worked from the measurement,
    not the premise.
  - **A cost assumption CC shipped and then disproved with its own probe.** The first version
    walked all 217 blockers of a real 32x24 board per ray: **629 usec per unit, 10.07 ms a frame
    for a 16-unit roster** — a framerate defect manufactured by a correctness fix, on a `_process`
    path. `PartPicker.SKIP_RADIUS` is 3.0 and deliberately generous, so the cheap ground-plane
    reject admits a six-cell-wide strip of the whole board and every blocker gets iterated anyway.
    Filtering candidates through `Grid.line`'s supercover walk first: **41.2 usec per unit, 0.66 ms
    a frame** — 15x. Pinned by `test_cutout_gate_cost_probe.gd`, which asserts the ratio rather
    than a wall-clock bound.
  - **To see it:** put a unit in the open with walls nearby but none between it and the camera, and
    orbit. No wall should take a bite. Then step the same unit behind a wall — the porthole must
    still appear, unchanged from before. **If a unit behind a wall now gets NO cutout, the gate is
    inverted or too strict, and that is the regression to report.**

- **2026-08-09 (taskblock-61 Pass C1 follow-up — the gate shipped as a framerate regression, and
  the supervisor caught it in one session)** [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]. **Reported: FPS
  swinging 160 -> 13, "hard to tell if it's just while panning/rotating the camera, or always."**
  The combat log answers the second half: rolling-2s FPS sat at 122-146 during stretches with no
  `wall_cutout` lines at all and fell to 30-58 during stretches logging one line every 2.5 frames.
  Cutout log lines are emitted on change, so that is camera movement.
  - **The cause was CC's own probe measuring the wrong thing.** `test_cutout_gate_cost_probe.gd`
    reported 41 usec per unit against a fixture body of **one `Box`**. A real assembled shell
    (`combat_tester_chaingun`) is **48 boxes**, and `placements_aabb` costs eight corner transforms
    per box — so the fixture measured nothing that mattered. This is the same failure the
    taskblock-61 report already names as the block's lesson: a component measured headlessly is not
    the system.
  - **Measured end-to-end afterwards** (`test_cutout_feed_cost_probe.gd`, real board, real shells,
    real `Camera3D`, 16-unit roster), as usec per frame of `BoardView.update_wall_cutout`:
    **3 020 before the gate existed -> 5 281 as shipped -> 4 796 -> 3 613**. Two fixes: the feed was
    walking each body's geometry **twice** per frame (`bounding_sphere` for the fed position and
    again for the gate's sample points — now one `UnitGeometry.bounding_box` shared by both), and
    the gate's three rays each re-walked the supercover line (now one walk, all three points tested
    per candidate cell, sharing the per-cell lookup and the `assembly_placements` allocation).
  - **Residual: the gate costs ~617 usec a frame for 16 units**, against a measured floor of
    **3 114** for the body geometry alone. Pinned as a ratio rather than a wall-clock bound.
  - **The floor is a separate, pre-existing defect and is filed as `BR61.04`** — not caused here,
    and the larger of the two numbers.

- **2026-08-09 (taskblock-61 Pass C1 follow-up 2 — the zoom report, reproduced against and NOT
  confirmed; diagnostic added instead)** [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]. **Supervisor:**
  *"the cutout is still showing if far away, but is no longer cutting when close to the unit when
  there is no wall between camera and unit"*, disambiguated by them as **camera** distance: same
  unit, nothing between, correct zoomed in and wrong zoomed out.
  - **CC could not reproduce a gate that invents occlusion**
    (`test_cutout_gate_over_zoom.gd`). A board with **no blockers at all** and a board with a wall
    nine cells off the line both answer "clear" at every zoom from 3 to 30. Whatever is happening,
    the gate is not manufacturing geometry.
  - **What zoom actually changes is the angle, and it is not monotonic.** The camera orbits a
    **pivot**, not the unit, so pulling back walks it *over* a unit on its own side of that pivot:
    measured **5.6 degrees down at zoom 3, 83.6 at zoom 12, 46.2 at zoom 30**. The consequence is
    the supercover line length — **2 cells at zoom 3-6, 22 at zoom 30**. Zoomed in the camera is
    nearly overhead and almost nothing *can* be between; zoomed out the view is oblique and walls
    genuinely are. **This is a real mechanism for the reported behaviour that does not require a
    bug**, which is exactly why it should not be "fixed" on a theory.
  - **The three-point sampling bias was the prime suspect and was ruled out.** On a real generated
    board the **centre** ray is blocked every time the gate fires — it is never the feet ray alone
    keeping a plainly-visible unit's cutout alive.
  - **So the diagnostic was built rather than a fix.** `WallLegibility.blocking_cell` returns the
    **cell** it found rather than a bool, and the cutout log line now carries `blocked_by` — one
    cell per fed unit. **To settle this:** zoom out until the cutout appears with nothing that
    looks like it should be occluding, then read the `wall cutout: ... blocked by cells [...]` line
    and check whether that cell is genuinely between the camera and that unit. If it is, the gate
    is right and the visible defect is the residual per-fragment half of this entry; if it is not,
    the cell names the bug.
  - `BoardView`'s cutout logging moved to `src/debug/cutout_log.gd` to make room — the file was at
    `gdlint`'s 1000-line cap, and emission policy is a combat-log concern rather than a
    board-geometry one.

- **2026-08-09 (taskblock-61 Pass C1 follow-up 3 — cover no longer counts as occluding)**
  [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]. **Supervisor:** *"it looks like cover items are blocking
  the 'is this unit obscured' ray. Only things with the cutout related tag should be detected by
  that."* Correct, and it overrules a call CC made deliberately and wrote down: *"non-wall blockers
  (cover) still count, deliberately: the safe direction is keeping a cutout."* **That reasoning was
  wrong** — a cutout kept alive over geometry that can never be cut is not a safe answer, it is a
  hole with no visible cause.
  - **`MapGen` places six cover types as blockers** — `scrap_pile`, `goo_barrel`, `crate`,
    `pillar`, `forklift`, `barrel_pallet` — and every one of them is drawn with
    `WorldPalette.lit_material`, never the cutout material. None can ever be cut.
  - **There was no cutout tag; `BoardView` decided with `part.id == &"wall"`.** That is content
    identity hardcoded in code, which CLAUDE.md forbids outright, and it meant a second cuttable
    terrain type would need a code edit. Fixed at the same time rather than worked around: a
    `&"cutout"` tag authored on `wall.tres`, spelled once as `WallLegibility.CUTOUT_TAG`, read by
    **both** the material assignment and the sight gate. What is drawn cuttable and what counts as
    occluding are now the same authored fact and cannot drift.
  - **The tag name is CC's and is a data-plus-one-constant rename** if the supervisor wants a
    different word.
  - `RayCaster.blocker_obstructed_among` gained a `required_tag` filter, defaulting to no filter —
    the vocabulary stays with the caller, the same way `exclude_parts` already states membership
    without that function having an opinion about why.
  - **Pinned by three tests, not one:** cover between camera and unit does *not* keep the cutout
    (with a sanity assertion that the pillar genuinely IS in the way, so the test is about what
    counts rather than about what hits); a tagged wall still does; and a part with an id nobody
    wrote code for, carrying the tag, occludes like a wall — which is the "addable as data, no code
    edit" rule made checkable.
  - **Not changed, deliberately:** `BoardView`'s build-step counter still splits walls from cover on
    `blocker.id == &"wall"`, and `AsciiRender` still picks its wall glyph the same way. Those ask
    what the map is made of, not what the cutout may cut, and quietly changing a diagnostic's
    meaning is worse than leaving two different questions answered two ways.
  - Cost unchanged within noise (686 usec a frame above the geometry floor, against 616 before);
    the filter removes candidates, it does not add work.
- **2026-08-09 — `Resolved` on the supervisor's own instruction** (*"all the 32. entries can be
  marked as resolved"*), after seeing it in a live session (*"looks much better"*). Fixed across
  `5416d2b` (the per-unit sight gate, the supervisor's own fix shape), `b362954` (the framerate
  regression that gate shipped with), `608424e` (the `blocked_by` diagnostic) and `48a9e39` (the
  `cutout` tag, so cover stops counting as occluding). **The residual per-fragment half named in
  this entry — a second wall nearer the camera taking a bite while a first genuinely occludes — was
  never fixed and is closed with it.** [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]


### BR32.08 — Resolved — owner: `SUPERVISOR`
**Dead or knocked-out shells may have strange cutout behavior**
- **cluster:** `wall-cutout`
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). Not observed directly — flagged as a likely edge case: a
  dead or knocked-out shell may feed or interact with the wall-cutout oddly (still in
  `CombatState.units`? still fed to the cutout? faded as a friendly? left with a stale cell like
  BR32.01?).
- **Suspected, not confirmed** — logged so it isn't lost; confirm/describe at a review pass. Shares
  the unit-feed edge-case family with BR32.01 (extracted/removed) and BR32.03 (carryover).
- **taskblock-51 Pass A — did not reproduce, and the attempt is recorded rather than the conclusion.**
  The supervisor fired shots near a dead body in the spectator view and saw **no obvious cutout
  behaviour** around it. That is not a clearance: this entry is `Suspected` precisely because the
  original observation was vague, and one session that did not see it does not establish it never
  happens. **What was tried:** shots resolving near a downed shell, watched from the spectator view.
  **What was not:** a shell downed *between* camera and a living unit, which is the geometry the
  cutout actually keys on.

- **2026-08-09 (taskblock-61 Pass C1 — confirmed, mechanism found, fixed; `Pending`)**
  [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]. **This entry's own original guess was exactly right** — it asked
  *"still in `CombatState.units`? still fed to the cutout?"* and both are yes. `CombatState.
  kill_unit` sets `alive = false` and **leaves the body in `units` forever** (only the grid
  occupant is cleared), and `BattleScene` feeds `wall_cutout_units = combat_state.units` whole.
  The cutout feed filtered on `extracted` and the debug exclusion and **never on `alive`**, so
  every dead or shut-down shell kept cutting its own full-radius hole in walls permanently. A long
  firefight progressively opened the level up, and nobody chose that — it fell out of the roster
  array outliving the unit.
  - **The supervisor's rule, and it maps onto a predicate that already existed:** *"I think the fix
    is disable the cutout for dead units. If it gets a turn, it gets a cutout, if not, then no
    cutout."* That is `CombatState._can_take_a_turn` (`alive and not shutdown`), already documented
    as *"the one place that actually excludes it"* — made public as `can_take_a_turn` and read by
    the cutout feed rather than a second copy of the same condition in the view.
  - **Downed units still cut, on the supervisor's explicit instruction:** *"downed needs cutouts
    though, because a downed unit may be only a turn from being back to normal."* `Unit.is_downed()`
    is "no matrix docked" — orthogonal to `alive`/`shutdown` — so this needed no extra condition;
    a downed unit is alive, still takes turns and still cuts. Pinned so nobody tidies it away
    (`test_board_view_occlusion.gd::test_update_wall_cutout_still_cuts_for_a_downed_unit`).
  - **`Suspected` -> `Pending`, not `Suspected` -> closed.** taskblock-51 Pass A's non-reproduction
    stands as recorded; what changed is that a concrete mechanism was found by reading the feed
    rather than by watching for the symptom. The geometry that pass named as untried — a shell
    downed *between* camera and a living unit — is still untried, and is a good thing to look at.
  - **To see it:** kill something and leave the body where walls stand between it and the camera.
    No hole should follow the corpse. Then check a downed (not dead) crew member still gets one.
- **2026-08-09 — `Resolved` on the supervisor's own instruction** (*"all the 32. entries can be
  marked as resolved"*), confirmed live: *"dead units are no longer cutting out, that looks good."*
  Fixed by `5416d2b` (taskblock-61 Pass C1) — the cutout feed reads `CombatState.can_take_a_turn`,
  so a corpse stops cutting and a downed unit keeps doing so. [CC `74ebb574-245b-48e8-aed2-e1d09ea25527`]

