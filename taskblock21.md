# Taskblock 21 — The Inspect Panel, Bout Control, Flee/Extraction, and Cleanup

A big block, front-loaded with the **inspect panel** (the highest-value item — it's how you verify
everything tb20 added). Then bout control, the no-weapon flee behavior, and a cluster of fixes.
Two items are **data-only** (noted, not built as code).

---

# PASS A — The inspect / status panel

Wounds, deflections, per-part damage, and nested internals (tb20) now exist and are **untrackable**.
This panel is what makes them legible — and it's the tool you verify tb20 with. Layout (rough, not
to scale — CC judges proportions):

```
┌──────────────────────────────────────────────────────────┐
│ General info / title bar                                  │
├──────────────────┬──┬────────────────────────────────────┤
│                  │S │  ┌──────────────────────────────┐   │
│                  │t │  │ Logic matrix area            │   │
│  Bot viewer      │a │  └──────────────────────────────┘   │
│  (tall, rotates, │t │  ┌──────────────────────────────┐   │
│   drag to spin)  │u │  │ Inventory (sorted tree)      │   │
│                  │s │  └──────────────────────────────┘   │
│                  │/ │  ┌──────────────────────────────┐   │
│                  │W │  │ Info panel    ┌────────────┐ │   │
│                  │nd│  │ (hover fills) │ item viewer │ │   │
│                  │  │  │               └────────────┘ │   │
└──────────────────┴──┴──┴──────────────────────────────────┘
```

## A1. Bot viewer (left, tall)
- Renders the whole selected bot via `HitVolumeView` / the real assembly (the Resource Editor's
  preview already does this — reuse it).
- **Rotates on its own; click-drag interrupts the auto-rotate to inspect**, releases back to
  rotating. Same interaction as the Resource Editor's preview — share it.

## A2. Status / wound column (between viewer and the right stack)
- A vertical column that fills with **statuses above, wounds below** (tb20 wounds; statuses when
  they exist).
- Each entry is a **<5-char short blurb** now (a square icon later — leave room for that).
- **Hovering an entry fills the info panel** (A5) with its detail.

## A3. Logic matrix area (top-right)
- The selected bot's matrix: name, personal_speed, playstyle, perks (when they exist), link/base
  state (docs/04). Its own region because the matrix is the *pilot*, distinct from the shell.

## A4. Inventory (middle-right, sorted tree)
- **Strong sort, still tree'd:** **Weapons → Inventories/containers → body parts**, each group
  nested by the socket tree beneath it.
- Show **a few** key stats inline if the item has them (not all — the info panel holds the rest).
- This supersedes the current `inventory_panel` (taskblock-04/07) — it's the same "currently
  controlled shell" scope, reorganized and sorted.

## A5. Info panel + item viewer (bottom-right)
- **Hover anything** (a part in the tree, a wound/status, a weapon) → its info fills here.
- **Simple "here are the infos" now**; flagged that each item *type* gets an **authored info shape**
  later (a weapon shows different fields than a wound), plus a **small 3D view of that item alone**
  (separated from the shell) in the item-viewer sub-region.
- Every value through `StatResolver` (docs/08) — provenance, no arithmetic in the panel.

## A6. Dead zones hold the last info
- Hovering something fills the info panel; mousing into a **dead zone** of the panel (empty space)
  **leaves the info put**. Only hovering a *new* hoverable thing repopulates it. This is the
  pinned-until-replaced behavior — hover-off doesn't clear.

## A7. Right-click debug menu
- On a bot/part: **Reset Health**, **Set Health to 0**, and on placeholder guns **Set Ammo Type**.
- Additional suggestions (add if cheap): **Inflict Wound** (pick from the wound set — directly test
  tb20 D), **Detonate Part** (test the failure modes), **Strip Cladding** (test tb20 occlusion —
  reveal internals on demand), **Refill AP/Power**. All debug-only, flagged.

## A8. This supersedes hover-tooltip inspection
The panel replaces the transient tooltip as the primary inspect surface. Keep the lightweight
cursor tooltip for *quick* hovers (action bar, pips), but **object/part/unit inspection goes to this
panel.** Reconcile with `tooltip_controller` / `combat_readout` — don't run two inspect systems.

**TESTS (where reachable — the controller is pure, the panel thin):** the tree sorts weapons →
containers → parts; hovering a part fills the info panel; a dead-zone hover leaves info put; the
wound column lists tb20 wounds; the right-click menu's Reset/Zero Health and Set Ammo work; the
bot viewer renders the real assembly; the panel is the single inspect surface (no duplicate tooltip
path for parts).

---

# PASS B — Spectator: click a bot to pause and inspect

In spectator/bout mode, this panel **replaces hover-to-inspect** (tb17 C added hover-inspect to
spectator; supersede it):
- **Clicking a bot during a bout pauses the bout** and opens the inspect panel on that bot.
- Closing it resumes. The pause is the existing pacing pause (tb15) — reuse, don't add.

**TESTS:** clicking a bot in a bout pauses and opens the panel on it; closing resumes; the paused
bout's state is unchanged by inspection (read-only except the debug right-click menu).

---

# PASS C — "Assume control" in bouts

The overlay swap already exists (tb15 — control is a swappable overlay). This is a **toggle**:
- In the bout menu (and/or mid-bout), toggle **assume control of blue team** ↔ **watch**.
- Assume-control swaps blue's overlay from `SpectatorOverlay` to `SquadControlOverlay` (or
  single-unit); watching swaps it back. Red stays AI.
- Mid-bout toggle is allowed (swap the overlay between turns). No new control system — it's the
  overlay swap tb15 built, exposed as a toggle.

**TESTS:** toggling assume-control swaps blue to a player overlay and back; red stays AI throughout;
a bout with blue player-controlled resolves through the same path as a watched one (only the queue
producer differs); toggling between turns doesn't corrupt state.

---

# PASS D — No-weapon AI flees to extraction

When an AI has **no functional weapon**, it currently stalls. Make it **run away** — and add the
extraction infrastructure that gives "away" a destination.

## D1. Team-coded extraction tiles
- Extraction tiles, **coded per team** (blue extracts at blue's tiles, red at red's). A unit reaching
  its team's extraction tile **escapes** (leaves the board — the EXTRACTED path, docs/07, already
  exists for the mission end).
- Placed at bout setup (near each team's spawn is fine for now) — tunable.

## D2. Flee behavior
- An AI with no functional weapon (all weapons destroyed/disabled/unloaded) **paths to its nearest
  team extraction tile** and escapes.
- This also covers "done in a match" — a unit with nothing useful left leaves rather than mills.
- Fold into `UnitAI`: the weapon check is a new top-priority branch (no weapon → flee), above the
  ranged/cover planners.

**TESTS:** a weaponless AI paths to its team's extraction tile and escapes; extraction tiles are
team-coded (a unit can't use the enemy's); a unit with a working weapon doesn't flee; the escape
uses the existing EXTRACTED path, not a new outcome.

---

# PASS E — The inter-turn FPS hitch: find suspects, don't fix yet

There's a persistent, noticeable FPS hitch **between unit turns.** Per request: **CC investigates and
reports a few suspects with evidence — it does NOT fix immediately.** Rushing a fix risks papering
over the real cause.

Known candidates to profile (starting points, not conclusions):
- **Turn-start power recompute** (`_start_turn` → `PowerResolver.recharge_batteries` +
  `max_ap_for` every turn, tb20 F) — is it heavier than it looks?
- **View-side rebuild on turn change** — does an overlay/panel/board rebuild or re-instantiate nodes
  on every turn advance?
- **The combat-log turn-announce** (the hitch coincides with the turn-announcement entry, per an
  earlier note) — is a log sink doing a synchronous relayout?
- **Initiative re-sort** (tb18 C) — is the whole order recomputed per turn when it needn't be?

**Deliverable:** a short written report — each suspect, how it was measured (frame timing / print
profiling), and a recommendation. **No fix in this pass** unless one is trivially obvious and
CC flags it as such.

## Pass E findings (CC investigation report)

**Method:** standalone headless probe scripts (`SceneTree`-based, not GUT — timed with
`Time.get_ticks_usec()`), calling the real logic/view classes directly. Two measurements:
(1) microbenchmarking each suspect in isolation over repeated calls on a realistic 27-part
deep-struck unit, and (2) a real 3v3 bout (`BoutSetup.build_bout`, AGGRESSIVE AI both sides)
driven 60 turns through the actual `CombatState.resolve_until` path, counting real events/turn
and real affected-unit-ids/turn (what `refresh_unit_views` actually has to redraw) as it
happened. Numbers below are from this machine/build, order-of-magnitude evidence, not a
promise of exact ms in the real game loop (which also pays render/physics costs the probes
don't).

1. **`UISink.emit`'s full-text relayout — the biggest, most variable suspect, and worse than
   the "turn-announce" framing suggests.** `label.text = "\n".join(lines)` is a *full*
   reassignment of the whole up-to-200-line scrollback, on **every single event**, not just
   the turn-start line — measured at ~175-180us/call once the log is full (200 lines), vs.
   ~50us on an empty label. A real combat turn is not one event: the 3v3 bout averaged
   **9.9 events/turn**, peaking at **29** (a burst-fire turn). At steady state that's
   ~1.7ms on an average turn and **~5ms+ on a heavy one** — a real, visible stall, and it
   scales directly with how much a turn actually does (more scatter pellets/ricochets = more
   relayouts), which fits "persistent, noticeable, between turns" well. The turn-start line is
   just the first of many events paying the same tax that turn, which is probably why it reads
   as "coinciding with the turn-announcement" — it's simply first.
   *Recommendation:* switch to an incremental append (`RichTextLabel.append_text` for the new
   line only) instead of reassigning `.text` from the whole buffer; the 200-line cap needs a
   different trim strategy (e.g. trim every N lines instead of every line, or drop the cap and
   let `scroll_following` + a max buffer size handle it). Real design tradeoff, not fixed here.

2. **`HitVolumeView.refresh()` — full mesh teardown/rebuild, unconditional on the acting unit
   every single turn.** Measured ~550-600us per call on the 27-part unit (`remove_child` +
   `queue_free` on every child, then rebuild every box/mesh + material from
   `UnitGeometry.placements`). The 3v3 bout showed 2-4 affected unit ids per turn (mostly 2:
   the acting unit is *always* included via its own `turn_start` event, even on a turn where
   nothing about its geometry changed at all — no move, no hit taken). So this is ~0.6-2.3ms
   of guaranteed-every-turn work, most of it wasted on turns where the unit's own mesh didn't
   actually change.
   *Recommendation:* skip the rebuild for a unit whose only event this turn was `turn_start`/
   `turn_end`/`faced` (no `move`, `impact`, `part_destroyed`, `part_mangled`, `subtree_dropped`)
   — its geometry provably didn't change, so there's nothing to redraw.

3. **Turn-start power recompute — smaller in isolation, but mechanically wasteful.** Measured
   ~175us/call (`_start_turn`'s own `PowerResolver` sequence), unconditional every turn
   regardless of whether the shell even has a power system. Root cause: `has_power_system` +
   `recharge_batteries` + `max_ap_for` (which itself calls `reactor_power` a second time) +
   `discharge_batteries` each independently call `shell.all_parts()`/`operable_parts()`, and
   neither is cached — `Shell.all_parts()` re-walks the whole part graph
   (`PartGraph.walk`, recursive, allocates a fresh `Array[Part]` per level) from scratch on
   every call. One `_start_turn` call re-walks the *same, unchanged* 27-part graph roughly
   5-6 times. Real, but the smallest of the three — "heavier than it looks" mostly because of
   redundant work, not because any one walk is slow.
   *Recommendation:* compute `operable_parts()` once per `_start_turn` call and thread it
   through, instead of each `PowerResolver` function re-deriving it.

4. **Initiative re-sort (`_fastest_by_initiative`/`ResolutionSpeed.initiative`) — measured and
   ruled out.** ~3-4us/unit even across a 12-unit roster (~40us total per `advance_turn()`
   call). `ResolutionSpeed.initiative()` does route through `StatResolver` per docs/08, but at
   this roster scale it's noise next to suspects 1-3. Not a contributor to the hitch.

**Net read:** the log sink (1) is the largest and most turn-shape-dependent cost, the mesh
rebuild (2) is the second largest and the most obviously *wasteful* (fires on turns that
provably changed nothing), and the power recompute (3) is real but small. None was fixed in
this pass per the taskblock's own instruction — none of the three felt "trivially obvious"
enough to flag as an exception: each recommendation above has a real design tradeoff (the log
sink's line-cap strategy, what "provably unchanged" should mean for the view, and whether
`operable_parts()` should be cached on `Shell` itself or just threaded through one call).

---

# PASS F — Missed shots show tracers and raycasts

Missed shots currently draw no tracer/raycast — only hits do. **Every fired shot draws its ray**,
hit or miss (the ray still travels to *somewhere* — a wall, the void, max range). A miss is exactly
the shot you most want to see, to understand *why* it missed.

- Route misses through the same tracer/fade/dull-tracer path (tb15 B) as hits.
- (Ricochet/overpen tracer accounting is a separate earlier note — not required here, but if the
  same code path serves it, note it.)

**TESTS (where reachable):** a missed shot spawns a tracer along its actual ray; the ray terminates
at what it hit (wall/void/max range); misses and hits use the same tracer path.

---

# PASS G — The intermittent sideways slide

*Sometimes* a unit slides into position sideways — a facing bug, but intermittent (not the always-on
one already fixed). Intermittent = a race or a conditional path. Likely: per-tile facing (17-1) is
skipped on some path (a single-tile move? a lean's return leg? a held-turn resume?), leaving the
unit facing its prior direction while it slides.

**Diagnose against the real orientation:** find the move path that doesn't re-face (single-step,
step-out return, or resumed hold are the suspects), and ensure per-tile facing applies there too.

**TEST:** every move path (multi-step, single-step, step-out return, held-resume) faces before each
tile; no path slides sideways; the previously-fixed always-case stays fixed.

---

# PASS H — Data-only fixes (author, don't code)

Two notes are **authoring**, not code — the systems already support them. Do them as `.tres` edits
(and add a test that locks the values), no new mechanics:

## H1. Dartboard: three zones
The dartboard reads N rings from `weapon.scatter` (already N-count — no code limit). The reference
guns are authored with **two** rings. Re-author each gun's scatter as **three**: outer (few, low
weight), **middle (most, high weight)**, inner (few, low weight). This is the intended
outer/middle/inner distribution — a data fix honoring "never assume 3 rings" (it's data, not code).

## H2. Shoot AP cost per gun
`WeaponDef.ap_cost` / `burst_ap_cost` already exist and are checked/spent. Author the values:
**sniper 3 AP/shot, chaingun 4 AP/burst, shotgun 2 AP/shot** (auto-shotgun and others per feel).
Flagged placeholders, tunable.

**TESTS:** each reference gun has three weighted scatter rings (middle heaviest); each gun's ap_cost
matches the authored value and is spent on fire; a burst spends burst_ap_cost.

---

## Scope fence
- **In:** the inspect/status panel (viewer, matrix area, sorted inventory, info panel + item viewer,
  status/wound column, dead-zone hold, right-click debug menu); click-to-pause-inspect in spectator;
  assume-control toggle; weaponless-flee + team extraction tiles; the FPS-hitch *investigation*
  (report only); missed-shot tracers; the intermittent sideways-slide fix; the two data-value edits.
- **Out:** melee (its own next block — the deferred system that unblocks suppression/playstyles/
  Cutter); authored per-type info shapes and per-item 3D views (flagged, simple info now); status
  effects (the wound column shows wounds; statuses when that system exists); fixing the FPS hitch
  (investigation only this pass); icon art for wounds/statuses (short blurbs now).
