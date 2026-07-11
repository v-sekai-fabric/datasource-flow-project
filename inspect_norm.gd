extends SceneTree
var stage; var done := false; var frames := 0
func _initialize() -> void:
	var d := DirAccess.open("user://usd_cache")
	if d:
		d.list_dir_begin(); var f := d.get_next()
		while f != "":
			if not d.current_is_dir(): d.remove(f)
			f = d.get_next()
	var w := Node3D.new(); root.add_child(w)
	stage = ClassDB.instantiate("UsdStageNode3D")
	w.add_child(stage); stage.connect("stage_loading_finished", _on_done)
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
	var mi = _find(root); var mesh = mi.mesh
	print("MODE=", mesh.blend_shape_mode, " (0=NORMALIZED 1=RELATIVE)")
	var bs = mesh.surface_get_blend_shape_arrays(0)
	# for Key_1, check stored normals are unit and how many differ from base surface normal
	var base = mesh.surface_get_arrays(0)
	var bN = base[Mesh.ARRAY_NORMAL]
	var s = bs[0]
	var aN = s[Mesh.ARRAY_NORMAL]
	var nonunit := 0; var differ := 0; var minlen := 9.9; var maxlen := 0.0
	for i in range(aN.size()):
		var l = aN[i].length()
		minlen = min(minlen,l); maxlen = max(maxlen,l)
		if abs(l-1.0) > 0.05: nonunit += 1
		if (aN[i]-bN[i]).length() > 0.02: differ += 1
	print("Key_1 storedNormals: len[%.3f..%.3f] nonUnit=%d differFromBase=%d /%d" % [minlen,maxlen,nonunit,differ,aN.size()])
	quit(0)
