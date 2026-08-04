# 10 — The View: 3D, Camera, Aim & Playback

Phase 12's goal is **something you can see and show off**. One battle, no mission loop. It is
a *view over* the simulation, never a second copy of it.

## The three laws of the view
1. **The view reads; RESOLUTION writes.** No view code mutates `CombatState`. Every change
   goes through a queued Action (`docs/09`). If the view needs to know something, it *asks*
   the logic — it never recomputes.
2. **No number is born in the view.** Anything displayed comes from `StatResolver.resolve()`
   or a `Region`/`LogEvent`. A hand-computed damage preview in a UI script is the exact
   failure `docs/08` exists to prevent.
3. **Extract the logic, leave the pixels.** Any decision worth testing lives in a pure
   `RefCounted` controller that CC can test headlessly. The `Node` is a thin shell that reads
   the controller and sets properties. CC cannot see the screen — so the screen must contain
   nothing worth seeing.

## The view is one surface and a set of modules (taskblock-56 Passes C, D)

There is **one** `ControlOverlay`. There used to be four subclasses, and the reason they existed is
the reason they no longer do.

`SingleUnitOverlay` was 54 lines because it could inherit `SquadControlOverlay` wholesale.
`SpectatorOverlay` was 718 because it *could not*: inheriting would have dragged in
`TacticsController` and the entire unit-input path a spectator is specifically defined not to have.
So it re-implemented the display half, and every shared panel existed twice. **Inheritance forced
the fork** — it offers all-or-nothing, and the requirement was "all of the panels, none of the
input."

### A module

A `ViewModule` (`src/view/modules/`) is one toggleable piece of the surface: the combat log, the
stat readout, the action bar, the inspect modal, playback controls, the debug panel. It is
constructed with no arguments, mounted once against a `ModuleContext`, and unmounted once.

**The contract is that it must mount against a context whose every field is null.** No battle, no UI
root, no host, no tactics, no slots. That is not defensive coding — the player surface has always
had to build before a battle exists, because the session-start log line needs a live sink the
instant it is emitted. **`ModuleContext` deliberately has no `overlay` field**: the cheapest way to
make "a module cannot need its parent" true is to leave the parent out of the vocabulary. The two
things a module genuinely needs from its host are published as `Callable` capabilities.

### Two axes, not one

| kind | means |
|---|---|
| `DISPLAY` | reads the simulation and draws it. May be interactive — the inspect panel opens on a click — but **cannot queue an action against a unit** |
| `INPUT` | accepts player input that queues actions through `TacticsController`, i.e. the path ending in `ActionQueue.enqueue` |

**The line is drawn at unit input specifically, not at "does anything happen when I click."** That
is exactly the axis the spectator view needed and could not get from inheritance, and its contract
is now `has_unit_input() == false` rather than the absence of an inheritance edge.

**Debug injection sits outside this classification**, gated by `OS.is_debug_build()` rather than by
mode — a spectator has carried it since taskblock-30. Classifying it as input would make the
spectator an input mode and destroy the distinction.

### A mode is a declaration

A `ViewMode` says which modules, in what `ModeChrome` layout, with what options, under which turn
policy. **Adding one is a table entry in `ViewModes`, not a file.**

| mode | is |
|---|---|
| `player` | display + full unit input |
| `spectator` | display modules, no unit input |
| `single_unit` | `player` with one field changed |
| `bout_setup` | the roster menu, no board input |
| `empty` | nothing — a deliberate inert placeholder |

**Layout belongs to the mode; behaviour belongs to the module.** A mode publishes named slots
(`ModuleSlots`); a module asks for the one it wants and falls back to the UI root, or to itself,
when the slot is absent. That fallback is what lets the same module appear in the player's
four-region layout and the spectator's two top-left rows without knowing which it is in.

**Ordering within a mode's module list is meaningful** — a module that reads another at mount time
must be declared after it. Connections *between* modules are not subject to that: `link()` runs on
every module after all of them have mounted.

### Two things that bite, recorded so they bite once

- **`emit` does not await a coroutine handler.** It runs the handler to its first `await` and
  detaches. Routing the AI batch through a signal therefore returned control with the batch still in
  flight; it is awaited inline instead.
- **One engine input entry point.** A module defining `_unhandled_input` would receive events
  wherever its host happened to parent it, and a host that also forwarded would dispatch the same
  click twice. `ControlOverlay` owns the handler and routes into the board module. The per-frame
  tick is on the host for the same reason.

## Why 3D
Ragdolls, differing Y levels, and enemies much larger than a standard unit all have to be
faked in 2D, badly. Build it in 3D now. The grid stays `Vector2i` for this phase (a flat
board); height is a later grid change, not a later renderer change.

## Render is hitbox
A `Part.volume` is already `Array[Box]` of `Vector3` centre + size. **Render each box as a
`BoxMesh`.** That is the whole character art pipeline for Phase 12.

- Programmer art that is *correct by construction*: what you see is exactly what the shot
  plane will hit.
- Any visual/hitbox divergence is impossible, so a whole bug class never exists.
- HL2-era budgets (`docs/08`) apply when real meshes arrive later. They are not this phase.
- Colour by material via `WorldPalette` — see "World Palette, Materials & Lighting" below, not
  `HulkTheme` (that palette governs the terminal UI only). Destroyed parts vanish (they
  already leave `living_parts()`).

## World Palette, Materials & Lighting

### Two palettes, not one
`docs/08`'s **six colours is a rule about the terminal UI**, and only that. It never governed
the 3D world. Reading it as a world constraint is what produced a scene painted entirely in
`DIM` on a `BACKGROUND` ground.

| Palette | Scope | Rule |
|---|---|---|
| `HulkTheme` | Terminal UI — panels, log, stat blocks | 6 colours, one `Theme`, flat |
| `WorldPalette` | The 3D board and everything on it | Its own colours. **Lit and shaded.** |

### Two channels, never mixed
| Channel | Carries | Where it lives |
|---|---|---|
| **Material** | what a part is *made of* → its DT | the mesh **albedo** |
| **Allegiance** | whose side it's on | an **overlay** — never the albedo |

Material colour is the truthful channel: a steel plate is the same colour on any unit, on any
team, on the floor as loot. Team flagging sits **on top** so it can't corrupt that reading.

### Material colours are DATA
`color_for_material()`'s hardcoded DT thresholds (`if dt < 6 → DIM`) are **deleted**. Colour
moves onto `MaterialEntry` alongside `dt`, so a new material means a new table row and **no
code edit** — the standing open-endedness rule.

```
MaterialEntry: { dt, deflect_threshold_deg, retain_*, color: Color, ... }
```

Starter table (data — tune freely). Value broadly rises with DT, so armour reads at a glance
as a secondary cue:

| Material | DT | Colour | Hex |
|---|---|---|---|
| `flesh` | 0 | pale salmon | `#C98A7A` |
| `artificial_muscle` | 1 | dark red-brown | `#7A3B33` |
| `artificial_bone` | 2 | ivory | `#D8CFB4` |
| `sheet_steel` | 3 | dull grey | `#6E7276` |
| `steel` | 6 | blue-grey | `#8C949C` |
| `ceramic` | 9 | off-white | `#C6C9C2` |
| `reactive` | 12 | amber | `#C9A227` |

Mostly neutral on purpose — it leaves the blue/red overlay maximum room to read.
**No pool part may have `material == &""`.** That's a `validate_assembly()` violation, same as
a missing volume.

### World colours
| Role | Colour | Hex |
|---|---|---|
| Backdrop / empty space | black | `#050506` |
| Ground (no longer drawn — see below) | green | `#2E4A32` |
| Cover / blockers | brown | `#6B4A2F` |
| Team A flag | blue | `#3A7BD5` |
| Team B flag | red | `#D53A3A` |

Cover is brown **as a material** (`hull_plate` or similar in the table) — not a special case in
the renderer.

**taskblock-55 Pass B: there is no ground, so nothing is drawn in the ground colour.** The board
used to draw one flat quad per cell; a **cell** is a grid square and carries no elevation and no
geometry, and a **tile** — the walkable `Part` — carries all of it. Tiles are drawn as their real
authored boxes in their own part's *material* colour, exactly like cover and walls, from the same
`UnitGeometry.assembly_placements` call the ray caster marches. **An unfloored cell draws nothing**,
because nothing is there; `BoardView._build_empty_indicators` marks those.

`WorldPalette.GROUND` survives only as the contrast anchor `BACKDROP` is calibrated against. The
grid lines are one flat plane at a constant Y — a floor-plan reference saying where the cells are
and nothing about how high anything is, since a line riding a tile's top face would be a second
thing at that tile's elevation.

### Team flagging — an overlay
Two cheap layers, neither touching albedo:
1. **Ground marker.** A flat ring/disc in team colour under each unit. Unmissable, standard,
   costs nothing, survives any material.
2. **Rim outline.** `StandardMaterial3D.next_pass` with `grow_amount` + `cull_mode = FRONT` +
   unshaded team colour. A hull outline with **no custom shader**.

The selected unit gets a brighter ring; queued-move ghosts inherit its team colour.

### Lighting
Unshaded same-colour boxes have no edges — adjacent parts merge into one blob. That's what
made the render unreadable, and it isn't a palette problem.

- One `DirectionalLight3D`, angled (~45° elevation, off-axis) so box faces separate.
- Modest ambient (`AMBIENT_SOURCE_COLOR`, ~0.25 of the ground hue) so shadow faces aren't
  black.
- Part and blocker meshes: **`SHADING_MODE_PER_PIXEL`**, not unshaded.
- `flat_material()` stays unshaded and is for **UI and overlays only** (rings, rims, ghosts) —
  renamed `overlay_material()` so it can't be reached for by accident.
- No shadow maps needed yet. Ambient + directional is enough to read geometry.

CRT/scanline/glow remains a later VFX pass (`docs/08`). This is lighting, not fakery.

## PREREQUISITE — socket transforms (Phase 12.0, before any rendering)
Today `Socket` is `{socket_type, occupant}` and `Part.volume` is authored in absolute
unit-local coordinates. `BodyProjector` never consults sockets. Therefore a torso with 12
`SHOULDER` sockets hosting 12 arms puts **all twelve arms in the same place** — the
modularity pillar (`docs/01`) is not currently expressible in geometry, and the shot plane is
only correct for single-box bodies.

Fix:
```
Socket: { socket_type, occupant, transform: Transform3D }   # host-part-local
Part.volume: boxes relative to the PART's own origin, not the unit's
BodyProjector: compose transforms down the socket tree, then project
```
Fully headless-testable — this lands and goes green before a scene exists.

## Camera
| Mode | Behaviour |
|---|---|
| **Tactical** | Orbit + pan + zoom over the board. The default. |
| **Attack** | On confirming a target: ease to third-person over the shooter's shoulder, target framed. Return on cancel/fire. |

One `CameraRig` with a tween between two states. Transition duration is a constant in one
place, not sprinkled.

## The aim UI — a scrollable dartboard
This is the signature screen. The shot plane is **already** a depth-sorted `Array[Region]`
(`docs/02`), so this is mostly reading it.

**Layers.** Group the plane's regions by owning body (unit or cover object) → an ordered list
of layers, nearest first. Layer 0 is the near enemy; layer 1 is whatever stands behind it.

**Scrolling steps the layer index. It never moves the reticle.** The aim point is a fixed
point in plane coordinates, shared across every layer — the same centre point. Scrolling
changes *what you are reading*, never what you are shooting.

Rendering layer N:
- layer N: drawn solid, highlighted, with its stat readout
- layers < N: drawn ghosted/hatched — they are the occlusion you'd have to thread
- scatter rings drawn around the reticle, from the resolved `Array[Ring]` (**N rings — read
  the array, never assume 3**)

**Two facts are always on screen, and they must never be conflated:**
```
READING:   enemy_b  (layer 2 of 3)          <- what the scroll selected
RESOLVES:  enemy_a / torso_plate            <- what the reticle ACTUALLY hits
```
`RESOLVES` is `ShotPlane.resolve_projectile(whole_plane, reticle)` — always frontmost-first
against the **entire** plane, exactly as the shot will be. Scrolling cannot change it.

That is what makes threading legible and honest: scroll to the far target, walk the reticle
until `RESOLVES` flips to it, fire. You never *select* the far target — you find a gap. The
UI shows you the gap; it doesn't grant it.

Clicking fire without touching any of this sends a **default burst** at the target's centre.
Depth is opt-in, never mandatory.

`AimController` (pure, testable): plane + reticle + layer index → `{layers, reading,
resolves, rings}`. `AimView` (Node): draws what the controller says.

## Resolution playback = log replay
`resolve_turn()` is atomic and already emits a complete, deterministic event stream
(`docs/09`). **The view replays that log. It does not drive the simulation.** Cosmetic only —
which is also why a future multiplayer replay is the same code.

Barebones sequence for this phase:
```
End Turn pressed
  → banner "RESOLUTION", input locked
  → wait  RESOLVE_LEAD_IN        (~1.0s)
  → play events in order; projectiles fire staggered by PROJECTILE_STAGGER (~40ms)
      tracers may be raycast fakes — a line from muzzle to impact is enough
  → wait  RESOLVE_TAIL           (~1.0s)
  → banner "TACTICS", input unlocked
```
All timings are constants in one place. `LogPlayback` (pure) maps an `Array[LogEvent]` to an
ordered list of `{time, visual}` cues — testable headlessly. The Node just runs the cues.

Ragdolls are **not** this phase. A destroyed part hides; that's it.

## Input model (tactical phase)
| Input | Does |
|---|---|
| Click own unit | select; show reachable cells (`Pathfinder.reachable`, MP budget) |
| Click reachable cell | **queue** a `MoveAction`; show it as a ghost path |
| Click enemy | enter Attack camera + aim UI |
| Q / E | **queue** a `FaceAction`, turning relative to whatever's already queued this pass |
| Scroll (in aim UI) | step the dartboard layer |
| Click / confirm | queue an `AttackAction` with the reticle's `aim_offset` |
| Right-click / Esc (aiming) | cancel back to Tactical |
| Esc (not aiming) / click off the board | deselect (`TacticsController.deselect`) |
| End Turn | leave TACTICS, run resolution, play it back |

Queued actions are **previews against a speculative clone** (`docs/09`) — the board shows
intent, the authoritative state is untouched until End Turn.

## Facing (taskblock02 F3)
`FaceAction(unit, direction)` costs 1 MP, same AP-to-MP burn `MoveAction` already uses when MP
runs short (Appendix E) — turning to cover a flank costs distance, the intended tension.
`direction` is an absolute orientation in radians, not a delta, so two queued turns in one
TACTICS pass compose off whatever the first one would already leave the unit facing
(`SelectionController.previewed_orientation`), never both starting from the pre-queue value.

**Any action taken with a target faces for free**, inside that action's own `apply()`
(`FaceAction.face_for_free`) — never a separate charge. In practice that's `AttackAction` only:
`GatherAction`/`PickUpAction` both require standing exactly on the target cell, so there's no
direction to turn toward and neither calls it. Both paths log `faced`, with `reason: manual` or
`free_with_action` and `cost` (1 or 0) either way (`docs/09`: "if it changed the world, it's in
the log").

UI: a small wedge on the unit's own team marker (`HitVolumeView`), pointing along `Unit.orientation` —
present on every unit, not gated to the selected one, since it's strictly more information for
free. Q/E turn the selected unit by 45° (`TacticsController.FACE_STEP`, a flagged placeholder
same as `RETICLE_SENSITIVITY` — docs/10 doesn't pin an exact increment).

## Manual control of both sides (taskblock02 F1; tb31 Pass B)
`CombatState.squad_controllers` (squad_id -> `Enums.SquadController`) defaults every squad to
`UNASSIGNED` — a setup-time-only state, never a real answer to "who drives this squad's turns."
Running a bout with any squad still `UNASSIGNED` is a hard construction error
(`BoutRunner._init()`) — the exact silent-default inheritance that caused BR30.09 (a bout path
that assigned nothing read as a genuine hang, not a setup bug). Every real entry point assigns
explicitly before a bout can run: `CombatState.assign_all_to_human()` ("Control All Squads," a
visible call now, not a hidden getter default) or `assign_rest_to_ai(human_squads)` (the "mostly
AI" shortcut `_seed_battle()`/authoring flows actually want). Nothing in `TacticsController`/
`SelectionController` gates whose unit a click can select by squad; a human queuing either side's
turn emits the same `LogEvent` stream regardless, since both go through the identical
`ActionQueue` -> `resolve_turn()` path.

**Known gap, flagged not hidden:** no `AI` decision-maker actually exists in `src/` yet to
consult `controller_for()` and drive a squad on its own. The heuristics that pick a move/target
today live only inside `test_full_mission.gd`'s own test harness (`_take_turn`/`_queue_turn`),
never rehomed into production code. `squad_controllers` is real, tested data — extracting a
real `AIController` that reads it is the next step, not this one.

## Terminal shell
`HulkTheme` already exists (6 colours, one `Theme`). Phase 12 adds:
- the real OFL monospace font (`docs/08`) — currently the built-in default, a one-line swap
- the rolling combat log panel, fed by the existing `UISink`
- the selected unit's stat block via `StatBlockView`, with `docs/08` drill-down
- an aim readout panel (the READING/RESOLVES pair above)

No CRT/scanline/glow. That is a later shader pass over a correct, flat UI.

## Out of scope for Phase 12
Mission loop, gather/extract UI, roster/meta screens, ragdolls, real meshes, sound, the ship,
deep-strike UI. One battle, hand-seeded, from a "New Battle" button.
