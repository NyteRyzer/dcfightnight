extends Control
## Stage select with a live, scaled preview of the arena.

const Arena = preload("res://scripts/arenas/arena.gd")
const MenuList = preload("res://scripts/ui/menu_list.gd")

var menu: Control
var preview_clip: Control
var arena: Node2D
var t := 0.0


func _ready() -> void:
	menu = MenuList.new()
	menu.title = "SELECT STAGE"
	menu.width = 190.0
	menu.font_size = 10
	menu.item_h = 15.0
	var items: Array = [{"id": "random", "label": "Random Stage"}]
	for st in Data.stages:
		var ok := Game.stage_unlocked(st)
		items.append({"id": st["id"], "label": st["name"] if ok else "??? (locked)", "disabled": not ok})
	menu.set_items(items)
	var cur := 0
	for i in items.size():
		if items[i]["id"] == Game.stage_id:
			cur = i
	menu.index = cur
	menu.position = Vector2(16, 60)
	add_child(menu)
	menu.chosen.connect(_on_choice)
	menu.cancelled.connect(func(): Game.goto("select"))

	preview_clip = Control.new()
	preview_clip.clip_contents = true
	preview_clip.position = Vector2(222, 74)
	preview_clip.size = Vector2(400, 225)
	add_child(preview_clip)
	var holder := Node2D.new()
	holder.scale = Vector2(400.0 / 640.0, 225.0 / 360.0)
	preview_clip.add_child(holder)
	arena = Arena.new()
	arena.preview = true
	arena.cam_left = 180.0
	arena.position = Vector2(-180.0, 0)
	holder.add_child(arena)


func _on_choice(id: String) -> void:
	Game.stage_id = Game.random_stage() if id == "random" else id
	Game.fight_opts = {}
	Game.begin_fight()


func _process(delta: float) -> void:
	t += delta
	var id: String = menu.current_id()
	arena.stage_id = Data.stages[randi() % 10]["id"] if id == "random" and fmod(t, 0.5) < delta else (arena.stage_id if id == "random" else id)
	arena.cam_left = 180.0 + sin(t * 0.5) * 150.0
	arena.position.x = -arena.cam_left
	queue_redraw()


func _draw() -> void:
	var font: Font = Game.font
	draw_rect(Rect2(0, 0, 640, 360), Color("0a0c16"))
	draw_rect(Rect2(220, 72, 404, 229), Color(1, 0.85, 0.3, 0.8), false, 2.0)
	var st: Dictionary = Data.stage(arena.stage_id)
	var name_s: String = "RANDOM" if menu.current_id() == "random" else str(st.get("name", "")).to_upper()
	draw_string_outline(font, Vector2(224, 60), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
	draw_string(font, Vector2(224, 60), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.3))
	if menu.current_id() != "random":
		draw_string(font, Vector2(224, 318), str(st.get("location", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.85, 0.95))
	var a := Data.fighter(Game.chars[0])
	var b := Data.fighter(Game.chars[1])
	var vs := "%s  VS  %s" % [str(a.get("name", "")).to_upper(), str(b.get("name", "")).to_upper()]
	draw_string(font, Vector2(16, 30), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1))
	draw_string(font, Vector2(224, 340), "LIGHT: fight   MEDIUM: back", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.7, 0.8))
