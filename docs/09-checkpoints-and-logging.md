# 09 — Checkpoints, Combat Log & Turn Phases

## Turn phases: TACTICS then RESOLUTION
Turns are **queued, then paid off**. These are two distinct phases and the split is
structural, not cosmetic.

```
TACTICS     player queues an ordered action list per unit
            "go here, fire here, go here, fire here, end turn"
            → previews only. The authoritative state is NOT mutated.

RESOLUTION  on End Turn, the queue executes — until something interrupts it.
            → every mutation, every projectile, every explosion happens here.
```

Why it's built this way:
- **The payoff doesn't land while you're neck-deep in a stat panel.** Reading and watching are
  separated in time.
- **Multiplayer falls out cleanly.** Simultaneous turns need exactly this shape: collect
  intents → resolve authoritatively. Retrofitting it later means touching every action.

### Rules
- `ActionQueue`: an ordered list per unit. Queuing validates *optimistically* against a
  **speculative** state copy for previews.
- **RESOLUTION is a loop with re-entry (docs/10 taskblock06 Pass D), not one atomic pass:**
  `TACTICS → RESOLUTION → (interrupt) → TACTICS → RESOLUTION → ...`. `resolve_until()` is the
  real entry point (`resolve_turn()` is a thin void wrapper over it for callers that don't care
  about the outcome) and returns `{kind: COMPLETED}` or `{kind: STOPPED, unit, reason, refund:
  {ap, mp}}`.
- **Re-validate at resolution.** The world moved. **Stop the instant the next thing to happen is
  no longer legal — never "abort this one and keep going."** (This reverses the older rule this
  section used to state; taskblock02 F's "abort, log, continue" is gone.) A queued move is
  re-checked at cell granularity too, not just between actions — a lost leg can turn the rest of
  an already-approved path illegal even though the path itself never changed. **AP already
  spent stays spent** (it already bought whatever MP got used); **MP is refunded** as whatever
  the interrupted unit's own pool holds at the stopping point. **Only the interrupted unit
  returns to TACTICS** — every other unit's own queued resolution is unaffected.
- Resolution order is deterministic and seeded.
- No mutation ever escapes RESOLUTION. If a system mutates during TACTICS, that's a bug.

This stays out of scope for netcode (`99`) — but `CombatState` must remain serializable and
every mutation must flow through a queued Action, so a future authoritative host could replay
one turn's queues.

## The combat log
A **rolling, structured log** — a real game feature, and simultaneously CC's and your
monitoring channel.

```
LogEvent: { turn, phase, unit_id, kind: StringName, data: Dictionary, text: String }
CombatLog.emit(event)
```

**Sinks are pluggable** (this is the open-ended bit — do not hardcode a destination):

| Sink | Use |
|---|---|
| `MemorySink` | tests assert on the event stream |
| `StdoutSink` | CC reads it in the test log |
| `FileSink` | appends to `out/combat.log` — **you `tail -f` it** |
| `UISink` | the in-game rolling log panel (Phase 10+) |

Rules:
- Log **events, not strings**. `text` is rendered from `data` via the description builder
  (`08`), so the log and the tooltips can never disagree.
- Every projectile, deflection, ricochet, penetration, cook-off, abort-reason, and matrix
  ejection emits an event. If it changed the world, it's in the log.
- Same seed → byte-identical log. That makes the log a **regression fixture**: diff two runs.
- **One stream, many sinks — never two streams** (taskblock03 Pass B). `BattleScene` registers
  both `UISink` and `FileSink` on the *same* `CombatLog`, so the on-screen panel and
  `out/combat.log` are the identical event stream by construction — they cannot drift, because
  neither one renders anything the other doesn't also get. A `session_start` event carries the
  seed as the file's first line, so a human session is a regression fixture too, not just a
  headless test run: it's replayable from the log file alone.

## Checkpoints
Reviewable artifacts at points where a silent geometry or randomization bug would otherwise
get buried under later code. **Five, deliberately** — enough to catch drift, not so many that
reviewing them becomes the job.

Each is `./checkpoint.sh N` → writes to `out/checkpoints/NN/` → a short `README.md` plus
artifacts. CC does **not** proceed past a checkpoint without a go.

| # | After phase | Artifact | What you're looking for |
|---|---|---|---|
| **1** | 0 — Harness | ASCII grid + a generated hulk map, several seeds | Does the map look like a place? Are seeds actually different? |
| **2** | 3 — Projection | One cyborg's shot plane dumped from **8+ angles**, sweeping continuously | Do the boxes track the angle sanely? Does the rear ammo rack appear only from behind? Any pop or discontinuity = bug. |
| **3** | 5 — Armor & ricochet | A seeded burst into an armored target: impacts, deflections, ricochet paths, retained damage per bounce | Does grazing keep ~90%? Do bounces land somewhere plausible? Is the spray chaotic but not insane? |
| **4** | 7 — Deep strike | 20 randomly assembled cyborgs from a part pool, ASCII + stat blocks | The randomization/body-combo stress test. Anything malformed, unarmed, or absurd shows up here. |
| **5** | 11 — Full mission | Complete `combat.log` of a full seeded mission, start to extraction | The whole thing, readable. |

Checkpoint artifacts are **committed** so they diff across runs.

## Why this matters for CC specifically
CC cannot see the game. The ASCII dumps and the combat log **are** its eyes — and they're the
same artifacts you review. One channel, two consumers. Build them in Phase 0 and use them in
every phase; a spatial system without a dump is a system nobody can verify.
