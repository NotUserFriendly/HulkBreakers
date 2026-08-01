# Taskblock 51 — Addendum: two clusters the hunt found

*Read alongside `taskblock51.md`. These are two roots surfaced across the first four hunt sessions that
the original triage did not have, each accounting for several reported symptoms.*

*(Filed without a dash in the filename per `CLAUDE.md`'s naming convention — a dash interferes with
local reporting.)*

---

# PASS K — Selection only understands units

## K1. The root, and it is a missing type rather than a bug

`SelectionController` holds **one selectable slot**:

```gdscript
var selected_unit: Unit = null
func select(unit: Unit) -> void:
```

There is no representation for a barrel, a cover prop, or a bare tile. Meanwhile `PartPicker.hit`
already scans `grid.blockers` and `grid.field_items` on every hover — that is BR35.01's entire
complaint — **so the picker sees these things and selection has nowhere to put them.** Every symptom
below is that one gap seen from a different direction.

| reported symptom | what is actually happening |
|---|---|
| Selecting a barrel or any cover selects the tile beneath | the hit resolves to no `Unit`, so it falls through to the cell |
| `Set Part HP` cannot target parts that are not on a unit | the verb takes a unit; an off-unit part cannot be named |
| Selecting a bare tile or cover dims the screen and the dim persists | the inspect path opens for a thing it cannot describe |
| `Inspect` stays enabled when nothing selectable is selected | enablement is keyed to "something was clicked", not "something selectable is selected" |

**BR48.01 is re-scoped by this.** It was filed as a unit-selection bug; the supervisor's third session
established it is cover- and tile-related. Update the entry before working it — its current description
sends you to the wrong path.

## K2. What to build

**A selection target that is not necessarily a unit.** Whatever shape it takes, the requirement is that
`selected_unit` stops being the only answer to "what is selected." Everything downstream that assumes a
`Unit` — inspect, the debug verbs, the dim, hotbar enablement — reads the target's *kind* and either
handles it or declines it explicitly.

**Declining must be explicit and visible.** Half of these symptoms are things silently doing nothing:
the dim opening for something it cannot render, `Inspect` enabled with nothing to inspect. **A verb that
cannot act on the current target should be disabled, not silently inert** — that is the same
command/outcome pairing rule the combat log already follows.

**Do not special-case barrels.** Barrels are the reported case; cover, field items and props are the
same shape. A fix that names barrels leaves the next prop to rediscover this.

**TESTS:** selecting a cover prop selects the prop, not the cell beneath it; selecting a bare tile
selects the tile and opens nothing that cannot describe a tile; `Inspect` is disabled when the target
has nothing to inspect; the dim closes on every path that opens it — **and check whether a second
open/close makes it darker**, since stacking and persisting look identical from the chair; a debug verb
given an unsupported target reports a refusal rather than no-opping.

---

# PASS L — Death mid-turn leaves stale state

## L1. Four symptoms, reported across three sessions

- Killing a unit during its own turn **does not end that turn**.
- A dead or prone unit **cannot be selected**.
- Killing a unit during its turn **does not deselect it** — its movement range stays drawn into the
  next unit's turn.
- The active-turn indicator (**BR27.07 / BR32.09**) jumps to the next unit before the previous one
  finishes animating.

`SelectionController` never references `alive` or death anywhere. `selected_unit` is a raw `Unit`
reference that outlives the unit it points at.

## L2. The supervisor's fourth observation is the diagnosis

> **The indicator moves to the next unit before the animation completes when the AI is controlling. It
> moves with the unit correctly when the player is controlling.**

That is the two-clocks problem confirmed by a controlled comparison, and it is worth more than the
other three reports combined. A human turn ends *after* its animation, so the player path never exposes
the gap. The AI path advances `current_unit` when the **action resolves**, while `ResolutionPlayer` is
still drawing the previous unit's move.

`battle_scene.gd` already names the hazard in prose — the batch badge is unconditional in
`refresh_unit_views` *unlike* the active-turn highlight, which "a caller might want to defer until an
animation finishes." **There are three call sites and the defer is not happening on all of them.**

**Check whether BR27.07 is still the defect it describes.** The original was the highlight landing on
the *wrong unit*; this is the right unit at the *wrong time*. If the selector is now correct and only
the timing is wrong, rewrite the entry rather than carrying both descriptions.

## L3. Turn end and death are separate paths, and that is the bug

A turn ends when its actions complete. **A unit that dies mid-turn has no path to "turn over"** — the
action that would have ended it belongs to a unit that no longer exists. Same root as the stale
selection: death is not a lifecycle event anything listens for.

- **Death ends the turn**, wherever that is owned. Two-phase turns mean RESOLUTION owns the mutation; the
  turn-end path has to be reachable from a death as well as from an action completing.
- **Death clears anything keyed to that unit** — selection, queued actions, drawn reachability, the
  indicator.
- **Decide deliberately whether a dead unit is selectable.** It being unselectable is currently a
  *consequence* rather than a decision, and the supervisor filed it as a bug. A corpse is a thing on the
  board with parts on it, and Pass K is adding non-unit selection targets — so "select the wreck"
  becomes answerable rather than a special case.

**TESTS:** a unit killed during its own turn ends that turn; nothing keyed to it survives into the next
turn (selection, reachability overlay, queue); the indicator does not advance while playback is still
drawing — **assert this on the AI path specifically**, since the player path passes today for reasons
that hide the bug; a seeded bout where a unit dies mid-turn resolves identically before and after.

---

# Where these sit

**Pass K subsumes BR48.01** and is the likely cause of three of the supervisor's unnumbered reports.
**Pass L subsumes BR27.07 and BR32.09**, which taskblock-51 Pass I ordered last on the grounds that the
*One view* refactor would discard instance fixes there. **That reasoning does not apply to L**: turn-end
and death lifecycle are logic, not overlay structure, and no view refactor fixes them. Do L on its
merits and leave Pass I's spectator-divergence entries where they are.

Both are `SUPERVISOR`-observed. Append findings, mark `Pending`, close nothing.

# Not this addendum's job

- **The perf suite and the combat-log fold grouping.** Supervisor is taking both.
- **BR35.01's full scan**, though it lives in the same file as Pass K's picker. Fixing selection does
  not require fixing the scan, and bundling them means one regression test cannot tell you which change
  broke what.
- **BR51.01's shot-lands-left geometry.** Live troubleshooting, in hand.
