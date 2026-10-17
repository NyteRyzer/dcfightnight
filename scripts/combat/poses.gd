extends RefCounted
## Pose library for the procedural fighter rig.
##
## All values are authored facing RIGHT, in units of the fighter's height (H).
##   hip      : hip position relative to the feet anchor (root)
##   t        : torso lean in degrees (positive = lean forward)
##   h        : extra head tilt in degrees
##   fh / bh  : front / back hand target, relative to the shoulder
##   ff / bf  : front / back foot target, relative to the root
##   rot      : whole-body rotation around the hip (flips, tumbles)
##   fe / be  : elbow bend direction override (-1 flips the elbow)
##   draw     : bow string drawn to the back hand (Green Arrow)
##   gun      : pistols visible in the hands (Wild Dog)
##   stretch  : front arm length multiplier (Martian Manhunter)

const BASE := {
	"hip": Vector2(0, -0.455), "t": 6.0, "h": 0.0,
	"fh": Vector2(0.15, -0.10), "bh": Vector2(0.07, -0.07),
	"ff": Vector2(0.11, 0), "bf": Vector2(-0.13, 0),
	"rot": 0.0, "fe": 1.0, "be": 1.0, "draw": 0.0, "gun": 0.0, "stretch": 1.0,
}

const LIB := {
	"idle": {},
	"idle2": {"hip": Vector2(0, -0.445), "t": 7.0, "fh": Vector2(0.15, -0.085), "bh": Vector2(0.07, -0.055)},
	"walk1": {"hip": Vector2(0, -0.46), "t": 8.0, "ff": Vector2(0.17, 0), "bf": Vector2(-0.15, 0)},
	"walk2": {"hip": Vector2(0, -0.48), "t": 8.0, "ff": Vector2(0.03, -0.07), "bf": Vector2(0.0, 0)},
	"walk3": {"hip": Vector2(0, -0.46), "t": 8.0, "ff": Vector2(-0.12, 0), "bf": Vector2(0.15, 0)},
	"walk4": {"hip": Vector2(0, -0.48), "t": 8.0, "ff": Vector2(0.0, 0), "bf": Vector2(0.03, -0.07)},
	"crouch": {"hip": Vector2(0, -0.29), "t": 18.0, "fh": Vector2(0.15, -0.07), "bh": Vector2(0.08, -0.04), "ff": Vector2(0.17, 0), "bf": Vector2(-0.15, 0)},
	"prejump": {"hip": Vector2(0, -0.36), "t": 12.0, "fh": Vector2(0.12, -0.02), "bh": Vector2(0.05, 0.0)},
	"jump": {"hip": Vector2(0, -0.52), "t": 4.0, "fh": Vector2(0.10, -0.20), "bh": Vector2(0.04, -0.17), "ff": Vector2(0.08, 0.0), "bf": Vector2(-0.06, 0.02)},
	"jump_tuck": {"hip": Vector2(0, -0.40), "t": 14.0, "fh": Vector2(0.15, -0.08), "bh": Vector2(0.08, -0.05), "ff": Vector2(0.14, -0.14), "bf": Vector2(-0.03, -0.08)},
	"land": {"hip": Vector2(0, -0.36), "t": 14.0},
	"block": {"hip": Vector2(-0.01, -0.45), "t": -4.0, "h": 4.0, "fh": Vector2(0.11, -0.17), "bh": Vector2(0.07, -0.15)},
	"block_low": {"hip": Vector2(0, -0.29), "t": 10.0, "fh": Vector2(0.14, -0.02), "bh": Vector2(0.10, 0.01), "ff": Vector2(0.17, 0), "bf": Vector2(-0.15, 0)},
	"hit": {"hip": Vector2(-0.04, -0.45), "t": -16.0, "h": -18.0, "fh": Vector2(0.03, 0.06), "bh": Vector2(-0.05, 0.09), "ff": Vector2(0.13, 0), "bf": Vector2(-0.16, 0)},
	"hit_low": {"hip": Vector2(-0.02, -0.41), "t": 24.0, "h": 14.0, "fh": Vector2(0.08, 0.13), "bh": Vector2(0.03, 0.14)},
	"hit_crouch": {"hip": Vector2(-0.03, -0.28), "t": -5.0, "h": -15.0, "fh": Vector2(0.02, 0.06), "bh": Vector2(-0.04, 0.08), "ff": Vector2(0.17, 0), "bf": Vector2(-0.16, 0)},
	"airhit": {"hip": Vector2(0, -0.32), "t": -40.0, "h": -20.0, "fh": Vector2(-0.06, -0.14), "bh": Vector2(-0.12, -0.10), "ff": Vector2(0.18, -0.10), "bf": Vector2(0.08, -0.02), "rot": -15.0},
	"knockdown": {"hip": Vector2(0, -0.075), "t": -86.0, "h": -4.0, "fh": Vector2(0.06, 0.07), "bh": Vector2(0.02, 0.08), "ff": Vector2(0.50, -0.02), "bf": Vector2(0.42, 0.0)},
	"getup": {"hip": Vector2(-0.02, -0.26), "t": 34.0, "h": 10.0, "fh": Vector2(0.10, 0.18), "bh": Vector2(0.04, 0.2), "ff": Vector2(0.14, 0), "bf": Vector2(-0.20, 0)},
	"dash": {"hip": Vector2(0.02, -0.43), "t": 22.0, "fh": Vector2(0.14, -0.04), "bh": Vector2(-0.06, 0.06), "ff": Vector2(0.18, -0.03), "bf": Vector2(-0.22, 0)},
	"backdash": {"hip": Vector2(-0.02, -0.46), "t": -10.0, "ff": Vector2(0.16, -0.05), "bf": Vector2(-0.10, 0)},
	"victory": {"hip": Vector2(0, -0.49), "t": -3.0, "h": -8.0, "fh": Vector2(0.07, -0.30), "bh": Vector2(0.03, 0.22), "ff": Vector2(0.10, 0), "bf": Vector2(-0.10, 0)},
	"victory_hips": {"hip": Vector2(0, -0.49), "t": -2.0, "h": -5.0, "fh": Vector2(0.05, 0.22), "bh": Vector2(-0.06, 0.22), "fe": -1.0, "be": -1.0, "ff": Vector2(0.11, 0), "bf": Vector2(-0.11, 0)},
	"victory_bow": {"hip": Vector2(0, -0.49), "t": -2.0, "h": -6.0, "fh": Vector2(0.10, -0.29), "bh": Vector2(0.03, 0.22), "ff": Vector2(0.12, 0), "bf": Vector2(-0.10, 0)},
	"victory_arms": {"hip": Vector2(0, -0.49), "t": -4.0, "h": -10.0, "fh": Vector2(0.14, -0.26), "bh": Vector2(-0.10, -0.26), "ff": Vector2(0.14, 0), "bf": Vector2(-0.14, 0)},
	"defeat": {"hip": Vector2(0, -0.27), "t": 38.0, "h": 28.0, "fh": Vector2(0.06, 0.2), "bh": Vector2(0.0, 0.21), "ff": Vector2(0.16, 0), "bf": Vector2(-0.24, 0)},
	"super": {"hip": Vector2(0, -0.47), "t": -8.0, "h": -12.0, "fh": Vector2(0.12, 0.13), "bh": Vector2(0.03, 0.15), "ff": Vector2(0.17, 0), "bf": Vector2(-0.19, 0)},
	"jab_w": {"t": 3.0, "fh": Vector2(0.09, -0.08)},
	"jab_s": {"t": 12.0, "fh": Vector2(0.33, -0.06), "bh": Vector2(0.06, -0.06), "ff": Vector2(0.15, 0)},
	"cross_w": {"t": 0.0, "bh": Vector2(-0.02, -0.06)},
	"cross_s": {"hip": Vector2(0.03, -0.45), "t": 18.0, "bh": Vector2(0.34, -0.06), "fh": Vector2(0.06, -0.03), "ff": Vector2(0.17, 0), "bf": Vector2(-0.13, 0)},
	"haymaker_w": {"hip": Vector2(-0.02, -0.45), "t": -10.0, "fh": Vector2(-0.08, -0.14), "bh": Vector2(0.10, -0.06)},
	"haymaker_s": {"hip": Vector2(0.05, -0.44), "t": 22.0, "fh": Vector2(0.30, -0.12), "bh": Vector2(-0.02, 0.0), "ff": Vector2(0.19, 0), "bf": Vector2(-0.13, 0)},
	"midkick_w": {"hip": Vector2(-0.02, -0.47), "t": -6.0, "ff": Vector2(0.12, -0.22), "bf": Vector2(-0.08, 0)},
	"midkick_s": {"hip": Vector2(-0.03, -0.48), "t": -12.0, "ff": Vector2(0.48, -0.34), "bf": Vector2(-0.08, 0), "fh": Vector2(0.10, -0.12), "bh": Vector2(0.0, -0.06)},
	"highkick_w": {"hip": Vector2(-0.03, -0.48), "t": -10.0, "ff": Vector2(0.10, -0.30), "bf": Vector2(-0.07, 0)},
	"highkick_s": {"hip": Vector2(-0.05, -0.49), "t": -22.0, "ff": Vector2(0.42, -0.72), "bf": Vector2(-0.06, 0), "fh": Vector2(0.06, -0.14), "bh": Vector2(-0.06, -0.04)},
	"low_punch_s": {"hip": Vector2(0.01, -0.29), "t": 22.0, "fh": Vector2(0.33, -0.01), "bh": Vector2(0.06, -0.03), "ff": Vector2(0.18, 0), "bf": Vector2(-0.15, 0)},
	"low_kick_s": {"hip": Vector2(-0.05, -0.27), "t": 26.0, "ff": Vector2(0.48, 0), "bf": Vector2(-0.14, 0), "fh": Vector2(0.10, 0.0), "bh": Vector2(0.05, 0.02)},
	"uppercut_w": {"hip": Vector2(0, -0.32), "t": 20.0, "fh": Vector2(0.05, 0.08), "bh": Vector2(0.08, -0.03), "ff": Vector2(0.17, 0), "bf": Vector2(-0.15, 0)},
	"uppercut_s": {"hip": Vector2(0.03, -0.50), "t": 8.0, "h": -10.0, "fh": Vector2(0.12, -0.32), "bh": Vector2(0.02, 0.05), "ff": Vector2(0.12, 0), "bf": Vector2(-0.14, 0)},
	"air_punch_s": {"hip": Vector2(0, -0.40), "t": 20.0, "fh": Vector2(0.30, 0.08), "bh": Vector2(0.05, -0.04), "ff": Vector2(0.12, -0.12), "bf": Vector2(-0.04, -0.06)},
	"air_kick_s": {"hip": Vector2(0, -0.45), "t": -14.0, "ff": Vector2(0.40, -0.10), "bf": Vector2(0.0, -0.17), "fh": Vector2(0.10, -0.12), "bh": Vector2(-0.04, -0.08)},
	"air_heavy_w": {"hip": Vector2(0, -0.42), "t": -12.0, "fh": Vector2(0.02, -0.31), "bh": Vector2(-0.02, -0.30), "ff": Vector2(0.12, -0.14), "bf": Vector2(-0.04, -0.08)},
	"air_heavy_s": {"hip": Vector2(0, -0.42), "t": 26.0, "fh": Vector2(0.25, 0.18), "bh": Vector2(0.22, 0.19), "ff": Vector2(0.10, -0.12), "bf": Vector2(-0.06, -0.05)},
	"throw_w": {"t": 14.0, "fh": Vector2(0.28, -0.03), "bh": Vector2(0.26, 0.0), "ff": Vector2(0.17, 0)},
	"throw_s": {"hip": Vector2(-0.03, -0.47), "t": -24.0, "h": -10.0, "fh": Vector2(-0.18, -0.26), "bh": Vector2(-0.20, -0.22), "ff": Vector2(0.15, 0), "bf": Vector2(-0.16, 0)},
	"cast_w": {"t": -6.0, "fh": Vector2(-0.02, -0.04), "bh": Vector2(-0.06, 0.0)},
	"cast_s": {"t": 12.0, "fh": Vector2(0.33, -0.07), "bh": Vector2(0.20, -0.05), "ff": Vector2(0.17, 0), "bf": Vector2(-0.15, 0)},
	"bow_w": {"t": 2.0, "fh": Vector2(0.32, -0.07), "bh": Vector2(0.16, -0.07), "draw": 1.0},
	"bow_s": {"t": 4.0, "fh": Vector2(0.33, -0.07), "bh": Vector2(-0.04, -0.09), "draw": 1.0, "ff": Vector2(0.15, 0)},
	"bow_up_w": {"t": -6.0, "h": -20.0, "fh": Vector2(0.20, -0.26), "bh": Vector2(0.12, -0.16), "draw": 1.0},
	"bow_up_s": {"t": -10.0, "h": -25.0, "fh": Vector2(0.20, -0.26), "bh": Vector2(-0.02, -0.08), "draw": 1.0},
	"beam_s": {"hip": Vector2(0, -0.46), "t": 6.0, "h": 12.0, "fh": Vector2(0.06, 0.17), "bh": Vector2(0.0, 0.18), "ff": Vector2(0.16, 0), "bf": Vector2(-0.17, 0)},
	"breath_s": {"t": 2.0, "h": -4.0, "fh": Vector2(-0.02, 0.15), "bh": Vector2(-0.06, 0.15), "ff": Vector2(0.18, 0), "bf": Vector2(-0.16, 0)},
	"scream_s": {"t": 12.0, "h": 6.0, "fh": Vector2(-0.13, 0.06), "bh": Vector2(-0.17, 0.07), "ff": Vector2(0.18, 0), "bf": Vector2(-0.17, 0)},
	"rush_s": {"hip": Vector2(0.02, -0.42), "t": 30.0, "fh": Vector2(0.33, -0.02), "bh": Vector2(-0.12, 0.10), "ff": Vector2(0.21, 0), "bf": Vector2(-0.30, 0)},
	"rush_s2": {"hip": Vector2(0.02, -0.42), "t": 28.0, "bh": Vector2(0.34, -0.04), "fh": Vector2(-0.04, 0.06), "ff": Vector2(0.21, 0), "bf": Vector2(-0.30, 0)},
	"fly_s": {"hip": Vector2(0, -0.30), "t": 76.0, "h": -60.0, "fh": Vector2(0.33, -0.02), "bh": Vector2(-0.10, 0.12), "ff": Vector2(-0.38, -0.30), "bf": Vector2(-0.40, -0.24)},
	"flip_kick": {"hip": Vector2(0, -0.45), "t": -20.0, "ff": Vector2(0.30, -0.80), "bf": Vector2(-0.05, -0.15), "rot": -40.0, "fh": Vector2(-0.10, 0.05), "bh": Vector2(-0.14, 0.02)},
	"counter_stance": {"hip": Vector2(-0.03, -0.43), "t": -6.0, "fh": Vector2(0.19, -0.13), "bh": Vector2(0.13, -0.11), "ff": Vector2(0.14, 0), "bf": Vector2(-0.17, 0)},
	"elbow_s": {"hip": Vector2(0.04, -0.45), "t": 20.0, "fh": Vector2(0.02, -0.12), "bh": Vector2(0.0, 0.05), "ff": Vector2(0.20, 0), "bf": Vector2(-0.13, 0)},
	"slam_w": {"hip": Vector2(0, -0.50), "t": -12.0, "h": -15.0, "fh": Vector2(0.06, -0.32), "bh": Vector2(0.02, -0.32), "ff": Vector2(0.13, 0), "bf": Vector2(-0.13, 0)},
	"slam_s": {"hip": Vector2(0.02, -0.30), "t": 44.0, "h": 10.0, "fh": Vector2(0.24, 0.25), "bh": Vector2(0.21, 0.26), "ff": Vector2(0.20, 0), "bf": Vector2(-0.19, 0)},
	"charge_s": {"hip": Vector2(0.02, -0.42), "t": 32.0, "h": -8.0, "fh": Vector2(0.10, 0.06), "bh": Vector2(0.04, 0.09), "ff": Vector2(0.21, 0), "bf": Vector2(-0.30, 0)},
	"ram_up_s": {"hip": Vector2(0, -0.52), "t": 6.0, "h": -20.0, "fh": Vector2(0.10, -0.30), "bh": Vector2(0.03, 0.02), "ff": Vector2(0.10, 0.0), "bf": Vector2(-0.08, 0.04)},
	"shoot_w": {"t": 0.0, "fh": Vector2(0.20, -0.02), "bh": Vector2(0.18, 0.0), "gun": 1.0},
	"shoot_s": {"t": 4.0, "fh": Vector2(0.33, -0.07), "bh": Vector2(0.31, -0.06), "gun": 1.0, "ff": Vector2(0.15, 0), "bf": Vector2(-0.15, 0)},
	"toss_w": {"t": -12.0, "bh": Vector2(-0.16, -0.20), "fh": Vector2(0.18, -0.10)},
	"toss_s": {"t": 16.0, "bh": Vector2(0.28, -0.18), "fh": Vector2(0.02, 0.04), "ff": Vector2(0.16, 0)},
	"stretch_s": {"t": 10.0, "fh": Vector2(0.62, -0.07), "bh": Vector2(0.05, -0.05), "stretch": 1.9, "ff": Vector2(0.17, 0), "bf": Vector2(-0.15, 0)},
	"point_s": {"t": 6.0, "fh": Vector2(0.32, -0.12), "bh": Vector2(0.05, -0.04), "ff": Vector2(0.14, 0)},
	"telepath_s": {"t": 0.0, "h": -6.0, "fh": Vector2(0.12, -0.27), "bh": Vector2(0.30, -0.08), "ff": Vector2(0.15, 0)},
	"dive_s": {"hip": Vector2(0, -0.45), "t": 35.0, "fh": Vector2(0.24, 0.16), "bh": Vector2(0.18, 0.18), "ff": Vector2(0.02, -0.04), "bf": Vector2(-0.14, -0.10)},
}

const VEC_KEYS := ["hip", "fh", "bh", "ff", "bf"]
const NUM_KEYS := ["t", "h", "rot", "draw", "gun", "stretch"]

static var _cache: Dictionary = {}


static func has_pose(pose_name: String) -> bool:
	return LIB.has(pose_name)


static func get_pose(pose_name: String) -> Dictionary:
	if _cache.has(pose_name):
		return _cache[pose_name]
	var p: Dictionary = BASE.duplicate()
	var src: Dictionary = LIB.get(pose_name, {})
	for k in src:
		p[k] = src[k]
	_cache[pose_name] = p
	return p


static func blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	k = clampf(k, 0.0, 1.0)
	if k <= 0.0:
		return a
	if k >= 1.0:
		return b
	var out := {}
	for key in VEC_KEYS:
		var va: Vector2 = a[key]
		var vb: Vector2 = b[key]
		out[key] = va.lerp(vb, k)
	for key in NUM_KEYS:
		out[key] = lerpf(a[key], b[key], k)
	var src := b if k > 0.5 else a
	out["fe"] = src["fe"]
	out["be"] = src["be"]
	return out


## Returns a pose cycling through `names`, `frames_per` frames per key, smoothly.
static func cycle(names: Array, frame: int, frames_per: int) -> Dictionary:
	var n := names.size()
	var pos := float(frame) / float(frames_per)
	var i := int(floorf(pos)) % n
	var j := (i + 1) % n
	return blend(get_pose(names[i]), get_pose(names[j]), pos - floorf(pos))


static func with_rot(p: Dictionary, extra_rot: float) -> Dictionary:
	var out := p.duplicate()
	out["rot"] = p["rot"] + extra_rot
	return out
