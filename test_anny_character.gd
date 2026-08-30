extends SceneTree

# Composition through the engine's own machinery: an AnimationTree of Add2
# nodes over delta clips, one parameter per phenotype axis. weight=1 and
# muscle=1 together must drive BOTH shapes to ~1 (single-timeline segments
# cannot do this), move the probe bone further than either axis alone, and
# setting both back to 0 must return the pose to rest.

var _char: AnnyCharacter = null
var _phase := 0
var _t0 := 0.0
var _w_only := 0.0
var _frames := 0

func _initialize() -> void:
	_char = AnnyCharacter.new()
	root.add_child(_char)
	var stage = ClassDB.instantiate("UsdStageNode3D")
	_char.add_child(stage)
	stage.set("stage_uri", "res://art/canonical_anny/anny_anim_test.usdz")

func _shape(name: String) -> float:
	for i in _char.mesh.get_blend_shape_count():
		if str(_char.mesh.mesh.get_blend_shape_name(i)) == name:
			return _char.mesh.get_blend_shape_value(i)
	return -1.0

func _probe_mm() -> float:
	var bi := _char.skeleton.find_bone("upperleg01_L")
	var rest := _char.skeleton.get_bone_rest(bi).origin
	return (_char.skeleton.get_bone_pose_position(bi) - rest).length() * 1000.0

func _process(_d: float) -> bool:
	_frames += 1
	if _phase == 0:
		if _char.skeleton == null:
			if not _char.build():
				if _frames > 600:
					printerr("FAIL: character never built")
					quit(1)
				return false
			print("tree built: %d axes" % _char.axes.size())
			for a in _char.axes:
				_char.set_phenotype(a, 0.0)
			_char.set_phenotype("ph_weight", 1.0)
			_phase = 1
			_t0 = Time.get_ticks_msec() / 1000.0
		return false
	if Time.get_ticks_msec() / 1000.0 - _t0 < 2.5:
		return false

	if _phase == 1:
		_w_only = _probe_mm()
		print("weight only: probe %.2f mm, ph_weight %.3f" % [_w_only, _shape("ph_weight")])
		_char.set_phenotype("ph_muscle", 1.0)
		_phase = 2
		_t0 = Time.get_ticks_msec() / 1000.0
		return false
	if _phase == 2:
		var both := _probe_mm()
		var w := _shape("ph_weight")
		var m := _shape("ph_muscle")
		print("composed: probe %.2f mm (weight-only %.2f), ph_weight %.3f, ph_muscle %.3f" %
			[both, _w_only, w, m])
		var failures := 0
		if w < 0.9 or m < 0.9:
			printerr("FAIL: shapes do not compose (%.3f, %.3f); both must be near 1" % [w, m])
			failures += 1
		if both < _w_only + 0.2:
			printerr("FAIL: probe %.2f mm not beyond weight-only %.2f; the skeletons do not add" % [both, _w_only])
			failures += 1
		if failures > 0:
			printerr("RESULT: FAIL")
			quit(1)
			return true
		_char.set_phenotype("ph_weight", 0.0)
		_char.set_phenotype("ph_muscle", 0.0)
		_phase = 3
		_t0 = Time.get_ticks_msec() / 1000.0
		return false
	# phase 3: zeroed sliders must return to rest — the control that the tree
	# subtracts what it added rather than accumulating.
	var back := _probe_mm()
	var w0 := _shape("ph_weight")
	print("zeroed: probe %.2f mm, ph_weight %.3f" % [back, w0])
	if back > 0.3 or w0 > 0.02:
		printerr("RESULT: FAIL — sliders at 0 do not return to rest")
		quit(1)
	else:
		print("RESULT: PASS — phenotype clips compose through the AnimationTree and return to rest")
		quit(0)
	return true
