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
	var w := Node3D.new(); root.add_child(w)
	stage = ClassDB.instantiate("UsdStageNode3D")
	w.add_child(stage)
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
	var mesh = mi.mesh
	var base = mesh.surface_get_arrays(0)
	var bV = base[Mesh.ARRAY_VERTEX]
	var bN = base[Mesh.ARRAY_NORMAL]
	var bs = mesh.surface_get_blend_shape_arrays(0)
	for si in range(bs.size()):
		var s = bs[si]
		var aV = s[Mesh.ARRAY_VERTEX]
		var aN = s[Mesh.ARRAY_NORMAL]
		var moved := 0
		var nchg := 0
		var bleed := 0   # verts NOT moved but normal changed (non-independence)
		for i in range(bV.size()):
			var pm = (aV[i]-bV[i]).length() > 0.001
			var nm = (aN[i]-bN[i]).length() > 0.02
			if pm: moved += 1
			if nm: nchg += 1
			if nm and not pm: bleed += 1
		print("RESULT %s moved=%d normalChanged=%d bleed(normalChg_noMove)=%d /%d" % [str(mesh.get_blend_shape_name(si)), moved, nchg, bleed, bV.size()])
	quit(0)
