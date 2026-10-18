extends Control
## Title screen and main menu.

const Rig = preload("res://scripts/combat/rig.gd")
const Poses = preload("res://scripts/combat/poses.gd")
const MenuList = preload("res://scripts/ui/menu_list.gd")

var menu: Control
var t := 0.0
var pair := 0
var pairs := [["flash", "reverse_flash"], ["green_arrow", "deathstroke"], ["supergirl", "reign"], ["black_canary", "vigilante"], ["citizen_steel", "vandal_savage"], ["vibe", "martian_manhunter"]]
var bolts: Array = []


func _ready() -> void:
	Sound.play_music("menu")
	menu = MenuList.new()
	menu.width = 200.0
	menu.font_size = 11
	menu.item_h = 14.5
	var progress := int(Game.save.get("story_progress", 0))
	var items := [
		{"id": "story", "label": "Story Mode"},
	]
	if progress > 0:
		items.append({"id": "story_continue", "label": "Continue Story (Ch. %d)" % (progress + 1)})
	items += [
		{"id": "arcade", "label": "Arcade"},
		{"id": "survival", "label": "Survival"},
		{"id": "brawl", "label": "Beat 'em Up"},
		{"id": "brawl_coop", "label": "Beat 'em Up Co-op"},
		{"id": "versus", "label": "Versus (2 Players)"},
		{"id": "versus_cpu", "label": "Versus CPU"},
		{"id": "training", "label": "Training"},
		{"id": "tutorial", "label": "Tutorial" if Game.save.get("tutorial_done", false) else "Tutorial (start here!)"},
		{"id": "howto", "label": "How to Play"},
		{"id": "options", "label": "Options"},
		{"id": "credits", "label": "Credits"},
		{"id": "quit", "label": "Quit"},
	]
	menu.set_items(items)
	menu.position = Vector2(220, 104)
	add_child(menu)
	menu.chosen.connect(_on_choice)
	pair = randi() % pairs.size()


func _on_choice(id: String) -> void:
	match id:
		"story":
			Game.story_champion = ""
			Game.start_story(0)
		"story_continue":
			Game.story_champion = ""
			Game.start_story(int(Game.save.get("story_progress", 0)))
		"arcade":
			Game.mode = "arcade"
			Game.cpu = [false, true]
			Game.goto("select")
		"survival":
			Game.mode = "survival"
			Game.cpu = [false, true]
			Game.goto("select")
		"versus":
			Game.start_versus(false)
		"versus_cpu":
			Game.start_versus(true)
		"training":
			Game.start_training()
		"brawl":
			Game.choose_brawl(false)
		"brawl_coop":
			Game.choose_brawl(true)
		"tutorial":
			Game.start_tutorial()
		"howto":
			Game.goto("howto")
		"options":
			Game.goto("options")
		"credits":
			Game.goto("credits")
		"quit":
			get_tree().quit()


func _process(delta: float) -> void:
	t += delta
	if fmod(t, 5.0) < delta:
		pair = (pair + 1) % pairs.size()
	if randf() < 0.08:
		var y := randf() * 360.0
		bolts.append({"y": y, "x": -40.0, "life": 1.0, "c": [Color(1, 0.8, 0.2), Color(0.3, 0.7, 1.0), Color(0.4, 1, 0.5)][randi() % 3]})
	for b in bolts:
		b["x"] += 26.0
		b["life"] -= 0.02
	bolts = bolts.filter(func(b): return b["x"] < 700.0 and b["life"] > 0.0)
	queue_redraw()


func _draw() -> void:
	var font: Font = Game.font
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(640, 0), Vector2(640, 360), Vector2(0, 360)]),
		PackedColorArray([Color("0a0c1e"), Color("140a1e"), Color("2a0c10"), Color("0a1a2a")]))
	for i in 18:
		var x := fmod(i * 47.0 + t * 12.0, 700.0) - 30.0
		draw_line(Vector2(x, 0), Vector2(x - 120, 360), Color(1, 1, 1, 0.025), 8.0)
	for b in bolts:
		var pts := PackedVector2Array()
		for k in 6:
			pts.append(Vector2(b["x"] - k * 14.0, b["y"] + (randf() - 0.5) * 10.0))
		draw_polyline(pts, Color(b["c"].r, b["c"].g, b["c"].b, b["life"] * 0.7), 2.0)
	# Two heroes facing off.
	var ids: Array = pairs[pair]
	var k := clampf(fmod(t, 5.0) * 2.0, 0.0, 1.0) * clampf((5.0 - fmod(t, 5.0)) * 2.0, 0.0, 1.0)
	for i in 2:
		var f := Data.fighter(ids[i])
		var x := 100.0 if i == 0 else 540.0
		var pose := Poses.blend(Poses.get_pose("idle"), Poses.get_pose("idle2"), (sin(t * 5.0 + i) + 1.0) * 0.5)
		draw_set_transform(Vector2(x + (1.0 - k) * (-60.0 if i == 0 else 60.0), 350), 0.0, Vector2(1.3, 1.3))
		var power: Color = f["look"].get("power", Color.WHITE)
		draw_set_transform(Vector2(x + (1.0 - k) * (-60.0 if i == 0 else 60.0), 350), 0.0, Vector2(1.3, 0.3))
		draw_circle(Vector2.ZERO, 50, Color(power.r, power.g, power.b, 0.15 * k))
		draw_set_transform(Vector2(x + (1.0 - k) * (-60.0 if i == 0 else 60.0), 350), 0.0, Vector2(1.3, 1.3))
		Rig.draw(self, Vector2.ZERO, 1 if i == 0 else -1, pose, f["look"], float(f["height"]), {"alpha": k})
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Title.
	var t1 := "DC'S ARROWVERSE"
	var w1 := font.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string_outline(font, Vector2(320 - w1 * 0.5, 42), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
	draw_string(font, Vector2(320 - w1 * 0.5, 42), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 1.0))
	var t2 := "FIGHT NIGHT"
	var w2 := font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	draw_string_outline(font, Vector2(320 - w2 * 0.5 + 3, 92), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 10, Color(0.5, 0.05, 0.05))
	draw_string_outline(font, Vector2(320 - w2 * 0.5, 89), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 6, Color.BLACK)
	draw_string(font, Vector2(320 - w2 * 0.5, 89), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(1, 0.82, 0.2))
	draw_rect(Rect2(320 - w2 * 0.5, 96, w2, 2), Color(1, 0.3, 0.2))
	var foot := "Personal noncommercial fan project  -  all art & audio generated in code"
	var wf := font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(320 - wf * 0.5, 354), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.6, 0.6, 0.7))
	var hint := "%s: select   %s: back" % [InputManager.prompt("accept"), InputManager.prompt("back")]
	var wh := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(320 - wh * 0.5, 342), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.75, 0.75, 0.85))
