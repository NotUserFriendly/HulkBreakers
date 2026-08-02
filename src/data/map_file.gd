class_name MapFile
extends Resource

## taskblock-53 Pass B: **a saved, height-aware map.** Nothing serialized before this — a
## `Grid` existed only as something `MapGen` produced or a fixture hand-built, so every AI
## diagnosis for eight blocks was done by hunting a seed. This turns *"find a seed that
## reproduces this"* into *"build the situation."*
##
## ## What a map owns, and what it deliberately does not
##
## A map is the **pristine, authored board**. It carries geometry and authoring intent:
## dimensions, placed surfaces with their heights and facings, blockers, field items, spawn
## markers and sight-blocking.
##
## It does **not** carry runtime state. `Grid.occupant_id` is who is standing where, which
## belongs to a bout and not to a map — a saved map with a unit baked into it would load a
## board that claims to be occupied by nobody. Part hp is likewise absent: parts are
## referenced by id and start intact (see `MapPlacement`).
##
## **This is a map format, not a savegame.** Saving a bout in progress is a different thing
## wanting different content, and conflating them is how a format acquires fields that are
## meaningless half the time.
##
## ## Sparse, and why
##
## `Grid` stores `spawn_marker` and `opacity` as dense per-cell arrays. A 40x30 board is
## 1200 entries of which perhaps eight are spawns — so both are stored here as parallel
## sparse pairs, cells alongside values. Dense arrays would make a hand-authored map
## unreadable and unreviewable, which is the one thing Pass B needs it to be.
##
## `opacity` is stored rather than derived. It correlates with wall blockers but is written
## independently (`MapGen` sets it, `DamageResolver` clears it when a blocker dies), so
## deriving it would invent a rule the engine does not actually follow.

## Human-facing, and the only field with no mechanical effect. A map that cannot be told
## apart from another in a list is a map nobody loads twice.
@export var map_name: String = ""
@export var width: int = 0
@export var rows: int = 0

## Every surface, blocker and field item, in authored order. Order matters within a cell:
## `Grid.surfaces` is an ordered array and `Surface.first_walkable` takes the first match.
@export var placements: Array[MapPlacement] = []

## Sparse spawn markers — parallel arrays, one marker per cell. `Enums.SpawnMarker` is a
## closed engine enum (which squad starts where is not content a designer extends), so this
## is an int rather than a `StringName`.
@export var spawn_cells: Array[Vector2i] = []
@export var spawn_markers: Array[int] = []

## Sparse sight-blocking — only cells with a non-zero value appear.
@export var opacity_cells: Array[Vector2i] = []
@export var opacity_values: Array[float] = []
