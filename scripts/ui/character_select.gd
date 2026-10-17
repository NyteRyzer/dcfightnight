extends Control
## Character select with portraits, big animated previews, per-player cursors,
## random select and alternate costumes (confirm with HEAVY).

const Rig = preload("res://scripts/combat/rig.gd")
const Poses = preload("res://scripts/combat/poses.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")

const COLS := 5
const CELL := 50.0
const GAP := 4.0
const GRID_X := 186.0
const GRID_Y := 58.0

var ids: Array = []
var cursor := [0, 1]
var picked := ["", ""]
var picked_alt := [false, false]
var step := 0           # for sequential modes: which slot P1 is choosing
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
	two_humans = Game.mode == "versus"
	single = Game.mode in ["arcade", "survival", "story_choose"]
	var prev0: int = ids.find(Game.chars[0])
	var prev1: int = ids.find(Game.chars[1])
	cursor = [maxi(0, prev0), maxi(0, prev1 if prev1 != prev0 else (prev0 + 1) % (ids.size() - 1))]
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
	var cx := i % COLS
	var cy := i / COLS
	return Rect2(GRID_X + cx * (CELL + GAP), GRID_Y + cy * (CELL + GAP), CELL, CELL)


func _available(id: String) -> bool:
	if id == "random":
		return true
	if Game.mode == "story_choose" and Data.locked.has(id):
		return false
	return Game.is_unlocked(id)


func _active_slot() -> int:
	# Which slot the keyboard/pad of P1 currently controls in sequential modes.
	if two_humans or single:
		return 0
	return step


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
		preview_frame[slot] = 0
		Sound.play("menu_move")
	var heavy := Input.is_action_just_pressed(InputManager.action_name(input_pid, "heavy"))
	if InputManager.menu("accept", input_pid) or heavy:
		var id: String = ids[cursor[slot]]
		if not _available(id):
			message = Data.locked.get(id, "Locked.")
			message_t = 2.5
			Sound.play("menu_back")
			return
		if id == "random":
			var pool := Game.unlocked_fighters() if Game.mode != "story_choose" else Game.hero_ids()
			id = pool[randi() % pool.size()]
			cursor[slot] = ids.find(id)
		picked[slot] = id
		picked_alt[slot] = heavy
		Game.alt_pref[slot] = heavy
		Sound.play("menu_ok")
		Sound.play("hit_m", 1.2, -6.0)
		_after_pick(slot)
	elif InputManager.menu("back", input_pid):
		if not two_humans and step == 1 and not single:
			step = 0
			picked[0] = ""
			Sound.play("menu_back")
		else:
			Sound.play("menu_back")
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
		return
	if not two_humans and slot == 0:
		step = 1
		return
	if picked[0] != "" and picked[1] != "":
		Game.chars = [picked[0], picked[1]]
		await get_tree().create_timer(0.35).timeout
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
		"training": title = "TRAINING - SELECT FIGHTER" if step == 0 else "TRAINING - SELECT DUMMY"
		"versus_cpu": title = "SELECT YOUR FIGHTER" if step == 0 else "SELECT CPU OPPONENT"
	_text(Vector2(320, 26), title, 18, Color(1, 0.85, 0.25), true, 4)
	# Big previews.
	var slots := [0] if single else [0, 1]
	for s in slots:
		var id: String = picked[s] if picked[s] != "" else ids[cursor[s]]
		var x := 92.0 if s == 0 else 548.0
		var col := Color(1, 0.3, 0.25) if s == 0 else Color(0.3, 0.6, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 80, 50), Vector2(x + 80, 50), Vector2(x + 70, 340), Vector2(x - 90, 340)]), Color(col.r, col.g, col.b, 0.12))
		if id == "random" or not _available(id):
			_text(Vector2(x, 210), "?", 60, Color(1, 1, 1, 0.8), true, 4)
			_text(Vector2(x, 330), "RANDOM" if id == "random" else "LOCKED", 14, Color(1, 1, 1), true)
			continue
		var f := Data.fighter(id)
		var look: Dictionary = f["alt_look"] if (picked[s] != "" and picked_alt[s]) else f["look"]
		var pose: Dictionary
		if picked[s] != "":
			pose = Poses.get_pose(f.get("victory_pose", "victory"))
		else:
			pose = Poses.blend(Poses.get_pose("super"), Poses.blend(Poses.get_pose("idle"), Poses.get_pose("idle2"), (sin(t * 5.0) + 1.0) * 0.5), minf(1.0, preview_frame[s] / 14.0))
		var scale := 1.1
		draw_set_transform(Vector2(x, 322), 0.0, Vector2(scale, scale))
		Rig.draw(self, Vector2.ZERO, 1 if s == 0 else -1, pose, look, float(f["height"]), {"flash": maxf(0.0, 1.0 - preview_frame[s] / 6.0) * 0.6})
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text(Vector2(x, 336), str(f["name"]).to_upper(), 14, Color(1, 1, 1), true, 4)
		_text(Vector2(x, 349), str(f.get("real_name", "")), 9, Color(0.85, 0.85, 0.95), true)
		if picked[s] != "":
			_text(Vector2(x, 66), "READY!", 14, col.lightened(0.4), true, 3)
	# Grid.
	for i in ids.size():
		var r := _cell_rect(i)
		var id: String = ids[i]
		draw_rect(r.grow(1), Color(0, 0, 0))
		draw_rect(r, Color(0.12, 0.12, 0.22))
		if id == "random":
			_text(r.get_center() + Vector2(0, 8), "?", 24, Color(1, 0.85, 0.3), true)
			_text(r.position + Vector2(r.size.x * 0.5, r.size.y - 3), "RANDOM", 7, Color(0.9, 0.9, 1), true, 2)
		elif not _available(id):
			draw_rect(r, Color(0.05, 0.05, 0.08))
			_text(r.get_center() + Vector2(0, 8), "?", 24, Color(0.5, 0.5, 0.6), true)
		else:
			pass
		draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
	# Cursors.
	for s in slots:
		var r2 := _cell_rect(cursor[s]).grow(2 + (1 if int(t * 6) % 2 == 0 else 0))
		var col2 := Color(1, 0.3, 0.25) if s == 0 else Color(0.3, 0.6, 1.0)
		if picked[s] != "":
			col2 = col2.lightened(0.5)
		draw_rect(r2, col2, false, 2.0)
		var lab := "1P" if s == 0 else ("2P" if two_humans else "CPU")
		_text(r2.position + Vector2(2 if s == 0 else r2.size.x - 18, -2), lab, 9, col2, false, 3)
	# Info panel for the hovered fighter(s).
	var info_slots := slots
	for k in info_slots.size():
		var s2: int = info_slots[k]
		var id2: String = ids[cursor[s2]]
		var bx := 186.0 if (k == 0 and not single) or single else 324.0
		var bw := 268.0 if single else 130.0
		draw_rect(Rect2(bx, 172, bw, 128), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bx, 172, bw, 128), Color(1, 1, 1, 0.2), false, 1.0)
		if id2 == "random":
			_text(Vector2(bx + 6, 188), "RANDOM", 11, Color(1, 0.85, 0.3), false, 2)
			continue
		if not _available(id2):
			_text(Vector2(bx + 6, 188), "LOCKED", 11, Color(0.7, 0.7, 0.8), false, 2)
			var ll := _wrap(Data.locked.get(id2, ""), bw - 12, 8)
			for li in ll.size():
				_text(Vector2(bx + 6, 202 + li * 10), ll[li], 8, Color(0.8, 0.8, 0.9), false, 0)
			continue
		var f3 := Data.fighter(id2)
		_text(Vector2(bx + 6, 186), str(f3.get("team", "")).to_upper(), 8, Color(0.7, 0.8, 1.0), false, 0)
		_text(Vector2(bx + 6, 198), str(f3.get("archetype", "")), 9, Color(1, 0.85, 0.3), false, 0)
		var lines := _wrap(str(f3.get("bio", "")), bw - 12, 8)
		for li in mini(lines.size(), 7):
			_text(Vector2(bx + 6, 212 + li * 10), lines[li], 8, Color(0.9, 0.9, 0.95), false, 0)
		_text(Vector2(bx + 6, 294), "HP %d   SPEED %.1f" % [int(f3.get("health", 1000)), float(f3.get("walk", 3))], 8, Color(0.6, 1.0, 0.6), false, 0)
	var hint := "LIGHT: select   HEAVY: alt costume   MEDIUM: back"
	if two_humans:
		hint = "P1: WASD + J/L   P2: Arrows + Num1/Num3 (or , /)   back: K / Num2 (or .)"
	_text(Vector2(320, 316), hint, 8, Color(0.8, 0.8, 0.9), true, 2)
	if message_t > 0.0:
		_text(Vector2(320, 164), message, 10, Color(1, 0.5, 0.4), true, 3)
