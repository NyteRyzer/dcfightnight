extends RefCounted
## Interactive tutorial run inside the training room. Each lesson has a goal
## that is checked from the fighters' state, a dummy behaviour, and on-screen
## instructions that show the player's actual keys or buttons.

const LESSONS := [
	{"id": "walk", "title": "Moving", "text": "Walk toward the dummy with {right}, then away with {left}.", "goal": 2, "dummy": "idle"},
	{"id": "jump", "title": "Jumping", "text": "Press {up} to jump. Hold {left} or {right} too to jump in that direction. Jump 3 times.", "goal": 3, "dummy": "idle"},
	{"id": "crouch", "title": "Crouching", "text": "Hold {down} to crouch. Crouching ducks under high attacks.", "goal": 1, "dummy": "idle"},
	{"id": "normals", "title": "Basic Attacks", "text": "Try all three attacks: Light {light}, Medium {medium} and Heavy {heavy}.", "goal": 3, "dummy": "idle"},
	{"id": "chain", "title": "Combos", "text": "Walk up close and press Light, Medium, Heavy in a quick rhythm to chain a 3-hit combo.", "goal": 1, "dummy": "idle"},
	{"id": "block_high", "title": "Blocking", "text": "The dummy will attack. Hold {block} to block its standing attacks. Block 3 hits.", "goal": 3, "dummy": "attack_high"},
	{"id": "block_low", "title": "Low Blocking", "text": "Low kicks hit standing blockers. Hold {down} + {block} to block low. Block 2 low kicks.", "goal": 2, "dummy": "attack_low"},
	{"id": "specials", "title": "Special Moves", "text": "Press {special}, then {right} + {special} (toward), then {left} + {special} (away). Each is a different special.", "goal": 3, "dummy": "idle"},
	{"id": "throw", "title": "Throws", "text": "Throws beat blocking. Walk right up to the dummy and press {throw}.", "goal": 1, "dummy": "block"},
	{"id": "super", "title": "Super Move", "text": "Your meter is full. Press {down} + {special} to unleash your super. Make it hit!", "goal": 1, "dummy": "idle"},
	{"id": "amplify", "title": "Amplify", "text": "Press {special}, then tap {block} right away to Amplify the special (costs 1 bar): more damage and armor.", "goal": 1, "dummy": "idle"},
]

var stage: Node
var lesson := 0
var progress := 0
var seen := {}
var counter := 0
var done_t := 0
var prev_state := ""
var prev_move := ""
var dummy_t := 0
var finished := false
var fresh := true


func setup(s: Node) -> void:
	stage = s
	_start(0)


func current() -> Dictionary:
	return LESSONS[mini(lesson, LESSONS.size() - 1)]


func _start(i: int) -> void:
	lesson = i
	progress = 0
	seen = {}
	counter = 0
	done_t = 0
	dummy_t = 0
	# Every lesson starts from the usual positions so "toward" is always right.
	if i > 0:
		stage._reset_positions()
	fresh = true


func skip() -> void:
	if not finished:
		_complete()


## Instruction text with the player's real keys / buttons filled in.
func instruction() -> String:
	if finished:
		return "That's everything! Story Mode starts on easier fights, so you're ready. Pause to exit, or keep practising here."
	var t: String = current()["text"]
	for k in ["up", "down", "left", "right", "light", "medium", "heavy", "special", "block", "throw"]:
		t = t.replace("{%s}" % k, "[%s]" % InputManager.prompt(k, 0))
	return t


func tick() -> void:
	var p: Node2D = stage.fighters[0]
	var d: Node2D = stage.fighters[1]
	if finished:
		return
	if done_t > 0:
		done_t -= 1
		if done_t == 0:
			if lesson + 1 >= LESSONS.size():
				finished = true
				Game.save["tutorial_done"] = true
				Game.write_save()
				Sound.play("bell")
			else:
				_start(lesson + 1)
				stage.hud.announce("LESSON %d" % (lesson + 1), current()["title"].to_upper(), 70, Color(1, 0.85, 0.3))
		return
	var cur: Dictionary = current()
	if fresh:
		fresh = false
		for f in stage.fighters:
			f.meter = 0.0
	if cur["id"] in ["super", "amplify"]:
		p.meter = 1000.0
	match cur["id"]:
		"walk":
			if p.state == "walk_f":
				counter += 1
				if counter > 25:
					seen["f"] = true
			elif p.state == "walk_b":
				counter += 1
				if counter > 25:
					seen["b"] = true
			else:
				counter = 0
			progress = seen.size()
		"jump":
			if p.state == "air" and prev_state != "air":
				progress += 1
		"crouch":
			counter = counter + 1 if p.state == "crouch" else 0
			if counter > 40:
				progress = 1
		"normals":
			if p.move_id != prev_move and p.move_id in ["L", "M", "H", "cL", "cM", "cH"]:
				seen[p.move_id.substr(p.move_id.length() - 1)] = true
			progress = seen.size()
		"chain":
			if d.combo_hits >= 3:
				progress = 1
		"specials":
			if p.move_id != prev_move and p.move_id in ["S", "fS", "bS"]:
				seen[p.move_id] = true
			progress = seen.size()
		"throw":
			if d.state == "thrown":
				progress = 1
		"amplify":
			if p.amplified:
				progress = 1
	prev_state = p.state
	prev_move = p.move_id
	if progress >= int(cur["goal"]):
		_complete()


func _complete() -> void:
	progress = int(current()["goal"])
	done_t = 70
	stage.hud.announce("NICE!", "", 50, Color(0.5, 1, 0.5))
	Sound.play("menu_ok")
	stage.fighters[0].health = stage.fighters[0].max_health


## Called by the fight manager for every resolved hit.
func on_hit(a: Node2D, d: Node2D, res: String, atk: Dictionary) -> void:
	if done_t > 0 or finished:
		return
	var id: String = current()["id"]
	if a.pid == 1 and res == "block":
		if id == "block_high" or (id == "block_low" and str(atk.get("level", "mid")) == "low"):
			progress += 1
	if a.pid == 0 and res == "hit" and id == "super" and atk.get("super", false):
		progress = 1


## Scripted dummy: idle, blocking, or walking in to attack high or low.
func dummy_input() -> Dictionary:
	var mode: String = current()["dummy"] if not finished else "idle"
	var p: Node2D = stage.fighters[0]
	var d: Node2D = stage.fighters[1]
	var toward := "r" if p.pos.x > d.pos.x else "l"
	match mode:
		"block":
			return {"B": true}
		"attack_high", "attack_low":
			if done_t > 0:
				return {}
			dummy_t += 1
			var dist: float = absf(p.pos.x - d.pos.x)
			if dist > 0.42 * d.H and d.is_actionable():
				return {toward: true}
			var cyc := dummy_t % 75
			if mode == "attack_high":
				return {"M": true} if cyc == 30 else {}
			if cyc >= 24 and cyc <= 34:
				return {"d": true, "M": cyc == 28}
			return {}
	return {}
