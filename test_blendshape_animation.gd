extends SceneTree

# Headless check that an animated blendShapeWeights attribute actually moves the
# imported mesh's blend-shape value over time. The static fixture is the
# negative control: run with FIXTURE=res://blendshape_test.usda and the value
# must NOT move, or the pass on the animated fixture is decoration.

var fixture := "res://blendshape_anim_test.usda"
var expect_motion := true

var _frames := 0
var _samples: Array[float] = []
var _mi: MeshInstance3D = null
var _t0 := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			fixture = arg.get_slice("=", 1)
		if arg == "--expect-static":
			expect_motion = false
	var world := Node3D.new()
	root.add_child(world)
	if not ClassDB.class_exists("UsdStageNode3D"):
		printerr("FAIL: UsdStageNode3D not registered")
		quit(1)
		return
	var stage = ClassDB.instantiate("UsdStageNode3D")
	world.add_child(stage)
	print("loading ", fixture, " expect_motion=", expect_motion)
	stage.set("stage_uri", fixture)

func _find_blend_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.get_blend_shape_count() > 0:
		return node
	for c in node.get_children():
		var r := _find_blend_mesh(c)
		if r:
			return r
	return null

func _process(_delta: float) -> bool:
	_frames += 1
	if _mi == null:
		_mi = _find_blend_mesh(root)
		if _mi != null:
			_t0 = Time.get_ticks_msec() / 1000.0
			print("blend mesh found: ", _mi.name, " shapes=", _mi.get_blend_shape_count())
		elif _frames > 600:
			printerr("FAIL: no blend-shape mesh appeared")
			quit(1)
		return false
	_samples.append(_mi.get_blend_shape_value(0))
	var elapsed := Time.get_ticks_msec() / 1000.0 - _t0
	if elapsed < 1.5:
		return false
	var lo: float = _samples.min()
	var hi: float = _samples.max()
	print("samples=%d  min=%.3f  max=%.3f over %.2fs" % [_samples.size(), lo, hi, elapsed])
	if expect_motion:
		if hi - lo > 0.4 and hi > 0.5:
			print("RESULT: PASS — blend weight animates")
			quit(0)
		else:
			printerr("RESULT: FAIL — weight did not move (span %.3f)" % (hi - lo))
			quit(1)
	else:
		if hi - lo < 0.01:
			print("RESULT: PASS — static fixture stays still")
			quit(0)
		else:
			printerr("RESULT: FAIL — static fixture moved (span %.3f)" % (hi - lo))
			quit(1)
	return true
