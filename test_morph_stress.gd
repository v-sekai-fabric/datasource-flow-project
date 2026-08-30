extends SceneTree

# Plays art/stress_test_animation/morph_stress_test.usda — rebuilt directly
# from Khronos's MorphStressTest.glb by make_morph_stress_from_gltf.py (no
# Blender in the chain). 8 shapes, 281 weight samples, no joint samples: the
# case joint-timecode sampling flattens to one rest key. Every shape's
# authored range is [0, 1] in the canonical source; the earlier 0.1754 peak
# on Key_8 was an artifact of the Blender-converted usdc this replaces.

const FIXTURE := "res://art/stress_test_animation/morph_stress_test.usda"
const CLIP_SECONDS := 8.0
# Authored per-shape max, printed by the generator from the GLB samplers.
const EXPECT_MAX := {
	"Key_1": 1.0, "Key_2": 1.0, "Key_3": 1.0, "Key_4": 1.0,
	"Key_5": 1.0, "Key_6": 1.0, "Key_7": 1.0, "Key_8": 1.0,
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

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

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
	# Structural fidelity: densely interpolate the imported tracks. A live frame
	# sweep cannot pin a one-sample-wide authored spike (Key_8 measured 0.845
	# at frame rate), but the track itself must carry the full curve.
	var sk := _find_skel(root)
	var anim: Animation = sk.get_animation() if sk and sk.has_method("get_animation") else null
	var track_max := {}
	if anim:
		for t in anim.get_track_count():
			if anim.track_get_type(t) != Animation.TYPE_BLEND_SHAPE:
				continue
			var nm := str(anim.track_get_path(t)).get_file()
			var mx := 0.0
			var tt := 0.0
			while tt <= anim.length:
				mx = max(mx, anim.blend_shape_track_interpolate(t, tt))
				tt += 0.001
			track_max[nm] = mx
	for nm in EXPECT_MAX:
		if not _hi.has(nm):
			printerr("FAIL: shape %s missing" % nm)
			failures += 1
			continue
		var want: float = EXPECT_MAX[nm]
		var tm: float = track_max.get(nm, -1.0)
		print("%s  live [%.3f, %.3f]  track max %.3f  authored %.3f" % [nm, _lo[nm], _hi[nm], tm, want])
		if abs(tm - want) > 0.01:
			printerr("FAIL: %s track max %.3f vs authored %.3f" % [nm, tm, want])
			failures += 1
		if _hi[nm] < 0.5:
			printerr("FAIL: %s barely moves live (max %.3f); playback is not driving it" % [nm, _hi[nm]])
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
