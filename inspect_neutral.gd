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
	stage.set("stage_uri", "res://unassigned_vert_test.usda")
func _process(_x) -> bool:
	frames += 1
	if frames > 800: printerr("TIMEOUT"); quit(1); return true
	return false
func _walk(n, cb):
	cb.call(n)
	for c in n.get_children(): _walk(c, cb)
func _on_done(ok):
	if done: return
	done = true
	var skels := []
	var meshes := []
	_walk(root, func(n):
		if n is Skeleton3D: skels.append(n)
		if n is MeshInstance3D: meshes.append(n))
	for sk in skels:
		var names := []
		for b in range(sk.get_bone_count()): names.append(str(sk.get_bone_name(b)))
		print("SKELETON '", sk.name, "' bones=", names)
	for mi in meshes:
		var mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0: continue
		var arr = mesh.surface_get_arrays(0)
		var b = arr[Mesh.ARRAY_BONES]; var wt = arr[Mesh.ARRAY_WEIGHTS]
		if b == null or b.is_empty(): 
			print("MESH '", mi.name, "' not skinned")
			continue
		var stride = b.size() / arr[Mesh.ARRAY_VERTEX].size()
		var report := []
		for v in range(arr[Mesh.ARRAY_VERTEX].size()):
			var bs := []
			var ws := []
			for k in range(stride): bs.append(b[v*stride+k]); ws.append(wt[v*stride+k])
			report.append("v%d bones=%s w=%s" % [v, str(bs), str(ws)])
		print("MESH '", mi.name, "' stride=", stride, " verts=", arr[Mesh.ARRAY_VERTEX].size())
		for r in report: print("   ", r)
	quit(0)
