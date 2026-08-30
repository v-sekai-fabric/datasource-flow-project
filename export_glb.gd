extends SceneTree

# Exports the imported canonical-ANNY stage back out as GLB via Godot's own
# GLTFDocument, beside the source usda. Loading both into one scene should
# z-fight everywhere: any visible separation is a bake-path deviation.

func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var stage = ClassDB.instantiate("UsdStageNode3D")
	world.add_child(stage)
	stage.set("stage_uri", "res://art/canonical_anny/anny_anim_test.usdz")

var _frames := 0
func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 60:
		return false
	# The adapter plays animations from inside its nodes, so no AnimationPlayer
	# exists and GLTFDocument would export a static scene. Materialise one:
	# copy the skeleton's animation into a player-rooted clip with absolute
	# track paths (bones stay on the skeleton; blend tracks retarget to the
	# mesh instance that carries the shape).
	var scene_root: Node = root.get_child(0)
	var sk: Skeleton3D = null
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			sk = n
			break
		for c in n.get_children():
			stack.append(c)
	if sk != null and sk.has_method("get_animation") and sk.get_animation() != null:
		var src: Animation = sk.get_animation()
		var mi: MeshInstance3D = null
		for c in sk.get_children():
			if c is MeshInstance3D and c.get_blend_shape_count() > 0:
				mi = c
				break
		var player := AnimationPlayer.new()
		scene_root.add_child(player)
		player.owner = scene_root
		var sk_path := str(scene_root.get_path_to(sk))
		var mi_path := str(scene_root.get_path_to(mi)) if mi else ""
		# Source bone tracks carry full slashed USD joint paths, which cannot
		# ride in a :subname; the joint map resolves them to real bone names.
		var jmap: Dictionary = sk.get_joint_map()
		var clip := Animation.new()
		clip.length = src.length
		for t in src.get_track_count():
			var tt := src.track_get_type(t)
			var old_path := str(src.track_get_path(t))
			var nt := clip.add_track(tt)
			if tt == Animation.TYPE_BLEND_SHAPE:
				if mi == null:
					continue
				clip.track_set_path(nt, NodePath(mi_path + ":" + old_path.get_file()))
			else:
				var bi: int = jmap.get(NodePath(old_path), -1)
				if bi < 0:
					continue
				clip.track_set_path(nt, NodePath(sk_path + ":" + sk.get_bone_name(bi)))
			for k in src.track_get_key_count(t):
				clip.track_insert_key(nt, src.track_get_key_time(t, k), src.track_get_key_value(t, k))
		var lib := AnimationLibrary.new()
		lib.add_animation("anny_clip", clip)
		player.add_animation_library("", lib)
		print("animation player assembled: %d tracks, %.1f s" % [clip.get_track_count(), clip.length])

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root.get_child(0), state)
	if err != OK:
		printerr("FAIL: append_from_scene err=", err)
		quit(1)
		return true
	err = doc.write_to_filesystem(state, "res://art/canonical_anny/anny_anim_test.glb")
	if err != OK:
		printerr("FAIL: write_to_filesystem err=", err)
		quit(1)
		return true
	print("RESULT: PASS — wrote art/canonical_anny/anny_anim_test.glb")
	quit(0)
	return true
