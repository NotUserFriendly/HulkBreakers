class_name ResponseCurve
extends Resource

## taskblock-45 Pass A: how one normalized input becomes one normalized utility.
##
## A consideration asks a question with a 0–1 answer ("how hurt am I", "how close
## is the nearest threat") and this decides what that answer is *worth*. The same
## input drives wildly different behaviour depending on the curve over it, which
## is the whole reason a utility planner needs no per-behaviour code: a cautious
## profile and an aggressive one can share `own_hp_ratio` and disagree entirely
## about what a low value means.
##
## **Input and output are both clamped to 0–1.** That is not defensive tidying —
## the scorer multiplies these together and a value above 1 would let one
## consideration inflate a product rather than only ever damping it, which breaks
## the "every consideration can only veto or reduce" property the whole model
## rests on.
##
## `shape` is an open `StringName` (CLAUDE.md) with an unrecognised value falling
## back to linear rather than erroring, same posture as the playstyle vocabulary's
## own unknown-value fallback. **In practice the set is closed by the maths below** — a genuinely
## new shape needs a new arm here, not just new data — so this is the one place
## in the AI data model where "addable as data" does not fully hold, and it is
## flagged rather than pretended otherwise.

const LINEAR: StringName = &"linear"
const QUADRATIC: StringName = &"quadratic"
const LOGISTIC: StringName = &"logistic"
const STEP: StringName = &"step"

@export var shape: StringName = LINEAR
## Multiplies the curve's output before clamping. 1.0 is the identity.
@export var slope: float = 1.0
## Shifts the curve's output. 0.0 is the identity.
@export var offset: float = 0.0
## `quadratic`'s power, `logistic`'s steepness. Ignored by the others.
@export var exponent: float = 2.0
## `logistic`'s centre and `step`'s threshold — the input value the curve turns
## over at. Ignored by `linear`/`quadratic`.
@export var midpoint: float = 0.5
## True inverts the response: a high input becomes a low utility. Cheaper and far
## clearer at the authoring site than expressing "less is better" as a negative
## slope plus a compensating offset.
@export var invert: bool = false


func _init(
	p_shape: StringName = LINEAR,
	p_slope: float = 1.0,
	p_offset: float = 0.0,
	p_exponent: float = 2.0,
	p_midpoint: float = 0.5,
	p_invert: bool = false
) -> void:
	shape = p_shape
	slope = p_slope
	offset = p_offset
	exponent = p_exponent
	midpoint = p_midpoint
	invert = p_invert


## The utility of `input`, in 0–1. Total over every real input: an out-of-range
## or non-finite input is clamped rather than propagating a NaN into a product
## that would then poison every candidate's score silently.
func apply(input: float) -> float:
	var x: float = 0.0 if not is_finite(input) else clampf(input, 0.0, 1.0)
	if invert:
		x = 1.0 - x
	var y: float = _shape_value(x)
	return clampf(y * slope + offset, 0.0, 1.0)


func _shape_value(x: float) -> float:
	match shape:
		QUADRATIC:
			return pow(x, exponent)
		LOGISTIC:
			# Centred on `midpoint`, steepness from `exponent`. Written as a plain
			# logistic rather than a lookup so the authored numbers mean the usual
			# thing to anyone who has seen one before.
			return 1.0 / (1.0 + exp(-exponent * (x - midpoint)))
		STEP:
			return 1.0 if x >= midpoint else 0.0
		_:
			# `linear`, and anything unrecognised. Falling back rather than
			# erroring keeps a typo in authored data from taking a bout down.
			return x
