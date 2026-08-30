extends SceneTree

# Plays art/stress_test_animation/morph_stress_test.usdc (8 shapes, 250 weight
# samples, NO joint samples — the case the old joint-timecode sampling flattened
# to one rest key) and compares each shape's observed range against the authored
# curves. Key_8's authored peak is 0.1754, not 1.0, so a track-order mixup or a
# normalisation error fails here even when "everything moved".

const FIXTURE := "res://art/stress_test_animation/morph_stress_test.usdc"
const CLIP_SECONDS := 250.0 / 30.0
# Authored per-shape max, read from the usdc with UsdSkel.Animation.
const EXPECT_MAX := {
	"Key_1": 1.0, "Key_2": 1.0, "Key_3": 1.0, "Key_4": 1.0,
	"Key_5": 1.0, "Key_6": 1.0, "Key_7": 1.0, "Key_8": 0.1754,
}
const TOL := 0.06

var _mi: MeshInstance3D = null
var _t0 := 0.0
var _lo := {}
var _hi := {}
var _frames := 0

func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	if not ClassDB.class_exists("UsdStageNode3D"):
		printerr("FAIL: UsdStageNode3D not registered")
		quit(1)
		return
	var stage = ClassDB.instantiate("UsdStageNode3D")
	world.add_child(stage)
	stage.set("stage_uri", FIXTURE)

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
		if _mi == null:
			if _frames > 600:
				printerr("FAIL: no blend-shape mesh appeared")
				quit(1)
			return false
		_t0 = Time.get_ticks_msec() / 1000.0
		print("mesh: ", _mi.name, " shapes=", _mi.get_blend_shape_count())
		for i in _mi.get_blend_shape_count():
			var nm := str(_mi.mesh.get_blend_shape_name(i))
			_lo[nm] = 1e9
			_hi[nm] = -1e9
		return false
	for i in _mi.get_blend_shape_count():
		var nm := str(_mi.mesh.get_blend_shape_name(i))
		var v := _mi.get_blend_shape_value(i)
		_lo[nm] = min(_lo[nm], v)
		_hi[nm] = max(_hi[nm], v)
	if Time.get_ticks_msec() / 1000.0 - _t0 < CLIP_SECONDS + 0.5:
		return false

	var failures := 0
	if _hi.size() != EXPECT_MAX.size():
		printerr("FAIL: %d shapes observed, %d expected" % [_hi.size(), EXPECT_MAX.size()])
		failures += 1
	for nm in EXPECT_MAX:
		if not _hi.has(nm):
			printerr("FAIL: shape %s missing" % nm)
			failures += 1
			continue
		var want: float = EXPECT_MAX[nm]
		print("%s  observed [%.3f, %.3f]  authored max %.3f" % [nm, _lo[nm], _hi[nm], want])
		if abs(_hi[nm] - want) > TOL:
			printerr("FAIL: %s max %.3f vs authored %.3f" % [nm, _hi[nm], want])
			failures += 1
		if _lo[nm] > TOL:
			printerr("FAIL: %s never returns near 0 (min %.3f)" % [nm, _lo[nm]])
			failures += 1
	if failures == 0:
		print("RESULT: PASS — all 8 shapes track their authored curves")
		quit(0)
	else:
		printerr("RESULT: FAIL — %d assertion(s)" % failures)
		quit(1)
	return true
