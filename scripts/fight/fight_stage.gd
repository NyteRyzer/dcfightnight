extends Node2D
## Fight manager: builds the arena, fighters and HUD, runs the deterministic
## 60 Hz fight loop, resolves hits/throws/projectiles, and handles rounds,
## pause, results and training mode.

const FighterScene = preload("res://scenes/fight/Fighter.tscn")
const HUDScene = preload("res://scenes/fight/HUD.tscn")
const Projectile = preload("res://scripts/combat/projectile.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Arena = preload("res://scripts/arenas/arena.gd")
const CpuAI = preload("res://scripts/combat/cpu_ai.gd")
const MenuList = preload("res://scripts/ui/menu_list.gd")

const STAGE_W := 1000.0
const FLOOR_Y := 322.0
const HALF_VIEW := 320.0
const EDGE := 22.0

@export var training := false
## When true (tests), both fighters are CPU-driven and menus never block.
var autoplay := false

var fighters: Array = []
var projectiles: Array = []
var ai: Array = [null, null]
var arena: Node2D
var fx: Node2D
var world: Node2D
var cam: Camera2D
var hud: Control
var ui: CanvasLayer
var menu: Control = null
var result_panel: Control = null

var phase := "vs"
var pt := 0
var round_num := 1
var rounds_to_win := 2
var round_time := 99
var timer := 0
var cinematic := 0
var slowmo := 0
var shake_amt := 0.0
var cam_x := STAGE_W * 0.5
var winner := -1
var match_winner := -1
var regen_wait := [0, 0]
var last_move := ["", ""]
var total_frames := 0
var hit_count := [0, 0]
var pause_lock := 0
var zoom_punch := 0.0
var first_strike := false
var ko_freeze := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	world = Node2D.new()
	add_child(world)
	arena = Arena.new()
	arena.stage_id = Game.stage_id
	arena.glitch = Game.fight_opts.get("glitch", false)
	arena.z_index = -10
	world.add_child(arena)
	for i in 2:
		var f: Node2D = FighterScene.instantiate()
		f.setup(Data.fighter(Game.chars[i]), i, Game.costume[i])
		f.manager = self
		var rc := Color.html(str(Data.stage(Game.stage_id).get("rim", "#c8d8ff")))
		rc.a = 0.6
		f.rim = rc
		world.add_child(f)
		fighters.append(f)
	fighters[0].opponent = fighters[1]
	fighters[1].opponent = fighters[0]
	fx = Effects.new()
	fx.z_index = 5
	fx.reduce_flash = Game.settings.get("reduce_flash", false)
	world.add_child(fx)
	cam = Camera2D.new()
	cam.position = Vector2(cam_x, 180)
	add_child(cam)
	cam.make_current()
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	hud = HUDScene.instantiate()
	hud.fight = self
	ui.add_child(hud)
	hud.ladder_label = Game.fight_opts.get("ladder_label", "")

	var boss: bool = Game.fight_opts.get("boss", false)
	if boss:
		var cf: Node2D = fighters[1]
		cf.max_health = float(cf.def.get("boss_health", cf.max_health))
		cf.health = cf.max_health
	rounds_to_win = 1 if Game.fight_opts.get("single_round", false) else int(Game.settings.get("rounds", 2))
	round_time = int(Game.settings.get("round_time", 99))
	if training:
		round_time = 0
		rounds_to_win = 99
	var level: int = Game.fight_opts.get("cpu_level", int(Game.settings.get("difficulty", 2)))
	if boss:
		level = mini(4, level + 1)
	for i in 2:
		if Game.cpu[i] or autoplay:
			var brain := CpuAI.new()
			brain.setup(fighters[i], fighters[1 - i], self, level)
			if training and i == 1:
				brain.mode = Game.training.get("dummy", "stand")
			ai[i] = brain
	_play_music()
	InputManager.pad_disconnected.connect(_on_pad_lost)
	if training:
		_reset_positions()
		phase = "fight"
		for f in fighters:
			f.controlled = true
			f.meter = 1000.0
	else:
		phase = "vs"
		hud.vs_t = 150
		_reset_positions()
	_update_camera()


func enable_autoplay() -> void:
	autoplay = true
	for i in 2:
		if ai[i] == null:
			var brain := CpuAI.new()
			brain.setup(fighters[i], fighters[1 - i], self, 3)
			ai[i] = brain
		ai[i].mode = "cpu"


func _play_music() -> void:
	if Game.fight_opts.get("boss", false) or Game.stage_id == "freak_studio":
		Sound.play_music("boss")
	elif Game.mode == "survival":
		Sound.play_music("survival")
	else:
		var idx := int(Data.stage(Game.stage_id).get("music", 0))
		Sound.play_music("fight", (idx % 5) - 2)


# --- Round flow -----------------------------------------------------------------------

func _reset_positions() -> void:
	projectiles.map(func(p): p.queue_free())
	projectiles.clear()
	cam_x = STAGE_W * 0.5
	for i in 2:
		var f: Node2D = fighters[i]
		f.pos = Vector2(STAGE_W * 0.5 + (-125.0 if i == 0 else 125.0), FLOOR_Y)
		f.vel = Vector2.ZERO
		f.facing = 1 if i == 0 else -1
		f.move = {}
		f.stun = 0
		f.hitstop = 0
		f.invuln = 0
		f.combo_hits = 0
		f.afterimages.clear()
		f.set_state("idle")
		f.position = f.pos


func start_round() -> void:
	_reset_positions()
	hud.vs_t = 0
	first_strike = false
	for i in 2:
		var f: Node2D = fighters[i]
		f.breaker_used = false
		f.health = f.max_health
		if i == 0 and Game.fight_opts.has("start_health") and round_num == 1:
			f.health = f.max_health * float(Game.fight_opts["start_health"])
		f.set_state("intro")
		f.controlled = false
	timer = round_time * 60
	phase = "intro"
	pt = 0
	var label := "FINAL ROUND" if fighters[0].wins == rounds_to_win - 1 and fighters[1].wins == rounds_to_win - 1 and rounds_to_win > 1 else "ROUND %d" % round_num
	if rounds_to_win == 1:
		label = "FIGHT NIGHT"
	hud.announce(label, Data.stage(Game.stage_id).get("name", ""), 58, Color(1, 1, 1))
	Sound.play("bell")
	Sound.announce("round")


func _physics_process(_delta: float) -> void:
	pt += 1
	total_frames += 1
	match phase:
		"vs":
			if pt > 150 or (pt > 30 and (InputManager.menu("accept") or autoplay)):
				start_round()
		"intro":
			_sim(false)
			if pt == 62:
				hud.announce("FIGHT!", "", 40, Color(1, 0.3, 0.2))
				Sound.announce("fight")
			if pt >= 70:
				phase = "fight"
				for f in fighters:
					if f.state == "intro":
						f.to_neutral()
		"fight":
			_sim(true)
			if not training:
				_check_round_end()
			else:
				_training_tick()
			if pause_lock > 0:
				pause_lock -= 1
			elif Input.is_action_just_pressed("pause") and not autoplay:
				open_pause()
		"ko":
			_sim(false)
			_ko_phase()
		"roundwin":
			_sim(false)
			if pt >= 150:
				_after_round()
		"result":
			_sim(false)
			if autoplay and pt > 30:
				phase = "done"
	_update_camera()
	hud.tick()


func _sim(control: bool) -> void:
	if cinematic > 0:
		cinematic -= 1
		arena.dim = 0.65
		fx.step()
		for f in fighters:
			f.queue_redraw()
		return
	arena.dim = maxf(0.0, arena.dim - 0.06)
	if slowmo > 0:
		slowmo -= 1
		if slowmo % 2 == 1:
			fx.step()
			return
	for i in 2:
		var f: Node2D = fighters[i]
		var inp := {}
		if control:
			if ai[i] != null:
				inp = ai[i].think()
			else:
				inp = InputManager.sample(i)
		f.controlled = control
		f.set_input(inp)
	for f in fighters:
		var was: String = f.move_id
		f.step()
		if f.move_id != "" and f.move_id != was:
			last_move[f.pid] = f.move_id
	_push_apart()
	for f in fighters:
		clamp_fighter(f)
	_step_projectiles()
	_resolve_hits()
	_resolve_throws()
	var a: Node2D = fighters[0]
	var b: Node2D = fighters[1]
	a.z_index = 3 if a.state == "attack" and b.state != "attack" else 2
	b.z_index = 3 if a.z_index == 2 else 2
	for f in fighters:
		f.position = f.pos.round()
		f.queue_redraw()
	fx.step()


func _check_round_end() -> void:
	var d0: bool = fighters[0].health <= 0.0
	var d1: bool = fighters[1].health <= 0.0
	if d0 or d1:
		_on_ko(d0, d1)
		return
	if round_time > 0:
		timer -= 1
		if timer <= 0:
			_on_timeout()


func _on_ko(d0: bool, d1: bool) -> void:
	phase = "ko"
	pt = 0
	slowmo = 50
	winner = -1 if (d0 and d1) else (1 if d0 else 0)
	for i in 2:
		var f: Node2D = fighters[i]
		if f.health <= 0.0:
			f.health = 0.0
			if f.state not in ["airhit", "ko"]:
				var away := -1 if f.opponent.pos.x > f.pos.x else 1
				f.vel = Vector2(4.0 * away, -7.0)
				f.pos.y = minf(f.pos.y, FLOOR_Y - 1.0)
				f.set_state("airhit")
	hud.announce("K.O.", "", 90, Color(1, 0.2, 0.15))
	hud.flash_t = 10
	zoom_punch = 0.12
	for i in 2:
		_rumble(i, 0.8, 0.5)
	Sound.play("ko")
	Sound.announce("ko_voice")
	shake(8.0)


func _on_timeout() -> void:
	var r0: float = fighters[0].health / fighters[0].max_health
	var r1: float = fighters[1].health / fighters[1].max_health
	winner = -1 if absf(r0 - r1) < 0.001 else (0 if r0 > r1 else 1)
	phase = "ko"
	pt = 60
	hud.announce("TIME", "", 70, Color(1, 0.85, 0.2))
	Sound.announce("ko_voice")


func _ko_phase() -> void:
	if pt < 100:
		return
	for f in fighters:
		if f.state in ["airhit", "hitstun", "attack", "thrown", "throwing"] or not f.grounded():
			return
	phase = "roundwin"
	pt = 0
	if winner >= 0:
		var w: Node2D = fighters[winner]
		var l: Node2D = fighters[1 - winner]
		w.wins += 1
		w.set_state("win")
		w.controlled = false
		if l.state != "ko":
			l.set_state("lose")
		var flawless: bool = w.health >= w.max_health
		var quote: String = w.def.get("name", "").to_upper() + " WINS"
		hud.announce(quote, "FLAWLESS VICTORY" if flawless else "", 140, Color(1, 0.85, 0.2))
		Sound.announce("win")
	else:
		hud.announce("DRAW", "", 140, Color(0.9, 0.9, 1))


func _after_round() -> void:
	var done := false
	for i in 2:
		if fighters[i].wins >= rounds_to_win:
			match_winner = i
			done = true
	if round_num >= 7 and not done:
		match_winner = 0 if fighters[0].health >= fighters[1].health else 1
		done = true
	if done:
		_match_end()
	else:
		round_num += 1
		start_round()


func _match_end() -> void:
	phase = "result"
	pt = 0
	var w: Node2D = fighters[match_winner]
	w.set_state("win")
	Sound.play_music("victory")
	if autoplay:
		return
	_show_results()


# --- Collision & hits -------------------------------------------------------------------------

func bounds() -> Vector2:
	var left := maxf(EDGE, cam_x - HALF_VIEW + EDGE)
	var right := minf(STAGE_W - EDGE, cam_x + HALF_VIEW - EDGE)
	return Vector2(left, right)


func clamp_fighter(f: Node2D) -> void:
	var b := bounds()
	f.pos.x = clampf(f.pos.x, b.x, b.y)
	f.pos.y = minf(f.pos.y, FLOOR_Y)


func at_wall(f: Node2D) -> bool:
	var b := bounds()
	return f.pos.x <= b.x + 2.0 or f.pos.x >= b.y - 2.0


func _push_apart() -> void:
	var a: Node2D = fighters[0]
	var b: Node2D = fighters[1]
	if a.phase_through or b.phase_through:
		return
	for f in fighters:
		if f.state in ["thrown", "throwing", "knockdown", "getup", "ko"]:
			return
	var ra: Rect2 = a.pushbox()
	var rb: Rect2 = b.pushbox()
	if not ra.intersects(rb):
		return
	var overlap := minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x)
	var dir := -1.0 if a.pos.x < b.pos.x else 1.0
	if absf(a.pos.x - b.pos.x) < 0.5:
		dir = -float(a.facing)
	var bd := bounds()
	var a_wall: bool = (dir < 0 and a.pos.x <= bd.x + 1.0) or (dir > 0 and a.pos.x >= bd.y - 1.0)
	var b_wall: bool = (dir < 0 and b.pos.x >= bd.y - 1.0) or (dir > 0 and b.pos.x <= bd.x + 1.0)
	if a_wall:
		b.pos.x -= dir * overlap
	elif b_wall:
		a.pos.x += dir * overlap
	else:
		a.pos.x += dir * overlap * 0.5
		b.pos.x -= dir * overlap * 0.5


func _resolve_hits() -> void:
	var hits: Array = []
	for i in 2:
		var a: Node2D = fighters[i]
		var d: Node2D = fighters[1 - i]
		var hb: Rect2 = a.active_hitbox()
		if hb.size == Vector2.ZERO:
			continue
		for hr in d.hurtboxes():
			var r: Rect2 = hr
			if hb.intersects(r):
				hits.append([a, d, hb.intersection(r).get_center()])
				break
	for h in hits:
		var a: Node2D = h[0]
		var d: Node2D = h[1]
		var atk: Dictionary = a.current_attack()
		var res: String = d.receive_hit(atk, a, false)
		a.register_hit(res)
		_feedback(a, d, res, atk, h[2], false)


func _feedback(a: Node2D, d: Node2D, res: String, atk: Dictionary, at: Vector2, is_proj: bool) -> void:
	var dmg := float(atk.get("damage", 0))
	if res == "hit":
		hit_count[a.pid] += 1
	match res:
		"hit":
			var power: Color = a.look.get("power", Color.WHITE)
			if atk.get("fx_hit", "") == "slash":
				fx.slash(at, a.facing, clampf(dmg / 50.0, 0.8, 1.8), power)
			fx.spark(at, clampf(dmg / 55.0, 0.6, 1.8), power.lerp(Color.WHITE, 0.4))
			if atk.get("amp", false):
				fx.shockring(at, power, 6.0, 3.0, 14)
			var bonus: String = d.last_hit_bonus
			if bonus == "counter":
				fx.text(d.pos + Vector2(0, -d.H * 1.15), "COUNTER HIT", Color(1, 0.5, 0.3))
			elif bonus == "punish":
				fx.text(d.pos + Vector2(0, -d.H * 1.15), "PUNISH", Color(1, 0.8, 0.3))
			d.last_hit_bonus = ""
			if not first_strike and not training:
				first_strike = true
				hud.announce("FIRST STRIKE", "", 45, Color(1, 0.6, 0.2))
			_rumble(d.pid, 0.25 + minf(0.5, dmg / 200.0), 0.12 + dmg / 1200.0)
			_rumble(a.pid, 0.15, 0.06)
			zoom_punch = maxf(zoom_punch, clampf(dmg / 2500.0, 0.0, 0.045))
			var snd := "hit_l" if dmg < 45 else ("hit_m" if dmg < 80 else "hit_h")
			var sfx: String = atk.get("sfx", snd)
			Sound.play(sfx if sfx.begins_with("hit") else snd)
			var hs := clampi(int(5 + dmg / 12.0), 5, 13)
			if atk.get("super", false):
				hs = 6
			d.hitstop = hs
			if not is_proj:
				a.hitstop = hs
			if dmg >= 85:
				shake(2.0 + dmg / 40.0)
			hud.show_combo(a.pid, d.combo_hits, d.combo_damage)
			if not is_proj and at_wall(d):
				a.pos.x -= float(sign(d.pos.x - a.pos.x)) * float(atk.get("push", 5)) * 0.8
		"block":
			fx.block_spark(at)
			Sound.play("block")
			_rumble(d.pid, 0.15, 0.05)
			d.hitstop = 5
			if not is_proj:
				a.hitstop = 5
				if at_wall(d):
					a.pos.x -= float(sign(d.pos.x - a.pos.x)) * float(atk.get("push", 5))
		"armor":
			fx.spark(at, 0.8, Color(0.8, 0.9, 1.0))
			fx.text(d.pos + Vector2(0, -d.H * 1.1), "ARMOR", Color(0.8, 0.9, 1.0))
			Sound.play("block", 0.6)
			d.hitstop = 7
			if not is_proj:
				a.hitstop = 7
		"countered":
			Sound.play("block", 1.4)
			if not is_proj:
				a.hitstop = 8


func _resolve_throws() -> void:
	var attempts := [false, false]
	for i in 2:
		var a: Node2D = fighters[i]
		attempts[i] = a.state == "attack" and a.move.get("throw", false) and a.is_active()
	if attempts[0] and attempts[1]:
		throw_break(fighters[0], fighters[1])
		return
	for i in 2:
		if not attempts[i]:
			continue
		var a: Node2D = fighters[i]
		var d: Node2D = fighters[1 - i]
		var dist: float = absf(d.pos.x - a.pos.x)
		var in_front: bool = sign(d.pos.x - a.pos.x) == a.facing or dist < 4.0
		if in_front and dist <= float(a.move.get("range", 0.5)) * a.H + 0.1 * d.H and d.throwable():
			a.begin_throw(d)
			Sound.play("throw", 1.2)
			return


func throw_break(a: Node2D, d: Node2D) -> void:
	for f in [a, d]:
		if f == null:
			continue
		f.throw_victim = null
		f.thrower = null
		f.to_neutral()
		f.slide = 0.0
	if a != null and d != null:
		var dir := -1.0 if a.pos.x < d.pos.x else 1.0
		a.pos.x += dir * 24.0
		d.pos.x -= dir * 24.0
		fx.text((a.pos + d.pos) * 0.5 + Vector2(0, -150), "THROW BREAK", Color(0.6, 0.9, 1.0))
		fx.block_spark((a.pos + d.pos) * 0.5 + Vector2(0, -90))
	Sound.play("block")


# --- Projectiles --------------------------------------------------------------------------------

func has_projectile(src: Node2D, kind: String) -> bool:
	for p in projectiles:
		if p.alive and p.owner_fighter == src and p.kind == kind:
			return true
	return false


func incoming_projectile(target: Node2D, within: float):
	for p in projectiles:
		if not p.alive or p.owner_fighter == target or p.delay > 0:
			continue
		var dx: float = target.pos.x - p.pos.x
		if absf(dx) < within and (sign(dx) == sign(p.vel.x) or absf(p.vel.x) < 0.5):
			return p
	return null


func spawn_projectile(src: Node2D, d: Dictionary, index: int = 0) -> void:
	var owner_f := src
	var off: Array = d.get("offset", [0.4, -0.8])
	var power: Color = owner_f.look.get("power", Color.WHITE)
	if d.has("rain"):
		var r: Dictionary = d["rain"]
		var spread: Array = r.get("spread", [0])
		var xs: Array = []
		if int(d.get("count", 1)) <= 1:
			xs = spread
		else:
			xs = [spread[index % spread.size()]]
		for sx in xs:
			var p := Projectile.new()
			var tx: float = owner_f.opponent.pos.x + float(sx)
			p.setup(owner_f, d, Vector2(tx, float(r.get("height", -30))), owner_f.facing, power)
			p.vel = Vector2(0, float(d.get("vy", 9)))
			p.delay = int(r.get("delay", 12))
			world.add_child(p)
			projectiles.append(p)
		return
	var start := Vector2(owner_f.pos.x + float(off[0]) * owner_f.H * owner_f.facing, owner_f.pos.y + float(off[1]) * owner_f.H)
	if owner_f.amplified:
		d = d.duplicate()
		d["damage"] = float(d.get("damage", 0)) * 1.35
		d["speed"] = float(d.get("speed", 8)) * 1.25
		d["hits"] = int(d.get("hits", 1)) + 1
		d["amp"] = true
	var pr := Projectile.new()
	pr.setup(owner_f, d, start, owner_f.facing, power)
	if owner_f.amplified:
		pr.size *= 1.2
	world.add_child(pr)
	projectiles.append(pr)
	if pr.kind == "bullet":
		Sound.play("shot")
		fx.spark(start, 0.4, Color(1, 0.9, 0.5))


func _step_projectiles() -> void:
	for p in projectiles:
		p.step()
	# Clashes between opposing projectiles.
	for i in projectiles.size():
		for j in range(i + 1, projectiles.size()):
			var a = projectiles[i]
			var b = projectiles[j]
			if a.owner_fighter != b.owner_fighter and a.can_hit() and b.can_hit() and a.rect().intersects(b.rect()):
				a.on_hit()
				b.on_hit()
				fx.spark((a.pos + b.pos) * 0.5, 0.9, Color(1, 1, 1))
				Sound.play("block", 0.8)
	for p in projectiles:
		if not p.can_hit():
			continue
		var tgt: Node2D = p.owner_fighter.opponent
		for hr in tgt.hurtboxes():
			if p.rect().intersects(hr):
				var atk: Dictionary = p.attack()
				var res: String = tgt.receive_hit(atk, p.owner_fighter, true)
				if res == "whiff":
					break
				p.on_hit()
				_feedback(p.owner_fighter, tgt, res, atk, p.pos, true)
				if res == "hit":
					p.owner_fighter.meter = minf(1000.0, p.owner_fighter.meter + float(atk.get("damage", 0)) * 0.6)
				if p.explodes():
					p.alive = false
					p.detonated = true
					fx.explosion(p.pos, float(p.data["explode"]), Color(1, 0.6, 0.2))
					Sound.play("explode", 1.2, -4.0)
				break
	for p in projectiles:
		if not p.alive and p.explodes() and not p.detonated:
			p.detonated = true
			_detonate(p)
	var keep: Array = []
	for p in projectiles:
		if p.alive:
			keep.append(p)
		else:
			p.queue_free()
	projectiles = keep


func _detonate(p) -> void:
	var r := float(p.data["explode"])
	fx.explosion(p.pos, r, Color(1, 1, 0.9) if p.kind == "flashbang" else Color(1, 0.6, 0.2))
	Sound.play("explode", 1.3, -3.0)
	if p.kind == "flashbang":
		hud.flash_t = 6
	var area := Rect2(p.pos - Vector2(r, r), Vector2(r, r) * 2.0)
	var tgt: Node2D = p.owner_fighter.opponent
	for hr in tgt.hurtboxes():
		if area.intersects(hr):
			var atk: Dictionary = p.attack()
			var res: String = tgt.receive_hit(atk, p.owner_fighter, true)
			_feedback(p.owner_fighter, tgt, res, atk, p.pos, true)
			break


# --- FX hooks used by fighters ------------------------------------------------------------------

func on_super(f: Node2D, m: Dictionary) -> void:
	cinematic = 32
	var power: Color = f.look.get("power", Color.WHITE)
	hud.banner(str(m.get("name", "SUPER")).to_upper(), f.pid, power)
	hud.flash_t = 4
	Sound.play("super")
	Sound.announce("super_voice")
	fx.shockring(f.pos + Vector2(0, -f.H * 0.5), power, 10.0, 4.0, 24)
	zoom_punch = 0.08
	_rumble(f.pid, 0.4, 0.3)


func on_amplify(f: Node2D) -> void:
	var power: Color = f.look.get("power", Color.WHITE)
	fx.text(f.pos + Vector2(0, -f.H * 1.15), "AMPLIFIED", power.lightened(0.3))
	fx.shockring(f.pos + Vector2(0, -f.H * 0.5), power, 8.0, 3.0, 16)
	Sound.play("super", 1.6, -6.0)
	_rumble(f.pid, 0.3, 0.12)


func on_breaker(f: Node2D) -> void:
	var o: Node2D = f.opponent
	var power: Color = f.look.get("power", Color.WHITE)
	f.to_neutral()
	f.vel = Vector2.ZERO
	f.pos.y = FLOOR_Y
	f.invuln = 24
	f.stun = 0
	f.slide = 0.0
	if o.state != "ko":
		var away := 1.0 if o.pos.x > f.pos.x else -1.0
		o.move = {}
		o.move_id = ""
		o.vel = Vector2(7.0 * away, -7.0)
		o.pos.y = minf(o.pos.y, FLOOR_Y - 1.0)
		o.set_state("airhit")
		o.juggle_immune = true
	fx.text(f.pos + Vector2(0, -f.H * 1.2), "BREAKER!", Color(1, 1, 1))
	fx.shockring(f.pos + Vector2(0, -f.H * 0.5), power, 12.0, 6.0, 22)
	hud.flash_t = 6
	Sound.play("explode", 1.4, -4.0)
	shake(6.0)
	_rumble(f.pid, 0.6, 0.25)


func fx_wallbounce(f: Node2D) -> void:
	fx.dust(f.pos + Vector2(0, -f.H * 0.5), 1.4)
	fx.shockring(f.pos + Vector2(0, -f.H * 0.5), Color(1, 1, 1), 6.0, 3.0, 12)
	fx.text(f.pos + Vector2(0, -f.H * 1.1), "WALL BOUNCE", Color(1, 0.85, 0.4))
	Sound.play("slam", 1.3, -4.0)
	shake(5.0)


func _rumble(pid: int, strength: float, duration: float) -> void:
	if autoplay or ai[pid] != null:
		return
	InputManager.rumble(pid, strength, duration)


func fx_dust(at: Vector2, scale: float) -> void:
	fx.dust(at, scale)


func fx_text(at: Vector2, s: String, col: Color) -> void:
	fx.text(at, s, col)


func fx_spark(at: Vector2, scale: float, col: Color) -> void:
	fx.spark(at, scale, col)


func fx_teleport(at: Vector2, col: Color) -> void:
	fx.breach(at, col)
	Sound.play("teleport", 1.1, -4.0)


func fx_move(f: Node2D, kind: String) -> void:
	var power: Color = f.look.get("power", Color.WHITE)
	var m: Dictionary = f.move
	var head: Vector2 = f.pos + Vector2(0.25 * f.H * f.facing, -0.85 * f.H)
	match kind:
		"breath":
			for i in 8:
				fx.add({"t": "line", "p": head + Vector2(0, randf_range(-20, 40)), "v": Vector2(9.0 * f.facing, randf_range(-0.5, 1.0)), "life": 20, "c": Color(0.8, 0.95, 1.0, 0.8), "w": 2.0})
		"flare":
			fx.explosion(f.pos + Vector2(0, -f.H * 0.6), 160.0, Color(1, 0.9, 0.4))
			hud.flash_t = 10
			shake(8.0)
		"sonic_beam":
			var to: Vector2 = head + Vector2(600.0 * f.facing, 10)
			fx.beam(head, to, power, 14.0, int(m.get("active", 40)))
			for i in 6:
				fx.shockring(head + Vector2(i * 70.0 * f.facing, 10), power, 8.0, 2.0, 30 + i * 2)
		"breach":
			fx.breach(f.pos + Vector2(0, -f.H * 0.5), power)
		"heal":
			for i in 10:
				fx.add({"t": "puff", "p": f.pos + Vector2(randf_range(-30, 30), randf_range(-f.H, -10)), "v": Vector2(0, -1.2), "life": 30, "c": Color(power.r, power.g, power.b, 0.6), "r": 3.0})


func shake(amount: float) -> void:
	if Game.settings.get("shake", true):
		shake_amt = maxf(shake_amt, amount)


func _update_camera() -> void:
	var mid: float = (fighters[0].pos.x + fighters[1].pos.x) * 0.5
	cam_x = lerpf(cam_x, clampf(mid, HALF_VIEW, STAGE_W - HALF_VIEW), 0.25)
	var off := Vector2.ZERO
	if shake_amt > 0.1:
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
		shake_amt *= 0.85
	else:
		shake_amt = 0.0
	cam.position = Vector2(round(cam_x), 180) + off.round()
	zoom_punch *= 0.86
	var z := 1.0 + zoom_punch
	cam.zoom = Vector2(z, z)
	arena.cam_left = round(cam_x) - HALF_VIEW


# --- Training ------------------------------------------------------------------------------------

func _training_tick() -> void:
	var opts: Dictionary = Game.training
	for f in fighters:
		f.show_boxes = opts.get("boxes", false)
		if opts.get("meter", "infinite") == "infinite":
			f.meter = 1000.0
		var i: int = f.pid
		if f.state in ["hitstun", "airhit", "knockdown", "getup", "blockstun", "thrown"]:
			regen_wait[i] = 0
		else:
			regen_wait[i] += 1
			if opts.get("regen", true) and regen_wait[i] > 50:
				f.health = move_toward(f.health, f.max_health, 25.0)
		f.health = maxf(1.0, f.health)
	if ai[1] != null:
		ai[1].mode = opts.get("dummy", "stand")
	if Input.is_physical_key_pressed(KEY_R) or Input.is_joy_button_pressed(InputManager.pad_device[0], JOY_BUTTON_BACK):
		_reset_positions()
	var p1: Node2D = fighters[0]
	var info := "DUMMY: %s   (Pause for options, R to reset)" % str(opts.get("dummy", "stand")).to_upper()
	var mid: String = last_move[0]
	if mid != "" and p1.def["moves"].has(mid):
		var m: Dictionary = p1.def["moves"][mid]
		info += "\nLAST: %s  startup %d / active %d / recovery %d  dmg %d" % [m.get("name", mid), int(m.get("startup", 0)), int(m.get("active", 0)), int(m.get("recovery", 0)), int(m.get("damage", 0))]
	var d: Node2D = fighters[1]
	if d.combo_hits > 0:
		info += "\nCOMBO: %d hits, %d damage" % [d.combo_hits, int(d.combo_damage)]
	hud.training_info = info


# --- Pause & results menus -----------------------------------------------------------------------

func _make_menu(title: String, items: Array, width: float = 220.0) -> Control:
	_close_menu()
	var m: Control = MenuList.new()
	m.title = title
	m.width = width
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	m.set_items(items)
	m.position = Vector2((640 - width) * 0.5, 100)
	ui.add_child(m)
	menu = m
	return m


func _close_menu() -> void:
	if menu != null:
		menu.queue_free()
		menu = null


func _on_pad_lost(device: int) -> void:
	if autoplay or phase not in ["fight", "intro"] or get_tree().paused:
		return
	var pid := InputManager.player_for_device(device)
	if pid >= 0 and ai[pid] == null:
		open_pause()


func open_pause() -> void:
	get_tree().paused = true
	Sound.play("menu_ok")
	var items := [{"id": "resume", "label": "Resume"}, {"id": "moves", "label": "Move List"}]
	if training:
		items += [
			{"id": "dummy", "label": "Dummy", "value": str(Game.training.get("dummy", "stand")).to_upper()},
			{"id": "meter", "label": "Super Meter", "value": str(Game.training.get("meter", "infinite")).to_upper()},
			{"id": "boxes", "label": "Hitboxes", "value": "ON" if Game.training.get("boxes", false) else "OFF"},
			{"id": "regen", "label": "Health Regen", "value": "ON" if Game.training.get("regen", true) else "OFF"},
			{"id": "reset", "label": "Reset Position"},
		]
	else:
		items.append({"id": "restart", "label": "Restart Match"})
	items += [{"id": "select", "label": "Character Select"}, {"id": "menu", "label": "Main Menu"}]
	var m := _make_menu("PAUSED", items, 240.0)
	m.position.y = 70
	m.chosen.connect(_on_pause_choice)
	m.adjusted.connect(func(id, _dir): _on_pause_choice(id))
	m.cancelled.connect(_resume)


func _resume() -> void:
	_close_menu()
	get_tree().paused = false
	pause_lock = 10


func _on_pause_choice(id: String) -> void:
	match id:
		"resume":
			_resume()
		"moves":
			_show_move_list()
		"dummy":
			var modes := ["stand", "crouch", "jump", "block", "cpu"]
			var cur := modes.find(Game.training.get("dummy", "stand"))
			Game.training["dummy"] = modes[(cur + 1) % modes.size()]
			open_pause()
			menu.index = 2
		"meter":
			Game.training["meter"] = "normal" if Game.training.get("meter", "infinite") == "infinite" else "infinite"
			open_pause()
			menu.index = 3
		"boxes":
			Game.training["boxes"] = not Game.training.get("boxes", false)
			open_pause()
			menu.index = 4
		"regen":
			Game.training["regen"] = not Game.training.get("regen", true)
			open_pause()
			menu.index = 5
		"reset":
			_reset_positions()
			_resume()
		"restart":
			Game.begin_fight()
		"select":
			Game.goto("select" if Game.mode in ["versus", "versus_cpu", "training"] else "menu")
		"menu":
			Game.goto("menu")


func _show_move_list() -> void:
	var f: Node2D = fighters[0]
	var items: Array = []
	var order := ["S", "fS", "bS", "dS", "jS", "throw", "L", "M", "H", "cL", "cM", "cH", "jL", "jM", "jH"]
	var labels := {"L": "LIGHT", "M": "MEDIUM", "H": "HEAVY", "cL": "DOWN + LIGHT", "cM": "DOWN + MEDIUM", "cH": "DOWN + HEAVY",
		"jL": "AIR LIGHT", "jM": "AIR MEDIUM", "jH": "AIR HEAVY", "throw": "MEDIUM + HEAVY", "S": "SP", "fS": "FWD + SP", "bS": "BACK + SP", "dS": "DOWN + SP", "jS": "SP (AIR)"}
	for k in order:
		if not f.def["moves"].has(k):
			continue
		var m: Dictionary = f.def["moves"][k]
		items.append({"id": "back", "label": str(m.get("name", k)), "value": str(m.get("input", labels.get(k, k))).to_upper()})
	items.append({"id": "back", "label": "-- SYSTEM --", "value": ""})
	items.append({"id": "back", "label": "Amplify (1 bar)", "value": "BLOCK during a special"})
	items.append({"id": "back", "label": "Breaker (2 bars)", "value": "FWD + BLOCK while hit"})
	items.append({"id": "back", "label": "Quick Rise / Roll", "value": "ANY BUTTON (+BACK) when down"})
	var ml := _make_menu(str(f.def.get("name", "")).to_upper() + " - MOVE LIST", items, 380.0)
	ml.font_size = 9
	ml.item_h = 13.0
	ml.set_items(items)
	ml.position = Vector2(130, 22)
	ml.chosen.connect(func(_id): open_pause())
	ml.cancelled.connect(open_pause)


func _show_results() -> void:
	var w: Node2D = fighters[match_winner]
	var p1_won := match_winner == 0
	var quotes: Array = w.def.get("quotes", [""])
	var quote: String = quotes[randi() % quotes.size()] if quotes.size() > 0 else ""
	var items: Array = []
	match Game.mode:
		"arcade":
			if p1_won:
				items = [{"id": "arcade_next", "label": "Continue"}]
			else:
				items = [{"id": "arcade_retry", "label": "Continue? (Retry)"}, {"id": "menu", "label": "Give Up"}]
		"survival":
			if p1_won:
				items = [{"id": "survival_next", "label": "Next Opponent"}, {"id": "menu", "label": "Quit"}]
			else:
				items = [{"id": "survival_retry", "label": "Try Again"}, {"id": "menu", "label": "Main Menu"}]
		"story":
			if p1_won:
				items = [{"id": "story_next", "label": "Continue Story"}]
			else:
				items = [{"id": "story_retry", "label": "Retry Chapter"}, {"id": "menu", "label": "Quit Story"}]
		_:
			items = [{"id": "rematch", "label": "Rematch"}, {"id": "select", "label": "Character Select"}, {"id": "stage", "label": "Stage Select"}, {"id": "menu", "label": "Main Menu"}]
	result_panel = Control.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_panel.draw.connect(func():
		var font: Font = Game.font
		result_panel.draw_rect(Rect2(0, 52, 640, 44), Color(0, 0, 0, 0.7))
		var title: String = "%s WINS" % str(w.def.get("name", "")).to_upper()
		if Game.mode == "survival" and not p1_won:
			title = "SURVIVAL OVER - %d WINS" % int(Game.survival.get("wins", 0))
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		result_panel.draw_string_outline(font, Vector2(320 - tw * 0.5, 74), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color.BLACK)
		result_panel.draw_string(font, Vector2(320 - tw * 0.5, 74), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.2))
		var q := "\"%s\"" % quote
		var qw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		result_panel.draw_string(font, Vector2(320 - qw * 0.5, 90), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1)))
	ui.add_child(result_panel)
	var m := _make_menu("", items, 200.0)
	m.position = Vector2(220, 230)
	m.chosen.connect(_on_result_choice)


func _on_result_choice(id: String) -> void:
	match id:
		"rematch":
			Game.begin_fight()
		"select":
			Game.goto("select")
		"stage":
			Game.goto("stage")
		"menu":
			Game.goto("menu")
		"arcade_next":
			Game.arcade_won()
		"arcade_retry":
			Game.arcade_retry()
		"survival_next":
			Game.survival_won(fighters[0].health / fighters[0].max_health)
		"survival_retry":
			Game.start_survival(Game.survival["char"])
		"story_next":
			Game.story_won()
		"story_retry":
			Game.story_fight()
