class_name AnnyCharacter
extends Node3D

# Character-controller wiring over the flow adapter's clip library: an
# AnimationPlayer holds DELTA versions of the eleven phenotype clips (Godot's
# additive blend nodes expect deltas, and the imported clips are absolute), and
# an AnimationTree chains Add2 nodes so each axis is one parameter. Composition
# is then the engine's own: weight=1 and muscle=1 blend additively instead of
# fighting over tracks.

var skeleton: Skeleton3D
var mesh: MeshInstance3D
var tree: AnimationTree
var axes: Array[String] = []

static func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for c in root.get_children():
		var r := find_skeleton(c)
		if r:
			return r
	return null

func _delta_clip(src: Animation, sk_path: String, mi_path: String, jmap: Dictionary) -> Animation:
	var clip := Animation.new()
	clip.length = src.length
	for t in src.get_track_count():
		var tt := src.track_get_type(t)
		var old_path := str(src.track_get_path(t))
		if tt == Animation.TYPE_BLEND_SHAPE:
			var nt := clip.add_track(tt)
			clip.track_set_path(nt, NodePath(mi_path + ":" + old_path.get_file()))
			for k in src.track_get_key_count(t):
				clip.track_insert_key(nt, src.track_get_key_time(t, k), src.track_get_key_value(t, k))
			continue
		var bi: int = jmap.get(NodePath(old_path), -1)
		if bi < 0:
			continue
		var path := NodePath(sk_path + ":" + skeleton.get_bone_name(bi))
		var nt := clip.add_track(tt)
		clip.track_set_path(nt, path)
		# Values stay ABSOLUTE: Godot's additive blend subtracts the rest pose
		# itself, so pre-subtracting here double-counts (measured: a 2.18 mm
		# authored delta probed 100.47 mm -- the rest origin's own length).
		for k in src.track_get_key_count(t):
			clip.track_insert_key(nt, src.track_get_key_time(t, k), src.track_get_key_value(t, k))
	return clip

func build() -> bool:
	skeleton = find_skeleton(self)
	if skeleton == null or not skeleton.has_method("get_animations"):
		return false
	for c in skeleton.get_children():
		if c is MeshInstance3D and c.get_blend_shape_count() > 0:
			mesh = c
			break
	var clips: Dictionary = skeleton.get_animations()
	if clips.is_empty():
		return false
	var jmap: Dictionary = skeleton.get_joint_map()
	var sk_path := str(get_path_to(skeleton))
	var mi_path := str(get_path_to(mesh)) if mesh else ""

	# Stop the adapter's internal playback: the tree owns the pose from here.
	skeleton.set_animation(null)
	if mesh and mesh.has_method("set_animation"):
		mesh.set_animation(null)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)
	var lib := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.001
	lib.add_animation("RESET", reset)
	for clip_name in clips:
		lib.add_animation(clip_name, _delta_clip(clips[clip_name], sk_path, mi_path, jmap))
	player.add_animation_library("", lib)

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	var bt := AnimationNodeBlendTree.new()
	var prev := "rest"
	var rest_node := AnimationNodeAnimation.new()
	rest_node.animation = "RESET"
	bt.add_node("rest", rest_node)
	axes.clear()
	for clip_name in clips:
		var axis: String = str(clip_name).trim_prefix("clip_")
		axes.append(axis)
		var an := AnimationNodeAnimation.new()
		an.animation = clip_name
		bt.add_node("anim_" + axis, an)
		var add := AnimationNodeAdd2.new()
		bt.add_node("add_" + axis, add)
		bt.connect_node("add_" + axis, 0, prev)
		bt.connect_node("add_" + axis, 1, "anim_" + axis)
		prev = "add_" + axis
	bt.connect_node("output", 0, prev)
	tree.tree_root = bt
	tree.active = true
	return true

func set_phenotype(axis: String, amount: float) -> void:
	tree.set("parameters/add_%s/add_amount" % axis, clampf(amount, 0.0, 1.0))
