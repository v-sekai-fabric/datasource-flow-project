extends SceneTree

# Headless import test for issue #24 (blend shapes). Loads a USD skinned mesh
# with a UsdSkelBlendShape via the IDTXFlow GDExtension and asserts the resulting
# Godot mesh carries the morph target, its name, its per-vertex delta, and the
# animation-driven weight.

const FIXTURE := "res://blendshape_test.usda"

var _stage
var _done := false
var _frames := 0

func _initialize() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	if not ClassDB.class_exists("UsdStageNode3D"):
		printerr("FAIL: UsdStageNode3D not registered — extension did not load")
		quit(1)
		return

	_stage = ClassDB.instantiate("UsdStageNode3D")
	world.add_child(_stage)
	_stage.connect("stage_loading_finished", Callable(self, "_on_loaded"))
	print("setting stage uri: ", FIXTURE)
	_stage.set("stage_uri", FIXTURE)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames > 600:
		printerr("FAIL: timed out waiting for stage_loading_finished")
		quit(1)
		return true
	return false

func _find_mesh_instances(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_find_mesh_instances(c, out)

func _on_loaded(success: bool) -> void:
	if _done:
		return
	_done = true
	print("stage_loading_finished success=", success)

	var meshes: Array = []
	_find_mesh_instances(root, meshes)
	print("MeshInstance3D count: ", meshes.size())

	var failures := 0
	var checked_blendshape := false
	for mi in meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var bsc: int = mesh.get_blend_shape_count()
		print("  mesh '", mi.name, "' surfaces=", mesh.get_surface_count(), " blend_shapes=", bsc)
		if bsc == 0:
			continue
		checked_blendshape = true
		for b in range(bsc):
			var nm: StringName = mesh.get_blend_shape_name(b)
			var val: float = mi.get_blend_shape_value(b)
			print("    blend_shape[", b, "] name='", nm, "' value=", val)
			if str(nm) != "smile":
				printerr("    FAIL: expected name 'smile', got '", nm, "'")
				failures += 1
			if abs(val - 0.75) > 0.001:
				printerr("    FAIL: expected weight 0.75, got ", val)
				failures += 1
		# read the blend-shape delta array straight off the surface and confirm
		# only the two top vertices carry the (0, 0.5, 0) offset.
		var arrays := mesh.surface_get_blend_shape_arrays(0)
		if arrays.size() >= 1:
			var shape0: Array = arrays[0]
			var verts: PackedVector3Array = shape0[Mesh.ARRAY_VERTEX]
			var moved := 0
			var max_y := 0.0
			for v in verts:
				if v.length() > 0.0001:
					moved += 1
					max_y = max(max_y, v.y)
			print("    delta: moved_vertices=", moved, " max_y=", max_y, " (total verts=", verts.size(), ")")
			if not is_equal_approx(max_y, 0.5):
				printerr("    FAIL: expected max delta y 0.5, got ", max_y)
				failures += 1
			if moved == 0:
				printerr("    FAIL: no vertices carry a delta")
				failures += 1

	if not checked_blendshape:
		printerr("FAIL: no mesh with blend shapes found")
		failures += 1

	if failures == 0:
		print("RESULT: PASS — blend shapes imported correctly")
		quit(0)
	else:
		printerr("RESULT: FAIL — ", failures, " assertion(s) failed")
		quit(1)
