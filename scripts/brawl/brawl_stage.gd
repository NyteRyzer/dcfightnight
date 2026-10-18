extends Node2D
## Beat 'em up mode: a side-scrolling brawler for 1-2 players.
##
## Players walk left/right and up/down in depth lanes, fight waves of NPC
## enemies across several areas per level, grab pickups, and face a boss at the
## end of each level. Fighters and projectiles reuse the versus combat code;
## depth is a per-fighter floor line plus a lane check on every hit.

const FighterScene = preload("res://scenes/fight/Fighter.tscn")
const Projectile = preload("res://scripts/combat/projectile.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Arena = preload("res://scripts/arenas/arena.gd")
const BrawlAI = preload("res://scripts/brawl/brawl_ai.gd")
const BrawlHUD = preload("res://scripts/brawl/brawl_hud.gd")
const MenuList = preload("res://scripts/ui/menu_list.gd")

const STAGE_W := 1000.0
const HALF_VIEW := 320.0
const EDGE := 18.0
const FEET_TOP := 290.0      # floor line of the back depth lane
const DEPTH_MAX := 54.0
const DEPTH_SPEED := 1.9
const LANE_HIT := 16.0       # max depth difference for a hit to connect
const MAX_TOKENS := 2        # enemies allowed to attack one player at once

var autoplay := false
var players: Array = []
var enemies: Array = []
var projectiles: Array = []
var pickups: Array = []
var player_ai: Array = [null, null]
var ai_of := {}
var tokens := {}
var arena: Node2D
var world: Node2D
var fx: Node2D
var pickup_layer: Node2D
var cam: Camera2D
var ui: CanvasLayer
var hud: Control
var menu: Control = null

var levels: Array = []
var level_i := 0
var area_i := 0
var wave_i := 0
var phase := "title"
var pt := 0
var total_frames := 0
var cam_x := HALF_VIEW
var cinematic := 0
var shake_amt := 0.0
var zoom_punch := 0.0
var score := [0, 0]
var lives := [3, 3]
var respawn_t := [0, 0]
var combo := [0, 0]
var combo_t := [0, 0]
var spawn_queue: Array = []
var boss: Node2D = null
var focus_enemy: Node2D = null
var focus_t := 0
var message := ""
var message_sub := ""
var message_t := 0
var miniboss_done := false
var fade := 0.0
var pause_lock := 0
var kills := 0
var level_kills := 0
var continues := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	levels = Data.brawl.get("levels", [])
	level_i = clampi(int(Game.brawl.get("level", 0)), 0, levels.size() - 1)
	continues = int(Game.brawl.get("continues", 0))
	world = Node2D.new()
	add_child(world)
	arena = Arena.new()
	arena.z_index = -100
	arena.position.y = -40.0
	arena.floor_extend = 80.0
	world.add_child(arena)
	pickup_layer = Node2D.new()
	pickup_layer.z_index = -5
	pickup_layer.draw.connect(_draw_pickups)
	world.add_child(pickup_layer)
	fx = Effects.new()
	fx.z_index = 200
	fx.reduce_flash = Game.settings.get("reduce_flash", false)
	world.add_child(fx)
	cam = Camera2D.new()
	cam.position = Vector2(cam_x, 180)
	add_child(cam)
	cam.make_current()
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var ids: Array = Game.brawl.get("players", ["flash"])
	var costumes: Array = Game.brawl.get("costumes", [0, 0])
	for i in ids.size():
		var f := _make_fighter(Data.fighter(ids[i]), costumes[i] if i < costumes.size() else 0, 0)
		f.pid = i
		f.max_health *= 1.5
		f.health = f.max_health
		f.free_facing = true
		f.pos = Vector2(120.0 + i * 40.0, 0)
		f.depth = 18.0 + i * 24.0
		f.facing = 1
		players.append(f)
	hud = BrawlHUD.new()
	hud.stage = self
	ui.add_child(hud)
	InputManager.pad_disconnected.connect(_on_pad_lost)
	_start_level()


func enable_autoplay() -> void:
	autoplay = true
	for i in players.size():
		var a := BrawlAI.new()
		a.setup(players[i], self, "player", 3)
		player_ai[i] = a


func _make_fighter(def: Dictionary, costume: int, team: int) -> Node2D:
	var f: Node2D = FighterScene.instantiate()
	f.setup(def, team, costume)
	f.manager = self
	f.team = team
	var rc := Color.html(str(Data.stage(arena.stage_id).get("rim", "#c8d8ff")))
	rc.a = 0.6
	f.rim = rc
	world.add_child(f)
	return f


# --- Level / area flow ------------------------------------------------------------------

func _level() -> Dictionary:
	return levels[level_i]


func _start_level() -> void:
	area_i = 0
	level_kills = 0
	boss = null
	for p in players:
		p.health = minf(p.max_health, p.health + p.max_health * 0.5) if total_frames > 0 else p.max_health
	_start_area()
	phase = "title"
	pt = 0
	var lv := _level()
	_say(str(lv.get("name", "")).to_upper(), str(lv.get("subtitle", "")), 150)
	Sound.play_music("survival")


func _area() -> Dictionary:
	return _level()["areas"][area_i]


func _start_area() -> void:
	arena.stage_id = _area().get("stage", "star_city")
	_apply_rim()
	wave_i = 0
	miniboss_done = not _area().has("miniboss")
	cam_x = HALF_VIEW
	for i in players.size():
		var p: Node2D = players[i]
		p.pos.x = 90.0 + i * 50.0
		p.facing = 1
		p.vel = Vector2.ZERO
		if p.health > 0.0:
			p.to_neutral()
		_set_floor(p)
		p.pos.y = p.floor_y
	_clear_projectiles()
	pickups.clear()
	spawn_queue.clear()
	_queue_wave()


func _apply_rim() -> void:
	var rc := Color.html(str(Data.stage(arena.stage_id).get("rim", "#c8d8ff")))
	rc.a = 0.6
	for f in players + enemies:
		f.rim = rc


func _queue_wave() -> void:
	var waves: Array = _area().get("waves", [])
	if wave_i >= waves.size():
		return
	var delay := 40
	for entry in waves[wave_i]:
		for n in int(entry[1]):
			spawn_queue.append({"type": entry[0], "delay": delay})
			delay += 35


func _spawn_enemy(type_id: String) -> void:
	var def: Dictionary = Data.npcs.get(type_id, {})
	if def.is_empty():
		return
	var e := _make_fighter(def, 0, 1)
	var variants: Array = def.get("variants", [])
	if variants.size() > 0:
		e.look = variants[randi() % variants.size()]
	var hscale := randf_range(0.95, 1.06)
	e.H = float(e.look.get("height", def.get("height", 170))) * hscale
	var coop := 1.3 if players.size() > 1 else 1.0
	e.max_health = float(def.get("health", 200)) * coop
	e.health = e.max_health
	e.lod = true
	e.rim_enabled = false
	# Grunts hit softer than versus fighters; difficulty 0-4 scales 0.5x-0.82x.
	e.dmg_mult = 0.5 + 0.08 * int(Game.settings.get("difficulty", 2))
	var side := -1.0 if randf() < 0.3 else 1.0
	e.pos = Vector2(cam_x + side * (HALF_VIEW + 40.0), 0)
	e.depth = randf_range(0.0, DEPTH_MAX)
	_set_floor(e)
	e.pos.y = e.floor_y
	e.facing = -int(side)
	var ai := BrawlAI.new()
	ai.setup(e, self, str(def.get("ai", "brawler")), int(Game.settings.get("difficulty", 2)))
	ai_of[e] = ai
	e.set_meta("npc", type_id)
	e.set_meta("score", int(def.get("score", 100)))
	enemies.append(e)


func _spawn_boss(fighter_id: String, health: float, line: String) -> Node2D:
	var def := Data.fighter(fighter_id)
	var b := _make_fighter(def, 0, 1)
	var coop := 1.3 if players.size() > 1 else 1.0
	b.max_health = health * coop
	b.health = b.max_health
	b.dmg_mult = 0.75
	b.pos = Vector2(cam_x + HALF_VIEW - 90.0, 0)
	b.depth = DEPTH_MAX * 0.5
	_set_floor(b)
	b.pos.y = b.floor_y
	b.facing = -1
	var ai := BrawlAI.new()
	ai.setup(b, self, "boss", mini(4, int(Game.settings.get("difficulty", 2)) + 1))
	ai_of[b] = ai
	b.set_meta("score", 5000)
	b.set_meta("boss", true)
	enemies.append(b)
	if line != "":
		_say(str(def.get("name", "")).to_upper(), "\"%s\"" % line, 150)
	return b


func _set_floor(f: Node2D) -> void:
	f.depth = clampf(f.depth, 0.0, DEPTH_MAX)
	var was_grounded: bool = f.pos.y >= f.floor_y - 0.5
	f.floor_y = FEET_TOP + f.depth
	if was_grounded:
		f.pos.y = f.floor_y
	f.z_index = 10 + int(f.depth)


func _say(text: String, sub: String = "", frames: int = 90) -> void:
	message = text
	message_sub = sub
	message_t = frames


func _clear_projectiles() -> void:
	for p in projectiles:
		p.queue_free()
	projectiles.clear()


# --- Main loop -----------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	pt += 1
	total_frames += 1
	if message_t > 0:
		message_t -= 1
	if focus_t > 0:
		focus_t -= 1
	for i in 2:
		if combo_t[i] > 0:
			combo_t[i] -= 1
			if combo_t[i] == 0:
				combo[i] = 0
	match phase:
		"title":
			_sim(false)
			if pt > 120 or (pt > 30 and InputManager.menu("accept")):
				phase = "play"
				pt = 0
		"play", "go", "boss":
			_sim(true)
			_flow()
			if pause_lock > 0:
				pause_lock -= 1
			elif Input.is_action_just_pressed("pause") and not autoplay:
				open_pause()
		"transition":
			fade = minf(1.0, fade + 0.06)
			if fade >= 1.0:
				_next_area()
		"boss_intro":
			_sim(false)
			if pt > 110:
				boss.to_neutral()
				phase = "boss"
				pt = 0
				_say("FIGHT!", "", 40)
				Sound.announce("fight")
		"level_clear":
			_sim(false)
			if pt == 1:
				_say("LEVEL CLEAR!", "Score: %d" % (score[0] + score[1]), 160)
				Sound.play_music("victory")
				for p in players:
					if p.health > 0.0:
						p.set_state("win")
			if pt > 200 or (autoplay and pt > 60):
				_after_level()
		"gameover":
			_sim(false)
			if pt == 2 and not autoplay:
				_show_gameover()
			elif autoplay and pt > 30:
				phase = "done"
		"victory", "done":
			pass
	if phase != "transition":
		fade = maxf(0.0, fade - 0.06)
	_update_camera()
	pickup_layer.queue_redraw()
	hud.queue_redraw()


func _sim(control: bool) -> void:
	if cinematic > 0:
		cinematic -= 1
		arena.dim = 0.6
		fx.step()
		return
	arena.dim = maxf(0.0, arena.dim - 0.06)
	_spawn_tick()
	tokens.clear()
	# Targets.
	for p in players:
		p.opponent = _nearest(p, enemies)
	for e in enemies:
		e.opponent = _nearest(e, players)
	# Input.
	for i in players.size():
		var p: Node2D = players[i]
		var inp := {}
		var dz := 0.0
		if control and p.health > 0.0:
			if player_ai[i] != null:
				var r: Dictionary = player_ai[i].think()
				inp = r["inp"]
				dz = r["dz"]
			else:
				var raw := InputManager.sample(i)
				inp = _translate(p, raw)
				dz = (-1.0 if raw["u"] else 0.0) + (1.0 if raw["d"] else 0.0)
		_move_depth(p, dz)
		p.controlled = control and p.health > 0.0
		p.set_input(inp)
	for e in enemies:
		var inp2 := {}
		var dz2 := 0.0
		if control and e.health > 0.0 and ai_of.has(e):
			var r2: Dictionary = ai_of[e].think()
			inp2 = r2["inp"]
			dz2 = r2["dz"]
		_move_depth(e, dz2)
		e.controlled = control and e.health > 0.0
		e.set_input(inp2)
	for f in players + enemies:
		f.step()
	_push_apart()
	for f in players + enemies:
		clamp_fighter(f)
	_step_projectiles()
	_resolve_hits()
	_resolve_throws()
	_pickups_tick()
	_deaths()
	var odd := total_frames % 2
	for f in players + enemies:
		f.position = Vector2(f.pos.x, f.pos.y).round()
		f.z_index = 10 + int(f.depth)
		if not f.lod or f.state == "attack" or int(f.get_instance_id()) % 2 == odd:
			f.queue_redraw()
	fx.step()


## Brawler controls: Up/Down walk in depth lanes, Block guards (and still
## Amplifies / Breaks), Throw grabs a nearby enemy or jumps, and Light+Heavy
## together fires the super at 3 bars.
func _translate(p: Node2D, raw: Dictionary) -> Dictionary:
	var inp := {"l": raw["l"], "r": raw["r"], "L": raw["L"], "M": raw["M"], "H": raw["H"], "S": raw["S"], "B": raw["B"]}
	if raw["T"]:
		inp["M"] = false
		inp["H"] = false
		if _grab_target(p) != null:
			inp["M"] = true
			inp["H"] = true
		else:
			inp["u"] = true
	if raw["L"] and raw["H"] and p.meter >= 1000.0 and not raw["T"]:
		inp = {"l": raw["l"], "r": raw["r"], "S": true, "d": true}
	return inp


func _grab_target(p: Node2D) -> Node2D:
	for e in enemies:
		if e.health > 0.0 and absf(e.depth - p.depth) < LANE_HIT and absf(e.pos.x - p.pos.x) < 0.5 * p.H and e.throwable():
			return e
	return null


func _move_depth(f: Node2D, dz: float) -> void:
	var moving := false
	if dz != 0.0 and f.state in ["idle", "walk_f", "walk_b", "crouch"] and f.grounded():
		var before: float = f.depth
		f.depth = clampf(f.depth + dz * DEPTH_SPEED, 0.0, DEPTH_MAX)
		moving = absf(f.depth - before) > 0.01
		_set_floor(f)
	f.depth_walk = moving and f.state == "idle"


func _nearest(f: Node2D, pool: Array) -> Node2D:
	var best: Node2D = f
	var bd := INF
	for o in pool:
		if o.health <= 0.0 or o.state == "ko":
			continue
		var d: float = absf(o.pos.x - f.pos.x) + absf(o.depth - f.depth) * 2.5
		if d < bd:
			bd = d
			best = o
	return best


func request_token(e: Node2D, target: Node2D) -> bool:
	if e.has_meta("boss"):
		return true
	var key := target.get_instance_id()
	var n: int = tokens.get(key, 0)
	if n < MAX_TOKENS:
		tokens[key] = n + 1
		return true
	return false


func _spawn_tick() -> void:
	if spawn_queue.is_empty():
		return
	var entry: Dictionary = spawn_queue[0]
	entry["delay"] -= 1
	if entry["delay"] <= 0 and _alive_enemies() < 5:
		spawn_queue.pop_front()
		_spawn_enemy(entry["type"])


func _alive_enemies() -> int:
	var n := 0
	for e in enemies:
		if e.health > 0.0:
			n += 1
	return n


func _flow() -> void:
	if phase == "play":
		if _alive_enemies() == 0 and spawn_queue.is_empty():
			var waves: Array = _area().get("waves", [])
			if wave_i < waves.size() - 1:
				wave_i += 1
				_queue_wave()
			elif not miniboss_done:
				miniboss_done = true
				var mb: Dictionary = _area()["miniboss"]
				_spawn_boss(mb["fighter"], float(mb.get("health", 1000)), "")
			else:
				phase = "go"
				pt = 0
				_say("GO!", "", 60)
				Sound.play("bell")
	elif phase == "go":
		var lead := -INF
		for p in players:
			if p.health > 0.0:
				lead = maxf(lead, p.pos.x)
		if lead > STAGE_W - 60.0 or (autoplay and pt > 90):
			phase = "transition"
			fade = 0.0
	elif phase == "boss":
		if boss != null and boss.health <= 0.0 and boss.state == "ko" and pt > 30:
			phase = "level_clear"
			pt = 0


func _next_area() -> void:
	focus_enemy = null
	for e in enemies:
		e.queue_free()
	enemies.clear()
	ai_of.clear()
	area_i += 1
	if area_i < _level()["areas"].size():
		_start_area()
		phase = "play"
		pt = 0
		return
	# Boss area.
	var b: Dictionary = _level()["boss"]
	arena.stage_id = b.get("stage", arena.stage_id)
	_apply_rim()
	cam_x = STAGE_W * 0.5
	for i in players.size():
		var p: Node2D = players[i]
		p.pos.x = cam_x - 200.0 + i * 40.0
		p.facing = 1
		_set_floor(p)
		p.pos.y = p.floor_y
	_clear_projectiles()
	pickups.clear()
	boss = _spawn_boss(b["fighter"], float(b.get("health", 1300)), str(b.get("line", "")))
	boss.set_state("intro")
	phase = "boss_intro"
	pt = 0
	Sound.play_music("boss")


func _after_level() -> void:
	focus_enemy = null
	boss = null
	for e in enemies:
		e.queue_free()
	enemies.clear()
	ai_of.clear()
	level_i += 1
	Game.brawl["level"] = level_i
	var best := int(Game.save.get("brawl_best", 0))
	if score[0] + score[1] > best:
		Game.save["brawl_best"] = score[0] + score[1]
		Game.write_save()
	if level_i >= levels.size():
		phase = "victory"
		Game.brawl["level"] = 0
		if autoplay:
			phase = "done"
			return
		var names: Array = []
		for p in players:
			names.append(str(p.def.get("name", "")))
		Game.story_cards = [{"title": "THE STREETS ARE SAFE", "subtitle": "Beat 'em Up Complete",
			"lines": [["", "%s fought through every corner of Control Freak's simulation and shut down the broadcast for good." % " and ".join(names)],
				["", "Final score: %d   Enemies defeated: %d   Continues used: %d" % [score[0] + score[1], kills, continues]]]}]
		Game.story_next = "credits"
		Game.goto("story")
		return
	for p in players:
		if p.health > 0.0:
			p.to_neutral()
	_start_level()


# --- Combat resolution -------------------------------------------------------------------------

func _active(f: Node2D) -> bool:
	return f.health > 0.0 or f.state not in ["ko"]


func _resolve_hits() -> void:
	var all: Array = players + enemies
	for a in all:
		var hb: Rect2 = a.active_hitbox()
		if hb.size == Vector2.ZERO:
			continue
		var res_any := "whiff"
		var atk: Dictionary = a.current_attack()
		for d in all:
			if d.team == a.team or d.state == "ko" or absf(d.depth - a.depth) > LANE_HIT:
				continue
			for hr in d.hurtboxes():
				var r: Rect2 = hr
				if hb.intersects(r):
					var res: String = d.receive_hit(atk, a, false)
					if res != "whiff":
						res_any = res if res_any == "whiff" or res == "hit" else res_any
						_feedback(a, d, res, atk, hb.intersection(r).get_center(), false)
					break
		if res_any != "whiff":
			a.register_hit(res_any)


func _feedback(a: Node2D, d: Node2D, res: String, atk: Dictionary, at: Vector2, is_proj: bool) -> void:
	var dmg := float(atk.get("damage", 0))
	match res:
		"hit":
			var power: Color = a.look.get("power", Color.WHITE)
			if atk.get("fx_hit", "") == "slash":
				fx.slash(at, a.facing, clampf(dmg / 50.0, 0.8, 1.8), power)
			fx.spark(at, clampf(dmg / 55.0, 0.6, 1.8), power.lerp(Color.WHITE, 0.4))
			var snd := "hit_l" if dmg < 45 else ("hit_m" if dmg < 80 else "hit_h")
			Sound.play(snd)
			var hs := clampi(int(4 + dmg / 14.0), 4, 11)
			d.hitstop = hs
			if not is_proj:
				a.hitstop = hs
			if dmg >= 85:
				shake(2.0 + dmg / 45.0)
				zoom_punch = maxf(zoom_punch, 0.025)
			if a.team == 0:
				var i: int = a.pid
				score[i] += int(dmg)
				combo[i] += 1
				combo_t[i] = 70
				focus_enemy = d
				focus_t = 180
				InputManager.rumble(i, 0.2, 0.06)
			else:
				InputManager.rumble(d.pid, 0.3 + minf(0.4, dmg / 200.0), 0.12)
		"block":
			fx.block_spark(at)
			Sound.play("block")
			d.hitstop = 4
			if not is_proj:
				a.hitstop = 4
		"armor":
			fx.spark(at, 0.8, Color(0.8, 0.9, 1.0))
			fx.text(d.pos + Vector2(0, -d.H * 1.1), "ARMOR", Color(0.8, 0.9, 1.0))
			Sound.play("block", 0.6)
		"countered":
			Sound.play("block", 1.4)


func _resolve_throws() -> void:
	for a in players:
		if not (a.state == "attack" and a.move.get("throw", false) and a.is_active()):
			continue
		for d in enemies:
			if d.health <= 0.0 or d.has_meta("boss") and d.state == "attack":
				continue
			var dist: float = absf(d.pos.x - a.pos.x)
			if absf(d.depth - a.depth) < LANE_HIT and dist <= float(a.move.get("range", 0.5)) * a.H + 0.1 * d.H and d.throwable():
				a.begin_throw(d)
				Sound.play("throw", 1.2)
				break


func _push_apart() -> void:
	var all: Array = players + enemies
	for i in all.size():
		for k in range(i + 1, all.size()):
			var a: Node2D = all[i]
			var b: Node2D = all[k]
			if a.phase_through or b.phase_through or absf(a.depth - b.depth) > 14.0:
				continue
			if a.state in ["thrown", "throwing", "knockdown", "getup", "ko"] or b.state in ["thrown", "throwing", "knockdown", "getup", "ko"]:
				continue
			# Crowds of enemies spread out instead of stacking on one spot.
			if a.team == 1 and b.team == 1 and a.grounded() and b.grounded():
				var gap: float = b.pos.x - a.pos.x
				if absf(gap) < 34.0:
					var push := 1.2 if gap >= 0.0 else -1.2
					if gap == 0.0:
						push = 1.2 if a.get_instance_id() < b.get_instance_id() else -1.2
					a.pos.x -= push
					b.pos.x += push
				continue
			var ra: Rect2 = a.pushbox()
			var rb: Rect2 = b.pushbox()
			if not ra.intersects(rb):
				continue
			var overlap := minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x)
			var dir := -1.0 if a.pos.x < b.pos.x else 1.0
			a.pos.x += dir * overlap * 0.5
			b.pos.x -= dir * overlap * 0.5


# --- Projectiles ---------------------------------------------------------------------------------

func has_projectile(src: Node2D, kind: String) -> bool:
	for p in projectiles:
		if p.alive and p.owner_fighter == src and p.kind == kind:
			return true
	return false


func incoming_projectile(target: Node2D, within: float):
	for p in projectiles:
		if not p.alive or p.team == target.team or p.delay > 0 or absf(p.depth - target.depth) > LANE_HIT:
			continue
		var dx: float = target.pos.x - p.pos.x
		if absf(dx) < within and (sign(dx) == sign(p.vel.x) or absf(p.vel.x) < 0.5):
			return p
	return null


func spawn_projectile(src: Node2D, d: Dictionary, index: int = 0) -> void:
	var power: Color = src.look.get("power", Color.WHITE)
	var data := d.duplicate()
	if src.dmg_mult != 1.0:
		data["damage"] = float(d.get("damage", 0)) * src.dmg_mult
	if src.amplified:
		data["damage"] = float(data.get("damage", 0)) * 1.35
		data["speed"] = float(d.get("speed", 8)) * 1.25
		data["hits"] = int(d.get("hits", 1)) + 1
		data["amp"] = true
	if data.has("rain"):
		var r: Dictionary = data["rain"]
		var spread: Array = r.get("spread", [0])
		var xs: Array = spread if int(data.get("count", 1)) <= 1 else [spread[index % spread.size()]]
		var tgt: Node2D = src.opponent if src.opponent != null else src
		for sx in xs:
			var p := Projectile.new()
			p.setup(src, data, Vector2(tgt.pos.x + float(sx), float(r.get("height", -30))), src.facing, power)
			p.vel = Vector2(0, float(data.get("vy", 9)))
			p.delay = int(r.get("delay", 12))
			p.floor_y = tgt.floor_y
			p.depth = tgt.depth
			p.z_index = 10 + int(p.depth)
			world.add_child(p)
			projectiles.append(p)
		return
	var off: Array = data.get("offset", [0.4, -0.8])
	var start := Vector2(src.pos.x + float(off[0]) * src.H * src.facing, src.pos.y + float(off[1]) * src.H)
	var pr := Projectile.new()
	pr.setup(src, data, start, src.facing, power)
	pr.z_index = 10 + int(pr.depth)
	world.add_child(pr)
	projectiles.append(pr)
	if pr.kind == "bullet":
		Sound.play("shot")


func _step_projectiles() -> void:
	for p in projectiles:
		p.step()
	var all: Array = players + enemies
	for p in projectiles:
		if not p.can_hit():
			continue
		for d in all:
			if d.team == p.team or d.state == "ko" or absf(d.depth - p.depth) > LANE_HIT:
				continue
			var hit := false
			for hr in d.hurtboxes():
				if p.rect().intersects(hr):
					var atk: Dictionary = p.attack()
					var res: String = d.receive_hit(atk, p.owner_fighter, true)
					if res != "whiff":
						p.on_hit()
						_feedback(p.owner_fighter, d, res, atk, p.pos, true)
						if p.explodes():
							p.alive = false
							p.detonated = true
							fx.explosion(p.pos, float(p.data["explode"]), Color(1, 0.6, 0.2))
							Sound.play("explode", 1.2, -4.0)
						hit = true
					break
			if hit or not p.can_hit():
				break
	for p in projectiles:
		if not p.alive and p.explodes() and not p.detonated:
			p.detonated = true
			fx.explosion(p.pos, float(p.data["explode"]), Color(1, 0.8, 0.5))
			Sound.play("explode", 1.3, -3.0)
			var r := float(p.data["explode"])
			var area := Rect2(p.pos - Vector2(r, r), Vector2(r, r) * 2.0)
			for d in all:
				if d.team == p.team or absf(d.depth - p.depth) > LANE_HIT * 2.0:
					continue
				for hr in d.hurtboxes():
					if area.intersects(hr):
						var res2: String = d.receive_hit(p.attack(), p.owner_fighter, true)
						_feedback(p.owner_fighter, d, res2, p.attack(), p.pos, true)
						break
	var keep: Array = []
	for p in projectiles:
		if p.alive and absf(p.pos.x - cam_x) < HALF_VIEW + 200.0:
			keep.append(p)
		else:
			p.queue_free()
	projectiles = keep


# --- Deaths, respawns, pickups -----------------------------------------------------------------

func _deaths() -> void:
	# Chip and armor damage can drop health to 0 without a knockdown; send
	# those fighters into the KO fall so they don't stand around at 0 HP.
	for f in players + enemies:
		if f.health <= 0.0 and f.state not in ["ko", "airhit", "thrown", "throwing"]:
			f.move = {}
			f.move_id = ""
			f.throw_victim = null
			f.vel = Vector2(-3.0 * f.facing, -6.0)
			f.pos.y = minf(f.pos.y, f.floor_y - 1.0)
			f.set_state("airhit")
	var keep: Array = []
	for e in enemies:
		if e.health <= 0.0 and e.state == "ko":
			var t: int = e.get_meta("dead_t", 0) + 1
			e.set_meta("dead_t", t)
			e.alpha = 1.0 if (t / 4) % 2 == 0 else 0.3
			if t == 1:
				kills += 1
				level_kills += 1
				var bonus: int = e.get_meta("score", 100)
				var who := 0
				if players.size() > 1 and absf(players[1].pos.x - e.pos.x) < absf(players[0].pos.x - e.pos.x):
					who = 1
				score[who] += bonus
				fx.text(e.pos + Vector2(0, -e.H * 0.6), "+%d" % bonus, Color(1, 0.85, 0.3))
				if not e.has_meta("boss") and randf() < 0.28:
					_drop_pickup(e)
			if t > 50 and not e.has_meta("boss"):
				ai_of.erase(e)
				if focus_enemy == e:
					focus_enemy = null
				e.queue_free()
				continue
		keep.append(e)
	enemies = keep
	var any_alive := false
	for i in players.size():
		var p: Node2D = players[i]
		if p.health > 0.0:
			any_alive = true
			continue
		if p.state != "ko":
			if lives[i] >= 0:
				any_alive = true
			continue
		respawn_t[i] += 1
		if respawn_t[i] == 70:
			lives[i] -= 1
			if lives[i] >= 0:
				respawn_t[i] = 0
				p.health = p.max_health
				p.meter = maxf(p.meter, 1000.0 / 3.0)
				p.to_neutral()
				p.pos.y = p.floor_y
				p.invuln = 120
				p.vel = Vector2.ZERO
				fx.shockring(p.pos + Vector2(0, -p.H * 0.5), p.look.get("power", Color.WHITE), 10.0, 4.0, 24)
				any_alive = true
		elif lives[i] >= 0:
			any_alive = true
	if not any_alive and phase in ["play", "go", "boss"]:
		phase = "gameover"
		pt = 0
		_say("GAME OVER", "", 400)
		Sound.play("ko")


func _drop_pickup(e: Node2D) -> void:
	var kinds := ["burger", "burger", "battery", "medkit"]
	pickups.append({"x": e.pos.x, "depth": e.depth, "kind": kinds[randi() % kinds.size()], "t": 0})


func _pickups_tick() -> void:
	var keep: Array = []
	for pk in pickups:
		pk["t"] += 1
		var taken := false
		for p in players:
			if p.health > 0.0 and absf(p.pos.x - float(pk["x"])) < 22.0 and absf(p.depth - float(pk["depth"])) < 12.0 and p.grounded():
				match pk["kind"]:
					"burger":
						p.health = minf(p.max_health, p.health + 250.0)
						fx.text(p.pos + Vector2(0, -p.H), "BIG BELLY BURGER +250", Color(0.6, 1, 0.5))
					"medkit":
						p.health = minf(p.max_health, p.health + 500.0)
						fx.text(p.pos + Vector2(0, -p.H), "MEDKIT +500", Color(0.6, 1, 0.5))
					"battery":
						p.meter = minf(1000.0, p.meter + 1000.0 / 3.0)
						fx.text(p.pos + Vector2(0, -p.H), "SPEED FORCE CELL +1 BAR", Color(1, 0.9, 0.3))
				Sound.play("menu_ok")
				taken = true
				break
		if not taken and pk["t"] < 900:
			keep.append(pk)
	pickups = keep


func _draw_pickups() -> void:
	for pk in pickups:
		var x: float = pk["x"]
		var y: float = FEET_TOP + float(pk["depth"]) - 2.0 - absf(sin(float(pk["t"]) * 0.1)) * 3.0
		if int(pk["t"]) > 780 and int(pk["t"]) % 8 < 4:
			continue
		pickup_layer.draw_set_transform(Vector2(x, FEET_TOP + float(pk["depth"])), 0.0, Vector2(1, 0.3))
		pickup_layer.draw_circle(Vector2.ZERO, 10, Color(0, 0, 0, 0.35))
		pickup_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		match pk["kind"]:
			"burger":
				pickup_layer.draw_rect(Rect2(x - 9, y - 14, 18, 5), Color(0.85, 0.55, 0.2))
				pickup_layer.draw_rect(Rect2(x - 10, y - 9, 20, 3), Color(0.3, 0.7, 0.2))
				pickup_layer.draw_rect(Rect2(x - 10, y - 6, 20, 3), Color(0.45, 0.22, 0.1))
				pickup_layer.draw_rect(Rect2(x - 9, y - 3, 18, 3), Color(0.85, 0.55, 0.2))
			"medkit":
				pickup_layer.draw_rect(Rect2(x - 10, y - 14, 20, 14), Color(0.95, 0.95, 0.95))
				pickup_layer.draw_rect(Rect2(x - 2, y - 12, 4, 10), Color(0.85, 0.1, 0.1))
				pickup_layer.draw_rect(Rect2(x - 6, y - 9, 12, 4), Color(0.85, 0.1, 0.1))
			"battery":
				pickup_layer.draw_rect(Rect2(x - 6, y - 18, 12, 18), Color(0.15, 0.15, 0.2))
				pickup_layer.draw_rect(Rect2(x - 4, y - 16, 8, 14), Color(1, 0.85, 0.2, 0.6 + 0.4 * sin(float(pk["t"]) * 0.3)))
				pickup_layer.draw_rect(Rect2(x - 2, y - 20, 4, 2), Color(0.6, 0.6, 0.65))


# --- Hooks used by fighters (same API as the versus fight manager) -------------------------------

func bounds_for(f: Node2D) -> Vector2:
	var left := cam_x - HALF_VIEW + EDGE
	var right := cam_x + HALF_VIEW - EDGE
	if f.team == 1:
		left -= 80.0
		right += 80.0
	return Vector2(maxf(EDGE, left), minf(STAGE_W - EDGE, right))


func clamp_fighter(f: Node2D) -> void:
	var b := bounds_for(f)
	f.pos.x = clampf(f.pos.x, b.x, b.y)
	f.pos.y = minf(f.pos.y, f.floor_y)


func at_wall(f: Node2D) -> bool:
	var b := bounds_for(f)
	return f.pos.x <= b.x + 2.0 or f.pos.x >= b.y - 2.0


func on_super(f: Node2D, m: Dictionary) -> void:
	cinematic = 28
	var power: Color = f.look.get("power", Color.WHITE)
	_say(str(m.get("name", "SUPER")).to_upper(), "", 45)
	Sound.play("super")
	Sound.announce("super_voice")
	fx.shockring(f.pos + Vector2(0, -f.H * 0.5), power, 10.0, 4.0, 24)
	zoom_punch = 0.06


func on_amplify(f: Node2D) -> void:
	fx.text(f.pos + Vector2(0, -f.H * 1.15), "AMPLIFIED", f.look.get("power", Color.WHITE))
	Sound.play("super", 1.6, -6.0)


func on_breaker(f: Node2D) -> void:
	f.to_neutral()
	f.invuln = 30
	for e in enemies + players:
		if e.team != f.team and e.health > 0.0 and absf(e.pos.x - f.pos.x) < 160.0 and absf(e.depth - f.depth) < 30.0:
			var away := 1.0 if e.pos.x > f.pos.x else -1.0
			e.move = {}
			e.vel = Vector2(7.0 * away, -7.0)
			e.pos.y = minf(e.pos.y, e.floor_y - 1.0)
			e.set_state("airhit")
	fx.text(f.pos + Vector2(0, -f.H * 1.2), "BREAKER!", Color(1, 1, 1))
	fx.shockring(f.pos + Vector2(0, -f.H * 0.5), f.look.get("power", Color.WHITE), 12.0, 6.0, 22)
	Sound.play("explode", 1.4, -4.0)
	shake(6.0)


func throw_break(a: Node2D, d: Node2D) -> void:
	for f in [a, d]:
		if f != null:
			f.throw_victim = null
			f.thrower = null
			f.to_neutral()
	Sound.play("block")


func fx_wallbounce(f: Node2D) -> void:
	fx.dust(f.pos + Vector2(0, -f.H * 0.5), 1.4)
	Sound.play("slam", 1.3, -4.0)
	shake(4.0)


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
	match kind:
		"flare":
			fx.explosion(f.pos + Vector2(0, -f.H * 0.6), 160.0, Color(1, 0.9, 0.4))
			shake(6.0)
		"sonic_beam":
			var head: Vector2 = f.pos + Vector2(0.25 * f.H * f.facing, -0.85 * f.H)
			fx.beam(head, head + Vector2(600.0 * f.facing, 10), power, 14.0, int(f.move.get("active", 40)))
		"breach":
			fx.breach(f.pos + Vector2(0, -f.H * 0.5), power)
		"heal":
			fx.shockring(f.pos + Vector2(0, -f.H * 0.5), power, 8.0, 2.0, 30)


func shake(amount: float) -> void:
	if Game.settings.get("shake", true):
		shake_amt = maxf(shake_amt, amount)


func _update_camera() -> void:
	var sum := 0.0
	var n := 0
	for p in players:
		if p.health > 0.0:
			sum += p.pos.x
			n += 1
	if n > 0 and phase not in ["boss", "boss_intro"]:
		var target := clampf(sum / n + 60.0, HALF_VIEW, STAGE_W - HALF_VIEW)
		# Don't scroll forward while enemies are still on screen.
		if _alive_enemies() > 0 and target > cam_x:
			target = cam_x
		cam_x = lerpf(cam_x, target, 0.08)
	var off := Vector2.ZERO
	if shake_amt > 0.1:
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
		shake_amt *= 0.85
	cam.position = Vector2(round(cam_x), 180) + off.round()
	zoom_punch *= 0.86
	cam.zoom = Vector2.ONE * (1.0 + zoom_punch)
	arena.cam_left = round(cam_x) - HALF_VIEW


# --- Pause & game over ----------------------------------------------------------------------------

func _on_pad_lost(_device: int) -> void:
	if not autoplay and phase in ["play", "go", "boss"] and not get_tree().paused:
		open_pause()


func _make_menu(title: String, items: Array) -> Control:
	if menu != null:
		menu.queue_free()
	var m: Control = MenuList.new()
	m.title = title
	m.width = 220.0
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	m.set_items(items)
	m.position = Vector2(210, 110)
	ui.add_child(m)
	menu = m
	return m


func open_pause() -> void:
	get_tree().paused = true
	Sound.play("menu_ok")
	var m := _make_menu("PAUSED", [{"id": "resume", "label": "Resume"}, {"id": "controls", "label": "Brawler Controls"},
		{"id": "restart", "label": "Restart Level"}, {"id": "menu", "label": "Quit to Main Menu"}])
	m.chosen.connect(_on_pause_choice)
	m.cancelled.connect(func(): _on_pause_choice("resume"))


func _on_pause_choice(id: String) -> void:
	match id:
		"resume":
			menu.queue_free()
			menu = null
			get_tree().paused = false
			pause_lock = 10
		"controls":
			var m := _make_menu("BRAWLER CONTROLS", [
				{"id": "back", "label": "Move", "value": "Left/Right + Up/Down"},
				{"id": "back", "label": "Attacks", "value": "Light / Medium / Heavy"},
				{"id": "back", "label": "Specials", "value": "SP, Fwd+SP, Back+SP"},
				{"id": "back", "label": "Block", "value": "BLOCK (hold)"},
				{"id": "back", "label": "Jump / Grab", "value": "THROW (grabs when close)"},
				{"id": "back", "label": "Super (3 bars)", "value": "LIGHT + HEAVY"},
				{"id": "back", "label": "Back", "value": ""}])
			m.width = 320.0
			m.set_items(m.items)
			m.position = Vector2(160, 80)
			m.chosen.connect(func(_i): open_pause())
			m.cancelled.connect(open_pause)
		"restart":
			get_tree().paused = false
			Game.goto("brawl")
		"menu":
			Game.goto("menu")


func _show_gameover() -> void:
	var m := _make_menu("GAME OVER", [{"id": "continue", "label": "Continue (restart level)"}, {"id": "menu", "label": "Main Menu"}])
	m.chosen.connect(func(id):
		if id == "continue":
			Game.brawl["continues"] = int(Game.brawl.get("continues", 0)) + 1
			Game.goto("brawl")
		else:
			Game.goto("menu"))
