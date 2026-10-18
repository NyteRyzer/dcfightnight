extends Node
## Difficulty sanity check: a weak CPU stands in for a new player (Flash) and
## fights Green Arrow (Story chapter 1) under different CPU settings.
##   godot --headless --path . --fixed-fps 60 res://tests/DifficultyCheck.tscn

const FightScene = preload("res://scenes/fight/FightStage.tscn")
const CpuAI = preload("res://scripts/combat/cpu_ai.gd")
const N := 16

# [label, stand-in player level, CPU level, CPU damage]
var scenarios := [
	["old default: HARD, full damage", 1, 2, 1.0],
	["new Story Act I on NORMAL", 1, 0, CpuAI.DAMAGE[0]],
	["new NORMAL (Act II+)", 1, 1, CpuAI.DAMAGE[1]],
	["new Act I after 3 retries", 1, 0, CpuAI.DAMAGE[0] * 0.9],
	["weaker player vs old default", 0, 2, 1.0],
	["weaker player vs new Act I", 0, 0, CpuAI.DAMAGE[0]],
]
var si := 0
var played := 0
var won := 0
var current: Node = null
var frames := 0


func _ready() -> void:
	_next.call_deferred()


func _next() -> void:
	if current != null:
		current.queue_free()
		current = null
	if played >= N:
		print("%-34s player wins %2d/%d (%d%%)" % [scenarios[si][0], won, N, 100 * won / N])
		si += 1
		played = 0
		won = 0
	if si >= scenarios.size():
		get_tree().quit()
		return
	var sc: Array = scenarios[si]
	Game.chars = ["flash", "green_arrow"]
	Game.costume = [0, 0]
	Game.cpu = [true, true]
	Game.mode = "cpu_vs_cpu"
	Game.stage_id = "star_labs"
	Game.fight_opts = {"single_round": true}
	current = FightScene.instantiate()
	add_child(current)
	current.enable_autoplay()
	current.ai[0].setup(current.fighters[0], current.fighters[1], current, sc[1])
	current.ai[1].setup(current.fighters[1], current.fighters[0], current, sc[2])
	current.fighters[1].dmg_mult = sc[3]
	frames = 0


func _physics_process(_d: float) -> void:
	if current == null:
		return
	frames += 1
	if current.phase == "done" or frames > 60 * 120:
		played += 1
		if current.phase == "done" and current.match_winner == 0:
			won += 1
		_next()
