extends Control
## Beat 'em up HUD: player portraits, health, 3-bar meter, lives and score;
## the last enemy hit; boss bar; level banners, GO arrow and fades.

const Portrait = preload("res://scripts/ui/portrait.gd")

var stage: Node = null
var trail := [1.0, 1.0]
var boss_trail := 1.0
var _portraits: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in stage.players.size():
		var f: Node2D = stage.players[i]
		var p := Portrait.new()
		p.position = Vector2(6.0 if i == 0 else 600.0, 6)
		p.size = Vector2(34, 34)
		p.look = f.look
		p.H = f.H
		p.facing = 1 if i == 0 else -1
		add_child(p)
		_portraits.append(p)


func _bar(r: Rect2, ratio: float, tr: float, col: Color, rtl: bool) -> void:
	draw_rect(r.grow(1), Color(0, 0, 0, 0.85))
	draw_rect(r, Color(0.25, 0.05, 0.05))
	var tw := r.size.x * clampf(tr, 0.0, 1.0)
	var w := r.size.x * clampf(ratio, 0.0, 1.0)
	if rtl:
		draw_rect(Rect2(r.end.x - tw, r.position.y, tw, r.size.y), Color(1, 0.85, 0.3))
		draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), col)
	else:
		draw_rect(Rect2(r.position, Vector2(tw, r.size.y)), Color(1, 0.85, 0.3))
		draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.25))


func _text(p: Vector2, s: String, size: int, col: Color, outline := 3) -> void:
	var font: Font = Game.font
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color.BLACK)
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _centered(y: float, s: String, size: int, col: Color, outline := 4) -> void:
	var w := Game.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(Vector2(320 - w * 0.5, y), s, size, col, outline)


func _draw() -> void:
	if stage == null:
		return
	var font: Font = Game.font
	# Players.
	for i in stage.players.size():
		var f: Node2D = stage.players[i]
		var rtl: bool = i == 1
		var x0 := 44.0 if not rtl else 396.0
		var hp := clampf(f.health / f.max_health, 0.0, 1.0)
		trail[i] = hp if hp > trail[i] else move_toward(trail[i], hp, 0.006)
		var col := Color(0.3, 0.85, 0.35) if hp > 0.3 else Color(0.95, 0.3, 0.2)
		_bar(Rect2(x0, 8, 200, 9), hp, trail[i], col, rtl)
		# Meter: three segments.
		var power: Color = f.look.get("power", Color(0.4, 0.7, 1))
		for s in 3:
			var seg := Rect2(x0 + (s * 46.0 if not rtl else 200.0 - (s + 1) * 46.0 + 4.0), 20, 42, 4)
			draw_rect(seg.grow(1), Color(0, 0, 0, 0.8))
			var fill := clampf((f.meter - s * 1000.0 / 3.0) / (1000.0 / 3.0), 0.0, 1.0)
			var full: bool = fill >= 1.0
			var c: Color = power if not full else power.lerp(Color.WHITE, 0.3 + 0.3 * sin(stage.total_frames * 0.25))
			draw_rect(Rect2(seg.position.x + (seg.size.x * (1.0 - fill) if rtl else 0.0), seg.position.y, seg.size.x * fill, seg.size.y), c)
		var name := str(f.def.get("short", f.def.get("name", ""))).to_upper()
		var lives_s: String = "x%d" % maxi(0, stage.lives[i])
		var score_s: String = "%07d" % stage.score[i]
		if not rtl:
			_text(Vector2(x0, 35), name, 8, Color(1, 0.9, 0.5))
			_text(Vector2(x0 + 150, 35), score_s, 8, Color.WHITE)
			_text(Vector2(8, 50), lives_s, 9, Color(1, 1, 1))
		else:
			_text(Vector2(x0 + 200 - font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, 35), name, 8, Color(1, 0.9, 0.5))
			_text(Vector2(x0, 35), score_s, 8, Color.WHITE)
			_text(Vector2(612, 50), lives_s, 9, Color(1, 1, 1))
		if f.health <= 0.0 and stage.lives[i] < 0:
			_text(Vector2(x0 + 70, 16), "OUT", 9, Color(1, 0.3, 0.3))
		if stage.combo[i] >= 3:
			var cx := 20.0 if not rtl else 540.0
			_text(Vector2(cx, 110), "%d HITS" % stage.combo[i], 14, Color(1, 0.85, 0.25))
	# Level / area.
	var lv: Dictionary = stage.levels[stage.level_i] if stage.level_i < stage.levels.size() else {}
	var area_n: int = lv.get("areas", []).size()
	var where: String = "BOSS" if stage.phase in ["boss", "boss_intro", "level_clear"] else "AREA %d/%d" % [stage.area_i + 1, area_n]
	_centered(18, "LEVEL %d  -  %s" % [stage.level_i + 1, where], 8, Color(0.8, 0.85, 1.0), 3)
	# Focus enemy.
	var fe = stage.focus_enemy
	if fe != null and is_instance_valid(fe) and stage.focus_t > 0 and not fe.has_meta("boss"):
		var r := Rect2(260, 44, 120, 5)
		_bar(r, fe.health / fe.max_health, fe.health / fe.max_health, Color(0.9, 0.5, 0.2), false)
		_centered(60, str(fe.def.get("name", "")).to_upper(), 7, Color(1, 0.8, 0.6), 2)
	# Boss bar.
	var b = stage.boss
	if b != null and not is_instance_valid(b):
		b = null
	if b == null:
		for e in stage.enemies:
			if e.has_meta("boss") and is_instance_valid(e):
				b = e
	if b != null and is_instance_valid(b) and stage.phase not in ["title"]:
		var ratio := clampf(b.health / b.max_health, 0.0, 1.0)
		boss_trail = ratio if ratio > boss_trail else move_toward(boss_trail, ratio, 0.004)
		var r2 := Rect2(140, 334, 360, 8)
		_bar(r2, ratio, boss_trail, Color(0.85, 0.15, 0.2), false)
		_text(Vector2(140, 330), str(b.def.get("name", "")).to_upper(), 9, Color(1, 0.5, 0.45))
	# GO arrow.
	if stage.phase == "go" and int(stage.pt / 15) % 2 == 0:
		_text(Vector2(560, 160), "GO", 20, Color(1, 0.85, 0.2), 4)
		draw_colored_polygon(PackedVector2Array([Vector2(596, 146), Vector2(620, 158), Vector2(596, 170)]), Color(1, 0.85, 0.2))
	# Messages.
	if stage.message_t > 0:
		var a := clampf(stage.message_t / 15.0, 0.0, 1.0)
		if stage.message_sub != "":
			draw_rect(Rect2(0, 128, 640, 70), Color(0, 0, 0, 0.6 * a))
		_centered(162, stage.message, 24, Color(1, 0.85, 0.25, a), 5)
		if stage.message_sub != "":
			_centered(184, stage.message_sub, 10, Color(0.9, 0.92, 1.0, a), 3)
	if stage.phase == "title" and int(stage.pt / 20) % 2 == 0 and stage.pt > 30:
		_centered(230, "%s to start" % InputManager.prompt("accept"), 9, Color(0.8, 0.85, 1.0), 3)
	# Fade.
	if stage.fade > 0.0:
		draw_rect(Rect2(0, 0, 640, 360), Color(0, 0, 0, stage.fade))
