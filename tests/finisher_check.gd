extends Node
## Plays every fighter's finisher: forces a deciding KO, waits for the
## "FINISH IT" stagger, enters the command and checks the cinematic ends in a
## normal round win. With an output dir it also saves mid-finisher shots:
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/FinisherCheck.tscn -- <out_dir>

const FightScene = preload("res://scenes/fight/FightStage.tscn")

var ids: Array = []
var current: Node = null
var frames := 0
var out_dir := ""
var failures: Array = []
var shot_at := []
var id := ""


func _ready() -> void:
	ids = Data.roster.duplicate()
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
		DirAccess.make_dir_recursive_absolute(out_dir)
	if args.size() > 1:
		ids = args.slice(1)
	_next.call_deferred()


func _next() -> void:
	if current != null:
		current.queue_free()
		current = null
	if ids.is_empty():
		print("FINISHER CHECK: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	id = ids.pop_front()
	var opp := "green_arrow" if id != "green_arrow" else "flash"
	Game.chars = [id, opp]
	Game.costume = [0, 0]
	Game.cpu = [true, true]
	Game.mode = "cpu_vs_cpu"
	Game.stage_id = "star_labs"
	Game.fight_opts = {"single_round": true}
	current = FightScene.instantiate()
	add_child(current)
	current.enable_autoplay()
	frames = 0


func _physics_process(_d: float) -> void:
	if current == null:
		return
	frames += 1
	var f: Node = current
	if OS.get_environment("FDBG") != "" and (frames % 30 == 0 or f.phase != str(get_meta("lp", ""))):
		set_meta("lp", f.phase)
		print("    [%d] %s pt=%d hp=%.0f/%.0f st=%s/%s" % [frames, f.phase, f.pt, f.fighters[0].health, f.fighters[1].health, f.fighters[0].state, f.fighters[1].state])
	match f.phase:
		"fight":
			if f.pt == 110:
				# Alternate between a launched KO and a standing KO.
				var l: Node2D = f.fighters[1]
				l.health = 1.0
				l.invuln = 0
				l.to_neutral()
				if ids.size() % 2 == 0:
					l.receive_hit({"damage": 50, "hitstun": 20, "launch": [4, -8]}, f.fighters[0], false)
				l.health = 0.0
		"finish_wait":
			if f.finish_t > 5:
				f._start_finisher()
		"finisher":
			var n := int(f.finish_seq.get("len", 180))
			if out_dir != "" and (f.pt == int(n * 0.3) or f.pt == int(n * 0.55)):
				var img := get_viewport().get_texture().get_image()
				img.save_png(out_dir.path_join("%s_%d.png" % [id, f.pt]))
		"roundwin":
			if f.pt == 2 and not f.finish_done:
				_fail("%s: round ended without the finisher" % id)
		"done":
			if f.match_winner != 0:
				_fail("%s: wrong winner" % id)
			print("  %-18s %s OK" % [id, f.finish_name])
			_next()
			return
	if frames > 60 * 40:
		_fail("%s: stuck in phase %s" % [id, f.phase])
		_next()


func _fail(msg: String) -> void:
	failures.append(msg)
	printerr("FAIL: ", msg)
