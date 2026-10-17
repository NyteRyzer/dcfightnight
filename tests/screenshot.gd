extends Node
## Dev helper: renders scenes and saves PNG screenshots.
## xvfb-run godot --path . --rendering-driver opengl3 res://tests/Screenshot.tscn -- <out_dir> [shots...]
## shots: menu select stage fight:<p1>:<p2>:<stage>:<frames> story training

var out_dir := "user://shots"
var shots: Array = []
var current: Node = null
var wait := 0
var name_s := ""
var after := 0


class PoseSheet extends Node2D:
	const Rig = preload("res://scripts/combat/rig.gd")
	const Poses = preload("res://scripts/combat/poses.gd")
	var poses: Array = []

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 640, 360), Color(0.25, 0.27, 0.33))
		var ids: Array = Data.roster
		for r in poses.size():
			for c in ids.size():
				var f: Dictionary = Data.fighter(ids[c])
				var pname: String = poses[r]
				if pname == "S" or pname == "fS" or pname == "bS" or pname == "dS":
					var mp: Array = f["moves"][pname].get("pose", ["idle"])
					pname = mp[mp.size() - 1]
				var origin := Vector2(36 + c * 71, 112 + r * 118)
				draw_set_transform(origin, 0.0, Vector2(0.55, 0.55))
				Rig.draw(self, Vector2.ZERO, 1, Poses.get_pose(pname), f["look"], float(f["height"]))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_line(origin + Vector2(-30, 0), origin + Vector2(30, 0), Color(0, 0, 0, 0.4), 1.0)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	shots = args.slice(1) if args.size() > 1 else ["menu", "select", "stage", "fight:flash:green_arrow:star_labs:400", "story"]
	DirAccess.make_dir_recursive_absolute(out_dir)


func _process(_d: float) -> void:
	if current == null:
		if shots.is_empty():
			get_tree().quit()
			return
		_start(shots.pop_front())
		return
	wait -= 1
	if wait <= 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(name_s + ".png"))
		print("saved ", name_s)
		current.queue_free()
		current = null
		get_tree().paused = false


func _start(s: String) -> void:
	var parts := s.split(":")
	name_s = s.replace(":", "_")
	wait = 40
	match parts[0]:
		"sheet":
			current = PoseSheet.new()
			current.poses = parts.slice(1)
			wait = 4
		"menu":
			current = load("res://scenes/ui/MainMenu.tscn").instantiate()
		"select":
			Game.mode = "versus"
			current = load("res://scenes/ui/CharacterSelect.tscn").instantiate()
		"stage":
			current = load("res://scenes/ui/StageSelect.tscn").instantiate()
		"options":
			current = load("res://scenes/ui/Options.tscn").instantiate()
		"story":
			Game.story_cards = Data.story["intro"]
			Game.story_next = "menu"
			current = load("res://scenes/story/StoryScene.tscn").instantiate()
			wait = 200
		"fight", "training":
			Game.chars = [parts[1], parts[2]]
			Game.stage_id = parts[3]
			Game.alt = [false, parts[1] == parts[2]]
			Game.fight_opts = {}
			Game.cpu = [true, true]
			Game.mode = "training" if parts[0] == "training" else "cpu_vs_cpu"
			if parts[0] == "training":
				Game.training["boxes"] = true
			current = load("res://scenes/fight/TrainingRoom.tscn" if parts[0] == "training" else "res://scenes/fight/FightStage.tscn").instantiate()
			wait = int(parts[4]) if parts.size() > 4 else 300
	add_child(current)
	if parts[0] == "fight":
		current.enable_autoplay()
