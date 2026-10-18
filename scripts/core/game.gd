extends Node
## Global game state: current mode, selections, ladders, settings and save data.

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"

const SCENES := {
	"menu": "res://scenes/ui/MainMenu.tscn",
	"select": "res://scenes/ui/CharacterSelect.tscn",
	"stage": "res://scenes/ui/StageSelect.tscn",
	"fight": "res://scenes/fight/FightStage.tscn",
	"training": "res://scenes/fight/TrainingRoom.tscn",
	"story": "res://scenes/story/StoryScene.tscn",
	"options": "res://scenes/ui/Options.tscn",
	"credits": "res://scenes/ui/Credits.tscn",
	"howto": "res://scenes/ui/HowToPlay.tscn",
	"brawl": "res://scenes/brawl/BrawlStage.tscn",
}

var font: Font
var theme: Theme

## Modes: story, arcade, survival, versus, versus_cpu, training, cpu_vs_cpu
var mode := "versus"
var chars := ["flash", "green_arrow"]
var cpu := [false, true]
## Costume index per player (0 = default suit). See fighter JSON "costumes".
var costume := [0, 0]
var costume_pref := [0, 0]
var stage_id := "star_labs"
## Extra per-fight options (boss, glitch, single_round, labels...). Reset per fight.
var fight_opts := {}

var arcade := {"char": "", "ladder": [], "index": 0}
var survival := {"char": "", "wins": 0, "health": 1.0, "seed": 0}
var story_index := 0
var story_champion := ""
## Cards for StoryScene: [{title, subtitle, lines: [[speaker, text], ...]}]
var story_cards: Array = []
var story_next := "menu"
## Beat 'em up run: {players: [ids], costumes: [..], level, continues}
var brawl := {"players": ["flash"], "costumes": [0, 0], "level": 0, "continues": 0}

var training := {"dummy": "stand", "meter": "infinite", "boxes": false, "regen": true}

var settings := {
	"music_vol": 0.6, "sfx_vol": 0.8, "voice_vol": 0.8, "mute": false,
	"fullscreen": false, "window_scale": 2, "integer_scale": true,
	"shake": true, "reduce_flash": false, "difficulty": 1,
	"round_time": 99, "rounds": 2,
	"rumble": true, "rumble_strength": 0.8, "deadzone": 0.45,
	"finishers": true, "banter": true,
}
## Losses in a row on the current Story chapter / Arcade fight. Each retry
## eases the CPU a little more (see _assist_opts).
var retries := 0
var save := {"story_done": false, "arcade_done": false, "story_progress": 0}


var _toast_layer: CanvasLayer
var _toast_text := ""
var _toast_t := 0.0
var _toast_node: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_theme()
	load_settings()
	load_save()
	apply_settings()
	randomize()
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 100
	add_child(_toast_layer)
	_toast_node = Control.new()
	_toast_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_node.draw.connect(_draw_toast)
	_toast_layer.add_child(_toast_node)
	InputManager.pad_connected.connect(func(_d, n): toast("Controller connected: %s" % n))
	InputManager.pad_disconnected.connect(func(_d): toast("Controller disconnected"))


## Small notification at the top of the screen (controller connected, etc.).
func toast(text: String) -> void:
	_toast_text = text
	_toast_t = 3.0


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast_node.queue_redraw()


func _draw_toast() -> void:
	if _toast_t <= 0.0 or font == null:
		return
	var a := clampf(_toast_t * 2.0, 0.0, 1.0)
	var w := font.get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 16
	_toast_node.draw_rect(Rect2(320 - w * 0.5, 4, w, 16), Color(0, 0, 0, 0.8 * a))
	_toast_node.draw_rect(Rect2(320 - w * 0.5, 4, w, 16), Color(1, 0.85, 0.3, a), false, 1.0)
	_toast_node.draw_string(font, Vector2(320 - w * 0.5 + 8, 16), _toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, a))


func _setup_theme() -> void:
	font = ThemeDB.fallback_font
	if font is FontFile:
		var ff: FontFile = (font as FontFile).duplicate()
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.hinting = TextServer.HINTING_NONE
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font = ff
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 10
	get_tree().root.theme = theme


func goto(scene_key: String) -> void:
	get_tree().paused = false
	# Outside two-player versus, any controller can drive Player 1.
	InputManager.set_shared(mode not in ["versus", "brawl_coop"])
	var path: String = SCENES.get(scene_key, scene_key)
	get_tree().change_scene_to_file.call_deferred(path)


# --- Unlocks ----------------------------------------------------------------

func is_unlocked(fighter_id: String) -> bool:
	if not Data.locked.has(fighter_id):
		return true
	return save.get("story_done", false) or save.get("arcade_done", false)


func stage_unlocked(st: Dictionary) -> bool:
	if not st.get("locked", false):
		return true
	return save.get("story_done", false) or save.get("arcade_done", false)


func unlocked_fighters() -> Array:
	var out := []
	for id in Data.roster:
		if is_unlocked(id):
			out.append(id)
	return out


func hero_ids() -> Array:
	var out := []
	for id in Data.roster:
		if not Data.locked.has(id):
			out.append(id)
	return out


func is_villain(id: String) -> bool:
	return str(Data.fighter(id).get("team", "")) == "Villain"


func random_stage(include_locked := false) -> String:
	var pool := []
	for st in Data.stages:
		if include_locked or stage_unlocked(st):
			if st["id"] != "freak_studio":
				pool.append(st["id"])
	return pool[randi() % pool.size()]


# --- Mode flows ---------------------------------------------------------------

## Tutorial: Flash vs a Citizen Steel practice dummy, lesson by lesson.
func start_tutorial() -> void:
	mode = "tutorial"
	chars = ["flash", "citizen_steel"]
	cpu = [false, true]
	costume = [0, 0]
	stage_id = "star_labs"
	fight_opts = {}
	goto("training")


## Beat 'em up: 1 player ("brawl") or 2-player co-op ("brawl_coop").
func choose_brawl(coop: bool) -> void:
	mode = "brawl_coop" if coop else "brawl"
	cpu = [false, false]
	goto("select")


func start_brawl(ids: Array) -> void:
	brawl = {"players": ids.duplicate(), "costumes": costume_pref.duplicate(), "level": 0, "continues": 0}
	if ids.size() > 1 and ids[0] == ids[1] and brawl["costumes"][0] == brawl["costumes"][1]:
		brawl["costumes"][1] = (brawl["costumes"][0] + 1) % Data.fighter(ids[1])["costumes"].size()
	goto("brawl")


func start_versus(p2_cpu: bool) -> void:
	mode = "versus_cpu" if p2_cpu else "versus"
	cpu = [false, p2_cpu]
	goto("select")


func start_training() -> void:
	mode = "training"
	cpu = [false, true]
	goto("select")


func begin_fight() -> void:
	costume = costume_pref.duplicate()
	if chars[0] == chars[1] and costume[0] == costume[1]:
		var n: int = Data.fighter(chars[1])["costumes"].size()
		costume[1] = (costume[0] + 1) % n
	goto("training" if mode == "training" else "fight")


## Arcade: pick a fighter, beat 6 random opponents, then Control Freak.
func start_arcade(char_id: String) -> void:
	mode = "arcade"
	retries = 0
	arcade = {"char": char_id, "ladder": [], "index": 0}
	costume_pref[1] = 0
	var pool := hero_ids()
	pool.erase(char_id)
	pool.shuffle()
	for i in mini(6, pool.size()):
		arcade["ladder"].append({"opponent": pool[i], "stage": random_stage()})
	arcade["ladder"].append({"opponent": "control_freak", "stage": "freak_studio", "boss": true})
	_arcade_fight()


func _arcade_fight() -> void:
	var step: Dictionary = arcade["ladder"][arcade["index"]]
	chars = [arcade["char"], step["opponent"]]
	cpu = [false, true]
	stage_id = step["stage"]
	# The first two arcade fights are a level easier as a warm-up.
	var offset := -1 if arcade["index"] < 2 else 0
	fight_opts = {"boss": step.get("boss", false), "ladder_label": "ARCADE %d/%d" % [arcade["index"] + 1, arcade["ladder"].size()]}
	fight_opts.merge(_assist_opts(offset))
	begin_fight()


## CPU level and damage for Story / Arcade. `offset` shifts the level for
## early chapters; every retry after a loss lowers it one more step, and from
## the third retry on the CPU also hits softer.
func _assist_opts(offset: int) -> Dictionary:
	var base := int(settings.get("difficulty", 1))
	var lvl := clampi(base + offset - retries, 0, 4)
	var opts := {"cpu_level": lvl}
	if retries >= 3:
		opts["cpu_damage"] = maxf(0.6, 1.0 - 0.1 * (retries - 2))
	if retries > 0:
		toast("Assist: CPU eased after %d loss%s" % [retries, "" if retries == 1 else "es"])
	return opts


func arcade_won() -> void:
	retries = 0
	arcade["index"] += 1
	if arcade["index"] >= arcade["ladder"].size():
		save["arcade_done"] = true
		write_save()
		var f := Data.fighter(arcade["char"])
		story_cards = [{"title": f.get("name", ""), "subtitle": "Arcade Ending", "speaker": arcade["char"],
			"lines": [[arcade["char"], f.get("ending", "")], ["", "ARCADE COMPLETE. Control Freak and Freak's Studio are unlocked."]]}]
		story_next = "credits"
		goto("story")
	else:
		_arcade_fight()


func arcade_retry() -> void:
	_arcade_fight()


## Survival: endless opponents, health carries over with a small heal.
func start_survival(char_id: String) -> void:
	mode = "survival"
	survival = {"char": char_id, "wins": 0, "health": 1.0}
	costume_pref[1] = 0
	_survival_fight()


func _survival_fight() -> void:
	var pool := unlocked_fighters()
	pool.erase(survival["char"])
	chars = [survival["char"], pool[randi() % pool.size()]]
	cpu = [false, true]
	stage_id = random_stage()
	fight_opts = {"single_round": true, "start_health": survival["health"],
		"cpu_level": mini(4, 1 + int(survival["wins"] / 3)), "ladder_label": "SURVIVAL  WINS: %d" % survival["wins"]}
	begin_fight()


func survival_won(health_ratio: float) -> void:
	survival["wins"] += 1
	survival["health"] = minf(1.0, health_ratio + 0.25)
	_survival_fight()


# --- Story ----------------------------------------------------------------------

func start_story(from_chapter: int = 0) -> void:
	mode = "story"
	retries = 0
	story_index = from_chapter
	if from_chapter == 0:
		story_cards = []
		for c in Data.story.get("intro", []):
			story_cards.append(c)
		story_cards.append(_chapter_card(0))
	else:
		story_cards = [_chapter_card(from_chapter)]
	story_next = "story_fight"
	goto("story")


func _chapter_card(i: int) -> Dictionary:
	var ch: Dictionary = Data.story["chapters"][i]
	return {"title": ch.get("title", ""), "subtitle": "%s  -  CHAPTER %d" % [ch.get("act", ""), i + 1], "lines": ch.get("before", [])}


func story_chapter() -> Dictionary:
	return Data.story["chapters"][story_index]


## Called by StoryScene when the pre-fight cards finish.
func story_continue() -> void:
	var ch := story_chapter()
	if ch.get("choose", false) and story_champion == "":
		mode = "story_choose"
		cpu = [false, true]
		goto("select")
		return
	story_fight()


func story_fight() -> void:
	var ch := story_chapter()
	mode = "story"
	var player: String = story_champion if ch.get("choose", false) else ch["player"]
	costume_pref = [costume_pref[0] if ch.get("choose", false) else 0, 0]
	chars = [player, ch["opponent"]]
	cpu = [false, true]
	stage_id = ch["stage"]
	fight_opts = {"single_round": not ch.get("boss", false), "boss": ch.get("boss", false), "glitch": ch.get("glitch", false),
		"ladder_label": "%s - %s" % [ch.get("act", ""), ch.get("title", "")]}
	# Act I eases players in one difficulty level below their setting.
	fight_opts.merge(_assist_opts(int(ch.get("cpu_offset", -1 if ch.get("act", "") == "ACT I" else 0))))
	begin_fight()


func story_won() -> void:
	retries = 0
	var ch := story_chapter()
	story_cards = [{"title": ch.get("title", ""), "subtitle": "AFTERMATH", "lines": ch.get("after", [])}]
	story_index += 1
	save["story_progress"] = maxi(int(save.get("story_progress", 0)), story_index)
	if story_index >= Data.story["chapters"].size():
		save["story_done"] = true
		save["story_progress"] = 0
		story_champion = ""
		story_next = "credits"
	else:
		story_cards.append(_chapter_card(story_index))
		story_next = "story_fight"
	write_save()
	goto("story")


# --- Settings & save ---------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cfg.get_value("settings", k, settings[k])
	# Older builds defaulted the CPU to HARD (2). Move players who never
	# changed it to NORMAL once.
	if int(cfg.get_value("meta", "version", 1)) < 2:
		if int(settings["difficulty"]) == 2:
			settings["difficulty"] = 1
		save_settings()
	var keys = cfg.get_value("input", "keys", null)
	if keys is Dictionary:
		InputManager.import_keys(keys)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 2)
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.set_value("input", "keys", InputManager.export_keys())
	cfg.save(SETTINGS_PATH)


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k in save.keys():
		save[k] = cfg.get_value("save", k, save[k])


func write_save() -> void:
	var cfg := ConfigFile.new()
	for k in save:
		cfg.set_value("save", k, save[k])
	cfg.save(SAVE_PATH)


func apply_settings() -> void:
	Sound.set_volumes(settings["music_vol"], settings["sfx_vol"], settings["voice_vol"], settings["mute"])
	InputManager.rebuild()
	if DisplayServer.get_name() == "headless":
		return
	var win := get_tree().root
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if settings["integer_scale"] else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if settings["fullscreen"]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var s: int = clampi(int(settings["window_scale"]), 1, 4)
		var size := Vector2i(640 * s, 360 * s)
		var screen := DisplayServer.screen_get_size()
		if size.x <= screen.x and size.y <= screen.y and DisplayServer.window_get_size() != size:
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position((screen - size) / 2)
