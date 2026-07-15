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

## Art pipeline (Phase 12+)
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

## run_tests.sh
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
