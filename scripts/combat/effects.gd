extends Node2D
## Lightweight pixel particle system: hit sparks, block sparks, dust, rings,
## explosions, teleport breaches, floating text and power effects.

var parts: Array = []
var reduce_flash := false


func add(p: Dictionary) -> void:
	p["age"] = 0
	parts.append(p)


func spark(at: Vector2, scale: float, col: Color) -> void:
	var n := int(6 + scale * 4)
	for i in n:
		var a := randf() * TAU
		var sp := (2.0 + randf() * 4.0) * scale
		add({"t": "line", "p": at, "v": Vector2(cos(a), sin(a)) * sp, "life": 10 + randi() % 6, "c": col, "w": 2.0})
	add({"t": "star", "p": at, "life": 6, "c": Color(1, 1, 1), "r": 10.0 * scale})
	add({"t": "ring", "p": at, "life": 10, "c": col, "r": 4.0, "grow": 2.5 * scale})


func block_spark(at: Vector2) -> void:
	for i in 6:
		var a := randf() * TAU
		add({"t": "line", "p": at, "v": Vector2(cos(a), sin(a)) * 3.0, "life": 8, "c": Color(0.5, 0.8, 1.0), "w": 1.5})
	add({"t": "ring", "p": at, "life": 8, "c": Color(0.6, 0.85, 1.0), "r": 6.0, "grow": 1.5})


func dust(at: Vector2, scale: float) -> void:
	for i in int(4 * scale) + 2:
		var dir := -1.0 if i % 2 == 0 else 1.0
		add({"t": "puff", "p": at + Vector2(dir * randf() * 8, -2), "v": Vector2(dir * (0.5 + randf() * 1.5) * scale, -0.3 - randf() * 0.5), "life": 18, "c": Color(0.75, 0.7, 0.62, 0.7), "r": 3.0 + randf() * 3.0 * scale})


func explosion(at: Vector2, radius: float, col: Color) -> void:
	add({"t": "disc", "p": at, "life": 10, "c": Color(1, 0.95, 0.7), "r": radius * 0.5, "grow": radius * 0.06})
	add({"t": "ring", "p": at, "life": 16, "c": col, "r": radius * 0.4, "grow": radius * 0.06})
	for i in 10:
		var a := randf() * TAU
		add({"t": "puff", "p": at, "v": Vector2(cos(a), sin(a)) * (1.0 + randf() * 2.5), "life": 22, "c": Color(0.35, 0.3, 0.3, 0.8), "r": 4.0 + randf() * 4.0})


func breach(at: Vector2, col: Color) -> void:
	add({"t": "breach", "p": at, "life": 18, "c": col, "r": 26.0})


func text(at: Vector2, s: String, col: Color) -> void:
	add({"t": "text", "p": at, "v": Vector2(0, -0.6), "life": 50, "c": col, "s": s})


func shockring(at: Vector2, col: Color, r: float, grow: float, life: int) -> void:
	add({"t": "ring", "p": at, "life": life, "c": col, "r": r, "grow": grow})


func beam(from: Vector2, to: Vector2, col: Color, width: float, life: int) -> void:
	add({"t": "beam", "p": from, "q": to, "life": life, "c": col, "w": width})


func step() -> void:
	for p in parts:
		p["age"] += 1
		if p.has("v"):
			p["p"] += p["v"]
			p["v"] *= 0.9
		if p.has("grow"):
			p["r"] += p["grow"]
	parts = parts.filter(func(p): return p["age"] < p["life"])
	queue_redraw()


func _draw() -> void:
	var font: Font = Game.font
	for p in parts:
		var k: float = 1.0 - float(p["age"]) / float(p["life"])
		var c: Color = p["c"]
		c.a *= k
		var at: Vector2 = p["p"]
		match p["t"]:
			"line":
				var v: Vector2 = p["v"]
				draw_line(at, at - v * 2.0, c, p["w"])
			"star":
				var r: float = p["r"] * k
				draw_line(at - Vector2(r, 0), at + Vector2(r, 0), c, 3.0)
				draw_line(at - Vector2(0, r), at + Vector2(0, r), c, 3.0)
				draw_line(at - Vector2(r, r) * 0.6, at + Vector2(r, r) * 0.6, c, 1.0)
				draw_line(at - Vector2(r, -r) * 0.6, at + Vector2(r, -r) * 0.6, c, 1.0)
			"ring":
				draw_arc(at, p["r"], 0, TAU, 20, c, 2.0)
			"disc":
				if not reduce_flash:
					draw_circle(at, p["r"], c)
			"puff":
				draw_circle(at, p["r"] * (0.6 + 0.4 * k), c)
			"breach":
				var r2: float = p["r"] * minf(1.0, float(p["age"]) / 5.0) * (0.5 + 0.5 * k)
				draw_set_transform(at, 0.0, Vector2(0.45, 1.0))
				draw_circle(Vector2.ZERO, r2 + 2, Color(c.r, c.g, c.b, 0.4 * k))
				draw_circle(Vector2.ZERO, r2 * 0.75, Color(0.02, 0.02, 0.08, 0.9 * k))
				draw_arc(Vector2.ZERO, r2, float(p["age"]) * 0.4, float(p["age"]) * 0.4 + PI * 1.5, 14, c, 2.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"beam":
				draw_line(at, p["q"], Color(c.r, c.g, c.b, c.a * 0.5), p["w"] + 6.0)
				draw_line(at, p["q"], c, p["w"])
				draw_line(at, p["q"], Color(1, 1, 1, c.a), maxf(1.0, p["w"] * 0.3))
			"text":
				var s: String = p["s"]
				var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				draw_string_outline(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, c.a))
				draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
