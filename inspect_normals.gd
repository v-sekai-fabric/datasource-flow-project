extends SceneTree
var stage
var done := false
var frames := 0
func _initialize() -> void:
	# clear converted-scene cache so the new DLL reconverts
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
	stage.set("stage_uri", "res://blendshape_test.usda")
func _process(_d) -> bool:
	frames += 1
	if frames > 800:
		printerr("TIMEOUT"); quit(1); return true
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
	print("RESULT bs_count=", mesh.get_blend_shape_count(), " mode=", mesh.blend_shape_mode)
	var base = mesh.surface_get_arrays(0)
	var baseN = base[Mesh.ARRAY_NORMAL]
	var baseV = base[Mesh.ARRAY_VERTEX]
	var bsarr = mesh.surface_get_blend_shape_arrays(0)
	for si in range(bsarr.size()):
		var nm = str(mesh.get_blend_shape_name(si))
		var s = bsarr[si]
		# surface_get_blend_shape_arrays returns ABSOLUTE (base+delta)
		var absV = s[Mesh.ARRAY_VERTEX]
		var absN = s[Mesh.ARRAY_NORMAL]
		# recover deltas
		var maxNd := 0.0
		var changed := 0
		for i in range(baseN.size()):
			var nd = (absN[i] - baseN[i]).length()
			maxNd = max(maxNd, nd)
			if nd > 0.01: changed += 1
		# For "thin": flattened cube -> top/bottom faces normals should be ~ +/-Y.
		# report the spread of absolute morphed normals
		print("  shape[", si, "] '", nm, "' max_normal_delta=", "%.3f" % maxNd, " verts_with_normal_change=", changed, "/", baseN.size())
	quit(0)
