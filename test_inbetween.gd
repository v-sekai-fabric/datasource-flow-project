extends SceneTree

# The primary is keyed 0 -> 1 -> 0 with an in-between authored at weight 0.5.
# Correct baking inserts keys at the crossing times, so the promoted in-between
# shape must peak near 1 mid-ramp and the primary near 1 at the top. A bake
# without crossing keys leaves the in-between track flat at 0 -- the corner is
# not merely cut, it is gone -- which is exactly what this fails on.

var _mi: MeshInstance3D = null
var _t0 := 0.0
var _frames := 0
var _hi := {}
var _lo := {}
var _primary_peak := -1.0
var _ib_at_peak := -1.0

func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	if not ClassDB.class_exists("UsdStageNode3D"):
		printerr("FAIL: UsdStageNode3D not registered")
		quit(1)
		return
	var stage = ClassDB.instantiate("UsdStageNode3D")
	world.add_child(stage)
	stage.set("stage_uri", "res://inbetween_anim.usda")

func _find(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.get_blend_shape_count() > 0:
		return node
	for c in node.get_children():
		var r := _find(c)
		if r:
			return r
	return null

func _process(_d: float) -> bool:
	_frames += 1
	if _mi == null:
		_mi = _find(root)
		if _mi != null:
			_t0 = Time.get_ticks_msec() / 1000.0
			print("shapes=", _mi.get_blend_shape_count())
			for i in _mi.get_blend_shape_count():
				var nm := str(_mi.mesh.get_blend_shape_name(i))
				_hi[nm] = -1e9
				_lo[nm] = 1e9
		elif _frames > 600:
			printerr("FAIL: no blend mesh")
			quit(1)
		return false
	var frame := {}
	for i in _mi.get_blend_shape_count():
		var nm := str(_mi.mesh.get_blend_shape_name(i))
		var v := _mi.get_blend_shape_value(i)
		frame[nm] = v
		_hi[nm] = max(_hi[nm], v)
		_lo[nm] = min(_lo[nm], v)
	# Phase: the two shapes trade places, so when the primary is at its top the
	# in-between must be near zero. An in-between wrongly given the primary's
	# own curve passes every min/max check and fails only here.
	if frame.get("lean", 0.0) > _primary_peak:
		_primary_peak = frame["lean"]
		_ib_at_peak = frame.get("lean__ib0", -1.0)
	if Time.get_ticks_msec() / 1000.0 - _t0 < 2.3:
		return false

	print("at primary peak %.3f the in-between reads %.3f" % [_primary_peak, _ib_at_peak])
	if _primary_peak > 0.9 and _ib_at_peak > 0.1:
		printerr("FAIL: in-between %.3f at primary peak; the shapes do not trade places" % _ib_at_peak)
		quit(1)
		return true

	var failures := 0
	if _hi.size() != 2:
		printerr("FAIL: expected the primary and one promoted in-between, got ", _hi.keys())
		failures += 1
	for nm in _hi:
		print("%s observed [%.3f, %.3f]" % [nm, _lo[nm], _hi[nm]])
		if _hi[nm] < 0.9:
			printerr("FAIL: %s never approaches 1 (max %.3f)" % [nm, _hi[nm]])
			failures += 1
		if _lo[nm] > 0.1:
			printerr("FAIL: %s never returns near 0 (min %.3f)" % [nm, _lo[nm]])
			failures += 1
	if failures == 0:
		print("RESULT: PASS — in-between peaks at its position, primary at the top")
		quit(0)
	else:
		printerr("RESULT: FAIL — %d assertion(s)" % failures)
		quit(1)
	return true
