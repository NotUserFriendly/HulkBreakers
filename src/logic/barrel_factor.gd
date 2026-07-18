class_name BarrelFactor
extends RefCounted

## taskblock-13 Pass D/E: "longer barrel = better," shared between recoil
## (Pass D: divides down the dartboard-widening step) and spread (Pass E:
## divides down the mechanical pattern size) — one curve, tunable in one
## place, per the taskblock's own "reuse the same barrel_factor shape...
## sharing the curve keeps them coherent." Flagged placeholder shape (no
## concrete curve was ever specified) — ask before tuning.

## A floor, not zero — `barrel_length == 0.0` (Pass H's own "zero barrel
## length" hardening case) must read as "worst case," not divide-by-zero/
## NaN. Below this floor, the factor stops shrinking further.
const MIN_BARREL_LENGTH := 0.1


## Identity above the floor: a 1.0-length barrel divides by 1.0 (no
## change), a 2.0-length barrel halves whatever it divides.
static func value(barrel_length: float) -> float:
	return maxf(barrel_length, MIN_BARREL_LENGTH)
