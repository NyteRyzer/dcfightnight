extends Node2D
## A data-driven fighter: frame-based state machine, input buffer, move
## execution (startup / active / recovery), hit reception, and rendering.
##
## The fight manager drives everything through step(), one call per 60 Hz tick,
## and resolves collisions between fighters.

const Poses = preload("res://scripts/combat/poses.gd")
const Rig = preload("res://scripts/combat/rig.gd")

const FLOOR_Y := 322.0
const BUFFER_FRAMES := 8
const NEUTRAL := ["idle", "walk_f", "walk_b", "crouch", "block", "block_low"]
const MAX_JUGGLE := 5
## The super meter is split into three bars: Amplify costs 1, Breaker 2, Super 3.
const BAR := 1000.0 / 3.0
const STANCES := {
	"": ["idle", "idle2"], "heavy": ["idle_heavy", "idle_heavy2"], "speed": ["idle_speed", "idle_speed2"],
	"fem": ["idle_fem", "idle_fem2"], "sword": ["idle_sword", "idle_sword2"], "guns": ["idle_guns", "idle_guns2"],
}

var manager: Node = null
var def: Dictionary = {}
var look: Dictionary = {}
var pid := 0
var H := 170.0
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var facing := 1
var max_health := 1000.0
var health := 1000.0
var meter := 0.0
var wins := 0

var state := "idle"
var sf := 0
var frame := 0
var move: Dictionary = {}
var move_id := ""
var move_connected := false
var hits_done := 0
var last_hit_frame := -100
var counter_triggered := false
var armor_used := 0
var spawned := {}

var stun := 0
var stun_low := false
var hit_pose := "hit"
var slide := 0.0
var air_juggle := 0
var juggle_immune := false
var combo_hits := 0
var combo_damage := 0.0
var invuln := 0
var hitstop := 0
var flash := 0.0
var alpha := 1.0
var used_air_attack := false
var jump_dir := 0
var air_time := 0
var air_total := 40
var tech_window := 0
var throw_victim: Node2D = null
var thrower: Node2D = null
var phase_through := false

var opponent: Node2D = null
var inp := {}
var prev := {}
var buf: Array = []
var last_tap := {"f": -100, "b": -100}
var held_dir_prev := 5

var display_pose: Dictionary = Poses.get_pose("idle")
var afterimages: Array = []
var show_boxes := false
var cape_sway := 0.0
var controlled := true
var amplified := false
var breaker_used := false
var wall_bounce_ok := false
var wall_bounced := false
var roll_dir := 0
## Set by receive_hit for the fight manager's feedback: "", "counter" or "punish".
var last_hit_bonus := ""
var stance_names: Array = ["idle", "idle2"]
## Stage-tinted rim light that separates the silhouette from the background.
var rim := Color(0.8, 0.85, 1.0, 0.55)


func setup(fighter_def: Dictionary, player_index: int, costume_index: int = 0) -> void:
	def = fighter_def
	pid = player_index
	var costumes: Array = def.get("costumes", [{"look": def["look"]}])
	look = costumes[clampi(costume_index, 0, costumes.size() - 1)]["look"]
	H = float(def.get("height", 170))
	stance_names = STANCES.get(str(def.get("stance", "")), STANCES[""])
	max_health = float(def.get("health", 1000))
	health = max_health
	z_index = 2


func m_stat(key: String, fallback: float) -> float:
	return float(def.get(key, fallback))


# --- Input -------------------------------------------------------------------------

func set_input(i: Dictionary) -> void:
	prev = inp
	inp = i


func held(k: String) -> bool:
	return inp.get(k, false)


func pressed(k: String) -> bool:
	return inp.get(k, false) and not prev.get(k, false)


func fwd_held() -> bool:
	return held("r") if facing == 1 else held("l")


func back_held() -> bool:
	return held("l") if facing == 1 else held("r")


## Numpad-notation direction relative to facing (6 = toward the opponent).
func dir_now() -> int:
	var x := 0
	if fwd_held():
		x = 1
	elif back_held():
		x = -1
	var y := 0
	if held("u"):
		y = 1
	elif held("d"):
		y = -1
	return 5 + x + y * 3


func _record_buffer() -> void:
	for e in buf:
		e["age"] += 1
	while buf.size() > 0 and buf[0]["age"] > BUFFER_FRAMES:
		buf.pop_front()
	var d := dir_now()
	for b in ["L", "M", "H", "S"]:
		if pressed(b):
			buf.append({"b": b, "age": 0, "dir": d})
	# Double-tap detection for dashes.
	var tap_f := fwd_held() and held_dir_prev != 6 and held_dir_prev != 9 and held_dir_prev != 3
	var tap_b := back_held() and held_dir_prev != 4 and held_dir_prev != 7 and held_dir_prev != 1
	if tap_f:
		buf.append({"b": "dash_f", "age": 0, "dir": d, "gap": frame - last_tap["f"]})
		last_tap["f"] = frame
	if tap_b:
		buf.append({"b": "dash_b", "age": 0, "dir": d, "gap": frame - last_tap["b"]})
		last_tap["b"] = frame
	held_dir_prev = d


func _throw_buffered() -> bool:
	var has_m := -1
	var has_h := -1
	for e in buf:
		if e["b"] == "M":
			has_m = e["age"]
		elif e["b"] == "H":
			has_h = e["age"]
	return has_m >= 0 and has_h >= 0 and absi(has_m - has_h) <= 3


func _clear_buffer_attacks() -> void:
	buf = buf.filter(func(e): return e["b"].begins_with("dash"))


## Resolves the oldest buffered button into a move id for the given context.
func _take_buffered(ctx: String) -> String:
	if ctx != "air" and _throw_buffered():
		_clear_buffer_attacks()
		return "throw"
	for i in buf.size():
		var e: Dictionary = buf[i]
		var b: String = e["b"]
		if b.begins_with("dash"):
			continue
		var id := _resolve(b, int(e["dir"]), ctx)
		if id != "" and can_use(id):
			buf.remove_at(i)
			return id
	return ""


func _resolve(b: String, d: int, ctx: String) -> String:
	var moves: Dictionary = def["moves"]
	if b == "S":
		if ctx == "air":
			return "jS" if moves.has("jS") else ""
		if d in [1, 2, 3]:
			if moves.has("dS") and meter >= float(moves["dS"].get("meter", 1000)):
				return "dS"
			return "S"
		if d in [6, 9]:
			return "fS"
		if d in [4, 7]:
			return "bS"
		return "S"
	if ctx == "air":
		return "j" + b
	if ctx == "crouch":
		return "c" + b
	return b


func can_use(id: String) -> bool:
	var moves: Dictionary = def["moves"]
	if not moves.has(id):
		return false
	var m: Dictionary = moves[id]
	if m.get("super", false) and meter < float(m.get("meter", 1000)):
		return false
	if m.has("projectile") and m["projectile"].get("single", false) and manager != null:
		if manager.has_projectile(self, m["projectile"]["kind"]):
			return false
	return true


# --- Queries -----------------------------------------------------------------------

func grounded() -> bool:
	return pos.y >= FLOOR_Y - 0.5


func is_crouching() -> bool:
	return state in ["crouch", "block_low"] or (state == "blockstun" and stun_low) or (state == "hitstun" and hit_pose == "hit_crouch") or (state == "attack" and move.get("crouch", false))


func is_actionable() -> bool:
	return state in NEUTRAL or state == "land"


func in_move_window(arr: Array) -> bool:
	return sf >= int(arr[0]) and sf <= int(arr[1])


func is_invuln(kind: String) -> bool:
	if invuln > 0 or state in ["knockdown", "getup", "ko", "thrown", "throwing", "intro", "win", "lose"]:
		return true
	if state == "airhit" and juggle_immune:
		return true
	if state == "attack" and move.has("invuln"):
		var iv: Dictionary = move["invuln"]
		if in_move_window(iv["frames"]):
			var t: String = iv.get("type", "all")
			return t == "all" or t == kind
	return false


func is_blocking() -> bool:
	return state in ["block", "block_low", "blockstun"]


func throwable() -> bool:
	if not grounded() or is_invuln("throw"):
		return false
	return state in NEUTRAL or state in ["land", "dash_f", "dash_b", "attack", "blockstun"]


func move_total() -> int:
	return int(move.get("startup", 1)) + int(move.get("active", 1)) + int(move.get("recovery", 1))


func is_active() -> bool:
	if state != "attack":
		return false
	var st := int(move.get("startup", 1))
	return sf > st and sf <= st + int(move.get("active", 1))


func is_attacking_threat() -> bool:
	return state == "attack" and sf <= int(move.get("startup", 1)) + int(move.get("active", 1)) and (move.has("hitbox") or move.get("throw", false))


func _box(b: Array) -> Rect2:
	var x := float(b[0]) * H
	var y := float(b[1]) * H
	var w := float(b[2]) * H
	var h := float(b[3]) * H
	if facing == 1:
		return Rect2(pos.x + x, pos.y + y, w, h)
	return Rect2(pos.x - x - w, pos.y + y, w, h)


func hurtboxes() -> Array:
	var out: Array = []
	if state in ["knockdown", "getup", "ko"]:
		return out
	var b := 1.0 + (float(look.get("bulk", 1.0)) - 1.0) * 0.5
	if not grounded() or state in ["airhit", "thrown"]:
		out.append(_box([-0.14 * b, -0.9, 0.28 * b, 0.86]))
	elif is_crouching():
		out.append(_box([-0.16 * b, -0.64, 0.32 * b, 0.64]))
	else:
		out.append(_box([-0.13 * b, -0.98, 0.27 * b, 0.98]))
	if state == "attack" and move.has("hitbox") and sf > int(move.get("startup", 1)):
		var hb: Array = move["hitbox"]
		if float(hb[0]) >= 0.0:
			out.append(_box([float(hb[0]), float(hb[1]) + float(hb[3]) * 0.1, float(hb[2]) * 0.8, float(hb[3]) * 0.8]))
	return out


func pushbox() -> Rect2:
	var hw := 0.09 * H * float(look.get("bulk", 1.0))
	var top := 0.9 * H if grounded() else 0.55 * H
	return Rect2(pos.x - hw, pos.y - top, hw * 2.0, top)


func max_hits() -> int:
	var n := int(move.get("hits", 1))
	return n + 1 if amplified and n > 1 else n


func active_hitbox() -> Rect2:
	if not is_active() or not move.has("hitbox"):
		return Rect2()
	if hits_done >= max_hits():
		return Rect2()
	if hits_done > 0 and sf - last_hit_frame < int(move.get("hit_interval", 99)):
		return Rect2()
	return _box(move["hitbox"])


## The attack data for the next hit of the current move (multi-hit aware).
func current_attack() -> Dictionary:
	var a := move
	var last := hits_done + 1 >= max_hits()
	if (last and move.has("launch_last")) or amplified:
		a = move.duplicate()
		if last and move.has("launch_last"):
			a["launch"] = move["launch_last"]
		if amplified:
			a["damage"] = float(move.get("damage", 0)) * 1.35
			a["hitstun"] = int(move.get("hitstun", 15)) + 3
			a["amp"] = true
	return a


# --- State control ---------------------------------------------------------------------

func set_state(s: String) -> void:
	if s != state:
		state = s
		sf = 0


func face_opponent() -> void:
	if opponent == null:
		return
	var dx: float = opponent.pos.x - pos.x
	if absf(dx) > 1.0:
		facing = 1 if dx > 0 else -1


func start_move(id: String) -> void:
	var m: Dictionary = def["moves"][id]
	move = m
	move_id = id
	set_state("attack")
	sf = 0
	move_connected = false
	hits_done = 0
	last_hit_frame = -100
	counter_triggered = false
	armor_used = 0
	amplified = false
	spawned = {}
	phase_through = m.get("phase", false)
	if m.get("super", false):
		meter = maxf(0.0, meter - float(m.get("meter", 1000)))
		if manager != null:
			manager.on_super(self, m)
	if m.get("sfx", "") == "slash":
		Sound.play("slash", 1.0 + randf() * 0.15, -3.0)
	elif m.has("sfx") and not m.has("hitbox"):
		Sound.play(m["sfx"])
	elif m.has("projectile") or m.has("teleport"):
		pass
	else:
		Sound.play("whoosh", 1.0 + randf() * 0.2, -6.0)
	if grounded() and not m.has("vel") and not m.has("impulse"):
		vel.x *= 0.3


func end_move() -> void:
	phase_through = false
	move = {}
	move_id = ""
	if grounded():
		vel = Vector2.ZERO
		set_state("idle")
		face_opponent()
	else:
		set_state("air")
		used_air_attack = true


func to_neutral() -> void:
	combo_hits = 0
	combo_damage = 0.0
	air_juggle = 0
	juggle_immune = false
	wall_bounced = false
	wall_bounce_ok = false
	roll_dir = 0
	set_state("idle")
	face_opponent()


# --- Main tick ---------------------------------------------------------------------------

func step() -> void:
	frame += 1
	_record_buffer()
	if hitstop > 0:
		hitstop -= 1
		flash = maxf(0.0, flash - 0.08)
		return
	sf += 1
	if invuln > 0:
		invuln -= 1
	flash = maxf(0.0, flash - 0.12)
	alpha = 1.0
	match state:
		"idle", "walk_f", "walk_b", "crouch", "block", "block_low":
			_neutral()
		"land":
			vel.x = 0
			if sf >= 4:
				to_neutral()
				_neutral()
		"prejump":
			vel.x = 0
			if sf >= 3:
				_launch_jump()
		"air":
			_air()
		"dash_f", "dash_b":
			_dash()
		"attack":
			_process_move()
		"hitstun":
			if _try_breaker():
				return
			_slide()
			stun -= 1
			if stun <= 0:
				to_neutral()
		"blockstun":
			_slide()
			stun -= 1
			if stun <= 0:
				set_state("block_low" if stun_low else "block")
				if not held("B"):
					to_neutral()
		"airhit":
			if _try_breaker():
				return
			_airhit()
		"knockdown":
			vel = Vector2.ZERO
			if sf >= 34:
				set_state("getup")
			elif sf >= 6 and controlled and health > 0 and (pressed("L") or pressed("M") or pressed("H") or pressed("S") or pressed("B")):
				# Quick rise; hold back to roll away.
				roll_dir = -facing if back_held() else 0
				set_state("getup")
				if manager != null:
					manager.fx_text(pos + Vector2(0, -H * 0.4), "ROLL" if roll_dir != 0 else "QUICK RISE", Color(0.8, 0.9, 1.0))
		"getup":
			if roll_dir != 0:
				pos.x += roll_dir * 4.0
				if manager != null:
					manager.clamp_fighter(self)
			if sf >= 20:
				invuln = 3
				to_neutral()
		"ko":
			_ko_fall()
		"throwing":
			_throwing()
		"thrown":
			_thrown()
		"intro", "win", "lose":
			vel = Vector2.ZERO
		_:
			to_neutral()
	_trail_update()
	display_pose = _compute_pose()
	cape_sway = lerpf(cape_sway, clampf(absf(vel.x) / 10.0 + (0.5 if not grounded() else 0.0), 0.0, 1.0), 0.15)


func _neutral() -> void:
	if not controlled:
		vel.x = 0
		if state != "idle":
			set_state("idle")
		return
	face_opponent()
	var crouching := held("d")
	var id := _take_buffered("crouch" if crouching else "ground")
	if id != "":
		start_move(id)
		return
	if held("u"):
		set_state("prejump")
		vel.x = 0
		return
	if held("B"):
		set_state("block_low" if crouching else "block")
		vel.x = 0
		return
	if crouching:
		set_state("crouch")
		vel.x = 0
		return
	for i in range(buf.size() - 1, -1, -1):
		var e: Dictionary = buf[i]
		if e["b"].begins_with("dash") and int(e.get("gap", 99)) <= 14:
			buf.remove_at(i)
			set_state(e["b"])
			Sound.play("whoosh", 1.3, -8.0)
			return
	if fwd_held():
		set_state("walk_f")
		vel.x = m_stat("walk", 3.5) * facing
	elif back_held():
		set_state("walk_b")
		vel.x = -m_stat("back_walk", 3.0) * facing
	else:
		set_state("idle")
		vel.x = 0
	pos.x += vel.x


func _launch_jump() -> void:
	jump_dir = 0
	if fwd_held():
		jump_dir = 1
	elif back_held():
		jump_dir = -1
	var j: Array = def.get("jump", [4.5, -16.0])
	vel = Vector2(float(j[0]) * jump_dir * facing, float(j[1]))
	pos.y = FLOOR_Y - 1.0
	used_air_attack = false
	air_time = 0
	air_total = int(2.0 * absf(float(j[1])) / m_stat("gravity", 0.8))
	set_state("air")
	Sound.play("jump", 1.0, -6.0)


func _air() -> void:
	air_time += 1
	if not used_air_attack and controlled:
		var id := _take_buffered("air")
		if id != "":
			used_air_attack = true
			start_move(id)
			_physics_air()
			return
	_physics_air()
	if grounded():
		_land()


func _physics_air() -> void:
	vel.y += m_stat("gravity", 0.8)
	pos += vel
	if pos.y >= FLOOR_Y:
		pos.y = FLOOR_Y


func _land() -> void:
	pos.y = FLOOR_Y
	vel = Vector2.ZERO
	set_state("land")
	face_opponent()
	Sound.play("land", 1.0, -8.0)
	if manager != null:
		manager.fx_dust(pos, 1.0)


func _dash() -> void:
	var dur := 14 if state == "dash_f" else 12
	var sp := m_stat("dash", 8.0)
	var k := 1.0 - float(sf) / dur
	vel.x = (sp if state == "dash_f" else -sp * 0.9) * facing * maxf(0.2, k)
	pos.x += vel.x
	if state == "dash_b" and sf <= 5:
		invuln = maxi(invuln, 1)
	if sf >= dur:
		vel.x = 0
		to_neutral()


func _slide() -> void:
	pos.x += slide
	slide *= 0.82
	if absf(slide) < 0.1:
		slide = 0.0
	if not grounded():
		vel.y += m_stat("gravity", 0.8)
		pos.y += vel.y
		if pos.y >= FLOOR_Y:
			pos.y = FLOOR_Y


func _try_breaker() -> bool:
	if breaker_used or not controlled or meter < BAR * 2.0 - 0.5 or combo_hits < 2 or health <= 0.0 or juggle_immune:
		return false
	if pressed("B") and fwd_held():
		breaker_used = true
		meter -= BAR * 2.0
		if manager != null:
			manager.on_breaker(self)
		return true
	return false


func _airhit() -> void:
	vel.y += m_stat("gravity", 0.8) * 0.9
	pos += vel
	if wall_bounce_ok and not wall_bounced and manager != null and absf(vel.x) > 3.0 and pos.y < FLOOR_Y - 20.0 and manager.at_wall(self):
		wall_bounced = true
		vel.x = -vel.x * 0.35
		vel.y = minf(vel.y, -6.5)
		manager.fx_wallbounce(self)
	if pos.y >= FLOOR_Y and vel.y > 0:
		pos.y = FLOOR_Y
		vel = Vector2.ZERO
		if manager != null:
			manager.fx_dust(pos, 1.6)
		Sound.play("land", 0.8, -2.0)
		if health <= 0:
			set_state("ko")
		else:
			set_state("knockdown")
			juggle_immune = false


func _ko_fall() -> void:
	if not grounded():
		vel.y += m_stat("gravity", 0.8)
		pos += vel
		if pos.y >= FLOOR_Y:
			pos.y = FLOOR_Y
			vel = Vector2.ZERO
	else:
		vel = Vector2.ZERO


func _process_move() -> void:
	var m := move
	var st := int(m.get("startup", 1))
	var ac := int(m.get("active", 1))
	var f := sf
	# Counter stance follow-up.
	if counter_triggered and m.has("counter"):
		counter_triggered = false
		face_opponent()
		start_move(m["counter"]["move"])
		if manager != null:
			manager.fx_text(pos + Vector2(0, -H * 1.1), "COUNTER!", Color(0.6, 0.9, 1.0))
		return
	# Amplify: press Block during a special's start-up to spend one bar.
	if not amplified and m.get("special", false) and not m.get("super", false) and not m.get("hidden", false) and f <= st and controlled and pressed("B") and meter >= BAR - 0.5:
		amplified = true
		meter -= BAR
		flash = 0.7
		if manager != null:
			manager.on_amplify(self)
	if m.has("heal") and f == int(m.get("heal_frame", st)):
		health = minf(max_health, health + float(m["heal"]))
		if manager != null:
			manager.fx_text(pos + Vector2(0, -H * 1.1), "+%d" % int(m["heal"]), Color(0.5, 1.0, 0.5))
	# Chains and special cancels after connecting.
	if move_connected and f > st and controlled:
		var ctx := "air" if not grounded() else ("crouch" if held("d") else "ground")
		for i in buf.size():
			var e: Dictionary = buf[i]
			if e["b"].begins_with("dash"):
				continue
			var nid := _resolve(e["b"], int(e["dir"]), ctx)
			var chain: Array = m.get("chain", [])
			var is_special: bool = nid != "" and def["moves"].has(nid) and def["moves"][nid].get("special", false)
			var ok: bool = nid in chain or (is_special and (not m.get("special", false) or def["moves"][nid].get("super", false)))
			if ok and nid != move_id and can_use(nid):
				buf.remove_at(i)
				start_move(nid)
				return
	# Teleport.
	if m.has("teleport") and f == int(m["teleport"]["frame"]):
		_teleport(m["teleport"])
	# Velocity.
	var flying: bool = m.get("fly", false)
	if m.has("vel"):
		var vf: Array = m.get("vel_frames", [1, st + ac])
		var v: Array = m["vel"]
		if in_move_window(vf) and not (m.get("stop_on_hit", false) and move_connected):
			vel.x = float(v[0]) * facing
			if float(v[1]) != 0.0:
				vel.y = float(v[1])
		elif f > int(vf[1]) or (m.get("stop_on_hit", false) and move_connected):
			vel.x *= 0.6
			if flying:
				vel.y = 0.0
	elif grounded():
		vel.x *= 0.7
	if m.has("impulse") and f == int(m.get("impulse_frame", 1)):
		var imp: Array = m["impulse"]
		vel = Vector2(float(imp[0]) * facing, float(imp[1]))
		pos.y = minf(pos.y, FLOOR_Y - 1.0)
	# Gravity for airborne moves.
	var airborne := not grounded() or vel.y < 0
	if airborne and not (flying and m.has("vel") and in_move_window(m.get("vel_frames", [1, 1]))):
		if not (m.has("teleport") and m["teleport"].get("to", "") == "above" and f <= int(m["teleport"]["frame"]) + 2):
			vel.y += m_stat("gravity", 0.8)
	pos += vel
	if flying and pos.y < FLOOR_Y and not airborne:
		pos.y = FLOOR_Y
	# Landing.
	if airborne and pos.y >= FLOOR_Y:
		pos.y = FLOOR_Y
		vel.y = 0
		if m.get("air", false) or m.get("land_cancel", false) or m.has("impulse"):
			if m.has("on_land_projectile") and manager != null:
				manager.spawn_projectile(self, m["on_land_projectile"])
				manager.shake(6.0)
			_land()
			if not m.get("air", false):
				sf = -6
			return
	elif not airborne:
		pos.y = FLOOR_Y
	# Projectiles.
	if m.has("projectile") and manager != null:
		var p: Dictionary = m["projectile"]
		var count := int(p.get("count", 1))
		var every := int(p.get("every", 1))
		for i in count:
			var at := int(p.get("frame", st)) + i * every
			if f == at and not spawned.has(i):
				spawned[i] = true
				var pd := p
				if i == count - 1 and p.has("launch_last"):
					pd = p.duplicate()
					pd["launch"] = p["launch_last"]
				manager.spawn_projectile(self, pd, i)
	# Alpha (teleports / phasing).
	if m.has("alpha") and in_move_window(m["alpha"]["frames"]):
		alpha = float(m["alpha"]["value"])
	if m.has("fx") and manager != null and f == st + 1:
		manager.fx_move(self, m["fx"])
	if f >= move_total():
		end_move()


func _teleport(tp: Dictionary) -> void:
	if opponent == null:
		return
	var to: String = tp.get("to", "behind")
	var dist := float(tp.get("dist", 0.4)) * H
	if manager != null:
		manager.fx_teleport(pos + Vector2(0, -H * 0.5), look.get("power", Color.WHITE))
	match to:
		"behind":
			var side := 1 if opponent.pos.x >= pos.x else -1
			pos.x = opponent.pos.x + side * dist
		"front":
			var side2 := -1 if opponent.pos.x >= pos.x else 1
			pos.x = opponent.pos.x + side2 * dist
		"above":
			pos.x = opponent.pos.x - float(opponent.facing) * 0.0
			pos.y = FLOOR_Y - H * 1.15
			vel = Vector2.ZERO
	if manager != null:
		manager.clamp_fighter(self)
		manager.fx_teleport(pos + Vector2(0, -H * 0.5), look.get("power", Color.WHITE))
	face_opponent()


func _throwing() -> void:
	vel = Vector2.ZERO
	if throw_victim == null:
		end_move()
		return
	if sf < 18:
		throw_victim.pos = Vector2(pos.x + facing * H * 0.32, FLOOR_Y)
	elif sf == 18:
		var dmg := float(def["moves"]["throw"].get("damage", 120))
		throw_victim.thrown_release(self, dmg)
		Sound.play("throw")
		if manager != null:
			manager.shake(5.0)
	if sf >= 40:
		throw_victim = null
		to_neutral()


func _thrown() -> void:
	tech_window -= 1
	if tech_window > 0 and controlled and _throw_buffered():
		_clear_buffer_attacks()
		if manager != null:
			manager.throw_break(thrower, self)
		return
	if thrower == null:
		to_neutral()


func begin_throw(victim: Node2D) -> void:
	throw_victim = victim
	set_state("throwing")
	victim.thrower = self
	victim.set_state("thrown")
	victim.tech_window = 10
	victim.vel = Vector2.ZERO
	victim.move = {}
	victim.facing = -facing


func thrown_release(by: Node2D, dmg: float) -> void:
	thrower = null
	health -= dmg
	combo_hits += 1
	combo_damage += dmg
	pos.x = by.pos.x - by.facing * H * 0.25
	pos.y = FLOOR_Y - 30
	vel = Vector2(-by.facing * 4.0, -7.0)
	flash = 1.0
	set_state("airhit")
	if manager != null:
		manager.clamp_fighter(self)
		manager.fx_spark(pos + Vector2(0, -H * 0.4), 1.4, Color(1, 0.9, 0.6))


## Applies an incoming attack. Returns "whiff", "block", "armor", "countered" or "hit".
func receive_hit(a: Dictionary, src: Node2D, is_proj: bool) -> String:
	if is_invuln("projectile" if is_proj else "strike"):
		return "whiff"
	if not is_proj and state == "attack" and move.has("counter") and in_move_window(move["counter"]["window"]):
		counter_triggered = true
		hitstop = 6
		return "countered"
	var level: String = a.get("level", "mid")
	var dmg := float(a.get("damage", 0))
	var away := -1 if src.pos.x > pos.x else 1
	if src.pos.x == pos.x:
		away = -src.facing
	if is_blocking() and grounded():
		var low := state == "block_low" or (state == "blockstun" and stun_low)
		var blocked := true
		if level == "low" and not low:
			blocked = false
		elif level == "overhead" and low:
			blocked = false
		if blocked:
			health -= dmg * float(a.get("chip", 0.0))
			stun = int(a.get("blockstun", 10))
			stun_low = low
			set_state("blockstun")
			slide = away * float(a.get("push", 5)) * 0.9
			meter = minf(1000.0, meter + dmg * 0.25)
			return "block"
	var has_armor: bool = state == "attack" and move.has("armor") and in_move_window(move["armor"]["frames"]) and armor_used < int(move["armor"].get("hits", 1))
	var amp_armor: bool = state == "attack" and amplified and sf <= int(move.get("startup", 1)) + int(move.get("active", 1)) and armor_used < 1
	if has_armor or amp_armor:
		armor_used += 1
		health -= dmg * 0.5
		flash = 0.6
		return "armor"
	# Clean hit. Counter hits (interrupting start-up) and punishes (hitting recovery) hurt more.
	last_hit_bonus = ""
	if combo_hits == 0 and state == "attack" and not move.is_empty():
		var st2 := int(move.get("startup", 1))
		if sf <= st2:
			last_hit_bonus = "counter"
		elif sf > st2 + int(move.get("active", 1)):
			last_hit_bonus = "punish"
	elif combo_hits == 0 and state in ["dash_b", "land"]:
		last_hit_bonus = "punish"
	combo_hits += 1
	var floor_scale := 0.6 if a.get("super", false) else 0.35
	var scale := maxf(floor_scale, 1.0 - 0.09 * float(combo_hits - 1))
	if last_hit_bonus == "counter":
		scale *= 1.2
	elif last_hit_bonus == "punish":
		scale *= 1.1
	var d := dmg * scale
	health -= d
	combo_damage += d
	meter = minf(1000.0, meter + d * 0.5)
	flash = 1.0
	phase_through = false
	move = {}
	move_id = ""
	var hs := maxi(6, int(a.get("hitstun", 15)) - maxi(0, combo_hits - 5) + (4 if last_hit_bonus == "counter" else 0))
	var launch: Array = a.get("launch", [])
	if health <= 0.0:
		launch = [4.0, -8.0] if launch.is_empty() else launch
	if not grounded() or not launch.is_empty() or a.get("knockdown", false):
		air_juggle += 1
		if air_juggle > MAX_JUGGLE:
			juggle_immune = true
		var lv := Vector2(4.0, -6.0)
		if not launch.is_empty():
			lv = Vector2(float(launch[0]), float(launch[1]))
		elif a.get("knockdown", false):
			lv = Vector2(5.0, -7.0)
		vel = Vector2(lv.x * away, lv.y)
		pos.y = minf(pos.y, FLOOR_Y - 1.0)
		wall_bounce_ok = lv.x >= 5.0 and air_juggle <= 2
		set_state("airhit")
	else:
		stun = hs
		if is_crouching():
			hit_pose = "hit_crouch"
		elif level == "low" or (a.has("hitbox") and float(a["hitbox"][1]) > -0.6):
			hit_pose = "hit_low"
		else:
			hit_pose = "hit"
		set_state("hitstun")
		vel = Vector2.ZERO
		slide = away * float(a.get("push", 5))
	if a.get("pull", 0) and src != null:
		pos.x = move_toward(pos.x, src.pos.x, float(a["pull"]))
	return "hit"


func register_hit(result: String) -> void:
	if result == "whiff":
		return
	move_connected = true
	hits_done += 1
	last_hit_frame = sf
	if result == "countered":
		hits_done = max_hits()
	var dmg := float(move.get("damage", 0))
	meter = minf(1000.0, meter + dmg * (0.7 if result == "hit" else 0.3))


# --- Visuals ---------------------------------------------------------------------------------

func _trail_update() -> void:
	var trailing: bool = (state == "attack" and move.get("trail", false)) or (def.get("trail", false) and state in ["dash_f", "dash_b", "walk_f"])
	if trailing and frame % 2 == 0:
		afterimages.push_front({"p": pos, "f": facing, "pose": display_pose, "life": 1.0})
	for ai in afterimages:
		ai["life"] -= 0.12
	while afterimages.size() > 0 and afterimages[-1]["life"] <= 0.0:
		afterimages.pop_back()
	if afterimages.size() > 6:
		afterimages.resize(6)


func _compute_pose() -> Dictionary:
	match state:
		"idle":
			var breathe := (sin(frame * 0.09) + 1.0) * 0.5
			return Poses.blend(Poses.get_pose(stance_names[0]), Poses.get_pose(stance_names[1]), breathe * breathe * (3.0 - 2.0 * breathe))
		"walk_f":
			return Poses.cycle(["walk1", "walk2", "walk3", "walk4"], frame, 6)
		"walk_b":
			return Poses.cycle(["walk4", "walk3", "walk2", "walk1"], frame, 7)
		"crouch":
			return Poses.blend(Poses.get_pose("idle"), Poses.get_pose("crouch"), minf(1.0, sf / 3.0))
		"block":
			return Poses.get_pose("block")
		"block_low":
			return Poses.get_pose("block_low")
		"blockstun":
			return Poses.get_pose("block_low" if stun_low else "block")
		"prejump", "land":
			return Poses.get_pose("prejump")
		"air":
			var p := Poses.blend(Poses.get_pose("jump"), Poses.get_pose("jump_tuck"), clampf((vel.y + 10.0) / 10.0, 0.0, 1.0))
			if def.get("flip_jump", false) and jump_dir != 0:
				var k := clampf(float(air_time) / maxf(1.0, air_total * 0.85), 0.0, 1.0)
				p = Poses.with_rot(Poses.get_pose("jump_tuck"), 360.0 * k * jump_dir)
			return p
		"dash_f":
			return Poses.get_pose("dash")
		"dash_b":
			return Poses.get_pose("backdash")
		"attack":
			return _move_pose()
		"hitstun":
			return Poses.get_pose(hit_pose)
		"airhit", "thrown":
			var spin := clampf(vel.y * 3.0, -30.0, 40.0) if state == "airhit" else 0.0
			return Poses.with_rot(Poses.get_pose("airhit"), spin)
		"knockdown", "ko":
			if not grounded():
				return Poses.get_pose("airhit")
			return Poses.get_pose("knockdown")
		"getup":
			var k2 := float(sf) / 20.0
			var gp: Dictionary
			if k2 < 0.5:
				gp = Poses.blend(Poses.get_pose("knockdown"), Poses.get_pose("getup"), k2 * 2.0)
			else:
				gp = Poses.blend(Poses.get_pose("getup"), Poses.get_pose(stance_names[0]), (k2 - 0.5) * 2.0)
			if roll_dir != 0 and k2 < 0.7:
				gp = Poses.with_rot(Poses.get_pose("jump_tuck"), -360.0 * (k2 / 0.7) * float(roll_dir * facing))
			return gp
		"throwing":
			return Poses.get_pose("throw_w" if sf < 18 else "throw_s")
		"intro":
			return Poses.blend(Poses.get_pose("super"), Poses.get_pose("idle"), clampf((sf - 40) / 20.0, 0.0, 1.0))
		"win":
			return Poses.blend(Poses.get_pose("idle"), Poses.get_pose(def.get("victory_pose", "victory")), minf(1.0, sf / 12.0))
		"lose":
			return Poses.blend(Poses.get_pose("idle"), Poses.get_pose("defeat"), minf(1.0, sf / 16.0))
	return Poses.get_pose("idle")


func _move_pose() -> Dictionary:
	var m := move
	var names: Array = m.get("pose", ["idle"])
	var w := Poses.get_pose(names[0])
	var s := Poses.get_pose(names[names.size() - 1])
	var base_name: String = stance_names[0]
	if m.get("crouch", false) or m.get("crouch_start", false):
		base_name = "crouch"
	elif not grounded() and m.get("air", false):
		base_name = "jump_tuck"
	var base := Poses.get_pose(base_name)
	var st := int(m.get("startup", 1))
	var ac := int(m.get("active", 1))
	var rc := int(m.get("recovery", 1))
	var f := sf
	if f <= st:
		# Wind-up eases in, then the strike snaps out (ease-out) for impact.
		var k := float(f) / float(st)
		if k < 0.6:
			var kw := k / 0.6
			return Poses.blend(base, w, kw * kw * (3.0 - 2.0 * kw))
		var ks := (k - 0.6) / 0.4
		return Poses.blend(w, s, 1.0 - (1.0 - ks) * (1.0 - ks))
	if f <= st + ac:
		if m.has("pose_cycle"):
			var cyc: Array = m["pose_cycle"]
			var per := maxi(2, int(m.get("hit_interval", 4)))
			var i := ((f - st) / per) % cyc.size()
			return Poses.get_pose(cyc[i])
		return s
	var end_pose := base
	if not grounded():
		end_pose = Poses.get_pose("jump_tuck")
	elif m.get("crouch", false):
		end_pose = Poses.get_pose("crouch")
	var kr := clampf((float(f - st - ac) / float(rc) - 0.25) / 0.75, 0.0, 1.0)
	return Poses.blend(s, end_pose, kr * kr * (3.0 - 2.0 * kr))


func _draw() -> void:
	var gy := FLOOR_Y - pos.y
	var sh_scale := clampf(1.0 - (FLOOR_Y - pos.y) / 300.0, 0.4, 1.0)
	draw_set_transform(Vector2(0, gy), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 0.19 * H * float(look.get("bulk", 1.0)) * sh_scale, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var power: Color = look.get("power", Color.WHITE)
	for ai in afterimages:
		var c := Color(power.r, power.g, power.b, 0.35 * float(ai["life"]))
		Rig.draw(self, (ai["p"] as Vector2) - pos, ai["f"], ai["pose"], look, H, {"solid": c})
	_draw_smear(power)
	var o := {"flash": flash, "alpha": alpha, "sway": cape_sway, "time": frame / 60.0}
	if amplified and state == "attack":
		o["outline"] = power.lightened(0.3)
	if meter >= 1000.0 and state in NEUTRAL:
		var pulse := (sin(frame * 0.2) + 1.0) * 0.5
		o["outline"] = Rig.OUTLINE.lerp(power, 0.2 + 0.35 * pulse)
	if alpha > 0.9:
		Rig.draw(self, Vector2(-1.5 * facing, -1.0), facing, display_pose, look, H, {"solid": rim, "sway": cape_sway, "time": frame / 60.0})
	Rig.draw(self, Vector2.ZERO, facing, display_pose, look, H, o)
	if show_boxes:
		for r in hurtboxes():
			var rr: Rect2 = r
			draw_rect(Rect2(rr.position - pos, rr.size), Color(0.2, 0.6, 1.0, 0.8), false, 1.0)
		var hb := active_hitbox()
		if hb.size != Vector2.ZERO:
			draw_rect(Rect2(hb.position - pos, hb.size), Color(1.0, 0.15, 0.15, 0.9), false, 1.0)
		var pb := pushbox()
		draw_rect(Rect2(pb.position - pos, pb.size), Color(1, 1, 0.2, 0.5), false, 1.0)


## Motion smear: a translucent arc from the wind-up to the strike position of
## whichever hand or foot moved the most, on the first frames of a strike.
func _draw_smear(power: Color) -> void:
	if state != "attack" or not is_active() or move.has("pose_cycle"):
		return
	var st := int(move.get("startup", 1))
	if sf > st + 2:
		return
	var names: Array = move.get("pose", ["idle"])
	if names.size() < 2:
		return
	var jw := Rig.solve(Poses.get_pose(names[0]), H, look)
	var js := Rig.solve(Poses.get_pose(names[names.size() - 1]), H, look)
	var best := "hf"
	var dist := 0.0
	for key in ["hf", "hb", "ftf", "ftb"]:
		var d: float = (js[key] as Vector2).distance_to(jw[key])
		if d > dist:
			dist = d
			best = key
	if dist < 0.12 * H:
		return
	var a: Vector2 = jw[best]
	var b: Vector2 = js[best]
	a.x *= facing
	b.x *= facing
	var mid := (a + b) * 0.5 + (b - a).normalized().rotated(-PI * 0.5 * facing) * dist * 0.25
	var pts := PackedVector2Array()
	for i in 7:
		var t := i / 6.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	var fade := 1.0 - float(sf - st - 1) / 2.0
	draw_polyline(pts, Color(power.r, power.g, power.b, 0.35 * fade), 0.07 * H)
	draw_polyline(pts, Color(1, 1, 1, 0.45 * fade), 2.0)
