# TESTING.md — Tester Mode Workflow

How the in-game tester tools (tb28 + tb29) are meant to be used during development. This is the
**headless successor** — instead of reading log summaries and guessing, CC builds a scenario, forces
it into a live bout, and the supervisor watches it play out.

*This describes intent, not a locked spec — the tools are still settling. Update as the workflow
changes.*

---

## The core loop

The intended cycle when chasing a bug or checking a behavior:

1. **CC has something to test** — a specific condition it needs to see (a chaingun firing at a target
   directly beside it, a unit leaning into an overwatch arc, a step-out mid-cover).
2. **CC builds the scenario** — assembles a preset/variant (tb28) and/or scripts an injection (tb29)
   that forces exactly that condition. Authoring is *by data and code*, not by clicking through an
   in-game builder — the authoring UI would be throwaway, and injection can force any state a UI
   couldn't expose anyway.
3. **CC launches a bout in spectator** — the scenario loads, the supervisor takes the spectator view.
4. **The supervisor presses play and steps through** — watches the forced condition resolve, pauses,
   inspects, steps frame by frame. What the log can't show (a backward-drawing tracer, a jittery
   transition) is visible here.
5. **What's seen goes back into the loop** — confirmed working, or filed as a bug (`docs/BUGS.md`)
   with the injection that reproduces it, so it's re-runnable on demand.

The whole point: a bug no longer has to *randomly occur* in a bout to be studied. CC forces it.

---

## The two halves

### Realistic bouts (tb28) — variants, kits, presets
- **Presets** (already existed) — a saved bot: template, loadout, playstyle. Save/load/list; the bout
  menu loads them into teams.
- **Variants** — a preset family generates *structural variation* deterministically (a junk_bot spawns
  with armor in random spots; a combat_tester stays uniform). Same seed → same bot. So a test roster
  looks like real field bots, not clones.
- **Kits** — a bot spawns with a kit (weapon + ammo + magazines + grenades) in a container and equips
  from it. Equip is **instant** at bout start (no watching units rummage); a toggle seam exists for a
  future "watch them arm up" mode, not yet built.

Use this half to make a bout *representative* — the units are armed and varied the way a real fight
would be.

### Forceable bouts (tb29 + tb30) — injection
- **`BoutInjector`** — the debug channel that mutates a *live* `CombatState` at a step boundary
  (never mid-resolution). Every injection is logged with an `inject` marker, so an injected scenario
  is self-documenting.
- **Verbs:** spawn a unit, set a position, arm/equip, set state (HP/wounds/status/AP/facing/pose),
  trigger (make current, force an overwatch arm, queue an action). Each fronts the *real* system —
  an injected spawn is a real spawn, an injected equip is a real kit-equip.
- **Programmatic first** — CC's real use is scripting a scenario in code and injecting it; the
  spectator/player-view injection UIs are convenience wrappers over the same API.
- **Owned by the bout, not the overlay (tb30)** — `BattleScene.bout_injector` is built once per
  `load_battle()`, so it survives a spectator ↔ player-controlled overlay swap
  (`toggle_blue_control()`) instead of being torn down with whichever view first reached for it.
  Both `SpectatorOverlay` (hover-targeted) and `SquadControlOverlay` (selection-targeted) expose the
  same `[*]` Inject menu (`InjectMenu`, one shared item list/dispatch) — `SquadControlOverlay`'s own
  is real-gated behind `OS.is_debug_build()`, not just the `[*]` label, so it structurally can't ship
  in a release export. The actual safety property this always protected — no *ordinary* click/action
  can ever trigger injection — is now drawn at `TacticsController`/`ActionBar` (the real gameplay-
  input classes), not at "which overlay is installed."

Use this half to *force the exact condition* you want to study, instead of waiting for it.

---

## Determinism — read this before trusting a reproduction

- A **clean** bout (seed only, no injection) is fully reproducible: same seed → same bout, always.
  This is the baseline for any "does this bug reproduce" check.
- An **injected** bout is **not** reproducible from seed alone — injection is a deliberate outside
  mutation. An injected bout flags itself (`was_injected`) so it's never mistaken for a clean replay.
- An injected bout *is* reproducible **given the same injections in the same order on the same seed**
  — so a scripted scenario is re-runnable, it just carries its injections as part of its definition,
  not just a seed.
- **Practical rule:** to prove a bug is real and not an injection artifact, reproduce it *clean* if
  you can (force the setup with position/spawn, then let it play seeded). Use injection to *find* and
  *study* a bug; prefer a clean seed to *confirm* it when possible.

---

## Pairs with the log geometry (tb28 Pass C)

Injection sets up the scenario; the **combat-log shot geometry** lets CC read what happened in
numbers (origin + direction per shot, which the log used to drop). Together: **inject the scenario,
read the geometry, see the bug** — CC gets the numbers, the supervisor gets the eyes, and a
rendering-path bug like a backward-drawing tracer is finally diagnosable from both sides.

---

## What this is not (yet)
- **Not an in-game bot builder** — authoring is data/code + injection, deliberately. No throwaway UI.
- **Not a replay system** — injected bouts aren't clean reproducible artifacts; don't treat them as
  save-and-share replays.
- **Not a shipping feature** — reachable during a normal player-controlled bout now (tb30), but only
  behind a real `OS.is_debug_build()` gate: the affordance is never even constructed in a release
  export, so there's nothing to click regardless of what a screen-reader of the code might imply
  from the `[*]` label alone. It's a dev scalpel, not a game feature, in either overlay.
- **Doesn't retire the headless harness on its own** — that happens once this workflow is proven in
  practice. Until then both exist.
