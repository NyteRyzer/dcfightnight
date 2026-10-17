extends Node
## End-to-end flow test: drives Story, Arcade, Survival, Versus and Training
## through real scene changes by pulsing the confirm button and forcing
## round results. Run headless:
##   godot --headless --path . --fixed-fps 60 res://tests/FlowTest.tscn

const LIMIT := 60 * 60 * 20

var flows := ["story", "arcade", "survival", "versus", "training"]
var flow := ""
var frames := 0
var flow_frames := 0
var fights := {}
var seen: Array = []
var last_scene := ""
var failures: Array = []
var survival_rounds := 0
var pulse_held := false
var saved_backup: Dictionary = {}


func _ready() -> void:
	saved_backup = Game.save.duplicate()
	Game.settings["round_time"] = 99
	Game.settings["rounds"] = 2
	Game.save = {"story_done": false, "arcade_done": false, "story_progress": 0}
	_reparent.call_deferred()


func _reparent() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.goto("menu")


func _scene() -> Node:
	return get_tree().current_scene


func _scene_name() -> String:
	var s := _scene()
	return s.name if s != null else ""


func _fail(msg: String) -> void:
	failures.append(msg)
	printerr("FAIL [%s]: %s" % [flow, msg])


func _start_next() -> void:
	if flows.is_empty():
		_report()
		return
	flow = flows.pop_front()
	flow_frames = 0
	fights[flow] = 0
	print("--- flow: ", flow)
	match flow:
		"story":
			Game.start_story(0)
		"arcade":
			Game.start_arcade("supergirl")
		"survival":
			Game.start_survival("wild_dog")
		"versus":
			Game.mode = "versus"
			Game.chars = ["vibe", "black_canary"]
			Game.cpu = [false, false]
			Game.alt_pref = [false, true]
			Game.stage_id = "national_city"
			Game.fight_opts = {}
			Game.begin_fight()
		"training":
			Game.mode = "training"
			Game.chars = ["martian_manhunter", "citizen_steel"]
			Game.cpu = [false, true]
			Game.stage_id = "arrow_bunker"
			Game.fight_opts = {}
			Game.begin_fight()


func _process(_d: float) -> void:
	frames += 1
	flow_frames += 1
	if pulse_held:
		Input.action_release("p1_light")
		pulse_held = false
	var name_s := _scene_name()
	if name_s != last_scene:
		last_scene = name_s
		seen.append("%s:%s" % [flow, name_s])
		flow_frames = mini(flow_frames, 1) if name_s == "" else flow_frames
	if frames > LIMIT:
		_fail("global time limit reached in scene %s" % name_s)
		_report()
		return
	match name_s:
		"MainMenu":
			if flow_frames > 20 or flow == "":
				_start_next()
			return
		"FightStage", "TrainingRoom":
			_drive_fight(_scene())
			return
		"Credits":
			if flow_frames > 30:
				Game.goto("menu")
			return
	if flow_frames % 12 == 0:
		Input.action_press("p1_light")
		pulse_held = true


func _drive_fight(f: Node) -> void:
	if f.training:
		if flow_frames > 200:
			if f.fighters[0].health <= 0:
				_fail("training fighter died")
			Game.goto("menu")
		return
	match f.phase:
		"vs", "intro":
			pass
		"fight":
			if f.fighters[0].controlled and f.pt % 4 == 0:
				var lose: bool = flow == "survival" and survival_rounds >= 2
				f.fighters[0 if lose else 1].health = 0.0
		"result":
			if f.pt == 2:
				fights[flow] += 1
				print("  fight %d done (%s vs %s @ %s) winner P%d" % [fights[flow], Game.chars[0], Game.chars[1], Game.stage_id, f.match_winner + 1])
			if flow == "versus" and f.pt == 61:
				Game.goto("menu")
				return
			if flow == "survival" and f.pt == 61:
				survival_rounds += 1
				if f.match_winner == 0:
					Game.survival_won(1.0)
				else:
					Game.goto("menu")
				return
			if flow in ["story", "arcade"] and f.pt > 40 and f.pt % 12 == 0:
				Input.action_press("p1_light")
				pulse_held = true


func _report() -> void:
	var chapters: int = Data.story["chapters"].size()
	if fights.get("story", 0) != chapters:
		_fail("story ran %d fights, expected %d" % [fights.get("story", 0), chapters])
	if fights.get("arcade", 0) != 7:
		_fail("arcade ran %d fights, expected 7" % fights.get("arcade", 0))
	if fights.get("survival", 0) < 3:
		_fail("survival ran %d fights" % fights.get("survival", 0))
	if fights.get("versus", 0) != 1:
		_fail("versus ran %d fights" % fights.get("versus", 0))
	if not Game.save.get("story_done", false):
		_fail("story completion was not saved")
	if not Game.is_unlocked("control_freak"):
		_fail("Control Freak not unlocked")
	# Restore the player's real save file.
	Game.save = saved_backup
	Game.write_save()
	print("Scenes visited: ", ", ".join(seen))
	print("Fights per flow: ", fights)
	if failures.is_empty():
		print("FLOW TEST PASSED in %d frames" % frames)
		get_tree().quit(0)
	else:
		print("%d FLOW FAILURES" % failures.size())
		get_tree().quit(1)
