# Taskblock 64 — A bout that produces gunfire

*Closes `BR63.04`, `BR63.05`, `BR63.01`, `BR63.02`, `BR63.03`, and the reopened `BR61.07`. Depends on
taskblock-63.*

**No bout currently produces a shot.** Two played bouts after taskblock-63 — one all-chaingun roster,
one mixed — fired **zero rounds** with units at point-blank range. That is not a bug list; it is the
game not working.

**Two independent defects, and neither fix produces a working bout alone.** Fix the chaingun and units
still cannot find each other; fix sight and chaingun rosters stay silent. **So they land together, and
the acceptance is a played bout that resolves by combat** — not a log line, not a green suite.

**The suite fired 481 rounds during taskblock-63's own gate while both of these were live.** That is
the block's most important finding and Pass D exists for it.

---

# PASS A — Measure the blindness. Fix nothing.

**The failure is proven at decision time.** An `ELITE` unit chose **`roam`** — whose preconditions
require `enemy_unknown` — with an enemy **two cells away**. Two `MINDLESS` units chose
`seek_extraction` at one cell. The path is `_nearest_known_enemy` → `WorldView.units_visible_to` →
`_has_direct_sight` → `LoS.has_los` → `RayCaster.obstructed`: **a sight failure feeding the planner,
not a firing failure.**

**Do not fix anything in this pass.** The geometry may be *correct* — a wall between two levels
arguably should span them — in which case the defect is in what occlusion reads, not in what the
generator builds. **A measurement taken after a fix is written cannot say that.**

## A1. The two-cell fixture first

**The one-cell case narrows sharply and does not need a board.** `_has_direct_sight` is *only*
`LoS.has_los` — no range, no arc, no tier gate — and `has_los` **exempts every part standing at either
endpoint cell**. So between two orthogonally adjacent cells at the same floor height, with a horizontal
ray at `SIGHT_HEIGHT` between their centres, **nothing on that line can block it.**

Which leaves exactly four candidates:

1. The cells were at **different heights**, so the ray slants and clips a neighbour's box.
2. **`_endpoints` is not exempting what it should.**
3. **`RayCaster.obstructed` reports geometry not on the line.**
4. The units were **not where the log says** at decision time.

**Build two adjacent floored cells, a unit on each, and walk the matrix**: wall/no wall in each
neighbouring cell, same/different floor height, blocker present at each endpoint. **Minutes, headless,
and it either names the cause or proves it is systemic.**

## A2. The seed sweep, only if A1 does not reproduce

Build seed `642296523` at 40x30 on the current tree and at `316edc5` (the last commit before Pass D),
and for every pair of cells within 3 of each other ask `LoS.has_los`. Report:

- how many pairs changed answer, and in which direction;
- for each newly-blocked pair, the wall cells on the line with their `Blocker.height` and box extent;
- the same sweep with `_stand_wall` reverted to a bare `place_blocker(cell, part)`, to isolate it.

**The standing hypothesis, unverified:** Pass D2's `_stand_wall` places a wall at the lowest
neighbouring floor and *sizes* it to clear the highest, so with `TALL_ROOM_LEVEL = 4` a wall can be
**6.4 tall where it was 2.4**. Occlusion now reads `blocker_height_for_cell` rather than
`true_height_for_cell`, so lines that used to pass over a short wall hit a tall one. **It does not
explain one cell**, which is why A1 comes first.

**TESTS:** the fixture itself is the deliverable, committed and rerunnable. **Whatever A finds gets a
test that fails on the current tree before B fixes it.**

---

# PASS B — Fix what A found

Held separate on purpose: **a fix written before the measurement will bend the measurement to fit it.**

**One thing to decide with the fix rather than after:** if the wall geometry is correct and occlusion is
reading the wrong height, then the fix is in `RayCaster` / `SightSpans`, not in `MapGen` — and that is a
better outcome, because reverting `_stand_wall` would reintroduce the walls-too-short defect it was
built for.

**The test written for that guarantees the failure rather than catching it.**
`test_no_generated_wall_is_shorter_than_the_floor_beside_it` asserts walls are *tall enough* and nothing
asserts the converse. **Add the converse**, whatever shape B takes.

**TESTS:** the A1 fixture passes; a wall between two levels still spans them (**do not fix this by
making walls short again**); a seeded bout's sight answers are reported before and after.

---

# PASS C — A chaingun unit can fire

**Four pieces compose into a dead end**, and the log signature is 10 of 10:

- `chaingun.tres` provides **`burst` only** — it cannot single-fire.
- `shoot.tres`'s preconditions **never ask whether the weapon provides `shoot`**.
- `suppress.tres` and `overwatch.tres` — the only actions with `executor_id = burst` — are gated
  `TRAINED`/`ELITE`.
- `UtilityContext._find_weapon_id` returns the first living part with `damage > 0` and **never consults
  `provides_actions`**.

So `shoot` wins the selection and `AttackAction.is_legal` refuses it on `provides_a_single_pull` —
**working exactly as designed**. `UtilityPlanner._commit` returns silently.

## C1. `burst` levels with `shoot`

**Nobody decided a grunt cannot fire an automatic weapon.** `docs/11`'s tier table places **`suppress`**
at Trained, meaning *suppressive fire is a trained tactic* — and `suppress` merely happens to be the
only burst-shaped action, so **a tactic gate has been acting as a weapon gate.**

**Add a plain `burst` utility action, tier-gated exactly as `shoot` is.** Pulling the trigger on an
automatic weapon is a **weapon property, not intelligence**.

**`suppress` is not an authored behaviour** — it was implemented from a line in a doc rather than
designed. **If it is in the way, bypass it.** It is a feature worth having later, so do not delete it
silently: if it moves or loosens, `SUPERSEDED.md` records what it was and why.

## C2. Two repairs that stand on their own merits

- **`_find_weapon_id` must not pick a weapon the planner cannot use.** A planner selecting an unusable
  weapon is a defect independent of anything else.
- **`shoot` must not be offered where the weapon cannot single-fire.** An action offered where it cannot
  execute makes the decision log show a choice that never existed. **This is what made the failure
  invisible** — the log reported a confident `shoot@(25,13)` and then nothing.

**Both are correct regardless of C1**, and with C1 a chaingun grunt has something to select instead of
nothing.

**TESTS:** a `GRUNT` with a chaingun selects and executes `burst`; `shoot` is not offered to a
burst-only weapon; `_find_weapon_id` skips a weapon providing no action the planner can use; a unit
carrying only an `arc_welder` is offered no firing action at all and **that is reported, not silent**.

---

# PASS D — The seam nothing tests

**No test crosses between what a generated bout arms and what the planner can offer.** Headless bouts
pick presets that provide `shoot`, and fired 481 rounds during taskblock-63's full gate **on the exact
tree where an all-chaingun roster could not fire a single round.**

**That gap is worth more than either fix.**

- **For every preset in the library, every weapon it carries must have at least one utility action the
  preset's own tier can select and the executor will accept.** Not "a shot happened once" — the
  cross-product, asserted.
- **`combat_tester_chaingun.tres` is the only `GRUNT` preset**, and the chaingun the only weapon that
  does not provide `shoot`. **A library that cannot arm a unit it can also plan for is the defect
  class**, and one authored combination proved it.

**TESTS:** the cross-product above, enumerated from the library rather than from a list (**a hand-written
list goes stale the day a preset is added**); a deliberately broken preset — a weapon whose actions no
tier can reach — fails it.

---

# PASS E — A bout can be won by fighting

**Every AI measurement to date runs in a mode where *leaving* wins.** A squad that never fires can still
complete a mission, which is why 31 turns of silence read as a slow bout rather than a broken one.

**Three terminating conditions, and a team meeting any of them has lost:**

- **No living units.**
- **No units on the board** — the whole team fled or extracted.
- **No unit with a usable weapon** — nothing left that can contest.

**The third is the diagnostic.** Under it, `BR63.04` would have **ended the bout immediately as a
loss** instead of running silently to the turn cap. **The win condition is itself the instrument.**

**It must be reachable from the existing bout builder UI.** A mode the supervisor cannot select is a
mode that cannot be tested. **Deliberately minimal — a dropdown, nothing more** — because that surface
is marked for removal and this should not deepen the investment in it.

**Not "deathmatch".** The name overstates it: this is *a team that can no longer contest has lost*,
which is narrower and more useful.

**TESTS:** a team reduced to no usable weapon loses immediately; a team that extracts entirely loses
under this mode (**and still wins under extraction mode — the modes must not leak into each other**);
the mode round-trips through the bout builder.

---

# PASS F — The vertical routes, again

- **`BR63.01`** — a ladder generates for a **one-level rise**, and **both pieces are 2 units tall**.
  Each should be **1**, and **a short rise should generate the top piece only**. A bottom piece with
  nothing to climb is scenery pretending to be a route. Check the rise thresholds against `step_height`:
  a rise of 1 is above the default free step but well below anything wanting two pieces.
- **`BR63.02`** — the two ladder pieces are **visually indistinguishable**, and the one attached to a
  ship floor sits at a **strange offset** while the other is centred on its edge. **Likely the same
  placement-record work as `BR62.05`** — an offset that used to be implicit is now carried explicitly
  and one piece is not setting it.

**TESTS:** a one-level rise generates a single top piece; each ladder piece is 1 unit tall; both pieces
sit where their placement record says.

---

# PASS G — Two clocks, still disagreeing

- **`BR61.07` reopened, and the symptom inverted.** It was *too early* — the destroyed thing left the
  board before its tracer played. It is now **comically late**. **A fix that overshot rather than
  missed**: the removal moved from resolution time to playback time and now waits for something longer
  than the impact, plausibly the whole action's playback rather than the hit that caused it.
- **`BR54.02` is the same pairing from the other side** — a part vanishing before the tracer that
  destroyed it. **Whatever clock the teardown now reads, check that entry against it.**
- **`BR63.03`** — extracted units remain drawn on the board. Check whether they are also **targetable**
  and **still taking turns**, which would make it a gameplay defect rather than a drawing one.

**TESTS:** a destroyed part leaves the board when *its own impact* finishes playing — not before, not at
end of action; an extracted unit is gone from the board, from targeting, and from the turn order.

---

# When to stop and report

- **Pass A reproduces nothing in the fixture and nothing in the sweep.** Then the cause is neither the
  walls nor the geometry, and that is a finding worth stopping on.
- **The fix for A belongs in `MapGen` rather than in occlusion.** Reverting `_stand_wall` reintroduces
  the defect it was built for; say so before doing it.
- **Pass D's cross-product fails for combinations nobody has hit yet.** Report the list; do not fix a
  library-wide gap inside a repair block.

# Acceptance

- **A played bout produces gunfire, and can be won by fighting.**
- The blindness has a named cause with a test that failed before the fix.
- A `GRUNT` chaingun unit fires.
- Every preset's weapons have a reachable action, asserted from the library.
- A ladder for a one-level rise is one piece, one unit tall.
- Destroyed and extracted things leave the board when they should.

# Not this block's job

- **Framerate.** Eight entries, and the ledger header records why they sit.
- **`BR58.01`'s wall-clock budget** — three turns were lost to `panic: budget_aborted` this session and
  candidate counts reached 3150, so taskblock-63 may have made it bite harder. **Measure if it is free;
  do not fix it here.**
- **`BR35.02`** — held for the next hunt by the supervisor's own call.
- **The AI rework.** `suppress` being implemented from a doc line rather than designed is a symptom of
  it; this block bypasses, it does not redesign.
