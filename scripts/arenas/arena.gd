extends Node2D
## Procedurally drawn, parallax arenas. Every stage shares the same template:
## far layer (slow parallax), mid layer, and a floor at FLOOR_Y. The central
## play lane is kept clear so fighters stay readable.

const FLOOR_Y := 322.0
const W := 640.0
const STAGE_W := 1000.0

var stage_id := "star_labs"
var cam_left := 180.0
var t := 0.0
var dim := 0.0
var glitch := false
var preview := false
var _seed := 0


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func px(p: float) -> float:
	return cam_left * (1.0 - p)


func R(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


func grad(x: float, y: float, w: float, h: float, top: Color, bot: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]),
		PackedColorArray([top, top, bot, bot]))


func txt(x: float, y: float, s: String, size: int, c: Color) -> void:
	draw_string(Game.font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func hsh(i: int) -> float:
	# Deterministic pseudo-random in [0,1) per index, stable between frames.
	var x := sin(float(i) * 12.9898 + 78.233) * 43758.5453
	return x - floorf(x)


func _draw() -> void:
	var sx := cam_left
	match stage_id:
		"star_labs": _star_labs(sx)
		"ccpd": _ccpd(sx)
		"arrow_bunker": _bunker(sx)
		"waverider": _waverider(sx)
		"deo": _deo(sx)
		"central_city": _central(sx)
		"star_city": _star_city(sx)
		"national_city": _national(sx)
		"apocalypse": _apocalypse(sx)
		"earth_x": _earth_x(sx)
		"freak_studio": _studio(sx)
		_: _star_labs(sx)
	if glitch and not preview:
		_glitch(sx)
	if dim > 0.0:
		R(sx - 4, -4, W + 8, 370, Color(0, 0, 0.02, dim))


# --- Shared pieces --------------------------------------------------------------------

func _floor(sx: float, top: Color, bot: Color, line: Color, spacing: float, shine: float) -> void:
	grad(sx - 10, FLOOR_Y, W + 20, 60, top, bot)
	R(sx - 10, FLOOR_Y, W + 20, 2, line.lightened(0.2))
	var start := floorf((sx - 10) / spacing) * spacing
	var x := start
	while x < sx + W + 20:
		draw_line(Vector2(x, FLOOR_Y + 2), Vector2(x + (x - sx - W * 0.5) * 0.35, 362), line, 1.0)
		x += spacing
	for i in 3:
		R(sx - 10, FLOOR_Y + 8 + i * 12 + i * i * 2, W + 20, 1, line)
	if shine > 0.0:
		for i in 6:
			var rx := sx + fmod(i * 131.0 - sx * 0.2, W)
			R(rx, FLOOR_Y + 6, 34, 30, Color(1, 1, 1, shine * 0.25))


func _window_grid(x: float, y: float, w: float, h: float, cols: int, rows: int, lit: Color, dark: Color, seed_i: int) -> void:
	var cw := w / cols
	var ch := h / rows
	for cx in cols:
		for cy in rows:
			var on := hsh(seed_i + cx * 31 + cy * 7) > 0.45
			R(x + cx * cw + 1, y + cy * ch + 1, cw - 2, ch - 2, lit if on else dark)


func _glitch(sx: float) -> void:
	var slot := int(t * 6.0)
	if hsh(slot) > 0.72:
		for i in 3:
			var y := hsh(slot * 3 + i) * 300.0
			var h := 2.0 + hsh(slot * 5 + i) * 8.0
			var c: Color = [Color(1, 0, 0.4, 0.35), Color(0, 1, 0.9, 0.3), Color(1, 1, 1, 0.2)][i]
			R(sx + hsh(slot + i) * 40.0 - 20.0, y, W, h, c)


func _lamp_cone(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(x - 4, y), Vector2(x + 4, y), Vector2(x + w * 0.5, y + h), Vector2(x - w * 0.5, y + h)]), c)


# --- 1. S.T.A.R. Labs ---------------------------------------------------------------------

func _star_labs(sx: float) -> void:
	grad(sx, 0, W, 360, Color("0a1430"), Color("14284e"))
	var o := px(0.25)
	# Accelerator ring overhead.
	draw_arc(Vector2(o + 500, -260), 420, 0.15 * PI, 0.85 * PI, 48, Color("1d3a6e"), 26.0)
	draw_arc(Vector2(o + 500, -260), 420, 0.15 * PI, 0.85 * PI, 48, Color("3d74c8"), 3.0)
	# Glass wall panels.
	for i in 12:
		var x := o + i * 74.0 - 20.0
		R(x, 40, 70, 210, Color(0.35, 0.6, 1.0, 0.08))
		R(x, 40, 2, 210, Color("2c4f8a"))
		R(x, 40, 70, 3, Color("2c4f8a"))
		R(x + 6, 50, 20, 120, Color(0.7, 0.9, 1.0, 0.05))
	txt(o + 330, 78, "S.T.A.R. LABS", 22, Color("6fa8ff"))
	R(o + 330, 84, 168, 2, Color("6fa8ff"))
	# Mid layer: monitors and consoles.
	var m := px(0.6)
	for i in 8:
		var x2 := m + i * 120.0
		R(x2, 200, 64, 40, Color("0b1020"))
		R(x2 + 3, 203, 58, 34, Color("123a72"))
		for b in 6:
			var bh := 6.0 + 20.0 * absf(sin(t * 2.0 + i + b * 0.7))
			R(x2 + 6 + b * 9, 233 - bh, 6, bh, Color("4fc3ff"))
		R(x2 - 10, 250, 90, 52, Color("1a2338"))
		R(x2 - 10, 250, 90, 4, Color("33476e"))
		R(x2 + 4, 262, 10, 4, Color(0.3, 1.0, 0.6) if int(t * 3 + i) % 2 == 0 else Color(0.1, 0.4, 0.2))
	# Equipment cylinder with arcing electricity.
	var cx := m + 420.0
	R(cx, 150, 30, 150, Color("26334f"))
	R(cx + 4, 150, 6, 150, Color("41567f"))
	if fmod(t, 2.3) < 0.25:
		var pts := PackedVector2Array()
		for k in 6:
			pts.append(Vector2(cx + 15 + (hsh(int(t * 30) + k) - 0.5) * 24, 150 - k * 12))
		draw_polyline(pts, Color(0.7, 0.9, 1.0), 2.0)
	_floor(sx, Color("1b2c52"), Color("0a1226"), Color("2a4072"), 80, 0.5)


# --- 2. CCPD ---------------------------------------------------------------------------------

func _ccpd(sx: float) -> void:
	grad(sx, 0, W, 360, Color("3b2d22"), Color("251c15"))
	var o := px(0.25)
	for i in 6:
		var x := o + i * 130.0
		R(x, 30, 100, 110, Color("0e1424"))
		_window_grid(x + 6, 40, 88, 90, 6, 5, Color("e8c060"), Color("1b2234"), i * 17)
		R(x - 4, 26, 108, 6, Color("5a4634"))
		R(x + 48, 30, 4, 110, Color("5a4634"))
	txt(o + 290, 170, "CENTRAL CITY POLICE DEPT.", 12, Color("c8a878"))
	# Evidence board.
	var m := px(0.6)
	R(m + 300, 170, 120, 70, Color("8a6038"))
	R(m + 304, 174, 112, 62, Color("b0844c"))
	for k in 6:
		R(m + 310 + (k % 3) * 34, 180 + (k / 3) * 28, 22, 18, Color("ece4d0"))
	draw_line(Vector2(m + 321, 189), Vector2(m + 389, 217), Color(0.8, 0.1, 0.1), 1.0)
	draw_line(Vector2(m + 355, 189), Vector2(m + 321, 217), Color(0.8, 0.1, 0.1), 1.0)
	# Desks.
	for i in 6:
		var x2 := m + i * 170.0 - 40.0
		R(x2, 262, 110, 40, Color("4a3424"))
		R(x2, 262, 110, 5, Color("6a4c34"))
		R(x2 + 14, 236, 34, 26, Color("15181e"))
		R(x2 + 17, 239, 28, 18, Color("3a6a8a") if int(t + i) % 3 else Color("4a8aaa"))
		R(x2 + 70, 246, 4, 16, Color("2a2a2a"))
		draw_colored_polygon(PackedVector2Array([Vector2(x2 + 64, 246), Vector2(x2 + 82, 246), Vector2(x2 + 76, 238)]), Color("d0b060"))
	# Emergency lights.
	var phase := int(t * 4.0) % 2
	for side in 2:
		var lx := sx + 30 + side * 580
		var col := Color(1, 0.1, 0.1, 0.8) if (phase + side) % 2 == 0 else Color(0.1, 0.3, 1, 0.8)
		R(lx - 8, 8, 16, 8, col)
		_lamp_cone(lx, 16, 140, 120, Color(col.r, col.g, col.b, 0.08))
	_floor(sx, Color("4e3e30"), Color("241a12"), Color("3a2c20"), 60, 0.15)


# --- 3. Arrow Bunker --------------------------------------------------------------------------

func _bunker(sx: float) -> void:
	grad(sx, 0, W, 360, Color("141a16"), Color("0c100e"))
	var o := px(0.25)
	for i in 8:
		var x := o + i * 110.0
		R(x, 0, 18, 330, Color("1e2620"))
		R(x + 3, 0, 4, 330, Color("2a342c"))
	# Computer array with green glow.
	var cx := o + 300.0
	R(cx - 6, 120, 200, 90, Color("080c0a"))
	for k in 3:
		R(cx + k * 64, 126, 60, 40, Color("0c2a14"))
		for ln in 5:
			var w := 20.0 + 30.0 * hsh(int(t * 2) + k * 9 + ln)
			R(cx + k * 64 + 4, 130 + ln * 7, w, 2, Color("3cff6a"))
	draw_circle(Vector2(cx + 94, 190), 70, Color(0.2, 1.0, 0.4, 0.04))
	# Weapon wall: bows on racks.
	var m := px(0.55)
	R(m + 40, 150, 150, 90, Color("1a1e1c"))
	for k in 4:
		var bx := m + 60 + k * 34
		draw_arc(Vector2(bx, 195), 34, -PI * 0.42, PI * 0.42, 10, Color("3a6a3a"), 3.0)
		draw_line(Vector2(bx + 34 * cos(-PI * 0.42), 195 + 34 * sin(-PI * 0.42)), Vector2(bx + 34 * cos(PI * 0.42), 195 + 34 * sin(PI * 0.42)), Color("8a8a7a"), 1.0)
	# Salmon ladder.
	var lx := m + 640.0
	R(lx, 110, 8, 190, Color("2a2e2c"))
	R(lx + 90, 110, 8, 190, Color("2a2e2c"))
	for k in 6:
		R(lx + 4, 120 + k * 26, 90, 4, Color("6a6e6a"))
	# Hanging lamps.
	for k in 4:
		var hx := px(0.8) + k * 240.0 + 60.0
		draw_line(Vector2(hx, 0), Vector2(hx, 40), Color("2a2e2c"), 2.0)
		R(hx - 10, 40, 20, 6, Color("3a3e3a"))
		_lamp_cone(hx, 46, 150, 276, Color(0.9, 1.0, 0.8, 0.045))
	_floor(sx, Color("2a302c"), Color("0e1210"), Color("1c221e"), 40, 0.1)


# --- 4. Waverider ------------------------------------------------------------------------------

func _waverider(sx: float) -> void:
	R(sx, 0, W, 360, Color("06070e"))
	# Starfield through the curved window (slow parallax + drift).
	var o := px(0.1)
	for i in 90:
		var x := fmod(hsh(i) * 900.0 + o - t * (8.0 + 20.0 * hsh(i + 5)), 900.0) + sx - 130.0
		var y := 30.0 + hsh(i + 99) * 210.0
		var b := 0.4 + 0.6 * hsh(i + 7)
		R(x, y, 1 + int(hsh(i + 3) * 2), 1, Color(b, b, 1.0))
	draw_circle(Vector2(o + 420, 120), 50, Color(0.5, 0.2, 0.6, 0.15))
	draw_circle(Vector2(o + 460, 140), 34, Color(0.2, 0.4, 0.8, 0.12))
	# Window frame: curved hull.
	var m := px(0.45)
	draw_colored_polygon(PackedVector2Array([Vector2(sx - 10, 0), Vector2(sx + W + 10, 0), Vector2(sx + W + 10, 34), Vector2(sx - 10, 34)]), Color("2a2620"))
	for i in 9:
		var x2 := m + i * 110.0
		draw_colored_polygon(PackedVector2Array([Vector2(x2, 30), Vector2(x2 + 14, 30), Vector2(x2 + 24, 250), Vector2(x2 + 10, 250)]), Color("3a3428"))
		draw_line(Vector2(x2 + 7, 30), Vector2(x2 + 17, 250), Color("c8902c"), 1.0)
	R(sx - 10, 240, W + 20, 20, Color("2e2a22"))
	R(sx - 10, 240, W + 20, 2, Color("e0a030"))
	# Consoles.
	for i in 7:
		var c := px(0.7) + i * 150.0
		draw_colored_polygon(PackedVector2Array([Vector2(c, 302), Vector2(c + 80, 302), Vector2(c + 70, 268), Vector2(c + 10, 268)]), Color("3a3630"))
		R(c + 14, 272, 52, 8, Color(1.0, 0.6, 0.15, 0.6 + 0.4 * sin(t * 3 + i)))
		R(c + 18, 284, 8, 4, Color("40c0ff"))
		R(c + 34, 284, 8, 4, Color("ff5040") if int(t * 2 + i) % 2 else Color("401010"))
	_floor(sx, Color("3a3a3e"), Color("16161a"), Color("5a4a2a"), 70, 0.2)


# --- 5. D.E.O. ----------------------------------------------------------------------------------

func _deo(sx: float) -> void:
	grad(sx, 0, W, 360, Color("d8e8f8"), Color("8fb0d0"))
	var o := px(0.25)
	for i in 10:
		var x := o + i * 90.0
		R(x, 20, 80, 190, Color(1, 1, 1, 0.35))
		R(x, 20, 3, 190, Color("6a8aac"))
		R(x + 10, 30, 60, 4, Color(1, 1, 1, 0.7))
	# Insignia (original design: ringed globe).
	draw_circle(Vector2(o + 420, 110), 42, Color("1c3a6a"))
	draw_arc(Vector2(o + 420, 110), 36, 0, TAU, 32, Color("e8eef8"), 3.0)
	draw_arc(Vector2(o + 420, 110), 22, 0, TAU, 24, Color("8fc0ff"), 2.0)
	draw_line(Vector2(o + 384, 110), Vector2(o + 456, 110), Color("e8eef8"), 2.0)
	txt(o + 396, 168, "D.E.O.", 16, Color("1c3a6a"))
	# Secure door with hazard stripes.
	var m := px(0.6)
	R(m + 120, 150, 90, 152, Color("4a5a6e"))
	R(m + 126, 156, 78, 140, Color("6a7a90"))
	for k in 8:
		draw_colored_polygon(PackedVector2Array([Vector2(m + 120 + k * 12, 296), Vector2(m + 128 + k * 12, 296), Vector2(m + 136 + k * 12, 302), Vector2(m + 128 + k * 12, 302)]), Color("e0c020"))
	R(m + 196, 210, 6, 10, Color(0.2, 1, 0.3) if fmod(t, 1.2) < 0.6 else Color(0.1, 0.3, 0.1))
	# Balcony railing and monitors.
	R(sx - 10, 236, W + 20, 4, Color("e8f0fa"))
	for i in 12:
		R(px(0.75) + i * 70.0, 236, 3, 40, Color("c8d8ea"))
	for i in 5:
		var x3 := m + 400 + i * 120.0
		R(x3, 180, 70, 44, Color("0c1424"))
		R(x3 + 3, 183, 64, 38, Color("1e4a8a"))
		draw_arc(Vector2(x3 + 35, 202), 12, 0, TAU, 16, Color("7fd0ff"), 1.0)
		draw_line(Vector2(x3 + 35, 202), Vector2(x3 + 35 + 12 * cos(t * 2 + i), 202 + 12 * sin(t * 2 + i)), Color("7fd0ff"), 1.0)
	_floor(sx, Color("e8eef6"), Color("98a8bc"), Color("b8c8da"), 90, 0.6)


# --- 6. Central City Street ---------------------------------------------------------------------

func _central(sx: float) -> void:
	grad(sx, 0, W, 360, Color("120c2a"), Color("2c1e4a"))
	var o := px(0.15)
	for i in 14:
		var x := o + i * 64.0 - 30.0
		var h := 120.0 + hsh(i) * 120.0
		R(x, 260 - h, 58, h, Color("1a1430"))
		_window_grid(x + 4, 266 - h, 50, h - 12, 4, int(h / 14), Color(1, 0.85, 0.45, 0.8), Color("221a3a"), i * 13)
	# Storefronts.
	var m := px(0.6)
	var names := ["JOLT COFFEE", "CENTRAL CITY", "BOOKS", "PIZZA"]
	for i in 7:
		var x2 := m + i * 150.0 - 40.0
		R(x2, 170, 140, 132, Color("3a2a44"))
		R(x2 + 8, 210, 124, 70, Color(1, 0.8, 0.5, 0.25))
		R(x2 + 8, 210, 124, 2, Color("6a5a7a"))
		var sign_col: Color = [Color("ff5aa0"), Color("ffd040"), Color("60e0ff"), Color("ff8040")][i % 4]
		var flick := 0.6 if hsh(int(t * 8) + i) > 0.93 else 1.0
		R(x2 + 10, 182, 120, 20, Color("140c1c"))
		txt(x2 + 16, 197, names[i % 4], 11, Color(sign_col.r, sign_col.g, sign_col.b, flick))
	# Traffic light.
	var tl := px(0.8) + 520.0
	R(tl, 150, 5, 150, Color("1a1a1e"))
	R(tl - 6, 150, 17, 42, Color("1a1a1e"))
	var cyc := int(t / 2.0) % 3
	for k in 3:
		var lc: Color = [Color(1, 0.15, 0.1), Color(1, 0.8, 0.1), Color(0.1, 1, 0.4)][k]
		draw_circle(Vector2(tl + 2.5, 158 + k * 12), 4, lc if k == cyc else lc.darkened(0.75))
	# Street lamps.
	for k in 4:
		var lx := px(0.8) + k * 260.0 + 80.0
		R(lx, 160, 4, 142, Color("2a2a34"))
		R(lx - 12, 156, 20, 6, Color("2a2a34"))
		draw_circle(Vector2(lx - 8, 163), 4, Color("fff0b0"))
		_lamp_cone(lx - 8, 165, 120, 157, Color(1, 0.9, 0.6, 0.06))
	# Wet street with reflections.
	grad(sx - 10, FLOOR_Y, W + 20, 60, Color("2a2438"), Color("100c18"))
	R(sx - 10, FLOOR_Y, W + 20, 2, Color("5a5070"))
	for i in 10:
		var rx := px(0.6) + i * 110.0
		var c: Color = [Color(1, 0.35, 0.6, 0.18), Color(1, 0.8, 0.3, 0.18), Color(0.4, 0.9, 1, 0.18)][i % 3]
		R(rx, FLOOR_Y + 3, 18, 30 + 8 * sin(t * 2 + i), c)
	for k in 8:
		R(sx + fmod(k * 100.0 - sx, W), FLOOR_Y + 26, 40, 3, Color(0.9, 0.9, 0.7, 0.4))


# --- 7. Star City Street --------------------------------------------------------------------------

func _star_city(sx: float) -> void:
	grad(sx, 0, W, 360, Color("06100e"), Color("12261e"))
	var o := px(0.15)
	for i in 12:
		var x := o + i * 76.0 - 30.0
		var h := 140.0 + hsh(i + 40) * 100.0
		R(x, 250 - h, 70, h, Color("0c1814"))
		_window_grid(x + 5, 256 - h, 60, h - 14, 5, int(h / 16), Color(0.75, 0.9, 0.5, 0.5), Color("101e18"), i * 19)
		if hsh(i) > 0.6:
			R(x + 20, 230 - h, 26, 20, Color("1a2a22"))
			R(x + 24, 250 - h, 4, 10, Color("1a2a22"))
			R(x + 38, 250 - h, 4, 10, Color("1a2a22"))
	# Alley walls with fire escapes and neon.
	var m := px(0.6)
	for i in 5:
		var x2 := m + i * 220.0 - 60.0
		R(x2, 110, 130, 192, Color("1e2420"))
		for f in 3:
			R(x2 + 10, 140 + f * 50, 80, 3, Color("3a403a"))
			for b in 8:
				R(x2 + 12 + b * 10, 128 + f * 50, 1, 12, Color("3a403a"))
		var neon := Color("60ff70") if i % 2 == 0 else Color("ffb040")
		var on := hsh(int(t * 10) + i * 3) > 0.08
		R(x2 + 96, 150, 26, 60, Color("0c100e"))
		if on:
			draw_rect(Rect2(x2 + 98, 152, 22, 56), neon, false, 2.0)
			txt(x2 + 102, 186, "BAR" if i % 2 == 0 else "24H", 9, neon)
	# Steam vent.
	var vx := px(0.85) + 500.0
	R(vx, 296, 30, 6, Color("2a2e2a"))
	for k in 5:
		var ph := fmod(t * 0.8 + k * 0.2, 1.0)
		draw_circle(Vector2(vx + 15 + sin(ph * 6 + k) * 6, 296 - ph * 90), 6 + ph * 12, Color(0.8, 0.85, 0.8, 0.12 * (1.0 - ph)))
	# Drizzle.
	for i in 70:
		var rx := sx + fmod(hsh(i) * W + t * 40.0, W)
		var ry := fmod(hsh(i + 50) * 360.0 + t * 380.0, 360.0)
		draw_line(Vector2(rx, ry), Vector2(rx - 2, ry + 8), Color(0.6, 0.8, 0.7, 0.25), 1.0)
	_floor(sx, Color("1e2622"), Color("0a0e0c"), Color("2a342e"), 70, 0.2)


# --- 8. National City Street --------------------------------------------------------------------------

func _national(sx: float) -> void:
	grad(sx, 0, W, 200, Color("2a3a7a"), Color("f0906a"))
	grad(sx, 200, W, 160, Color("f0906a"), Color("ffc890"))
	var o := px(0.12)
	draw_circle(Vector2(o + 160, 190), 30, Color(1, 0.85, 0.6, 0.8))
	for i in 12:
		var x := o + i * 74.0 - 20.0
		var h := 120.0 + hsh(i + 77) * 150.0
		grad(x, 270 - h, 64, h, Color("6a7aa8"), Color("3a3a6a"))
		for k in int(h / 12):
			R(x + 4, 274 - h + k * 12, 56, 2, Color(1, 0.8, 0.6, 0.25))
	# Landmark tower with glowing crown (original design).
	var tx := o + 470.0
	grad(tx, 40, 54, 230, Color("8a9ac8"), Color("4a4a7a"))
	draw_colored_polygon(PackedVector2Array([Vector2(tx, 40), Vector2(tx + 54, 40), Vector2(tx + 27, 10)]), Color("9aaad8"))
	draw_circle(Vector2(tx + 27, 34), 6, Color(1, 0.95, 0.7, 0.6 + 0.4 * sin(t * 2)))
	# Elevated train track and train.
	var m := px(0.55)
	R(sx - 10, 196, W + 20, 8, Color("3a3040"))
	for i in 10:
		R(m + i * 120.0, 204, 10, 98, Color("3a3040"))
	var trx := fmod(t * 160.0, 2200.0) - 600.0 + sx
	if trx > sx - 400 and trx < sx + W + 50:
		R(trx, 170, 360, 26, Color("d8dce8"))
		for k in 12:
			R(trx + 8 + k * 29, 176, 20, 9, Color("4a5a8a"))
		R(trx, 190, 360, 3, Color("c84040"))
	# Plaza planters.
	for i in 5:
		var x3 := px(0.8) + i * 230.0
		R(x3, 280, 60, 22, Color("8a7a6a"))
		draw_circle(Vector2(x3 + 18, 276), 12, Color("4a8a4a"))
		draw_circle(Vector2(x3 + 40, 274), 14, Color("3a7a40"))
	_floor(sx, Color("d8c0a8"), Color("8a7060"), Color("b8a088"), 64, 0.3)


# --- 9. Future Apocalypse ---------------------------------------------------------------------------

func _apocalypse(sx: float) -> void:
	grad(sx, 0, W, 360, Color("2a0e06"), Color("c8501a"))
	var o := px(0.12)
	for i in 4:
		var cx := o + 100.0 + i * 190.0
		for k in 6:
			var ph := fmod(t * 0.1 + k * 0.17 + i * 0.3, 1.0)
			draw_circle(Vector2(cx + sin(ph * 5 + i) * 20, 240 - ph * 240), 20 + ph * 40, Color(0.12, 0.06, 0.05, 0.35 * (1.0 - ph)))
	for i in 14:
		var x := o + i * 64.0 - 30.0
		var h := 80.0 + hsh(i + 120) * 130.0
		var pts := PackedVector2Array([Vector2(x, 270), Vector2(x, 270 - h), Vector2(x + 18, 270 - h + 14), Vector2(x + 30, 270 - h - 10), Vector2(x + 46, 270 - h + 24), Vector2(x + 60, 270 - h + 6), Vector2(x + 60, 270)])
		draw_colored_polygon(pts, Color("1a0a08"))
		for k in 3:
			if hsh(i * 3 + k) > 0.6:
				R(x + 8 + k * 16, 270 - h + 40 + k * 20, 6, 8, Color(1, 0.5, 0.1, 0.4 + 0.3 * sin(t * 5 + i)))
	# Fires along the mid ground.
	var m := px(0.6)
	for i in 8:
		var fx := m + i * 140.0
		R(fx - 30, 280, 70, 22, Color("2a1410"))
		for k in 4:
			var fh := 14.0 + 12.0 * absf(sin(t * 7 + i + k * 1.7))
			draw_colored_polygon(PackedVector2Array([Vector2(fx - 16 + k * 10, 282), Vector2(fx - 8 + k * 10, 282), Vector2(fx - 12 + k * 10, 282 - fh)]), Color(1, 0.55 + 0.2 * k / 4.0, 0.1, 0.85))
	# Wrecked car.
	var cx2 := px(0.8) + 600.0
	draw_colored_polygon(PackedVector2Array([Vector2(cx2, 302), Vector2(cx2 + 110, 302), Vector2(cx2 + 100, 280), Vector2(cx2 + 70, 266), Vector2(cx2 + 30, 270), Vector2(cx2 + 6, 284)]), Color("241410"))
	draw_circle(Vector2(cx2 + 24, 302), 9, Color("100806"))
	# Embers.
	for i in 40:
		var ex := sx + fmod(hsh(i) * W + sin(t + i) * 20.0, W)
		var ey := 340.0 - fmod(hsh(i + 9) * 360.0 + t * (20 + 30 * hsh(i + 2)), 360.0)
		R(ex, ey, 2, 2, Color(1, 0.6, 0.2, 0.8))
	_floor(sx, Color("4a2418"), Color("1a0a06"), Color("3a1a10"), 50, 0.0)


# --- 10. Earth-X ------------------------------------------------------------------------------------

func _earth_x(sx: float) -> void:
	grad(sx, 0, W, 360, Color("0a0406"), Color("3a0a0e"))
	var o := px(0.1)
	# Searchlights.
	for i in 3:
		var bx := o + 120.0 + i * 220.0
		var ang := sin(t * 0.6 + i * 2.0) * 0.5 - PI * 0.5
		var tip := Vector2(bx, 260) + Vector2(cos(ang), sin(ang)) * 320.0
		var side := Vector2(-sin(ang), cos(ang)) * 40.0
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 3, 260), Vector2(bx + 3, 260), tip + side, tip - side]), Color(1, 0.95, 0.8, 0.07))
	# Airship silhouette.
	draw_set_transform(Vector2(o + 300 + sin(t * 0.2) * 30, 60), 0.0, Vector2(1, 0.32))
	draw_circle(Vector2.ZERO, 70, Color("1a0a0c"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Brutalist buildings with banners (original emblem: X in a ring).
	var m := px(0.45)
	for i in 7:
		var x := m + i * 150.0 - 50.0
		R(x, 90, 120, 212, Color("1e1416"))
		R(x + 10, 100, 100, 6, Color("2e2224"))
		R(x + 38, 120, 44, 120, Color("8a0c12"))
		draw_circle(Vector2(x + 60, 160), 14, Color("120a0a"))
		draw_arc(Vector2(x + 60, 160), 14, 0, TAU, 20, Color("e8e0d8"), 2.0)
		draw_line(Vector2(x + 52, 152), Vector2(x + 68, 168), Color("e8e0d8"), 2.0)
		draw_line(Vector2(x + 68, 152), Vector2(x + 52, 168), Color("e8e0d8"), 2.0)
		for k in 4:
			R(x + 14, 250 + k * 12, 20, 6, Color(1, 0.7, 0.4, 0.3) if hsh(i + k) > 0.5 else Color("2a1a1c"))
	# Barricades.
	for i in 4:
		var bx2 := px(0.8) + i * 280.0 + 40.0
		R(bx2, 284, 70, 18, Color("3a3032"))
		for k in 5:
			draw_line(Vector2(bx2 + k * 14, 284), Vector2(bx2 + k * 14 + 10, 302), Color("c8a020"), 2.0)
	_floor(sx, Color("2e2224"), Color("0e0808"), Color("3e2a2c"), 56, 0.05)


# --- Boss: Freak's Studio ---------------------------------------------------------------------------

func _studio(sx: float) -> void:
	R(sx, 0, W, 360, Color("0a0610"))
	var o := px(0.2)
	# Curtains.
	for i in 18:
		var x := o + i * 46.0 - 40.0
		grad(x, 0, 23, 300, Color("4a1a6a"), Color("1e0a2a"))
		grad(x + 23, 0, 23, 300, Color("2e0e44"), Color("12061a"))
	# Wall of TVs.
	var m := px(0.45)
	for cx in 7:
		for cy in 3:
			var x2 := m + 100.0 + cx * 70.0
			var y2 := 82.0 + cy * 50.0
			R(x2, y2, 62, 46, Color("1a1a1e"))
			var mode_i := int(hsh(cx * 7 + cy + int(t * 2)) * 4)
			match mode_i:
				0:
					for ln in 10:
						var g := hsh(int(t * 30) + ln + cx * 11 + cy)
						R(x2 + 4, y2 + 4 + ln * 4, 54, 2, Color(g, g, g))
				1:
					var bars := [Color(1, 1, 1), Color(1, 1, 0), Color(0, 1, 1), Color(0, 1, 0), Color(1, 0, 1), Color(1, 0, 0), Color(0, 0, 1)]
					for b in 7:
						R(x2 + 4 + b * 8, y2 + 4, 8, 38, bars[b])
				2:
					R(x2 + 4, y2 + 4, 54, 38, Color("40ffb0"))
					txt(x2 + 10, y2 + 28, "FREAK", 10, Color("0a3020"))
				_:
					R(x2 + 4, y2 + 4, 54, 38, Color("20104a"))
					draw_circle(Vector2(x2 + 31, y2 + 23), 10, Color("ff60c0"))
	# ON AIR sign.
	var on := fmod(t, 1.0) < 0.75
	R(m + 300, 56, 70, 20, Color("1a0606"))
	txt(m + 308, 71, "ON AIR", 12, Color(1, 0.15, 0.15) if on else Color(0.3, 0.05, 0.05))
	# Stage lights.
	for k in 4:
		var lx := px(0.8) + k * 260.0 + 30.0
		R(lx - 8, 0, 16, 10, Color("2a2a2e"))
		var lc: Color = [Color(1, 0.3, 0.8, 0.07), Color(0.3, 1, 0.8, 0.07), Color(1, 1, 0.5, 0.07), Color(0.5, 0.5, 1, 0.07)][k]
		_lamp_cone(lx, 10, 160, 312, lc)
	# Checkered stage floor.
	R(sx - 10, FLOOR_Y, W + 20, 60, Color("16101e"))
	var startx := floorf((sx - 10) / 32.0) * 32.0
	var x3 := startx
	var idx := 0
	while x3 < sx + W + 20:
		for row in 3:
			if (idx + row) % 2 == 0:
				R(x3, FLOOR_Y + row * 13, 32, 13, Color("2a1e3a"))
		x3 += 32.0
		idx += 1
	R(sx - 10, FLOOR_Y, W + 20, 2, Color("ff60c0"))
