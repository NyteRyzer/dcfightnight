extends Node
## Beat 'em up soak test: autoplays every level (solo, then co-op) with AI
## players and reports progress, frame counts and lives lost. Run headless:
##   godot --headless --path . --fixed-fps 60 res://tests/BrawlTest.tscn [-- quick]

const BrawlScene = preload("res://scenes/brawl/BrawlStage.tscn")
const LEVEL_LIMIT := 60 * 60 * 7

var runs: Array = [["flash"], ["green_arrow", "supergirl"]]
var stage: Node = null
var frames := 0
var failures: Array = []
var last_level := -1
var last_phase := ""
var level_start := 0
var lives_used := 0
var quick := false


func _ready() -> void:
	quick = "quick" in OS.get_cmdline_user_args()
	if quick:
		runs = [["vigilante", "reign"]]
	_next_run.call_deferred()


func _next_run() -> void:
	if stage != null:
		stage.queue_free()
		stage = null
	if runs.is_empty():
		_report()
		return
	var ids: Array = runs.pop_front()
	Game.brawl = {"players": ids, "costumes": [0, 1], "level": 0, "continues": 0}
	stage = BrawlScene.instantiate()
	add_child(stage)
	stage.enable_autoplay()
	# Generous lives: the test checks the flow, not the AI's skill.
	stage.lives = [40, 40]
	frames = 0
	last_level = -1
	print("--- run: ", ids)


func _physics_process(_d: float) -> void:
	if stage == null:
		return
	frames += 1
	if stage.level_i != last_level:
		if last_level >= 0:
			print("  level %d cleared in %d s" % [last_level + 1, (frames - level_start) / 60])
		last_level = stage.level_i
		level_start = frames
		if last_level < stage.levels.size():
			print("  level %d: %s" % [last_level + 1, stage.levels[last_level]["name"]])
	if stage.phase != last_phase:
		last_phase = stage.phase
		if last_phase in ["boss_intro", "gameover"]:
			print("    %s (area %d, frame %d, lives %s)" % [last_phase, stage.area_i, frames, stage.lives])
	if stage.enemies.size() > 12:
		_fail("too many enemies alive: %d" % stage.enemies.size())
	for f in stage.players + stage.enemies:
		if not is_finite(f.pos.x) or f.pos.y > f.floor_y + 1.0:
			_fail("bad fighter position %s" % f.pos)
	var quick_done: bool = quick and stage.level_i >= 2
	if stage.phase == "done" or stage.phase == "victory" or quick_done:
		var reached: int = stage.level_i
		print("  finished: phase=%s levels=%d score=%d kills=%d lives left=%s" % [stage.phase, reached, stage.score[0] + stage.score[1], stage.kills, stage.lives])
		if stage.phase == "done" and reached < stage.levels.size() and not quick_done:
			_fail("run ended early at level %d" % (reached + 1))
		_next_run()
	elif frames - level_start > LEVEL_LIMIT:
		# A slow AI player is fine; a soft-lock (nothing left to fight, or a
		# boss stuck at 0 HP) is not.
		var alive: int = stage._alive_enemies()
		var stuck: bool = alive == 0 and stage.spawn_queue.is_empty()
		var info := "level %d area %d phase %s alive=%d queue=%d" % [stage.level_i + 1, stage.area_i, stage.phase, alive, stage.spawn_queue.size()]
		if stuck:
			_fail("soft-lock at " + info)
		else:
			print("  (time limit reached, still fighting: %s)" % info)
		_next_run()


func _fail(msg: String) -> void:
	if failures.size() < 20:
		printerr("FAIL: ", msg)
	failures.append(msg)


func _report() -> void:
	Game.brawl = {"players": ["flash"], "costumes": [0, 0], "level": 0, "continues": 0}
	print("BRAWL TEST: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
