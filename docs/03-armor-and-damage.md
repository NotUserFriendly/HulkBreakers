# 03 — Armor, Damage Threshold & Chaos

## Damage Threshold (DT)
Armor is **not** more hitpoints. Each part/plate has a **DT** looked up from its `material`,
plus its own HP.

**The material table is data**, not a code constant — a `Resource` mapping
`material: StringName → {dt, ricochet_bias, tags}`. New materials must never need a code edit.

```
resolve_impact(projectile, region) -> Outcome:
    if projectile.damage >= region.part.dt:      # PENETRATE
        damage the plate AND whatever is behind it in the shot plane
    else:                                        # STOPPED — geometry decides how
        bend = angle(incoming_dir, surface_normal)
        if bend <= material.deflect_threshold:   # steep / near head-on
            STOP_DEAD  → plate takes the damage, projectile ends
        else:                                    # oblique
            DEFLECT    → plate takes NO damage, spawn ricochet
```

`surface_normal` comes free from the projection (`02`) — the box face that was hit. Angle is
real geometry, not a roll.

This gives heavy units a real identity: **a steel combat unit shrugs off an entire chaingun
burst** because every round is under its DT. One high-damage rifle round goes straight
through, damaging both plate and the part beneath.

## Ricochet — the chaos engine
A deflected round **does not vanish**. It spawns a new projectile off the surface normal that
travels the world and can hit **anything**: allies, the shooter, terrain, cover, or a
different part of the same target.

### Damage retention scales with how hard it bent
Velocity is what's lost, so a graze keeps nearly everything and a hard bounce keeps almost
nothing.

```
retained = lerp(0.90, 0.25, clamp(bend_angle / MAX_BEND, 0.0, 1.0))
```

| Bounce | Retained |
|---|---|
| Barely licks the plate and carries on | **~90%** |
| Moderate deflection | ~55% |
| Near right-angle bounce | **~25%** |

So a round that grazes a plate and hits the guy behind it does **the majority of its damage**.
That's the intent — grazing is not a save.

The `0.90 / 0.25` endpoints and the curve shape are **tunables in the material table**, not
constants in code.

### Termination is mandatory
Cap ricochet depth (default 2) and drop projectiles below a minimum damage floor. The sim
must always terminate, and must be seeded — the same seed replays the identical spray.

## Crits
| Target | Crit effect |
|---|---|
| Armored | **Bypass armor** — resolve against the part behind, ignore DT. |
| Unarmored | **Bonus damage.** |

Crit chance is a **float**, not a bool. 125% = always crit, and 25% of the time **double
crit** → bypass armor *and* bonus damage.

## Why the player can still win (anti-unkillable rules)
1. **Stop-dead damages the armor.** Sustained fire grinds a plate down even with no
   penetration. Deflection doesn't — so angle matters both ways.
2. **Coverage is never total.** Front-heavy armor means flanking puts every round onto thin
   rear plate or bare parts — automatic from the projection (`02`), not a bonus.
3. **Crits beat armor.**

## Cook-off
Parts tagged `VOLATILE` (ammo racks, fuel cells) explode when destroyed: area damage centred
on the part's holder. This is what makes flanking a back-mounted ammo rack a *tactic* rather
than a stat bonus.

## Flanking
Positioning grants **access**, not a damage bonus — to thin armor, to the ammo rack, to an
unplated joint. Small extra: attacks from behind bias toward knockdown.

Counters exist and are **earned, not innate**: auto-facing anyone entering melee, a dodge
reaction, back plating, or wearing something disposable on the `BACK` socket.

## Materials (starting data — tune freely, this lives in a Resource)
| Material | DT | Notes |
|---|---|---|
| Flesh / organic | 0 | surrogate tissue |
| Artificial muscle | 1 | bare actuator |
| Artificial bone | 2 | bare structure |
| Sheet steel | 3 | civilian plating |
| Steel | 6 | combat plating |
| Ceramic composite | 9 | ablative; degrades on stop-dead |
| Reactive | 12 | high-end |

## Determinism
Scatter, crit rolls, and ricochet paths all draw from the battle's seeded RNG. Deflection
angle is **pure geometry** — not random at all. Same seed + same actions = same spray. This
must be a test.
