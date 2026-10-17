extends Control
## Options: audio, video, gameplay, accessibility, keyboard and controller
## remapping, rumble and deadzone.

const MenuList = preload("res://scripts/ui/menu_list.gd")

var menu: Control
var page := "main"
var remap_pid := 0
var waiting_action := ""
var waiting_pad := false
var return_index := {}


func _ready() -> void:
	Sound.play_music("menu")
	menu = MenuList.new()
	menu.width = 360.0
	menu.font_size = 10
	menu.item_h = 15.0
	menu.position = Vector2(140, 36)
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
	var items: Array = []
	match page:
		"main":
			menu.title = "OPTIONS"
			items = [
				{"id": "p_audio", "label": "Audio..."},
				{"id": "p_video", "label": "Video & Accessibility..."},
				{"id": "p_gameplay", "label": "Gameplay..."},
				{"id": "p_controls", "label": "Controls & Controllers..."},
				{"id": "back", "label": "Back"},
			]
		"audio":
			menu.title = "AUDIO"
			items = [
				{"id": "music_vol", "label": "Music Volume", "value": _pct(s["music_vol"])},
				{"id": "sfx_vol", "label": "Effects Volume", "value": _pct(s["sfx_vol"])},
				{"id": "voice_vol", "label": "Announcer Volume", "value": _pct(s["voice_vol"])},
				{"id": "mute", "label": "Mute All", "value": _onoff(s["mute"])},
				{"id": "back", "label": "Back"},
			]
		"video":
			menu.title = "VIDEO & ACCESSIBILITY"
			items = [
				{"id": "fullscreen", "label": "Fullscreen", "value": _onoff(s["fullscreen"])},
				{"id": "window_scale", "label": "Window Scale", "value": "%dx" % int(s["window_scale"])},
				{"id": "integer_scale", "label": "Pixel Scaling", "value": "CRISP (INTEGER)" if s["integer_scale"] else "FILL SCREEN"},
				{"id": "shake", "label": "Screen Shake", "value": _onoff(s["shake"])},
				{"id": "reduce_flash", "label": "Reduce Flashing", "value": _onoff(s["reduce_flash"])},
				{"id": "back", "label": "Back"},
			]
		"gameplay":
			menu.title = "GAMEPLAY"
			var diff := ["EASY", "NORMAL", "HARD", "EXPERT", "LEGEND"]
			items = [
				{"id": "difficulty", "label": "CPU Difficulty", "value": diff[clampi(int(s["difficulty"]), 0, 4)]},
				{"id": "round_time", "label": "Round Timer", "value": "INFINITE" if int(s["round_time"]) <= 0 else str(s["round_time"])},
				{"id": "rounds", "label": "Rounds to Win", "value": str(s["rounds"])},
				{"id": "back", "label": "Back"},
			]
		"controls":
			menu.title = "CONTROLS & CONTROLLERS"
			items = [
				{"id": "keys_0", "label": "Player 1 Keyboard..."},
				{"id": "keys_1", "label": "Player 2 Keyboard..."},
				{"id": "pad_0", "label": "Player 1 Controller...", "value": InputManager.pad_label(0)},
				{"id": "pad_1", "label": "Player 2 Controller...", "value": InputManager.pad_label(1)},
				{"id": "swap_pads", "label": "Swap Controllers (P1 <-> P2)", "value": "SWAPPED" if InputManager.swapped else "NORMAL"},
				{"id": "rumble", "label": "Vibration", "value": _onoff(s["rumble"])},
				{"id": "rumble_strength", "label": "Vibration Strength", "value": _pct(s["rumble_strength"])},
				{"id": "deadzone", "label": "Stick Deadzone", "value": _pct(s["deadzone"])},
				{"id": "test_rumble", "label": "Test Vibration"},
				{"id": "reset", "label": "Reset All Controls to Default"},
				{"id": "back", "label": "Back"},
			]
		"keys":
			menu.title = "PLAYER %d KEYBOARD" % (remap_pid + 1)
			for a in InputManager.ACTIONS:
				var v := InputManager.key_label(remap_pid, a)
				if waiting_action == a:
					v = "PRESS A KEY..."
				items.append({"id": a, "label": InputManager.ACTION_LABELS[a], "value": v})
			items.append({"id": "back", "label": "Back"})
		"pad":
			menu.title = "PLAYER %d CONTROLLER" % (remap_pid + 1)
			for a in InputManager.FIGHT_BUTTONS:
				var v2 := InputManager.pad_label_for(remap_pid, a)
				if waiting_action == a:
					v2 = "PRESS A BUTTON..."
				items.append({"id": a, "label": InputManager.ACTION_LABELS[a], "value": v2})
			items.append({"id": "back", "label": "Back"})
	menu.set_items(items)
	menu.index = clampi(keep, 0, menu.items.size() - 1)


func _goto_page(p: String) -> void:
	return_index[page] = menu.index
	page = p
	menu.index = 0
	_build()


func _on_adjust(id: String, dir: int) -> void:
	if page in ["keys", "pad", "main"]:
		return
	var s := Game.settings
	match id:
		"music_vol", "sfx_vol", "voice_vol", "rumble_strength":
			s[id] = clampf(snappedf(float(s[id]) + dir * 0.1, 0.1), 0.0, 1.0)
		"deadzone":
			s[id] = clampf(snappedf(float(s[id]) + dir * 0.05, 0.05), 0.1, 0.9)
		"mute", "fullscreen", "integer_scale", "shake", "reduce_flash", "rumble":
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
	if id == "back":
		_on_back()
		return
	match page:
		"main":
			_goto_page(id.substr(2))
		"controls":
			if id.begins_with("keys_"):
				remap_pid = int(id.substr(5))
				_goto_page("keys")
			elif id.begins_with("pad_"):
				remap_pid = int(id.substr(4))
				_goto_page("pad")
			elif id == "reset":
				InputManager.reset_defaults()
				Game.save_settings()
				Game.toast("Controls reset to defaults")
				_build()
			elif id == "test_rumble":
				for p in 2:
					InputManager.rumble(p, 1.0, 0.4)
			else:
				_on_adjust(id, 1)
		"keys", "pad":
			waiting_action = id
			waiting_pad = page == "pad"
			menu.active = false
			_build()
		_:
			_on_adjust(id, 1)


func _on_back() -> void:
	if waiting_action != "":
		return
	if page == "main":
		Game.save_settings()
		Game.goto("menu")
		return
	var parent := "controls" if page in ["keys", "pad"] else "main"
	page = parent
	menu.index = return_index.get(parent, 0)
	_build()


func _finish_wait() -> void:
	waiting_action = ""
	get_viewport().set_input_as_handled()
	_build()
	await get_tree().process_frame
	menu.active = true
	menu.cooldown = 8


func _input(event: InputEvent) -> void:
	if waiting_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k != KEY_ESCAPE and not waiting_pad:
			InputManager.set_key(remap_pid, waiting_action, k)
			Game.save_settings()
		_finish_wait()
	elif waiting_pad and event is InputEventJoypadButton and event.pressed:
		if event.button_index != JOY_BUTTON_START:
			InputManager.set_pad_button(remap_pid, waiting_action, event.button_index)
			Game.save_settings()
		_finish_wait()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("0a0c18"))
	var font: Font = Game.font
	var hint := "%s: select   LEFT/RIGHT: change   %s: back" % [InputManager.prompt("accept"), InputManager.prompt("back")]
	match page:
		"keys":
			hint = "Select an action, then press the new key. ESC cancels."
		"pad":
			hint = "Select an action, then press a controller button. START or ESC cancels. LT always blocks, RT always throws."
		"controls":
			var pads := InputManager.connected_pads()
			var names: Array = []
			for d in pads:
				names.append("%d: %s" % [d, Input.get_joy_name(d)])
			var line := "Connected controllers: " + (", ".join(names) if names.size() > 0 else "none")
			var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string(font, Vector2(320 - lw * 0.5, 334), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.6, 0.9, 0.6))
	var w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(320 - w * 0.5, 348), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.75, 0.75, 0.85))


func _process(_delta: float) -> void:
	queue_redraw()
