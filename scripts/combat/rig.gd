extends RefCounted
## Procedural pixel-art fighter renderer (v2).
##
## Fighters are drawn from a pose (poses.gd) and a "look" (costume data from the
## fighter JSON). Every body part is a shaped polygon (tapered, muscled limbs,
## sculpted torso, profile head) with 3-tone banded shading from a fixed light,
## a dark outline, and costume layers on top: masks, hoods, hair, capes, coats,
## skirts, armor plates, belts, emblems, gloves, boots and weapons.
##
## Everything is built in LOCAL space (facing right, origin at the feet) and
## mirrored on output, and it renders at the 640x360 base resolution so the
## nearest-neighbour upscale keeps it crisp pixel art.

const Poses = preload("res://scripts/combat/poses.gd")
const OUTLINE := Color(0.05, 0.04, 0.08)
const WHITE := Color(1, 1, 1)
## Direction TOWARD the light in each fighter's local space: from above and
## slightly in front, so faces and chests read clearly whichever way they face.
const LIGHT := Vector2(0.34, -0.94)

# Limb width profiles in units of H (sampled shoulder->elbow etc.).
const UA := [0.088, 0.086, 0.072, 0.058]
const FA := [0.062, 0.068, 0.057, 0.044]
const TH := [0.118, 0.112, 0.094, 0.07]
const SN := [0.07, 0.078, 0.062, 0.046]

# --- Unit shapes (facing right, y down, in head radii) ------------------------------------
const HEAD := [Vector2(-0.62, 0.55), Vector2(-0.9, 0.1), Vector2(-0.95, -0.35), Vector2(-0.7, -0.82), Vector2(-0.25, -1.02),
	Vector2(0.25, -1.0), Vector2(0.62, -0.8), Vector2(0.82, -0.45), Vector2(0.86, -0.2), Vector2(0.98, 0.02), Vector2(0.88, 0.14),
	Vector2(0.9, 0.3), Vector2(0.84, 0.42), Vector2(0.8, 0.6), Vector2(0.55, 0.8), Vector2(0.2, 0.78), Vector2(-0.2, 0.66)]
const HAIR_SHORT := [Vector2(-0.95, 0.15), Vector2(-1.0, -0.4), Vector2(-0.75, -0.92), Vector2(-0.25, -1.12), Vector2(0.3, -1.08),
	Vector2(0.7, -0.85), Vector2(0.86, -0.5), Vector2(0.62, -0.58), Vector2(0.3, -0.68), Vector2(0.0, -0.62), Vector2(-0.25, -0.35),
	Vector2(-0.5, -0.05), Vector2(-0.6, 0.25)]
const HAIR_SLICK := [Vector2(-0.92, 0.05), Vector2(-0.98, -0.45), Vector2(-0.7, -0.9), Vector2(-0.2, -1.07), Vector2(0.35, -1.03),
	Vector2(0.72, -0.82), Vector2(0.8, -0.62), Vector2(0.4, -0.78), Vector2(-0.1, -0.75), Vector2(-0.45, -0.45), Vector2(-0.55, 0.0)]
const HAIR_LONG := [Vector2(-0.95, 0.2), Vector2(-1.02, -0.4), Vector2(-0.75, -0.95), Vector2(-0.2, -1.14), Vector2(0.35, -1.08),
	Vector2(0.75, -0.85), Vector2(0.92, -0.45), Vector2(0.85, -0.1), Vector2(0.7, -0.5), Vector2(0.35, -0.75), Vector2(0.0, -0.7),
	Vector2(-0.3, -0.45), Vector2(-0.45, 0.1), Vector2(-0.55, 0.5)]
const HAIR_SHAGGY := [Vector2(-1.05, 0.35), Vector2(-1.12, -0.3), Vector2(-0.9, -0.95), Vector2(-0.35, -1.22), Vector2(0.25, -1.18),
	Vector2(0.75, -0.95), Vector2(0.98, -0.5), Vector2(0.85, -0.38), Vector2(0.62, -0.6), Vector2(0.45, -0.42), Vector2(0.2, -0.66),
	Vector2(-0.15, -0.5), Vector2(-0.35, -0.1), Vector2(-0.6, 0.35)]
const HAIR_CURTAIN := [Vector2(-0.5, -0.95), Vector2(-1.05, -0.5), Vector2(-1.15, 0.3), Vector2(-1.1, 1.2), Vector2(-0.95, 2.1),
	Vector2(-0.6, 2.5), Vector2(-0.25, 2.3), Vector2(-0.2, 1.6), Vector2(-0.3, 0.9), Vector2(-0.2, 0.2)]
const COWL := [Vector2(-0.98, 0.45), Vector2(-1.0, -0.38), Vector2(-0.74, -0.96), Vector2(-0.24, -1.1), Vector2(0.3, -1.06),
	Vector2(0.68, -0.84), Vector2(0.9, -0.46), Vector2(0.94, -0.18), Vector2(0.6, -0.02), Vector2(0.45, 0.25), Vector2(0.36, 0.62),
	Vector2(0.0, 0.74), Vector2(-0.4, 0.68)]
const COWL_LENS := [Vector2(0.42, -0.36), Vector2(0.86, -0.34), Vector2(0.88, -0.16), Vector2(0.5, -0.12)]
const EAR_BOLT := [Vector2(0.0, 0.1), Vector2(-0.35, -0.05), Vector2(-0.2, -0.12), Vector2(-0.62, -0.42), Vector2(-0.15, -0.3),
	Vector2(-0.28, -0.2), Vector2(0.05, -0.08)]
const HELMET := [Vector2(-0.65, 0.6), Vector2(-0.97, 0.1), Vector2(-1.02, -0.38), Vector2(-0.76, -0.9), Vector2(-0.26, -1.1),
	Vector2(0.28, -1.07), Vector2(0.68, -0.86), Vector2(0.9, -0.46), Vector2(0.97, -0.1), Vector2(0.96, 0.25), Vector2(0.88, 0.56),
	Vector2(0.6, 0.84), Vector2(0.2, 0.84), Vector2(-0.2, 0.74)]
const HOOD_BACK := [Vector2(-1.25, 1.15), Vector2(-1.38, 0.2), Vector2(-1.25, -0.6), Vector2(-0.85, -1.2), Vector2(-0.35, -1.58),
	Vector2(0.15, -1.4), Vector2(0.6, -1.15), Vector2(0.95, -0.72), Vector2(1.08, -0.25), Vector2(1.0, 0.2), Vector2(0.75, 0.35),
	Vector2(0.4, 1.15)]
const HOOD_SHADOW := [Vector2(0.12, -0.92), Vector2(0.8, -0.76), Vector2(0.99, -0.3), Vector2(0.96, 0.0), Vector2(0.6, 0.02), Vector2(0.18, -0.2)]
const HOOD_FRONT := [Vector2(-0.35, -1.2), Vector2(0.25, -1.16), Vector2(0.75, -0.92), Vector2(1.06, -0.46), Vector2(1.06, -0.2),
	Vector2(0.88, -0.56), Vector2(0.5, -0.84), Vector2(0.05, -0.9), Vector2(-0.2, -0.5), Vector2(-0.05, 0.3), Vector2(0.15, 0.85),
	Vector2(-0.3, 1.08), Vector2(-0.72, 0.4), Vector2(-0.66, -0.6)]
const DOMINO := [Vector2(0.25, -0.34), Vector2(0.9, -0.32), Vector2(0.93, -0.06), Vector2(0.62, -0.02), Vector2(0.5, -0.14), Vector2(0.3, -0.06)]
const HOCKEY := [Vector2(0.12, -0.86), Vector2(0.6, -0.83), Vector2(0.88, -0.46), Vector2(0.99, 0.0), Vector2(0.91, 0.45),
	Vector2(0.7, 0.76), Vector2(0.25, 0.73), Vector2(0.05, 0.1)]
const REIGN_MASK := [Vector2(0.05, -0.98), Vector2(0.6, -0.88), Vector2(0.9, -0.48), Vector2(0.99, -0.06), Vector2(0.6, 0.03),
	Vector2(0.3, -0.08), Vector2(0.02, -0.42)]
const MOHAWK := [Vector2(-0.75, -0.6), Vector2(-0.55, -1.25), Vector2(-0.15, -1.38), Vector2(0.35, -1.3), Vector2(0.62, -0.95),
	Vector2(0.45, -0.88), Vector2(0.0, -0.98), Vector2(-0.45, -0.85)]
const BEANIE := [Vector2(-0.98, -0.12), Vector2(-0.95, -0.7), Vector2(-0.55, -1.15), Vector2(0.05, -1.25), Vector2(0.55, -1.08),
	Vector2(0.85, -0.66), Vector2(0.9, -0.35), Vector2(0.45, -0.4), Vector2(-0.3, -0.3)]
const CAP := [Vector2(-0.95, -0.2), Vector2(-0.88, -0.75), Vector2(-0.4, -1.12), Vector2(0.2, -1.12), Vector2(0.7, -0.82),
	Vector2(0.85, -0.5), Vector2(1.35, -0.45), Vector2(1.3, -0.33), Vector2(0.4, -0.35), Vector2(-0.4, -0.2)]
const ARMY := [Vector2(-1.1, -0.05), Vector2(-1.0, -0.7), Vector2(-0.55, -1.18), Vector2(0.1, -1.25), Vector2(0.62, -1.05),
	Vector2(0.95, -0.6), Vector2(1.08, -0.3), Vector2(0.95, -0.25), Vector2(0.2, -0.35), Vector2(-0.6, -0.1)]
const SHADES := [Vector2(0.28, -0.34), Vector2(0.95, -0.32), Vector2(0.92, -0.06), Vector2(0.62, -0.03), Vector2(0.5, -0.16),
	Vector2(0.3, -0.12)]
const TV_BOX := [Vector2(-1.15, -1.15), Vector2(1.15, -1.15), Vector2(1.15, 0.75), Vector2(-1.15, 0.75)]
const BEARD := [Vector2(-0.05, 0.22), Vector2(0.5, 0.28), Vector2(0.82, 0.34), Vector2(0.86, 0.55), Vector2(0.66, 0.86),
	Vector2(0.3, 0.97), Vector2(-0.05, 0.82), Vector2(-0.28, 0.5)]
const GOATEE := [Vector2(0.55, 0.45), Vector2(0.86, 0.42), Vector2(0.82, 0.72), Vector2(0.6, 0.76)]
const JAY_DOME := [Vector2(-0.95, -0.12), Vector2(-0.88, -0.78), Vector2(-0.35, -1.22), Vector2(0.35, -1.22), Vector2(0.86, -0.78),
	Vector2(1.0, -0.36), Vector2(1.2, -0.28), Vector2(-1.08, -0.1)]
const JAY_WING := [Vector2(-0.2, -0.66), Vector2(-0.8, -1.1), Vector2(-0.62, -0.82), Vector2(-0.95, -0.86), Vector2(-0.55, -0.55)]
const BOLT := [Vector2(0.15, -1.05), Vector2(-0.5, 0.05), Vector2(0.0, 0.0), Vector2(-0.2, 1.05), Vector2(0.5, -0.15), Vector2(0.02, -0.08)]
const SHIELD := [Vector2(-1.0, -0.62), Vector2(1.0, -0.62), Vector2(1.22, -0.18), Vector2(0.0, 1.0), Vector2(-1.22, -0.18)]
## Diagnostics: when set, invalid polygons are reported with this tag.
static var debug_tag := ""

const BOOT := [Vector2(-0.036, -0.036), Vector2(0.026, -0.032), Vector2(0.066, 0.004), Vector2(0.096, 0.022), Vector2(0.1, 0.043),
	Vector2(-0.044, 0.046), Vector2(-0.05, 0.012)]


# --- Kinematics ---------------------------------------------------------------------------------

static func _ik(a: Vector2, target: Vector2, l1: float, l2: float, bend: float) -> Array:
	var d := target - a
	var dist := d.length()
	var dir := d / dist if dist > 0.001 else Vector2(0, 1)
	dist = clampf(dist, absf(l1 - l2) + 0.5, l1 + l2 - 0.01)
	var x := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - x * x))
	var perp := Vector2(-dir.y, dir.x)
	return [a + dir * x + perp * h * bend, a + dir * dist]


static func _build(look: Dictionary) -> String:
	return str(look.get("build", "male"))


## Solves a pose into joint positions in LOCAL space (facing right, feet origin).
static func solve(pose: Dictionary, H: float, look: Dictionary, sway: float = 0.0) -> Dictionary:
	var bulk: float = look.get("bulk", 1.0)
	var fem := _build(look) == "female"
	var hip: Vector2 = pose["hip"] * H
	var t := deg_to_rad(pose["t"])
	var tdir := Vector2(sin(t), -cos(t))
	var tn := Vector2(cos(t), sin(t))
	var sh := hip + tdir * 0.262 * H
	var neck := hip + tdir * 0.30 * H
	var ha := deg_to_rad(pose["t"] + pose["h"])
	var head := neck + Vector2(sin(ha), -cos(ha)) * 0.074 * H
	var sw := (0.024 if fem else 0.032) * bulk
	var s_f := sh + tn * sw * H
	var s_b := sh - tn * (sw + 0.012) * H + Vector2(0, 0.006 * H)
	var st: float = pose["stretch"]
	var fh: Vector2 = pose["fh"]
	var bh: Vector2 = pose["bh"]
	var ff: Vector2 = pose["ff"]
	var bf: Vector2 = pose["bf"]
	var af := _ik(s_f, s_f + fh * H, 0.165 * H * st, 0.155 * H * st, pose["fe"])
	var ab := _ik(s_b, s_b + bh * H, 0.165 * H, 0.155 * H, pose["be"])
	var hw := (0.03 if fem else 0.026) * H * bulk
	var hp_f := hip + Vector2(hw, 0)
	var hp_b := hip - Vector2(hw, 0)
	var lf := _ik(hp_f, ff * H, 0.255 * H, 0.25 * H, -1.0)
	var lb := _ik(hp_b, bf * H, 0.255 * H, 0.25 * H, -1.0)
	var j := {
		"hip": hip, "sh": sh, "neck": neck, "head": head,
		"sf": s_f, "sb": s_b, "ef": af[0], "hf": af[1], "eb": ab[0], "hb": ab[1],
		"hpf": hp_f, "hpb": hp_b, "kf": lf[0], "ftf": lf[1], "kb": lb[0], "ftb": lb[1],
	}
	var rot: float = pose["rot"]
	if absf(rot) > 0.01:
		var r := deg_to_rad(rot)
		for k in j.keys():
			j[k] = hip + (j[k] - hip).rotated(r)
		tdir = tdir.rotated(r)
		tn = tn.rotated(r)
		ha += r
	j["tdir"] = tdir
	j["tn"] = tn
	j["ha"] = ha
	return j


# --- Colour helpers ------------------------------------------------------------------------------

static func _c(col: Color, o: Dictionary) -> Color:
	var c := col
	var fl: float = o.get("flash", 0.0)
	if fl > 0.0:
		c = c.lerp(WHITE, fl)
	if o.has("tint"):
		var tint: Color = o["tint"]
		c = c.lerp(Color(tint.r, tint.g, tint.b, c.a), tint.a)
	c.a *= float(o.get("alpha", 1.0))
	return c


static func _shadow(col: Color) -> Color:
	var c := col.darkened(0.36).lerp(Color(0.16, 0.1, 0.3, col.a), 0.14)
	c.a = col.a
	return c


static func _hilite(col: Color) -> Color:
	var c := col.lightened(0.3).lerp(Color(1, 0.96, 0.86, col.a), 0.08)
	c.a = col.a
	return c


static func _col(look: Dictionary, key: String, fallback: Color) -> Color:
	var v = look.get(key)
	return v if v is Color else fallback


# --- Geometry helpers ----------------------------------------------------------------------------

static func _tp(cx: Dictionary, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	var f: float = cx["f"]
	var org: Vector2 = cx["org"]
	for i in pts.size():
		out[i] = org + Vector2(pts[i].x * f, pts[i].y)
	return out


static func _tv(cx: Dictionary, p: Vector2) -> Vector2:
	return cx["org"] + Vector2(p.x * cx["f"], p.y)


static func _fill(ci: CanvasItem, pts: PackedVector2Array, col: Color, check: bool = true) -> void:
	if not check or _ok(pts):
		ci.draw_colored_polygon(pts, col)


## True when a polygon can be filled (not degenerate / self-intersecting).
static func _ok(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty()


static func _clip(poly: PackedVector2Array, q: Vector2, dir: Vector2) -> Array:
	var t := Vector2(-dir.y, dir.x)
	var hp := PackedVector2Array([q + t * 900.0, q - t * 900.0, q - t * 900.0 + dir * 900.0, q + t * 900.0 + dir * 900.0])
	return Geometry2D.intersect_polygons(poly, hp)


static func _wat(widths: Array, t: float) -> float:
	var n := widths.size() - 1
	var x := clampf(t, 0.0, 1.0) * n
	var i := mini(int(x), n - 1)
	return lerpf(widths[i], widths[i + 1], x - i)


## Closed polygon for a tapered limb segment with rounded ends.
static func _profile(a: Vector2, b: Vector2, widths: Array, t0: float = 0.0, t1: float = 1.0, grow: float = 0.0) -> PackedVector2Array:
	var d := b - a
	if d.length() < 0.5:
		d = Vector2(0, 0.5)
	var dir := d.normalized()
	var n := Vector2(-dir.y, dir.x)
	var pa := a + d * t0
	var pb := a + d * t1
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in 5:
		var tt := lerpf(t0, t1, k / 4.0)
		var c := a + d * tt
		var w := _wat(widths, tt) * 0.5 + grow
		left.append(c + n * w)
		right.append(c - n * w)
	var out := PackedVector2Array()
	out.append_array(left)
	var rb := _wat(widths, t1) * 0.5 + grow
	for k in [1, 2, 3]:
		var th: float = PI * k / 4.0
		out.append(pb + n * cos(th) * rb + dir * sin(th) * rb)
	right.reverse()
	out.append_array(right)
	var ra := _wat(widths, t0) * 0.5 + grow
	for k in [1, 2, 3]:
		var th: float = PI * k / 4.0
		out.append(pa - n * cos(th) * ra - dir * sin(th) * ra)
	return out


static func _scale(ws: Array, s: float) -> Array:
	var out: Array = []
	for w in ws:
		out.append(float(w) * s)
	return out


## Shape relative to a head: unit points rotated by the head angle and scaled.
static func _hpoly(c: Vector2, r: float, ang: float, pts: Array, sx: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + Vector2(p.x * sx, p.y).rotated(ang) * r)
	return out


static func _hp(c: Vector2, r: float, ang: float, p: Vector2) -> Vector2:
	return c + p.rotated(ang) * r


## Convex outline of a cloth shape. Capes, coat tails and skirts can fold over
## themselves during flips and tumbles; the hull keeps the polygon valid.
static func _hull(pts: PackedVector2Array) -> PackedVector2Array:
	var h := Geometry2D.convex_hull(pts)
	if h.size() > 1 and h[0] == h[h.size() - 1]:
		h.remove_at(h.size() - 1)
	return h


static func _circle(c: Vector2, r: float, n: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _frame(c: Vector2, u: Vector2, v: Vector2, pts: Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + u * p.x * s + v * p.y * s)
	return out


# --- Drawing primitives --------------------------------------------------------------------------

## Fills a shape with banded shading (shadow / base / highlight) and an outline.
static func _part(cx: Dictionary, poly: PackedVector2Array, col: Color, ld: Vector2, center: Vector2, hw: float, outline: bool = true, shade: bool = true) -> void:
	if poly.size() < 3:
		return
	var ci: CanvasItem = cx["ci"]
	var o: Dictionary = cx["o"]
	var sp := _tp(cx, poly)
	if not _ok(sp):
		if debug_tag != "":
			print("BADPOLY ", debug_tag, " ", poly.size(), " ", poly)
		return
	if o.has("solid"):
		_fill(ci, sp, o["solid"], false)
		return
	if not shade:
		_fill(ci, sp, _c(col, o), false)
	else:
		_fill(ci, sp, _c(_shadow(col), o), false)
		for p in _clip(poly, center - ld * hw * 0.05, ld):
			_fill(ci, _tp(cx, p), _c(col, o))
		if not o.get("lod", false):
			for p in _clip(poly, center + ld * hw * 0.62, ld):
				_fill(ci, _tp(cx, p), _c(_hilite(col), o))
	if outline:
		var cl := sp.duplicate()
		cl.append(sp[0])
		ci.draw_polyline(cl, _c(cx["oc"], o), 1.0)


## Draws an outline silhouette (polygon grown by ~1px) so chained parts merge
## into one outlined shape (upper arm + forearm + hand, thigh + shin + boot).
static func _sil(cx: Dictionary, polys: Array) -> void:
	var o: Dictionary = cx["o"]
	if o.has("solid"):
		return
	var ci: CanvasItem = cx["ci"]
	var col := _c(cx["oc"], o)
	for poly in polys:
		for g in Geometry2D.offset_polygon(poly, 1.1):
			if _ok(g):
				_fill(ci, _tp(cx, g), col)


static func _flat(cx: Dictionary, poly: PackedVector2Array, col: Color) -> void:
	if poly.size() < 3:
		return
	var o: Dictionary = cx["o"]
	if o.has("solid"):
		return
	_fill(cx["ci"], _tp(cx, poly), _c(col, o))


static func _line(cx: Dictionary, a: Vector2, b: Vector2, col: Color, w: float = 1.0) -> void:
	var o: Dictionary = cx["o"]
	if o.has("solid"):
		return
	(cx["ci"] as CanvasItem).draw_line(_tv(cx, a), _tv(cx, b), _c(col, o), w)


static func _limb(cx: Dictionary, a: Vector2, b: Vector2, widths: Array, col: Color, t0: float = 0.0, t1: float = 1.0, grow: float = 0.0, outline: bool = true) -> void:
	var poly := _profile(a, b, widths, t0, t1, grow)
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x)
	var ld: Vector2 = cx["light"]
	var nl := n if n.dot(ld) >= 0.0 else -n
	var tm := (t0 + t1) * 0.5
	_part(cx, poly, col, nl, a.lerp(b, tm), _wat(widths, tm) * 0.5, outline)
	if cx["metal"] and not cx["o"].has("solid"):
		var w := _wat(widths, tm) * 0.5
		_line(cx, a.lerp(b, t0 + (t1 - t0) * 0.15) + nl * w * 0.55, a.lerp(b, t0 + (t1 - t0) * 0.8) + nl * w * 0.5, Color(1, 1, 1, 0.75), 1.0)
	var seam = cx["look"].get("seams")
	if seam is Color and t0 == 0.0 and t1 == 1.0:
		var w2 := _wat(widths, tm) * 0.5
		_line(cx, a.lerp(b, 0.12) - nl * w2 * 0.35, b.lerp(a, 0.12) - nl * w2 * 0.3, seam, 1.0)


static func _hand_poly(wrist: Vector2, elbow: Vector2, s: float, open: bool) -> PackedVector2Array:
	var dir := (wrist - elbow).normalized()
	var n := Vector2(-dir.y, dir.x)
	if open:
		return _frame(wrist + dir * s * 0.55, dir, n, [Vector2(-0.45, -0.42), Vector2(0.35, -0.48), Vector2(0.72, -0.3), Vector2(0.78, 0.15),
			Vector2(0.4, 0.42), Vector2(0.1, 0.62), Vector2(-0.12, 0.45), Vector2(-0.45, 0.4)], s)
	return _frame(wrist + dir * s * 0.42, dir, n, [Vector2(-0.45, -0.42), Vector2(0.3, -0.52), Vector2(0.55, -0.32), Vector2(0.56, 0.3),
		Vector2(0.3, 0.5), Vector2(-0.1, 0.55), Vector2(-0.45, 0.38)], s)


static func _hand(cx: Dictionary, wrist: Vector2, elbow: Vector2, col: Color, s: float, open: bool, outline: bool = true) -> void:
	var dir := (wrist - elbow).normalized()
	var n := Vector2(-dir.y, dir.x)
	var c := wrist + dir * s * (0.55 if open else 0.42)
	var poly := _hand_poly(wrist, elbow, s, open)
	_part(cx, poly, col, cx["light"], c, s * 0.5, outline)
	if not open:
		_line(cx, c + dir * s * 0.32 + n * s * 0.35, c + dir * s * 0.32 - n * s * 0.35, _shadow(col), 1.0)


static func _boot_poly(ankle: Vector2, knee: Vector2, s: float) -> PackedVector2Array:
	var v := (ankle - knee).normalized()
	return _frame(ankle, Vector2(v.y, -v.x), v, BOOT, s)


static func _boot(cx: Dictionary, ankle: Vector2, knee: Vector2, col: Color, s: float, outline: bool = true) -> void:
	var v := (ankle - knee).normalized()
	var u := Vector2(v.y, -v.x)
	var poly := _boot_poly(ankle, knee, s)
	_part(cx, poly, col, cx["light"], ankle + u * s * 0.03, s * 0.05, outline)
	_line(cx, ankle + u * (-0.044 * s) + v * (0.04 * s), ankle + u * (0.098 * s) + v * (0.038 * s), _shadow(col).darkened(0.3), 1.0)


# --- Main entry ----------------------------------------------------------------------------------

## Draws a complete fighter. `origin` is the feet anchor in the canvas item's space.
static func draw(ci: CanvasItem, origin: Vector2, facing: int, pose: Dictionary, look: Dictionary, H: float, o: Dictionary = {}) -> void:
	var sway := float(o.get("sway", 0.0))
	var j := solve(pose, H, look, sway)
	var cx := {
		"ci": ci, "o": o, "f": float(facing), "org": origin, "look": look,
		"light": LIGHT.normalized(),
		"oc": o.get("outline", OUTLINE), "metal": look.get("metal", false),
	}
	var bulk: float = look.get("bulk", 1.0)
	var fem := _build(look) == "female"
	var arm_s := H * bulk * (0.8 if fem else 1.0)
	var leg_s := H * bulk * (0.92 if fem else 1.0)
	var skin := _col(look, "skin", Color(0.9, 0.7, 0.55))
	var suit := _col(look, "suit", Color(0.5, 0.5, 0.5))
	var arms := _col(look, "arms", suit)
	var forearm := _col(look, "forearm", arms)
	var gloves := _col(look, "gloves", forearm)
	var legs := _col(look, "legs", suit)
	var shins := _col(look, "shins", legs)
	var boots := _col(look, "boots", shins)
	var glove_len: float = look.get("glove_len", 0.0 if gloves == forearm else 0.32)
	var boot_len: float = look.get("boot_len", 0.0 if boots == shins else 0.5)
	var time := float(o.get("time", 0.0))
	var tdir: Vector2 = j["tdir"]
	var down := (-tdir).lerp(Vector2(0, 1), 0.5).normalized()

	# 1. Back layers: cape, coat tail, long hair.
	if look.get("cape") is Color:
		_cape(cx, j, look, H, sway, time)
	if look.get("coat") is Color:
		_coat_tail(cx, j, look, H, sway, true)
	if str(look.get("head", "")) in ["long", "wavy"]:
		var r0 := 0.062 * H * float(look.get("head_scale", 1.0))
		var cur := _hpoly(j["head"], r0, j["ha"] * 0.5, HAIR_CURTAIN)
		for i in range(4, cur.size()):
			cur[i] += Vector2(-sway * 0.04 * H, 0)
		if Geometry2D.triangulate_polygon(cur).is_empty():
			cur = _hull(cur)
		_part(cx, cur, _col(look, "hair", Color.BLACK), cx["light"], j["head"], r0)

	# 2. Back arm and back leg (darker for depth).
	var bd := 0.24
	_arm(cx, j["sb"], j["eb"], j["hb"], arms.darkened(bd), forearm.darkened(bd), gloves.darkened(bd), glove_len, arm_s, pose, false, look)
	_leg(cx, j["hpb"], j["kb"], j["ftb"], legs.darkened(bd), shins.darkened(bd), boots.darkened(bd), boot_len, leg_s, look, true)

	# 3. Gear worn on the back.
	_back_gear(cx, j, look, H)

	# 4. Torso.
	_torso(cx, j, look, H, suit)

	# 5. Front leg, then skirt / front coat panel over it.
	_leg(cx, j["hpf"], j["kf"], j["ftf"], legs, shins, boots, boot_len, leg_s, look, false)
	if look.get("skirt") is Color:
		_skirt(cx, j, look, H)
	if look.get("coat") is Color:
		_coat_tail(cx, j, look, H, sway, false)

	# 6. Neck and head.
	var head_style := str(look.get("head", "short"))
	var neck_col := skin
	if head_style in ["cowl", "helmet", "hood", "visor", "prometheus"]:
		neck_col = _col(look, "mask", suit).darkened(0.15)
	if look.get("collar") is Color:
		neck_col = look["collar"]
	var r := 0.062 * H * float(look.get("head_scale", 1.0))
	var neck_end := _hp(j["head"], r, j["ha"], Vector2(-0.18, 0.55))
	_limb(cx, j["sh"] + tdir * 0.01 * H, neck_end, _scale([0.07, 0.062], H * sqrt(bulk)), neck_col)
	_head(cx, j, look, r, pose)

	# 7. Front arm and held props.
	_arm(cx, j["sf"], j["ef"], j["hf"], arms, forearm, gloves, glove_len, arm_s, pose, true, look)
	_props(cx, j, look, pose, H, down)


# --- Body parts -----------------------------------------------------------------------------------

static func _arm(cx: Dictionary, s: Vector2, e: Vector2, h: Vector2, upper: Color, fore: Color, glove: Color, glove_len: float, sc: float, pose: Dictionary, front: bool, look: Dictionary) -> void:
	var stretch: float = pose["stretch"] if front else 1.0
	var ua := _scale(UA, sc)
	var fa := _scale(FA, sc * (0.9 if stretch > 1.2 else 1.0))
	var hs := 0.062 * sc
	var open: bool = pose["open"] > 0.5
	_sil(cx, [_profile(s, e, ua), _profile(e, h, fa), _hand_poly(h, e, hs, open)])
	_limb(cx, s, e, ua, upper, 0.0, 1.0, 0.0, false)
	if look.get("pads", false) and front:
		var pc := _col(look, "pad_color", Color(0.3, 0.31, 0.34))
		var d := (e - s).normalized()
		_part(cx, _frame(s + d * sc * 0.015, d, Vector2(-d.y, d.x), [Vector2(-0.05, -0.05), Vector2(0.03, -0.055), Vector2(0.06, 0.0), Vector2(0.03, 0.05), Vector2(-0.05, 0.05)], sc), pc, cx["light"], s, sc * 0.05)
	_limb(cx, e, h, fa, fore, 0.0, 1.0, 0.0, false)
	if glove_len > 0.0:
		_limb(cx, e, h, fa, glove, 1.0 - glove_len, 1.0, 0.7, false)
		var gd := (h - e).normalized()
		var gn := Vector2(-gd.y, gd.x)
		var gt := e.lerp(h, 1.0 - glove_len)
		var gw := _wat(fa, 1.0 - glove_len) * 0.5 + 0.7
		_line(cx, gt + gn * gw, gt - gn * gw, _shadow(glove).darkened(0.3), 1.0)
	var stripe = look.get("stripe")
	if stripe is Color:
		var d2 := (h - e).normalized()
		var nn := Vector2(-d2.y, d2.x)
		_line(cx, e.lerp(h, 0.1) + nn * 1.5, e.lerp(h, 0.85) + nn * 1.5, stripe, 1.5)
		var d3 := (e - s).normalized()
		var n3 := Vector2(-d3.y, d3.x)
		_line(cx, s.lerp(e, 0.15) + n3 * 2.0, s.lerp(e, 0.88) + n3 * 2.0, stripe, 1.5)
	_hand(cx, h, e, glove, hs, open, false)


static func _leg(cx: Dictionary, hp: Vector2, k: Vector2, ft: Vector2, thigh_c: Color, shin_c: Color, boot_c: Color, boot_len: float, sc: float, look: Dictionary, back: bool) -> void:
	var th := _scale(TH, sc)
	var sn := _scale(SN, sc)
	var bs := sc * (0.95 if _build(look) == "female" else 1.0)
	_sil(cx, [_profile(hp, k, th), _profile(k, ft, sn), _boot_poly(ft, k, bs)])
	_limb(cx, hp, k, th, thigh_c, 0.0, 1.0, 0.0, false)
	_limb(cx, k, ft, sn, shin_c, 0.0, 1.0, 0.0, false)
	if boot_len > 0.0:
		_limb(cx, k, ft, sn, boot_c, 1.0 - boot_len, 1.0, 0.8, false)
		var d := (ft - k).normalized()
		var nn := Vector2(-d.y, d.x)
		var top := k.lerp(ft, 1.0 - boot_len)
		var w := _wat(sn, 1.0 - boot_len) * 0.5 + 0.8
		_line(cx, top + nn * w, top - nn * w, _hilite(boot_c), 1.0)
	if look.get("kneepads") is Color:
		var kc: Color = look["kneepads"]
		if back:
			kc = kc.darkened(0.24)
		_part(cx, _circle(k + (k - ft).normalized().rotated(-PI * 0.5) * sc * 0.012, sc * 0.04, 7), kc, cx["light"], k, sc * 0.04)
	_boot(cx, ft, k, boot_c, bs, false)


static func _tq(j: Dictionary, H: float, bw: float, x: float, y: float) -> Vector2:
	return j["hip"] + j["tn"] * x * H * bw + j["tdir"] * y * H


static func _torso_pts(j: Dictionary, look: Dictionary, H: float) -> PackedVector2Array:
	var bw: float = look.get("bulk", 1.0)
	var belly: float = look.get("belly", 0.0)
	var raw: Array
	if _build(look) == "female":
		raw = [Vector2(0.02, -0.05), Vector2(0.07, 0.0), Vector2(0.05 + 0.05 * belly, 0.10), Vector2(0.066, 0.165), Vector2(0.076, 0.185),
			Vector2(0.098, 0.212), Vector2(0.06, 0.262), Vector2(0.022, 0.29), Vector2(-0.028, 0.29), Vector2(-0.06, 0.266),
			Vector2(-0.07, 0.22), Vector2(-0.06, 0.15), Vector2(-0.045, 0.09), Vector2(-0.078, 0.0), Vector2(-0.03, -0.05)]
	else:
		raw = [Vector2(0.02, -0.05), Vector2(0.068, -0.01), Vector2(0.06 + 0.07 * belly, 0.10), Vector2(0.072 + 0.04 * belly, 0.17),
			Vector2(0.088, 0.20), Vector2(0.092, 0.235), Vector2(0.06, 0.27), Vector2(0.025, 0.29), Vector2(-0.03, 0.29),
			Vector2(-0.07, 0.27), Vector2(-0.082, 0.22), Vector2(-0.07, 0.15), Vector2(-0.055, 0.09), Vector2(-0.072, 0.01),
			Vector2(-0.03, -0.05)]
	var out := PackedVector2Array()
	for p in raw:
		out.append(_tq(j, H, bw, p.x, p.y))
	return out


static func _torso(cx: Dictionary, j: Dictionary, look: Dictionary, H: float, suit: Color) -> void:
	var bw: float = look.get("bulk", 1.0)
	var fem := _build(look) == "female"
	var poly := _torso_pts(j, look, H)
	var center := _tq(j, H, bw, 0.0, 0.14)
	_part(cx, poly, suit, cx["light"], center, 0.09 * H * bw)
	if cx["o"].has("solid"):
		return
	# Side panel (suit2) along the back/side.
	if look.get("suit2") is Color:
		var sp := PackedVector2Array([_tq(j, H, bw, -0.072, 0.22), _tq(j, H, bw, -0.03, 0.225), _tq(j, H, bw, -0.018, 0.02), _tq(j, H, bw, -0.066, 0.02)])
		for p in Geometry2D.intersect_polygons(sp, poly):
			_flat(cx, p, look["suit2"])
	# Shirt strip for open jackets/coats.
	if look.get("shirt") is Color:
		var strip := PackedVector2Array([_tq(j, H, bw, 0.018, 0.288), _tq(j, H, bw, 0.06, 0.268), _tq(j, H, bw, 0.088 if not fem else 0.09, 0.215),
			_tq(j, H, bw, 0.066, 0.1), _tq(j, H, bw, 0.03, 0.06), _tq(j, H, bw, 0.028, 0.2)])
		for p in Geometry2D.intersect_polygons(strip, poly):
			_part(cx, p, look["shirt"], cx["light"], center, 0.05 * H, false)
		_line(cx, _tq(j, H, bw, 0.028, 0.27), _tq(j, H, bw, 0.03, 0.06), _shadow(suit).darkened(0.3), 1.0)
	# Muscle definition for skin-tight suits.
	if look.get("muscles", false):
		var mc := _shadow(suit)
		mc.a = 0.8
		if not fem:
			_line(cx, _tq(j, H, bw, 0.01, 0.2), _tq(j, H, bw, 0.085, 0.198), mc)
			_line(cx, _tq(j, H, bw, 0.04, 0.155), _tq(j, H, bw, 0.07, 0.152), mc)
			_line(cx, _tq(j, H, bw, 0.04, 0.12), _tq(j, H, bw, 0.066, 0.118), mc)
		_line(cx, _tq(j, H, bw, 0.045, 0.18), _tq(j, H, bw, 0.045, 0.07), mc)
	# Armor plates.
	if look.get("plates") is Color:
		var pc: Color = look["plates"]
		var pec := PackedVector2Array([_tq(j, H, bw, 0.0, 0.258), _tq(j, H, bw, 0.07, 0.25), _tq(j, H, bw, 0.088, 0.21), _tq(j, H, bw, 0.075, 0.18), _tq(j, H, bw, 0.0, 0.178)])
		_part(cx, pec, pc, cx["light"], _tq(j, H, bw, 0.04, 0.22), 0.04 * H)
		for k in 3:
			var y := 0.155 - k * 0.04
			var ab := PackedVector2Array([_tq(j, H, bw, 0.012, y), _tq(j, H, bw, 0.068, y), _tq(j, H, bw, 0.066, y - 0.032), _tq(j, H, bw, 0.012, y - 0.032)])
			_part(cx, ab, pc.darkened(0.1), cx["light"], _tq(j, H, bw, 0.04, y - 0.016), 0.02 * H)
	# Belt.
	if look.get("belt") is Color:
		var bc: Color = look["belt"]
		var band := PackedVector2Array([_tq(j, H, bw, -0.08, 0.045), _tq(j, H, bw, 0.08, 0.045), _tq(j, H, bw, 0.08, 0.008), _tq(j, H, bw, -0.08, 0.008)])
		for p in Geometry2D.intersect_polygons(band, poly):
			_part(cx, p, bc, cx["light"], _tq(j, H, bw, 0.0, 0.026), 0.02 * H)
		var bk := _col(look, "buckle", _hilite(bc))
		_flat(cx, PackedVector2Array([_tq(j, H, bw, 0.045, 0.04), _tq(j, H, bw, 0.07, 0.04), _tq(j, H, bw, 0.07, 0.012), _tq(j, H, bw, 0.045, 0.012)]), bk)
		if look.get("pouches", false):
			for k in 2:
				var x0 := -0.06 + k * 0.045
				_part(cx, PackedVector2Array([_tq(j, H, bw, x0, 0.03), _tq(j, H, bw, x0 + 0.035, 0.03), _tq(j, H, bw, x0 + 0.035, -0.02), _tq(j, H, bw, x0, -0.02)]), bc.darkened(0.15), cx["light"], _tq(j, H, bw, x0 + 0.017, 0.005), 0.02 * H)
	_emblem(cx, j, look, H, bw, poly)


static func _emblem(cx: Dictionary, j: Dictionary, look: Dictionary, H: float, bw: float, torso: PackedVector2Array) -> void:
	var c := _tq(j, H, bw, 0.028, 0.214)
	var s := 0.046 * H
	var u: Vector2 = j["tn"]
	var v: Vector2 = -j["tdir"]
	var accent := _col(look, "accent", Color(0.95, 0.75, 0.15))
	match str(look.get("emblem", "")):
		"bolt":
			var ring := _col(look, "emblem_ring", accent)
			var bg := _col(look, "emblem_bg", Color(0.97, 0.95, 0.9))
			var fg := _col(look, "emblem_fg", accent)
			_part(cx, _circle(c, s * 1.12, 12), ring, cx["light"], c, s)
			_part(cx, _circle(c, s * 0.92, 12), bg, cx["light"], c, s, false)
			_part(cx, _frame(c, u, v, BOLT, s * 0.9), fg, cx["light"], c, s * 0.5, false)
		"bolt_plain":
			_part(cx, _frame(c, u, v, BOLT, s * 1.2), accent, cx["light"], c, s * 0.6)
		"shield":
			var outer := _frame(c, u, v, SHIELD, s * 1.12)
			_part(cx, outer, _col(look, "emblem_bg", accent), cx["light"], c, s)
			_part(cx, _frame(c, u, v, SHIELD, s * 0.78), _col(look, "emblem_fg", Color(0.82, 0.08, 0.1)), cx["light"], c, s, false)
			var sline := PackedVector2Array()
			for p in [Vector2(0.42, -0.42), Vector2(-0.3, -0.38), Vector2(-0.38, -0.12), Vector2(0.3, -0.02), Vector2(0.3, 0.22), Vector2(-0.35, 0.3)]:
				sline.append(c + u * p.x * s + v * p.y * s)
			if not cx["o"].has("solid"):
				(cx["ci"] as CanvasItem).draw_polyline(_tp(cx, sline), _c(_col(look, "emblem_bg", accent), cx["o"]), 2.0)
		"xstraps":
			var red := _col(look, "accent", Color.RED)
			for pair in [[torso[6], torso[13]], [torso[9], torso[1]]]:
				var a: Vector2 = pair[0]
				var b: Vector2 = pair[1]
				var d := (b - a).normalized()
				var n := Vector2(-d.y, d.x) * 0.02 * H
				var band := PackedVector2Array([a + n, b + n, b - n, a - n])
				for p in Geometry2D.intersect_polygons(band, torso):
					_part(cx, p, red, cx["light"], (a + b) * 0.5, 0.02 * H)
		"strap":
			var a2: Vector2 = torso[7]
			var b2: Vector2 = torso[13]
			var d2 := (b2 - a2).normalized()
			var n2 := Vector2(-d2.y, d2.x) * 0.016 * H
			for p in Geometry2D.intersect_polygons(PackedVector2Array([a2 + n2, b2 + n2, b2 - n2, a2 - n2]), torso):
				_part(cx, p, _col(look, "strap", Color(0.3, 0.19, 0.1)), cx["light"], (a2 + b2) * 0.5, 0.016 * H)
		"zip":
			_line(cx, _tq(j, H, bw, 0.07, 0.27), _tq(j, H, bw, 0.055, 0.02), Color(0.72, 0.72, 0.78), 1.0)
			if look.get("choker") is Color:
				_line(cx, _tq(j, H, bw, -0.02, 0.3), _tq(j, H, bw, 0.03, 0.3), look["choker"], 2.0)
		"vest":
			for k in 2:
				var y := 0.21 - k * 0.06
				_part(cx, PackedVector2Array([_tq(j, H, bw, 0.03, y), _tq(j, H, bw, 0.085, y), _tq(j, H, bw, 0.08, y - 0.045), _tq(j, H, bw, 0.03, y - 0.045)]),
					_col(look, "vest", Color(0.2, 0.21, 0.24)), cx["light"], _tq(j, H, bw, 0.055, y - 0.02), 0.025 * H)
		"piping":
			var pc := _col(look, "accent", Color(0.3, 0.6, 1.0))
			_line(cx, torso[6], torso[4], pc, 1.5)
			_line(cx, torso[4], torso[2], pc, 1.5)
		"tie":
			_flat(cx, PackedVector2Array([_tq(j, H, bw, 0.02, 0.29), _tq(j, H, bw, 0.07, 0.27), _tq(j, H, bw, 0.05, 0.2)]), Color(0.92, 0.92, 0.95))
			_part(cx, PackedVector2Array([_tq(j, H, bw, 0.05, 0.27), _tq(j, H, bw, 0.065, 0.26), _tq(j, H, bw, 0.075, 0.12), _tq(j, H, bw, 0.06, 0.1), _tq(j, H, bw, 0.05, 0.12)]),
				_col(look, "accent", Color(0.5, 0.1, 0.12)), cx["light"], _tq(j, H, bw, 0.06, 0.18), 0.01 * H)
		"glyph":
			var gc := _col(look, "accent", Color(0.85, 0.1, 0.12))
			var pts := [Vector2(0.0, -1.0), Vector2(0.35, -0.2), Vector2(1.0, 0.0), Vector2(0.35, 0.25), Vector2(0.0, 1.0), Vector2(-0.35, 0.25), Vector2(-1.0, 0.0), Vector2(-0.35, -0.2)]
			_part(cx, _frame(c, u, v, pts, s * 0.95), gc, cx["light"], c, s * 0.5)
		"tv":
			_part(cx, _frame(c, u, v, [Vector2(-0.6, -0.5), Vector2(0.6, -0.5), Vector2(0.6, 0.45), Vector2(-0.6, 0.45)], s), Color(0.3, 0.9, 0.7), cx["light"], c, s * 0.5)
			_line(cx, c + u * -0.3 * s + v * -0.5 * s, c + u * -0.6 * s + v * -0.95 * s, OUTLINE)
			_line(cx, c + u * 0.2 * s + v * -0.5 * s, c + u * 0.5 * s + v * -0.95 * s, OUTLINE)


static func _cape(cx: Dictionary, j: Dictionary, look: Dictionary, H: float, sway: float, time: float) -> void:
	var tdir: Vector2 = j["tdir"]
	var tn: Vector2 = j["tn"]
	var down := (-tdir).lerp(Vector2(0, 1), 0.55).normalized()
	var back := Vector2(-1, 0)
	var L := float(look.get("cape_len", 0.46)) * H
	var flutter := sin(time * 7.0) * 0.015 * H * (0.4 + sway)
	var hip: Vector2 = j["hip"]
	var pts := PackedVector2Array([
		j["sb"] + tdir * 0.03 * H,
		j["sh"] + tdir * 0.035 * H + tn * 0.015 * H,
		hip + down * 0.12 * H + back * (0.02 + sway * 0.05) * H,
		hip + down * (L - 0.27 * H) + back * (0.06 + sway * 0.16) * H + Vector2(0, flutter),
		hip + down * (L - 0.25 * H) + back * (0.2 + sway * 0.34) * H + Vector2(flutter, -flutter),
		j["sb"] + back * (0.06 + sway * 0.08) * H + down * 0.1 * H,
	])
	var col := _col(look, "cape", Color.RED)
	var crease_a := pts[2].lerp(pts[5], 0.4)
	var crease_b := pts[3].lerp(pts[4], 0.45)
	pts = _hull(pts)
	if pts.size() < 3:
		return
	_part(cx, pts, col, cx["light"], hip.lerp(j["sb"], 0.5) + back * 0.1 * H, 0.12 * H)
	if not cx["o"].has("solid"):
		_line(cx, crease_a, crease_b, _shadow(col).darkened(0.2), 1.0)


static func _coat_tail(cx: Dictionary, j: Dictionary, look: Dictionary, H: float, sway: float, back_side: bool) -> void:
	var bw: float = look.get("bulk", 1.0)
	var col: Color = look["coat"]
	var hip: Vector2 = j["hip"]
	var down := (-(j["tdir"] as Vector2)).lerp(Vector2(0, 1), 0.6).normalized()
	var L := float(look.get("coat_len", 0.32)) * H
	var pts: PackedVector2Array
	if back_side:
		pts = PackedVector2Array([_tq(j, H, bw, -0.075, 0.06), _tq(j, H, bw, 0.0, 0.06), hip + down * L * 0.95 + Vector2(0.02, 0) * H,
			hip + down * L + Vector2(-0.12 - sway * 0.14, -sway * 0.03) * H])
		col = col.darkened(0.2)
	else:
		pts = PackedVector2Array([_tq(j, H, bw, 0.035, 0.06), _tq(j, H, bw, 0.07, 0.06), hip + down * L * 0.9 + Vector2(0.1, 0) * H,
			hip + down * L * 0.95 + Vector2(0.0 - sway * 0.05, 0) * H])
	pts = _hull(pts)
	if pts.size() < 3:
		return
	_part(cx, pts, col, cx["light"], hip + down * L * 0.5, 0.06 * H)


static func _skirt(cx: Dictionary, j: Dictionary, look: Dictionary, H: float) -> void:
	var bw: float = look.get("bulk", 1.0)
	var down := (-(j["tdir"] as Vector2)).lerp(Vector2(0, 1), 0.5).normalized()
	var hip: Vector2 = j["hip"]
	var col: Color = look["skirt"]
	var pts := PackedVector2Array([_tq(j, H, bw, -0.08, 0.05), _tq(j, H, bw, 0.075, 0.05), hip + down * 0.12 * H + Vector2(0.12, 0) * H,
		hip + down * 0.14 * H + Vector2(0.0, 0) * H, hip + down * 0.12 * H + Vector2(-0.13, 0) * H])
	pts = _hull(pts)
	if pts.size() < 3:
		return
	_part(cx, pts, col, cx["light"], hip + down * 0.05 * H, 0.08 * H)
	for k in 3:
		var x := -0.06 + k * 0.06
		_line(cx, _tq(j, H, bw, x, 0.03), hip + down * 0.12 * H + Vector2(x * 1.6, 0) * H, _shadow(col), 1.0)


static func _back_gear(cx: Dictionary, j: Dictionary, look: Dictionary, H: float) -> void:
	var tdir: Vector2 = j["tdir"]
	var tn: Vector2 = j["tn"]
	var bw: float = look.get("bulk", 1.0)
	if look.get("prop", "") == "bow":
		var qc: Vector2 = j["sh"].lerp(j["hip"], 0.3) - tn * 0.1 * H * bw
		var qa := tdir.rotated(deg_to_rad(-25))
		var qt := qc + qa * 0.16 * H
		var qb := qc - qa * 0.11 * H
		_limb(cx, qb, qt, [0.05 * H, 0.055 * H], Color(0.38, 0.22, 0.1))
		for i in 4:
			var base := qt + Vector2((i - 1.5) * 2.2, 0).rotated(qa.angle() + PI * 0.5)
			var tip := base + qa * 0.05 * H
			_line(cx, base, tip, Color(0.12, 0.1, 0.08), 1.0)
			_line(cx, tip - qa * 0.02 * H, tip, Color(0.8, 0.15, 0.1) if i % 2 == 0 else Color(0.2, 0.55, 0.2), 2.0)
	var w := str(look.get("weapon", ""))
	if w == "katana":
		var a: Vector2 = j["sb"] + tdir * 0.04 * H - tn * 0.03 * H
		var d := tdir.rotated(deg_to_rad(-30)) * -1.0
		_limb(cx, a - d * 0.06 * H, a + d * 0.36 * H, [0.022 * H, 0.02 * H], Color(0.12, 0.12, 0.14))


static func _props(cx: Dictionary, j: Dictionary, look: Dictionary, pose: Dictionary, H: float, _down: Vector2) -> void:
	var prop := str(look.get("prop", ""))
	var hf: Vector2 = j["hf"]
	var aim: Vector2 = (hf - j["ef"]).normalized()
	var o: Dictionary = cx["o"]
	if prop == "bow":
		var axis := Vector2(-aim.y, aim.x)
		if axis.y > 0:
			axis = -axis
		var top := hf + axis * 0.25 * H
		var bot := hf - axis * 0.25 * H
		var pts := PackedVector2Array()
		for i in 13:
			var k := i / 12.0
			var bulge := sin(k * PI) * 0.075 * H - pow(1.0 - sin(k * PI), 3.0) * 0.03 * H
			pts.append(bot.lerp(top, k) + aim * bulge)
		var ci: CanvasItem = cx["ci"]
		if o.has("solid"):
			ci.draw_polyline(_tp(cx, pts), o["solid"], 3.0)
		else:
			ci.draw_polyline(_tp(cx, pts), _c(OUTLINE, o), 4.0)
			ci.draw_polyline(_tp(cx, pts), _c(_col(look, "bow_color", Color(0.18, 0.2, 0.18)), o), 2.0)
			var sc := Color(0.86, 0.86, 0.8, 0.9)
			if pose["draw"] > 0.5:
				_line(cx, pts[0], j["hb"], sc)
				_line(cx, j["hb"], pts[12], sc)
				_line(cx, j["hb"], hf + aim * 0.12 * H, Color(0.6, 0.45, 0.25))
				_line(cx, hf + aim * 0.1 * H, hf + aim * 0.13 * H, Color(0.8, 0.82, 0.85), 2.0)
			else:
				_line(cx, pts[0], pts[12], sc)
	elif prop == "remote":
		var rp := hf + aim * 0.02 * H
		_limb(cx, rp, rp + aim * 0.07 * H, [0.03 * H, 0.03 * H], Color(0.2, 0.2, 0.24))
		_line(cx, rp + aim * 0.055 * H, rp + aim * 0.06 * H, Color(1, 0.2, 0.2), 2.0)
	var weapon := str(look.get("weapon", ""))
	if weapon == "katana" or weapon == "dagger":
		var bdir := aim.rotated(deg_to_rad(pose["blade"]))
		var blen := (0.44 if weapon == "katana" else 0.2) * H
		var guard := hf + bdir * 0.025 * H
		var tip := guard + bdir * blen
		var n := Vector2(-bdir.y, bdir.x)
		var blade := PackedVector2Array([guard + n * 1.6, tip - bdir * 3.0 + n * 1.2, tip, tip - bdir * 3.0 - n * 1.0, guard - n * 1.4])
		_part(cx, blade, _col(look, "blade_color", Color(0.78, 0.8, 0.86)), Vector2(-n.x, -n.y) if n.dot(cx["light"]) < 0 else n, guard.lerp(tip, 0.5), 2.0)
		_line(cx, guard + n * 0.8, tip - bdir * 2.0, Color(1, 1, 1, 0.8), 1.0)
		_limb(cx, hf - bdir * 0.07 * H, guard, [0.022 * H, 0.022 * H], _col(look, "hilt", Color(0.12, 0.1, 0.1)))
		_part(cx, _circle(guard, 0.022 * H, 6), Color(0.65, 0.5, 0.2), cx["light"], guard, 0.02 * H)
	if pose["gun"] > 0.5 or look.get("always_guns", false):
		for hand in ["hf", "hb"]:
			var hp: Vector2 = j[hand]
			var el: Vector2 = j["ef" if hand == "hf" else "eb"]
			var ga: Vector2 = (hp - el).normalized()
			var gn := Vector2(-ga.y, ga.x)
			if gn.y > 0:
				gn = -gn
			var g := PackedVector2Array([hp - ga * 0.01 * H + gn * 0.012 * H, hp + ga * 0.075 * H + gn * 0.012 * H, hp + ga * 0.075 * H - gn * 0.002 * H,
				hp + ga * 0.02 * H - gn * 0.004 * H, hp + ga * 0.012 * H - gn * 0.035 * H, hp - ga * 0.008 * H - gn * 0.03 * H])
			_part(cx, g, _col(look, "gun_color", Color(0.2, 0.2, 0.23)), cx["light"], hp, 0.02 * H)


# --- Head ----------------------------------------------------------------------------------------

static func _head(cx: Dictionary, j: Dictionary, look: Dictionary, r: float, pose: Dictionary) -> void:
	var c: Vector2 = j["head"]
	var a: float = j["ha"]
	var skin := _col(look, "skin", Color(0.9, 0.7, 0.55))
	var hair := _col(look, "hair", Color(0.15, 0.1, 0.05))
	var style := str(look.get("head", "short"))
	var face := str(look.get("face", ""))
	var mask := _col(look, "mask", Color(0.1, 0.1, 0.12))
	var ld: Vector2 = cx["light"]
	var solid: bool = cx["o"].has("solid")

	if style == "hood" or style == "visor" or style == "prometheus":
		var hood := _col(look, "hood", Color(0.2, 0.45, 0.2))
		_part(cx, _hpoly(c, r, a, HOOD_BACK), hood.darkened(0.12), ld, c, r * 1.2)
	if style == "tv":
		_tv_head(cx, c, r, a, look)
		return
	# Skull / face.
	_part(cx, _hpoly(c, r, a, HEAD), skin, ld, c, r)
	if solid:
		return
	# Ear.
	if style in ["short", "long", "wavy", "slick", "bald", "shaggy", "mohawk", "shaved"]:
		_part(cx, _circle(_hp(c, r, a, Vector2(-0.18, 0.04)), r * 0.2, 6), skin.darkened(0.08), ld, _hp(c, r, a, Vector2(-0.18, 0.04)), r * 0.2)
	# Facial features.
	var eye := _hp(c, r, a, Vector2(0.56, -0.14))
	var dark := Color(0.08, 0.06, 0.1)
	if face not in ["visor", "helmet", "hockey"]:
		_line(cx, _hp(c, r, a, Vector2(0.66, 0.42)), _hp(c, r, a, Vector2(0.83, 0.39)), skin.darkened(0.45), 1.0)
		_line(cx, _hp(c, r, a, Vector2(0.84, 0.06)), _hp(c, r, a, Vector2(0.92, 0.1)), skin.darkened(0.3), 1.0)
		var ec := _col(look, "eyes", dark)
		_flat(cx, _hpoly(c, r, a, [Vector2(0.4, -0.06), Vector2(0.52, -0.22), Vector2(0.74, -0.2), Vector2(0.78, -0.08), Vector2(0.6, -0.02)]), Color(0.96, 0.95, 0.93))
		_flat(cx, _hpoly(c, r, a, [Vector2(0.58, -0.2), Vector2(0.72, -0.19), Vector2(0.72, -0.05), Vector2(0.58, -0.04)]), ec)
		_line(cx, _hp(c, r, a, Vector2(0.4, -0.22)), _hp(c, r, a, Vector2(0.76, -0.22)), skin.darkened(0.5), 1.0)
		_line(cx, _hp(c, r, a, Vector2(0.32, -0.38)), _hp(c, r, a, Vector2(0.82, -0.33)), hair.darkened(0.2) if style != "bald" else skin.darkened(0.45), 2.0)
		var cheek := skin.darkened(0.2)
		cheek.a = 0.45
		_flat(cx, _hpoly(c, r, a, [Vector2(0.15, 0.08), Vector2(0.42, 0.06), Vector2(0.38, 0.2), Vector2(0.15, 0.3)]), cheek)
		if look.get("lips") is Color:
			_line(cx, _hp(c, r, a, Vector2(0.66, 0.42)), _hp(c, r, a, Vector2(0.83, 0.39)), look["lips"], 1.5)
	if look.get("beard") is Color:
		_part(cx, _hpoly(c, r, a, BEARD), look["beard"], ld, _hp(c, r, a, Vector2(0.3, 0.55)), r * 0.5)
		_line(cx, _hp(c, r, a, Vector2(0.64, 0.44)), _hp(c, r, a, Vector2(0.84, 0.42)), skin.darkened(0.5), 1.0)
	elif look.get("goatee") is Color:
		_part(cx, _hpoly(c, r, a, GOATEE), look["goatee"], ld, _hp(c, r, a, Vector2(0.7, 0.6)), r * 0.2)

	# Hair.
	match style:
		"short":
			_hair(cx, _hpoly(c, r, a, HAIR_SHORT), hair, c, r)
		"slick":
			_hair(cx, _hpoly(c, r, a, HAIR_SLICK), hair, c, r)
		"long", "wavy":
			_hair(cx, _hpoly(c, r, a, HAIR_LONG), hair, c, r)
		"shaggy":
			_hair(cx, _hpoly(c, r, a, HAIR_SHAGGY), hair, c, r)
		"bald":
			pass
		"shaved":
			var stub := hair
			stub.a = 0.45
			_flat(cx, _hpoly(c, r, a, HAIR_SLICK), stub)
		"mohawk":
			var side := hair
			side.a = 0.35
			_flat(cx, _hpoly(c, r, a, HAIR_SLICK), side)
			_hair(cx, _hpoly(c, r, a, MOHAWK), hair, _hp(c, r, a, Vector2(0, -1.0)), r * 0.4)

	# Masks / face coverings.
	match face:
		"domino":
			_part(cx, _hpoly(c, r, a, DOMINO), mask, ld, eye, r * 0.3)
			_flat(cx, _circle(eye, 1.3, 5), Color(0.92, 0.92, 0.95))
		"paint":
			var pc := mask
			pc.a = 0.85
			_flat(cx, _hpoly(c, r, a, DOMINO), pc)
			_flat(cx, _circle(eye, 1.0, 4), Color(0.85, 0.85, 0.8))
		"goggles":
			var band := [Vector2(-0.75, -0.36), Vector2(0.9, -0.36), Vector2(0.93, -0.02), Vector2(-0.75, 0.0)]
			_part(cx, _hpoly(c, r, a, band), mask, ld, eye, r * 0.3)
			var lens := [Vector2(0.35, -0.32), Vector2(0.9, -0.32), Vector2(0.92, -0.06), Vector2(0.38, -0.06)]
			_part(cx, _hpoly(c, r, a, lens), _col(look, "lens", Color(0.3, 0.6, 1.0)), ld, eye, r * 0.25)
		"bandana":
			_part(cx, _hpoly(c, r, a, [Vector2(-0.1, 0.12), Vector2(0.95, 0.08), Vector2(0.88, 0.62), Vector2(0.55, 0.82), Vector2(0.1, 0.78)]), mask, ld, c, r * 0.5)
		"hockey":
			var hk := _col(look, "mask", Color(0.92, 0.92, 0.9))
			_part(cx, _hpoly(c, r, a, HOCKEY), hk, ld, _hp(c, r, a, Vector2(0.5, 0.0)), r * 0.6)
			_flat(cx, _hpoly(c, r, a, [Vector2(0.4, -0.32), Vector2(0.78, -0.3), Vector2(0.74, -0.12), Vector2(0.44, -0.12)]), Color(0.06, 0.06, 0.08))
			for p in [Vector2(0.75, 0.25), Vector2(0.62, 0.42), Vector2(0.78, 0.5), Vector2(0.5, 0.6)]:
				_flat(cx, _circle(_hp(c, r, a, p), 0.9, 4), Color(0.2, 0.2, 0.22))
			_line(cx, _hp(c, r, a, Vector2(0.3, -0.7)), _hp(c, r, a, Vector2(0.5, 0.1)), _col(look, "accent", Color(0.8, 0.1, 0.1)), 1.5)
		"glasses":
			_flat(cx, _hpoly(c, r, a, [Vector2(0.3, -0.34), Vector2(0.9, -0.33), Vector2(0.9, 0.02), Vector2(0.32, 0.02)]), OUTLINE)
			_flat(cx, _hpoly(c, r, a, [Vector2(0.38, -0.27), Vector2(0.84, -0.26), Vector2(0.84, -0.04), Vector2(0.4, -0.04)]), Color(0.75, 0.9, 1.0))
		"martian":
			_part(cx, _hpoly(c, r, a, [Vector2(0.15, -0.46), Vector2(0.94, -0.34), Vector2(0.96, -0.18), Vector2(0.25, -0.24)]), skin.darkened(0.25), ld, eye, r * 0.2)
			_flat(cx, _hpoly(c, r, a, [Vector2(0.38, -0.24), Vector2(0.85, -0.2), Vector2(0.8, -0.06), Vector2(0.42, -0.08)]), Color(0.95, 0.12, 0.08))
			for k in 3:
				_line(cx, _hp(c, r, a, Vector2(-0.6 + k * 0.3, -0.85 + absf(k - 1) * 0.08)), _hp(c, r, a, Vector2(-0.5 + k * 0.3, -0.45)), skin.darkened(0.3), 1.0)
		"eyepatch":
			_flat(cx, _hpoly(c, r, a, [Vector2(0.45, -0.3), Vector2(0.75, -0.3), Vector2(0.72, 0.0), Vector2(0.48, 0.0)]), Color(0.05, 0.05, 0.06))
			_line(cx, _hp(c, r, a, Vector2(0.45, -0.2)), _hp(c, r, a, Vector2(-0.8, -0.45)), Color(0.05, 0.05, 0.06), 1.0)
		"reign":
			_part(cx, _hpoly(c, r, a, REIGN_MASK), mask, ld, eye, r * 0.4)
		"shades":
			_part(cx, _hpoly(c, r, a, SHADES), _col(look, "mask", Color(0.06, 0.06, 0.08)), ld, eye, r * 0.3)
			_line(cx, _hp(c, r, a, Vector2(0.55, -0.28)), _hp(c, r, a, Vector2(0.75, -0.27)), Color(0.75, 0.85, 1.0, 0.8), 1.0)
			_line(cx, _hp(c, r, a, Vector2(0.3, -0.25)), _hp(c, r, a, Vector2(-0.3, -0.2)), Color(0.06, 0.06, 0.08), 1.0)

	# Hats.
	var hat_col := _col(look, "hat_color", Color(0.2, 0.2, 0.22))
	match str(look.get("hat", "")):
		"beanie":
			_part(cx, _hpoly(c, r, a, BEANIE), hat_col, ld, c, r)
			_line(cx, _hp(c, r, a, Vector2(-0.95, -0.25)), _hp(c, r, a, Vector2(0.88, -0.45)), _shadow(hat_col), 2.0)
		"cap":
			_part(cx, _hpoly(c, r, a, CAP), hat_col, ld, c, r)
		"army":
			_part(cx, _hpoly(c, r, a, ARMY), hat_col, ld, c, r)
			_line(cx, _hp(c, r, a, Vector2(-0.9, -0.42)), _hp(c, r, a, Vector2(0.9, -0.55)), _shadow(hat_col).darkened(0.2), 1.0)

	# Full-head coverings.
	match style:
		"cowl":
			_part(cx, _hpoly(c, r, a, COWL), mask, ld, c, r)
			_flat(cx, _hpoly(c, r, a, COWL_LENS), _col(look, "lens", Color(0.98, 0.96, 0.88)))
			var ear := _hp(c, r, a, Vector2(-0.22, -0.02))
			_part(cx, _hpoly(ear, r, a, EAR_BOLT), _col(look, "ear_color", _col(look, "accent", Color.GOLD)), ld, ear, r * 0.3)
		"jay":
			_part(cx, _hpoly(c, r, a, JAY_DOME), Color(0.72, 0.74, 0.78), ld, c, r)
			_part(cx, _hpoly(c, r, a, JAY_WING), Color(0.85, 0.86, 0.9), ld, c, r * 0.4)
		"hood":
			var hood2 := _col(look, "hood", Color(0.2, 0.45, 0.2))
			var sh := hood2.darkened(0.75)
			sh.a = 0.85
			_flat(cx, _hpoly(c, r, a, HOOD_SHADOW), sh)
			_flat(cx, _circle(eye, 1.0, 4), _col(look, "glow_eyes", Color(0.85, 0.85, 0.8)))
			_part(cx, _hpoly(c, r, a, HOOD_FRONT), hood2, ld, c, r)
		"helmet":
			var hm := _hpoly(c, r, a, HELMET)
			_part(cx, hm, mask, ld, c, r)
			var fd := Vector2(cos(a), sin(a))
			for p in _clip(hm, c + fd * r * 0.12, fd):
				_part(cx, p, _col(look, "mask2", Color(0.95, 0.45, 0.08)), ld, c + fd * r * 0.7, r * 0.3)
			_flat(cx, _hpoly(c, r, a, [Vector2(-0.2, -0.27), Vector2(0.1, -0.28), Vector2(0.1, -0.15), Vector2(-0.18, -0.13)]), Color(0.03, 0.03, 0.04))
			_line(cx, _hp(c, r, a, Vector2(-0.2, -1.0)), _hp(c, r, a, Vector2(-0.4, 0.6)), _shadow(mask), 1.0)
		"visor", "prometheus":
			var hood3 := _col(look, "hood", Color(0.3, 0.3, 0.32))
			var hm2 := _hpoly(c, r, a, HELMET)
			_part(cx, hm2, mask, ld, c, r)
			if style == "prometheus":
				var fd2 := Vector2(cos(a), sin(a))
				for p in _clip(hm2, c + fd2 * r * 0.25, fd2):
					_part(cx, p, Color(0.62, 0.64, 0.68), ld, c + fd2 * r * 0.6, r * 0.3)
				for k in 4:
					var y := -0.05 + k * 0.17
					_line(cx, _hp(c, r, a, Vector2(0.45, y)), _hp(c, r, a, Vector2(0.92, y)), Color(0.2, 0.2, 0.22), 1.0)
			var visor := [Vector2(0.2, -0.33), Vector2(0.96, -0.3), Vector2(0.97, -0.12), Vector2(0.22, -0.1)]
			_flat(cx, _hpoly(c, r, a, visor), _col(look, "lens", Color(0.85, 0.9, 1.0)))
			_part(cx, _hpoly(c, r, a, HOOD_FRONT), hood3, ld, c, r)
	# Glowing eyes (Reign, Reverse-Flash lenses, Spectre...).
	var glow = look.get("glow_eyes")
	if glow is Color:
		var gp := eye
		var gc: Color = glow
		var halo := gc
		halo.a = 0.35
		_flat(cx, _circle(gp, 3.6, 7), halo)
		_flat(cx, _circle(gp, 1.7, 6), gc.lightened(0.4))


static func _tv_head(cx: Dictionary, c: Vector2, r: float, a: float, look: Dictionary) -> void:
	var box := _hpoly(c, r, a, TV_BOX)
	_part(cx, box, _col(look, "mask", Color(0.32, 0.24, 0.2)), cx["light"], c, r)
	if cx["o"].has("solid"):
		return
	var t := float(cx["o"].get("time", 0.0))
	var scr := _hpoly(c, r, a, [Vector2(-0.6, -0.85), Vector2(0.95, -0.85), Vector2(0.95, 0.5), Vector2(-0.6, 0.5)])
	var sc := _col(look, "lens", Color(0.4, 1.0, 0.75))
	_flat(cx, scr, sc.darkened(0.3 + 0.2 * sin(t * 9.0)))
	for k in 3:
		var y := -0.6 + k * 0.4 + fmod(t * 2.0, 0.4)
		_line(cx, _hp(c, r, a, Vector2(-0.55, y)), _hp(c, r, a, Vector2(0.9, y)), sc.lightened(0.3), 1.0)
	_flat(cx, _circle(_hp(c, r, a, Vector2(-0.88, 0.2)), r * 0.12, 5), Color(0.8, 0.2, 0.2))
	_line(cx, _hp(c, r, a, Vector2(-0.3, -1.15)), _hp(c, r, a, Vector2(-0.8, -1.9)), OUTLINE, 1.0)
	_line(cx, _hp(c, r, a, Vector2(0.3, -1.15)), _hp(c, r, a, Vector2(0.75, -1.85)), OUTLINE, 1.0)


static func _hair(cx: Dictionary, poly: PackedVector2Array, col: Color, c: Vector2, r: float) -> void:
	_part(cx, poly, col, cx["light"], c, r)
	if cx["o"].has("solid") or poly.size() < 6:
		return
	var hl := _hilite(col)
	hl.a = 0.8
	_line(cx, poly[2].lerp(poly[3], 0.5), poly[4].lerp(poly[5], 0.5), hl, 1.0)


## Portrait bust helper used by menus: draws the fighter scaled into a box.
static func draw_portrait(ci: CanvasItem, rect: Rect2, look: Dictionary, H: float, facing: int = 1, o: Dictionary = {}) -> void:
	var scale := rect.size.y / (H * 0.36)
	var origin := rect.position + Vector2(rect.size.x * 0.5 - 0.04 * H * scale * facing, rect.size.y * 2.62)
	ci.draw_set_transform(origin, 0.0, Vector2(scale, scale))
	draw(ci, Vector2.ZERO, facing, Poses.get_pose("idle"), look, H, o)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
