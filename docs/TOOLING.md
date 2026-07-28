# TOOLING.md

Everything here is free. Nothing in this project requires a paid tool.

## Required
| Need | Tool | License | Where |
|---|---|---|---|
| Engine | Godot 4.7 | MIT | https://godotengine.org |
| Tests | GUT | MIT | https://github.com/bitwes/Gut |
| Lint / format | gdtoolkit (`pip install gdtoolkit`) → `gdlint`, `gdformat` | MIT | https://github.com/Scony/godot-gdscript-toolkit |

`gdlint` gates `run_tests.sh`. It catches parse errors and smells in ~1s without launching
the engine — a much faster failure signal than a headless GUT run.

**Reviewing without the engine:** the toolkit runs standalone — `gdparse` (syntax) and
`gdlint` (smells) validate a checkout with no Godot binary present, which is how a reviewer
on a clean clone confirms a push parses and lints before the author runs the full GUT suite.

---

## The scripts, and which need a screen

Every script honours `GODOT=/path/to/godot` if `godot` isn't on `PATH`.

| Script | Screen? | What it is |
|---|---|---|
| `run_tests.sh` | headless | The gate. Lint → import → GUT. |
| `run_game.sh` | **on-screen** | The actual game. Press `B` at `battle_scene` for Simulate Bout. |
| `run_resource_editor.sh` | **on-screen** | The Resource Editor as its own process. |
| `checkpoint.sh N` | **on-screen** | Runs visual checkpoint `N`. |
| `tools/checkpoints/run_visual_checkpoint.sh` | **on-screen** | The generic driver `checkpoint.sh` dispatches to. |
| `tools/bench_release.sh` | export | Release-vs-debug AI planning measurement. |

**Headless is not a lesser mode and is not being retired.** It is the only mode that can gate a
commit, and the on-screen tools exist because `--headless` has a no-op renderer and therefore cannot
answer "does this *look* right." Both stay.

### `run_tests.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
GODOT="${GODOT:-godot}"

# 1. Lint gate — fast failure, no engine needed.
gdlint src test

# 2. Warm-up import so class_name scripts register (required on cold checkouts).
"$GODOT" --headless --path . --import --quit || true

# 3. Headless GUT. GODOT_DISABLE_LEAK_CHECKS avoids false failures from exit-time leak logs.
GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
  --display-driver headless --audio-driver Dummy \
  --path . \
  -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://test -ginclude_subdirs -gexit
```

### Visual checkpoints
A checkpoint is a real scenario driven through a real GPU frame, writing screenshots and a `run.log`
into `out/checkpoints/NN/`. **`out/checkpoints/` is local-only** — the images are the thing you looked
at; the durable artefact is the supervisor's answers, which go in the taskblock report.

Authoring one is ordinary work, not a ceremony: **the original checkpoint discipline retired the
"stop and wait for a go" gate, not the capability.** There is no hard stop in either script.

`tools/checkpoints/parse_guard.gd` runs inside `run_tests.sh` and loads every checkpoint script,
failing on a parse error. Rendering can't happen in CI; **parsing can** — and without it a rename
silently orphans these scripts, which has happened twice (a `UnitView` rename went unnoticed for
roughly fifteen blocks, then the same class of failure recurred one directory over in `tools/`).

The guard scans `.gd` **directly under `tools/`** plus `tools/checkpoints/`, deliberately
**not recursively** — so `tools/archive/` is out of scope by design, which is where retired one-off
scripts belong rather than being kept compiling forever.

### Benching AI planning
Two files, transposed names, **not duplicates** — do not "clean up" one of them:

- `tools/ai_planning_bench.gd` — `class_name AiPlanningBench`, the measuring library.
- `tools/bench_ai_planning.gd` — the `SceneTree` entry point that drives it (`-s`).

Output is stamped with the build it came from (`BuildIdentity`: `editor_debug` / `exported_debug` /
`exported_release`) and warns when the build isn't representative of play. **Read that stamp before
comparing any two numbers** — a whole series of measurements was taken on an editor binary before
anyone checked what that cost.

### `tools/bench_release.sh` — the release comparison
Runs the same bench, same seeds, same steps, on a release export and on the debug path, and prints
the ratio. **Deliberately not in `run_tests.sh`**: an export takes real time and this is a
measurement, not a gate — the same reasoning that keeps visual checkpoints off the test path.

Two requirements, both of which fail loudly rather than degrading silently:

1. **Export templates matching the engine version.** *Editor → Manage Export Templates → Download and
   Install*, or unzip the `Godot_v<version>-stable_export_templates.tpz` release asset into
   `~/.local/share/godot/export_templates/<version>.stable/`.
2. **An `export_presets.cfg`**, which is gitignored because export paths are per-machine. Keep a
   committed `.example` beside it so the preset *name* the script expects is shared knowledge.

**Exporting is a first-class diagnostic, not a release chore.** Nothing had ever been exported until
taskblock-44, and the first export revealed that the shipping configuration loaded no data at all —
binary conversion produced `.res` and `.tres.remap` files that the loader's `.tres` filter skipped, so
every downstream path died on a division by zero, as a bare `SIGFPE` with no message. Export **debug
and release**: the debug export is what makes such a crash legible; release alone is a silent trap.

### `tools/` one-offs
`author_*.gd` and `migrate_data.gd` are single-use data-authoring scripts, run once and kept for
provenance. Retired ones live in `tools/archive/`, outside the parse guard's scope — they are history,
not code that must keep compiling.

---

## Art pipeline (later — when the part vocabulary stops moving; see CLAUDE.md)
| Need | Tool | License | Where |
|---|---|---|---|
| Modeling | Blender | GPL | https://blender.org |
| 2D / UI art | Krita | GPL | https://krita.org |
| CC0 3D placeholders | Kenney | CC0 | https://kenney.nl |
| CC0 3D placeholders | Quaternius | CC0 | https://quaternius.com |
| CC0 textures / HDRI | Poly Haven | CC0 | https://polyhaven.com |
| CC0 textures | ambientCG | CC0 | https://ambientcg.com |
| Binary assets in git | Git LFS | MIT | https://git-lfs.com |

## Terminal UI fonts (all OFL, free)
JetBrains Mono · IBM Plex Mono · Share Tech Mono · VT323 — https://fonts.google.com

Pick **one** and put it in a `Theme` resource. Six colors max: background, foreground, dim,
highlight, warn, damage.

---

## Known gotchas
- **Warm-up import is mandatory.** Without `--import --quit` first, `class_name` scripts
  aren't registered on a cold checkout and the run fails.
- **Leak-check false negatives.** Godot prints `ERROR` lines and can exit non-zero even when
  every test passed. `GODOT_DISABLE_LEAK_CHECKS=1` fixes it.
- **Don't hand-author `.tscn` for logic.** Internal resource IDs are fiddly and get corrupted.
  Keep scenes trivial; build nodes in code.
- **Builtin shadowing.** `gdparse` accepts a param named `range`/`load`/`sign`, but it
  shadows the builtin and fails at load or call time. (This bit v1's `los.gd`.) `gdlint`
  catches the class of problem faster than the engine does.
- **`-s` is ignored on some invocations.** A script path passed with `-s` can be silently skipped
  rather than erroring — verified by passing a *nonexistent* path and getting an identical result.
  If a `-s` entry point seems not to run, check that before debugging the script.
- **An exported build is not the build you tested.** Resource conversion, filter globs and missing
  data only bite after export. See `bench_release.sh` above.
