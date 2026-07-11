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
	# base smoothing: normals per position
	var g = {}
	for i in range(bV.size()):
		var k = str(Vector3i(round(bV[i].x*4096),round(bV[i].y*4096),round(bV[i].z*4096)))
		if not g.has(k): g[k]=[]
		var nq = Vector3i(round(bN[i].x*64),round(bN[i].y*64),round(bN[i].z*64))
		if not g[k].has(nq): g[k].append(nq)
	var maxn=0
	for k in g: maxn=max(maxn,g[k].size())
	print("BASE uniquePos=%d maxNormalsPerPos=%d (3=respects flat cube, 1=forced-smooth)" % [g.size(), maxn])
	# independence
	var bs = mesh.surface_get_blend_shape_arrays(0)
	var totbleed = 0
	for si in range(bs.size()):
		var s = bs[si]
		var aV = s[Mesh.ARRAY_VERTEX]; var aN = s[Mesh.ARRAY_NORMAL]
		var bleed = 0
		for i in range(bV.size()):
			if (aV[i]-bV[i]).length() <= 0.001 and (aN[i]-bN[i]).length() > 0.02: bleed += 1
		totbleed += bleed
	print("INDEPENDENCE total_bleed(normalChg_without_move) across %d shapes = %d" % [bs.size(), totbleed])
	quit(0)
