# Taskblock 57 — The layout, and an editor you can actually author in

*Closes `PLAN.md` NEXT 1 (*The UI layout*) and NEXT 2 (*The manipulation gizmo*). Depends on
taskblock-56's module system.*

**This is a re-slotting, not new machinery.** taskblock-56 made a mode a table entry, a slot an open
`StringName`, and proved a module mounts against a context with no overlay. **Everything below should be
modules moving, modules retiring, and a handful of new ones.** If a pass needs a new mechanism, that is
worth saying out loud rather than building quietly — one exception is named up front (the action bar
publishing slots) and one is expected (the gizmo).

**The supervisor will fine-tune with CC after the bulk lands.** So: get the structure right and the
numbers approximately right. Padding, exact sizes and colour values are the cheap half and they are the
half that wants a screen.

---

# PASS A — Two coordinate spaces, and a UI scale that exists

## A1. `safe_rect` and `screen_rect`

**All sizing is against a 16:9 reference rect.** Ultrawide letterboxes to a 16:9 rect inside the screen;
narrower ratios (4:3, 16:10) **crush** rather than clip.

**Make "escapes the safe rect" a property of a slot**, not a comment in a panel. Three surfaces do it
deliberately — Inspect, the Inspect Viewer, the performance monitor — and a property is checkable where
a convention is not.

## A2. UI scale

**A multiplier on pixel sizes**, replacing the constants that stand in for it today. Not settable yet —
it belongs to an options menu that does not exist — so a variable with a default of 1.0 and one place
that reads it.

**This is what makes the collapse rule mean anything:** every side-pinned surface is collapsible or off
by default, so a square-ratio player is never forced to shrink the UI to play. They lose nothing; they
toggle.

**TESTS:** `safe_rect` is 16:9 inside any screen ratio and never exceeds it; a slot marked as escaping
resolves against `screen_rect`; scale multiplies every sized element (assert against one changed value,
not against a render); every side-pinned module reports itself collapsible.

---

# PASS B — The action bar publishes slots

**Four surfaces pin relative to the action bar, not to the screen** — turn order to its right, combat
log to its left, unit resources above centre, UI buttons above right. Today's slots all resolve against
the screen.

**The action bar publishes its own slots** — `action_bar_left`, `action_bar_right`,
`action_bar_top_left`, `action_bar_top_right` — rather than becoming a composite cluster module. That
keeps each surface an independent module and fits `ModuleSlots`' existing vocabulary.

**This is the one new mechanism in the block: a module may be a slot provider.** Keep it general; do not
special-case the action bar. Anything else may want to publish later.

**TESTS:** a module mounted into an action-bar slot positions against the bar, not the screen; with no
action bar present those modules still mount somewhere sensible (**the stand-alone acceptance from
taskblock-56 Pass C still holds and is not weakened by relative anchoring**); moving the bar moves its
dependants.

---

# PASS C — Place everything

| surface | placement |
|---|---|
| **Action bar** | bottom, centred, half a 16:9 screen wide at 1x |
| **Turn order management** | right of the action bar, padded. **Player mode only.** End turn with AP or MP left **prompts for confirmation** |
| **Combat log** | left of the action bar, padded. **Minimises to a button flush against the bar, no padding.** Word wrap and verbose as checkboxes |
| **Unit resources** | above the bar, centred — AP/MP pips, RAM, room for later resources |
| **UI buttons** | above the bar, right edge — module toggles, Inspect, the debug menu |
| **Inspect / Inventory** | top-right, ~2/3 screen tall, square. **Escapes the safe rect** |
| **Inspect viewer** | top-left, ~2/3 tall, half as wide — the 3D view, split out so the centre stays clear. **Escapes the safe rect** |
| **Debug menu** | top edge, centred, 1/4 of the 16:9 width, drag-resizable height. **Budges left if Inspect crowds it — a one-off, not a mechanism** |
| **Performance monitor** | true bottom-right corner, no padding, **click-through and mostly transparent**. Takes the FPS readout off the combat log; **use the existing perf stats from the debug menu rather than the log's** |
| **Announcements** | top, centred, invisible and click-through |

**Hovering:** 1.5 s motionless before a tooltip. **Two behaviours sharing one timer** — a button
tooltip is *descriptive* (what will this do), a combat-log overflow preview is *revealing* (what does
this line say, shown in place over the text). Do not merge their content models.

**TESTS:** each module resolves into its declared slot; the debug menu budges and only for Inspect; the
minimised log's button abuts the bar with zero padding; ending a turn with AP or MP remaining raises a
confirmation and cancelling it leaves the turn intact.

---

# PASS D — Retire, fold, and collapse

- **`queue_panel_module` retires.** Waypoints and ghosts carry the load. **What is lost is confirmation
  that a click registered**, which has confused people before — so it moves to the combat log under a
  queuing fold: *unit 0 queued a move to (0,0,1)*, *unit 0 queued action: burst*, *unit 0 cancelled
  move*, *unit 0 cancelled action: burst*.
- **`stat_panels_module` retires.**
- **`board_inspect_module` folds into Inspect.** **Everything is a part**, so one inspector shows a
  unit, a piece of cover, a part lying on a tile, or the tile itself. **Rare targets — floor tiles
  especially — should need enabling from the debug menu** rather than being clickable by default, or
  every misclick lands on the floor.
- **`controls_legend_module` → UI buttons. `top_left_controls_module` → the spectator action bar.**
- **`bout_setup_module` stays centred** and keeps turning everything else off. Temporary; its
  full-screen width is acceptable while it is modal.
- **Player and single-unit modes collapse into one**, **with the active unit pre-selected.** Clicking
  your own unit every turn is ungainly, and with one unit the behaviour was already identical.

**TESTS:** the queuing log entries appear on queue and on cancel, and fold together; the inspector
renders a unit, a cover piece, a loose part and a tile; a floor tile is not selectable with the debug
toggle off; the collapsed player mode pre-selects the active unit at turn start; `single_unit` is gone
from `ViewModes` and nothing references it.

---

# PASS E — Announcements are a view of the log

**One emit, two views.** Anything tagged as an announcement lands in the combat log *and* is shown at
the announcement position. **Sequential, not double-rendered** — it can never appear in one and not the
other, which is exactly what two calls would eventually produce.

**The only thing the log lacks is a lifetime, and it belongs to the view.** The announcement position
shows tagged entries newer than N seconds; the log keeps them forever.

**Announcements carry a priority**, driving **duration, colour, and whether a sound plays**. **There is
no audio system** — the priority carries a `sound` field and nothing consumes it, exactly as
`encounter_types` is authored and unread. Do not build audio here.

**Alignment:** centred when the inspect panels are closed, left-aligned when open. **If that
cross-module read is awkward, left-align always** — the supervisor has said so explicitly, so take the
simpler option rather than building a dependency for it.

**TESTS:** a tagged event appears in both surfaces from one emit; an expired announcement leaves the
position and remains in the log; priority changes duration and colour; the `sound` field round-trips
unread.

---

# PASS F — Aim is a mode

**Most modules turn off when the camera drops to over-the-shoulder or sniper view.** That is a module
set, so **it is a mode** — enter aim, switch; leave, switch back. No suspension mechanism, and "what is
visible while aiming" becomes a table entry someone can read.

**The aim view and dartboard are not UI modules** and do not become ones. They are what the mode
switches *to*.

**TESTS:** entering aim switches modes and leaving restores the previous one; the aim mode's module set
is a table entry; a module absent from the aim set is not mounted while aiming.

---

# PASS G — The editor surface

## G1. Three action bars, not one with three contents

Shaped differently, so genuinely three modules sharing one slot:

- **Player** — square items, left-aligned, two rows, small padding.
- **Spectator** — playback controls, plus the old top-left cluster.
- **Editor** — **labelled buttons, not squares.** *"Place Items"* opens a **centred, searchable list of
  every part placeable on a tile**; **tiles and claims get their own buttons.** Also holds save, load,
  run-a-bout, and undo.

## G2. The editor's own surfaces

- **A coordinate readout replaces Unit Resources in editor mode** — same slot, different module. Cell,
  height, and a truncated name of what is there. Detail is the inspector's job.
- **Section details go where the Inspect Viewer sits**, with a toggle in UI buttons.
- **Validation warnings go to the combat log**, and the significant ones surface as announcements.
  *Warn, never block* needs somewhere to warn.
- **Current tool shows on the cursor** — a small icon of what is being placed — **or** is carried by the
  action bar's own highlight. Either is fine; neither is not.

**TESTS:** each mode mounts its own action bar module; the place-items list is searchable and offers
every placeable part; the coordinate readout tracks the cursor's cell and height; a validation warning
reaches the log and a significant one reaches the announcement position.

---

# PASS H — The manipulation gizmo

**A 3D CAD-style handle set with a numeric readout**, doing two jobs.

- **Placement height.** Click a placed item, drag the up arrow, watch the readout show 0.3. **Snap to
  0.1** — the precision authored maps were always intended to have.
- **Claim volumes.** **One click selects and gives translate arrows; a second click swaps to resize
  handles.** Same gizmo, two handle sets.

**The picking foundation exists.** `PartPicker.hit` and `UnitPicker.hit` are analytic ray-vs-box in
`src/logic`, and gizmo handles are boxes — **the same primitive, not a new one.**

**Keep the drag math in logic.** Screen delta → axis delta → snapped value is pure, so the gizmo is
testable without a screen exactly as `EditorController` is. **The scene reads and draws; it decides
nothing.**

**Do not let this become a second selection system.** A gizmo is a tool over the existing selection, not
its own notion of what is selected. This project has produced two visibility systems, two aiming paths
and two overlay hierarchies; that is the shape this takes if it drifts.

**TESTS:** a drag of N pixels along an axis produces the correctly snapped value, headless; every value
lands on a 0.1 multiple; a second click on a claim swaps handle sets and a click elsewhere deselects;
the gizmo never changes what is selected; resizing a claim produces a valid volume and an invalid drag
is refused rather than clamped silently.

---

# When to stop and report

- **A module cannot mount without the action bar.** Relative anchoring must not weaken taskblock-56's
  stand-alone acceptance.
- **The gizmo needs its own selection.** Report it rather than building it.
- **A retirement loses coverage** — particularly `queue_panel`'s confirmation role. The log entries are
  the replacement and must land first.
- **Budging turns out to want to be general.** It is specified as a one-off; if a second case appears,
  say so rather than generalising quietly.

# Acceptance

- `safe_rect` and `screen_rect` are both real, and escaping is a slot property.
- The action bar publishes slots, and it is not special-cased to do so.
- Every surface in Pass C's table is in its declared place.
- `queue_panel` and `stat_panels` are gone; queueing is legible in the log.
- One emit puts an announcement in both surfaces.
- Aim is a mode.
- A height is authored by dragging an arrow to 0.3.

# Not this block's job

- **Audio.** Priority carries a `sound` field nothing reads.
- **The options menu** that would make UI scale settable.
- **The debug-menu redesign.** It gets a placement here and nothing more.
- **Claim volume *authoring* beyond the gizmo** — the section vocabulary is landed; this is the handles.
- **`BR56.01`** — a facing bug in the ramp subsystem NEXT 3 deletes. Do not fix it first.
