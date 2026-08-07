# Taskblock 61 — The hunt

*Acts on taskblock-60's clustered ledger. 41 live entries; this block works about half of them
deliberately.*

**This block is expected to run out before the list does.** Work the clusters in order; whatever is
untouched passes to the next hunt. **Do not thin a cluster to fit** — a half-diagnosed cluster is worse
than an untouched one, because the next hunt inherits a partial theory it has to re-verify.

**Most entries are `SUPERVISOR`-owned.** Append findings and mark `Pending`; **close nothing** the
supervisor owns. The block's real output is a `Pending` digest — *here is what I think I fixed, please
confirm* — not a shorter ledger.

**Every fix needs a test that fails without it.** Seven blocks running, the story has been a check that
could not fail; a fix landing with no regression test leaves the same hole open.

**Read the cluster tags.** taskblock-60 Pass D sorted the ledger by cause. A cluster is a claim that
several entries share a mechanism — **and taskblock-60 Pass C disproved exactly that claim about seven
entries.** Test the grouping before trusting it.

---

# PASS A — Shot geometry, and the instrument nobody has read

**`BR51.01` · `BR52.07` · `BR54.01` · `BR52.10`**

**taskblock-60 Pass B built `weapon_used` specifically for these and nothing has read it yet.** Every
firing path now announces itself with origin, intended direction, the unit's own facing, and the
weapon. **Before Pass B, `BR54.01`'s 43-degree table had to be inferred from impacts.**

**Read the log before forming a theory.** Three of these are angle complaints — wide left, 90 degrees
off, 43 degrees off facing — and they are either one cause or three. **The log answers that in one bout;
guessing costs a day.**

- **`BR51.01`** — sniper and chaingun shoot wide *left and down*. The supervisor's own lead: the fixed
  aim camera sits back and right of the shooter, and shots land left. **A matching angle is a strong
  hint that something aims from the camera rather than from the muzzle.**
- **`BR54.01`** — chaingun units within 8.6 degrees, everything else drifting to 43. **The per-unit
  split is the tell**; whatever this is, it is not uniform scatter.
- **`BR52.07`** — one shot in a burst at roughly 90 degrees. May be the same thing at its extreme.
- **`BR52.10`** — an AI unit fires a full burst through the ally in front of it. **Different mechanism**
  — the ally check existed on the retired branch planner and was lost in the taskblock-45 rewrite. It
  rides here because it is the same log that shows it.

**This pass may reorder the rest of the block.** If the angle entries share a cause, that cause is
plausibly upstream of the wall cutout too — both are *geometry disagrees with what is drawn*. **Report
before continuing** if so.

---

# PASS B — The membership question, decided once

**`BR60.02` · `BR52.06` · `BR51.24` · `BR52.09` · `BR51.25` · `BR30.02`**

**`BR60.02` is the one with a named mechanism**, and it is a `docs/10` violation with no timing in it:
`BodyProjector.projects()` returns `hp > 0 or is_mangled or is_disabled`; `UnitGeometry.assembly_
placements` emits under a bare `hp > 0`. **A mangled part is hittable and undrawn in the same frame.**

**Do not patch it locally.** CC declined to, correctly: it is the **fourth instance of one membership
question having two answers**, and `PLAN`'s *Derive plane/picker membership instead of answering it in
four places* is the item. **Decide the rule once and let the entries fall out.**

- **Which side is wrong is a design call**, not a code call: does a mangled part still occlude and take
  hits (the shot plane's answer) or is it gone (the view's)? `docs/03` says MANGLE and DISABLE stay
  fully attached, which argues for the projector — **but then the view must draw them.**
- **`BR52.06`** (a leg appears to have no model) is very likely this, and its own volume theory was
  ruled out — every leg part authors real boxes.
- **`BR52.09`** (destroyed cover's model stays) is a **missing teardown path**, not a membership
  disagreement: nothing in `src/view/` listens for `part_destroyed` and `_spawn_blocker` keeps no
  handle. Separate fix, same cluster tag.
- **`BR51.24`** is an undecided rule pointing two ways; refresh already runs. **The membership decision
  probably settles it** — check after, not before.
- **`BR30.02`** did not reproduce across three real-scene scenarios. **Re-verify or reclassify**; do not
  hunt an unreproduced entry.

---

# PASS C — The wall cutout, newly affordable

**`BR32.04` · `BR32.05` · `BR32.08`**

**Re-read the cost before deferring these a fourth time.** `BR32.05` says it needs a real ray test in
the shader, which was a rewrite when it was filed — **`RayCaster` exists now, and `PartPicker` reports
the struck world point.** The expensive half is built.

- **`BR32.05`** — the cutout's heuristic is a scalar depth compare plus a screen-space radius, with no
  real test against the camera-to-unit line. **Vertical separation is exactly what a screen radius
  cannot distinguish from horizontal**, which is why elevation makes it worse.
- **`BR32.04`** has a worked fix shape already recorded; its difficulty is override lifecycle.
- **`BR32.08`** is `Suspected` — dead or knocked-out shells behaving oddly. **Confirm or drop it in the
  same session**; it costs nothing extra once the cutout is on screen.

**Shader defects are invisible to CC.** taskblock-32 established that these crack only with the
supervisor running the real game against diagnostic builds. **Plan for that rather than discovering
it.**

---

# PASS D — Supervised session: input affordance

**`BR27.15` · `BR30.04` · `BR32.07` · `BR34.03` · `BR35.02` · `BR33.01`**

**Six entries, all supervisor-sourced UI observations, all needing eyes.** This is where a live session
pays; CC can assert that a controller's state changed and cannot see whether anything told the player.

- **`BR27.15`** is the sharpest: step-out has **no view affordance at all** — nothing in `src/view/` or
  `src/debug/` reads step-out state, so the safest-first candidates and the wheel cycling are both
  invisible. **Every controller-state test passes and nothing tests that a player can see it.**
- **`BR33.01`** is `Suspected` and the supervisor has said it is *"more likely to be obsoleted than
  fixed"* — **decide that before working it.**
- **`BR35.02`** is spectator tile-inspect resolving to a hidden cell. taskblock-56's module collapse
  was expected to dissolve it and did not.

**Capture routes, not descriptions.** *"Spectate a bout with two squads on different levels, click a
wall tile"* is a route; *"the inspect is wrong"* is not.

---

# PASS E — The cheap remainder

Small, unrelated, and each closes an entry.

- **`BR51.21`** — a debug injection never animates because `_on_debug_panel_applied` never calls
  `ResolutionPlayer.play()`. **Likely small, and it unblocks `BR35.08`'s confirmation**, which cannot be
  judged on the debug path at all until it lands.
- **`BR51.16`** — the in-game combat log empties itself while the file keeps filling.
- **`BR57.02`** — inspect viewer renders with no directional lighting. The **third** defect found in the
  non-unit preview path after `BR48.01` and `BR51.25`; **that path has never been exercised as carefully
  as the unit path**, which is itself the finding.
- **`BR34.04`** — sniper camera frames from an odd angle. The supervisor's spec: a short distance from
  the target, on the line between shooter and target.
- **`BR51.19`** — more than four units a side spawn stacked.
- **`BR60.01`** — generated maps can contain a large raised region reachable only by ladder.

---

# PASS F — Digest, and what the hunt learned

**The block's deliverable.** Every `SUPERVISOR`-owned entry moved to `Pending`, listed with what was
done and how to see it. **A hunt that fixes eight things and hands back an unreadable ledger has
produced less than one that fixes five and says clearly which five.**

**Also report:**

- **Whether Pass A's angle entries shared a cause.** That answer is worth more than any single fix.
- **Which clusters held and which did not.** taskblock-60 Pass C disproved a seven-entry grouping by
  testing it; the same discipline applies to the rest.
- **Untouched clusters named explicitly** — not silently carried.

# Not this block's job

- **Framerate** (`BR26.02`, `BR27.09`, `BR51.14`, `BR51.15`, `BR57.03`). The ledger header records the
  release bar and the working tolerance, and states these sit deliberately. **Do not re-triage them.**
- **`BR58.01`** — the pacer's wall-clock abort. A determinism defect with its own item and a known fix
  direction; it is not hunted, it is built.
- **`BR54.02` and `BR27.07`** — the two genuine two-clocks entries. They need the snapshot split, which
  did not land, and `PLAN` now records that half of it already exists.
- **`BR52.02`, `BR52.14`** — test infrastructure. `BR52.14`'s own entry flags it as a hunt-waster.
- **`BR51.18`** — `Suspected`, one observation, no route.
- **Closing anything the supervisor owns.** `Pending` with the session uuid, and the digest.
