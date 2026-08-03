# Taskblock 54 Report — Tiles, gaps, and sections

All five passes landed in order and are green. Suite at **2744 tests, 0 failures**. The block's
through-line — *only parts are real* — held: the riser deletion, the escape counter and the
section format all follow from it.

## Decisions made without asking

- **The `tile` sweep uses a non-letter boundary, not `\b`.** `\btiles?\b` treats `_` as a
  boundary, so it reported clean while `test_..._extraction_tiles` and `EXTRACTION_TILE_HEIGHT`
  plainly still contained the word — my first pass did exactly that and left a tail behind.
  Requiring a non-letter on each side catches those *and* gets every genuine substring right for
  free (`hostile`, `percentile`, `volatile`, `versatile`, `projectile`, `stiletto`), so the
  allowlist is one word rather than seven.
- **Two `build_step` log names changed** (`empty_tiles`/`extraction_tiles` → `..._cells`), so
  bout-build log output differs. The alternative was exempting log strings from the sweep, which
  would leave the word in the one place a human reads it.
- **`BR52.03` closed `Obsolete`, not `Resolved`.** The entry framed the fix as a decision —
  either the riser becomes a real `Surface` or it stops being drawn — and neither branch was
  taken as a repair. The feature was retired, and `Resolved` would claim a riser now behaves.
- **A section reuses `MapPlacement` and delegates placement to `MapSerializer`.** A section
  previewed alone genuinely is a tiny map; a second placement loop would be the first thing to
  drift. The cost is that `SectionSerializer` depends on `MapSerializer`, which I judged cheaper
  than two answers to one question.
- **`can_join` reads both edges and neither is the host.** The taskblock said to reuse the
  attachment grammar's *reasoning* and not assume the code fits, and this is where it does not:
  a part attaches *to* a host, but two sections are peers and either may refuse.
- **`BoardSwap` was extracted from `BoutInjector`.** Two verbs now replace the whole board and
  duplicated the relocation loop; the file was also over its 1000-line lint cap. Splitting the
  "where does this unit stand now" question out was the smaller change than shortening prose.
- **The authored sections open on rows 1–2 of 4, not the whole side.** An empty `openings` list
  means "the whole side", so two whole-side edges would match without the opening comparison ever
  executing — the fixture would have passed while proving less.
- **`Sealed Bay` is the same size and shape as the section that joins.** A refusal that only
  happened between obviously-different sections would not show that the *edge metadata* carries
  the decision.

## Tests that failed, then were corrected

1. **The two vocabulary guards failed each other.** My new guard's doc comment named taskblock-40's
   guard and its retired word, which that guard scans for — correctly, since the word really was
   sitting in a scanned file. Reworded rather than adding a second exemption: exempting files is
   how a sweep quietly stops sweeping.
2. **A free-step threshold I added was wrong and was reverted.** Making a sub-level rise cost
   ordinary movement contradicted *"partial MP costs round up"*, a settled `PLAN.md` decision
   pinned by `test_pathfinder.gd` — a 0.3 rise costs `ceil(4.0 × 0.3) = 2`, cheap rather than
   free. **The failing test was right and my change was not**; I should not invent a movement rule
   against a settled call.
3. **A reproducibility test compared two empty transcripts** and would have passed. A sanity
   assertion caught it. The cause was `MoveAction`'s path convention — a path **includes the
   starting cell** — which I diagnosed twice, first wrongly as the fixture lacking legs.
4. **The riser test almost measured nothing.** Counting vertices on one terraced board proves
   little; comparing a terraced board against a flat board of the same size is what makes "no
   geometry was added" the assertion. Both come back 96.
5. **My `describe_problems` first rejected a section with no walkable surface**, inheriting the
   map rule. That is precisely the edge-piece case the taskblock says the format must accept, and
   a test now asserts the contrast in both directions.

## Open questions

- **A 0.3 lip is impassable to every unit that exists.** Any upward rise is capability-gated and
  no shipped part carries a climbing tag. taskblock-53 answered this at the generator level (a map
  owes a route), so it is not a defect — but it means "standable" and "reachable" are different
  properties of a small step, and a collapse that leaves one will strand things.
- **Raised floors now read as floating slabs.** Expected and recorded, not a regression: filling a
  step's side is authored content and there is nothing to author it into until sections are placed
  by a generator. It will look wrong in the meantime.
- **Nothing decides whether an assembled board is navigable.** `can_join` decides whether a *seam*
  is legal; the asymmetric flood is still the only navigability check and the generator will owe
  it exactly as `MapGen` does.
- **A single shot emits no fire event at all, and that is a hole in `docs/09`'s own rule.**
  Found while investigating `BR54.01`: **`BurstAction` is the only firing path that announces
  itself** (`burst_fired`). `AttackAction`, `StabAction`, `SlashAction`, `GrindAction`,
  `Suppression` and `Overwatch` all resolve shots and emit **impacts only** — so a shot that
  strikes nothing leaves a bare `miss`, and a sniper firing is indistinguishable in the log from
  a sniper doing nothing until something is hit. Every sniper and shotgun shot in `BR54.01` had
  to be **inferred from its impacts**, which is why characterising that bug took measuring rather
  than reading. *"If it changed the world, it's in the log"* — firing changes the world.

  **The supervisor's shape for the fix, recorded rather than built:** a `single_shot_fired` event
  plus a **framework the other firing methods tag into**, so a new way of putting a round in the
  air announces itself by construction rather than by whoever adds it remembering. `burst_fired`
  becomes one member of that vocabulary rather than the exception that happens to have one.
  Queued in `PLAN.md`.

- **The escape counter has a first baseline: 182 across a full suite run** (2744 tests, 61 bouts).
  That is a whole-suite figure and not a per-board one, so it is a starting point rather than a
  verdict — the number becomes useful the moment there is a section library to compare boards
  against. Worth noting the counter was collected but **not printed** until the very end of the
  block; a counter nobody prints is one nobody reads, which was the point of adding it.
