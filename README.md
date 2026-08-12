# HulkBreakers

A turn-based tactical roguelike in Godot 4.7. You captain a salvage ship stripping derelict
**voidhulks** — dead ships full of things worth more than the crew you send in after them.

Your crew are **Intelligence Matrices**: human minds in hardware, wearing grown surrogate flesh over
disposable modular shells. Matrices persist. Bodies are ammunition.

## What makes it different

**Armour is geometry, not a hit-point pool.** A shot is a real ray marched from the muzzle. It
meets whatever is in its way — a limb, a crate, a wall, the deck — and solves the angle of
incidence against the surface it actually struck. There is no exposure table, no
FRONT/BACK/LEFT/RIGHT snapping, and no weighted body-part roll. If a wall is in the way, the wall
is in the way.

**Penetration never rolls.** Damage carries through a part or it stops, decided by material and
angle. A round keeps going while it still has damage to spend, so a burst that punches through a
target goes on to strike the floor behind it. A deflection starts a new ray from the impact —
the same call, a different direction — bounded by a depth cap and a damage floor so the
simulation provably terminates.

**You aim at a point, not at a body part.** The reticle picks a spot on a depth-sorted projection
of everything along the line of fire; scatter rings offset it; then the round is fired at where
that lands. There is no "aim for the neck" checkbox — you pick a spot and live with the spread.

**Parts attach by tag, not by slot.** Anything shoulder-shaped fits any shoulder. Weapons, limbs,
armour and infrastructure are all `Part`s carrying open `StringName` vocabularies, so content is
addable as data without a code edit.

## Layout

| | |
|---|---|
| `src/data/` | `Resource` subclasses — parts, materials, weapons, tables |
| `src/logic/` | `RefCounted` rules with **zero SceneTree dependency** |
| `src/debug/` | ASCII renderers and the combat log |
| `src/view/` | Thin presentation over the logic layer |
| `src/resource_editor/` | In-editor tool for authoring the `src/data/` resources |
| `docs/` | Design docs `00`–`11` and the unqueued backlog `99`, plus the living ledgers below |
| `test/` | GUT suite, headless — script and test counts in `test/SUITE-PROFILE.md` |

**The organising constraint is that every rule must be verifiable without rendering.** Logic is pure
GDScript tested headlessly; the view layer is thin and added last. Anything spatial prints an ASCII
dump into the test log, because a spatial system nobody can read is one nobody can check.

## Running it

```bash
./run_tests.sh test_foo.gd   # one file — the edit loop
./run_tests.sh fast          # no bouts
./run_tests.sh shard         # everything, 8 processes
./run_tests.sh               # everything, one process; writes the suite profile
```

Requires Godot 4.7 and `gdtoolkit` (`pip install gdtoolkit`) for `gdlint` / `gdformat`.

The sharded gate's cost is a band rather than a number: it ends when a randomly-drawn mission
sample ends, so identical runs land anywhere from roughly 220 s to 630 s. `test/SUITE-PROFILE.md`
has the current figures.

## Reading the design

Start at `docs/00-pillars-and-loop.md`. The numbered docs are the design; four living documents
carry current state:

| | |
|---|---|
| `docs/PLAN.md` | forward-only, dependency-sequenced — what is unbuilt and in what order |
| `docs/CHANGELOG.md` | what has been built, tagged with the taskblock that landed it |
| `docs/SUPERSEDED.md` | append-only reversal ledger, so an old comment is never mistaken for current truth |
| `docs/BUGS.md` | open defects only; closed ones move verbatim to `docs/BUGS-ARCHIVE.md` |

## Status

In development, single developer. There is no playable entry point yet — the game currently starts
in a battle-scene test harness. See `docs/PLAN.md`.

## Licence

All rights reserved. See [LICENSE](LICENSE) — you may read this repository, and nothing else is
granted.
