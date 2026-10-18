extends RefCounted
## Beat 'em up AI for enemy NPCs, bosses and autoplay players.
##
## Returns {"inp": fighter input, "dz": depth step -1/0/1}. Enemies take an
## "attack token" from the manager before closing in, so crowds circle and
## take turns instead of piling on, the way classic brawlers pace fights.

const CpuAI = preload("res://scripts/combat/cpu_ai.gd")

var me: Node2D
var manager: Node
var kind := "brawler"
var rng := RandomNumberGenerator.new()
var plan: Array = []
var think_cd := 0
var hover_side := 1.0
var hover_depth := 0.0
var cpu = null
var level := 2


func setup(f: Node2D, m: Node, ai_kind: String, lvl: int = 2) -> void:
	me = f
	manager = m
	kind = ai_kind
	level = lvl
	rng.randomize()
	hover_side = 1.0 if rng.randf() < 0.5 else -1.0
	hover_depth = rng.randf_range(-24.0, 24.0)
	think_cd = rng.randi_range(10, 40)
	if kind == "boss":
		cpu = CpuAI.new()


func _resolve(i: Dictionary, target: Node2D) -> Dictionary:
	var out := {}
	var right: bool = target.pos.x >= me.pos.x
	for k in i:
		match k:
			"f":
				out["r" if right else "l"] = true
			"b":
				out["l" if right else "r"] = true
			_:
				out[k] = i[k]
	return out


func _push(i: Dictionary, n: int = 1) -> void:
	plan.append({"i": i, "n": n})


func _tap(i: Dictionary) -> void:
	_push(i, 1)
	_push({}, 1)


func think() -> Dictionary:
	var target: Node2D = me.opponent
	if target == null or target == me or me.health <= 0.0:
		return {"inp": {}, "dz": 0.0}
	var dz: float = target.depth - me.depth
	var dx: float = target.pos.x - me.pos.x
	var dist := absf(dx)
	var H: float = me.H
	if kind == "boss":
		return _boss(target, dz)
	if plan.size() > 0:
		var e: Dictionary = plan[0]
		e["n"] -= 1
		if e["n"] <= 0:
			plan.pop_front()
		return {"inp": _resolve(e["i"], target), "dz": 0.0}
	if not me.is_actionable():
		# Continue chains while attacking.
		if me.state == "attack" and me.move_connected and me.sf > int(me.move.get("startup", 1)) and rng.randf() < 0.35:
			var chain: Array = me.move.get("chain", [])
			if chain.size() > 0:
				var nxt: String = chain[rng.randi() % chain.size()]
				if not nxt.begins_with("c"):
					_tap({nxt: true})
		return {"inp": {}, "dz": 0.0}
	var has_token: bool = kind == "player" or manager.request_token(me, target)
	var ranged := kind in ["gunner", "caster"]
	var want := 0.55 * H
	if ranged:
		want = 2.2 * H if kind == "gunner" else 1.7 * H
	if not has_token:
		want = 1.7 * H
	var inp := {}
	var step := 0.0
	var tgt_depth: float = target.depth + (0.0 if has_token else hover_depth)
	if absf(tgt_depth - me.depth) > 4.0:
		step = signf(tgt_depth - me.depth)
	if think_cd > 0:
		think_cd -= 1
	# Approach / keep spacing.
	if dist > want + 18.0:
		inp["f"] = true
	elif dist < want - 30.0 and (ranged or not has_token):
		inp["b"] = true
	var aligned := absf(dz) < 10.0
	if think_cd <= 0 and aligned and has_token:
		var r := rng.randf()
		think_cd = rng.randi_range(18, 45) - level * 4
		match kind:
			"gunner", "caster":
				if dist > 0.9 * H and me.can_use("S"):
					_tap({"S": true})
				elif dist < 0.7 * H:
					_tap({"L": true})
			"knife":
				if dist < 0.7 * H:
					_tap({"L": true} if r < 0.6 else {"M": true})
				elif dist < 1.5 * H and me.def["moves"].has("fS"):
					_tap({"S": true, "f": true})
			"brute":
				if dist < 0.75 * H:
					_tap({"H": true} if r < 0.55 else {"L": true})
				elif dist < 1.8 * H and me.def["moves"].has("fS") and r < 0.4:
					_tap({"S": true, "f": true})
			"agile":
				if dist < 0.7 * H:
					_tap({"L": true} if r < 0.4 else {"H": true})
				elif dist < 1.6 * H and r < 0.45:
					_tap({"S": true, "f": true})
				elif dist < 2.2 * H and r < 0.7:
					_push({"u": true, "f": true}, 3)
					_push({"f": true}, 14)
					_tap({"H": true})
			"player":
				me.facing = 1 if dx >= 0.0 else -1
				if dist < 0.75 * H:
					var opts := [{"L": true}, {"M": true}, {"H": true}, {"S": true, "f": true}, {"S": true}]
					_tap(opts[rng.randi() % opts.size()])
					if me.meter >= 1000.0 and r < 0.2:
						_tap({"S": true, "d": true})
			_:
				if dist < 0.7 * H:
					_tap({"L": true} if r < 0.5 else ({"M": true} if r < 0.8 else {"H": true}))
	return {"inp": _resolve(inp, target), "dz": step}


func _boss(target: Node2D, dz: float) -> Dictionary:
	if cpu.me != me or cpu.opp != target:
		cpu.setup(me, target, manager, level)
	var step := 0.0
	if absf(dz) > 6.0 and me.is_actionable():
		step = signf(dz)
	return {"inp": cpu.think(), "dz": step}
