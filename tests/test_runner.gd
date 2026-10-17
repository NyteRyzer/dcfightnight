extends Node
## Automated smoke & balance-safety tests. Run headless:
##   godot --headless --path . --fixed-fps 60 res://tests/TestRunner.tscn
## Optional user args (after `--`): quick (fewer matchups)
##
## Checks: data validation, every pose solves, every scene loads and runs,
## every fighter vs every fighter (CPU vs CPU) for softlocks, out-of-bounds,
## invalid health/meter, runaway combos, and matches that never finish.

const FightScene = preload("res://scenes/fight/FightStage.tscn")
const TrainingScene = preload("res://scenes/fight/TrainingRoom.tscn")
const Poses = preload("res://scripts/combat/poses.gd")
const Rig = preload("res://scripts/combat/rig.gd")

const MATCH_FRAME_LIMIT := 60 * 60 * 3
const STUCK_LIMIT := 600

var failures: Array = []
var queue: Array = []
var current: Node = null
var frames := 0
var stuck := [0, 0]
var max_combo := 0
var label := ""
var results: Array = []
var quick := false
var scene_queue: Array = []
var t0 := 0
var wins := {}
var games := {}


func _ready() -> void:
	t0 = Time.get_ticks_msec()
	quick = "quick" in OS.get_cmdline_user_args()
	_check_data()
	_check_poses()
	Game.settings["round_time"] = 30
	Game.settings["rounds"] = 1
	Game.settings["shake"] = false
	var ids: Array = Data.roster
	var stages: Array = Data.stages
	var n := 0
	for a in ids:
		for b in ids:
			if quick and n % 7 != 0:
				n += 1
				continue
			queue.append({"a": a, "b": b, "stage": stages[n % stages.size()]["id"]})
			n += 1
	scene_queue = ["res://scenes/ui/MainMenu.tscn", "res://scenes/ui/CharacterSelect.tscn", "res://scenes/ui/StageSelect.tscn",
		"res://scenes/ui/Options.tscn", "res://scenes/ui/Credits.tscn", "story", "training"]
	print("Running %d matchups + %d scene checks" % [queue.size(), scene_queue.size()])


func _fail(msg: String) -> void:
	failures.append(msg)
	printerr("FAIL: ", msg)


func _check_data() -> void:
	var errs: Array = Data.validate()
	for e in errs:
		_fail("data: " + str(e))
	print("data validation: %d problems" % errs.size())


func _check_poses() -> void:
	for id in Data.roster:
		var f: Dictionary = Data.fighter(id)
		for pname in Poses.LIB:
			var j: Dictionary = Rig.solve(Poses.get_pose(pname), float(f["height"]), f["look"])
			for k in j:
				var v = j[k]
				if v is Vector2 and (is_nan(v.x) or is_nan(v.y) or is_inf(v.x) or is_inf(v.y)):
					_fail("pose %s for %s produced invalid joint %s" % [pname, id, k])
	print("pose solve check done")


func _process(_delta: float) -> void:
	if current == null:
		_next()
		return
	frames += 1
	if current.has_method("enable_autoplay"):
		_check_fight()
	elif frames > 90:
		_finish_scene()


func _next() -> void:
	if scene_queue.size() > 0:
		var s: String = scene_queue.pop_front()
		label = s
		frames = 0
		if s == "story":
			Game.mode = "story"
			Game.story_index = 0
			Game.story_cards = Data.story["intro"]
			Game.story_next = "menu"
			current = load("res://scenes/story/StoryScene.tscn").instantiate()
		elif s == "training":
			Game.chars = ["flash", "citizen_steel"]
			Game.cpu = [false, true]
			Game.costume = [0, 0]
			Game.stage_id = "star_labs"
			Game.fight_opts = {}
			Game.mode = "training"
			Game.training = {"dummy": "block", "meter": "infinite", "boxes": true, "regen": true}
			current = TrainingScene.instantiate()
		else:
			current = load(s).instantiate()
		add_child(current)
		return
	if queue.is_empty():
		_report()
		return
	var m: Dictionary = queue.pop_front()
	label = "%s vs %s @ %s" % [m["a"], m["b"], m["stage"]]
	Game.chars = [m["a"], m["b"]]
	Game.costume = [0, 1 if m["a"] == m["b"] else 0]
	Game.cpu = [true, true]
	Game.mode = "cpu_vs_cpu"
	Game.stage_id = m["stage"]
	Game.fight_opts = {"single_round": true, "boss": m["b"] == "control_freak"}
	current = FightScene.instantiate()
	add_child(current)
	current.enable_autoplay()
	frames = 0
	stuck = [0, 0]
	max_combo = 0


func _finish_scene() -> void:
	if current.has_method("enable_autoplay"):
		var t: bool = current.training
		if t:
			for f in current.fighters:
				if f.health <= 0:
					_fail("training: fighter died")
	current.queue_free()
	current = null
	get_tree().paused = false


func _check_fight() -> void:
	var fs: Array = current.fighters
	var b: Vector2 = current.bounds()
	if current.training:
		# Feed P1 some attacks through the AI so training logic runs.
		if frames > 400:
			_finish_scene()
		return
	for i in 2:
		var f: Node2D = fs[i]
		if is_nan(f.pos.x) or is_nan(f.pos.y):
			_fail("%s: NaN position" % label)
		if f.pos.x < b.x - 1.0 or f.pos.x > b.y + 1.0 or f.pos.x < 0 or f.pos.x > 1000:
			_fail("%s: fighter %d out of bounds at %.1f (bounds %.1f..%.1f)" % [label, i, f.pos.x, b.x, b.y])
		if f.pos.y > f.FLOOR_Y + 0.5:
			_fail("%s: fighter %d below floor" % [label, i])
		if f.health > f.max_health + 0.01:
			_fail("%s: health above max" % label)
		if f.meter < -0.01 or f.meter > 1000.01:
			_fail("%s: meter out of range %.1f" % [label, f.meter])
		if current.phase == "fight" and f.state not in ["idle", "walk_f", "walk_b", "crouch", "block", "block_low"]:
			stuck[i] += 1
			if stuck[i] == STUCK_LIMIT:
				_fail("%s: fighter %d stuck in state '%s' (move %s) for %d frames" % [label, i, f.state, f.move_id, STUCK_LIMIT])
		else:
			stuck[i] = 0
		max_combo = maxi(max_combo, f.combo_hits)
	if max_combo > 30:
		_fail("%s: runaway combo of %d hits" % [label, max_combo])
		max_combo = -1000
	if current.phase == "done":
		var ids: Array = Game.chars
		if ids[0] != ids[1]:
			for k in 2:
				games[ids[k]] = games.get(ids[k], 0) + 1
			var wid: String = ids[current.match_winner]
			wins[wid] = wins.get(wid, 0) + 1
		results.append("%s -> winner P%d in %d frames (max combo %d, hp left %d%% / %d%%, hits %d/%d)" % [label, current.match_winner + 1, frames, maxi(0, max_combo),
			int(100.0 * fs[0].health / fs[0].max_health), int(100.0 * fs[1].health / fs[1].max_health), current.hit_count[0], current.hit_count[1]])
		_finish_scene()
	elif frames > MATCH_FRAME_LIMIT:
		_fail("%s: match did not finish (phase %s)" % [label, current.phase])
		_finish_scene()


func _report() -> void:
	for r in results:
		print(r)
	print("--------------------------------------------------")
	print("CPU vs CPU win rates (rough balance signal):")
	var order: Array = games.keys()
	order.sort_custom(func(x, y): return float(wins.get(x, 0)) / games[x] > float(wins.get(y, 0)) / games[y])
	for id in order:
		print("  %-20s %5.1f%%  (%d games)" % [id, 100.0 * wins.get(id, 0) / games[id], games[id]])
	print("--------------------------------------------------")
	print("Matchups run: %d   Time: %.1fs" % [results.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	if failures.is_empty():
		print("ALL TESTS PASSED")
		get_tree().quit(0)
	else:
		print("%d FAILURES" % failures.size())
		get_tree().quit(1)
