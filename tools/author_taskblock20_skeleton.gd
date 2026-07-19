extends SceneTree

## taskblock-20 Pass A: one-time authoring pass — "the torso was always
## meant to be the struts connecting its sockets. The solid box hid the
## internals (reactor, matrix) behind geometry instead of behind
## cladding." Loads the real `torso.tres`, replaces its own solid-box
## `volume` (one box, 0.5 x 0.7 x 0.28, filling the whole chest cavity)
## with a thin strut skeleton, and re-saves it. Not a from-scratch
## re-author: every socket (and the reactor/matrix already mounted in
## theirs) is untouched — only the structural part's own volume shrinks.
## Run once via `godot --headless -s
## res://tools/author_taskblock20_skeleton.gd`; kept afterward as a
## record, same convention as every other `tools/author_taskblockNN_*.gd`.
##
## Three thin struts, all well inside `torso_cladding`'s own 0.53 x 0.73
## x 0.31 bounding box (the outer hit layer once this pass makes
## cladding load-bearing for silhouette) rather than reaching all the way
## to the shoulder/hip MOUNTING sockets (those are attachment points for
## the arm/leg assemblies, not meant to sit inside the torso's own
## visible silhouette): a central spine (the old box's own height), plus
## a shoulder-height and hip-height cross-brace, narrower than the
## cladding's own width so nothing pokes through it. Flagged geometry —
## a "recognizable ribcage-ish frame," not an anatomically exact
## skeleton; no dimensions were specified beyond "thin."

const OLD_CENTER := Vector3(0, 1.25, 0)


func _initialize() -> void:
	var path: String = "res://data/parts/torso.tres"
	var torso: Part = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if torso == null:
		push_error("Failed to load torso.tres")
		quit()
		return

	var spine := Box.new(OLD_CENTER, Vector3(0.1, 0.6, 0.1))
	var shoulder_brace := Box.new(Vector3(0.0, 1.5, 0.0), Vector3(0.4, 0.08, 0.08))
	var hip_brace := Box.new(Vector3(0.0, 0.95, 0.0), Vector3(0.3, 0.08, 0.08))
	torso.volume = [spine, shoulder_brace, hip_brace]

	var err: Error = ResourceSaver.save(torso, path)
	if err != OK:
		push_error("Failed to save %s: %s" % [path, err])
		quit()
		return
	print("Rebuilt torso.tres as a strut skeleton.")
	quit()
