extends SceneTree

# Canonical-ANNY phenotype-clip playback: the joints travel default-rest to
# heavy-rest and back while ph_weight rides 0 -> 1 -> 0 on the same keys, with
# the forearm bend overlaid. The pelvis must now MOVE mid-clip (the skeleton
# follows the phenotype) and must end where it started (loop closure); the
# unanimated fa_jawOpen shape is the stillness control.

const FIXTURE := "res://art/canonical_anny/anny_anim_test.usdz"
const BEND_BONE := "lowerarm01_L"   # sanitised from lowerarm01.L
const PHENO_BONE := "upperleg01_L"  # largest skeletal move under weight=1: 2.18 mm

var _sk: Skeleton3D = null
var _mi: MeshInstance3D = null
var _t0 := 0.0
var _frames := 0
var _settle := 0
var _rest_bend: Quaternion
var _bend0: Quaternion
var _pheno0: Vector3
var _rest_pheno: Vector3
var _bend_max_deg := 0.0
var _pheno_mm := 0.0
var _pheno_min_mm := 1e9
var _w_lo := 1e9
var _w_hi := -1e9
var _still_hi := 0.0
var _animated_idx := -1
var _still_idx := -1

func _find_shape(name: String) -> int:
	for i in _mi.get_blend_shape_count():
		if str(_mi.mesh.get_blend_shape_name(i)) == name:
			return i
	return -1

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

func _find(node: Node) -> void:
	if _sk == null and node is Skeleton3D:
		_sk = node
	if _mi == null and node is MeshInstance3D and node.get_blend_shape_count() > 0:
		_mi = node
	for c in node.get_children():
		_find(c)

func _angle_between(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(a.angle_to(b))

func _process(_delta: float) -> bool:
	_frames += 1
	if _sk == null or _mi == null:
		_find(root)
		if _sk != null and _mi != null:
			var bi := _sk.find_bone(BEND_BONE)
			var hi := _sk.find_bone(PHENO_BONE)
			if bi < 0 or hi < 0:
				printerr("FAIL: bones not found (%s=%d, %s=%d) of %d" %
					[BEND_BONE, bi, PHENO_BONE, hi, _sk.get_bone_count()])
				quit(1)
				return true
			_rest_bend = _sk.get_bone_pose_rotation(bi)
			_rest_pheno = _sk.get_bone_pose_position(hi)
			_animated_idx = _find_shape("ph_weight")
			_still_idx = _find_shape("fa_jawOpen")
			print("skeleton bones=%d, blend shapes=%d" %
				[_sk.get_bone_count(), _mi.get_blend_shape_count()])
			if _mi.get_blend_shape_count() != 317:
				printerr("FAIL: expected 317 shapes (11 phenotypes + 52 facial actions + 254 local changes)")
				quit(1)
				return true
			var clips: Dictionary = _sk.get_animations()
			if clips.size() != 11 or not clips.has("clip_ph_weight"):
				printerr("FAIL: expected 11 independent phenotype clips, got %d %s" % [clips.size(), clips.keys()])
				quit(1)
				return true
			# Composability evidence: two different clips end (t=2 s) driving two
			# DIFFERENT shapes to 1 -- each clip owns exactly one axis, so any
			# pair can be blended without fighting over a track.
			var a: Animation = clips["clip_ph_weight"]
			var b: Animation = clips["clip_ph_muscle"]
			var a_shape := ""
			var b_shape := ""
			for t in a.get_track_count():
				if a.track_get_type(t) == Animation.TYPE_BLEND_SHAPE and a.blend_shape_track_interpolate(t, 2.0) > 0.99:
					a_shape = str(a.track_get_path(t)).get_file()
			for t in b.get_track_count():
				if b.track_get_type(t) == Animation.TYPE_BLEND_SHAPE and b.blend_shape_track_interpolate(t, 2.0) > 0.99:
					b_shape = str(b.track_get_path(t)).get_file()
			if a_shape != "ph_weight" or b_shape != "ph_muscle":
				printerr("FAIL: clips do not each own their axis (got %s / %s)" % [a_shape, b_shape])
				quit(1)
				return true
			print("independent clips: 11; clip_ph_weight -> %s at 1.0, clip_ph_muscle -> %s at 1.0" % [a_shape, b_shape])
			if _animated_idx < 0 or _still_idx < 0:
				printerr("FAIL: ph_weight or fa_jawOpen shape missing")
				quit(1)
				return true
		elif _frames > 900:
			printerr("FAIL: skeleton or blend mesh never appeared")
			quit(1)
		return false

	var bi := _sk.find_bone(BEND_BONE)
	var hi := _sk.find_bone(PHENO_BONE)
	_settle += 1
	if _settle <= 2:
		# Playback baseline, taken once the animation drives the pose. The gap
		# between the imported rest and this first applied frame is reported
		# below as a finding of its own, not asserted here: this test's claim
		# is the dynamics.
		_bend0 = _sk.get_bone_pose_rotation(bi)
		_pheno0 = _sk.get_bone_pose_position(hi)
		_t0 = Time.get_ticks_msec() / 1000.0
		if _settle == 2:
			print("rest -> applied offset: bend %.1f deg" % _angle_between(_rest_bend, _bend0))
		return false
	_bend_max_deg = max(_bend_max_deg, _angle_between(_bend0, _sk.get_bone_pose_rotation(bi)))
	var dist := (_sk.get_bone_pose_position(hi) - _rest_pheno).length() * 1000.0
	_pheno_mm = max(_pheno_mm, dist)
	_pheno_min_mm = min(_pheno_min_mm, dist)
	var w := _mi.get_blend_shape_value(_animated_idx)
	_w_lo = min(_w_lo, w)
	_w_hi = max(_w_hi, w)
	_still_hi = max(_still_hi, absf(_mi.get_blend_shape_value(_still_idx)))

	if Time.get_ticks_msec() / 1000.0 - _t0 < 2.6:
		return false

	# A number without a baseline is not a measurement: 2.18 mm is the AUTHORED
	# skeletal travel of this joint under weight=1, printed beside the reading.
	print("forearm travel %.1f deg, upperleg phenotype [%.2f, %.2f] mm of authored 2.18, ph_weight [%.3f, %.3f]" %
		[_bend_max_deg, _pheno_min_mm, _pheno_mm, _w_lo, _w_hi])
	var failures := 0
	if _bend_max_deg < 45.0:
		printerr("FAIL: forearm travelled %.1f deg, expected toward 90" % _bend_max_deg)
		failures += 1
	# The player loops the clip, so closure is periodic rather than terminal:
	# each cycle the bone must reach the phenotype AND pass back through rest.
	if _pheno_mm < 1.5:
		printerr("FAIL: upperleg reached %.2f mm; the skeleton must move with the phenotype (authored 2.18 mm)" % _pheno_mm)
		failures += 1
	if _pheno_min_mm > 0.3:
		printerr("FAIL: upperleg never returns within %.2f mm of rest; the loop does not close" % _pheno_min_mm)
		failures += 1
	if _w_hi - _w_lo < 0.4 or _w_hi < 0.5:
		printerr("FAIL: ph_weight span [%.3f, %.3f], expected 0 toward 1" % [_w_lo, _w_hi])
		failures += 1
	if _still_hi > 0.01:
		printerr("FAIL: fa_jawOpen moved to %.3f; unanimated shapes must hold at rest" % _still_hi)
		failures += 1
	if failures == 0:
		print("RESULT: PASS — joints and phenotype blendshape both animate, control holds")
		quit(0)
	else:
		printerr("RESULT: FAIL — %d assertion(s)" % failures)
		quit(1)
	return true
