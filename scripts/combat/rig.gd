extends RefCounted
## Procedural pixel-art fighter renderer.
##
## Fighters are drawn from a pose (see poses.gd) and a "look" (costume colours and
## features from the fighter JSON). Everything renders at the 640x360 base
## resolution and is upscaled with nearest-neighbour filtering, which produces
## crisp, chunky pixel art with an outline, a shadow tone and a lit tone.

const Poses = preload("res://scripts/combat/poses.gd")
const OUTLINE := Color(0.05, 0.04, 0.08)
const WHITE := Color(1, 1, 1)


static func _ik(a: Vector2, target: Vector2, l1: float, l2: float, bend: float) -> Array:
	var d := target - a
	var dist := d.length()
	var dir := d / dist if dist > 0.001 else Vector2(0, 1)
	dist = clampf(dist, absf(l1 - l2) + 0.5, l1 + l2 - 0.01)
	var x := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - x * x))
	var perp := Vector2(-dir.y, dir.x)
	return [a + dir * x + perp * h * bend, a + dir * dist]


## Forward/inverse kinematics for a pose. Returns joint positions in LOCAL space
## (facing right, origin at the feet anchor) plus torso direction vectors.
static func solve(pose: Dictionary, H: float, look: Dictionary, sway: float = 0.0) -> Dictionary:
	var bulk: float = look.get("bulk", 1.0)
	var belly: float = look.get("belly", 0.0)
	var hip: Vector2 = pose["hip"] * H
	var t := deg_to_rad(pose["t"])
	var tdir := Vector2(sin(t), -cos(t))
	var tn := Vector2(cos(t), sin(t))
	var sh := hip + tdir * 0.265 * H
	var neck := hip + tdir * 0.30 * H
	var ht := deg_to_rad(pose["t"] + pose["h"])
	var head := neck + Vector2(sin(ht), -cos(ht)) * 0.085 * H
	var s_f := sh + tn * 0.02 * H * bulk
	var s_b := sh - tn * 0.03 * H * bulk + Vector2(0, 0.006 * H)
	var st: float = pose["stretch"]
	var fh: Vector2 = pose["fh"]
	var bh: Vector2 = pose["bh"]
	var ff: Vector2 = pose["ff"]
	var bf: Vector2 = pose["bf"]
	var af := _ik(s_f, s_f + fh * H, 0.17 * H * st, 0.16 * H * st, pose["fe"])
	var ab := _ik(s_b, s_b + bh * H, 0.17 * H, 0.16 * H, pose["be"])
	var hp_f := hip + Vector2(0.025 * H * bulk, 0)
	var hp_b := hip - Vector2(0.025 * H * bulk, 0)
	var lf := _ik(hp_f, ff * H, 0.25 * H, 0.25 * H, -1.0)
	var lb := _ik(hp_b, bf * H, 0.25 * H, 0.25 * H, -1.0)
	var kf: Vector2 = lf[0]
	var ftf: Vector2 = lf[1]
	var kb: Vector2 = lb[0]
	var ftb: Vector2 = lb[1]
	var sdf := (ftf - kf).normalized()
	var sdb := (ftb - kb).normalized()

	var cw := 0.165 * H * bulk
	var ww := 0.12 * H * bulk
	var torso := PackedVector2Array([
		sh - tn * cw * 0.5,
		sh + tdir * 0.035 * H - tn * cw * 0.2,
		sh + tdir * 0.035 * H + tn * cw * 0.25,
		sh + tn * cw * 0.55,
		hip.lerp(sh, 0.68) + tn * cw * 0.62,
		hip + tdir * 0.09 * H + tn * ww * (0.5 + belly),
		hip + tn * ww * 0.56 - tdir * 0.035 * H,
		hip - tn * ww * 0.56 - tdir * 0.035 * H,
		hip + tdir * 0.12 * H - tn * ww * 0.5,
	])
	var j := {
		"hip": hip, "sh": sh, "neck": neck, "head": head,
		"sf": s_f, "sb": s_b, "ef": af[0], "hf": af[1], "eb": ab[0], "hb": ab[1],
		"hpf": hp_f, "hpb": hp_b, "kf": kf, "ftf": ftf, "kb": kb, "ftb": ftb,
		"tof": ftf + Vector2(sdf.y, -sdf.x) * 0.075 * H,
		"tob": ftb + Vector2(sdb.y, -sdb.x) * 0.075 * H,
		"chest": hip.lerp(sh, 0.68) + tn * cw * 0.12,
		"beltf": hip + tdir * 0.03 * H + tn * ww * 0.58,
		"beltb": hip + tdir * 0.03 * H - tn * ww * 0.58,
		"torso": torso,
	}
	if look.has("cape"):
		var down := (-tdir).lerp(Vector2(0, 1), 0.5).normalized()
		var back := Vector2(-down.y, down.x) * -1.0
		if back.x > 0:
			back = -back
		j["cape"] = PackedVector2Array([
			s_b + tdir * 0.02 * H,
			sh + tdir * 0.035 * H + tn * 0.02 * H,
			hip + down * 0.20 * H + back * 0.02 * H,
			hip + down * (0.26 - sway * 0.08) * H + back * (0.16 + sway * 0.16) * H,
			s_b + back * 0.05 * H,
		])
	var rot: float = pose["rot"]
	if absf(rot) > 0.01:
		var r := deg_to_rad(rot)
		for k in j.keys():
			var v = j[k]
			if v is Vector2:
				j[k] = hip + (v - hip).rotated(r)
			elif v is PackedVector2Array:
				var arr: PackedVector2Array = v
				for i in arr.size():
					arr[i] = hip + (arr[i] - hip).rotated(r)
				j[k] = arr
		tdir = tdir.rotated(r)
		tn = tn.rotated(r)
	j["tdir"] = tdir
	j["tn"] = tn
	return j


static func _c(col: Color, o: Dictionary) -> Color:
	if o.has("solid"):
		return o["solid"]
	var c := col
	var fl: float = o.get("flash", 0.0)
	if fl > 0.0:
		c = c.lerp(WHITE, fl)
	if o.has("tint"):
		var tint: Color = o["tint"]
		c = c.lerp(Color(tint.r, tint.g, tint.b), tint.a)
	c.a *= float(o.get("alpha", 1.0))
	return c


static func _capsule(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	var r := w * 0.5
	if d.length() > 0.01:
		var n := Vector2(-d.y, d.x).normalized() * r
		ci.draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), col)
	ci.draw_circle(a, r, col)
	ci.draw_circle(b, r, col)


static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color, o: Dictionary, metal := false) -> void:
	_capsule(ci, a, b, w + 2.5, _c(o.get("outline", OUTLINE), o))
	_capsule(ci, a, b, w, _c(col.darkened(0.38), o))
	var off := Vector2(-0.16, -0.2) * w
	_capsule(ci, a + off, b + off, w * 0.52, _c(col, o))
	if metal:
		_capsule(ci, a + off * 1.4, b + off * 1.4, maxf(1.0, w * 0.12), _c(col.lightened(0.55), o))


static func _box(ci: CanvasItem, p: Vector2, size: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(p, size).abs(), col)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, o: Dictionary, shade := true) -> void:
	var oc := _c(o.get("outline", OUTLINE), o)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_colored_polygon(pts, _c(col.darkened(0.38) if shade else col, o))
	if shade:
		var cen := Vector2.ZERO
		for p in pts:
			cen += p
		cen /= pts.size()
		var lit := PackedVector2Array()
		for p in pts:
			lit.append(cen + (p - cen) * 0.68 + Vector2(-1.5, -1.5))
		ci.draw_colored_polygon(lit, _c(col, o))
	ci.draw_polyline(closed, oc, 1.5)


static func _bolt(ci: CanvasItem, c: Vector2, s: float, f: int, col: Color, o: Dictionary) -> void:
	var raw := [Vector2(0.1, -1.0), Vector2(-0.45, 0.1), Vector2(-0.02, 0.05), Vector2(-0.15, 1.0), Vector2(0.45, -0.15), Vector2(0.02, -0.08)]
	var pts := PackedVector2Array()
	for p in raw:
		pts.append(c + Vector2(p.x * f, p.y) * s)
	ci.draw_colored_polygon(pts, _c(col, o))


static func _col(look: Dictionary, key: String, fallback: Color) -> Color:
	var v = look.get(key)
	return v if v is Color else fallback


## Draws a complete fighter. `origin` is the feet anchor in the canvas item's space.
static func draw(ci: CanvasItem, origin: Vector2, facing: int, pose: Dictionary, look: Dictionary, H: float, o: Dictionary = {}) -> void:
	var f := facing
	var j := solve(pose, H, look, float(o.get("sway", 0.0)))
	var tdir: Vector2 = j["tdir"]
	var tn: Vector2 = j["tn"]
	tdir.x *= f
	tn.x *= f
	for k in j.keys():
		var v = j[k]
		if v is Vector2 and k != "tdir" and k != "tn":
			j[k] = origin + Vector2(v.x * f, v.y)
		elif v is PackedVector2Array:
			var arr: PackedVector2Array = v
			for i in arr.size():
				arr[i] = origin + Vector2(arr[i].x * f, arr[i].y)
			j[k] = arr

	var bulk: float = look.get("bulk", 1.0)
	var metal: bool = look.get("metal", false)
	var skin := _col(look, "skin", Color(0.9, 0.7, 0.55))
	var suit := _col(look, "suit", Color(0.5, 0.5, 0.5))
	var arms := _col(look, "arms", suit)
	var forearm := _col(look, "forearm", arms)
	var gloves := _col(look, "gloves", forearm)
	var legs := _col(look, "legs", suit)
	var shins := _col(look, "shins", legs)
	var boots := _col(look, "boots", shins)
	var wu := 0.07 * H * bulk
	var wl := 0.06 * H * bulk
	var wt := 0.095 * H * bulk
	var ws := 0.075 * H * bulk
	var back_dark := 0.22

	# Cape and long hair sit behind everything.
	if j.has("cape"):
		_poly(ci, j["cape"], _col(look, "cape", Color.RED), o)
	if look.get("head", "") == "long" or look.get("head", "") == "shaggy":
		var hr := 0.068 * H
		var hc: Vector2 = j["head"]
		var hair := _col(look, "hair", Color.BLACK)
		var lng := 2.4 if look.get("head") == "long" else 1.3
		_limb(ci, hc + Vector2(-0.3 * hr * f, -0.2 * hr), hc + Vector2(-0.55 * hr * f, lng * hr), hr * 1.25, hair, o)

	# Back arm and leg (slightly darker for depth).
	_limb(ci, j["sb"], j["eb"], wu, arms.darkened(back_dark), o, metal)
	_limb(ci, j["eb"], j["hb"], wl, forearm.darkened(back_dark), o, metal)
	_capsule(ci, j["hb"], j["hb"], wl * 1.05 + 2.5, _c(o.get("outline", OUTLINE), o))
	_capsule(ci, j["hb"], j["hb"], wl * 1.05, _c(gloves.darkened(back_dark + 0.15), o))
	_leg(ci, j["hpb"], j["kb"], j["ftb"], j["tob"], wt, ws, legs.darkened(back_dark), shins.darkened(back_dark), boots.darkened(back_dark), o, metal)

	# Quiver on the back.
	if look.get("prop", "") == "bow":
		var qc: Vector2 = j["sh"].lerp(j["hip"], 0.3) - tn * 0.1 * H * bulk
		var qa := tdir.rotated(deg_to_rad(-25 * f))
		var qt := qc + qa * 0.15 * H
		var qb := qc - qa * 0.1 * H
		_limb(ci, qb, qt, 0.05 * H, Color(0.35, 0.22, 0.12), o)
		for i in 3:
			var tip := qt + qa * 0.035 * H + Vector2((i - 1) * 2.5, 0)
			ci.draw_line(qt, tip, _c(Color(0.75, 0.15, 0.1), o), 2.0)

	# Torso.
	_poly(ci, j["torso"], suit, o)
	_torso_details(ci, j, look, f, H, o)
	# Neck.
	var neck_col := skin
	if look.get("head", "") == "cowl":
		neck_col = _col(look, "mask", suit)
	elif look.get("head", "") == "hood":
		neck_col = _col(look, "hood", suit).darkened(0.2)
	_limb(ci, j["sh"] + tdir * 0.02 * H, j["neck"], 0.055 * H, neck_col, o, metal)

	# Front leg.
	_leg(ci, j["hpf"], j["kf"], j["ftf"], j["tof"], wt, ws, legs, shins, boots, o, metal)

	# Head.
	_head(ci, j["head"], 0.068 * H, f, look, o, metal)

	# Front arm.
	_limb(ci, j["sf"], j["ef"], wu, arms, o, metal)
	_limb(ci, j["ef"], j["hf"], wl, forearm, o, metal)
	var stripe = look.get("stripe")
	if stripe is Color:
		ci.draw_line(j["ef"].lerp(j["hf"], 0.15), j["ef"].lerp(j["hf"], 0.8), _c(stripe, o), 2.0)
		ci.draw_line(j["sf"].lerp(j["ef"], 0.2), j["sf"].lerp(j["ef"], 0.85), _c(stripe, o), 2.0)
	_capsule(ci, j["hf"], j["hf"], wl * 1.1 + 2.5, _c(o.get("outline", OUTLINE), o))
	_capsule(ci, j["hf"], j["hf"], wl * 1.1, _c(gloves.darkened(0.15), o))
	ci.draw_circle(j["hf"] + Vector2(-0.6, -0.8), wl * 0.32, _c(gloves.lightened(0.15), o))
	if look.get("pads", false):
		ci.draw_circle(j["sf"], wu * 0.75 + 1.5, _c(OUTLINE, o))
		ci.draw_circle(j["sf"], wu * 0.75, _c(Color(0.32, 0.33, 0.36), o))
		ci.draw_circle(j["sf"] + Vector2(-1, -1.5), wu * 0.35, _c(Color(0.48, 0.5, 0.54), o))

	_props(ci, j, look, pose, f, H, o)


static func _leg(ci: CanvasItem, hp: Vector2, k: Vector2, ft: Vector2, toe: Vector2, wt: float, ws: float, legs: Color, shins: Color, boots: Color, o: Dictionary, metal: bool) -> void:
	_limb(ci, hp, k, wt, legs, o, metal)
	_limb(ci, k, ft, ws, shins, o, metal)
	var boot_top := k.lerp(ft, 0.5)
	if boots != shins:
		_limb(ci, boot_top, ft, ws * 1.08, boots, o)
	_limb(ci, ft, toe, ws * 0.62, boots, o)


static func _torso_details(ci: CanvasItem, j: Dictionary, look: Dictionary, f: int, H: float, o: Dictionary) -> void:
	var belt = look.get("belt")
	if belt is Color:
		ci.draw_line(j["beltb"], j["beltf"], _c(OUTLINE, o), 0.035 * H + 2.0)
		ci.draw_line(j["beltb"], j["beltf"], _c(belt, o), 0.035 * H)
	var chest: Vector2 = j["chest"]
	var s := 0.05 * H
	match look.get("emblem", ""):
		"bolt":
			ci.draw_circle(chest, s * 1.05 + 1.5, _c(_col(look, "accent", Color.GOLD), o))
			ci.draw_circle(chest, s, _c(Color(0.97, 0.95, 0.9), o))
			_bolt(ci, chest, s * 0.95, f, _col(look, "accent", Color.GOLD), o)
		"shield":
			var raw := [Vector2(-1, -0.65), Vector2(1, -0.65), Vector2(1.2, -0.15), Vector2(0, 1.0), Vector2(-1.2, -0.15)]
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			for p in raw:
				outer.append(chest + Vector2(p.x * f, p.y) * s * 1.1)
				inner.append(chest + Vector2(p.x * f, p.y) * s * 0.75)
			ci.draw_colored_polygon(outer, _c(_col(look, "accent", Color.GOLD), o))
			ci.draw_colored_polygon(inner, _c(Color(0.8, 0.08, 0.1), o))
			var sz := PackedVector2Array([chest + Vector2(0.4 * f, -0.4) * s, chest + Vector2(-0.35 * f, -0.3) * s, chest + Vector2(0.3 * f, 0.1) * s, chest + Vector2(-0.3 * f, 0.4) * s])
			ci.draw_polyline(sz, _c(_col(look, "accent", Color.GOLD), o), 1.5)
		"xstraps":
			var tor: PackedVector2Array = j["torso"]
			var red := _col(look, "accent", Color.RED)
			for pair in [[tor[1], tor[6]], [tor[2], tor[7]]]:
				ci.draw_line(pair[0], pair[1], _c(OUTLINE, o), 0.04 * H + 2.0)
				ci.draw_line(pair[0], pair[1], _c(red, o), 0.04 * H)
		"strap":
			var tor2: PackedVector2Array = j["torso"]
			ci.draw_line(tor2[2], tor2[7], _c(OUTLINE, o), 0.03 * H + 2.0)
			ci.draw_line(tor2[2], tor2[7], _c(Color(0.32, 0.2, 0.1), o), 0.03 * H)
		"zip":
			var tor3: PackedVector2Array = j["torso"]
			ci.draw_line(tor3[2].lerp(tor3[3], 0.5), tor3[6], _c(Color(0.75, 0.75, 0.8), o), 1.0)
			ci.draw_line(tor3[3], tor3[4], _c(Color(0.25, 0.25, 0.3), o), 2.0)
		"vest":
			var tor4: PackedVector2Array = j["torso"]
			var c4 := Color(0.85, 0.85, 0.85)
			ci.draw_line(tor4[2], tor4[5], _c(c4, o), 1.5)
			_box(ci, chest + Vector2(-0.2 * s * f, -0.5 * s), Vector2(1.0 * s * f, 0.7 * s), _c(Color(0.2, 0.21, 0.24), o))
			_box(ci, chest + Vector2(-0.1 * s * f, -0.4 * s), Vector2(0.8 * s * f, 0.12 * s), _c(c4, o))
		"piping":
			var tor5: PackedVector2Array = j["torso"]
			var pc := _col(look, "accent", Color(0.3, 0.6, 1.0))
			ci.draw_line(tor5[2], tor5[4], _c(pc, o), 2.0)
			ci.draw_line(tor5[4], tor5[6], _c(pc, o), 2.0)
		"tv":
			_box(ci, chest + Vector2(-0.6 * s * f, -0.55 * s) - Vector2(1, 1), Vector2(1.2 * s * f, 0.95 * s) + Vector2(2 * f, 2), _c(OUTLINE, o))
			_box(ci, chest + Vector2(-0.6 * s * f, -0.55 * s), Vector2(1.2 * s * f, 0.95 * s), _c(Color(0.3, 0.9, 0.7), o))
			ci.draw_line(chest + Vector2(-0.3 * s * f, -0.55 * s), chest + Vector2(-0.6 * s * f, -1.0 * s), _c(OUTLINE, o), 1.0)
			ci.draw_line(chest + Vector2(0.2 * s * f, -0.55 * s), chest + Vector2(0.5 * s * f, -1.0 * s), _c(OUTLINE, o), 1.0)


static func _head(ci: CanvasItem, c: Vector2, r: float, f: int, look: Dictionary, o: Dictionary, metal: bool) -> void:
	var skin := _col(look, "skin", Color(0.9, 0.7, 0.55))
	var hair := _col(look, "hair", Color(0.15, 0.1, 0.05))
	var style: String = look.get("head", "short")
	var face: String = look.get("face", "")
	var oc := _c(o.get("outline", OUTLINE), o)
	var eye_col := _col(look, "eyes", Color(0.08, 0.06, 0.1))
	ci.draw_circle(c, r + 1.5, oc)
	if style == "hood":
		var hood := _col(look, "hood", Color(0.2, 0.45, 0.2))
		var hc := c + Vector2(-0.16 * r * f, -0.1 * r)
		var peak := PackedVector2Array([hc + Vector2(-0.9 * r * f, -0.55 * r), hc + Vector2(-0.2 * r * f, -1.45 * r), hc + Vector2(0.5 * r * f, -1.0 * r)])
		ci.draw_colored_polygon(peak, oc)
		ci.draw_circle(hc, r * 1.22 + 1.5, oc)
		ci.draw_circle(hc, r * 1.22, _c(hood.darkened(0.35), o))
		ci.draw_circle(hc + Vector2(-0.2 * r * f, -0.2 * r), r * 0.95, _c(hood, o))
		ci.draw_circle(c + Vector2(0.38 * r * f, 0.1 * r), r * 0.68, _c(hood.darkened(0.7), o))
		ci.draw_circle(c + Vector2(0.48 * r * f, 0.32 * r), r * 0.46, _c(skin.darkened(0.15), o))
		_box(ci, c + Vector2(0.2 * r * f, -0.18 * r), Vector2(0.75 * r * f, 0.26 * r), _c(_col(look, "mask", Color(0.1, 0.18, 0.1)), o))
		_box(ci, c + Vector2(0.6 * r * f, -0.1 * r), Vector2(0.18 * r * f, 0.12 * r), _c(Color(0.9, 0.9, 0.85), o))
		_box(ci, c + Vector2(0.45 * r * f, 0.5 * r), Vector2(0.4 * r * f, 0.28 * r), _c(hair, o))
		return
	if style == "cowl":
		var m := _col(look, "mask", Color(0.75, 0.1, 0.1))
		ci.draw_circle(c, r, _c(m.darkened(0.38), o))
		ci.draw_circle(c + Vector2(-0.12 * r * f, -0.14 * r), r * 0.8, _c(m, o))
		ci.draw_circle(c + Vector2(0.42 * r * f, 0.48 * r), r * 0.44, _c(skin, o))
		_box(ci, c + Vector2(0.18 * r * f, -0.26 * r), Vector2(0.7 * r * f, 0.22 * r), _c(Color(0.98, 0.95, 0.85), o))
		_bolt(ci, c + Vector2(-0.3 * r * f, -0.1 * r), r * 0.55, f, _col(look, "accent", Color.GOLD), o)
		return
	# Base head with a lit face circle.
	ci.draw_circle(c, r, _c(skin.darkened(0.3), o))
	ci.draw_circle(c + Vector2(0.1 * r * f, -0.05 * r), r * 0.86, _c(skin, o))
	if metal:
		ci.draw_circle(c + Vector2(-0.2 * r * f, -0.4 * r), r * 0.25, _c(skin.lightened(0.5), o))
	match style:
		"short", "long", "shaggy":
			var hc2 := c + Vector2(-0.12 * r * f, -0.2 * r)
			var hr := r * (0.9 if style != "shaggy" else 1.0)
			ci.draw_circle(hc2, hr, _c(hair.darkened(0.25), o))
			ci.draw_circle(hc2 + Vector2(-0.1 * r * f, -0.12 * r), hr * 0.75, _c(hair, o))
			ci.draw_circle(c + Vector2(0.3 * r * f, 0.22 * r), r * 0.7, _c(skin, o))
			if style == "long":
				_box(ci, c + Vector2(0.15 * r * f, -0.9 * r), Vector2(0.75 * r * f, 0.4 * r), _c(hair, o))
		"bald":
			ci.draw_line(c + Vector2(0.15 * r * f, -0.35 * r), c + Vector2(0.95 * r * f, -0.25 * r), _c(skin.darkened(0.45), o), 2.0)
	# Eyes and mouth.
	var eye := c + Vector2(0.55 * r * f, -0.12 * r)
	match face:
		"domino":
			_box(ci, c + Vector2(0.15 * r * f, -0.3 * r), Vector2(0.88 * r * f, 0.32 * r), _c(_col(look, "mask", Color(0.05, 0.05, 0.07)), o))
			_box(ci, eye, Vector2(2 * f, 2), _c(Color(0.9, 0.9, 0.95), o))
		"goggles":
			_box(ci, c + Vector2(-0.3 * r * f, -0.34 * r), Vector2(1.32 * r * f, 0.36 * r), _c(Color(0.08, 0.08, 0.12), o))
			_box(ci, c + Vector2(0.35 * r * f, -0.3 * r), Vector2(0.55 * r * f, 0.22 * r), _c(_col(look, "accent", Color(0.3, 0.6, 1)), o))
		"bandana":
			_box(ci, eye, Vector2(2 * f, 2), _c(eye_col, o))
			_box(ci, c + Vector2(-0.1 * r * f, 0.12 * r), Vector2(1.1 * r * f, 0.6 * r), _c(_col(look, "mask", Color(0.2, 0.2, 0.22)), o))
		"glasses":
			_box(ci, c + Vector2(0.3 * r * f, -0.3 * r), Vector2(0.6 * r * f, 0.36 * r), _c(OUTLINE, o))
			_box(ci, c + Vector2(0.38 * r * f, -0.24 * r), Vector2(0.44 * r * f, 0.24 * r), _c(Color(0.75, 0.9, 1.0), o))
			ci.draw_line(c + Vector2(0.5 * r * f, 0.45 * r), c + Vector2(0.85 * r * f, 0.4 * r), _c(skin.darkened(0.5), o), 1.0)
		"martian":
			_box(ci, c + Vector2(0.35 * r * f, -0.22 * r), Vector2(0.5 * r * f, 0.22 * r), _c(Color(0.95, 0.15, 0.1), o))
			ci.draw_line(c + Vector2(0.2 * r * f, -0.4 * r), c + Vector2(1.0 * r * f, -0.32 * r), _c(skin.darkened(0.55), o), 2.0)
		_:
			_box(ci, eye, Vector2(2 * f, 2), _c(eye_col, o))
			ci.draw_line(c + Vector2(0.4 * r * f, -0.32 * r), c + Vector2(0.9 * r * f, -0.3 * r), _c(hair.darkened(0.3), o), 1.0)
			ci.draw_line(c + Vector2(0.55 * r * f, 0.45 * r), c + Vector2(0.85 * r * f, 0.42 * r), _c(skin.darkened(0.45), o), 1.0)
	if look.get("hat", "") == "cap":
		var capc := _col(look, "hat_color", Color(0.1, 0.1, 0.12))
		var pts := PackedVector2Array()
		for i in 9:
			var a := PI + PI * float(i) / 8.0
			pts.append(c + Vector2(0, -0.18 * r) + Vector2(cos(a) * r * 1.02, sin(a) * r * 0.95))
		ci.draw_colored_polygon(pts, _c(capc, o))
		ci.draw_polyline(pts, oc, 1.0)
		_box(ci, c + Vector2(0.55 * r * f, -0.32 * r), Vector2(0.75 * r * f, 0.2 * r), _c(capc.darkened(0.3), o))


static func _props(ci: CanvasItem, j: Dictionary, look: Dictionary, pose: Dictionary, f: int, H: float, o: Dictionary) -> void:
	var prop: String = look.get("prop", "")
	var hf: Vector2 = j["hf"]
	var aim: Vector2 = (hf - j["ef"]).normalized()
	if prop == "bow":
		var axis := Vector2(-aim.y, aim.x)
		if axis.y > 0:
			axis = -axis
		var top := hf + axis * 0.24 * H
		var bot := hf - axis * 0.24 * H
		var pts := PackedVector2Array()
		for i in 9:
			var k := float(i) / 8.0
			var bulge := sin(k * PI) * 0.07 * H
			pts.append(bot.lerp(top, k) + aim * bulge)
		ci.draw_polyline(pts, _c(OUTLINE, o), 4.0)
		ci.draw_polyline(pts, _c(Color(0.22, 0.24, 0.22), o), 2.0)
		var string_col := _c(Color(0.85, 0.85, 0.8, 0.9), o)
		if pose.get("draw", 0.0) > 0.5:
			ci.draw_line(top, j["hb"], string_col, 1.0)
			ci.draw_line(j["hb"], bot, string_col, 1.0)
			ci.draw_line(j["hb"], hf + aim * 0.1 * H, _c(Color(0.6, 0.45, 0.25), o), 1.0)
		else:
			ci.draw_line(top, bot, string_col, 1.0)
	elif prop == "remote":
		var rp := hf + aim * 0.02 * H
		ci.draw_line(rp, rp + aim * 0.07 * H, _c(OUTLINE, o), 6.0)
		ci.draw_line(rp, rp + aim * 0.07 * H, _c(Color(0.2, 0.2, 0.24), o), 4.0)
		ci.draw_circle(rp + aim * 0.055 * H, 1.2, _c(Color(1, 0.2, 0.2), o))
	if pose.get("gun", 0.0) > 0.5:
		for hand in ["hf", "hb"]:
			var hp: Vector2 = j[hand]
			ci.draw_line(hp, hp + aim * 0.07 * H, _c(OUTLINE, o), 5.0)
			ci.draw_line(hp, hp + aim * 0.065 * H, _c(Color(0.25, 0.25, 0.28), o), 3.0)


## Portrait bust helper used by menus: draws the fighter scaled into a box.
static func draw_portrait(ci: CanvasItem, rect: Rect2, look: Dictionary, H: float, facing: int = 1, o: Dictionary = {}) -> void:
	var scale := rect.size.y / (H * 0.36)
	var origin := rect.position + Vector2(rect.size.x * 0.5 - 0.04 * H * scale * facing, rect.size.y * 2.62)
	ci.draw_set_transform(origin, 0.0, Vector2(scale, scale))
	draw(ci, Vector2.ZERO, facing, Poses.get_pose("idle"), look, H, o)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
