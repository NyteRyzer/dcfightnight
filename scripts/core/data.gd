extends Node
## Loads all data-driven content from res://data and builds merged fighter
## definitions (shared normals + per-fighter overrides and specials).

const Poses = preload("res://scripts/combat/poses.gd")

const SPECIAL_KEYS := ["S", "fS", "bS", "dS", "jS"]
const REQUIRED_MOVES := ["L", "M", "H", "cL", "cM", "cH", "jL", "jM", "jH", "throw", "S", "fS", "bS", "dS"]

var roster: Array = []
var locked: Dictionary = {}
var fighters: Dictionary = {}
var stages: Array = []
var stage_map: Dictionary = {}
var story: Dictionary = {}
var base_moves: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	base_moves = load_json("res://data/moves/base_normals.json")
	base_moves.erase("_doc")
	var r := load_json("res://data/roster.json")
	roster = r.get("fighters", [])
	locked = r.get("locked", {})
	fighters.clear()
	for id in roster:
		fighters[id] = build_fighter(load_json("res://data/fighters/%s.json" % id))
	var s := load_json("res://data/stages.json")
	stages = s.get("stages", [])
	stage_map.clear()
	for st in stages:
		stage_map[st["id"]] = st
	story = load_json("res://data/story.json")


func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Invalid JSON in %s" % path)
	return {}


func build_fighter(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	var moves := {}
	for key in base_moves:
		moves[key] = (base_moves[key] as Dictionary).duplicate(true)
	var own: Dictionary = src.get("moves", {})
	for key in own:
		if moves.has(key):
			var m: Dictionary = moves[key]
			for field in own[key]:
				m[field] = own[key][field]
		else:
			moves[key] = (own[key] as Dictionary).duplicate(true)
	for key in moves:
		var m: Dictionary = moves[key]
		m["id"] = key
		m["special"] = key in SPECIAL_KEYS or m.get("super", false) or m.get("hidden", false)
		if m["special"] and not m.has("chip"):
			m["chip"] = 0.2
		if m.get("super", false) and not m.has("meter"):
			m["meter"] = 1000
	d["moves"] = moves
	d["look"] = parse_look(src.get("look", {}))
	var alt: Dictionary = src.get("look", {}).duplicate()
	for k in src.get("alt_look", {}):
		alt[k] = src["alt_look"][k]
	d["alt_look"] = parse_look(alt)
	return d


func parse_look(raw: Dictionary) -> Dictionary:
	var out := {}
	for k in raw:
		var v = raw[k]
		if v is String and v.begins_with("#"):
			out[k] = Color.html(v)
		elif v == null:
			continue
		else:
			out[k] = v
	return out


func fighter(id: String) -> Dictionary:
	return fighters.get(id, fighters.get(roster[0], {}))


func stage(id: String) -> Dictionary:
	return stage_map.get(id, stages[0] if stages.size() > 0 else {})


## Returns a list of human-readable problems with the loaded data (empty = valid).
func validate() -> Array:
	var errors: Array = []
	for id in roster:
		var f: Dictionary = fighters[id]
		for field in ["name", "height", "health", "walk", "jump", "look"]:
			if not f.has(field):
				errors.append("%s: missing field '%s'" % [id, field])
		var moves: Dictionary = f.get("moves", {})
		for key in REQUIRED_MOVES:
			if not moves.has(key):
				errors.append("%s: missing move '%s'" % [id, key])
		for key in moves:
			var m: Dictionary = moves[key]
			for p in m.get("pose", []):
				if not Poses.has_pose(p):
					errors.append("%s.%s: unknown pose '%s'" % [id, key, p])
			for p in m.get("pose_cycle", []):
				if not Poses.has_pose(p):
					errors.append("%s.%s: unknown cycle pose '%s'" % [id, key, p])
			for field in ["startup", "active", "recovery"]:
				if int(m.get(field, 0)) <= 0:
					errors.append("%s.%s: '%s' must be > 0" % [id, key, field])
			var does_something: bool = m.has("hitbox") or m.has("projectile") or m.get("throw", false) or m.has("counter") or m.get("utility", false)
			if not does_something:
				errors.append("%s.%s: move has no hitbox, projectile, throw, counter or utility flag" % [id, key])
			if m.has("counter") and not moves.has(m["counter"].get("move", "")):
				errors.append("%s.%s: counter follow-up missing" % [id, key])
			if m.has("hitbox") and (m["hitbox"] as Array).size() != 4:
				errors.append("%s.%s: hitbox must have 4 numbers" % [id, key])
		var vp: String = f.get("victory_pose", "victory")
		if not Poses.has_pose(vp):
			errors.append("%s: unknown victory pose '%s'" % [id, vp])
	for st in stages:
		for field in ["id", "name"]:
			if not st.has(field):
				errors.append("stage missing '%s'" % field)
	for ch in story.get("chapters", []):
		if not ch.get("choose", false) and not fighters.has(ch.get("player", "")):
			errors.append("story chapter '%s' has unknown player" % ch.get("title", "?"))
		if not fighters.has(ch.get("opponent", "")):
			errors.append("story chapter '%s' has unknown opponent" % ch.get("title", "?"))
		if not stage_map.has(ch.get("stage", "")):
			errors.append("story chapter '%s' has unknown stage" % ch.get("title", "?"))
	return errors
