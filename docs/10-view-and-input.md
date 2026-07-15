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
- Colour by material via the `HulkTheme` palette; destroyed parts vanish (they already leave
  `living_parts()`).

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
| Scroll (in aim UI) | step the dartboard layer |
| Click / confirm | queue an `AttackAction` with the reticle's `aim_offset` |
| Right-click / Esc | cancel back to Tactical |
| End Turn | leave TACTICS, run resolution, play it back |

Queued actions are **previews against a speculative clone** (`docs/09`) — the board shows
intent, the authoritative state is untouched until End Turn.

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
