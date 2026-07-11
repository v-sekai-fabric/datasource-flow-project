extends SceneTree
var stage
var done := false
var frames := 0
func _initialize() -> void:
	var d := DirAccess.open("user://usd_cache")
	if d:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if not d.current_is_dir(): d.remove(f)
			f = d.get_next()
	var world := Node3D.new(); root.add_child(world)
	stage = ClassDB.instantiate("UsdStageNode3D")
	world.add_child(stage)
	stage.connect("stage_loading_finished", _on_done)
	stage.set("stage_uri", "res://morph_stress_test.usda")
func _process(_x) -> bool:
	frames += 1
	if frames > 800: printerr("TIMEOUT"); quit(1); return true
	return false
func _find(n):
	if n is MeshInstance3D: return n
	for c in n.get_children():
		var r = _find(c)
		if r: return r
	return null
func _on_done(ok):
	if done: return
	done = true
	var mi = _find(root)
	if mi == null: printerr("no mesh"); quit(1); return
	var mesh = mi.mesh
	var base = mesh.surface_get_arrays(0)
	var bN = base[Mesh.ARRAY_NORMAL]
	var bV = base[Mesh.ARRAY_VERTEX]
	var bsarr = mesh.surface_get_blend_shape_arrays(0)
	for si in range(bsarr.size()):
		var s = bsarr[si]
		var aV = s[Mesh.ARRAY_VERTEX]
		var aN = s[Mesh.ARRAY_NORMAL]
		var mp := 0.0
		var mn := 0.0
		for i in range(bN.size()):
			mp = max(mp, (aV[i]-bV[i]).length())
			mn = max(mn, (aN[i]-bN[i]).length())
		print("RESULT ", str(mesh.get_blend_shape_name(si)), " maxPosDelta=%.3f maxNrmDelta=%.3f" % [mp, mn])
	quit(0)
