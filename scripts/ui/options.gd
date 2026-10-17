extends Control
## Options: audio, video, gameplay, accessibility and keyboard remapping.

const MenuList = preload("res://scripts/ui/menu_list.gd")

var menu: Control
var page := "main"
var remap_pid := 0
var waiting_action := ""


func _ready() -> void:
	Sound.play_music("menu")
	menu = MenuList.new()
	menu.width = 330.0
	menu.font_size = 10
	menu.item_h = 15.0
	menu.position = Vector2(155, 40)
	add_child(menu)
	menu.chosen.connect(_on_choice)
	menu.adjusted.connect(_on_adjust)
	menu.cancelled.connect(_on_back)
	_build()


func _pct(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))


func _onoff(v: bool) -> String:
	return "ON" if v else "OFF"


func _build() -> void:
	var s := Game.settings
	var keep: int = menu.index
	if page == "main":
		menu.title = "OPTIONS"
		var diff := ["EASY", "NORMAL", "HARD", "EXPERT", "LEGEND"]
		menu.set_items([
			{"id": "music_vol", "label": "Music Volume", "value": _pct(s["music_vol"])},
			{"id": "sfx_vol", "label": "Effects Volume", "value": _pct(s["sfx_vol"])},
			{"id": "voice_vol", "label": "Announcer Volume", "value": _pct(s["voice_vol"])},
			{"id": "mute", "label": "Mute All", "value": _onoff(s["mute"])},
			{"id": "fullscreen", "label": "Fullscreen", "value": _onoff(s["fullscreen"])},
			{"id": "window_scale", "label": "Window Scale", "value": "%dx" % int(s["window_scale"])},
			{"id": "integer_scale", "label": "Pixel Scaling", "value": "CRISP (INTEGER)" if s["integer_scale"] else "FILL SCREEN"},
			{"id": "shake", "label": "Screen Shake", "value": _onoff(s["shake"])},
			{"id": "reduce_flash", "label": "Reduce Flashing", "value": _onoff(s["reduce_flash"])},
			{"id": "difficulty", "label": "CPU Difficulty", "value": diff[clampi(int(s["difficulty"]), 0, 4)]},
			{"id": "round_time", "label": "Round Timer", "value": "INFINITE" if int(s["round_time"]) <= 0 else str(s["round_time"])},
			{"id": "rounds", "label": "Rounds to Win", "value": str(s["rounds"])},
			{"id": "keys_p1", "label": "Player 1 Controls..."},
			{"id": "keys_p2", "label": "Player 2 Controls..."},
			{"id": "swap_pads", "label": "Swap Gamepads", "value": "P1=PAD %d  P2=PAD %d" % [InputManager.pad_device[0], InputManager.pad_device[1]]},
			{"id": "back", "label": "Back"},
		])
	else:
		menu.title = "PLAYER %d KEYBOARD" % (remap_pid + 1)
		var items: Array = []
		for a in InputManager.ACTIONS:
			var v := InputManager.key_label(remap_pid, a)
			if waiting_action == a:
				v = "PRESS A KEY..."
			items.append({"id": a, "label": InputManager.ACTION_LABELS[a], "value": v})
		items.append({"id": "reset", "label": "Reset All Controls to Default"})
		items.append({"id": "back", "label": "Back"})
		menu.set_items(items)
	menu.index = clampi(keep, 0, menu.items.size() - 1)


func _on_adjust(id: String, dir: int) -> void:
	if page != "main":
		return
	var s := Game.settings
	match id:
		"music_vol", "sfx_vol", "voice_vol":
			s[id] = clampf(snappedf(float(s[id]) + dir * 0.1, 0.1), 0.0, 1.0)
		"mute", "fullscreen", "integer_scale", "shake", "reduce_flash":
			s[id] = not s[id]
		"window_scale":
			s[id] = clampi(int(s[id]) + dir, 1, 4)
		"difficulty":
			s[id] = clampi(int(s[id]) + dir, 0, 4)
		"round_time":
			var opts := [30, 60, 99, 0]
			var i := opts.find(int(s[id]))
			s[id] = opts[wrapi(i + dir, 0, opts.size())]
		"rounds":
			s[id] = clampi(int(s[id]) + dir, 1, 3)
		"swap_pads":
			InputManager.swap_pads()
		_:
			return
	Game.apply_settings()
	Game.save_settings()
	_build()


func _on_choice(id: String) -> void:
	if page == "main":
		match id:
			"keys_p1":
				page = "keys"
				remap_pid = 0
				menu.index = 0
				_build()
			"keys_p2":
				page = "keys"
				remap_pid = 1
				menu.index = 0
				_build()
			"back":
				_on_back()
			_:
				_on_adjust(id, 1)
	else:
		match id:
			"back":
				_on_back()
			"reset":
				InputManager.reset_defaults()
				Game.save_settings()
				_build()
			_:
				waiting_action = id
				menu.active = false
				_build()


func _on_back() -> void:
	if waiting_action != "":
		return
	if page != "main":
		page = "main"
		menu.index = 12 + remap_pid
		_build()
	else:
		Game.save_settings()
		Game.goto("menu")


func _input(event: InputEvent) -> void:
	if waiting_action == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.physical_keycode
	if k != KEY_ESCAPE:
		InputManager.set_key(remap_pid, waiting_action, k)
		Game.save_settings()
	waiting_action = ""
	get_viewport().set_input_as_handled()
	_build()
	await get_tree().process_frame
	menu.active = true
	menu.cooldown = 6


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("0a0c18"))
	var font: Font = Game.font
	var hint := "UP/DOWN: choose   LEFT/RIGHT: change   LIGHT: select   MEDIUM/ESC: back"
	if page != "main":
		hint = "Select an action, then press the new key (ESC cancels). Gamepads: X/Y/B attack, A/RB special, LB/LT block."
	var w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(320 - w * 0.5, 348), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.75, 0.75, 0.85))


func _process(_delta: float) -> void:
	queue_redraw()
