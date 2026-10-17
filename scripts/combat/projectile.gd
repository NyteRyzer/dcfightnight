extends Node2D
## A projectile spawned by a fighter's move. Data comes straight from the move's
## "projectile" block, so every field is tunable in the fighter JSON.

const FLOOR_Y := 322.0

var owner_fighter: Node2D = null
var data: Dictionary = {}
var kind := "bolt"
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var gravity := 0.0
var size := Vector2(20, 10)
var life := 180
var age := 0
var hits_left := 1
var interval := 4
var cooldown := 0
var color := Color.WHITE
var facing := 1
var alive := true
var delay := 0
var origin := Vector2.ZERO
var detonated := false


func setup(src: Node2D, d: Dictionary, start: Vector2, dir: int, col: Color) -> void:
	owner_fighter = src
	data = d
	kind = d.get("kind", "bolt")
	facing = dir
	pos = start
	origin = start
	vel = Vector2(float(d.get("speed", 8)) * dir, float(d.get("vy", 0)))
	gravity = float(d.get("gravity", 0.0))
	var s: Array = d.get("size", [20, 10])
	size = Vector2(float(s[0]), float(s[1]))
	life = int(d.get("life", 200))
	hits_left = int(d.get("hits", 1))
	interval = int(d.get("interval", 4))
	color = col
	if d.has("color"):
		color = Color.html(d["color"])
	z_index = 3


func rect() -> Rect2:
	return Rect2(pos - size * 0.5, size)


func attack() -> Dictionary:
	var a := data.duplicate()
	a["chip"] = data.get("chip", 0.2)
	return a


func can_hit() -> bool:
	return alive and delay <= 0 and cooldown <= 0 and hits_left > 0


func on_hit() -> void:
	hits_left -= 1
	cooldown = interval
	if hits_left <= 0:
		alive = false


func step() -> void:
	age += 1
	if delay > 0:
		delay -= 1
		return
	if cooldown > 0:
		cooldown -= 1
	vel.y += gravity
	pos += vel
	if data.get("ground", false):
		pos.y = FLOOR_Y - size.y * 0.5
	if pos.y + size.y * 0.5 >= FLOOR_Y and vel.y > 0 and not data.get("ground", false):
		pos.y = FLOOR_Y - size.y * 0.5
		alive = false
	if age > life:
		alive = false
	position = pos.round()
	queue_redraw()


func explodes() -> bool:
	return data.has("explode")


func _draw() -> void:
	if delay > 0:
		# Warning marker where a rain projectile will fall.
		if age % 6 < 3:
			draw_rect(Rect2(-6, FLOOR_Y - pos.y - 3, 12, 3), Color(color.r, color.g, color.b, 0.7))
		return
	var f := facing
	var t := float(age)
	match kind:
		"bolt":
			var pts := PackedVector2Array()
			for i in 7:
				var x := (-size.x * 0.5 + size.x * i / 6.0) * f
				pts.append(Vector2(x, (randf() - 0.5) * size.y))
			draw_polyline(pts, Color(1, 1, 1), 3.0)
			draw_polyline(pts, color, 1.5)
			draw_circle(Vector2(size.x * 0.5 * f, 0), 4, Color(1, 1, 0.8))
		"arrow_x", "arrow", "arrow_down":
			var dir := vel.normalized() if vel.length() > 0.1 else Vector2(f, 0)
			var tail := -dir * size.x * 0.5 if kind != "arrow_down" else -dir * size.y * 0.5
			var tip := -tail
			draw_line(tail, tip, Color(0.1, 0.08, 0.06), 3.0)
			draw_line(tail, tip, Color(0.55, 0.42, 0.25), 1.5)
			draw_colored_polygon(PackedVector2Array([tip + dir * 5, tip + Vector2(-dir.y, dir.x) * 3, tip - Vector2(-dir.y, dir.x) * 3]), Color(0.75, 0.78, 0.8))
			draw_line(tail, tail + dir * 5, Color(0.2, 0.7, 0.25), 3.0)
			if kind == "arrow_x":
				draw_circle(tip - dir * 4, 3.0 + sin(t * 0.8), Color(1.0, 0.5, 0.1))
		"beam":
			var length := minf(absf(pos.x - origin.x) + size.x * 0.5, 260.0)
			var back := Vector2(-length * f, -vel.y / maxf(1.0, absf(vel.x)) * length)
			draw_line(back, Vector2(size.x * 0.5 * f, 0), Color(1.0, 0.85, 0.6, 0.6), size.y + 4)
			draw_line(back, Vector2(size.x * 0.5 * f, 0), color, size.y)
			draw_line(back, Vector2(size.x * 0.5 * f, 0), Color(1, 1, 0.9), 2.0)
		"sonic":
			for i in 3:
				var r := size.y * 0.5 * (0.5 + 0.25 * i) + sin(t * 0.5 + i) * 2.0
				draw_arc(Vector2(-i * 9 * f, 0), r, -PI * 0.4 + (PI if f < 0 else 0.0), PI * 0.4 + (PI if f < 0 else 0.0), 10, Color(color.r, color.g, color.b, 0.9 - i * 0.25), 2.0)
		"vibe", "vibe_big":
			var r2 := size.y * 0.42
			for i in 3:
				draw_arc(Vector2.ZERO, r2 * (0.4 + 0.3 * i) + sin(t * 0.6 + i * 2) * 2.0, t * 0.2 * f + i, t * 0.2 * f + i + PI * 1.4, 12, Color(color.r, color.g, color.b, 0.95 - i * 0.2), 3.0 if kind == "vibe_big" else 2.0)
			draw_circle(Vector2.ZERO, r2 * 0.3, Color(0.85, 0.95, 1.0))
		"bullet":
			draw_line(Vector2(-size.x * 0.5 * f, 0), Vector2(size.x * 0.5 * f, 0), Color(1, 0.9, 0.5), 3.0)
			draw_line(Vector2(-size.x * 1.2 * f, 0), Vector2(-size.x * 0.5 * f, 0), Color(1, 0.8, 0.4, 0.4), 2.0)
		"flashbang":
			draw_circle(Vector2.ZERO, 5, Color(0.1, 0.1, 0.1))
			draw_circle(Vector2.ZERO, 3.5, Color(0.4, 0.42, 0.45))
			if age % 8 < 4:
				draw_circle(Vector2(0, -4), 1.5, Color(1, 0.2, 0.2))
		"psi":
			for i in 4:
				var a := t * 0.15 + i * PI * 0.5
				draw_circle(Vector2(cos(a), sin(a)) * size.y * 0.35, 4.0, Color(color.r, color.g, color.b, 0.8))
			draw_circle(Vector2.ZERO, 6, Color(1, 0.7, 0.5))
			draw_arc(Vector2.ZERO, size.y * 0.5, 0, TAU, 16, Color(color.r, color.g, color.b, 0.5), 1.5)
		"shockwave", "shockwave_big":
			var hgt := size.y
			for i in 4:
				var x2 := (-size.x * 0.5 + i * size.x / 4.0) * f
				var hh := hgt * (0.5 + 0.5 * absf(sin(t * 0.5 + i)))
				draw_colored_polygon(PackedVector2Array([Vector2(x2, size.y * 0.5), Vector2(x2 + 6 * f, size.y * 0.5 - hh), Vector2(x2 + 12 * f, size.y * 0.5)]), Color(0.55, 0.5, 0.45))
			draw_line(Vector2(-size.x * 0.5, size.y * 0.5 - 1), Vector2(size.x * 0.5, size.y * 0.5 - 1), Color(0.8, 0.9, 1.0), 2.0)
		"static", "pause":
			draw_rect(Rect2(-size * 0.5 - Vector2(2, 2), size + Vector2(4, 4)), Color(0.05, 0.05, 0.08))
			for y in range(int(size.y)):
				if y % 2 == 0:
					var g := randf()
					draw_line(Vector2(-size.x * 0.5, -size.y * 0.5 + y), Vector2(size.x * 0.5, -size.y * 0.5 + y), Color(g, g, g * 1.1, 0.9), 1.0)
			if kind == "pause":
				draw_rect(Rect2(-7, -8, 5, 16), Color(1, 1, 1))
				draw_rect(Rect2(2, -8, 5, 16), Color(1, 1, 1))
			else:
				draw_rect(Rect2(-size * 0.5, size), Color(color.r, color.g, color.b, 0.25))
		"tv":
			draw_rect(Rect2(-size * 0.5 - Vector2(1, 1), size + Vector2(2, 2)), Color(0.05, 0.04, 0.05))
			draw_rect(Rect2(-size * 0.5, size), Color(0.35, 0.25, 0.2))
			draw_rect(Rect2(-size * 0.5 + Vector2(3, 3), size - Vector2(10, 6)), Color(0.6 + randf() * 0.3, 0.9, 0.8))
			draw_line(Vector2(-4, -size.y * 0.5), Vector2(-9, -size.y * 0.5 - 7), Color(0.1, 0.1, 0.1), 1.0)
			draw_line(Vector2(4, -size.y * 0.5), Vector2(9, -size.y * 0.5 - 7), Color(0.1, 0.1, 0.1), 1.0)
		"remnant":
			for i in 4:
				var off := Vector2(-i * 12.0 * f, 0)
				var al := 0.7 - i * 0.16
				draw_rect(Rect2(off + Vector2(-8, -size.y * 0.5), Vector2(16, size.y * 0.75)), Color(0.95, 0.75, 0.1, al))
				draw_circle(off + Vector2(0, -size.y * 0.55), 7, Color(0.95, 0.75, 0.1, al))
				draw_line(off + Vector2(-6, -size.y * 0.2), off + Vector2(6, size.y * 0.1), Color(1, 0.15, 0.1, al), 2.0)
			draw_circle(Vector2(3 * f, -size.y * 0.57), 1.5, Color(1, 0.2, 0.1))
		"dagger":
			var dd := Vector2(f, 0).rotated(age * 0.0)
			draw_line(-dd * size.x * 0.5, dd * size.x * 0.5, Color(0.1, 0.08, 0.06), 4.0)
			draw_line(-dd * size.x * 0.1, dd * size.x * 0.5, Color(0.8, 0.82, 0.88), 2.0)
			draw_line(-dd * size.x * 0.5, -dd * size.x * 0.15, Color(0.45, 0.3, 0.15), 3.0)
			draw_line(-dd * size.x * 0.9, -dd * size.x * 0.5, Color(1, 0.6, 0.2, 0.4), 2.0)
		"meteor":
			draw_circle(Vector2(0, -size.y * 0.6), size.x * 0.45, Color(1, 0.55, 0.1, 0.35))
			draw_circle(Vector2.ZERO, size.x * 0.5, Color(0.25, 0.18, 0.15))
			draw_circle(Vector2(-3, -3), size.x * 0.32, Color(0.45, 0.32, 0.25))
			for i in 3:
				draw_circle(Vector2((randf() - 0.5) * size.x, -size.y * (0.6 + randf() * 0.5)), 3, Color(1, 0.7, 0.2, 0.7))
		"mine":
			draw_rect(Rect2(-size.x * 0.5 - 1, -size.y * 0.5 - 1, size.x + 2, size.y + 2), Color(0.03, 0.03, 0.04))
			draw_rect(Rect2(-size.x * 0.5, -size.y * 0.5, size.x, size.y), Color(0.3, 0.32, 0.3))
			draw_rect(Rect2(-size.x * 0.5, -size.y * 0.5, size.x, 2), Color(0.45, 0.48, 0.45))
			if age % 20 < 10:
				draw_circle(Vector2(0, -size.y * 0.5 - 1), 2, Color(1, 0.15, 0.1))
		_:
			draw_circle(Vector2.ZERO, size.y * 0.5, color)
	if data.get("amp", false) and age % 4 < 2:
		draw_arc(Vector2.ZERO, maxf(size.x, size.y) * 0.6, 0, TAU, 16, Color(1, 1, 1, 0.6), 1.0)
