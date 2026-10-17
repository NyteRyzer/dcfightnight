extends Control
## Fight HUD: health bars with damage trails, super meters, round markers,
## timer, combo counters, announcements, super banners and the VS splash.

const Rig = preload("res://scripts/combat/rig.gd")
const Poses = preload("res://scripts/combat/poses.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")

var fight: Node = null
var trail := [1.0, 1.0]
var announce_text := ""
var announce_sub := ""
var announce_t := 0
var announce_col := Color(1, 0.85, 0.2)
var banner_text := ""
var banner_t := 0
var banner_side := 0
var banner_col := Color.WHITE
var combo := [0, 0]
var combo_dmg := [0.0, 0.0]
var combo_t := [0, 0]
var flash_t := 0
var vs_t := 0
var training_info := ""
var ladder_label := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fight != null:
		for i in 2:
			var f: Node2D = fight.fighters[i]
			var p := Portrait.new()
			p.position = Vector2(8.0 if i == 0 else 596.0, 8)
			p.size = Vector2(36, 36)
			p.look = f.look
			p.H = f.H
			p.facing = 1 if i == 0 else -1
			add_child(p)


func announce(text: String, sub: String = "", frames: int = 70, col: Color = Color(1, 0.85, 0.2)) -> void:
	announce_text = text
	announce_sub = sub
	announce_t = frames
	announce_col = col


func banner(text: String, side: int, col: Color) -> void:
	banner_text = text
	banner_side = side
	banner_t = 50
	banner_col = col


func show_combo(side: int, hits: int, dmg: float) -> void:
	combo[side] = hits
	combo_dmg[side] = dmg
	combo_t[side] = 70


func tick() -> void:
	if announce_t > 0:
		announce_t -= 1
	if banner_t > 0:
		banner_t -= 1
	if flash_t > 0:
		flash_t -= 1
	if vs_t > 0:
		vs_t -= 1
	for i in 2:
		if combo_t[i] > 0:
			combo_t[i] -= 1
		if fight != null:
			var f: Node2D = fight.fighters[i]
			var hp := clampf(f.health / f.max_health, 0.0, 1.0)
			if f.state in ["hitstun", "airhit", "blockstun", "thrown"]:
				pass
			else:
				trail[i] = move_toward(trail[i], hp, 0.008)
			if trail[i] < hp:
				trail[i] = hp
	queue_redraw()


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 3) -> void:
	var font: Font = Game.font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	if outline > 0:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, col.a))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _bar(x: float, y: float, w: float, h: float, ratio: float, tr: float, flip: bool, fill: Color) -> void:
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(x, y, w, h), Color(0.25, 0.05, 0.05))
	var tw := w * tr
	var hw := w * ratio
	if flip:
		draw_rect(Rect2(x + w - tw, y, tw, h), Color(1, 0.85, 0.3))
		draw_rect(Rect2(x + w - hw, y, hw, h), fill)
		draw_rect(Rect2(x + w - hw, y, hw, 3), fill.lightened(0.35))
	else:
		draw_rect(Rect2(x, y, tw, h), Color(1, 0.85, 0.3))
		draw_rect(Rect2(x, y, hw, h), fill)
		draw_rect(Rect2(x, y, hw, 3), fill.lightened(0.35))
	draw_rect(Rect2(x, y, w, h), Color(1, 1, 1, 0.5), false, 1.0)


func _draw() -> void:
	if fight == null:
		return
	var fs: Array = fight.fighters
	var training: bool = fight.training
	for i in 2:
		var f: Node2D = fs[i]
		var flip := i == 1
		var hp := clampf(f.health / f.max_health, 0.0, 1.0)
		var bx := 46.0 if i == 0 else 362.0
		var col := Color(0.15, 0.85, 0.3) if hp > 0.3 else Color(0.95, 0.25, 0.15)
		_bar(bx, 14, 232, 14, hp, trail[i], flip, col)
		# Portrait chip.
		var px := 8.0 if i == 0 else 596.0
		draw_rect(Rect2(px - 2, 6, 40, 40), Color(0, 0, 0))
		draw_rect(Rect2(px - 1, 7, 38, 38), Color(1, 1, 1, 0.6), false, 1.0)
		var name_s: String = f.def.get("name", "").to_upper()
		if i == 0:
			_text(Vector2(bx, 40), name_s, 10, Color(1, 1, 1))
		else:
			_text(Vector2(bx + 232, 40), name_s, 10, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
		# Round markers.
		if not training:
			var need: int = fight.rounds_to_win
			for r in need:
				var mx := bx + 232 - 10 - r * 12 if i == 0 else bx + 4 + r * 12
				var won: bool = f.wins > r
				draw_circle(Vector2(mx + 3, 36), 4.5, Color(0, 0, 0))
				draw_circle(Vector2(mx + 3, 36), 3.5, Color(1, 0.8, 0.2) if won else Color(0.25, 0.25, 0.3))
		# Super meter.
		var mw := 150.0
		var mxb := 12.0 if i == 0 else 640.0 - 12.0 - mw
		var m: float = clampf(f.meter / 1000.0, 0.0, 1.0)
		draw_rect(Rect2(mxb - 2, 338, mw + 4, 12), Color(0, 0, 0, 0.85))
		var power: Color = f.look.get("power", Color(0.3, 0.6, 1))
		var full := m >= 1.0
		var mc := power if not full else power.lerp(Color.WHITE, (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.3)
		if i == 0:
			draw_rect(Rect2(mxb, 340, mw * m, 8), mc)
		else:
			draw_rect(Rect2(mxb + mw * (1.0 - m), 340, mw * m, 8), mc)
		for k in range(1, 3):
			draw_line(Vector2(mxb + mw * k / 3.0, 338), Vector2(mxb + mw * k / 3.0, 350), Color(0, 0, 0, 0.9), 2.0)
		var bars := int(floor(f.meter / (1000.0 / 3.0) + 0.001))
		var lab := "SUPER READY!" if full else ("%d BAR%s" % [bars, "" if bars == 1 else "S"] if bars > 0 else "METER")
		if i == 0:
			_text(Vector2(mxb + mw + 6, 349), lab, 9, Color(1, 1, 0.6) if full else Color(0.8, 0.8, 0.9))
		else:
			_text(Vector2(mxb - 6, 349), lab, 9, Color(1, 1, 0.6) if full else Color(0.8, 0.8, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
		# Combo counter.
		if combo_t[i] > 0 and combo[i] >= 2:
			var cx := 30.0 if i == 0 else 610.0
			var al := HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			var a := minf(1.0, combo_t[i] / 15.0)
			_text(Vector2(cx, 120), "%d HITS" % combo[i], 20, Color(1, 0.85, 0.2, a), al, 4)
			_text(Vector2(cx, 136), "%d DAMAGE" % int(combo_dmg[i]), 10, Color(1, 1, 1, a), al)
	# Timer.
	draw_rect(Rect2(296, 8, 48, 28), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(296, 8, 48, 28), Color(1, 1, 1, 0.4), false, 1.0)
	var tstr := "--" if training or fight.round_time <= 0 else str(int(ceil(fight.timer / 60.0)))
	_text(Vector2(320, 31), tstr, 20, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	if ladder_label != "":
		_text(Vector2(320, 50), ladder_label, 9, Color(0.85, 0.85, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	if training and training_info != "":
		var lines := training_info.split("\n")
		draw_rect(Rect2(212, 56, 216, 12 + lines.size() * 11), Color(0, 0, 0, 0.55))
		for li in lines.size():
			_text(Vector2(218, 67 + li * 11), lines[li], 9, Color(0.85, 1.0, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 0)
	# Super banner.
	if banner_t > 0:
		var k := minf(1.0, (50 - banner_t) / 6.0)
		var by := 150.0
		var x0 := -640.0 * (1.0 - k) if banner_side == 0 else 640.0 * (1.0 - k)
		draw_rect(Rect2(x0, by, 640, 34), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(x0, by, 640, 2), banner_col)
		draw_rect(Rect2(x0, by + 32, 640, 2), banner_col)
		_text(Vector2(320 + x0, by + 25), banner_text, 22, banner_col.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, 4)
	# Announcement.
	if announce_t > 0:
		var a2 := minf(1.0, announce_t / 10.0)
		var sc := 1.0 + maxf(0.0, (announce_t - 55) / 15.0) * 0.6
		_text(Vector2(320, 170), announce_text, int(36 * sc), Color(announce_col.r, announce_col.g, announce_col.b, a2), HORIZONTAL_ALIGNMENT_CENTER, 6)
		if announce_sub != "":
			_text(Vector2(320, 196), announce_sub, 12, Color(1, 1, 1, a2), HORIZONTAL_ALIGNMENT_CENTER, 3)
	# VS splash.
	if vs_t > 0:
		_draw_vs(fs)
	if flash_t > 0 and not Game.settings.get("reduce_flash", false):
		draw_rect(Rect2(0, 0, 640, 360), Color(1, 1, 1, flash_t / 12.0 * 0.6))


func _draw_vs(fs: Array) -> void:
	var a := minf(1.0, vs_t / 15.0)
	draw_rect(Rect2(0, 0, 640, 360), Color(0.02, 0.02, 0.06, 0.92 * a))
	var slide := clampf((150 - vs_t) / 12.0, 0.0, 1.0)
	for i in 2:
		var f: Node2D = fs[i]
		var power: Color = f.look.get("power", Color.WHITE)
		var x := 160.0 if i == 0 else 480.0
		var off := (1.0 - slide) * (-260.0 if i == 0 else 260.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 150 + off, 40), Vector2(x + 150 + off, 40), Vector2(x + 120 + off, 330), Vector2(x - 180 + off, 330)]), Color(power.r, power.g, power.b, 0.18 * a))
		var p := Poses.get_pose("super")
		var scale := 1.25
		draw_set_transform(Vector2(x + off, 320), 0.0, Vector2(scale, scale))
		Rig.draw(self, Vector2.ZERO, 1 if i == 0 else -1, p, f.look, f.H, {"alpha": a})
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text(Vector2(x + off, 330), f.def.get("name", "").to_upper(), 16, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 4)
		_text(Vector2(x + off, 344), f.def.get("real_name", ""), 9, Color(0.8, 0.8, 0.9, a), HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(320, 190), "VS", 44, Color(1, 0.85, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, 6)
	var st: Dictionary = Data.stage(Game.stage_id)
	_text(Vector2(320, 30), st.get("name", "").to_upper(), 14, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(320, 44), st.get("location", ""), 9, Color(0.8, 0.8, 0.9, a), HORIZONTAL_ALIGNMENT_CENTER)
