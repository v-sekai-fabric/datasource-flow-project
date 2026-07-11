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
func _dump(n, depth):
	var extra := ""
	if n is Skeleton3D: extra = " [Skeleton bones=%d]" % n.get_bone_count()
	if n is MeshInstance3D:
		var sk = n.skin
		extra = " [MeshInstance skin=%s skeleton=%s]" % [str(n.skin != null), str(n.skeleton)]
	print("  ".repeat(depth), n.name, " <", n.get_class(), ">", extra)
	for c in n.get_children(): _dump(c, depth+1)
func _on_done(ok):
	if done: return
	done = true
	_dump(stage, 0)
	quit(0)
