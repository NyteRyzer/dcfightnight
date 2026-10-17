extends RefCounted
## CPU opponent and training dummy. Produces the same held-input dictionary a
## human player would, so the AI can only do what a player could do.
##
## Plans are short queues of inputs. "f"/"b" mean toward/away from the opponent
## and are resolved on the frame they execute.

var me: Node2D
var opp: Node2D
var manager: Node
var level := 2
var mode := "cpu"   # cpu | stand | crouch | jump | block
var plan: Array = []
var think_cd := 0
var rng := RandomNumberGenerator.new()
var _amp_tried := false
var _prev_b := false

const REACT := [30, 18, 11, 6, 3]
const BLOCK_P := [0.2, 0.45, 0.68, 0.86, 0.95]
const AGGRO := [0.35, 0.5, 0.62, 0.75, 0.85]
const COMBO_P := [0.15, 0.45, 0.75, 0.92, 1.0]
const ANTI_AIR_P := [0.1, 0.35, 0.6, 0.8, 0.9]


func setup(f: Node2D, o: Node2D, m: Node, lvl: int) -> void:
	me = f
	opp = o
	manager = m
	level = clampi(lvl, 0, 4)
	rng.randomize()


func _resolve(i: Dictionary) -> Dictionary:
	var out := {}
	var toward_right: bool = opp.pos.x >= me.pos.x
	for k in i:
		match k:
			"f":
				out["r" if toward_right else "l"] = true
			"b":
				out["l" if toward_right else "r"] = true
			_:
				out[k] = i[k]
	return out


func _push(i: Dictionary, n: int = 1) -> void:
	plan.append({"i": i, "n": n})


func _tap(i: Dictionary, hold_dir: Dictionary = {}) -> void:
	var down := hold_dir.duplicate()
	for k in i:
		down[k] = i[k]
	_push(down, 1)
	_push(hold_dir, 1)


func think() -> Dictionary:
	if me == null or opp == null:
		return {}
	match mode:
		"stand":
			return {}
		"crouch":
			return {"d": true}
		"jump":
			return {"u": true} if me.grounded() and me.frame % 50 == 0 else {}
		"block":
			return _dummy_block()
	var sys := _system_moves()
	if not sys.is_empty():
		return sys
	if plan.size() > 0:
		var e: Dictionary = plan[0]
		e["n"] -= 1
		if e["n"] <= 0:
			plan.pop_front()
		return _resolve(e["i"])
	_decide()
	if plan.size() > 0:
		return think()
	return {}


## Meter tactics: Amplify specials and Breaker out of long combos.
func _system_moves() -> Dictionary:
	var bar: float = 1000.0 / 3.0
	if me.state != "attack":
		_amp_tried = false
	elif not _amp_tried and me.move.get("special", false) and not me.move.get("super", false) and not me.move.get("hidden", false):
		if me.sf <= int(me.move.get("startup", 1)) and me.meter >= bar and level >= 1:
			_amp_tried = true
			if rng.randf() < 0.12 * level:
				return {"B": true}
	if me.state in ["hitstun", "airhit"] and me.combo_hits >= 3 and me.meter >= bar * 2.0 and not me.breaker_used and level >= 2:
		if rng.randf() < 0.025 * level:
			return {"B": true, "f": true}
	return {}


func _dummy_block() -> Dictionary:
	var lvl := ""
	if opp.state == "attack" and opp.move.has("hitbox"):
		lvl = opp.move.get("level", "mid")
	var p = manager.incoming_projectile(me, 220.0) if manager != null else null
	if p != null:
		lvl = p.data.get("level", "mid")
	if lvl == "":
		return {"B": true}
	return {"B": true, "d": lvl == "low"}


func _decide() -> void:
	if think_cd > 0:
		think_cd -= 1
		return
	if not (me.is_actionable() or me.state in ["attack", "air"]):
		return
	var H: float = me.H
	var dist: float = absf(opp.pos.x - me.pos.x)
	var react: int = REACT[level]

	# Combo continuation: chain or cancel after a connecting hit.
	if me.state == "attack":
		if me.move_connected and rng.randf() < COMBO_P[level] and me.sf > int(me.move.get("startup", 1)):
			var chain: Array = me.move.get("chain", [])
			if me.meter >= 1000.0 and rng.randf() < 0.6 and not me.move.get("special", false):
				_tap({"S": true, "d": true}, {"d": true})
			elif chain.size() > 0 and rng.randf() < 0.75:
				var nxt: String = chain[mini(chain.size() - 1, rng.randi() % chain.size())]
				var crouch := nxt.begins_with("c")
				var btn := nxt.substr(1) if crouch else nxt
				var hold := {"d": true} if crouch else {}
				_tap({btn: true}, hold)
			elif not me.move.get("special", false):
				var choices := ["S", "fS"]
				var c: String = choices[rng.randi() % 2]
				_tap({"S": true, "f": true} if c == "fS" else {"S": true}, {"f": true} if c == "fS" else {})
			think_cd = 3
		return
	if me.state == "air":
		if not me.used_air_attack and dist < 0.75 * H and opp.pos.y > me.pos.y - H * 0.2:
			var btns := ["L", "M", "H"]
			_tap({btns[rng.randi() % 3]: true})
		return

	# Defense.
	var threat: bool = opp.is_attacking_threat() and dist < 1.5 * H
	var proj = manager.incoming_projectile(me, 200.0)
	if (threat or proj != null) and rng.randf() < BLOCK_P[level]:
		var low := false
		if threat:
			low = opp.move.get("level", "mid") == "low"
		elif proj != null:
			low = proj.data.get("level", "mid") == "low"
		if proj != null and not threat and rng.randf() < 0.25 and dist > 1.4 * H:
			_push({"u": true, "f": true}, 3)
			_push({"f": true}, 25)
			return
		_push({"B": true, "d": low}, 12 + rng.randi() % 10)
		think_cd = react / 3
		return

	# Whiff punish: opponent is stuck in recovery close by.
	if opp.state == "attack" and opp.sf > int(opp.move.get("startup", 1)) + int(opp.move.get("active", 1)) and dist < 1.0 * H and rng.randf() < COMBO_P[level]:
		if rng.randf() < 0.5:
			_tap({"H": true})
		else:
			_tap({"S": true, "f": true}, {"f": true})
		think_cd = 4
		return

	# Anti-air.
	if not opp.grounded() and opp.state in ["air", "attack"] and dist < 1.0 * H and rng.randf() < ANTI_AIR_P[level]:
		_tap({"H": true, "d": true}, {"d": true})
		_push({"d": true}, 4)
		think_cd = react
		return

	var r := rng.randf()
	var moves: Dictionary = me.def["moves"]
	if me.meter >= 1000.0 and dist < 1.4 * H and rng.randf() < 0.08 * (level + 1):
		_push({"d": true}, 2)
		_tap({"S": true, "d": true}, {"d": true})
		think_cd = react
		return
	if dist > 2.0 * H:
		var has_proj: bool = moves["S"].has("projectile")
		if has_proj and r < 0.35 and me.can_use("S"):
			_tap({"S": true})
		elif r < 0.5:
			_push({"f": true}, 1)
			_push({}, 1)
			_push({"f": true}, 10)
		elif r < 0.62:
			_push({"u": true, "f": true}, 3)
			_push({"f": true}, 18)
		elif r < 0.7 and moves.has("fS"):
			_tap({"S": true, "f": true}, {"f": true})
		else:
			_push({"f": true}, 18 + rng.randi() % 20)
	elif dist > 0.7 * H:
		if r < AGGRO[level] * 0.5:
			_push({"f": true}, 8 + rng.randi() % 10)
		elif r < 0.55:
			_tap({"M": true})
		elif r < 0.66:
			_tap({"S": true, "f": true}, {"f": true})
		elif r < 0.76:
			_push({"u": true, "f": true}, 3)
			_push({"f": true}, 10)
		elif r < 0.84 and moves["S"].has("projectile") and me.can_use("S"):
			_tap({"S": true})
		elif r < 0.9:
			_push({"d": true}, 3)
			_tap({"M": true, "d": true}, {"d": true})
		else:
			_push({"b": true}, 10 + rng.randi() % 10)
	else:
		if r < 0.3:
			_tap({"L": true})
		elif r < 0.45:
			_push({"d": true}, 2)
			_tap({"M": true, "d": true}, {"d": true})
		elif r < 0.55:
			_push({"M": true, "H": true}, 2)
		elif r < 0.68:
			_tap({"H": true})
		elif r < 0.76:
			_tap({"S": true, "b": true}, {"b": true})
		elif r < 0.86:
			_push({"B": true}, 14)
		else:
			_push({"b": true}, 1)
			_push({}, 1)
			_push({"b": true}, 8)
	think_cd = react
