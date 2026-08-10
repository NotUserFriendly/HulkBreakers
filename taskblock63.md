# Taskblock 63 — Finish what taskblock 62 exposed

*Closes `PLAN.md` NEXT 1–3, `BR62.02`, `BR62.03`, `BR62.04`, `BR62.05`, and gives `BR60.01` its repair.*

**Everything here was found by taskblock-62 and correctly declined mid-block.** Two are defects that
make the elevation work unusable, two make it unreadable in play, and one is a lint ceiling that has
twice been paid for out of documentation.

**Pass A goes first for a mechanical reason**, not an editorial one: three of the passes below add code
to files that already explain themselves, and a file crossing the cap mid-pass is how the cheapest thing
to cut becomes the explanation of why the code is as it is.

---

# PASS A — Raise the file-size cap to 2500

`gdlintrc:35` sets `max-file-lines: 1000`. **That is gdlint's default, not a considered project
choice** — it was inherited rather than decided, and this project overrides `max-returns` and
`max-public-methods` already.

**It has stopped doing its job.** It counts lines and cannot tell code from comments, and this project
deliberately carries its rules in doc comments (*carry the fact inline* is a standing convention). So
**the cap penalises exactly the files that explain themselves**, and `BR62.02` records it biting three
files in one block with **the cost coming out of documentation twice.**

- **`max-file-lines: 2500`.** One line.
- **`BR62.02` closes with it.**
- **Everything else gdlint does stays** — parse errors in ~6 s without launching Godot, builtin
  shadowing (which caught `los.gd`'s `range` parameter), naming, class-definition order, and the ability
  to validate a checkout with no Godot binary. **The tool is not the problem; the one rule was.**

**TESTS:** none beyond the gate passing. This is a config line.

---

# PASS B — A body's standing height derives from its legs

**This is why the first alternative leg was deleted rather than shipped.** `BodyAssembler` pins the
torso at the cell's floor and hangs the legs down from the torso's own `HIP` socket, so **a longer leg
puts its foot below the floor plane** instead of raising the hip. The socket transform lives on the
torso and is shared.

**Until this lands, no leg whose length differs from `leg.tres`'s can be authored at all** — which makes
it the gate on everything the step-height work was for.

- **The torso's height above the floor derives from the legs**, rather than the legs hanging from a
  fixed torso.
- **Matched legs only.** A unit with legs of *different* lengths needs somewhere to bend, and **there is
  nowhere** — `torso.tres` carries `HIP_L`/`HIP_R` sockets but no hip *segment*, and a leg has no knee.
  That is a part-tree addition and it belongs to `PLAN`'s *Legs must match* item, not here.
- **Author at least one alternative leg** and prove it stands correctly. A rule with no content
  exercising it is the shape that shipped `mangles_into` unread for sixty blocks.

**TESTS:** a shell with longer legs stands taller and its feet rest on the floor plane, not through it;
a shell with the default leg is unchanged (**pin this — it is a change to every existing unit's
assembly**); the hit volumes and the shot plane agree with the new standing height, since both read
`assembly_placements`.

---

# PASS C — The AI's distance flood runs the wrong way

`UtilityContext._path_cost_from_target` is a **forward flood rooted at the target**, so it answers
*"how far could the target walk to this cell"* — **not** *"how far must I walk to the target."*

**On symmetric ground the two agree and it has never mattered.** On one-way ground they disagree
exactly, and **a terraced map is made of one-way ground**: dropping off a shelf is cheap and climbing
back is not.

So `closes_distance` — the consideration that decides whether a candidate cell brings a unit nearer its
target — **is wrong precisely where elevation exists**, which is everywhere the last four blocks have
been working.

- **Flood from the mover, or reverse the edges.** taskblock-61 already hit the mirror of this:
  `Pathfinder._base_cost` refuses an occupied cell, so a reverse flood asking *which cells can reach
  where I stand* was gated on entering the asker's own cell. **Whatever shape is chosen, check it
  against that fix rather than rediscovering it.**
- **Report the behavioural delta.** `seeds_to_first_win` before and after, and whether the AI's chosen
  cell differs on terraced boards. A correctness fix that changes nothing observable is worth knowing
  about too.

**TESTS:** on a board with a one-way drop, the cost from a cell below to a target above is the **climb**
cost, not the drop cost; on flat ground the answer is unchanged (**assert both, since the flat case is
what has been passing all along**); a candidate that cannot reach the target at all is scored as such
rather than as near.

---

# PASS D — `BR60.01`'s repair, and a third generation height

## D1. Unreachable raised ground is detected and nothing fixes it

`BR60.01` records that generated maps can hold a large raised region reachable only by ladder — the
detection landed, the repair did not. **CC flagged this as needing a decision between three shapes.**
Pick one, state why, and build it.

**The invariant to satisfy is already written**: the asymmetric flood, judged against the **lowest step
height in play** rather than a constant.

## D2. A third fixed height

Generation currently offers **0 and +1**. **Add +4.** A tall shelf is what stresses the vertical work —
ladders, lifts, partial climbs, one-way awareness — and none of it has been exercised against a rise
that genuinely needs several turns.

## D3. And +4 exposes a blocker's missing placement record

**Walls are true parts and parts do carry full transforms — but a `Part` is a template, and the
transform lives in the placement *context*.** The three contexts are unequal:

| placement kind | context | carries |
|---|---|---|
| body part | the socket-tree walk | a full `Transform3D` |
| surface | `Surface(part, height, facing)` | height, facing |
| **blocker** | **a dictionary key** | **a cell, and nothing else** |

**Surfaces got their record in taskblock-38; blockers never got the equivalent.** `grid.blockers` is
`Dictionary[Vector2i, Part]`.

**And the fields already exist in the format.** `MapPlacement` carries `height`, `size`, `offset` and
`facing` — **`MapSerializer` drops all four**, loading with `grid.blockers[placement.cell] = part`
(`:169`) and saving from the cell and part id alone (`:57`). **It round-trips because both ends discard
the same fields**, so an authored wall at height 4.0 comes back at 0, silently. That is **`BR62.05`**,
and it is invisible today only because nothing authors a non-zero blocker height.

**So this is not a new capability.** It is:

- `Grid.blockers` holding a **placement record** rather than a bare `Part`.
- `MapSerializer` carrying the fields it already has, both directions.
- `board_view.gd:349` reading them.

**Then a wall following its neighbours up becomes authorable rather than a rule** — the generator places
a wall at the height its neighbours sit at, the same way it places anything else.

**Do not invent a second transform concept for blockers.** `MapPlacement` is the record; use it. A
parallel one is how the surface and blocker paths came to disagree in the first place.

**TESTS:** an authored blocker's height, size, offset and facing survive a save/load round trip
(**assert each field, since the current round trip passes by dropping both ways**); across a seed sweep
every generated map passes the asymmetric flood at the lowest step height present; a +4 region is
reachable; **no wall is shorter than the floor beside it** — assert the geometry, not the generator's
intent.

---

# PASS E — Make the vertical routes readable

Both fresh from your first play of taskblock-62's work.

- **`BR62.03` — ladders and mag lifts generate in the same cell.** taskblock-62 already fixed the
  neighbouring case, refusing to build a lift within one cell of an existing **pad**. **That refusal
  almost certainly does not know about ladders**, which would explain this exactly. Check before
  writing a new rule.
- **`BR62.04` — ladders are the same green as ship floor tiles**, so a route up reads as more floor.
  The floor green is a deliberate placeholder while tiles have no models; **the ladder inherited it
  rather than being given its own.**
- **There are now three vertical routes** — steps, ladders, lifts — and they probably want to read as a
  **family**, distinguishable from each other and from floor, rather than each picking a colour
  independently.
- **The mag lift's two surfaces should stack**, top plate hovering over the bottom one. Not two
  placements at unrelated heights — **the pad is visibly one object**, and the gap is what reads as the
  lift doing something. That also makes the pairing structural rather than inferred from proximity,
  which is what taskblock-62's cross-linked-chain failure came out of.

**TESTS:** no cell holds both a ladder and a lift pad; a lift's two surfaces are a paired placement
rather than two independent ones; the vertical-route colours are distinct from the floor colour and from
each other.

---

# When to stop and report

- **Pass B changes an existing unit's assembly.** It should not — the default leg's behaviour is pinned.
  A difference is a finding.
- **Pass C's fix changes nothing observable.** Worth reporting; a correctness fix with no behavioural
  delta on terraced boards would suggest the consideration is not weighted enough to matter.
- **Pass D3 turns out to need more than the placement record.** It is scoped as *carry fields that
  already exist*; if it grows into a new transform concept, stop — that is the parallel-systems shape.
  A +4 behind a flag is an acceptable landing.

# Acceptance

- The cap is 2500 and `BR62.02` is closed.
- A longer leg stands a unit taller with its feet on the floor.
- Distance-to-target is the mover's cost, not the target's.
- Every generated map passes the flood, and +4 exists.
- A ladder and a lift never share a cell, and neither reads as floor.

# Not this block's job

- **Leg mismatch, limping, crawling.** Needs a hip segment or a knee — neither exists — and it is close
  to inverse kinematics. Its own item.
- **The map-declaration fork** — whether a `MapFile` rolls chances at load. A decision, recorded, not
  work.
- **The aiming and camera rebuild.** Its own block, and better specced after `BR51.01`'s fix has been
  played with.
- **The fixture audit.** Its own block; it produces a list rather than fixes.
