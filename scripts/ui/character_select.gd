extends Control
## Character select: 14 fighters + random in a 5x3 grid, big animated previews,
## per-player cursors, and costume (alternate suit) selection.

const Rig = preload("res://scripts/combat/rig.gd")
const Poses = preload("res://scripts/combat/poses.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")

const COLS := 5
const CELL := 44.0
const GAP := 4.0
const GRID_X := 202.0
const GRID_Y := 40.0
const STANCE_POSES := {"heavy": ["idle_heavy", "idle_heavy2"], "speed": ["idle_speed", "idle_speed2"], "fem": ["idle_fem", "idle_fem2"],
	"sword": ["idle_sword", "idle_sword2"], "guns": ["idle_guns", "idle_guns2"]}

var ids: Array = []
var cursor := [0, 1]
var costume := [0, 0]
var picked := ["", ""]
var step := 0           # sequential modes: which slot P1 is choosing
var two_humans := false
var single := false
var t := 0.0
var message := ""
var message_t := 0.0
var preview_frame := [0, 0]


func _ready() -> void:
	Sound.play_music("select")
	ids = Data.roster.duplicate()
	ids.append("random")
	two_humans = Game.mode in ["versus", "brawl_coop"]
	single = Game.mode in ["arcade", "survival", "story_choose", "brawl"]
	var prev0: int = ids.find(Game.chars[0])
	var prev1: int = ids.find(Game.chars[1])
	cursor = [maxi(0, prev0), maxi(0, prev1 if prev1 != prev0 else (prev0 + 1) % (ids.size() - 1))]
	costume = [0, 0]
	if Game.mode == "story_choose":
		cursor[0] = ids.find("flash")
	for i in ids.size():
		var id: String = ids[i]
		if id == "random" or not _available(id):
			continue
		var f := Data.fighter(id)
		var p := Portrait.new()
		var r := _cell_rect(i)
		p.position = r.position
		p.size = r.size
		p.set_fighter(f)
		p.caption = str(f.get("short", f["name"]))
		add_child(p)


func _cell_rect(i: int) -> Rect2:
	return Rect2(GRID_X + (i % COLS) * (CELL + GAP), GRID_Y + (i / COLS) * (CELL + GAP), CELL, CELL)


func _available(id: String) -> bool:
	if id == "random":
		return true
	if Game.mode == "story_choose" and (Data.locked.has(id) or Game.is_villain(id)):
		return false
	return Game.is_unlocked(id)


func _active_slot() -> int:
	if two_humans or single:
		return 0
	return step


func _costumes(id: String) -> Array:
	if id == "random" or not Data.fighters.has(id):
		return []
	return Data.fighter(id)["costumes"]


func _process(delta: float) -> void:
	t += delta
	message_t = maxf(0.0, message_t - delta)
	for i in 2:
		preview_frame[i] += 1
	if two_humans:
		for p in 2:
			_handle_player(p, p)
	else:
		_handle_player(0, _active_slot())
	queue_redraw()


func _handle_player(input_pid: int, slot: int) -> void:
	if picked[slot] != "":
		if InputManager.menu("back", input_pid):
			picked[slot] = ""
			Sound.play("menu_back")
		return
	var c: int = cursor[slot]
	var n := ids.size()
	if InputManager.menu("left", input_pid):
		c = wrapi(c - 1, 0, n)
	elif InputManager.menu("right", input_pid):
		c = wrapi(c + 1, 0, n)
	elif InputManager.menu("up", input_pid):
		c = wrapi(c - COLS, 0, n)
	elif InputManager.menu("down", input_pid):
		c = wrapi(c + COLS, 0, n)
	if c != cursor[slot]:
		cursor[slot] = c
		costume[slot] = 0
		preview_frame[slot] = 0
		Sound.play("menu_move")
	var id: String = ids[cursor[slot]]
	if InputManager.menu("costume", input_pid):
		var cs := _costumes(id)
		if cs.size() > 1 and _available(id):
			costume[slot] = (costume[slot] + 1) % cs.size()
			preview_frame[slot] = 0
			Sound.play("menu_move", 1.3)
	if InputManager.menu("accept", input_pid):
		if not _available(id):
			message = Data.locked.get(id, "Not available in this mode.")
			message_t = 2.5
			Sound.play("menu_back")
			return
		if id == "random":
			var pool: Array = []
			for pid2 in Data.roster:
				if _available(pid2):
					pool.append(pid2)
			id = pool[randi() % pool.size()]
			cursor[slot] = ids.find(id)
			costume[slot] = randi() % _costumes(id).size()
		picked[slot] = id
		Game.costume_pref[slot] = costume[slot]
		Sound.play("menu_ok")
		Sound.play("hit_m", 1.2, -6.0)
		_after_pick(slot)
	elif InputManager.menu("back", input_pid):
		Sound.play("menu_back")
		if not two_humans and step == 1 and not single:
			step = 0
			picked[0] = ""
		else:
			Game.goto("menu")


func _after_pick(slot: int) -> void:
	if single:
		var id: String = picked[0]
		match Game.mode:
			"arcade":
				Game.start_arcade(id)
			"survival":
				Game.start_survival(id)
			"story_choose":
				Game.story_champion = id
				Game.story_fight()
			"brawl":
				Game.start_brawl([id])
		return
	if not two_humans and slot == 0:
		step = 1
		return
	if picked[0] != "" and picked[1] != "":
		Game.chars = [picked[0], picked[1]]
		await get_tree().create_timer(0.35).timeout
		if Game.mode == "brawl_coop":
			Game.start_brawl([picked[0], picked[1]])
		else:
			Game.goto("stage")


func _text(pos: Vector2, s: String, size: int, col: Color, center := false, outline := 3) -> void:
	var font: Font = Game.font
	var p := pos
	if center:
		p.x -= font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	if outline > 0:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color.BLACK)
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _wrap(s: String, width: float, size: int) -> Array:
	var font: Font = Game.font
	var lines: Array = []
	var cur := ""
	for word in s.split(" "):
		var test := word if cur == "" else cur + " " + word
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = test
	if cur != "":
		lines.append(cur)
	return lines


func _draw() -> void:
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(640, 0), Vector2(640, 360), Vector2(0, 360)]),
		PackedColorArray([Color("120a20"), Color("0a1226"), Color("0a0c18"), Color("1c0a12")]))
	for i in 12:
		draw_line(Vector2(i * 60.0 + fmod(t * 20.0, 60.0), 0), Vector2(i * 60.0 + fmod(t * 20.0, 60.0) - 80, 360), Color(1, 1, 1, 0.03), 14.0)
	var title := "SELECT YOUR FIGHTER"
	match Game.mode:
		"arcade": title = "ARCADE - SELECT YOUR FIGHTER"
		"survival": title = "SURVIVAL - SELECT YOUR FIGHTER"
		"story_choose": title = "CHOOSE YOUR CHAMPION"
		"brawl": title = "BEAT 'EM UP - SELECT YOUR FIGHTER"
		"brawl_coop": title = "BEAT 'EM UP CO-OP - SELECT FIGHTERS"
		"training": title = "TRAINING - SELECT FIGHTER" if step == 0 else "TRAINING - SELECT DUMMY"
		"versus_cpu": title = "SELECT YOUR FIGHTER" if step == 0 else "SELECT CPU OPPONENT"
	_text(Vector2(320, 26), title, 16, Color(1, 0.85, 0.25), true, 4)
	var slots := [0] if single else [0, 1]
	# Big previews.
	for s in slots:
		var id: String = picked[s] if picked[s] != "" else ids[cursor[s]]
		var x := 100.0 if s == 0 else 540.0
		var col := Color(1, 0.3, 0.25) if s == 0 else Color(0.3, 0.6, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 90, 40), Vector2(x + 90, 40), Vector2(x + 78, 352), Vector2(x - 102, 352)]), Color(col.r, col.g, col.b, 0.12))
		if id == "random" or not _available(id):
			_text(Vector2(x, 210), "?", 60, Color(1, 1, 1, 0.8), true, 4)
			_text(Vector2(x, 330), "RANDOM" if id == "random" else "LOCKED", 14, Color(1, 1, 1), true)
			continue
		var f := Data.fighter(id)
		var cs: Array = f["costumes"]
		var ci: int = clampi(costume[s], 0, cs.size() - 1)
		var look: Dictionary = cs[ci]["look"]
		var power: Color = look.get("power", Color.WHITE)
		draw_set_transform(Vector2(x, 318), 0.0, Vector2(1.6, 0.3))
		draw_circle(Vector2.ZERO, 40, Color(power.r, power.g, power.b, 0.18))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var stance: Array = STANCE_POSES.get(str(f.get("stance", "")), ["idle", "idle2"])
		var pose: Dictionary
		if picked[s] != "":
			pose = Poses.get_pose(f.get("victory_pose", "victory"))
		else:
			pose = Poses.blend(Poses.get_pose("super"), Poses.blend(Poses.get_pose(stance[0]), Poses.get_pose(stance[1]), (sin(t * 5.0) + 1.0) * 0.5), minf(1.0, preview_frame[s] / 14.0))
		draw_set_transform(Vector2(x, 318), 0.0, Vector2(1.1, 1.1))
		Rig.draw(self, Vector2.ZERO, 1 if s == 0 else -1, pose, look, float(f["height"]), {"flash": maxf(0.0, 1.0 - preview_frame[s] / 6.0) * 0.6, "time": t})
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text(Vector2(x, 334), str(f["name"]).to_upper(), 14, Color(1, 1, 1), true, 4)
		var cname := str(cs[ci]["name"])
		if cs.size() > 1:
			cname = "< %s >  %d/%d" % [cname, ci + 1, cs.size()]
		_text(Vector2(x, 348), cname, 9, Color(1, 0.85, 0.4), true, 2)
		if picked[s] != "":
			_text(Vector2(x, 58), "READY!", 14, col.lightened(0.4), true, 3)
	# Grid frames.
	for i in ids.size():
		var r := _cell_rect(i)
		var id2: String = ids[i]
		draw_rect(r.grow(1), Color(0, 0, 0))
		if id2 == "random":
			draw_rect(r, Color(0.12, 0.12, 0.22))
			_text(r.get_center() + Vector2(0, 8), "?", 22, Color(1, 0.85, 0.3), true)
			_text(r.position + Vector2(r.size.x * 0.5, r.size.y - 3), "RANDOM", 7, Color(0.9, 0.9, 1), true, 2)
		elif not _available(id2):
			draw_rect(r, Color(0.05, 0.05, 0.08))
			_text(r.get_center() + Vector2(0, 8), "?", 22, Color(0.5, 0.5, 0.6), true)
	# Cursors.
	for s2 in slots:
		var r2 := _cell_rect(cursor[s2]).grow(2 + (1 if int(t * 6) % 2 == 0 else 0))
		var col2 := Color(1, 0.3, 0.25) if s2 == 0 else Color(0.3, 0.6, 1.0)
		if picked[s2] != "":
			col2 = col2.lightened(0.5)
		draw_rect(r2, col2, false, 2.0)
		var lab := "1P" if s2 == 0 else ("2P" if two_humans else "CPU")
		_text(r2.position + Vector2(2 if s2 == 0 else r2.size.x - 18, -2), lab, 9, col2, false, 3)
	# Info panels.
	for k in slots.size():
		var s3: int = slots[k]
		var id3: String = ids[cursor[s3]]
		var bw := 236.0 if single else 116.0
		var bx := GRID_X + (0.0 if single or k == 0 else 120.0)
		var by := GRID_Y + 3 * (CELL + GAP) + 4
		draw_rect(Rect2(bx, by, bw, 112), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bx, by, bw, 112), Color(1, 1, 1, 0.2), false, 1.0)
		if id3 == "random":
			_text(Vector2(bx + 6, by + 16), "RANDOM", 11, Color(1, 0.85, 0.3), false, 2)
			continue
		if not _available(id3):
			_text(Vector2(bx + 6, by + 16), "LOCKED", 11, Color(0.7, 0.7, 0.8), false, 2)
			var ll := _wrap(Data.locked.get(id3, "Not available in this mode."), bw - 12, 8)
			for li in ll.size():
				_text(Vector2(bx + 6, by + 30 + li * 10), ll[li], 8, Color(0.8, 0.8, 0.9), false, 0)
			continue
		var f3 := Data.fighter(id3)
		_text(Vector2(bx + 6, by + 13), str(f3.get("real_name", "")), 8, Color(0.7, 0.8, 1.0), false, 0)
		_text(Vector2(bx + 6, by + 25), str(f3.get("archetype", "")), 9, Color(1, 0.85, 0.3), false, 0)
		var lines := _wrap(str(f3.get("bio", "")), bw - 12, 8)
		for li in mini(lines.size(), 6):
			_text(Vector2(bx + 6, by + 38 + li * 10), lines[li], 8, Color(0.9, 0.9, 0.95), false, 0)
		_text(Vector2(bx + 6, by + 107), "HP %d   SPEED %.1f" % [int(f3.get("health", 1000)), float(f3.get("walk", 3))], 8, Color(0.6, 1.0, 0.6), false, 0)
	var hint := "%s: select   %s: change suit   %s: back" % [InputManager.prompt("accept", 0), InputManager.prompt("costume", 0), InputManager.prompt("back", 0)]
	if two_humans and not InputManager.using_pad:
		hint = "P1: WASD, J select, U suit, K back     P2: Arrows, Num1 select, Num4 suit, Num2 back"
	_text(Vector2(320, 314), hint, 8, Color(0.8, 0.8, 0.9), true, 2)
	if message_t > 0.0:
		_text(Vector2(320, 302), message, 10, Color(1, 0.5, 0.4), true, 3)
