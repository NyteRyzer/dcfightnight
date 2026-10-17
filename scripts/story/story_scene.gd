extends Control
## Story / ending cutscenes: chapter title cards and typewriter dialogue with
## large character art drawn by the fighter rig.

const Rig = preload("res://scripts/combat/rig.gd")
const Poses = preload("res://scripts/combat/poses.gd")
const Arena = preload("res://scripts/arenas/arena.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")

var cards: Array = []
var card_i := 0
var line_i := -1
var shown := 0.0
var t := 0.0
var title_t := 0.0
var left_id := ""
var right_id := ""
var arena: Node2D
var portrait: Control


func _ready() -> void:
	Sound.play_music("story")
	cards = Game.story_cards
	arena = Arena.new()
	arena.preview = true
	arena.cam_left = 180.0
	arena.position = Vector2(-180, 0)
	arena.z_index = -5
	add_child(arena)
	portrait = Portrait.new()
	portrait.position = Vector2(28, 270)
	portrait.size = Vector2(56, 56)
	portrait.visible = false
	add_child(portrait)
	_start_card()


func _stage_for_card() -> String:
	if Game.mode == "story" and Game.story_next == "story_fight" and Game.story_index < Data.story["chapters"].size():
		if card_i == cards.size() - 1:
			return Data.story["chapters"][Game.story_index].get("stage", "star_labs")
	return "freak_studio" if Game.story_index == 0 else "star_labs"


func _start_card() -> void:
	if card_i >= cards.size():
		_finish()
		return
	line_i = -1
	title_t = 1.6
	if portrait != null:
		portrait.visible = false
	left_id = ""
	right_id = ""
	arena.stage_id = _stage_for_card()
	arena.glitch = true


func _advance() -> void:
	var lines: Array = cards[card_i].get("lines", [])
	if line_i >= 0 and shown < str(lines[line_i][1]).length():
		shown = 99999.0
		return
	line_i += 1
	shown = 0.0
	if line_i >= lines.size():
		card_i += 1
		_start_card()
		return
	var speaker: String = lines[line_i][0]
	portrait.visible = speaker != "" and Data.fighters.has(speaker)
	if portrait.visible:
		portrait.set_fighter(Data.fighter(speaker))
	if speaker != "" and speaker != left_id and speaker != right_id:
		if left_id == "":
			left_id = speaker
		elif right_id == "":
			right_id = speaker
		else:
			right_id = speaker
	Sound.play("menu_move", 0.8, -6.0)


func _finish() -> void:
	match Game.story_next:
		"story_fight":
			Game.story_continue()
		"credits":
			Game.goto("credits")
		_:
			Game.goto("menu")


func _process(delta: float) -> void:
	t += delta
	if card_i >= cards.size():
		return
	if title_t > 0.0:
		title_t -= delta
		if title_t <= 0.0 or InputManager.menu("accept"):
			title_t = 0.0
			_advance()
	else:
		shown += delta * 55.0
		if InputManager.menu("accept"):
			_advance()
	if Input.is_action_just_pressed("pause"):
		card_i = cards.size()
		_finish()
	queue_redraw()


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
	if card_i >= cards.size():
		draw_rect(Rect2(0, 0, 640, 360), Color.BLACK)
		return
	var font: Font = Game.font
	draw_rect(Rect2(0, 0, 640, 360), Color(0, 0, 0, 0.55))
	var card: Dictionary = cards[card_i]
	var lines: Array = card.get("lines", [])
	var speaker := ""
	if line_i >= 0 and line_i < lines.size():
		speaker = lines[line_i][0]
	# Characters.
	for side in 2:
		var id := left_id if side == 0 else right_id
		if id == "" or not Data.fighters.has(id):
			continue
		var f := Data.fighter(id)
		var talking := id == speaker
		var x := 120.0 if side == 0 else 520.0
		var pose := Poses.blend(Poses.get_pose("idle"), Poses.get_pose("idle2"), (sin(t * 4.0 + side) + 1.0) * 0.5)
		draw_set_transform(Vector2(x, 300), 0.0, Vector2(1.15, 1.15))
		Rig.draw(self, Vector2.ZERO, 1 if side == 0 else -1, pose, f["look"], float(f["height"]), {"tint": Color(0, 0, 0.05, 0.0 if talking else 0.55)})
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Title card.
	if title_t > 0.0 or line_i < 0:
		var a := clampf(title_t * 2.0, 0.0, 1.0)
		draw_rect(Rect2(0, 130, 640, 74), Color(0, 0, 0, 0.8 * a))
		var sub := str(card.get("subtitle", ""))
		var ttl := str(card.get("title", "")).to_upper()
		var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var tw := font.get_string_size(ttl, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(font, Vector2(320 - sw * 0.5, 150), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.85, 1, a))
		draw_string_outline(font, Vector2(320 - tw * 0.5, 186), ttl, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 5, Color(0, 0, 0, a))
		draw_string(font, Vector2(320 - tw * 0.5, 186), ttl, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.85, 0.25, a))
		return
	# Dialogue box.
	draw_rect(Rect2(20, 262, 600, 88), Color(0.02, 0.02, 0.06, 0.92))
	draw_rect(Rect2(20, 262, 600, 88), Color(1, 0.85, 0.3, 0.7), false, 1.0)
	var text: String = str(lines[line_i][1])
	var tx := 30.0
	if speaker != "" and Data.fighters.has(speaker):
		var f2 := Data.fighter(speaker)
		draw_rect(Rect2(27, 269, 58, 58), Color(1, 1, 1, 0.5), false, 1.0)
		draw_string(font, Vector2(28, 340), str(f2.get("short", f2["name"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.85, 0.3))
		tx = 94.0
	var visible := text.substr(0, int(shown))
	var wrapped := _wrap(visible, 610.0 - tx, 11)
	for i in mini(wrapped.size(), 6):
		draw_string(font, Vector2(tx, 280 + i * 13), wrapped[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1) if speaker != "" else Color(0.85, 0.9, 1.0))
	if int(t * 3) % 2 == 0 and shown >= text.length():
		draw_string(font, Vector2(598, 344), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.85, 0.3))
	draw_string(font, Vector2(470, 358), "%s: next   %s: skip" % [InputManager.prompt("accept"), InputManager.prompt("pause")], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.7, 0.8))
