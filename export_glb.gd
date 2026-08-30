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
