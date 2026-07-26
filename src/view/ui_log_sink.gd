class_name UiLogSink
extends LogSink

## taskblock-41 Pass A: the shared "render at most once per frame" seam for
## every combat-log sink that draws into a `RichTextLabel`.
##
## BR27.09 measured the cost this exists to remove: reassigning `label.text`
## in full costs ~175-180us at a 200-line scrollback, and a real 3v3 bout
## averages 9.9 events per turn with a peak of 29 — so a heavy turn used to
## pay ~5ms relaying text nobody scrolled to. That entry prescribes
## incremental `RichTextLabel.append_text` per new line, which fits `UISink`
## (genuinely append-only) but CANNOT fit `HierarchicalUiSink`: a new event
## there can rewrite an EXISTING group's summary rather than append a row,
## and expand/collapse re-renders everything. There is no correct
## incremental append against a folding model. Coalescing is correct for
## both, and — unlike a per-event optimization — its cost stops scaling with
## event count at all, which is what makes taskblock-41 Pass D's deliberate
## verbosity affordable rather than a regression.
##
## **`emit()` must still update the sink's own headless surface (`lines`)
## synchronously.** Only the `label` draw is deferred. `lines` is what every
## test without a SceneTree reads, and coalescing must not make the model
## lag the stream — the deferral is a render concern, never a model one.
##
## The frame tick comes from the owning Node (`ControlOverlay._process`),
## because a `RefCounted` sink has no frame of its own. A test drives
## `render_if_dirty()` directly with no SceneTree at all.

var label: RichTextLabel = null
var _dirty := false


## Marks the label stale. Called by `emit()` AFTER it has updated the
## model, never instead of updating it.
func mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


## The per-frame tick. Renders only if something arrived since the last
## render; returns whether a render actually happened, so a test can pin
## "N events in one frame produce exactly one render" as a real count
## rather than inferring it from output.
func render_if_dirty() -> bool:
	if not _dirty:
		return false
	render_now()
	return true


## The immediate path, for input that must not wait for a frame boundary —
## expand/collapse has to feel like it responded to the click, and a dirty
## flag that clears on the next frame would make clicks read as dropped.
func render_now() -> void:
	_dirty = false
	_render_label()


## Subclass hook: draw the current model into `label`. Always safe to call
## with no label attached.
func _render_label() -> void:
	pass
