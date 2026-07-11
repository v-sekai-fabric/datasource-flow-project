extends Node3D

var mi: MeshInstance3D
var stage

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.4, 3.2), Vector3(0, 0.2, 0), Vector3.UP)
	cam.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.2
	add_child(light)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.15, 0.15, 0.18)
	e.ambient_light_energy = 0.4
	we.environment = e
	add_child(we)

	stage = ClassDB.instantiate("UsdStageNode3D")
	add_child(stage)
	stage.connect("stage_loading_finished", _on_loaded)
	stage.set("stage_uri", "res://dome.usda")

func _find_mi(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mi(c)
		if r:
			return r
	return null

func _on_loaded(success: bool) -> void:
	mi = _find_mi(self)
	if mi == null:
		printerr("RENDER: no mesh instance found")
		get_tree().quit(1)
		return
	# neutral white, double-sided material so culling can't confuse the shading test
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.8, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	print("RENDER: mesh '", mi.name, "' blend_shapes=", mi.mesh.get_blend_shape_count())
	print("RENDER: mesh AABB=", mi.get_aabb(), " gxform=", mi.global_transform.origin)
	await _capture(0.0, "C:/Users/ernes/Desktop/flow-project/dome_w0.png")
	await _capture(1.0, "C:/Users/ernes/Desktop/flow-project/dome_w1.png")
	print("RENDER: done")
	get_tree().quit(0)

func _capture(w: float, path: String) -> void:
	for b in mi.mesh.get_blend_shape_count():
		mi.set_blend_shape_value(b, w)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("RENDER: saved ", path, " weight=", w)
