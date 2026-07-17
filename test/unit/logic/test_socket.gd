extends GutTest

## docs/09 taskblock06 Pass B: Socket.current_transform() is the seam a
## future rig posing system slots into — today a plain passthrough to the
## authored static `transform`, proven here so the seam itself has a test
## before anything real ever overrides it.


func test_current_transform_returns_the_authored_transform() -> void:
	var authored := Transform3D(Basis(Vector3.UP, PI / 3.0), Vector3(1.0, 2.0, 3.0))
	var socket := Socket.new(&"SHOULDER", authored, &"SHOULDER_L")

	assert_eq(socket.current_transform(), authored)


func test_current_transform_reflects_a_transform_changed_after_construction() -> void:
	var socket := Socket.new()
	var changed := Transform3D(Basis(), Vector3(5.0, 0.0, 0.0))
	socket.transform = changed

	assert_eq(socket.current_transform(), changed)
