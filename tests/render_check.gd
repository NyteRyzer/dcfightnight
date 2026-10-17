extends Node2D
## Renders every fighter x costume x pose (rotated, mirrored, with cape sway)
## and reports timing. Run with a display (or xvfb-run):
##   godot --path . --rendering-driver opengl3 res://tests/RenderCheck.tscn
## Engine "Invalid polygon" errors in the output indicate a broken shape.

const Rig = preload("res://scripts/combat/rig.gd")
const Poses = preload("res://scripts/combat/poses.gd")
var combos: Array = []
var idx := 0
var draws := 0
var usec := 0


func _ready() -> void:
	for id in Data.roster:
		for ci in Data.fighter(id)["costumes"].size():
			combos.append([id, ci])


func _process(_d: float) -> void:
	if idx >= combos.size():
		print("RENDER CHECK DONE: %d fighter draws, %.3f ms per draw" % [draws, usec / 1000.0 / maxf(1.0, draws)])
		get_tree().quit()
		return
	queue_redraw()


func _draw() -> void:
	if idx >= combos.size():
		return
	var id: String = combos[idx][0]
	var f: Dictionary = Data.fighter(id)
	var look: Dictionary = f["costumes"][combos[idx][1]]["look"]
	for pn in Poses.LIB:
		for sway in [0.0, 1.0]:
			for rot in [0.0, 90.0, 180.0, 270.0]:
				for fc in [1, -1]:
					var t0 := Time.get_ticks_usec()
					Rig.draw(self, Vector2(300, 300), fc, Poses.with_rot(Poses.get_pose(pn), rot), look, float(f["height"]), {"sway": sway, "time": 0.5})
					usec += Time.get_ticks_usec() - t0
					draws += 1
	idx += 1
