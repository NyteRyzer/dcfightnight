extends Node
## Plays through the tutorial with simulated Player 1 button presses and
## checks every lesson can be completed.
##   godot --headless --path . --fixed-fps 60 res://tests/TutorialCheck.tscn

const LIMIT := 60 * 25

# Per lesson: a looping script of [frames, [actions held]].
const SCRIPTS := {
	"walk": [[40, ["right"]], [40, ["left"]], [10, []]],
	"jump": [[4, ["up"]], [60, []]],
	"crouch": [[60, ["down"]], [5, []]],
	"normals": [[3, ["light"]], [40, []], [3, ["medium"]], [40, []], [3, ["heavy"]], [50, []]],
	"chain": [[50, ["right"]], [2, []], [3, ["light"]], [7, []], [3, ["medium"]], [9, []], [3, ["heavy"]], [50, []], [40, ["left"]]],
	"block_high": [[600, ["block"]]],
	"block_low": [[600, ["down", "block"]]],
	"specials": [[3, ["special"]], [80, []], [3, ["right", "special"]], [80, []], [3, ["left", "special"]], [80, []]],
	"throw": [[60, ["right"]], [3, ["throw"]], [60, []], [30, ["left"]]],
	"super": [[40, ["right"]], [4, ["down"]], [3, ["down", "special"]], [120, []], [30, ["left"]]],
	"amplify": [[3, ["special"]], [2, []], [3, ["block"]], [80, []]],
}

var stage: Node = null
var t := 0
var lesson_t := 0
var last_lesson := -1
var held: Array = []
var failures: Array = []


func _ready() -> void:
	Game.mode = "tutorial"
	Game.chars = ["flash", "citizen_steel"]
	Game.cpu = [false, true]
	Game.costume = [0, 0]
	Game.stage_id = "star_labs"
	Game.fight_opts = {}
	stage = load("res://scenes/fight/TrainingRoom.tscn").instantiate()
	add_child(stage)


func _set_held(actions: Array) -> void:
	for a in held:
		if not a in actions:
			Input.action_release("p1_" + a)
	for a in actions:
		Input.action_press("p1_" + a)
	held = actions


func _physics_process(_d: float) -> void:
	if stage.phase == "vs":
		if stage.pt == 40:
			stage.start_round()
		return
	if stage.phase != "fight" or stage.tutorial == null:
		return
	var tut = stage.tutorial
	if tut.finished:
		_set_held([])
		print("TUTORIAL CHECK: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	if tut.lesson != last_lesson:
		if last_lesson >= 0:
			print("  lesson %-12s done in %d frames" % [tut.LESSONS[last_lesson]["id"], lesson_t])
		last_lesson = tut.lesson
		lesson_t = 0
		t = 0
	lesson_t += 1
	if OS.get_environment("TDBG") != "" and tut.current()["id"] == "block_high" and lesson_t % 20 == 0:
		var d: Node2D = stage.fighters[1]
		var p: Node2D = stage.fighters[0]
		print("    dummy st=%s move=%s x=%.0f px=%.0f pst=%s ctrl=%s inp=%s" % [d.state, d.move_id, d.pos.x, p.pos.x, p.state, d.controlled, d.inp])
	if tut.done_t > 0:
		_set_held([])
		return
	var steps: Array = SCRIPTS[tut.current()["id"]]
	var total := 0
	for s in steps:
		total += int(s[0])
	var k := t % total
	t += 1
	for s in steps:
		if k < int(s[0]):
			_set_held(s[1])
			break
		k -= int(s[0])
	if lesson_t > LIMIT:
		failures.append(tut.current()["id"])
		printerr("FAIL: lesson %s not completed" % tut.current()["id"])
		tut.skip()
